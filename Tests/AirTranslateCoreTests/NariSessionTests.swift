import Foundation
import Testing
@testable import AirTranslate

@Suite(.serialized)
@MainActor
struct NariSessionTests {
    private func withSession(_ body: (TranslationSessionStore, UserDefaults, URL) throws -> Void) throws {
        let name = "NariSessionTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let session = TranslationSessionStore(modelAvailabilityProvider: { _, _ in [:] },
            settingsDefaults: defaults, transcriptsDirectoryURL: directory)
        defer {
            session.finishNariPipelineForTesting()
            defaults.removePersistentDomain(forName: name)
            try? FileManager.default.removeItem(at: directory)
        }
        try body(session, defaults, directory)
    }

    @Test func preservesDefaultAndSelectsNariAsSourceOnly() throws {
        try withSession { session, _, _ in
            #expect(session.selectedModel == .appleSystem)
            #expect(!session.isUsingNariSTT)
            session.useGeminiMode(.gemini35LiveTranslate)
            session.useNariSTTMode()
            #expect(session.isUsingNariSTT)
            #expect(session.nariTranscriptionModel == .qwen3ASRFast)
            #expect(session.isTranscribeOnlyMode)
            #expect(!session.isUsingGemini && !session.isUsingOpenAIRealtime && !session.isUsingMetaScribe)
            #expect(session.floatingCaptionDisplayMode == .original)
            #expect(!session.isDubbingEnabled)
            #expect(ProcessingEngine.current(for: session) == .nari)
        }
    }

    @Test func switchingAwayDisablesNariAndOutputModePreservesIt() throws {
        try withSession { session, _, _ in
            session.sourceLanguage = .english
            session.targetLanguage = .korean
            session.useNariSTTMode()
            session.useTranslationMode()
            #expect(session.isUsingNariSTT && !session.isTranscribeOnlyMode)
            session.useTranscribeOnlyMode()
            #expect(session.isUsingNariSTT && session.isTranscribeOnlyMode)
            session.useGPTRealtimeMode()
            #expect(!session.isUsingNariSTT)
            session.useNariSTTMode()
            session.useAzureMAIMode()
            #expect(!session.isUsingNariSTT)
            session.useNariSTTMode()
            session.useMetaScribeMode()
            #expect(!session.isUsingNariSTT)
            session.useNariSTTMode()
            session.useAppleDefaultMode()
            #expect(!session.isUsingNariSTT)
        }
    }

    @Test func sourceOnlySelectionRestoresWithoutChangingOtherPreferences() throws {
        try withSession { session, defaults, directory in
            session.sourceLanguage = .english
            session.targetLanguage = .korean
            session.useNariSTTMode()
            session.nariTranscriptionModel = .qwen3ASRFast
            session.isNariSourceAutoDetectionEnabled = true
            session.audioInputSource = .microphone
            let restored = TranslationSessionStore(modelAvailabilityProvider: { _, _ in [:] },
                settingsDefaults: defaults, transcriptsDirectoryURL: directory)
            #expect(restored.nariTranscriptionModel == .qwen3ASRFast)
            #expect(restored.isNariSourceAutoDetectionEnabled)
            #expect(restored.isTranscribeOnlyMode)
            #expect(restored.audioInputSource == .microphone)
            #expect(!restored.isTranscriptPersistenceEnabled)
        }
    }

    @Test func legacyFreeSelectionRestoresButBlocksStartUntilGAModelIsExplicitlySelected() throws {
        try withSession { session, defaults, directory in
            session.useNariSTTMode()
            session.nariTranscriptionModel = .qwen3ASRFastFree
            session.hasNariAPIKey = true
            let restored = TranslationSessionStore(modelAvailabilityProvider: { _, _ in [:] },
                settingsDefaults: defaults, transcriptsDirectoryURL: directory)
            restored.hasNariAPIKey = true
            #expect(restored.nariTranscriptionModel == .qwen3ASRFastFree)
            #expect(restored.startReadinessAssessment().issue == .nariLegacyFreeModelSelected)
            restored.start()
            #expect(!restored.isStarting && !restored.isRunning)
            #expect(restored.captureStartRecoveryAction == .generalSettings)
            restored.nariTranscriptionModel = .qwen3ASRFast
            #expect(restored.startReadinessAssessment().canStart)
            #expect(restored.captureStartRecoveryAction == nil)
            #expect(restored.captureStartFailureMessage == nil)
            #expect(restored.statusMessage == AppText.ready)

            restored.nariTranscriptionModel = .qwen3ASRFastFree
            restored.start()
            restored.useAppleDefaultMode()
            #expect(restored.captureStartRecoveryAction == nil)
            #expect(restored.captureStartFailureMessage == nil)
            #expect(restored.statusMessage == AppText.ready)
        }
    }

    @Test func keyReadinessPrecedesAssetsAndDoesNotEraseExistingText() throws {
        try withSession { session, _, _ in
            session.useNariSTTMode()
            session.lines = [CaptionLine(sourceText: "보존할 기록", translatedText: "", createdAt: Date(), isFinal: true)]
            session.hasNariAPIKey = false
            #expect(session.startReadinessAssessment().issue == .nariAPIKeyMissing)
            session.start()
            #expect(!session.isStarting && !session.isRunning)
            #expect(session.lines.first?.sourceText == "보존할 기록")
            #expect(session.captureStartRecoveryAction == .apiKeys)
            session.hasNariAPIKey = true
            #expect(session.startReadinessAssessment().canStart)
        }
    }

    @Test func configurationUsesSixteenKilohertzAndFencesNariSettings() {
        #expect(CaptureStartRecoveryAction.forFailure(NariTranscriptionError.authentication, audioInputSource: .systemAudio) == .apiKeys)
        func configuration(_ auto: Bool) -> StartConfiguration {
            StartConfiguration(audioInputSource: .systemAudio, microphoneDeviceUniqueID: nil,
                sourceLanguage: .korean, targetLanguage: .english, selectedModel: .appleSpeechOnly,
                openAITranscriptionModel: .off, openAITranslationModel: .off, geminiTranslationModel: .off,
                nariTranscriptionModel: .qwen3ASRFast, usesNariSourceAutoDetection: auto,
                usesAppleSourceAutoDetection: false)
        }
        #expect(configuration(false).sampleRate == 16_000)
        #expect(configuration(false).isTranscribeOnlyMode)
        var lifecycle = PipelineLifecycleState()
        let generation = lifecycle.beginStart(configuration: configuration(false))
        #expect(lifecycle.validateStart(generation: generation, currentConfiguration: configuration(true)) == .configurationChanged)
    }

    @Test func replacesPartialAndKeepsRepeatedFinalUtterancesSeparate() throws {
        try withSession { session, _, _ in
            session.useNariSTTMode()
            let generation = session.activateLiveCallbackPipelineForTesting().generation
            @MainActor func deliver(_ id: String, _ text: String, final: Bool) {
                session.deliverNariTranscriptForTesting(.init(itemID: id, text: text, isFinal: final,
                    languageCode: final ? "en" : nil, revision: final ? nil : 1), generation: generation)
            }
            deliver("one", "I scream", final: false)
            deliver("one", "Ice cream", final: false)
            #expect(session.lines.map(\.sourceText) == ["Ice cream"])
            deliver("one", "Ice cream is delicious.", final: true)
            deliver("one", "late partial", final: false)
            deliver("two", "Ice cream is delicious.", final: true)
            #expect(session.lines.count == 2)
            #expect(session.lines.allSatisfy { $0.sourceText == "Ice cream is delicious." && $0.isFinal && $0.translatedText.isEmpty })
        }
    }

    @Test func emptyFinalRemovesHypothesisAndStaleGenerationCannotWrite() throws {
        try withSession { session, _, _ in
            session.useNariSTTMode()
            let generation = session.activateLiveCallbackPipelineForTesting().generation
            session.deliverNariTranscriptForTesting(.init(itemID: "one", text: "hallucination", isFinal: false,
                languageCode: nil, revision: 1), generation: generation)
            session.deliverNariTranscriptForTesting(.init(itemID: "one", text: "", isFinal: true,
                languageCode: nil, revision: nil), generation: generation)
            #expect(session.lines.isEmpty)
            session.deliverNariTranscriptForTesting(.init(itemID: "two", text: "stale", isFinal: true,
                languageCode: "en", revision: nil), generation: generation &- 1)
            #expect(session.lines.isEmpty)
        }
    }

    @Test func pausedFinalIsPreservedAndPersistenceRemainsOptIn() throws {
        try withSession { session, _, directory in
            session.useNariSTTMode()
            let generation = session.activateLiveCallbackPipelineForTesting().generation
            session.isPaused = true
            session.deliverNariTranscriptForTesting(.init(itemID: "one", text: "마지막 발화", isFinal: true,
                languageCode: "ko", revision: nil), generation: generation)
            #expect(session.lines.first?.sourceText == "마지막 발화")
            session.finishNariPipelineForTesting()
            let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            #expect(files.isEmpty)
        }
    }

    @Test func completedTurnsSaveInOrderWithoutSpeculativePartial() throws {
        try withSession { session, _, directory in
            session.useNariSTTMode()
            session.isTranscriptPersistenceEnabled = true
            let generation = session.activateLiveCallbackPipelineForTesting().generation
            for id in ["one", "two"] {
                session.deliverNariTranscriptForTesting(.init(itemID: id, text: "Yes.", isFinal: true,
                    languageCode: "en", revision: nil), generation: generation)
            }
            session.deliverNariTranscriptForTesting(.init(itemID: "three", text: "unfinished", isFinal: false,
                languageCode: nil, revision: 1), generation: generation)
            session.finishNariPipelineForTesting()
            let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            let original = try #require(files.first { $0.pathExtension == "txt" })
            let text = try String(contentsOf: original, encoding: .utf8)
            #expect(text.contains("Yes.\nYes."))
            #expect(!text.contains("unfinished"))
        }
    }

    @Test func normalStopWaitsForTranslationAndSystemMenuUsesSameDrain() async throws {
        let name = "NariFinalTranslationTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let session = TranslationSessionStore(modelAvailabilityProvider: { _, _ in [:] },
            settingsDefaults: defaults, transcriptsDirectoryURL: directory)
        defer {
            session.finishNariPipelineForTesting()
            defaults.removePersistentDomain(forName: name)
            try? FileManager.default.removeItem(at: directory)
        }
        session.sourceLanguage = .english
        session.targetLanguage = .korean
        session.useNariSTTMode()
        session.useTranslationMode()
        session.isTranscriptPersistenceEnabled = true
        session.savedTranscriptContentMode = .originalAndTranslation
        session.nariTranslationForTesting = { text in
            try await Task.sleep(for: .milliseconds(60))
            return text == "First." ? "첫 문장." : "마지막 문장."
        }
        let generation = session.activateLiveCallbackPipelineForTesting().generation
        for (id, text) in [("first", "First."), ("last", "Last.")] {
            session.deliverNariTranscriptForTesting(.init(itemID: id, text: text, isFinal: true,
                languageCode: "en", revision: nil), generation: generation)
        }
        session.stopNariFromSystemMenuForTesting(generation: generation)
        #expect(session.isFinishingNariSTT)
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while session.isRunning, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(!session.isRunning)
        #expect(session.lines.map(\.translatedText) == ["첫 문장.", "마지막 문장."])
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        let translated = try #require(files.first { $0.lastPathComponent.contains("translation") })
        let content = try String(contentsOf: translated, encoding: .utf8)
        #expect(content.contains("첫 문장.\n마지막 문장."))
    }
}
