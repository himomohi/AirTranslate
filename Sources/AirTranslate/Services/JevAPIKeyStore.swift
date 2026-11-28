import Foundation
import Security
import LocalAuthentication

enum JevAPIKeyStore {
    private static let service = "AirTranslate.Jev"
    private static let account = "TYPESAFE_API_KEY"
    static let cache = APIKeyStoreCache()

    static func hasAPIKey() -> Bool {
        cache.hasAPIKey(presenceQuery: presenceQuery)
    }

    static func readAPIKey() throws -> String? {
        try cache.readAPIKey(
            readQuery: readQuery,
            makeStatusError: JevAPIKeyStoreError.keychainStatus,
            invalidStoredKeyError: JevAPIKeyStoreError.invalidStoredKey
        )
    }

    static func saveAPIKey(_ key: String) throws {
        let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty, trimmedKey.utf8.count <= 16_384,
              trimmedKey.utf8.allSatisfy({ $0 >= 0x21 && $0 <= 0x7e }) else {
            throw JevAPIKeyStoreError.emptyKey
        }
        try cache.saveAPIKey(
            trimmedKey,
            baseQuery: baseQuery(),
            invalidStoredKeyError: JevAPIKeyStoreError.invalidStoredKey,
            makeStatusError: JevAPIKeyStoreError.keychainStatus
        )
    }

    static func deleteAPIKey() throws {
        try cache.deleteAPIKey(
            baseQuery: baseQuery(),
            makeStatusError: JevAPIKeyStoreError.keychainStatus
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
        var query = baseQuery()
        query[kSecReturnData as String] = true
        let context = LAContext()
        context.interactionNotAllowed = true
        query[kSecUseAuthenticationContext as String] = context
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        return query
    }

    static func presenceQuery() -> [String: Any] {
        var query = baseQuery()
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUISkip
        return query
    }
}

enum JevAPIKeyStoreError: LocalizedError {
    case emptyKey
    case invalidStoredKey
    case keychainStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .emptyKey:
            JevCopy.keyRequired
        case .invalidStoredKey:
            JevCopy.keyRequired
        case let .keychainStatus(status):
            "Jev Keychain (\(status))"
        }
    }
}
