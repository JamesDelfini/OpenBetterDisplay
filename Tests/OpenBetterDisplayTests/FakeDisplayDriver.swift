import Foundation
import OpenBetterDisplayCore

final class FakeDisplayDriver: DisplayDriver, @unchecked Sendable {
    var onlineDisplays: [RawDisplayInfo]
    var brightnessReadings: [UInt32: BrightnessReading]
    var unsupportedDDCDisplayIDs: Set<UInt32>
    var enabledHistory: [(displayID: UInt32, enabled: Bool)] = []
    var mainDisplayHistory: [UInt32] = []
    var getBrightnessHistory: [UInt32] = []
    var setBrightnessHistory: [(displayID: UInt32, level: Double)] = []
    var setModeHistory: [(displayID: UInt32, modeID: Int32)] = []
    var setDisplayModeError: Error?
    var didResetSoftwareGamma: Bool = false
    var failingEnableDisplayIDs: Set<UInt32> = []

    private var disconnectedDisplays: [UInt32: RawDisplayInfo] = [:]

    init(
        onlineDisplays: [RawDisplayInfo] = [],
        brightnessReadings: [UInt32: BrightnessReading] = [:],
        unsupportedDDCDisplayIDs: Set<UInt32> = []
    ) {
        self.onlineDisplays = onlineDisplays
        self.brightnessReadings = brightnessReadings
        self.unsupportedDDCDisplayIDs = unsupportedDDCDisplayIDs
    }

    func fetchOnlineDisplays() -> [RawDisplayInfo] {
        onlineDisplays
    }

    func setDisplayEnabled(_ displayID: UInt32, enabled: Bool) throws {
        enabledHistory.append((displayID: displayID, enabled: enabled))
        if failingEnableDisplayIDs.contains(displayID) {
            throw DisplayDriverError.configurationFailed(-1)
        }
        if enabled {
            if var restored = disconnectedDisplays.removeValue(forKey: displayID) {
                restored.isActive = true
                if onlineDisplays.contains(where: \.isMain) {
                    restored.isMain = false
                }
                if !onlineDisplays.contains(where: { $0.displayID == displayID }) {
                    onlineDisplays.append(restored)
                }
            } else if let index = onlineDisplays.firstIndex(where: { $0.displayID == displayID }) {
                onlineDisplays[index].isActive = true
            }
        } else {
            if let index = onlineDisplays.firstIndex(where: { $0.displayID == displayID }) {
                var removed = onlineDisplays.remove(at: index)
                removed.isActive = false
                removed.isMain = false
                disconnectedDisplays[displayID] = removed
            }
        }
    }

    func setMainDisplay(_ displayID: UInt32) throws {
        mainDisplayHistory.append(displayID)
        for index in onlineDisplays.indices {
            onlineDisplays[index].isMain = (onlineDisplays[index].displayID == displayID)
        }
    }

    func getBrightness(_ displayID: UInt32) -> BrightnessReading {
        getBrightnessHistory.append(displayID)
        let backend = resolveBackend(for: displayID)
        let level = brightnessReadings[displayID]?.level ?? 1.0
        return BrightnessReading(level: level, backend: backend)
    }

    func setBrightness(_ displayID: UInt32, level: Double) -> BrightnessBackendUsed {
        setBrightnessHistory.append((displayID: displayID, level: level))
        let backend = resolveBackend(for: displayID)
        brightnessReadings[displayID] = BrightnessReading(level: level, backend: backend)
        return backend
    }

    func setDisplayMode(_ displayID: UInt32, modeID: Int32) throws {
        setModeHistory.append((displayID: displayID, modeID: modeID))
        if let setDisplayModeError {
            throw setDisplayModeError
        }
        if let index = onlineDisplays.firstIndex(where: { $0.displayID == displayID }) {
            onlineDisplays[index].currentModeID = modeID
        }
    }

    func resetSoftwareGamma() {
        didResetSoftwareGamma = true
    }

    private func resolveBackend(for displayID: UInt32) -> BrightnessBackendUsed {
        if let existing = brightnessReadings[displayID] {
            if unsupportedDDCDisplayIDs.contains(displayID), existing.backend == .hardwareDDC {
                return .softwareGamma
            }
            return existing.backend
        }
        let isBuiltIn = onlineDisplays.first(where: { $0.displayID == displayID })?.isBuiltIn ?? false
        if isBuiltIn {
            return .nativeAppleBacklight
        }
        return unsupportedDDCDisplayIDs.contains(displayID) ? .softwareGamma : .hardwareDDC
    }
}

final class InMemoryBrightnessStore: BrightnessPersistence, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Double]

    init(initialValues: [String: Double] = [:]) {
        self.values = initialValues.mapValues { max(0.0, min(1.0, $0)) }
    }

    func brightness(forKey key: String) -> Double? {
        lock.lock()
        defer { lock.unlock() }
        return values[key]
    }

    func setBrightness(_ level: Double, forKey key: String) {
        let clamped = max(0.0, min(1.0, level))
        lock.lock()
        defer { lock.unlock() }
        values[key] = clamped
    }
}

final class InMemoryFavoriteModesStore: FavoriteModesPersistence, @unchecked Sendable {
    private let lock = NSLock()
    private var slotsByKey: [String: [Int: FavoriteModeRecord]]

    init(initialSlotsByKey: [String: [Int: FavoriteModeRecord]] = [:]) {
        self.slotsByKey = initialSlotsByKey
    }

    func favoriteModes(forKey key: String) -> [Int: FavoriteModeRecord] {
        lock.lock()
        defer { lock.unlock() }
        return slotsByKey[key] ?? [:]
    }

    func setFavoriteModes(_ slots: [Int: FavoriteModeRecord], forKey key: String) {
        lock.lock()
        defer { lock.unlock() }
        let filtered = slots.filter { (1...5).contains($0.key) }
        if filtered.isEmpty {
            slotsByKey.removeValue(forKey: key)
        } else {
            slotsByKey[key] = filtered
        }
    }
}

@MainActor
final class ImmediateBrightnessWriteScheduler: BrightnessWriteScheduling {
    private final class NoOpToken: BrightnessWriteCancellable {
        func cancel() {}
    }

    init() {}

    func now() -> TimeInterval {
        0
    }

    func schedule(
        after delay: TimeInterval,
        action: @escaping @MainActor () -> Void
    ) -> BrightnessWriteCancellable {
        action()
        return NoOpToken()
    }

    func performWrite(
        _ work: @escaping @Sendable () -> BrightnessBackendUsed,
        completion: @escaping @MainActor (BrightnessBackendUsed) -> Void
    ) {
        completion(work())
    }
}
