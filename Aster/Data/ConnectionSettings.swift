import Foundation
import Security

enum ConnectionSettings {
    private static let endpointKey = "komari.endpoint"
    private static let demoModeKey = "komari.demoMode"
    static let tokenAccount = "komari-api-token"

    static var endpoint: String {
        get { UserDefaults.standard.string(forKey: endpointKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: endpointKey) }
    }

    static var isDemoMode: Bool {
        get { UserDefaults.standard.object(forKey: demoModeKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: demoModeKey) }
    }
}

enum KeychainStore {
    static func readToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: ConnectionSettings.tokenAccount,
            kSecReturnData as String: true
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func saveToken(_ token: String) throws {
        let data = Data(token.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: ConnectionSettings.tokenAccount
        ]
        SecItemDelete(query as CFDictionary)
        var item = query
        item[kSecValueData as String] = data
        guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else {
            throw KeychainError.saveFailed
        }
    }

    enum KeychainError: Error { case saveFailed }
}
