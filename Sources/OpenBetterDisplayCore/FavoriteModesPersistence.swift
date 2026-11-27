import Foundation

public protocol FavoriteModesPersistence: Sendable {
    func favoriteModes(forKey key: String) -> [Int: FavoriteModeRecord]
    func setFavoriteModes(_ slots: [Int: FavoriteModeRecord], forKey key: String)
}

public final class UserDefaultsFavoriteModesStore: FavoriteModesPersistence, Sendable {
    public static let validSlotRange = 1...5

    private let jsonStore: UserDefaultsJSONStore

    public init(
        userDefaults: UserDefaults = .standard,
        keyPrefix: String = "OpenBetterDisplay.favoriteModes."
    ) {
        self.jsonStore = UserDefaultsJSONStore(userDefaults: userDefaults, keyPrefix: keyPrefix)
    }

    public func favoriteModes(forKey key: String) -> [Int: FavoriteModeRecord] {
        guard let decoded = jsonStore.load([String: FavoriteModeRecord].self, forKey: key) else {
            return [:]
        }

        var result: [Int: FavoriteModeRecord] = [:]
        for (rawSlot, record) in decoded {
            if let slot = Int(rawSlot), Self.validSlotRange.contains(slot) {
                result[slot] = record
            }
        }
        return result
    }

    public func setFavoriteModes(_ slots: [Int: FavoriteModeRecord], forKey key: String) {
        var encodedPayload: [String: FavoriteModeRecord] = [:]
        for (slot, record) in slots where Self.validSlotRange.contains(slot) {
            encodedPayload[String(slot)] = record
        }

        jsonStore.save(encodedPayload.isEmpty ? nil : encodedPayload, forKey: key)
    }
}
