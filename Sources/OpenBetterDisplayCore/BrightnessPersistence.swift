import Foundation

public protocol BrightnessPersistence: Sendable {
    func brightness(forKey key: String) -> Double?
    func setBrightness(_ level: Double, forKey key: String)
}

public final class UserDefaultsBrightnessStore: BrightnessPersistence, @unchecked Sendable {
    private let userDefaults: UserDefaults
    private let keyPrefix: String

    public init(
        userDefaults: UserDefaults = .standard,
        keyPrefix: String = "OpenBetterDisplay.brightness."
    ) {
        self.userDefaults = userDefaults
        self.keyPrefix = keyPrefix
    }

    public func brightness(forKey key: String) -> Double? {
        guard let number = userDefaults.object(forKey: storageKey(for: key)) as? NSNumber else {
            return nil
        }
        return max(0.0, min(1.0, number.doubleValue))
    }

    public func setBrightness(_ level: Double, forKey key: String) {
        let clamped = max(0.0, min(1.0, level))
        userDefaults.set(clamped, forKey: storageKey(for: key))
    }

    private func storageKey(for key: String) -> String {
        keyPrefix + key
    }
}
