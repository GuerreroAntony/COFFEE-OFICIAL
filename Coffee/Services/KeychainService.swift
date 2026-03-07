import Foundation
import Security

final class KeychainService {
    static let shared = KeychainService()
    private init() {}

    private let tokenKey = "coffee.jwt.token"

    func save(key: String, data: Data) {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: key,
        ]
        SecItemDelete(query as CFDictionary)

        let attributes: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: key,
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        SecItemAdd(attributes as CFDictionary, nil)
    }

    func load(key: String) -> Data? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: key,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        SecItemCopyMatching(query as CFDictionary, &result)
        return result as? Data
    }

    func delete(key: String) {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: key,
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - JWT convenience

    func saveToken(_ token: String) {
        guard let data = token.data(using: .utf8) else { return }
        save(key: tokenKey, data: data)
    }

    func getToken() -> String? {
        guard let data = load(key: tokenKey) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func deleteToken() {
        delete(key: tokenKey)
    }
}
