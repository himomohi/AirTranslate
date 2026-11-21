import CoreMedia
import Foundation
import Testing
@testable import AirTranslate

@Suite(.serialized)
@MainActor
struct HyMTSessionTests {
    @Test func firstLaunchKeepsAppleAsDefaultAndDoesNotStartDownload() throws {
        let fixture = try HyMTSessionFixture()
        defer { fixture.cleanup() }
        let session = fixture.session
        #expect(ProcessingEngine.current(for: session) == .apple)
        #expect(session.selectedModel == .appleSystem)
        #expect(!session.isUsingHyMT)
        #expect(!session.isHyMTModelInstalled)
        #expect(!session.isHyMTModelDownloading)
        #expect(session.hyMTDownloadProgress == 0)
        #expect(!fixture.defaults.bool(forKey: "hyMTEnabled"))
    }

    @Test func modelOptionNeedsNoKeyOrServerConfigurationAndOpensGeneralSettings() throws {
        let fixture = try HyMTSessionFixture()
        defer { fixture.cleanup() }
        let session = fixture.session
        fixture.setKeys(false)
        #expect(ProcessingEngine.hyMT.credentialProvider == nil)
        #expect(ProcessingEngine.hyMT.hasRequiredKey(in: session))
        #expect(ProcessingEngine.hyMT.canSelect(in: session))
        #expect(ProcessingEngine.hyMT.select(in: session))
        #expect(session.isUsingHyMT)
        #expect(ProcessingEngine.current(for: session) == .hyMT)
        #expect(!session.isUsingAppleTextTranslation)
        #expect(!session.isTranscribeOnlyMode)
        #expect(!session.isHyMTModelDownloading)
        // 다운로드 전에도 옵션 선택은 허용하고, 시작은 모델 준비 상태로 막는다.
        #expect(!session.isHyMTModelInstalled)
        #expect(session.startReadinessAssessment().issue == .hyMTModelMissing)
        ProcessingEngine.hyMT.requestSettings(in: session)
        #expect(session.requestedSettingsCategoryID == "general")
        #expect(session.requestedAPIKeyProvider == nil)
    }

    @Test func selectedEngineAndLanguagesSurviveRelaunch() throws {
        let fixture = try HyMTSessionFixture()
        defer { fixture.cleanup() }
        let session = fixture.session
        session.sourceLanguage = .english
        session.targetLanguage = .korean
        session.useHyMTMode()
        #expect(fixture.defaults.bool(forKey: "hyMTEnabled"))
        let restored = fixture.makeSession()
        defer { restored.prepareForTermination() }
        #expect(restored.isUsingHyMT)
        #expect(ProcessingEngine.current(for: restored) == .hyMT)
        #expect(restored.selectedModel == .appleSystem)
        #expect(restored.sourceLanguage == .english)
        #expect(restored.targetLanguage == .korean)
        #expect(!restored.openAITranscriptionModel.isEnabled)
        #expect(!restored.openAITranslationModel.isEnabled)
        #expect(!restored.geminiTranslationModel.isEnabled)
        #expect(!restored.metaTranscriptionModel.isEnabled)
        #expect(!restored.nariTranscriptionModel.isEnabled)
        #expect(!restored.grokTranscriptionModel.isEnabled)
        #expect(!restored.qwenTranslationModel.isEnabled)
        #expect(!restored.isUsingAzureMAI)
    }

    @Test func switchingEveryProviderTurnsHyMTOffAndReenablingClearsOtherProviders() throws {
        let fixture = try HyMTSessionFixture()
        defer { fixture.cleanup() }
        let session = fixture.session
        fixture.setKeys(true)
        for engine in ProcessingEngine.allCases where engine != .hyMT {
            session.useHyMTMode()
            #expect(session.isUsingHyMT)
            #expect(engine.select(in: session))
            #expect(ProcessingEngine.current(for: session) == engine)
            #expect(!session.isUsingHyMT)
            #expect(!fixture.defaults.bool(forKey: "hyMTEnabled"))

            #expect(ProcessingEngine.hyMT.select(in: session))
            #expect(ProcessingEngine.current(for: session) == .hyMT)
            #expect(!session.isTranscribeOnlyMode)
            #expect(!session.openAITranscriptionModel.isEnabled)
            #expect(!session.openAITranslationModel.isEnabled)
            #expect(!session.geminiTranslationModel.isEnabled)
            #expect(!session.metaTranscriptionModel.isEnabled)
            #expect(!session.nariTranscriptionModel.isEnabled)
            #expect(!session.grokTranscriptionModel.isEnabled)
            #expect(!session.qwenTranslationModel.isEnabled)
            #expect(!session.isUsingAzureMAI)
        }
    }

    @Test func captureAndPendingStartRejectEngineChangesAndDirectHyMTWrites() throws {
        let fixture = try HyMTSessionFixture()
        defer { fixture.cleanup() }
        let session = fixture.session
        fixture.setKeys(true)
        for initiallyHyMT in [false, true] {
            session.isRunning = false
            session.isStarting = false
            if initiallyHyMT { session.useHyMTMode() }
            else { session.useAppleDefaultMode() }
            let originalEngine = ProcessingEngine.current(for: session)
            for (running, starting, paused) in [(true, false, false), (false, true, false), (true, false, true)] {
                session.isRunning = running
                session.isStarting = starting
                session.isPaused = paused
                session.isUsingHyMT = !initiallyHyMT
                session.useHyMTMode()
                for engine in ProcessingEngine.allCases { #expect(!engine.select(in: session)) }
                #expect(session.isUsingHyMT == initiallyHyMT)
                #expect(ProcessingEngine.current(for: session) == originalEngine)
                #expect(fixture.defaults.bool(forKey: "hyMTEnabled") == initiallyHyMT)
            }
            session.isRunning = false
            session.isStarting = false
            session.isPaused = false
        }
    }

    @Test func finalAppleCaptionUsesHyMTAndPersistsBothTextsWithoutCallingAppleTranslation() async throws {
        let probe = HyMTAppleTranslationProbe()
        let appleService = AppleTranslationService { text, _ in
            await probe.record(text)
            return "잘못된 Apple 번역"
        }
        let fixture = try HyMTSessionFixture(appleService: appleService)
        defer { fixture.cleanup() }
        let session = fixture.session
        session.sourceLanguage = .english
        session.targetLanguage = .korean
        session.isAppleSourceAutoDetectionEnabled = false
        session.useHyMTMode()
        session.isDubbingEnabled = false
        session.isTranscriptPersistenceEnabled = true
        session.savedTranscriptContentMode = .originalAndTranslation
        var translatedSources: [String] = []
        session.hyMTTranslationForTesting = { text in
            translatedSources.append(text)
            return "안녕하세요."
        }
        _ = session.activateLiveCallbackPipelineForTesting()
        let source = "Hello."
        session.receiveCaptionForTesting(source, metadata: .init(
            segmentID: "hymt-final", revision: 1, isFinal: true,
            audioRange: CMTimeRange(start: .zero, duration: CMTime(seconds: 1, preferredTimescale: 1_000)),
            sourceText: source, emittedAt: Date()
        ))
        #expect(await waitUntil { session.lines.last?.translatedText == "안녕하세요." })
        #expect(translatedSources == [source])
        #expect(await probe.count == 0)
        #expect(session.lines.last?.sourceText == source)
        #expect(session.lines.last?.isFinal == true)
        session.stop()
        #expect(!session.isRunning)
        let files = try FileManager.default.contentsOfDirectory(at: fixture.directory, includingPropertiesForKeys: nil)
        let original = try #require(files.first { $0.lastPathComponent.contains("original") })
        let translation = try #require(files.first { $0.lastPathComponent.contains("translation") })
        #expect(try String(contentsOf: original, encoding: .utf8) == source)
        #expect(try String(contentsOf: translation, encoding: .utf8) == "안녕하세요.")
    }

    @Test func terminologyPersistsIsBoundedAndStaysLockedDuringCaptureAndStart() throws {
        let fixture = try HyMTSessionFixture()
        defer { fixture.cleanup() }
        let session = fixture.session
        #expect(session.hyMTTerminologyText.isEmpty)
        session.hyMTTerminologyText = "ProductKit = 제품 키트\nMCP"
        let restored = fixture.makeSession()
        defer { restored.prepareForTermination() }
        #expect(restored.hyMTTerminologyText == "ProductKit = 제품 키트\nMCP")
        for (running, starting) in [(true, false), (false, true)] {
            session.isRunning = running
            session.isStarting = starting
            session.hyMTTerminologyText = "Changed"
            #expect(session.hyMTTerminologyText == "ProductKit = 제품 키트\nMCP")
        }
        session.isRunning = false
        session.isStarting = false
        session.hyMTTerminologyText = String(repeating: "😀", count: 4_010)
        #expect(session.hyMTTerminologyText.count == 4_000)
        #expect(fixture.defaults.string(forKey: "hyMTTerminologyText") == String(repeating: "😀", count: 4_000))
    }

    @Test func contextUsesOnlyTwoPriorCompletedCaptionsAndRepeatedTextIsNotCached() async throws {
        let fixture = try HyMTSessionFixture()
        defer { fixture.cleanup() }
        let session = fixture.session
        session.sourceLanguage = .english
        session.targetLanguage = .korean
        session.isAppleSourceAutoDetectionEnabled = false
        session.useHyMTMode()
        session.isDubbingEnabled = false
        session.hyMTTerminologyText = "ProductKit = 제품 키트\nMCP"
        var calls = 0
        session.hyMTTranslationForTesting = { _ in calls += 1; return "완료된 번역 \(calls)." }
        _ = session.activateLiveCallbackPipelineForTesting()
        for (index, source) in ["First sentence.", "Second sentence.", "Repeated sentence.", "Repeated sentence."].enumerated() {
            session.receiveCaptionForTesting(source, metadata: .init(segmentID: "context-\(index)", revision: 1, isFinal: true,
                audioRange: CMTimeRange(start: CMTime(seconds: Double(index * 2), preferredTimescale: 1_000),
                                       duration: CMTime(seconds: 1, preferredTimescale: 1_000)),
                sourceText: source, emittedAt: Date()))
            #expect(await waitUntil { session.lines.last?.translatedText == "완료된 번역 \(index + 1)." })
        }
        #expect(calls == 4)
        let options = session.hyMTOptionsForTesting(source: .english, target: .korean, currentText: "Next sentence.")
        #expect(options.terminology == ["ProductKit = 제품 키트", "MCP"])
        #expect(options.context == "Repeated sentence.\nRepeated sentence.")
        #expect(session.hyMTOptionsForTesting(source: .english, target: .korean, currentText: "Repeated sentence.").context == "First sentence.\nSecond sentence.")
        #expect(session.hyMTOptionsForTesting(source: .korean, target: .english, currentText: "다른 언어").context.isEmpty)
        session.stop()
        #expect(!session.isRunning)
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !condition(), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(5))
        }
        return condition()
    }
}

@MainActor
private final class HyMTSessionFixture {
    let name = "HyMTSessionTests.\(UUID().uuidString)"
    let defaults: UserDefaults
    let directory: URL
    let appleService: AppleTranslationService
    lazy var session = makeSession()

    init(appleService: AppleTranslationService = AppleTranslationService()) throws {
        defaults = try #require(UserDefaults(suiteName: name))
        directory = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(name)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.appleService = appleService
    }

    func makeSession() -> TranslationSessionStore {
        TranslationSessionStore(appleTranslationService: appleService,
            modelAvailabilityProvider: { _, _ in [:] }, settingsDefaults: defaults, transcriptsDirectoryURL: directory)
    }

    func setKeys(_ enabled: Bool) {
        session.hasOpenAIAPIKey = enabled
        session.hasGeminiAPIKey = enabled
        session.hasMetaAPIKey = enabled
        session.hasAzureSpeechAPIKey = enabled
        session.hasNariAPIKey = enabled
        session.hasGrokAPIKey = enabled
        session.hasQwenAPIKey = enabled
    }

    func cleanup() {
        session.stop()
        session.prepareForTermination()
        session.isRunning = false
        session.isStarting = false
        defaults.removePersistentDomain(forName: name)
        try? FileManager.default.removeItem(at: directory)
    }
}

private actor HyMTAppleTranslationProbe {
    private(set) var count = 0
    func record(_ text: String) { count += 1 }
}
