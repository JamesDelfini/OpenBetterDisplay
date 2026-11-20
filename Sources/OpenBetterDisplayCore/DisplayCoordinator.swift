import Foundation
import Combine

@MainActor
public final class DisplayCoordinator: ObservableObject {
    @Published public private(set) var displays: [DisplayState] = []

    private let driver: DisplayDriver
    private let brightnessStore: BrightnessPersistence
    private let ddcThrottleInterval: TimeInterval
    private let writeScheduler: BrightnessWriteScheduling
    private var knownOnlineDisplayIDs: Set<UInt32> = []
    private var persistenceKeysByDisplayID: [UInt32: String] = [:]
    private var pendingDDCLevels: [UInt32: Double] = [:]
    private var scheduledDDCTokens: [UInt32: AnyObject] = [:]
    private var lastDDCWriteTime: [UInt32: TimeInterval] = [:]
    private var inFlightDDCLevels: [UInt32: Double] = [:]

    public init(
        driver: DisplayDriver,
        brightnessStore: BrightnessPersistence = UserDefaultsBrightnessStore(),
        ddcThrottleInterval: TimeInterval = 0.06,
        writeScheduler: BrightnessWriteScheduling? = nil
    ) {
        self.driver = driver
        self.brightnessStore = brightnessStore
        self.ddcThrottleInterval = max(0, ddcThrottleInterval)
        self.writeScheduler = writeScheduler ?? MainQueueBrightnessWriteScheduler()
        refreshDisplays()
    }

    public func handleDisplayReconfiguration() {
        refreshDisplays()
    }

    public func refreshDisplays() {
        let online = driver.fetchOnlineDisplays()
        let sorted = online.sorted { lhs, rhs in
            if lhs.isBuiltIn != rhs.isBuiltIn {
                return lhs.isBuiltIn && !rhs.isBuiltIn
            }
            return lhs.displayID < rhs.displayID
        }

        let currentOnlineIDs = Set(sorted.map(\.displayID))
        let removedDisplayIDs = knownOnlineDisplayIDs.subtracting(currentOnlineIDs)
        for removedID in removedDisplayIDs {
            cancelPendingDDCWrite(for: removedID)
            lastDDCWriteTime.removeValue(forKey: removedID)
        }

        var updatedKeys: [UInt32: String] = [:]

        displays = sorted.map { raw in
            let persistenceKey = Self.persistenceKey(for: raw)
            updatedKeys[raw.displayID] = persistenceKey

            let isNewlyDiscovered = !knownOnlineDisplayIDs.contains(raw.displayID)
            let brightness: Double
            let backend: BrightnessBackendUsed

            if let activeDDCLevel = pendingDDCLevels[raw.displayID] ?? inFlightDDCLevels[raw.displayID] {
                brightness = activeDDCLevel
                backend = .hardwareDDC
            } else if isNewlyDiscovered, let savedLevel = brightnessStore.brightness(forKey: persistenceKey) {
                let clampedSaved = max(0.0, min(1.0, savedLevel))
                backend = driver.setBrightness(raw.displayID, level: clampedSaved)
                brightness = clampedSaved
            } else {
                let reading = driver.getBrightness(raw.displayID)
                brightness = max(0.0, min(1.0, reading.level))
                backend = reading.backend
            }

            return DisplayState(
                displayID: raw.displayID,
                name: Self.humanReadableName(for: raw),
                isBuiltIn: raw.isBuiltIn,
                isMain: raw.isMain,
                symbolName: raw.isBuiltIn ? "laptopcomputer" : "display",
                brightness: brightness,
                brightnessBackend: backend
            )
        }

        persistenceKeysByDisplayID = updatedKeys
        knownOnlineDisplayIDs = currentOnlineIDs
    }

    public func setBrightness(_ displayID: UInt32, level: Double) {
        let clamped = max(0.0, min(1.0, level))
        if let persistenceKey = persistenceKeysByDisplayID[displayID] {
            brightnessStore.setBrightness(clamped, forKey: persistenceKey)
        }

        guard let index = displays.firstIndex(where: { $0.displayID == displayID }) else {
            _ = driver.setBrightness(displayID, level: clamped)
            return
        }

        displays[index].brightness = clamped

        if displays[index].brightnessBackend == .hardwareDDC, ddcThrottleInterval > 0 {
            pendingDDCLevels[displayID] = clamped
            scheduleOrFlushDDCWrite(for: displayID)
        } else {
            cancelPendingDDCWrite(for: displayID)
            let backend = driver.setBrightness(displayID, level: clamped)
            displays[index].brightnessBackend = backend
        }
    }

    public func handleAppWillTerminate() {
        cancelAllPendingDDCWrites()
        driver.resetSoftwareGamma()
    }

    private func scheduleOrFlushDDCWrite(for displayID: UInt32) {
        guard inFlightDDCLevels[displayID] == nil else { return }

        let now = writeScheduler.now()
        if let lastWrite = lastDDCWriteTime[displayID] {
            let elapsed = now - lastWrite
            if elapsed < ddcThrottleInterval {
                if scheduledDDCTokens[displayID] == nil {
                    let remaining = ddcThrottleInterval - elapsed
                    let token = writeScheduler.schedule(after: remaining) { [weak self] in
                        guard let self else { return }
                        self.scheduledDDCTokens.removeValue(forKey: displayID)
                        self.flushDDCWrite(for: displayID)
                    }
                    scheduledDDCTokens[displayID] = token
                }
                return
            }
        }

        if let token = scheduledDDCTokens.removeValue(forKey: displayID) {
            writeScheduler.cancel(token)
        }
        flushDDCWrite(for: displayID)
    }

    private func flushDDCWrite(for displayID: UInt32) {
        guard let targetLevel = pendingDDCLevels.removeValue(forKey: displayID) else { return }
        guard knownOnlineDisplayIDs.contains(displayID) else { return }

        inFlightDDCLevels[displayID] = targetLevel
        lastDDCWriteTime[displayID] = writeScheduler.now()

        let driver = self.driver
        writeScheduler.performWrite({
            driver.setBrightness(displayID, level: targetLevel)
        }) { [weak self] backend in
            guard let self else { return }
            self.inFlightDDCLevels.removeValue(forKey: displayID)

            if let index = self.displays.firstIndex(where: { $0.displayID == displayID }) {
                self.displays[index].brightnessBackend = backend
            }

            if self.pendingDDCLevels[displayID] != nil {
                if backend == .hardwareDDC, self.ddcThrottleInterval > 0 {
                    self.scheduleOrFlushDDCWrite(for: displayID)
                } else if let trailingLevel = self.pendingDDCLevels.removeValue(forKey: displayID) {
                    let nextBackend = self.driver.setBrightness(displayID, level: trailingLevel)
                    if let index = self.displays.firstIndex(where: { $0.displayID == displayID }) {
                        self.displays[index].brightnessBackend = nextBackend
                    }
                }
            }
        }
    }

    private func cancelPendingDDCWrite(for displayID: UInt32) {
        pendingDDCLevels.removeValue(forKey: displayID)
        if let token = scheduledDDCTokens.removeValue(forKey: displayID) {
            writeScheduler.cancel(token)
        }
    }

    private func cancelAllPendingDDCWrites() {
        for token in scheduledDDCTokens.values {
            writeScheduler.cancel(token)
        }
        scheduledDDCTokens.removeAll()
        pendingDDCLevels.removeAll()
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
