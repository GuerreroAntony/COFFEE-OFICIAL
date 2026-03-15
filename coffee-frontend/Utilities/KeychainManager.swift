import Foundation
import Security

// MARK: - Keychain Manager
// Secure storage for JWT tokens — replaces localStorage in React

enum KeychainManager {

    private static let service = "com.coffee.ios"

    enum Key: String {
        case accessToken = "coffee_access_token"
        case refreshToken = "coffee_refresh_token"
        case userId = "coffee_user_id"
    }

    // MARK: - Save

    @discardableResult
    static func save(key: Key, value: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }

        // Delete existing item first
        delete(key: key)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    // MARK: - Read

    static func read(key: Key) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }

        return string
    }

    // MARK: - Delete

    @discardableResult
    static func delete(key: Key) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue
        ]

        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    // MARK: - Clear All

    static func clearAll() {
        Key.allCases.forEach { delete(key: $0) }
    }

    // MARK: - Token Helpers

    static var accessToken: String? {
        read(key: .accessToken)
    }

    static var isLoggedIn: Bool {
        accessToken != nil
    }

    static func saveTokens(access: String, userId: String) {
        save(key: .accessToken, value: access)
        save(key: .userId, value: userId)
    }
}

// MARK: - CaseIterable for clearAll

extension KeychainManager.Key: CaseIterable {}
