import Foundation
import Security

enum MetaAPIKeyStore {
    private static let service = "AirTranslate.Meta"
    private static let account = "MODEL_API_KEY"
    static let cache = APIKeyStoreCache()

    static func hasAPIKey() -> Bool {
        cache.hasAPIKey(presenceQuery: presenceQuery)
    }

    static func readAPIKey() throws -> String? {
        try cache.readAPIKey(
            readQuery: readQuery,
            makeStatusError: MetaAPIKeyStoreError.keychainStatus,
            invalidStoredKeyError: MetaAPIKeyStoreError.invalidStoredKey
        )
    }

    static func saveAPIKey(_ key: String) throws {
        let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            throw MetaAPIKeyStoreError.emptyKey
        }
        try cache.saveAPIKey(
            trimmedKey,
            baseQuery: baseQuery(),
            invalidStoredKeyError: MetaAPIKeyStoreError.invalidStoredKey,
            makeStatusError: MetaAPIKeyStoreError.keychainStatus
        )
    }

    static func deleteAPIKey() throws {
        try cache.deleteAPIKey(
            baseQuery: baseQuery(),
            makeStatusError: MetaAPIKeyStoreError.keychainStatus
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

enum MetaAPIKeyStoreError: LocalizedError {
    case emptyKey
    case invalidStoredKey
    case keychainStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .emptyKey:
            AppText.metaAPIKeyEmpty
        case .invalidStoredKey:
            AppText.metaAPIKeyInvalidStoredValue
        case let .keychainStatus(status):
            AppText.metaAPIKeychainFailed(status)
        }
    }
}
