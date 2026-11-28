import Foundation
import Security
import Testing
@testable import AirTranslate

private final class StubKeychainBackend: @unchecked Sendable {
    private let lock = NSLock()
    private var storedData: Data?
    var copyMatchingCalls = 0
    var addCalls = 0
    var updateCalls = 0
    var deleteCalls = 0
    var failAddWith: OSStatus?

    init(initialKey: String? = nil) {
        self.storedData = initialKey.flatMap { $0.data(using: .utf8) }
    }

    func operations() -> APIKeyStoreCache.KeychainOperations {
        APIKeyStoreCache.KeychainOperations(
            copyMatching: { query, result in
                self.lock.withLock {
                    self.copyMatchingCalls += 1
                    let dict = query as NSDictionary
                    guard let data = self.storedData else { return errSecItemNotFound }
                    if (dict[kSecReturnData as String] as? Bool) == true {
                        result?.pointee = data as CFData
                    } else if (dict[kSecReturnAttributes as String] as? Bool) == true {
                        result?.pointee = [:] as CFDictionary
                    }
                    return errSecSuccess
                }
            },
            add: { query, _ in
                self.lock.withLock {
                    self.addCalls += 1
                    if let fail = self.failAddWith { return fail }
                    guard self.storedData == nil else { return errSecDuplicateItem }
                    self.storedData = (query as NSDictionary)[kSecValueData as String] as? Data
                    return errSecSuccess
                }
            },
            update: { _, attributes in
                self.lock.withLock {
                    self.updateCalls += 1
                    guard self.storedData != nil else { return errSecItemNotFound }
                    self.storedData = (attributes as NSDictionary)[kSecValueData as String] as? Data
                    return errSecSuccess
                }
            },
            delete: { _ in
                self.lock.withLock {
                    self.deleteCalls += 1
                    guard self.storedData != nil else { return errSecItemNotFound }
                    self.storedData = nil
                    return errSecSuccess
                }
            }
        )
    }

    var currentKey: String? {
        lock.withLock { storedData.flatMap { String(data: $0, encoding: .utf8) } }
    }
}

@Suite(.serialized)
struct APIKeyStorePresenceTests {
    @Test
    func openAIPresenceCheckDoesNotReadSecretDataOrAllowAuthenticationUI() {
        verifyPresenceQuery(
            OpenAIAPIKeyStore.presenceQuery(),
            service: "AirTranslate.OpenAI",
            account: "OPENAI_API_KEY"
        )
    }

    @Test
    func geminiPresenceCheckDoesNotReadSecretDataOrAllowAuthenticationUI() {
        verifyPresenceQuery(
            GeminiAPIKeyStore.presenceQuery(),
            service: "AirTranslate.Gemini",
            account: "GEMINI_API_KEY"
        )
    }

    @Test
    func metaPresenceCheckDoesNotReadSecretDataOrAllowAuthenticationUI() {
        verifyPresenceQuery(
            MetaAPIKeyStore.presenceQuery(),
            service: "AirTranslate.Meta",
            account: "MODEL_API_KEY"
        )
    }

    @Test
    func nariPresenceCheckDoesNotReadSecretDataOrAllowAuthenticationUI() {
        verifyPresenceQuery(
            NariAPIKeyStore.presenceQuery(),
            service: "AirTranslate.Nari",
            account: "NARI_API_KEY"
        )
    }

    @Test
    func jevPresenceCheckUsesIsolatedKeychainWithoutReadingSecretData() {
        verifyPresenceQuery(JevAPIKeyStore.presenceQuery(), service: "AirTranslate.Jev", account: "TYPESAFE_API_KEY")
    }

    @Test
    func nariKeyValidationRejectsBlankAndEmbeddedControlCharactersWithoutAccessingKeychain() throws {
        #expect(try NariAPIKeyStore.normalizedAPIKey("  test-placeholder  ") == "test-placeholder")
        for value in ["", " \n ", "test\r\nheader", "test\u{00}value", "test value"] {
            #expect(throws: NariAPIKeyStoreError.self) {
                try NariAPIKeyStore.normalizedAPIKey(value)
            }
        }
    }

    @Test
    func keychainCacheHitsEliminateRepeatedIPCAndMutationsInvalidateOrUpdateAtomically() throws {
        let backend = StubKeychainBackend(initialKey: "sk-initial")
        OpenAIAPIKeyStore.cache.resetForTesting(operations: backend.operations())
        defer { OpenAIAPIKeyStore.resetCacheForTesting() }

        #expect(OpenAIAPIKeyStore.hasAPIKey())
        #expect(OpenAIAPIKeyStore.hasAPIKey())
        #expect(backend.copyMatchingCalls == 1)

        #expect(try OpenAIAPIKeyStore.readAPIKey() == "sk-initial")
        #expect(try OpenAIAPIKeyStore.readAPIKey() == "sk-initial")
        #expect(OpenAIAPIKeyStore.hasAPIKey())
        #expect(backend.copyMatchingCalls == 2)

        try OpenAIAPIKeyStore.saveAPIKey("sk-updated")
        #expect(backend.updateCalls == 1)
        #expect(backend.deleteCalls == 0)
        #expect(try OpenAIAPIKeyStore.readAPIKey() == "sk-updated")
        #expect(OpenAIAPIKeyStore.hasAPIKey())
        #expect(backend.copyMatchingCalls == 2)

        try OpenAIAPIKeyStore.deleteAPIKey()
        #expect(!OpenAIAPIKeyStore.hasAPIKey())
        #expect(try OpenAIAPIKeyStore.readAPIKey() == nil)
        #expect(backend.copyMatchingCalls == 2)

        backend.failAddWith = errSecAuthFailed
        #expect(throws: OpenAIAPIKeyStoreError.self) {
            try OpenAIAPIKeyStore.saveAPIKey("sk-fail")
        }
        #expect(OpenAIAPIKeyStore.cache.cachedStateForTesting == .unknown)
        backend.failAddWith = nil
        #expect(!OpenAIAPIKeyStore.hasAPIKey())
        #expect(backend.copyMatchingCalls == 3)

        try OpenAIAPIKeyStore.saveAPIKey("sk-new")
        #expect(backend.addCalls == 2)
        #expect(backend.currentKey == "sk-new")
        #expect(try OpenAIAPIKeyStore.readAPIKey() == "sk-new")
        #expect(backend.copyMatchingCalls == 3)

        OpenAIAPIKeyStore.cache.resetForTesting(operations: backend.operations())
        #expect(OpenAIAPIKeyStore.cache.cachedStateForTesting == .unknown)
        #expect(try OpenAIAPIKeyStore.readAPIKey() == "sk-new")
        #expect(backend.copyMatchingCalls == 4)
    }

    private func verifyPresenceQuery(
        _ query: [String: Any],
        service: String,
        account: String
    ) {
        #expect(query[kSecClass as String] as? String == kSecClassGenericPassword as String)
        #expect(query[kSecAttrService as String] as? String == service)
        #expect(query[kSecAttrAccount as String] as? String == account)
        #expect(query[kSecReturnAttributes as String] as? Bool == true)
        #expect(query[kSecReturnData as String] == nil)
        #expect(query[kSecMatchLimit as String] as? String == kSecMatchLimitOne as String)
        #expect(
            query[kSecUseAuthenticationUI as String] as? String
                == kSecUseAuthenticationUISkip as String
        )
    }
}
