import Combine
import Foundation

@MainActor
public final class DisplayCoordinator: ObservableObject {
    @Published public private(set) var displays: [DisplayState] = []
    @Published public private(set) var expandedSection: ExpandedPopoverSection? {
        didSet {
            if let managingID = managingFavoritesDisplayID, expandedSection != .displayMode(managingID) {
                managingFavoritesDisplayID = nil
            }
        }
    }
    @Published public private(set) var managingFavoritesDisplayID: UInt32?
    public var onRequestPopoverClose: (@MainActor () -> Void)?

    private struct DDCThrottleState {
        var pendingLevel: Double?
        var scheduledToken: BrightnessWriteCancellable?
        var lastWriteTime: TimeInterval?
        var inFlightLevel: Double?

        var activeTargetLevel: Double? {
            pendingLevel ?? inFlightLevel
        }
    }

    private let driver: DisplayDriver
    private let brightnessStore: BrightnessPersistence
    private let favoriteModesStore: FavoriteModesPersistence
    private let ddcThrottleInterval: TimeInterval
    private let writeScheduler: BrightnessWriteScheduling
    private var lastKnownRawDisplays: [UInt32: RawDisplayInfo] = [:]
    private var disconnectedDisplays: [UInt32: RawDisplayInfo] = [:]
    private var knownEnabledDisplayIDs: Set<UInt32> = []
    private var persistenceKeysByDisplayID: [UInt32: String] = [:]
    private var ddcThrottleStates: [UInt32: DDCThrottleState] = [:]

    public var hasDisconnectedDisplays: Bool {
        displays.contains(where: { !$0.isEnabled })
    }

    public init(
        driver: DisplayDriver,
        brightnessStore: BrightnessPersistence = UserDefaultsBrightnessStore(),
        favoriteModesStore: FavoriteModesPersistence = UserDefaultsFavoriteModesStore(),
        ddcThrottleInterval: TimeInterval = 0.06,
        writeScheduler: BrightnessWriteScheduling? = nil
    ) {
        self.driver = driver
        self.brightnessStore = brightnessStore
        self.favoriteModesStore = favoriteModesStore
        self.ddcThrottleInterval = max(0, ddcThrottleInterval)
        self.writeScheduler = writeScheduler ?? MainQueueBrightnessWriteScheduler()
        refreshDisplays()
    }

    public func canToggleOff(_ displayID: UInt32) -> Bool {
        guard let display = displays.first(where: { $0.displayID == displayID }) else {
            return false
        }
        return display.canToggleOff
    }

    public func toggleLockReason(for displayID: UInt32) -> DisplayToggleLockReason? {
        guard let display = displays.first(where: { $0.displayID == displayID }),
            display.isEnabled,
            !display.canToggleOff
        else {
            return nil
        }
        let activeCount = displays.filter(\.isEnabled).count
        if activeCount <= 1 {
            return .lastActiveDisplay
        }
        if display.isMain {
            return .mainDisplay
        }
        return nil
    }

    public func toggleDisplayEnabled(_ displayID: UInt32) {
        guard let display = displays.first(where: { $0.displayID == displayID }) else {
            return
        }
        setDisplayEnabled(displayID, enabled: !display.isEnabled)
    }

    public func toggleExpandedSection(_ section: ExpandedPopoverSection) {
        if expandedSection == section {
            expandedSection = nil
            return
        }
        if let displayID = section.displayID {
            guard let display = displays.first(where: { $0.displayID == displayID }),
                display.isEnabled
            else {
                return
            }
        }
        expandedSection = section
    }

    public func handlePopoverDidClose() {
        expandedSection = nil
    }

    public func toggleManageFavorites(for displayID: UInt32) {
        guard let display = displays.first(where: { $0.displayID == displayID }),
            display.isEnabled
        else {
            return
        }
        if managingFavoritesDisplayID == displayID {
            managingFavoritesDisplayID = nil
            return
        }
        expandedSection = .displayMode(displayID)
        managingFavoritesDisplayID = displayID
    }

    public func setDisplayEnabled(_ displayID: UInt32, enabled: Bool) {
        guard let display = displays.first(where: { $0.displayID == displayID }) else {
            return
        }

        if enabled {
            guard !display.isEnabled else { return }
            do {
                try driver.setDisplayEnabled(displayID, enabled: true)
                disconnectedDisplays.removeValue(forKey: displayID)
                refreshDisplays()
            } catch {
                return
            }
        } else {
            guard display.isEnabled, canToggleOff(displayID) else { return }
            let rawToCache =
                lastKnownRawDisplays[displayID]
                ?? RawDisplayInfo(
                    displayID: display.displayID,
                    name: display.name,
                    isBuiltIn: display.isBuiltIn,
                    isMain: false,
                    isActive: false
                )
            do {
                try driver.setDisplayEnabled(displayID, enabled: false)
                resetDDCThrottleState(for: displayID)
                var cached = rawToCache
                cached.isActive = false
                cached.isMain = false
                disconnectedDisplays[displayID] = cached
                refreshDisplays()
            } catch {
                return
            }
        }
    }

    public func handleDisplayReconfiguration() {
        refreshDisplays()
    }

    public func setMainDisplay(_ displayID: UInt32) {
        guard let target = displays.first(where: { $0.displayID == displayID }),
            target.isEnabled,
            !target.isMain
        else {
            return
        }
        expandedSection = nil
        onRequestPopoverClose?()
        do {
            try driver.setMainDisplay(displayID)
            for id in disconnectedDisplays.keys {
                disconnectedDisplays[id]?.isMain = false
            }
            refreshDisplays()
        } catch {
            return
        }
    }

    public func reconnectAllDisplays() {
        let disabledIDs = Set(displays.filter { !$0.isEnabled }.map(\.displayID))
            .union(disconnectedDisplays.keys)
            .sorted()
        guard !disabledIDs.isEmpty else { return }

        for id in disabledIDs {
            do {
                try driver.setDisplayEnabled(id, enabled: true)
                disconnectedDisplays.removeValue(forKey: id)
            } catch {
                continue
            }
        }
        refreshDisplays()
    }

    /// Lifecycle hook: the Mac woke from sleep — bring every turned-off display back.
    public func handleSystemWake() {
        reconnectAllDisplays()
    }

    /// Lifecycle hook: app is terminating — cancel pending DDC writes, re-enable all disconnected displays, and restore gamma.
    public func handleAppWillTerminate() {
        cancelAllPendingDDCWrites()
        reconnectAllDisplays()
        cancelAllPendingDDCWrites()
        driver.resetSoftwareGamma()
    }

    public func refreshDisplays() {
        let previousDisplaysByID = Dictionary(uniqueKeysWithValues: displays.map { ($0.displayID, $0) })
        let online = driver.fetchOnlineDisplays()
        var mergedByID: [UInt32: RawDisplayInfo] = [:]

        for raw in online {
            if raw.isActive || lastKnownRawDisplays[raw.displayID] == nil {
                lastKnownRawDisplays[raw.displayID] = raw
            }
            if let existingCached = disconnectedDisplays[raw.displayID] {
                if raw.isActive {
                    disconnectedDisplays.removeValue(forKey: raw.displayID)
                    mergedByID[raw.displayID] = raw
                } else {
                    mergedByID[raw.displayID] = existingCached
                }
            } else {
                mergedByID[raw.displayID] = raw
            }
        }

        for (id, cachedRaw) in disconnectedDisplays where mergedByID[id] == nil {
            mergedByID[id] = cachedRaw
        }

        let sorted = mergedByID.values.sorted { lhs, rhs in
            if lhs.isBuiltIn != rhs.isBuiltIn {
                return lhs.isBuiltIn && !rhs.isBuiltIn
            }
            return lhs.displayID < rhs.displayID
        }

        let currentEnabledIDs = Set(
            sorted.compactMap { raw -> UInt32? in
                let isEnabled = disconnectedDisplays[raw.displayID] == nil && raw.isActive
                return isEnabled ? raw.displayID : nil
            })
        let removedEnabledIDs = knownEnabledDisplayIDs.subtracting(currentEnabledIDs)
        for removedID in removedEnabledIDs {
            resetDDCThrottleState(for: removedID)
        }

        let enabledCount = currentEnabledIDs.count
        var updatedKeys: [UInt32: String] = [:]

        displays = sorted.map { raw in
            let isEnabled = currentEnabledIDs.contains(raw.displayID)
            let isMain = isEnabled && raw.isMain
            let canToggleOff = isEnabled && !isMain && enabledCount > 1
            let availableModes = DisplayModeFilter.filterModes(for: raw)
            let defaultMode = DisplayModeFilter.resolveDefaultMode(for: raw, availableModes: availableModes)
            let nativeMode = DisplayModeFilter.resolveNativeMode(for: raw, availableModes: availableModes)
            let currentModeOption = DisplayModeFilter.resolveCurrentModeOption(for: raw, availableModes: availableModes)

            let persistenceKey = Self.persistenceKey(for: raw)
            updatedKeys[raw.displayID] = persistenceKey
            let savedFavoriteRecords = favoriteModesStore.favoriteModes(forKey: persistenceKey)
            let favoriteModes = DisplayModeFilter.resolveFavoriteModes(
                from: savedFavoriteRecords,
                availableModes: availableModes
            )

            let (brightness, backend) = resolveBrightnessState(
                for: raw,
                isEnabled: isEnabled,
                persistenceKey: persistenceKey,
                previousDisplay: previousDisplaysByID[raw.displayID]
            )

            return DisplayState(
                displayID: raw.displayID,
                name: DisplayNameFormatter.format(
                    rawName: raw.name,
                    isBuiltIn: raw.isBuiltIn,
                    vendorID: raw.vendorID,
                    modelID: raw.modelID
                ),
                isBuiltIn: raw.isBuiltIn,
                isMain: isMain,
                isEnabled: isEnabled,
                canToggleOff: canToggleOff,
                brightness: brightness,
                brightnessBackend: backend,
                availableModes: availableModes,
                defaultMode: defaultMode,
                nativeMode: nativeMode,
                favoriteModes: favoriteModes,
                currentModeID: raw.currentModeID,
                currentModeOption: currentModeOption
            )
        }

        persistenceKeysByDisplayID = updatedKeys
        knownEnabledDisplayIDs = currentEnabledIDs

        if let expandedDisplayID = expandedSection?.displayID, !currentEnabledIDs.contains(expandedDisplayID) {
            expandedSection = nil
        }
    }

    /// Lightweight sync for built-in displays while the popover is visible,
    /// reflecting macOS brightness-key / Control Center changes without polling external DDC monitors.
    public func syncBuiltInBrightness() {
        for index in displays.indices where displays[index].isBuiltIn && displays[index].isEnabled {
            let displayID = displays[index].displayID
            let reading = driver.getBrightness(displayID)
            let clamped = max(0.0, min(1.0, reading.level))
            if abs(clamped - displays[index].brightness) > 0.001 {
                displays[index].brightness = clamped
                if let persistenceKey = persistenceKeysByDisplayID[displayID] {
                    brightnessStore.setBrightness(clamped, forKey: persistenceKey)
                }
            }
            if displays[index].brightnessBackend != reading.backend {
                displays[index].brightnessBackend = reading.backend
            }
        }
    }

    public func setBrightness(_ displayID: UInt32, level: Double) {
        let clamped = max(0.0, min(1.0, level))

        guard let index = displays.firstIndex(where: { $0.displayID == displayID }) else {
            return
        }
        guard displays[index].isEnabled else {
            return
        }

        if let persistenceKey = persistenceKeysByDisplayID[displayID] {
            brightnessStore.setBrightness(clamped, forKey: persistenceKey)
        }

        displays[index].brightness = clamped

        if displays[index].brightnessBackend == .hardwareDDC, ddcThrottleInterval > 0 {
            var state = ddcThrottleStates[displayID] ?? DDCThrottleState()
            state.pendingLevel = clamped
            ddcThrottleStates[displayID] = state
            scheduleOrFlushDDCWrite(for: displayID)
        } else {
            cancelPendingDDCWrite(for: displayID)
            let backend = driver.setBrightness(displayID, level: clamped)
            displays[index].brightnessBackend = backend
        }
    }

    public func selectDisplayMode(_ displayID: UInt32, modeID: Int32) {
        guard let index = displays.firstIndex(where: { $0.displayID == displayID }),
            displays[index].isEnabled
        else {
            return
        }

        let display = displays[index]
        let knownTargetOption = resolveKnownModeOption(for: display, modeID: modeID)
        if !display.availableModes.isEmpty, knownTargetOption == nil {
            return
        }

        guard modeID != display.currentModeID else {
            return
        }

        do {
            try driver.setDisplayMode(displayID, modeID: modeID)
            displays[index].currentModeID = modeID
            displays[index].currentModeOption = resolveSelectedModeOption(
                for: display,
                modeID: modeID,
                knownOption: knownTargetOption,
                raw: lastKnownRawDisplays[displayID]
            )
            lastKnownRawDisplays[displayID]?.currentModeID = modeID
        } catch {
            // Preserve currentModeID and currentModeOption if macOS rejects the display mode switch.
        }
    }

    public func assignCurrentModeToFavorite(_ displayID: UInt32, slot: Int) {
        guard let display = displays.first(where: { $0.displayID == displayID }),
            display.isEnabled,
            let currentMode = display.currentModeOption
        else {
            return
        }
        assignFavoriteModeOption(currentMode, for: displayID, slot: slot)
    }

    public func assignFavoriteMode(_ displayID: UInt32, modeID: Int32, slot: Int) {
        guard let display = displays.first(where: { $0.displayID == displayID }),
            display.isEnabled,
            let modeOption = resolveKnownModeOption(for: display, modeID: modeID)
                ?? (display.currentModeOption?.modeID == modeID ? display.currentModeOption : nil)
        else {
            return
        }
        assignFavoriteModeOption(modeOption, for: displayID, slot: slot)
    }

    public func clearFavoriteMode(_ displayID: UInt32, slot: Int) {
        guard UserDefaultsFavoriteModesStore.validSlotRange.contains(slot) else {
            return
        }
        updateFavoriteSlots(for: displayID) { slots, _ in
            slots.removeValue(forKey: slot)
        }
    }

    public func removeModeFromFavorites(_ displayID: UInt32, modeID: Int32) {
        updateFavoriteSlots(for: displayID) { slots, display in
            let matchingSlots = display.favoriteModes.filter { $0.matches(modeID: modeID) }.map(\.slot)
            for slot in matchingSlots {
                slots.removeValue(forKey: slot)
            }
        }
    }

    public func selectFavoriteMode(_ displayID: UInt32, slot: Int) {
        guard UserDefaultsFavoriteModesStore.validSlotRange.contains(slot),
            let display = displays.first(where: { $0.displayID == displayID }),
            display.isEnabled,
            let resolvedMode = display.favoriteMode(forSlot: slot)?.resolvedMode
        else {
            return
        }
        selectDisplayMode(displayID, modeID: resolvedMode.modeID)
    }

    private func assignFavoriteModeOption(_ modeOption: DisplayModeOption, for displayID: UInt32, slot: Int) {
        guard UserDefaultsFavoriteModesStore.validSlotRange.contains(slot) else {
            return
        }
        updateFavoriteSlots(for: displayID) { slots, _ in
            slots[slot] = FavoriteModeRecord(mode: modeOption)
        }
    }

    private func updateFavoriteSlots(
        for displayID: UInt32,
        mutate: (inout [Int: FavoriteModeRecord], DisplayState) -> Void
    ) {
        guard let index = displays.firstIndex(where: { $0.displayID == displayID }),
            displays[index].isEnabled,
            let persistenceKey = persistenceKeysByDisplayID[displayID]
        else {
            return
        }

        var slots = favoriteModesStore.favoriteModes(forKey: persistenceKey)
        mutate(&slots, displays[index])
        favoriteModesStore.setFavoriteModes(slots, forKey: persistenceKey)
        displays[index].favoriteModes = DisplayModeFilter.resolveFavoriteModes(
            from: slots,
            availableModes: displays[index].availableModes
        )
    }

    private func resolveKnownModeOption(for display: DisplayState, modeID: Int32) -> DisplayModeOption? {
        if let option = display.availableModes.first(where: { $0.modeID == modeID }) {
            return option
        }
        if display.defaultMode?.modeID == modeID {
            return display.defaultMode
        }
        if display.nativeMode?.modeID == modeID {
            return display.nativeMode
        }
        return nil
    }

    private func resolveSelectedModeOption(
        for display: DisplayState,
        modeID: Int32,
        knownOption: DisplayModeOption?,
        raw: RawDisplayInfo?
    ) -> DisplayModeOption? {
        if let knownOption {
            return knownOption
        }
        if let rawMode = raw?.modes.first(where: { $0.modeID == modeID }) {
            return DisplayModeFilter.makeModeOption(mode: rawMode)
        }
        return display.currentModeOption
    }

    // MARK: - Private Brightness Helpers

    private func resolveBrightnessState(
        for raw: RawDisplayInfo,
        isEnabled: Bool,
        persistenceKey: String,
        previousDisplay: DisplayState?
    ) -> (Double, BrightnessBackendUsed) {
        if !isEnabled {
            if let previousDisplay {
                return (previousDisplay.brightness, previousDisplay.brightnessBackend)
            }
            if let savedLevel = brightnessStore.brightness(forKey: persistenceKey) {
                return (max(0.0, min(1.0, savedLevel)), raw.isBuiltIn ? .nativeAppleBacklight : .hardwareDDC)
            }
            return (1.0, raw.isBuiltIn ? .nativeAppleBacklight : .hardwareDDC)
        }

        if raw.isBuiltIn {
            let reading = driver.getBrightness(raw.displayID)
            let level = max(0.0, min(1.0, reading.level))
            let previousLevel = previousDisplay?.brightness
            let persistedLevel = brightnessStore.brightness(forKey: persistenceKey)
            let changedFromPrevious = previousLevel.map { abs($0 - level) > 0.001 } ?? false
            let differsFromPersisted = persistedLevel.map { abs($0 - level) > 0.001 } ?? false
            if changedFromPrevious || differsFromPersisted {
                brightnessStore.setBrightness(level, forKey: persistenceKey)
            }
            return (level, reading.backend)
        }

        if let activeDDCLevel = ddcThrottleStates[raw.displayID]?.activeTargetLevel {
            return (activeDDCLevel, .hardwareDDC)
        }

        if !knownEnabledDisplayIDs.contains(raw.displayID),
            let savedLevel = brightnessStore.brightness(forKey: persistenceKey)
        {
            let clampedSaved = max(0.0, min(1.0, savedLevel))
            let backend = driver.setBrightness(raw.displayID, level: clampedSaved)
            return (clampedSaved, backend)
        }

        let reading = driver.getBrightness(raw.displayID)
        return (max(0.0, min(1.0, reading.level)), reading.backend)
    }

    private func scheduleOrFlushDDCWrite(for displayID: UInt32) {
        var state = ddcThrottleStates[displayID] ?? DDCThrottleState()
        guard state.inFlightLevel == nil else { return }

        let now = writeScheduler.now()
        if let lastWrite = state.lastWriteTime {
            let elapsed = now - lastWrite
            if elapsed < ddcThrottleInterval {
                if state.scheduledToken == nil {
                    let remaining = ddcThrottleInterval - elapsed
                    state.scheduledToken = writeScheduler.schedule(after: remaining) { [weak self] in
                        guard let self else { return }
                        self.ddcThrottleStates[displayID]?.scheduledToken = nil
                        self.flushDDCWrite(for: displayID)
                    }
                    ddcThrottleStates[displayID] = state
                }
                return
            }
        }

        if let token = state.scheduledToken {
            token.cancel()
            state.scheduledToken = nil
            ddcThrottleStates[displayID] = state
        }
        flushDDCWrite(for: displayID)
    }

    private func flushDDCWrite(for displayID: UInt32) {
        guard var state = ddcThrottleStates[displayID],
            let targetLevel = state.pendingLevel
        else {
            return
        }
        state.pendingLevel = nil
        guard knownEnabledDisplayIDs.contains(displayID) else {
            ddcThrottleStates[displayID] = state
            return
        }

        state.inFlightLevel = targetLevel
        state.lastWriteTime = writeScheduler.now()
        ddcThrottleStates[displayID] = state

        let driver = self.driver
        writeScheduler.performWrite(
            {
                driver.setBrightness(displayID, level: targetLevel)
            },
            completion: { [weak self] backend in
                guard let self else { return }
                self.ddcThrottleStates[displayID]?.inFlightLevel = nil

                if let index = self.displays.firstIndex(where: { $0.displayID == displayID }) {
                    self.displays[index].brightnessBackend = backend
                }

                if self.ddcThrottleStates[displayID]?.pendingLevel != nil {
                    if backend == .hardwareDDC, self.ddcThrottleInterval > 0 {
                        self.scheduleOrFlushDDCWrite(for: displayID)
                    } else if let trailingLevel = self.ddcThrottleStates[displayID]?.pendingLevel {
                        self.ddcThrottleStates[displayID]?.pendingLevel = nil
                        let nextBackend = self.driver.setBrightness(displayID, level: trailingLevel)
                        if let index = self.displays.firstIndex(where: { $0.displayID == displayID }) {
                            self.displays[index].brightnessBackend = nextBackend
                        }
                    }
                }
            }
        )
    }

    private func cancelPendingDDCWrite(for displayID: UInt32) {
        guard var state = ddcThrottleStates[displayID] else { return }
        state.pendingLevel = nil
        state.scheduledToken?.cancel()
        state.scheduledToken = nil
        ddcThrottleStates[displayID] = state
    }

    private func resetDDCThrottleState(for displayID: UInt32) {
        ddcThrottleStates[displayID]?.scheduledToken?.cancel()
        ddcThrottleStates.removeValue(forKey: displayID)
    }

    private func cancelAllPendingDDCWrites() {
        for displayID in ddcThrottleStates.keys {
            cancelPendingDDCWrite(for: displayID)
        }
    }

    private static func persistenceKey(for raw: RawDisplayInfo) -> String {
        if raw.isBuiltIn {
            return "builtin"
        }
        if raw.serialNumber != 0 {
            return String(format: "hardware:%04X:%04X:%08X", raw.vendorID, raw.modelID, raw.serialNumber)
        }
        if raw.vendorID != 0 || raw.modelID != 0 {
            return String(format: "display:%04X:%04X:%u", raw.vendorID, raw.modelID, raw.displayID)
        }
        return "display:\(raw.displayID)"
    }
}
