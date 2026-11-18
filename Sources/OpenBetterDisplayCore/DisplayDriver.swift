import Foundation

public protocol DisplayDriver: Sendable {
    func fetchOnlineDisplays() -> [RawDisplayInfo]
    func setDisplayEnabled(_ displayID: UInt32, enabled: Bool) throws
    func setMainDisplay(_ displayID: UInt32) throws
    func getBrightness(_ displayID: UInt32) -> BrightnessReading
    func setBrightness(_ displayID: UInt32, level: Double) -> BrightnessBackendUsed
    func setDisplayMode(_ displayID: UInt32, modeID: Int32) throws
    func resetSoftwareGamma()
}
