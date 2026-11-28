import Foundation
import Security

enum QwenAPIKeyStore {
    private static let service = "AirTranslate.Qwen"
    private static let account = "DASHSCOPE_API_KEY"
    static let cache = APIKeyStoreCache()

    static func hasAPIKey() -> Bool {
        cache.hasAPIKey(presenceQuery: presenceQuery)
    }

    static func readAPIKey() throws -> String? {
        try cache.readAPIKey(
            readQuery: readQuery,
            makeStatusError: QwenAPIKeyStoreError.keychainStatus,
            invalidStoredKeyError: QwenAPIKeyStoreError.invalidStoredKey
        )
    }

    static func saveAPIKey(_ key: String) throws {
        let trimmedKey = try normalizedAPIKey(key)
        try cache.saveAPIKey(
            trimmedKey,
            baseQuery: baseQuery(),
            invalidStoredKeyError: QwenAPIKeyStoreError.invalidStoredKey,
            makeStatusError: QwenAPIKeyStoreError.keychainStatus
        )
    }

    static func normalizedAPIKey(_ key: String) throws -> String {
        let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { throw QwenAPIKeyStoreError.emptyKey }
        guard trimmedKey.utf8.allSatisfy({ $0 >= 0x21 && $0 <= 0x7E }) else {
            throw QwenAPIKeyStoreError.invalidStoredKey
        }
        return trimmedKey
    }

    static func deleteAPIKey() throws {
        try cache.deleteAPIKey(
            baseQuery: baseQuery(),
            makeStatusError: QwenAPIKeyStoreError.keychainStatus
        )
    }

    #if DEBUG
    static func resetCacheForTesting() {
        cache.resetForTesting()
    }
    #endif

    private static func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private static func readQuery() -> [String: Any] {
        APIKeyStoreCache.nonInteractiveReadQuery(baseQuery: baseQuery())
    }

    static func presenceQuery() -> [String: Any] {
        var query = baseQuery()
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUISkip
        return query
    }
}

enum QwenAPIKeyStoreError: LocalizedError {
    case emptyKey
    case invalidStoredKey
    case keychainStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .emptyKey:
            QwenCopy.keyInvalid
        case .invalidStoredKey:
            QwenCopy.keyInvalid
        case let .keychainStatus(status):
            "Qwen Keychain (\(status))"
        }
    }
}
