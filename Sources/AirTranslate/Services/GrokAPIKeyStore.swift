import Foundation
import Security

enum GrokAPIKeyStore {
    private static let service = "AirTranslate.Grok"
    private static let account = "XAI_API_KEY"

    static func hasAPIKey() -> Bool {
        var item: CFTypeRef?
        let status = SecItemCopyMatching(presenceQuery() as CFDictionary, &item)
        return status == errSecSuccess
    }

    static func readAPIKey() throws -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw GrokAPIKeyStoreError.keychainStatus(status)
        }
        guard let data = item as? Data,
              let key = String(data: data, encoding: .utf8) else {
            throw GrokAPIKeyStoreError.invalidStoredKey
        }
        return key
    }

    static func saveAPIKey(_ key: String) throws {
        let trimmedKey = try normalizedAPIKey(key)
        guard let data = trimmedKey.data(using: .utf8) else {
            throw GrokAPIKeyStoreError.invalidStoredKey
        }

        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let update = SecItemUpdate(baseQuery() as CFDictionary, attributes as CFDictionary)
        if update == errSecSuccess { return }
        guard update == errSecItemNotFound else { throw GrokAPIKeyStoreError.keychainStatus(update) }

        var query = baseQuery()
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw GrokAPIKeyStoreError.keychainStatus(status)
        }
    }

    static func normalizedAPIKey(_ key: String) throws -> String {
        let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { throw GrokAPIKeyStoreError.emptyKey }
        guard trimmedKey.utf8.allSatisfy({ $0 >= 0x21 && $0 <= 0x7E }) else {
            throw GrokAPIKeyStoreError.invalidStoredKey
        }
        return trimmedKey
    }

    static func deleteAPIKey() throws {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw GrokAPIKeyStoreError.keychainStatus(status)
        }
    }

    private static func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
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

enum GrokAPIKeyStoreError: LocalizedError {
    case emptyKey
    case invalidStoredKey
    case keychainStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .emptyKey:
            GrokCopy.keyInvalid
        case .invalidStoredKey:
            GrokCopy.keyInvalid
        case let .keychainStatus(status):
            "Grok Keychain (\(status))"
        }
    }
}
