import Foundation

public protocol DisplayModeFilterPersistence: Sendable {
    func modeFilter(forKey key: String) -> DisplayModeFilterCriteria?
    func setModeFilter(_ filter: DisplayModeFilterCriteria?, forKey key: String)
}

public final class UserDefaultsDisplayModeFilterStore: DisplayModeFilterPersistence, Sendable {
    private let jsonStore: UserDefaultsJSONStore

    public init(
        userDefaults: UserDefaults = .standard,
        keyPrefix: String = "OpenBetterDisplay.displayModeFilter."
    ) {
        self.jsonStore = UserDefaultsJSONStore(userDefaults: userDefaults, keyPrefix: keyPrefix)
    }

    public func modeFilter(forKey key: String) -> DisplayModeFilterCriteria? {
        jsonStore.load(forKey: key)
    }

    public func setModeFilter(_ filter: DisplayModeFilterCriteria?, forKey key: String) {
        jsonStore.save(filter, forKey: key)
    }
}
