import Foundation

struct UserDefaultsJSONStore: @unchecked Sendable {
    private let userDefaults: UserDefaults
    private let keyPrefix: String

    init(userDefaults: UserDefaults = .standard, keyPrefix: String = "") {
        self.userDefaults = userDefaults
        self.keyPrefix = keyPrefix
    }

    func load<Value: Decodable>(_ type: Value.Type = Value.self, forKey key: String = "") -> Value? {
        guard let data = userDefaults.data(forKey: storageKey(for: key)) else {
            return nil
        }
        return try? JSONDecoder().decode(type, from: data)
    }

    func save<Value: Encodable>(_ value: Value?, forKey key: String = "") {
        let resolvedKey = storageKey(for: key)
        guard let value else {
            userDefaults.removeObject(forKey: resolvedKey)
            return
        }
        guard let data = try? JSONEncoder().encode(value) else {
            return
        }
        userDefaults.set(data, forKey: resolvedKey)
    }

    private func storageKey(for key: String) -> String {
        keyPrefix + key
    }
}
