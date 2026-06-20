// ios/PetHomepage/Mirror/KeychainHelper.swift
import Foundation
import Security

/// Minimal Keychain wrapper for storing/retrieving/deleting a single string value
/// identified by a `service` + `account` pair. Uses the generic password class
/// (`kSecClassGenericPassword`), which is encrypted at rest and excluded from
/// unencrypted iTunes/iCloud backups.
///
/// Only the `mirrorToken` (a write-capable bearer token) is stored here. The
/// `mirrorEndpoint` URL is not a credential and stays in UserDefaults.
enum KeychainHelper {
    /// Writes `value` to the Keychain. Upserts: deletes any existing item first so
    /// `SecItemAdd` never hits `errSecDuplicateItem`.
    static func save(_ value: String, service: String, account: String) {
        let data = Data(value.utf8)
        // Delete any existing item first (ignore errors — item may not exist).
        let deleteQuery: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecValueData: data,
            // Accessible after first unlock; excluded from unencrypted backups.
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    /// Returns the stored string, or `nil` if no item exists.
    static func read(service: String, account: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Removes the stored item. No-op if it does not exist.
    static func delete(service: String, account: String) {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
