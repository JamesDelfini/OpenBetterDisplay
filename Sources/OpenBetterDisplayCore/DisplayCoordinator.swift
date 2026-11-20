import Foundation
import Combine

@MainActor
public final class DisplayCoordinator: ObservableObject {
    @Published public private(set) var displays: [DisplayState] = []

    private let driver: DisplayDriver
    private var lastKnownRawDisplays: [UInt32: RawDisplayInfo] = [:]
    private var disconnectedDisplays: [UInt32: RawDisplayInfo] = [:]

    public var hasDisconnectedDisplays: Bool {
        displays.contains(where: { !$0.isEnabled })
    }

    public init(driver: DisplayDriver) {
        self.driver = driver
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
              !display.canToggleOff else {
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
            let rawToCache = lastKnownRawDisplays[displayID] ?? RawDisplayInfo(
                displayID: display.displayID,
                name: display.name,
                isBuiltIn: display.isBuiltIn,
                isMain: false,
                isActive: false
            )
            do {
                try driver.setDisplayEnabled(displayID, enabled: false)
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
              !target.isMain else {
            return
        }
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

    /// Lifecycle hook: app is terminating — re-enable all disconnected displays and restore gamma.
    public func handleAppWillTerminate() {
        reconnectAllDisplays()
        driver.resetSoftwareGamma()
    }

    public func refreshDisplays() {
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

        let enabledCount = sorted.filter { raw in
            disconnectedDisplays[raw.displayID] == nil && raw.isActive
        }.count

        displays = sorted.map { raw in
            let isEnabled = disconnectedDisplays[raw.displayID] == nil && raw.isActive
            let isMain = isEnabled && raw.isMain
            let canToggleOff = isEnabled && !isMain && enabledCount > 1
            let availableModes = Self.filterDisplayModes(for: raw)
            let resolvedCurrentModeID = Self.resolveCurrentModeID(for: raw, availableModes: availableModes)

            return DisplayState(
                displayID: raw.displayID,
                name: Self.humanReadableName(for: raw),
                isBuiltIn: raw.isBuiltIn,
                isMain: isMain,
                isEnabled: isEnabled,
                canToggleOff: canToggleOff,
                symbolName: raw.isBuiltIn ? "laptopcomputer" : "display",
                availableModes: availableModes,
                currentModeID: resolvedCurrentModeID
            )
        }
    }

    public func previewResolution(_ displayID: UInt32, modeID: Int32) {
        guard let index = displays.firstIndex(where: { $0.displayID == displayID }),
              displays[index].isEnabled else {
            return
        }
        guard displays[index].availableModes.contains(where: { $0.modeID == modeID }) else {
            return
        }
        displays[index].previewModeID = modeID
    }

    public func previewResolution(_ displayID: UInt32, stepIndex: Int) {
        guard let index = displays.firstIndex(where: { $0.displayID == displayID }),
              displays[index].isEnabled else {
            return
        }
        let modes = displays[index].availableModes
        guard !modes.isEmpty else {
            return
        }
        let clampedIndex = max(0, min(modes.count - 1, stepIndex))
        displays[index].previewModeID = modes[clampedIndex].modeID
    }

    public func commitResolution(_ displayID: UInt32, modeID: Int32? = nil) {
        guard let index = displays.firstIndex(where: { $0.displayID == displayID }),
              displays[index].isEnabled else {
            return
        }
        let targetModeID = modeID ?? displays[index].previewModeID
        displays[index].previewModeID = nil

        guard let targetModeID else {
            return
        }
        if !displays[index].availableModes.isEmpty {
            guard displays[index].availableModes.contains(where: { $0.modeID == targetModeID }) else {
                return
            }
        }
        guard targetModeID != displays[index].currentModeID else {
            return
        }

        do {
            try driver.setDisplayMode(displayID, modeID: targetModeID)
            displays[index].currentModeID = targetModeID
            lastKnownRawDisplays[displayID]?.currentModeID = targetModeID
        } catch {
            // Preserve currentModeID if macOS rejects the display mode switch.
        }
    }

    private static func resolveCurrentModeID(
        for raw: RawDisplayInfo,
        availableModes: [DisplayModeOption]
    ) -> Int32 {
        if availableModes.contains(where: { $0.modeID == raw.currentModeID }) {
            return raw.currentModeID
        }
        if let activeRaw = raw.modes.first(where: { $0.modeID == raw.currentModeID }),
           let matchingOption = availableModes.first(where: {
               $0.width == activeRaw.width && $0.height == activeRaw.height
           }) {
            return matchingOption.modeID
        }
        return availableModes.first(where: { $0.scalePercentage == 100 })?.modeID
            ?? availableModes.last?.modeID
            ?? raw.currentModeID
    }

    private static func filterDisplayModes(for raw: RawDisplayInfo) -> [DisplayModeOption] {
        let usableModes = raw.modes.filter {
            $0.isUsableForDesktopGUI && $0.width > 0 && $0.height > 0 && $0.pixelWidth > 0 && $0.pixelHeight > 0
        }
        guard !usableModes.isEmpty else {
            return []
        }

        let (nativePixelWidth, nativePixelHeight) = resolveNativePixelDimensions(for: raw, usableModes: usableModes)
        let nativeAspect = Double(nativePixelWidth) / Double(nativePixelHeight)

        let aspectMatching = usableModes.filter { mode in
            let aspect = Double(mode.width) / Double(mode.height)
            return abs(aspect - nativeAspect) <= 0.025
        }
        let aspectFiltered = aspectMatching.isEmpty ? usableModes : aspectMatching

        let activeRawMode = raw.modes.first(where: { $0.modeID == raw.currentModeID })
        let candidatePool: [RawDisplayMode]
        if let activeRate = activeRawMode?.refreshRate {
            if activeRate <= 0.5 {
                let variableRateModes = aspectFiltered.filter { $0.refreshRate <= 0.5 }
                if variableRateModes.count >= 2 || variableRateModes.count == aspectFiltered.count {
                    candidatePool = variableRateModes
                } else {
                    candidatePool = aspectFiltered
                }
            } else {
                let matchingRateModes = aspectFiltered.filter { abs($0.refreshRate - activeRate) <= 0.5 }
                candidatePool = matchingRateModes.isEmpty ? aspectFiltered : matchingRateModes
            }
        } else if aspectFiltered.allSatisfy({ $0.refreshRate <= 0.5 }) {
            candidatePool = aspectFiltered
        } else {
            let maxRate = aspectFiltered.map(\.refreshRate).max() ?? 60.0
            let matchingRateModes = aspectFiltered.filter { abs($0.refreshRate - maxRate) <= 0.5 }
            candidatePool = matchingRateModes.isEmpty ? aspectFiltered : matchingRateModes
        }

        let hiDPICandidates = candidatePool.filter { $0.pixelWidth > $0.width }
        let standardCandidates = candidatePool.filter { $0.pixelWidth <= $0.width }
        let isActiveModeHiDPI = activeRawMode.map { $0.pixelWidth > $0.width } ?? false
        let isRetinaOrHighDensityPanel = (raw.isBuiltIn && nativePixelWidth >= 2560)
            || nativePixelWidth >= 3000
            || (isActiveModeHiDPI && hiDPICandidates.count >= 2)

        let preferredModes: [RawDisplayMode]
        if !hiDPICandidates.isEmpty && (isRetinaOrHighDensityPanel || standardCandidates.isEmpty) {
            preferredModes = hiDPICandidates
        } else {
            preferredModes = standardCandidates.isEmpty ? candidatePool : standardCandidates
        }

        var deduplicatedByResolution: [String: RawDisplayMode] = [:]
        for mode in preferredModes {
            let key = "\(mode.width)x\(mode.height)"
            if let existing = deduplicatedByResolution[key] {
                if mode.modeID == raw.currentModeID {
                    deduplicatedByResolution[key] = mode
                } else if existing.modeID != raw.currentModeID {
                    if mode.pixelWidth > existing.pixelWidth
                        || (mode.pixelWidth == existing.pixelWidth && mode.refreshRate > existing.refreshRate) {
                        deduplicatedByResolution[key] = mode
                    }
                }
            } else {
                deduplicatedByResolution[key] = mode
            }
        }

        let sortedModes = deduplicatedByResolution.values.sorted { lhs, rhs in
            let lhsArea = lhs.width * lhs.height
            let rhsArea = rhs.width * rhs.height
            if lhsArea != rhsArea {
                return lhsArea < rhsArea
            }
            return lhs.width < rhs.width
        }

        return sortedModes.map { mode in
            let isHiDPI = mode.pixelWidth > mode.width
            let scalePercentage: Int
            if isHiDPI {
                scalePercentage = Int(((Double(mode.width) * 2.0) / Double(nativePixelWidth) * 100.0).rounded())
            } else {
                scalePercentage = Int(((Double(mode.width) / Double(nativePixelWidth)) * 100.0).rounded())
            }
            let label: String
            if isHiDPI && scalePercentage != 100 {
                label = "\(mode.width)x\(mode.height) · \(scalePercentage)%"
            } else {
                label = "\(mode.width)x\(mode.height)"
            }
            return DisplayModeOption(
                modeID: mode.modeID,
                width: mode.width,
                height: mode.height,
                pixelWidth: mode.pixelWidth,
                pixelHeight: mode.pixelHeight,
                refreshRate: mode.refreshRate,
                isHiDPI: isHiDPI,
                scalePercentage: scalePercentage,
                label: label
            )
        }
    }

    private static func resolveNativePixelDimensions(
        for raw: RawDisplayInfo,
        usableModes: [RawDisplayMode]
    ) -> (Int, Int) {
        let nativeFlaggedModes = usableModes.filter(\.isNative)
        if let native1x = nativeFlaggedModes.first(where: { $0.pixelWidth == $0.width && $0.pixelHeight == $0.height }) {
            return (native1x.pixelWidth, native1x.pixelHeight)
        }
        if let nativeMode = nativeFlaggedModes.first {
            return (nativeMode.pixelWidth, nativeMode.pixelHeight)
        }

        let maxLogicalWidth = usableModes.map(\.width).max() ?? 0
        let oneXModes = usableModes.filter { $0.pixelWidth == $0.width && $0.pixelHeight == $0.height }
        if let active = usableModes.first(where: { $0.modeID == raw.currentModeID }) {
            let activeAspect = Double(active.width) / Double(active.height)
            let matchingActiveAspect1x = oneXModes
                .filter { abs((Double($0.width) / Double($0.height)) - activeAspect) <= 0.025 }
                .max(by: { ($0.width * $0.height) < ($1.width * $1.height) })
            if let matchingActiveAspect1x,
               Double(matchingActiveAspect1x.pixelWidth) >= Double(maxLogicalWidth) * 0.90 {
                return (matchingActiveAspect1x.pixelWidth, matchingActiveAspect1x.pixelHeight)
            }
        }

        if let highest1x = oneXModes.max(by: { ($0.width * $0.height) < ($1.width * $1.height) }),
           highest1x.pixelWidth >= maxLogicalWidth {
            return (highest1x.pixelWidth, highest1x.pixelHeight)
        }

        let twoXModes = usableModes.filter { $0.pixelWidth == $0.width * 2 && $0.pixelWidth >= 2560 }
        if let base2x = twoXModes.min(by: { ($0.pixelWidth * $0.pixelHeight) < ($1.pixelWidth * $1.pixelHeight) }) {
            return (base2x.pixelWidth, base2x.pixelHeight)
        }

        if let highest1x = oneXModes.max(by: { ($0.width * $0.height) < ($1.width * $1.height) }) {
            return (highest1x.pixelWidth, highest1x.pixelHeight)
        }

        if let active = usableModes.first(where: { $0.modeID == raw.currentModeID }) {
            return (active.pixelWidth, active.pixelHeight)
        }

        if let largest = usableModes.max(by: { ($0.pixelWidth * $0.pixelHeight) < ($1.pixelWidth * $1.pixelHeight) }) {
            return (largest.pixelWidth, largest.pixelHeight)
        }

        return (1920, 1080)
    }

    private static func humanReadableName(for raw: RawDisplayInfo) -> String {
        let trimmed = raw.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.isBuiltIn {
            let genericBuiltInNames: Set<String> = [
                "",
                "Color LCD",
                "Built-in Retina Display",
                "Built-in Liquid Retina Display",
                "Built-in Liquid Retina XDR Display",
                "Liquid Retina XDR Display",
                "Liquid Retina Display"
            ]
            if genericBuiltInNames.contains(trimmed) {
                return "Built-in Display"
            }
            return trimmed
        }
        if !trimmed.isEmpty {
            return trimmed
        }
        if raw.vendorID != 0 || raw.modelID != 0 {
            return String(format: "External Display (%04X:%04X)", raw.vendorID, raw.modelID)
        }
        return "External Display"
    }
}
