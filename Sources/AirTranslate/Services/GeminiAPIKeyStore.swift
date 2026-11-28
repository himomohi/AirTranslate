import Foundation
import Security

enum GeminiAPIKeyStore {
    private static let service = "AirTranslate.Gemini"
    private static let account = "GEMINI_API_KEY"
    static let cache = APIKeyStoreCache()

    static func hasAPIKey() -> Bool {
        cache.hasAPIKey(presenceQuery: presenceQuery)
    }

    static func readAPIKey() throws -> String? {
        try cache.readAPIKey(
            readQuery: readQuery,
            makeStatusError: GeminiAPIKeyStoreError.keychainStatus,
            invalidStoredKeyError: GeminiAPIKeyStoreError.invalidStoredKey
        )
    }

    static func saveAPIKey(_ key: String) throws {
        let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            throw GeminiAPIKeyStoreError.emptyKey
        }
        try cache.saveAPIKey(
            trimmedKey,
            baseQuery: baseQuery(),
            invalidStoredKeyError: GeminiAPIKeyStoreError.invalidStoredKey,
            makeStatusError: GeminiAPIKeyStoreError.keychainStatus
        )
    }

    static func deleteAPIKey() throws {
        try cache.deleteAPIKey(
            baseQuery: baseQuery(),
            makeStatusError: GeminiAPIKeyStoreError.keychainStatus
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
            kSecAttrAccount as String: account
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
