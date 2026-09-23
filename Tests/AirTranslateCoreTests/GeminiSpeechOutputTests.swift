import Foundation
import Testing
@testable import AirTranslate

@Suite(.serialized)
struct GeminiSpeechOutputTests {
    private static let selectedModelKey = "speechSynthesisModelID"

    @Test
    func appleAndBothGeminiSpeechModelsAreSelectable() {
        #expect(SpeechSynthesisModel.allCases.map(\.rawValue) == [
            "apple-system",
            "gemini-3.8-flash-tts",
            "gemini-3.8-flash-lite-tts",
        ])
        #expect(SpeechSynthesisModel.appleSystem.apiModelID == nil)
        #expect(SpeechSynthesisModel.gemini38Flash.apiModelID == "gemini-3.8-flash-tts")
        #expect(SpeechSynthesisModel.gemini38FlashLite.apiModelID == "gemini-3.8-flash-lite-tts")
    }

    @Test(arguments: [
        SpeechSynthesisModel.gemini38Flash,
        SpeechSynthesisModel.gemini38FlashLite,
    ])
    @MainActor
    func requestUsesSelectedModelAndKeepsKeyOutOfBodyAndURL(_ model: SpeechSynthesisModel) throws {
        let apiKey = "test-gemini-key-123"
        let text = "Stable translated sentence."
        let request = try GeminiSpeechOutput.makeRequest(text: text, model: model, apiKey: apiKey)
        let body = try #require(request.httpBody)
        let payload = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let serializedBody = try #require(String(data: body, encoding: .utf8))

        #expect(request.httpMethod == "POST")
        #expect(request.url?.host == "generativelanguage.googleapis.com")
        #expect(request.url?.absoluteString.contains(apiKey) == false)
        #expect(request.value(forHTTPHeaderField: "x-goog-api-key") == apiKey)
        #expect(payload["model"] as? String == model.apiModelID)
        #expect(serializedBody.contains(text))
        #expect(!serializedBody.contains(apiKey))
    }

    @Test
    func redirectDelegateRejectsRequestForwarding() throws {
        let url = try #require(URL(string: "https://generativelanguage.googleapis.com/v1beta/interactions"))
        let redirectURL = try #require(URL(string: "https://attacker.example/collect"))
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let task = session.dataTask(with: url)
        let response = try #require(HTTPURLResponse(
            url: url,
            statusCode: 302,
            httpVersion: nil,
            headerFields: ["Location": redirectURL.absoluteString]
        ))
        let proposedRequest = URLRequest(url: redirectURL)
        var forwardedRequest: URLRequest? = proposedRequest

        GeminiSpeechOutputRejectRedirects().urlSession(
            session,
            task: task,
            willPerformHTTPRedirection: response,
            newRequest: proposedRequest,
            completionHandler: { forwardedRequest = $0 }
        )

        #expect(forwardedRequest == nil)
    }

    @Test
    @MainActor
    func selectedSpeechModelPersistsAndRestores() {
        StandardUserDefaultsTestLock.shared.withLock {
            let defaults = UserDefaults.standard
            let previousValue = defaults.object(forKey: Self.selectedModelKey)
            defer {
                if let previousValue {
                    defaults.set(previousValue, forKey: Self.selectedModelKey)
                } else {
                    defaults.removeObject(forKey: Self.selectedModelKey)
                }
            }

            defaults.set(SpeechSynthesisModel.appleSystem.rawValue, forKey: Self.selectedModelKey)
            let session = TranslationSessionStore(modelAvailabilityProvider: { _, _ in [:] })
            #expect(session.speechSynthesisModel == .appleSystem)

            session.speechSynthesisModel = .gemini38FlashLite
            #expect(defaults.string(forKey: Self.selectedModelKey) == SpeechSynthesisModel.gemini38FlashLite.rawValue)

            let restoredSession = TranslationSessionStore(modelAvailabilityProvider: { _, _ in [:] })
            #expect(restoredSession.speechSynthesisModel == .gemini38FlashLite)
        }
    }
}
