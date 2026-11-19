import Foundation
import Security

struct WatchCredentials: Codable {
    let token: String
    let key: Data
}

/// Tokens and transport keys stay in the device-only Keychain, never preferences.
enum WatchCredentialStore {
    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "app.openisland.mobile.watch-v2",
         kSecAttrAccount as String: "paired-mac"]
    }

    static func load() -> WatchCredentials? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(WatchCredentials.self, from: data)
    }

    static func save(_ credentials: WatchCredentials) throws {
        let data = try JSONEncoder().encode(credentials)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
    }

    static func remove() {
        SecItemDelete(query as CFDictionary)
        UserDefaults.standard.removeObject(forKey: "openisland.token")
    }
}
