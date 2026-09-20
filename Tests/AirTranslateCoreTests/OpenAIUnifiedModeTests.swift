import Foundation
import Testing
@testable import AirTranslate

@Suite(.serialized)
@MainActor
struct OpenAIUnifiedModeTests {
    private let japanese = LanguageOption(id: "ja-JP", title: "Japanese", locale: Locale(identifier: "ja-JP"))
    private func withSession(seed: [String: Any] = [:],
                             _ body: (TranslationSessionStore, UserDefaults, URL) throws -> Void) throws {
        let name = "OpenAIUnifiedModeTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for (key, value) in seed { defaults.set(value, forKey: key) }
        let session = TranslationSessionStore(modelAvailabilityProvider: { _, _ in [:] },
            settingsDefaults: defaults, transcriptsDirectoryURL: directory)
        session.hasOpenAIAPIKey = true
        defer {
            session.isRunning = false
            session.isStarting = false
            defaults.removePersistentDomain(forName: name)
            try? FileManager.default.removeItem(at: directory)
        }
        try body(session, defaults, directory)
    }

    @Test func oneProviderSwitchesModelsAndPricesWithoutFallingBackToApple() throws {
        try withSession { session, _, _ in
            #expect(ProcessingEngine.allCases.filter { $0.credentialProvider == .openAI } == [.openAI])
            #expect(ProcessingEngine.openAI.select(in: session))
            #expect(session.openAITranslationModel == .gptRealtimeTranslate)
            #expect(ProcessingEngine.openAI.information(in: session).price.contains("0.034"))
            session.useLiveOutputMode(.transcription)
            #expect(ProcessingEngine.current(for: session) == .openAI)
            #expect(session.openAITranscriptionModel == .gptLiveTranscribe)
            #expect(session.openAITranslationModel == .off)
            #expect(session.isTranscribeOnlyMode && !session.isDubbingEnabled)
            #expect(ProcessingEngine.openAI.information(in: session).price.contains("0.017"))
            session.useLiveOutputMode(.translation)
            #expect(ProcessingEngine.current(for: session) == .openAI)
            #expect(session.openAITranscriptionModel == .off)
            #expect(session.openAITranslationModel == .gptRealtimeTranslate)
        }
    }

    @Test func internalRoundTripPreservesLanguageVoiceAndCaptionPreferences() throws {
        for voiceEnabled in [false, true] {
            try withSession { session, _, _ in
                session.useOpenAIMode(.translation)
                session.targetLanguage = japanese
                session.isDubbingEnabled = voiceEnabled
                session.floatingCaptionDisplayMode = .originalAndTranslation
                session.useOpenAIMode(.transcription)
                #expect(!session.isDubbingEnabled)
                #expect(session.floatingCaptionDisplayMode == .original)
                session.sourceLanguage = .korean
                #expect(session.targetLanguage == japanese)
                session.useOpenAIMode(.translation)
                #expect(session.targetLanguage == japanese)
                #expect(session.isDubbingEnabled == voiceEnabled)
                #expect(session.floatingCaptionDisplayMode == .originalAndTranslation)
            }
        }
    }

    @Test func lastOutputSurvivesProviderChangeAndRelaunch() throws {
        try withSession { session, defaults, directory in
            session.useOpenAIMode(.transcription)
            session.useAppleDefaultMode()
            #expect(session.preferredOpenAIOutputMode == .transcription)
            #expect(ProcessingEngine.openAI.information(in: session).modelID == "gpt-live-transcribe")
            let restored = TranslationSessionStore(modelAvailabilityProvider: { _, _ in [:] },
                settingsDefaults: defaults, transcriptsDirectoryURL: directory)
            #expect(ProcessingEngine.current(for: restored) == .apple)
            restored.useOpenAIMode()
            #expect(restored.isUsingGPTTranscriptionMode)
            #expect(restored.preferredOpenAIOutputMode == .transcription)
        }
    }

    @Test func legacyTranscriptionRestoresWithoutNewPreferenceKey() throws {
        try withSession(seed: [
            "openAITranscriptionModelID": "gpt-live-transcribe",
            "openAITranslationModelID": "off",
            "selectedModelID": "apple-speech-only",
            "sourceLanguageID": LanguageOption.english.id,
            "targetLanguageID": japanese.id,
            "providerVoiceOutputEnabled": false,
        ]) { session, _, _ in
            #expect(ProcessingEngine.current(for: session) == .openAI)
            #expect(session.openAIOutputMode == .transcription)
            #expect(session.preferredOpenAIOutputMode == .transcription)
            #expect(session.targetLanguage == japanese)
            session.useOpenAIMode(.translation)
            #expect(session.targetLanguage == japanese)
            #expect(!session.isDubbingEnabled)
        }
    }

    @Test func transcriptionRelaunchKeepsHiddenTranslationSettings() throws {
        try withSession { session, defaults, directory in
            session.useOpenAIMode(.translation)
            session.targetLanguage = japanese
            session.isDubbingEnabled = false
            session.useOpenAIMode(.transcription)
            session.sourceLanguage = .korean
            let restored = TranslationSessionStore(modelAvailabilityProvider: { _, _ in [:] },
                settingsDefaults: defaults, transcriptsDirectoryURL: directory)
            #expect(restored.isUsingGPTTranscriptionMode)
            #expect(restored.targetLanguage == japanese)
            restored.useOpenAIMode(.translation)
            #expect(restored.targetLanguage == japanese)
            #expect(!restored.isDubbingEnabled)
        }
    }

    @Test func implicitSelectionKeepsTheActiveOutputAfterLegacyHelper() throws {
        try withSession { session, _, _ in
            session.useOpenAIMode(.transcription)
            session.useTranslationMode()
            #expect(session.isUsingOpenAIRealtimeTranslation)
            session.useOpenAIMode()
            #expect(session.isUsingOpenAIRealtimeTranslation)
            #expect(session.preferredOpenAIOutputMode == .translation)
            session.useAppleDefaultMode()
            session.useOpenAIMode()
            #expect(session.isUsingOpenAIRealtimeTranslation)
        }
    }

    @Test func captureLockAndReselectionPreserveCurrentConfiguration() throws {
        try withSession { session, _, _ in
            session.useOpenAIMode(.translation)
            session.isDubbingEnabled = false
            session.targetLanguage = japanese
            session.useOpenAIMode(.translation)
            #expect(!session.isDubbingEnabled && session.targetLanguage == japanese)
            for (running, starting, paused) in [(true, false, false), (false, true, false), (true, false, true)] {
                session.isRunning = running
                session.isStarting = starting
                session.isPaused = paused
                session.useOpenAIMode(.transcription)
                session.useLiveOutputMode(.transcription)
                #expect(session.isUsingOpenAIRealtimeTranslation)
                #expect(session.preferredOpenAIOutputMode == .translation)
            }
            session.isRunning = false
            session.isStarting = false
            session.isPaused = false
            session.useOpenAIMode(.transcription)
            #expect(ProcessingEngine.openAI.select(in: session))
            #expect(session.isUsingGPTTranscriptionMode)
        }
    }
}
