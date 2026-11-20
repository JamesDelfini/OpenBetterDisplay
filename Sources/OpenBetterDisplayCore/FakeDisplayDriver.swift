import Foundation

public final class FakeDisplayDriver: DisplayDriver, @unchecked Sendable {
    public var onlineDisplays: [RawDisplayInfo]
    public var brightnessReadings: [UInt32: BrightnessReading]
    public var unsupportedDDCDisplayIDs: Set<UInt32>
    public var enabledHistory: [(displayID: UInt32, enabled: Bool)] = []
    public var mainDisplayHistory: [UInt32] = []
    public var setBrightnessHistory: [(displayID: UInt32, level: Double)] = []
    public var setModeHistory: [(displayID: UInt32, modeID: Int32)] = []
    public var setDisplayModeError: Error?
    public var didResetSoftwareGamma: Bool = false
    public var failingEnableDisplayIDs: Set<UInt32> = []

    private var disconnectedDisplays: [UInt32: RawDisplayInfo] = [:]

    public init(
        onlineDisplays: [RawDisplayInfo] = [],
        brightnessReadings: [UInt32: BrightnessReading] = [:],
        unsupportedDDCDisplayIDs: Set<UInt32> = []
    ) {
        self.onlineDisplays = onlineDisplays
        self.brightnessReadings = brightnessReadings
        self.unsupportedDDCDisplayIDs = unsupportedDDCDisplayIDs
    }

    public func fetchOnlineDisplays() -> [RawDisplayInfo] {
        onlineDisplays
    }

    public func setDisplayEnabled(_ displayID: UInt32, enabled: Bool) throws {
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

    public func setMainDisplay(_ displayID: UInt32) throws {
        mainDisplayHistory.append(displayID)
        for index in onlineDisplays.indices {
            onlineDisplays[index].isMain = (onlineDisplays[index].displayID == displayID)
        }
    }

    public func getBrightness(_ displayID: UInt32) -> BrightnessReading {
        if let reading = brightnessReadings[displayID] {
            if unsupportedDDCDisplayIDs.contains(displayID), reading.backend == .hardwareDDC {
                return BrightnessReading(level: reading.level, backend: .softwareGamma)
            }
            return reading
        }
        let isBuiltIn = onlineDisplays.first(where: { $0.displayID == displayID })?.isBuiltIn ?? false
        let backend: BrightnessBackendUsed
        if isBuiltIn {
            backend = .nativeAppleBacklight
        } else if unsupportedDDCDisplayIDs.contains(displayID) {
            backend = .softwareGamma
        } else {
            backend = .hardwareDDC
        }
        return BrightnessReading(
            level: 1.0,
            backend: backend
        )
    }

    public func setBrightness(_ displayID: UInt32, level: Double) -> BrightnessBackendUsed {
        setBrightnessHistory.append((displayID: displayID, level: level))
        let isBuiltIn = onlineDisplays.first(where: { $0.displayID == displayID })?.isBuiltIn ?? false
        let backend: BrightnessBackendUsed
        if isBuiltIn {
            backend = .nativeAppleBacklight
        } else if unsupportedDDCDisplayIDs.contains(displayID) {
            backend = .softwareGamma
        } else {
            backend = getBrightness(displayID).backend
        }
        brightnessReadings[displayID] = BrightnessReading(level: level, backend: backend)
        return backend
    }

    public func setDisplayMode(_ displayID: UInt32, modeID: Int32) throws {
        setModeHistory.append((displayID: displayID, modeID: modeID))
        if let setDisplayModeError {
            throw setDisplayModeError
        }
        if let index = onlineDisplays.firstIndex(where: { $0.displayID == displayID }) {
            onlineDisplays[index].currentModeID = modeID
        }
    }

    public func resetSoftwareGamma() {
        didResetSoftwareGamma = true
    }
}
