import Security
import Testing
@testable import AirTranslate

@Suite
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
    func nariKeyValidationRejectsBlankAndEmbeddedControlCharactersWithoutAccessingKeychain() throws {
        #expect(try NariAPIKeyStore.normalizedAPIKey("  test-placeholder  ") == "test-placeholder")
        for value in ["", " \n ", "test\r\nheader", "test\u{00}value", "test value"] {
            #expect(throws: NariAPIKeyStoreError.self) {
                try NariAPIKeyStore.normalizedAPIKey(value)
            }
        }
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
