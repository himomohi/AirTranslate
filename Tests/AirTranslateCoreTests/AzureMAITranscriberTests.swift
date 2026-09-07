import AVFoundation
import Foundation
import Testing
@testable import AirTranslate

private final class AzureStub: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: request.value(forHTTPHeaderField: "Ocp-Apim-Subscription-Key") == "test-rejected" ? 401 : 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(#"{"combinedPhrases":[{"text":"안녕하세요"}]}"#.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private actor AzureResults {
    var texts: [String] = []
    var failures = 0
    func add(_ result: Result<String, AzureMAIError>) {
        switch result {
        case .success(let text): texts.append(text)
        case .failure: failures += 1
        }
    }
}

@Suite(.serialized)
struct AzureMAITranscriberTests {
    @Test func restContract() throws {
        let request = try AzureMAITranscriber.request(endpoint: "https://example.cognitiveservices.azure.com/", key: "test-only", pcm: Data([0, 0]), language: "ko")
        #expect(request.url?.absoluteString == "https://example.cognitiveservices.azure.com/speechtotext/transcriptions:transcribe?api-version=2025-10-15")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Ocp-Apim-Subscription-Key") == "test-only")
        let body = String(decoding: try #require(request.httpBody), as: UTF8.self)
        #expect(body.contains(#""enhancedMode":{"enabled":true,"model":"MAI-Transcribe-2"}"#))
        #expect(body.contains(#""locales":["ko"]"#))
        #expect(body.contains("name=\"audio\"; filename=\"audio.wav\""))
        #expect(body.contains("RIFF"))
        #expect(!body.contains("test-only"))
        let wav = AzureMAITranscriber.wav(Data([1, 2]))
        #expect(wav.count == 46)
        #expect(Array(wav[24..<28]) == [0x80, 0x3e, 0, 0])
        #expect(Array(wav.suffix(2)) == [1, 2])
    }

    @Test(arguments: ["http://example.cognitiveservices.azure.com", "https://evil.example", "https://example.cognitiveservices.azure.com.evil.example", "https://user:password@example.cognitiveservices.azure.com", "https://example.cognitiveservices.azure.com?key=value", "https://example.cognitiveservices.azure.com/path", "https://127.0.0.1"])
    func rejectsNonResourceEndpoints(_ endpoint: String) {
        #expect(throws: AzureMAIError.self) { try AzureMAITranscriber.endpointURL(endpoint) }
    }

    @Test func responseParsingAndEmptySpeech() throws {
        #expect(try AzureMAITranscriber.transcript(Data(#"{"combinedPhrases":[{"text":"hello"},{"text":"world"}]}"#.utf8)) == "hello\nworld")
        #expect(try AzureMAITranscriber.transcript(Data(#"{"combinedPhrases":[]}"#.utf8)).isEmpty)
        #expect(throws: AzureMAIError.self) { try AzureMAITranscriber.transcript(Data(#"{"error":"private server detail"}"#.utf8)) }
        #expect(!AzureMAIError.http(401).localizedDescription.contains("test-only"))
    }

    @Test func stopFlushesShortFinalSegmentAndPauseExcludesAudio() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AzureStub.self]
        let service = AzureMAITranscriber(configuration: configuration)
        let results = AzureResults()
        try service.start(endpoint: "https://example.cognitiveservices.azure.com", key: "test-only", language: "ko") {
            await results.add($0)
        }
        let sample = try makeSample()
        #expect(AzureMAITranscriber.pcm16(sample)?.count == 3_200)
        service.append(sample)
        service.setPaused(true)
        service.append(sample)
        service.setPaused(false)
        service.append(sample)
        await service.finish()
        #expect(await results.texts == ["안녕하세요", "안녕하세요"])
        #expect(await results.failures == 0)
        service.stop()
        service.append(sample)
        #expect(await results.texts.count == 2)
    }

    @Test func finalRequestFailureIsDeliveredBeforeFinishReturns() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AzureStub.self]
        let service = AzureMAITranscriber(configuration: configuration)
        let results = AzureResults()
        try service.start(endpoint: "https://example.cognitiveservices.azure.com", key: "test-rejected", language: "ko") {
            await results.add($0)
        }
        service.append(try makeSample())
        await service.finish()
        #expect(await results.failures == 1)
        #expect(await results.texts.isEmpty)
        service.stop()
    }

    @Test @MainActor func optionalModeRestoresAndSwitchesWithoutChangingDefault() throws {
        let suite = "AzureMAITests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(suite, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        let store = TranslationSessionStore(
            modelAvailabilityProvider: { _, _ in [:] },
            settingsDefaults: defaults,
            transcriptsDirectoryURL: directory
        )
        #expect(!store.isUsingAzureMAI)
        #expect(store.selectedModel == .appleSystem)
        store.useGPTRealtimeMode()
        store.sourceLanguage = .english
        store.targetLanguage = .korean
        store.useAzureMAIMode()
        #expect(store.isUsingAzureMAI)
        #expect(!store.isUsingOpenAIRealtime)
        #expect(!store.isUsingMetaScribe)
        store.hasAzureSpeechAPIKey = false
        #expect(store.startReadinessAssessment().issue == .azureConfigurationMissing)
        store.azureSpeechEndpoint = "https://example.cognitiveservices.azure.com"
        #expect(defaults.bool(forKey: "azureMAIEnabled"))
        let restoredDefaults = try #require(UserDefaults(suiteName: suite))
        let restored = TranslationSessionStore(
            modelAvailabilityProvider: { _, _ in [:] },
            settingsDefaults: restoredDefaults,
            transcriptsDirectoryURL: directory
        )
        #expect(restored.isUsingAzureMAI)
        #expect(restored.azureSpeechEndpoint == store.azureSpeechEndpoint)
        restored.useGeminiMode(.gemini35LiveTranslate)
        #expect(!restored.isUsingAzureMAI)
        restored.useAzureMAIMode()
        restored.useMetaScribeMode()
        #expect(!restored.isUsingAzureMAI)
        restored.useAzureMAIMode()
        restored.useAppleDefaultMode()
        #expect(!restored.isUsingAzureMAI)
    }

    private func makeSample() throws -> CMSampleBuffer {
        var description = AudioStreamBasicDescription(mSampleRate: 16_000, mFormatID: kAudioFormatLinearPCM, mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked, mBytesPerPacket: 2, mFramesPerPacket: 1, mBytesPerFrame: 2, mChannelsPerFrame: 1, mBitsPerChannel: 16, mReserved: 0)
        var format: CMAudioFormatDescription?
        #expect(CMAudioFormatDescriptionCreate(allocator: kCFAllocatorDefault, asbd: &description, layoutSize: 0, layout: nil, magicCookieSize: 0, magicCookie: nil, extensions: nil, formatDescriptionOut: &format) == noErr)
        var block: CMBlockBuffer?
        #expect(CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: 3_200, blockAllocator: kCFAllocatorDefault, customBlockSource: nil, offsetToData: 0, dataLength: 3_200, flags: kCMBlockBufferAssureMemoryNowFlag, blockBufferOut: &block) == noErr)
        #expect(CMBlockBufferFillDataBytes(with: 0, blockBuffer: try #require(block), offsetIntoDestination: 0, dataLength: 3_200) == noErr)
        var sample: CMSampleBuffer?
        #expect(CMAudioSampleBufferCreateReadyWithPacketDescriptions(allocator: kCFAllocatorDefault, dataBuffer: try #require(block), formatDescription: try #require(format), sampleCount: 1_600, presentationTimeStamp: .zero, packetDescriptions: nil, sampleBufferOut: &sample) == noErr)
        return try #require(sample)
    }
}
