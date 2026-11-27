import Foundation

public protocol DisplayModeFilterPersistence: Sendable {
    func modeFilter(forKey key: String) -> DisplayModeFilterCriteria?
    func setModeFilter(_ filter: DisplayModeFilterCriteria?, forKey key: String)
}

public final class UserDefaultsDisplayModeFilterStore: DisplayModeFilterPersistence, @unchecked Sendable {
    private let userDefaults: UserDefaults
    private let keyPrefix: String

    public init(
        userDefaults: UserDefaults = .standard,
        keyPrefix: String = "OpenBetterDisplay.displayModeFilter."
    ) {
        self.userDefaults = userDefaults
        self.keyPrefix = keyPrefix
    }

    public func modeFilter(forKey key: String) -> DisplayModeFilterCriteria? {
        guard let data = userDefaults.data(forKey: storageKey(for: key)) else {
            return nil
        }
        return try? JSONDecoder().decode(DisplayModeFilterCriteria.self, from: data)
    }

    public func setModeFilter(_ filter: DisplayModeFilterCriteria?, forKey key: String) {
        let storageKey = storageKey(for: key)
        guard let filter else {
            userDefaults.removeObject(forKey: storageKey)
            return
        }
        guard let encoded = try? JSONEncoder().encode(filter) else {
            return
        }
        userDefaults.set(encoded, forKey: storageKey)
    }

    private func storageKey(for key: String) -> String {
        keyPrefix + key
    }
}
