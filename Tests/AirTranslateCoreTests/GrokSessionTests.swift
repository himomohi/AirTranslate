import Foundation
import Testing
@testable import AirTranslate

@Suite(.serialized)
@MainActor
struct GrokSessionTests {
    private func withSession(_ body: (TranslationSessionStore, UserDefaults, URL) throws -> Void) throws {
        let name = "GrokSessionTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let session = TranslationSessionStore(modelAvailabilityProvider: { _, _ in [:] },
            settingsDefaults: defaults, transcriptsDirectoryURL: directory)
        defer {
            session.finishGrokPipelineForTesting()
            defaults.removePersistentDomain(forName: name)
            try? FileManager.default.removeItem(at: directory)
        }
        try body(session, defaults, directory)
    }

    @Test func preservesDefaultAndSelectsGrokAsSourceOnly() throws {
        try withSession { session, _, _ in
            #expect(session.selectedModel == .appleSystem)
            #expect(!session.isUsingGrokSTT)
            session.useGeminiMode(.gemini35LiveTranslate)
            session.useGrokSTTMode()
            #expect(session.isUsingGrokSTT)
            #expect(session.grokTranscriptionModel == .voiceTranscribe2)
            #expect(session.isTranscribeOnlyMode)
            #expect(!session.isUsingGemini && !session.isUsingOpenAIRealtime && !session.isUsingMetaScribe)
            #expect(session.floatingCaptionDisplayMode == .original)
            #expect(!session.isDubbingEnabled)
            #expect(ProcessingEngine.current(for: session) == .grok)
        }
    }

    @Test func switchingAwayDisablesGrokAndOutputModePreservesIt() throws {
        try withSession { session, _, _ in
            session.sourceLanguage = .english
            session.targetLanguage = .korean
            session.useGrokSTTMode()
            session.useTranslationMode()
            #expect(session.isUsingGrokSTT && !session.isTranscribeOnlyMode)
            session.useTranscribeOnlyMode()
            #expect(session.isUsingGrokSTT && session.isTranscribeOnlyMode)
            session.useGPTRealtimeMode()
            #expect(!session.isUsingGrokSTT)
            session.useGrokSTTMode()
            session.useAzureMAIMode()
            #expect(!session.isUsingGrokSTT)
            session.useGrokSTTMode()
            session.useMetaScribeMode()
            #expect(!session.isUsingGrokSTT)
            session.useGrokSTTMode()
            session.useAppleDefaultMode()
            #expect(!session.isUsingGrokSTT)
        }
    }

    @Test func switchingAwayClearsOnlyGrokConfigurationFailure() throws {
        try withSession { session, _, _ in
            for useApple in [true, false] {
                session.useGrokSTTMode()
                session.hasGrokAPIKey = false
                session.start()
                #expect(session.captureStartFailureMessage == GrokCopy.configurationRequired)
                if useApple { session.useAppleDefaultMode() } else { session.useGPTRealtimeMode() }
                #expect(session.captureStartFailureMessage == nil)
                #expect(session.captureStartRecoveryAction == nil)
                #expect(session.statusMessage == AppText.ready)
            }

            session.useGrokSTTMode()
            session.captureStartFailureMessage = "Unrelated capture failure"
            session.captureStartRecoveryAction = .retry
            session.statusMessage = "Unrelated capture failure"
            session.useAppleDefaultMode()
            #expect(session.captureStartFailureMessage == "Unrelated capture failure")
            #expect(session.captureStartRecoveryAction == .retry)
            #expect(session.statusMessage == "Unrelated capture failure")
        }
    }

    @Test func sourceOnlySelectionRestoresWithoutChangingOtherPreferences() throws {
        try withSession { session, defaults, directory in
            session.sourceLanguage = .english
            session.targetLanguage = .korean
            session.useGrokSTTMode()
            session.grokTranscriptionModel = .voiceTranscribe2
            session.isGrokSourceAutoDetectionEnabled = true
            session.audioInputSource = .microphone
            let restored = TranslationSessionStore(modelAvailabilityProvider: { _, _ in [:] },
                settingsDefaults: defaults, transcriptsDirectoryURL: directory)
            #expect(restored.grokTranscriptionModel == .voiceTranscribe2)
            #expect(restored.isGrokSourceAutoDetectionEnabled)
            #expect(restored.isTranscribeOnlyMode)
            #expect(restored.audioInputSource == .microphone)
            #expect(!restored.isTranscriptPersistenceEnabled)
        }
    }

    @Test func nariSelectionAndManualFormattingPreferenceRemainIndependent() throws {
        try withSession { session, defaults, directory in
            session.useNariSTTMode()
            let restored = TranslationSessionStore(modelAvailabilityProvider: { _, _ in [:] },
                settingsDefaults: defaults, transcriptsDirectoryURL: directory)
            #expect(restored.isUsingNariSTT && !restored.isUsingGrokSTT)
            session.useGrokSTTMode()
            #expect(!session.isUsingNariSTT)
            session.hasGrokAPIKey = true
            session.sourceLanguage = .init(id: "zh-Hans", title: "Chinese", locale: Locale(identifier: "zh-Hans"))
            #expect(session.startReadinessAssessment().canStart)
            session.isGrokSourceAutoDetectionEnabled = false
            #expect(session.startReadinessAssessment().issue == .grokLanguageUnsupported)
            session.sourceLanguage = .korean
            #expect(session.startReadinessAssessment().canStart)
        }
    }

    @Test func missingDetectedLanguageKeepsOriginalAndNeverSavesTranslationNotices() throws {
        try withSession { session, _, directory in
            session.useGrokSTTMode()
            session.useTranslationMode()
            session.isTranscriptPersistenceEnabled = true
            session.savedTranscriptContentMode = .originalAndTranslation
            let generation = session.activateLiveCallbackPipelineForTesting().generation
            session.deliverGrokTranscriptForTesting(.init(itemID: "first", text: "original", isFinal: true,
                languageCode: nil, revision: nil), generation: generation)
            session.deliverGrokTranscriptForTesting(.init(itemID: "pending", text: "unconfirmed", isFinal: false,
                languageCode: nil, revision: 1), generation: generation)
            #expect(session.lines.first?.translatedText == GrokCopy.translationLanguageUnavailable)
            #expect(session.lines.last?.translatedText == AppText.translating)
            session.finishGrokPipelineForTesting()
            for file in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) where file.pathExtension == "txt" {
                let text = try String(contentsOf: file, encoding: .utf8)
                #expect(!text.contains(GrokCopy.translationLanguageUnavailable))
                #expect(!text.contains(AppText.translating))
                #expect(!text.contains("unconfirmed"))
            }
        }
    }

    @Test func keyReadinessPrecedesAssetsAndDoesNotEraseExistingText() throws {
        try withSession { session, _, _ in
            session.useGrokSTTMode()
            session.lines = [CaptionLine(sourceText: "보존할 기록", translatedText: "", createdAt: Date(), isFinal: true)]
            session.hasGrokAPIKey = false
            #expect(session.startReadinessAssessment().issue == .grokAPIKeyMissing)
            session.start()
            #expect(!session.isStarting && !session.isRunning)
            #expect(session.lines.first?.sourceText == "보존할 기록")
            #expect(session.captureStartRecoveryAction == .apiKeys)
            session.hasGrokAPIKey = true
            #expect(session.startReadinessAssessment().canStart)
        }
    }

    @Test func configurationUsesSixteenKilohertzAndFencesGrokSettings() {
        #expect(CaptureStartRecoveryAction.forFailure(GrokTranscriptionError.missingKey, audioInputSource: .systemAudio) == .apiKeys)
        func configuration(_ auto: Bool) -> StartConfiguration {
            StartConfiguration(audioInputSource: .systemAudio, microphoneDeviceUniqueID: nil,
                sourceLanguage: .korean, targetLanguage: .english, selectedModel: .appleSpeechOnly,
                openAITranscriptionModel: .off, openAITranslationModel: .off, geminiTranslationModel: .off,
                grokTranscriptionModel: .voiceTranscribe2, usesGrokSourceAutoDetection: auto,
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
            session.useGrokSTTMode()
            let generation = session.activateLiveCallbackPipelineForTesting().generation
            @MainActor func deliver(_ id: String, _ text: String, final: Bool) {
                session.deliverGrokTranscriptForTesting(.init(itemID: id, text: text, isFinal: final,
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
            session.useGrokSTTMode()
            let generation = session.activateLiveCallbackPipelineForTesting().generation
            session.deliverGrokTranscriptForTesting(.init(itemID: "one", text: "hallucination", isFinal: false,
                languageCode: nil, revision: 1), generation: generation)
            session.deliverGrokTranscriptForTesting(.init(itemID: "one", text: "", isFinal: true,
                languageCode: nil, revision: nil), generation: generation)
            #expect(session.lines.isEmpty)
            session.deliverGrokTranscriptForTesting(.init(itemID: "two", text: "stale", isFinal: true,
                languageCode: "en", revision: nil), generation: generation &- 1)
            #expect(session.lines.isEmpty)
        }
    }

    @Test func pausedFinalIsPreservedAndPersistenceRemainsOptIn() throws {
        try withSession { session, _, directory in
            session.useGrokSTTMode()
            let generation = session.activateLiveCallbackPipelineForTesting().generation
            session.isPaused = true
            session.deliverGrokTranscriptForTesting(.init(itemID: "one", text: "마지막 발화", isFinal: true,
                languageCode: "ko", revision: nil), generation: generation)
            #expect(session.lines.first?.sourceText == "마지막 발화")
            session.finishGrokPipelineForTesting()
            let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            #expect(files.isEmpty)
        }
    }

    @Test func completedTurnsSaveInOrderWithoutSpeculativePartial() throws {
        try withSession { session, _, directory in
            session.useGrokSTTMode()
            session.isTranscriptPersistenceEnabled = true
            let generation = session.activateLiveCallbackPipelineForTesting().generation
            for id in ["one", "two"] {
                session.deliverGrokTranscriptForTesting(.init(itemID: id, text: "Yes.", isFinal: true,
                    languageCode: "en", revision: nil), generation: generation)
            }
            session.deliverGrokTranscriptForTesting(.init(itemID: "three", text: "unfinished", isFinal: false,
                languageCode: nil, revision: 1), generation: generation)
            session.finishGrokPipelineForTesting()
            let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            let original = try #require(files.first { $0.pathExtension == "txt" })
            let text = try String(contentsOf: original, encoding: .utf8)
            #expect(text.contains("Yes.\nYes."))
            #expect(!text.contains("unfinished"))
        }
    }

    @Test func normalStopWaitsForTranslationAndSystemMenuUsesSameDrain() async throws {
        let name = "GrokFinalTranslationTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let session = TranslationSessionStore(modelAvailabilityProvider: { _, _ in [:] },
            settingsDefaults: defaults, transcriptsDirectoryURL: directory)
        defer {
            session.finishGrokPipelineForTesting()
            defaults.removePersistentDomain(forName: name)
            try? FileManager.default.removeItem(at: directory)
        }
        session.sourceLanguage = .english
        session.targetLanguage = .korean
        session.useGrokSTTMode()
        session.useTranslationMode()
        session.isTranscriptPersistenceEnabled = true
        session.savedTranscriptContentMode = .originalAndTranslation
        session.grokTranslationForTesting = { text in
            try await Task.sleep(for: .milliseconds(60))
            return text == "First." ? "첫 문장." : "마지막 문장."
        }
        let generation = session.activateLiveCallbackPipelineForTesting().generation
        for (id, text) in [("first", "First."), ("last", "Last.")] {
            session.deliverGrokTranscriptForTesting(.init(itemID: id, text: text, isFinal: true,
                languageCode: "en", revision: nil), generation: generation)
        }
        session.stopGrokFromSystemMenuForTesting(generation: generation)
        #expect(session.isFinishingGrokSTT)
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
