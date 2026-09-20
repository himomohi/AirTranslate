import Foundation
import Testing
@testable import AirTranslate

@Suite(.serialized)
@MainActor
struct ProcessingModePickerTests {
    private func withSession(_ body: (TranslationSessionStore) throws -> Void) throws {
        let name = "ProcessingModePickerTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let session = TranslationSessionStore(modelAvailabilityProvider: { _, _ in [:] },
            settingsDefaults: defaults, transcriptsDirectoryURL: directory)
        setKeys(session, enabled: false)
        defer {
            session.isRunning = false
            session.isStarting = false
            defaults.removePersistentDomain(forName: name)
            try? FileManager.default.removeItem(at: directory)
        }
        try body(session)
    }

    private func setKeys(_ session: TranslationSessionStore, enabled: Bool) {
        session.hasOpenAIAPIKey = enabled
        session.hasGeminiAPIKey = enabled
        session.hasMetaAPIKey = enabled
        session.hasAzureSpeechAPIKey = enabled
        session.hasNariAPIKey = enabled
        session.hasGrokAPIKey = enabled
        session.hasQwenAPIKey = enabled
    }

    @Test func keyPresenceEnablesOnlyItsProvider() throws {
        try withSession { session in
            #expect(ProcessingEngine.allCases.filter { $0.canSelect(in: session) } == [.apple])
            let providers: [(CredentialProvider, ReferenceWritableKeyPath<TranslationSessionStore, Bool>)] = [
                (.openAI, \.hasOpenAIAPIKey), (.gemini, \.hasGeminiAPIKey),
                (.meta, \.hasMetaAPIKey), (.azure, \.hasAzureSpeechAPIKey),
                (.nari, \.hasNariAPIKey), (.grok, \.hasGrokAPIKey), (.qwen, \.hasQwenAPIKey),
            ]
            for (provider, keyPath) in providers {
                setKeys(session, enabled: false)
                session[keyPath: keyPath] = true
                for engine in ProcessingEngine.allCases {
                    #expect(engine.canSelect(in: session) == (engine == .apple || engine.credentialProvider == provider))
                }
            }
        }
    }

    @Test func missingKeysAndCaptureLockRejectSelection() throws {
        try withSession { session in
            for engine in ProcessingEngine.allCases where engine != .apple {
                #expect(!engine.select(in: session))
                #expect(ProcessingEngine.current(for: session) == .apple)
            }
            setKeys(session, enabled: true)
            session.useGrokSTTMode()
            for (running, starting, paused) in [(true, false, false), (false, true, false), (true, false, true)] {
                session.isRunning = running
                session.isStarting = starting
                session.isPaused = paused
                for engine in ProcessingEngine.allCases {
                    #expect(!engine.select(in: session))
                    #expect(ProcessingEngine.current(for: session) == .grok)
                }
            }
        }
    }

    @Test func enabledModesSwitchAndPreserveGeminiPreference() throws {
        try withSession { session in
            setKeys(session, enabled: true)
            session.useGeminiMode(.gemini35TranscribeLive)
            for engine in ProcessingEngine.allCases {
                #expect(engine.select(in: session))
                #expect(ProcessingEngine.current(for: session) == engine)
                if engine == .gemini {
                    #expect(session.geminiTranslationModel == .gemini35TranscribeLive)
                }
            }
            #expect(ProcessingEngine.apple.select(in: session))
            #expect(ProcessingEngine.current(for: session) == .apple)
        }
    }

    @Test func sameModeDoesNotResetOutputPreferences() throws {
        try withSession { session in
            setKeys(session, enabled: true)
            session.useAppleDefaultMode()
            session.useTranscribeOnlyMode()
            #expect(ProcessingEngine.apple.select(in: session))
            #expect(session.isTranscribeOnlyMode)
            for engine in [ProcessingEngine.nari, .grok] {
                #expect(engine.select(in: session))
                session.useTranslationMode()
                #expect(engine.select(in: session))
                #expect(!session.isTranscribeOnlyMode)
            }
        }
    }

    @Test func settingsRemainAccessibleWithoutKeysAndDuringCaptureWithoutSwitchingMode() throws {
        try withSession { session in
            session.useTranscribeOnlyMode()
            session.isStarting = true
            let source = session.sourceLanguage
            let target = session.targetLanguage
            let dubbing = session.isDubbingEnabled
            for engine in ProcessingEngine.allCases {
                engine.requestSettings(in: session)
                #expect(session.requestedSettingsCategoryID == (engine == .apple ? "general" : "apiKeys"))
                #expect(session.requestedAPIKeyProvider == engine.credentialProvider)
                #expect(ProcessingEngine.current(for: session) == .apple)
                #expect(session.isTranscribeOnlyMode)
                #expect(session.sourceLanguage == source && session.targetLanguage == target)
                #expect(session.isDubbingEnabled == dubbing)
            }
            session.requestAPIKeySettings()
            #expect(session.requestedAPIKeyProvider == nil)
        }
    }

    @Test func tooltipFollowsTheModelThatSelectingTheRowWillUse() throws {
        try withSession { session in
            let defaultNari = ProcessingEngine.nari.information(in: session)
            #expect(defaultNari.modelID == NariTranscriptionModel.qwen3ASRFast.rawValue)
            #expect(defaultNari.price.contains("0.12"))
            session.useNariSTTMode()
            session.nariTranscriptionModel = .qwen3ASR
            #expect(ProcessingEngine.nari.information(in: session).price.contains("0.06"))
            session.nariTranscriptionModel = .qwen3ASRFree
            let retired = ProcessingEngine.nari.information(in: session)
            #expect(!retired.price.contains("US$"))
            session.useAppleDefaultMode()
            #expect(ProcessingEngine.nari.information(in: session).modelID == defaultNari.modelID)

            session.useGeminiMode(.gemini35TranscribeLive)
            session.useAppleDefaultMode()
            let preferred = ProcessingEngine.gemini.information(in: session)
            #expect(preferred.modelID == GeminiTranslationModel.gemini35TranscribeLive.rawValue)
            #expect(preferred.price.contains("0.009"))
            #expect(ProcessingEngine.current(for: session) == .apple)
            #expect(session.requestedSettingsCategoryID == nil)
        }
    }

    @Test func tooltipPricesDistinguishStreamingEstimatesPromotionsAndRetiredModels() {
        #expect(ProcessingModeInfo.information(for: .grok).price.contains("0.20"))
        #expect(!ProcessingModeInfo.information(for: .grok).price.contains("0.10"))
        #expect(ProcessingModeInfo.information(for: .azure).price.contains("2026-12-31"))
        #expect(ProcessingModeInfo.information(for: .gemini).price.contains("0.0368"))
        for model in [NariTranscriptionModel.qwen3ASRFree, .qwen3ASRFastFree] {
            #expect(!ProcessingModeInfo.information(for: .nari, nariModel: model).price.contains("US$"))
        }
        for engine in ProcessingEngine.allCases {
            let info = ProcessingModeInfo.information(for: engine)
            #expect(info.tooltip.split(separator: "\n").count == 2)
        }
    }

}
