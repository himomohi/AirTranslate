import Foundation
import Security
import Testing
@testable import AirTranslate

private final class MAIVoiceCatalogStub: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var waiting: MAIVoiceCatalogStub?
    nonisolated(unsafe) private static var speechRequests = 0
    static var isWaiting: Bool { lock.withLock { waiting != nil } }
    static var paidRequests: Int { lock.withLock { speechRequests } }
    static func reset() { lock.withLock { waiting = nil; speechRequests = 0 } }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        if request.url?.path == "/api/v1/models" {
            Self.lock.withLock { Self.waiting = self }
        } else {
            Self.lock.withLock { Self.speechRequests += 1 }
            client?.urlProtocol(self, didFailWithError: URLError(.cancelled))
        }
    }
    override func stopLoading() {}
    static func releaseCatalog() {
        let pending = lock.withLock { let value = waiting; waiting = nil; return value }
        guard let pending, let url = pending.request.url else { return }
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        pending.client?.urlProtocol(pending, didReceive: response, cacheStoragePolicy: .notAllowed)
        pending.client?.urlProtocol(pending, didLoad: Data(#"{"data":[{"id":"microsoft/mai-voice-2.1","supported_voices":["en-US-Harper:MAI-Voice-2.1"]}]}"#.utf8))
        pending.client?.urlProtocolDidFinishLoading(pending)
    }
}

@Suite(.serialized)
struct MAIVoiceSpeechOutputTests {
    @Test(arguments: [SpeechSynthesisModel.maiVoice21, .maiVoice21Flash])
    @MainActor
    func requestUsesExactModelVoiceAndRawMP3(_ model: SpeechSynthesisModel) throws {
        let voice = "ko-KR-Haena:" + model.title
        let request = try MAIVoiceSpeechOutput.makeRequest(text: "안녕하세요", model: model, voice: voice, apiKey: "test-only")
        #expect(request.url?.absoluteString == "https://openrouter.ai/api/v1/audio/speech")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-only")
        let data = try #require(request.httpBody)
        let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: String])
        #expect(body == ["model": model.rawValue, "input": "안녕하세요", "voice": voice, "response_format": "mp3"])
        #expect(!String(decoding: data, as: UTF8.self).contains("test-only"))
        #expect(!model.isGeminiTTS)
        #expect(throws: (any Error).self) { try GeminiSpeechOutput.makeRequest(text: "hello", model: model, apiKey: "test-only") }
    }

    @Test func rejectsWrongModelVoiceAndHeaderInjection() {
        #expect(throws: MAIVoiceError.self) { try MAIVoiceSpeechOutput.makeRequest(text: "hello", model: .appleSystem, voice: "ko-KR-Harper:MAI-Voice-2.1", apiKey: "test-only") }
        #expect(throws: MAIVoiceError.self) { try MAIVoiceSpeechOutput.makeRequest(text: "hello", model: .maiVoice21Flash, voice: "ko-KR-Harper:MAI-Voice-2.1", apiKey: "test-only") }
        #expect(throws: MAIVoiceError.self) { try MAIVoiceSpeechOutput.makeRequest(text: "hello", model: .maiVoice21, voice: "ko-KR-Harper:MAI-Voice-2.1", apiKey: "test\r\nother: header") }
    }

    @Test func catalogChoosesOnlyPublishedVoicesForTargetLanguage() throws {
        let data = Data(#"{"data":[{"id":"microsoft/mai-voice-2.1","supported_voices":["ko-KR-Haena:MAI-Voice-2.1","ko-KR-Harper:MAI-Voice-2.1","en-US-Harper:MAI-Voice-2.1","ko-KR-Harper:MAI-Voice-2.1-Flash"]},{"id":"microsoft/mai-voice-2.1-flash","supported_voices":["ko-KR-Junho:MAI-Voice-2.1-Flash"]}]}"#.utf8)
        let catalog = try MAIVoiceCatalog.decode(data)
        let voices = try #require(catalog[SpeechSynthesisModel.maiVoice21.rawValue])
        #expect(voices.count == 3)
        #expect(try MAIVoiceCatalog.selectVoice(voices, languageID: "ko_KR", preferredName: "") == "ko-KR-Harper:MAI-Voice-2.1")
        #expect(try MAIVoiceCatalog.selectVoice(voices, languageID: "ko-KR", preferredName: "ko-KR-Haena") == "ko-KR-Haena:MAI-Voice-2.1")
        #expect(try MAIVoiceCatalog.selectVoice(voices, languageID: "en-GB", preferredName: "") == "en-US-Harper:MAI-Voice-2.1")
        #expect(throws: MAIVoiceError.self) { try MAIVoiceCatalog.selectVoice(voices, languageID: "ja-JP", preferredName: "") }
        #expect(throws: MAIVoiceError.self) { try MAIVoiceCatalog.selectVoice(voices, languageID: "ko-KR", preferredName: "en-US-Harper") }
    }

    @Test func audioResponseRejectsJSONAndReportsOnlyStatus() throws {
        let url = try #require(URL(string: "https://openrouter.ai/api/v1/audio/speech"))
        let mp3 = try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "audio/mpeg"]))
        try MAIVoiceSpeechOutput.validateResponse(mp3)
        let json = try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"]))
        #expect(throws: MAIVoiceError.self) { try MAIVoiceSpeechOutput.validateResponse(json) }
        let failure = try #require(HTTPURLResponse(url: url, statusCode: 401, httpVersion: nil, headerFields: [:]))
        #expect(throws: MAIVoiceError.self) { try MAIVoiceSpeechOutput.validateResponse(failure) }
        #expect(MAIVoiceError.http(401).localizedDescription.contains("401"))
    }

    @Test func responseBytesAreBounded() async throws {
        let bytes = AsyncStream<UInt8> { continuation in
            for byte in [UInt8(1), 2, 3] { continuation.yield(byte) }
            continuation.finish()
        }
        #expect(try await MAIVoiceSpeechOutput.collect(bytes, maximumBytes: 3) == Data([1, 2, 3]))
        let oversized = AsyncStream<UInt8> { continuation in
            for _ in 0..<4 { continuation.yield(1) }
            continuation.finish()
        }
        await #expect(throws: MAIVoiceError.self) { try await MAIVoiceSpeechOutput.collect(oversized, maximumBytes: 3) }
    }

    @Test func redirectNeverForwardsOpenRouterKey() throws {
        let url = try #require(URL(string: "https://openrouter.ai/api/v1/audio/speech"))
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let response = try #require(HTTPURLResponse(url: url, statusCode: 302, httpVersion: nil, headerFields: [:]))
        var proposed: URLRequest? = URLRequest(url: URL(string: "https://attacker.example")!)
        MAIVoiceRejectRedirects().urlSession(session, task: session.dataTask(with: url), willPerformHTTPRedirection: response,
                                           newRequest: proposed!, completionHandler: { proposed = $0 })
        #expect(proposed == nil)
        let query = OpenRouterAPIKeyStore.presenceQuery()
        #expect(query[kSecReturnData as String] == nil)
        #expect(query[kSecUseAuthenticationUI as String] as? String == kSecUseAuthenticationUISkip as String)
    }

    @Test @MainActor func stopBeforeWorkerStartsPreventsCredentialReadAndFailure() async {
        var reads = 0
        var failures = 0
        let output = MAIVoiceSpeechOutput(keyProvider: { reads += 1; return nil })
        output.onFailure = { _ in failures += 1 }
        output.speak("hello", model: .maiVoice21, language: .english, voiceName: "")
        output.stop()
        await Task.yield()
        #expect(reads == 0)
        #expect(failures == 0)
    }

    @Test @MainActor func stopDuringCatalogFetchPreventsPaidSpeechRequest() async throws {
        MAIVoiceCatalogStub.reset()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MAIVoiceCatalogStub.self]
        let catalog = MAIVoiceCatalog(configuration: config)
        let output = MAIVoiceSpeechOutput(configuration: config, catalog: catalog, keyProvider: { "test-only" })
        var failures = 0
        output.onFailure = { _ in failures += 1 }
        output.speak("hello", model: .maiVoice21, language: .english, voiceName: "")
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !MAIVoiceCatalogStub.isWaiting, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        #expect(MAIVoiceCatalogStub.isWaiting)
        output.stop()
        MAIVoiceCatalogStub.releaseCatalog()
        try await Task.sleep(for: .milliseconds(50))
        #expect(MAIVoiceCatalogStub.paidRequests == 0)
        #expect(failures == 0)
    }

    @Test @MainActor func streamingAndVoiceSelectionsRestoreWithoutChangingDefault() throws {
        let name = "MAIModelTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        defer { defaults.removePersistentDomain(forName: name); try? FileManager.default.removeItem(at: directory) }
        let session = TranslationSessionStore(modelAvailabilityProvider: { _, _ in [:] }, settingsDefaults: defaults, transcriptsDirectoryURL: directory)
        #expect(session.azureTranscriptionModel == .transcribe2)
        #expect(session.speechSynthesisModel == .appleSystem)
        session.useAzureMAIMode()
        session.hasAzureSpeechAPIKey = true
        session.azureTranscriptionModel = .transcribe2Streaming
        #expect(session.startReadinessAssessment().issue == .azureConfigurationMissing)
        session.maiStreamingEndpoint = "https://example.services.ai.azure.com"
        #expect(!session.hasAzureConfiguration)
        session.maiStreamingDeployment = "my-streaming-deployment"
        #expect(session.hasAzureConfiguration)
        session.speechSynthesisModel = .maiVoice21Flash
        session.maiVoiceName = "ko-KR-Haena"
        let restored = TranslationSessionStore(modelAvailabilityProvider: { _, _ in [:] }, settingsDefaults: defaults, transcriptsDirectoryURL: directory)
        #expect(restored.azureTranscriptionModel == .transcribe2Streaming)
        #expect(restored.maiStreamingEndpoint == session.maiStreamingEndpoint)
        #expect(restored.maiStreamingDeployment == session.maiStreamingDeployment)
        #expect(restored.speechSynthesisModel == .maiVoice21Flash)
        #expect(restored.maiVoiceName == "ko-KR-Haena")
        session.isRunning = true
        session.azureTranscriptionModel = .transcribe2
        #expect(session.azureTranscriptionModel == .transcribe2Streaming)
        session.isRunning = false
    }

    @Test @MainActor func emptyStreamingFinalRestoresOverlayAndStopKeepsTailTranslation() async throws {
        let name = "MAITailTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        defer { defaults.removePersistentDomain(forName: name); try? FileManager.default.removeItem(at: directory) }
        let session = TranslationSessionStore(modelAvailabilityProvider: { _, _ in [:] }, settingsDefaults: defaults, transcriptsDirectoryURL: directory)
        session.setFloatingCaptionPresentationActive(true)
        session.sourceLanguage = .english
        session.targetLanguage = .korean
        session.useAzureMAIMode()
        session.azureTranscriptionModel = .transcribe2Streaming
        session.azureTranslationForTesting = { text in
            try await Task.sleep(for: .milliseconds(50))
            return "번역: " + text
        }
        let pipeline = session.activateLiveCallbackPipelineForTesting()
        session.deliverAzureTranscriptForTesting("discarded interim", isFinal: false, generation: pipeline.generation)
        #expect(session.lines.last?.isFinal == false)
        session.deliverAzureTranscriptForTesting("", isFinal: true, generation: pipeline.generation)
        #expect(session.lines.isEmpty)
        #expect(session.floatingSourceText.isEmpty)
        session.deliverAzureTranscriptForTesting("last sentence", isFinal: false, generation: pipeline.generation)
        session.deliverAzureTranscriptForTesting("last sentence", isFinal: true, generation: pipeline.generation)
        #expect(session.lines.count == 1)
        session.stop()
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while session.isRunning, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        #expect(!session.isRunning)
        #expect(session.lines.last?.translatedText == "번역: last sentence")
        session.deliverAzureTranscriptForTesting("stale result", isFinal: true, generation: pipeline.generation)
        #expect(session.lines.count == 1)
    }
}
