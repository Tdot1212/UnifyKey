import Foundation
import Security

// MARK: - SharedKeychain (primary data sharing between app and extension)

/// Shares data between the main app and keyboard extension via Keychain.
/// No App Group needed — uses the keychain-access-groups entitlement.
/// Both targets share $(AppIdentifierPrefix)com.unifykey.shared.
/// kSecAttrAccessGroup is NOT specified — the system automatically uses
/// the first group from the keychain-access-groups entitlement.
final class SharedKeychain {
    static let shared = SharedKeychain()

    private let service = "com.unifykey"

    private init() {}

    // MARK: - Core Operations

    @discardableResult
    func save(key: String, value: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }

        // Delete existing first
        delete(key: key)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        #if DEBUG
        if status != errSecSuccess {
            print("[SharedKeychain] save '\(key)' failed: OSStatus \(status)")
        }
        #endif
        return status == errSecSuccess
    }

    func load(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }

        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    func delete(key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    // MARK: - Convenience: Bool

    @discardableResult
    func saveBool(key: String, value: Bool) -> Bool {
        save(key: key, value: value ? "1" : "0")
    }

    func loadBool(key: String) -> Bool {
        load(key: key) == "1"
    }

    // MARK: - Convenience: Double

    @discardableResult
    func saveDouble(key: String, value: Double) -> Bool {
        save(key: key, value: String(value))
    }

    func loadDouble(key: String) -> Double? {
        guard let str = load(key: key) else { return nil }
        return Double(str)
    }

    // MARK: - Convenience: JSON

    @discardableResult
    func saveJSON<T: Encodable>(key: String, value: T) -> Bool {
        guard let data = try? JSONEncoder().encode(value),
              let jsonString = String(data: data, encoding: .utf8) else {
            return false
        }
        return save(key: key, value: jsonString)
    }

    func loadJSON<T: Decodable>(key: String) -> T? {
        guard let jsonString = load(key: key),
              let data = jsonString.data(using: .utf8) else {
            return nil
        }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}

// MARK: - KeychainHelper (backward-compatible wrapper for API key)

/// Legacy wrapper — delegates to SharedKeychain for the API key.
/// Kept for backward compatibility with existing code.
final class KeychainHelper {
    static let shared = KeychainHelper()

    private init() {}

    func saveAPIKey(_ key: String) -> Bool {
        SharedKeychain.shared.save(key: "apiKey", value: key)
    }

    func loadAPIKey() -> String? {
        SharedKeychain.shared.load(key: "apiKey")
    }

    @discardableResult
    func deleteAPIKey() -> Bool {
        SharedKeychain.shared.delete(key: "apiKey")
    }
}
