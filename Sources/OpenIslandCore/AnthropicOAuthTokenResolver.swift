import Foundation
import Security
#if canImport(CryptoKit)
import CryptoKit
#endif

/// Resolves an Anthropic OAuth access token from local credential stores.
///
/// Tries multiple sources in order:
/// 1. Claude Code CLI Keychain entry ("Claude Code-credentials")
/// 2. Claude Desktop app config (encrypted token cache — best-effort)
public enum AnthropicOAuthTokenResolver {
    public enum Error: Swift.Error {
        case noCredentialsFound
        case invalidCredentialFormat
        case keychainError(OSStatus)
    }

    /// Attempts to resolve an OAuth access token from local stores.
    public static func resolve() throws -> String {
        // Layer 1: Claude Code CLI credentials in Keychain
        if let token = try? resolveFromClaudeCodeKeychain() {
            return token
        }

        // Layer 2: Claude Desktop config (best-effort)
        if let token = try? resolveFromClaudeDesktopConfig() {
            return token
        }

        throw Error.noCredentialsFound
    }

    // MARK: - Layer 1: Claude Code CLI Keychain

    private static func resolveFromClaudeCodeKeychain() throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else {
            throw Error.keychainError(status)
        }

        guard let data = result as? Data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = json["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String,
              !token.isEmpty
        else {
            throw Error.invalidCredentialFormat
        }

        return token
    }

    // MARK: - Layer 2: Claude Desktop config

    private static func resolveFromClaudeDesktopConfig() throws -> String? {
        let configURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Claude/config.json")

        guard FileManager.default.fileExists(atPath: configURL.path) else {
            return nil
        }

        let data = try Data(contentsOf: configURL)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        // The oauth:tokenCache value is encrypted (prefixed with "v10").
        // Decryption requires the "Claude Safe Storage" Keychain key.
        // This is best-effort; if decryption fails we return nil.
        guard let tokenCache = json["oauth:tokenCache"] as? String else {
            return nil
        }

        return try? decryptClaudeDesktopTokenCache(tokenCache)
    }

    /// Attempts to decrypt Claude Desktop's oauth:tokenCache.
    ///
    /// The cache format is: base64("v10" + encrypted_data)
    /// The encryption key is stored in Keychain under "Claude Safe Storage" / "Claude Key".
    ///
    /// This is a best-effort implementation based on reverse-engineering.
    /// If the format changes this may fail silently.
    private static func decryptClaudeDesktopTokenCache(_ tokenCache: String) throws -> String? {
        // 1. Base64 decode
        guard let data = Data(base64Encoded: tokenCache) else {
            return nil
        }

        // 2. Check version prefix
        let versionPrefix = Data("v10".utf8)
        guard data.count > versionPrefix.count,
              data.prefix(versionPrefix.count) == versionPrefix
        else {
            return nil
        }

        let ciphertext = data.dropFirst(versionPrefix.count)

        // 3. Retrieve encryption key from Keychain
        let keyQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Safe Storage",
            kSecAttrAccount as String: "Claude Key",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var keyResult: AnyObject?
        let keyStatus = SecItemCopyMatching(keyQuery as CFDictionary, &keyResult)
        guard keyStatus == errSecSuccess,
              let keyData = keyResult as? Data
        else {
            return nil
        }

        // 4. Decode key (base64)
        guard let keyString = String(data: keyData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              let key = Data(base64Encoded: keyString)
        else {
            return nil
        }

        // 5. Decrypt using AES-256-GCM (Electron safeStorage format)
        //    Format: 12-byte nonce || ciphertext || 16-byte auth tag
        guard ciphertext.count > 28 else { return nil }
        let nonce = ciphertext.prefix(12)
        let sealedBox = ciphertext.dropFirst(12)

        return try aesGCMDecrypt(sealedBox: Data(sealedBox), key: key, nonce: Data(nonce))
    }
}

// MARK: - AES-256-GCM Decryption

#if canImport(CryptoKit)
private func aesGCMDecrypt(sealedBox: Data, key: Data, nonce: Data) throws -> String? {
    guard key.count == 32,
          nonce.count == 12,
          sealedBox.count >= 16
    else {
        return nil
    }

    let symmetricKey = SymmetricKey(data: key)
    _ = try AES.GCM.Nonce(data: nonce)

    // sealedBox = ciphertext || tag(16 bytes)
    let ciphertext = sealedBox.dropLast(16)
    let tag = sealedBox.suffix(16)
    let combined = ciphertext + tag

    let sealedBoxObj = try AES.GCM.SealedBox(combined: combined)
    let decrypted = try AES.GCM.open(sealedBoxObj, using: symmetricKey)

    return String(data: decrypted, encoding: .utf8)
}
#else
private func aesGCMDecrypt(sealedBox: Data, key: Data, nonce: Data) throws -> String? {
    // Fallback when CryptoKit is unavailable
    return nil
}
#endif
