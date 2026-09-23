import Foundation
import Security
import Testing
@testable import AirTranslate

@Suite(.serialized)
@MainActor
struct QwenSessionTests {
    private func withSession(_ body: (TranslationSessionStore, UserDefaults, URL) throws -> Void) throws {
        let name = "QwenSessionTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        let session = TranslationSessionStore(modelAvailabilityProvider: { _, _ in [:] },
            settingsDefaults: defaults, transcriptsDirectoryURL: directory)
        session.hasQwenAPIKey = false
        defer {
            session.finishQwenPipelineForTesting()
            defaults.removePersistentDomain(forName: name)
            try? FileManager.default.removeItem(at: directory)
        }
        try body(session, defaults, directory)
    }

    @Test func defaultAndOtherProvidersArePreserved() throws {
        try withSession { session, _, _ in
            #expect(!session.isUsingQwenTranslation)
            #expect(ProcessingEngine.current(for: session) == .apple)
            session.hasQwenAPIKey = true
            for engine in ProcessingEngine.allCases where engine != .qwen {
                session.useQwenTranslationMode()
                #expect(session.isUsingProviderRealtimeTranslation && !session.isTranscribeOnlyMode)
                #expect(session.qwenTranslationModel.rawValue == "qwen3.8-livetranslate-flash-realtime")
                #expect(!session.isDubbingEnabled)
                session.hasOpenAIAPIKey = true
                session.hasGeminiAPIKey = true
                session.hasMetaAPIKey = true
                session.hasAzureSpeechAPIKey = true
                session.hasNariAPIKey = true
                session.hasGrokAPIKey = true
                #expect(engine.select(in: session))
                #expect(!session.isUsingQwenTranslation)
                #expect(ProcessingEngine.current(for: session) == engine)
            }
        }
    }

    @Test func readinessRequiresKeyAndWorkspaceButNoAppleAssets() throws {
        try withSession { session, _, _ in
            session.useQwenTranslationMode()
            #expect(session.startReadinessAssessment().issue == .qwenConfigurationMissing)
            session.hasQwenAPIKey = true
            for value in ["", "https://host", "x.y", "a/b", "a?b", "x\n", "-abc", "abc-", String(repeating: "a", count: 64)] {
                session.qwenWorkspaceID = value
                #expect(!session.startReadinessAssessment().canStart)
            }
            session.qwenWorkspaceID = "workspace-example"
            #expect(session.startReadinessAssessment().canStart)
            session.useQuickTargetLanguage(session.sourceLanguage)
            #expect(session.targetLanguage == session.sourceLanguage)
            #expect(!session.isTranscribeOnlyMode)
        }
    }

    @Test func audio31ReadinessRequiresKeyButNotWorkspace() throws {
        try withSession { session, _, _ in
            session.useQwenTranslationMode()
            session.qwenTranslationModel = .audio31RealtimePlus
            session.qwenWorkspaceID = ""
            #expect(session.startReadinessAssessment().issue == .qwenConfigurationMissing)

            session.hasQwenAPIKey = true
            #expect(session.hasQwenConfiguration)
            #expect(session.startReadinessAssessment().canStart)
            session.useAppleDefaultMode()
            #expect(session.hasQwenConfiguration)
        }
    }

    @Test func settingsAndIndependentVoicePreferenceRestore() throws {
        try withSession { session, defaults, directory in
            session.useQwenTranslationMode()
            session.qwenWorkspaceID = "workspace-example"
            session.targetLanguage = .korean
            session.audioInputSource = .microphone
            session.isDubbingEnabled = true
            session.useAppleDefaultMode()
            session.useQwenTranslationMode()
            #expect(session.isDubbingEnabled)
            let restored = TranslationSessionStore(modelAvailabilityProvider: { _, _ in [:] },
                settingsDefaults: defaults, transcriptsDirectoryURL: directory)
            #expect(restored.isUsingQwenTranslation)
            #expect(!restored.isUsingGemini && !restored.isUsingOpenAIRealtime && !restored.isUsingGrokSTT)
            #expect(restored.qwenWorkspaceID == "workspace-example")
            #expect(restored.isDubbingEnabled)
            #expect(restored.targetLanguage == .korean)
            #expect(restored.audioInputSource == .microphone)
        }
    }

    @Test func realtimeModelPreferenceRestoresAndSurvivesModeSwitch() throws {
        try withSession { session, defaults, directory in
            session.hasQwenAPIKey = true
            session.useQwenTranslationMode()
            session.qwenTranslationModel = .audio31RealtimePlus
            session.useAppleDefaultMode()
            #expect(session.qwenTranslationModel == .off)
            #expect(session.preferredQwenModel == .audio31RealtimePlus)
            #expect(defaults.string(forKey: "preferredQwenTranslationModelID") == "qwen-audio-3.1-realtime-plus")
            session.useQwenTranslationMode()
            #expect(session.qwenTranslationModel == .audio31RealtimePlus)

            let restored = TranslationSessionStore(modelAvailabilityProvider: { _, _ in [:] },
                settingsDefaults: defaults, transcriptsDirectoryURL: directory)
            #expect(restored.qwenTranslationModel == .audio31RealtimePlus)
            #expect(ProcessingModeInfo.information(for: .qwen, qwenModel: restored.qwenTranslationModel).modelID
                == "qwen-audio-3.1-realtime-plus")
        }
    }

    @Test func finalCorrectionRepeatsAndPausedDrainReachCaptions() throws {
        try withSession { session, _, _ in
            session.useQwenTranslationMode()
            let active = session.activateLiveCallbackPipelineForTesting()
            session.deliverQwenTextForTesting("go ", isFinal: false, isTranslation: false, generation: active.generation)
            session.deliverQwenTextForTesting("go", isFinal: false, isTranslation: false, generation: active.generation)
            session.deliverQwenTextForTesting("go go!", isFinal: true, isTranslation: false, generation: active.generation)
            session.deliverQwenTextForTesting("가", isFinal: false, isTranslation: true, generation: active.generation)
            session.isPaused = true
            session.deliverQwenTextForTesting("가세요!", isFinal: true, isTranslation: true, generation: active.generation)
            #expect(session.lines.last?.sourceText == "go go!")
            #expect(session.lines.last?.translatedText == "가세요!")
            #expect(session.lines.last?.isFinal == true)
            session.deliverQwenTextForTesting("다음", isFinal: true, isTranslation: true, generation: active.generation)
            #expect(session.lines.last?.translatedText == "가세요!\n다음")
            session.finishQwenPipelineForTesting()
            session.deliverQwenTextForTesting("stale", isFinal: true, isTranslation: true, generation: active.generation)
            #expect(session.lines.last?.translatedText == "가세요!\n다음")
        }
    }

    @Test func missingCredentialsDoNotEraseCaptionsAndSwitchClearsOwnFailure() throws {
        try withSession { session, _, _ in
            session.useQwenTranslationMode()
            let active = session.activateLiveCallbackPipelineForTesting()
            session.deliverQwenTextForTesting("keep", isFinal: true, isTranslation: false, generation: active.generation)
            session.finishQwenPipelineForTesting()
            session.start()
            #expect(!session.isStarting && !session.isRunning)
            #expect(session.lines.last?.sourceText == "keep")
            #expect(session.captureStartRecoveryAction == .apiKeys)
            session.useAppleDefaultMode()
            #expect(session.captureStartFailureMessage == nil)
        }
    }

    @Test func systemCaptureStopDrainsBeforeInvalidatingGeneration() throws {
        try withSession { session, _, _ in
            session.useQwenTranslationMode()
            let active = session.activateLiveCallbackPipelineForTesting()
            session.stopQwenFromSystemMenuForTesting(generation: active.generation)
            #expect(session.isFinishingQwenTranslation && session.isRunning)
            session.deliverQwenTextForTesting("last", isFinal: true, isTranslation: false, generation: active.generation)
            session.deliverQwenTextForTesting("마지막", isFinal: true, isTranslation: true, generation: active.generation)
            #expect(session.lines.last?.translatedText == "마지막")
        }
    }

    @Test func emptyFinalRetractsPartialFromCaptionOverlayAndPendingSave() throws {
        try withSession { session, _, directory in
            session.useQwenTranslationMode()
            session.isTranscriptPersistenceEnabled = true
            let active = session.activateLiveCallbackPipelineForTesting()
            session.deliverQwenTextForTesting("wrong", isFinal: false, isTranslation: false, generation: active.generation)
            #expect(!session.floatingSourceText.isEmpty)
            #expect(!session.checkpointQwenTranscriptForTesting())
            session.deliverQwenTextForTesting("", isFinal: true, isTranslation: false, generation: active.generation)
            #expect(session.lines.isEmpty)
            #expect(session.floatingSourceText.isEmpty && session.floatingTranslationText.isEmpty)
            session.finishQwenPipelineForTesting()
            let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            #expect(files.filter { $0.pathExtension == "txt" }.isEmpty)
        }
        var transcript = QwenCaptionTranscript()
        transcript.receive("kept", isFinal: true)
        transcript.receive("discard", isFinal: false)
        transcript.receive("", isFinal: true)
        #expect(transcript.text == "kept\n")
    }

    @Test func keyPresenceNeverReadsSecretAndValidationRejectsHeaderInjection() throws {
        let query = QwenAPIKeyStore.presenceQuery()
        #expect(query[kSecAttrService as String] as? String == "AirTranslate.Qwen")
        #expect(query[kSecReturnData as String] == nil)
        #expect(query[kSecUseAuthenticationUI as String] as? String == kSecUseAuthenticationUISkip as String)
        #expect(try QwenAPIKeyStore.normalizedAPIKey(" test-placeholder ") == "test-placeholder")
        for value in ["", "a b", "test\r\nheader", "test\u{0}value"] {
            #expect(throws: QwenAPIKeyStoreError.self) { try QwenAPIKeyStore.normalizedAPIKey(value) }
        }
    }
}
