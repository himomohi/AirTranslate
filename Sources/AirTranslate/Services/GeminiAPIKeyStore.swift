import Foundation
import os
import Security

enum GeminiAPIKeyStore {
    private static let service = "AirTranslate.Gemini"
    private static let account = "GEMINI_API_KEY"

    private static let cache = OSAllocatedUnfairLock<String?>(initialState: nil)

    static func hasAPIKey() -> Bool {
        var item: CFTypeRef?
        let status = SecItemCopyMatching(presenceQuery() as CFDictionary, &item)
        return status == errSecSuccess
    }

    /// Returns the cached key after the first successful read so repeated
    /// connections do not re-trigger macOS Keychain access prompts.
    static func readAPIKey() throws -> String? {
        if let cached = cache.withLock({ $0 }) {
            return cached
        }
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw GeminiAPIKeyStoreError.keychainStatus(status)
        }
        guard let data = item as? Data,
              let key = String(data: data, encoding: .utf8) else {
            throw GeminiAPIKeyStoreError.invalidStoredKey
        }
        cache.withLock { $0 = key }
        return key
    }

    static func saveAPIKey(_ key: String) throws {
        let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            throw GeminiAPIKeyStoreError.emptyKey
        }
        guard let data = trimmedKey.data(using: .utf8) else {
            throw GeminiAPIKeyStoreError.invalidStoredKey
        }

        cache.withLock { $0 = nil }
        SecItemDelete(baseQuery() as CFDictionary)

        var query = baseQuery()
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw GeminiAPIKeyStoreError.keychainStatus(status)
        }
        cache.withLock { $0 = trimmedKey }
    }

    static func deleteAPIKey() throws {
        cache.withLock { $0 = nil }
        let status = SecItemDelete(baseQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw GeminiAPIKeyStoreError.keychainStatus(status)
        }
    }

    private static func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    static func presenceQuery() -> [String: Any] {
        var query = baseQuery()
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUISkip
        return query
    }
}

enum GeminiAPIKeyStoreError: LocalizedError {
    case emptyKey
    case invalidStoredKey
    case keychainStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .emptyKey:
            AppText.geminiAPIKeyEmpty
        case .invalidStoredKey:
            AppText.geminiAPIKeyInvalidStoredValue
        case let .keychainStatus(status):
            AppText.geminiAPIKeychainFailed(status)
        }
    }
}
