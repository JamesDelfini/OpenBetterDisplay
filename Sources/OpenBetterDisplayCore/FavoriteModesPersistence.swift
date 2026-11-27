import Foundation

public protocol FavoriteModesPersistence: Sendable {
    func favoriteModes(forKey key: String) -> [Int: FavoriteModeRecord]
    func setFavoriteModes(_ slots: [Int: FavoriteModeRecord], forKey key: String)
}

public final class UserDefaultsFavoriteModesStore: FavoriteModesPersistence, @unchecked Sendable {
    public static let validSlotRange = 1...5

    private let userDefaults: UserDefaults
    private let keyPrefix: String

    public init(
        userDefaults: UserDefaults = .standard,
        keyPrefix: String = "OpenBetterDisplay.favoriteModes."
    ) {
        self.userDefaults = userDefaults
        self.keyPrefix = keyPrefix
    }

    public func favoriteModes(forKey key: String) -> [Int: FavoriteModeRecord] {
        guard let data = userDefaults.data(forKey: storageKey(for: key)),
            let decoded = try? JSONDecoder().decode([String: FavoriteModeRecord].self, from: data)
        else {
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

        let storageKey = storageKey(for: key)
        if encodedPayload.isEmpty {
            userDefaults.removeObject(forKey: storageKey)
            return
        }

        if let data = try? JSONEncoder().encode(encodedPayload) {
            userDefaults.set(data, forKey: storageKey)
        }
    }

    private func storageKey(for key: String) -> String {
        keyPrefix + key
    }
}
