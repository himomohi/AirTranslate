import Foundation
import LocalAuthentication
import Security

enum OpenAIAPIKeyStore {
    private static let service = "AirTranslate.OpenAI"
    private static let account = "OPENAI_API_KEY"
    static let cache = APIKeyStoreCache()

    static func hasAPIKey() -> Bool {
        cache.hasAPIKey(presenceQuery: presenceQuery)
    }

    static func readAPIKey() throws -> String? {
        try cache.readAPIKey(
            readQuery: readQuery,
            makeStatusError: OpenAIAPIKeyStoreError.keychainStatus,
            invalidStoredKeyError: OpenAIAPIKeyStoreError.invalidStoredKey
        )
    }

    static func saveAPIKey(_ key: String) throws {
        let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            throw OpenAIAPIKeyStoreError.emptyKey
        }
        try cache.saveAPIKey(
            trimmedKey,
            baseQuery: baseQuery(),
            invalidStoredKeyError: OpenAIAPIKeyStoreError.invalidStoredKey,
            makeStatusError: OpenAIAPIKeyStoreError.keychainStatus
        )
    }

    static func deleteAPIKey() throws {
        try cache.deleteAPIKey(
            baseQuery: baseQuery(),
            makeStatusError: OpenAIAPIKeyStoreError.keychainStatus
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

final class APIKeyStoreCache: @unchecked Sendable {
    enum State: Equatable {
        case unknown
        case missing
        case presentUnknownValue
        case value(String)
    }

    struct KeychainOperations: Sendable {
        let copyMatching: @Sendable (CFDictionary, UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus
        let add: @Sendable (CFDictionary, UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus
        let update: @Sendable (CFDictionary, CFDictionary) -> OSStatus
        let delete: @Sendable (CFDictionary) -> OSStatus

        static let live = KeychainOperations(
            copyMatching: { SecItemCopyMatching($0, $1) },
            add: { SecItemAdd($0, $1) },
            update: { SecItemUpdate($0, $1) },
            delete: { SecItemDelete($0) }
        )
    }

    private let lock = NSLock()
    private let mutationLock = NSLock()
    private var state: State = .unknown
    private var mutationVersion: UInt64 = 0
    private var operations: KeychainOperations = .live

    static func nonInteractiveReadQuery(baseQuery: [String: Any]) -> [String: Any] {
        var query = baseQuery
        query[kSecReturnData as String] = true
        let context = LAContext()
        context.interactionNotAllowed = true
        query[kSecUseAuthenticationContext as String] = context
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        return query
    }

    func hasAPIKey(presenceQuery: () -> [String: Any]) -> Bool {
        let snapshot: (Bool?, UInt64, KeychainOperations) = lock.withLock {
            switch state {
            case .value, .presentUnknownValue:
                return (true, mutationVersion, operations)
            case .missing:
                return (false, mutationVersion, operations)
            case .unknown:
                return (nil, mutationVersion, operations)
            }
        }
        if let cached = snapshot.0 {
            return cached
        }

        var item: CFTypeRef?
        let status = snapshot.2.copyMatching(presenceQuery() as CFDictionary, &item)
        return lock.withLock {
            if mutationVersion == snapshot.1, state == .unknown {
                if status == errSecSuccess {
                    state = .presentUnknownValue
                } else if status == errSecItemNotFound {
                    state = .missing
                }
            }
            switch state {
            case .value, .presentUnknownValue:
                return true
            case .missing:
                return false
            case .unknown:
                return status == errSecSuccess
            }
        }
    }

    func readAPIKey(
        readQuery: () -> [String: Any],
        makeStatusError: (OSStatus) -> any Error,
        invalidStoredKeyError: any Error
    ) throws -> String? {
        let snapshot: (Result<String?, Never>?, UInt64, KeychainOperations) = lock.withLock {
            switch state {
            case .missing:
                return (.success(nil), mutationVersion, operations)
            case .value(let key):
                return (.success(key), mutationVersion, operations)
            case .unknown, .presentUnknownValue:
                return (nil, mutationVersion, operations)
            }
        }
        if case let .success(cached) = snapshot.0 {
            return cached
        }

        var item: CFTypeRef?
        let status = snapshot.2.copyMatching(readQuery() as CFDictionary, &item)
        if status == errSecItemNotFound {
            return lock.withLock {
                if mutationVersion == snapshot.1 {
                    state = .missing
                    return nil
                }
                if case let .value(key) = state {
                    return key
                }
                return nil
            }
        }
        guard status == errSecSuccess else {
            throw makeStatusError(status)
        }
        guard let data = item as? Data,
              let key = String(data: data, encoding: .utf8) else {
            throw invalidStoredKeyError
        }
        return lock.withLock {
            if mutationVersion == snapshot.1 {
                state = .value(key)
                return key
            }
            switch state {
            case .value(let latest):
                return latest
            case .missing:
                return nil
            case .unknown, .presentUnknownValue:
                return key
            }
        }
    }

    func saveAPIKey(
        _ normalizedKey: String,
        baseQuery: [String: Any],
        invalidStoredKeyError: any Error,
        makeStatusError: (OSStatus) -> any Error
    ) throws {
        guard let data = normalizedKey.data(using: .utf8) else {
            throw invalidStoredKeyError
        }
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        try mutationLock.withLock {
            let ops = lock.withLock { operations }
            let updateStatus = ops.update(baseQuery as CFDictionary, attributes as CFDictionary)
            if updateStatus == errSecSuccess {
                lock.withLock {
                    mutationVersion &+= 1
                    state = .value(normalizedKey)
                }
                return
            }
            guard updateStatus == errSecItemNotFound else {
                lock.withLock {
                    mutationVersion &+= 1
                    state = .unknown
                }
                throw makeStatusError(updateStatus)
            }

            var addQuery = baseQuery
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let addStatus = ops.add(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                lock.withLock {
                    mutationVersion &+= 1
                    state = .unknown
                }
                throw makeStatusError(addStatus)
            }
            lock.withLock {
                mutationVersion &+= 1
                state = .value(normalizedKey)
            }
        }
    }

    func deleteAPIKey(
        baseQuery: [String: Any],
        makeStatusError: (OSStatus) -> any Error
    ) throws {
        try mutationLock.withLock {
            let ops = lock.withLock { operations }
            let status = ops.delete(baseQuery as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                lock.withLock {
                    mutationVersion &+= 1
                    state = .unknown
                }
                throw makeStatusError(status)
            }
            lock.withLock {
                mutationVersion &+= 1
                state = .missing
            }
        }
    }

    #if DEBUG
    var cachedStateForTesting: State {
        lock.withLock { state }
    }

    func resetForTesting(operations: KeychainOperations = .live) {
        mutationLock.withLock {
            lock.withLock {
                mutationVersion &+= 1
                state = .unknown
                self.operations = operations
            }
        }
    }
    #endif
}

enum OpenAIAPIKeyStoreError: LocalizedError {
    case emptyKey
    case invalidStoredKey
    case keychainStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .emptyKey:
            AppText.openAIAPIKeyEmpty
        case .invalidStoredKey:
            AppText.openAIAPIKeyInvalidStoredValue
        case let .keychainStatus(status):
            AppText.openAIAPIKeychainFailed(status)
        }
    }
}
