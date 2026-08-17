// CompanionEnrollmentKeychainStore.swift
// Fall Guardian — watchOS
//
// Durable storage for the watch's own device credentials, obtained once by
// claiming a companion-enrollment token from the phone. Per
// docs/COMPANION_ENROLLMENT.md §3: `deviceToken` is a durable secret and
// belongs in the Keychain; `deviceId`, schema version, and enrollment date
// are non-sensitive and are kept in UserDefaults alongside it.
//
// This item survives an app reinstall (Keychain items outlive the app unless
// explicitly deleted), which matches "retain the credentials after a
// restart." A new enrollment cleanly replaces the previous credentials.

import Foundation
import Security

struct CompanionCredentials {
    let deviceId: String
    let deviceToken: String
}

enum CompanionEnrollmentKeychainStore {
    private static let service = "com.fallguardian.app.watchkitapp.companion-credentials"
    private static let account = "companion-device-token"

    private static let deviceIdKey = "companion_device_id"
    private static let schemaVersionKey = "companion_schema_version"
    private static let enrolledAtKey = "companion_enrolled_at"

    /// Reads the currently stored credentials, if any. Returns `nil` if no
    /// enrollment has ever succeeded, or if the Keychain item is missing
    /// while the non-sensitive `deviceId` is still present (a corrupted or
    /// partially-deleted state) — callers must treat that as "not enrolled"
    /// rather than silently proceeding without a token.
    static func read() -> CompanionCredentials? {
        guard let deviceId = UserDefaults.standard.string(forKey: deviceIdKey) else {
            return nil
        }
        guard let deviceToken = readToken() else {
            return nil
        }
        return CompanionCredentials(deviceId: deviceId, deviceToken: deviceToken)
    }

    /// Persists new credentials, replacing any previous enrollment atomically
    /// from the caller's point of view: the non-sensitive fields and the
    /// Keychain secret are only considered saved once both writes succeed.
    @discardableResult
    static func save(deviceId: String, deviceToken: String, schemaVersion: Int) -> Bool {
        guard writeToken(deviceToken) else { return false }

        let defaults = UserDefaults.standard
        defaults.set(deviceId, forKey: deviceIdKey)
        defaults.set(schemaVersion, forKey: schemaVersionKey)
        defaults.set(Date().timeIntervalSince1970, forKey: enrolledAtKey)
        return true
    }

    /// Removes any stored enrollment so a new one starts from a clean slate.
    static func clear() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: deviceIdKey)
        defaults.removeObject(forKey: schemaVersionKey)
        defaults.removeObject(forKey: enrolledAtKey)
        deleteToken()
    }

    // MARK: - Keychain primitives

    private static func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private static func readToken() -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func writeToken(_ token: String) -> Bool {
        guard let data = token.data(using: .utf8) else { return false }
        deleteToken()

        var query = baseQuery()
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    private static func deleteToken() {
        SecItemDelete(baseQuery() as CFDictionary)
    }
}
