//
//  KeychainService.swift
//  Photo2drive
//

import Foundation
import Security

/// Service for securely storing tokens in the Keychain.
enum KeychainService {
    private static let service = "com.photo2drive"

    /// Saves a token to the Keychain.
    /// - Parameters:
    ///   - token: The token to save.
    ///   - key: The key to identify the token.
    static func save(token: String, forKey key: String) {
        guard let data = token.data(using: .utf8) else { return }

        // 既存のアイテムを削除
        delete(forKey: key)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        SecItemAdd(query as CFDictionary, nil)
    }

    /// Loads a token from the Keychain.
    /// - Parameter key: The key to identify the token.
    /// - Returns: The token if found, nil otherwise.
    static func load(forKey key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let token = String(data: data, encoding: .utf8) else {
            return nil
        }

        return token
    }

    /// Deletes a token from the Keychain.
    /// - Parameter key: The key to identify the token.
    static func delete(forKey key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]

        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Storage-specific keys

extension KeychainService {
    /// Keys for Box tokens.
    enum BoxKeys {
        static let accessToken = "box_access_token"
        static let refreshToken = "box_refresh_token"
    }

    /// Keys for Dropbox tokens.
    enum DropboxKeys {
        static let accessToken = "dropbox_access_token"
        static let refreshToken = "dropbox_refresh_token"
    }
}
