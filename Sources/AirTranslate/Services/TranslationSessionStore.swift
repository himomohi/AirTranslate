import AVFAudio
import AppKit
import AirTranslateCore
import Foundation
import Observation
import SwiftUI

enum PrivacySettingsPane: Equatable {
    case screenRecording
    case systemAudioRecording
    case microphone
    case speechRecognition

    fileprivate var anchor: String {
        switch self {
        case .screenRecording, .systemAudioRecording:
            // macOS groups Screen Recording and System Audio Recording in this pane.
            "Privacy_ScreenCapture"
        case .microphone:
            "Privacy_Microphone"
        case .speechRecognition:
            "Privacy_SpeechRecognition"
        }
    }
}

enum CaptureStartRecoveryAction: Equatable {
    case apiKeys
    case generalSettings
    case privacy(PrivacySettingsPane)
    case retry

    static func forFailure(_ error: Error, audioInputSource _: AudioInputSource) -> Self {
        if let grokError = error as? GrokTranscriptionError, grokError == .missingKey { return .apiKeys }
        if let nariError = error as? NariTranscriptionError {
            switch nariError {
            case .missingKey, .authentication: return .apiKeys
            default: return .retry
            }
        }
        if let captureError = error as? CaptureError {
            switch captureError {
            case .screenRecordingNotGranted:
                return .privacy(.screenRecording)
            case .microphoneNotGranted:
                return .privacy(.microphone)
            case .microphoneUnavailable, .microphoneInterrupted, .microphoneRuntimeFailure, .noDisplay:
                return .retry
            }
        }
        if let speechError = error as? SpeechError {
            switch speechError {
            case .notAuthorized:
                return .privacy(.speechRecognition)
            case .recognizerUnavailable:
                return .retry
            }
        }
        return .retry
    }

    static func forReadiness(_ readiness: StartReadinessAssessment) -> Self? {
        switch readiness.issue {
        case .openAIAPIKeyMissing, .geminiAPIKeyMissing, .metaAPIKeyMissing, .azureConfigurationMissing, .nariAPIKeyMissing, .grokAPIKeyMissing, .qwenConfigurationMissing:
            .apiKeys
        case .nariLegacyFreeModelSelected:
            .generalSettings
        case .localAssetsChecking, .localAssetsUnavailable, .nariLanguageUnsupported, .grokLanguageUnsupported:
            .retry
        case .localAssetsDownloadRequired, nil:
            nil
        }
    }
}

private enum SettingsKey {
    static let sourceLanguageID = "sourceLanguageID"
    static let targetLanguageID = "targetLanguageID"
    static let selectedModelID = "selectedModelID"
    static let openAITranscriptionModelID = "openAITranscriptionModelID"
    static let openAITranslationModelID = "openAITranslationModelID"
    static let geminiTranslationModelID = "geminiTranslationModelID"
    static let preferredOpenAIOutputMode = "preferredOpenAIOutputMode"
    static let preferredGeminiModelID = "preferredGeminiModelID"
    static let metaTranscriptionModelID = "metaTranscriptionModelID"
    static let nariTranscriptionModelID = "nariTranscriptionModelID"
    static let grokTranscriptionModelID = "grokTranscriptionModelID"
    static let nariSourceAutoDetectionEnabled = "nariSourceAutoDetectionEnabled"
    static let grokSourceAutoDetectionEnabled = "grokSourceAutoDetectionEnabled"
    static let metaSpeakerLabelsEnabled = "metaSpeakerLabelsEnabled"
    static let isDubbingEnabled = "isDubbingEnabled"
    static let appleVoiceOutputEnabled = "appleVoiceOutputEnabled"
    static let providerVoiceOutputEnabled = "providerVoiceOutputEnabled"
    static let translatedVoiceVolume = "translatedVoiceVolume"
    static let isTranscriptLintEnabled = "isTranscriptLintEnabled"
    static let isTranscriptPersistenceEnabled = "isTranscriptPersistenceEnabled"
    static let floatingCaptionDisplayMode = "floatingCaptionDisplayMode"
    static let floatingCaptionTextSize = "floatingCaptionTextSize"
    static let floatingCaptionLineCount = "floatingCaptionLineCount"
    static let keepsFloatingCaptionAboveOtherWindows = "keepsFloatingCaptionAboveOtherWindows"
    static let floatingCaptionStability = "floatingCaptionStability"
    static let floatingCaptionTextAlignment = "floatingCaptionTextAlignment"
    static let floatingCaptionCustomPointSize = "floatingCaptionCustomPointSize"
    static let floatingCaptionTextColorHex = "floatingCaptionTextColorHex"
    static let floatingCaptionBackgroundColorHex = "floatingCaptionBackgroundColorHex"
    static let floatingCaptionBackgroundOpacity = "floatingCaptionBackgroundOpacity"
    static let floatingCaptionStyle = "floatingCaptionStyle"
    static let paragraphBreakSilenceInterval = "paragraphBreakSilenceInterval"
    static let savedTranscriptContentMode = "savedTranscriptContentMode"
    static let sessionDurationMode = "sessionDurationMode"
    static let audioInputSource = "audioInputSource"
    static let selectedMicrophoneInputDeviceID = "selectedMicrophoneInputDeviceID"
    static let isAppleSourceAutoDetectionEnabled = "isAppleSourceAutoDetectionEnabled"
}

private struct TranslationRequest {
    let line: CaptionLine
    let sourceText: String
    let translationSourceText: String
    let source: LanguageOption
    let target: LanguageOption
    let preservesOrdering: Bool
    let bypassesDebounce: Bool
    let appleIdentity: AppleTranslationRequestIdentity?
}

private struct PendingCaptionPresentation {
    let lineID: UUID
    let sourceText: String
    let isFinal: Bool
    let source: LanguageOption
    let target: LanguageOption
    let metadata: AppleSpeechRecognitionMetadata?
}

private struct PendingRecognizedCaption {
    let sourceText: String
    let recognizedLanguage: LanguageOption
    let confidence: Double
    let metadata: AppleSpeechRecognitionMetadata?
}

struct StartConfiguration: Equatable {
    let audioInputSource: AudioInputSource
    let microphoneDeviceUniqueID: String?
    let sourceLanguage: LanguageOption
    let targetLanguage: LanguageOption
    let selectedModel: IntelligenceModel
    let openAITranscriptionModel: OpenAIRealtimeTranscriptionModel
    let openAITranslationModel: OpenAIRealtimeTranslationModel
    let geminiTranslationModel: GeminiTranslationModel
    let metaTranscriptionModel: MetaTranscriptionModel
    let nariTranscriptionModel: NariTranscriptionModel
    let grokTranscriptionModel: GrokTranscriptionModel
    let qwenTranslationModel: QwenTranslationModel
    let qwenWorkspaceID: String
    let qwenAudioOutputEnabled: Bool
    let usesNariSourceAutoDetection: Bool
    let usesGrokSourceAutoDetection: Bool
    let azureMAIEnabled: Bool
    let azureSpeechEndpoint: String
    let usesMetaSpeakerLabels: Bool
    let usesAppleSourceAutoDetection: Bool

    init(
        audioInputSource: AudioInputSource,
        microphoneDeviceUniqueID: String?,
        sourceLanguage: LanguageOption,
        targetLanguage: LanguageOption,
        selectedModel: IntelligenceModel,
        openAITranscriptionModel: OpenAIRealtimeTranscriptionModel,
        openAITranslationModel: OpenAIRealtimeTranslationModel,
        geminiTranslationModel: GeminiTranslationModel,
        metaTranscriptionModel: MetaTranscriptionModel = .off,
        qwenTranslationModel: QwenTranslationModel = .off,
        qwenWorkspaceID: String = "",
        qwenAudioOutputEnabled: Bool = false,
        grokTranscriptionModel: GrokTranscriptionModel = .off,
        usesGrokSourceAutoDetection: Bool = true,
        nariTranscriptionModel: NariTranscriptionModel = .off,
        usesNariSourceAutoDetection: Bool = false,
        azureMAIEnabled: Bool = false,
        azureSpeechEndpoint: String = "",
        usesMetaSpeakerLabels: Bool = true,
        usesAppleSourceAutoDetection: Bool
    ) {
        self.audioInputSource = audioInputSource
        self.microphoneDeviceUniqueID = microphoneDeviceUniqueID
        self.sourceLanguage = sourceLanguage
        self.targetLanguage = targetLanguage
        self.selectedModel = selectedModel
        self.openAITranscriptionModel = openAITranscriptionModel
        self.openAITranslationModel = openAITranslationModel
        self.geminiTranslationModel = geminiTranslationModel
        self.metaTranscriptionModel = metaTranscriptionModel
        self.qwenTranslationModel = qwenTranslationModel
        self.qwenWorkspaceID = qwenWorkspaceID
        self.qwenAudioOutputEnabled = qwenAudioOutputEnabled
        self.grokTranscriptionModel = grokTranscriptionModel
        self.usesGrokSourceAutoDetection = usesGrokSourceAutoDetection
        self.nariTranscriptionModel = nariTranscriptionModel
        self.usesNariSourceAutoDetection = usesNariSourceAutoDetection
        self.azureMAIEnabled = azureMAIEnabled
        self.azureSpeechEndpoint = azureSpeechEndpoint
        self.usesMetaSpeakerLabels = usesMetaSpeakerLabels
        self.usesAppleSourceAutoDetection = usesAppleSourceAutoDetection
    }

    var isUsingGPTTranscriptionMode: Bool {
        openAITranscriptionModel == .gptLiveTranscribe
    }

    var isTranscribeOnlyMode: Bool {
        selectedModel == .appleSpeechOnly
            || isUsingGPTTranscriptionMode
            || geminiTranslationModel.isTranscription
    }

    var sampleRate: Int {
        openAITranscriptionModel.isEnabled
            || openAITranslationModel.usesRealtimeAudioTranslation
            || metaTranscriptionModel.isEnabled
            ? 24_000
            : 16_000
    }
}

enum PipelineLifecyclePhase: Equatable {
    case stopped
    case starting
    case running
}

enum PipelineStartValidation: Equatable {
    case valid
    case staleGeneration
    case configurationChanged
}

struct PipelineLifecycleState {
    private(set) var generation: UInt64 = 0
    private(set) var phase = PipelineLifecyclePhase.stopped
    private(set) var startConfiguration: StartConfiguration?

    mutating func beginStart(configuration: StartConfiguration) -> UInt64 {
        generation &+= 1
        phase = .starting
        startConfiguration = configuration
        return generation
    }

    mutating func validateStart(
        generation expectedGeneration: UInt64,
        currentConfiguration: StartConfiguration
    ) -> PipelineStartValidation {
        guard generation == expectedGeneration, phase == .starting else {
            return .staleGeneration
        }
        guard startConfiguration == currentConfiguration else {
            generation &+= 1
            phase = .stopped
            startConfiguration = nil
            return .configurationChanged
        }
        return .valid
    }

    mutating func markRunning(
        generation expectedGeneration: UInt64,
        currentConfiguration: StartConfiguration
    ) -> PipelineStartValidation {
        let validation = validateStart(
            generation: expectedGeneration,
            currentConfiguration: currentConfiguration
        )
        if validation == .valid {
            phase = .running
        }
        return validation
    }

    mutating func fail(generation expectedGeneration: UInt64) -> Bool {
        guard generation == expectedGeneration, phase != .stopped else {
            return false
        }
        stop()
        return true
    }

    mutating func failCurrent() -> Bool {
        guard phase != .stopped else { return false }
        stop()
        return true
    }

    mutating func stop() {
        generation &+= 1
        phase = .stopped
        startConfiguration = nil
    }

    func acceptsSample(generation expectedGeneration: UInt64) -> Bool {
        generation == expectedGeneration && phase == .running
    }

    func isActive(generation expectedGeneration: UInt64) -> Bool {
        generation == expectedGeneration && phase != .stopped
    }
}

private enum PipelineStartError: LocalizedError {
    case configurationChanged

    var errorDescription: String? {
        switch self {
        case .configurationChanged:
            AppText.localized(
                english: "Capture settings changed while starting. Start again.",
                korean: "시작하는 동안 캡처 설정이 변경되었습니다. 다시 시작해 주세요.",
                japanese: "開始中にキャプチャ設定が変更されました。もう一度開始してください。",
                chineseSimplified: "启动期间捕获设置已更改。请重新启动。"
            )
        }
    }
}

private struct RealtimeAudioTransportError: LocalizedError {
    let degradation: RealtimeAudioTransportDegradation

    var errorDescription: String? {
        AppText.localized(
            english: "Realtime audio could not keep up, so capture was stopped to avoid missing captions.",
            korean: "실시간 오디오 전송이 입력을 따라가지 못해 자막 누락을 막기 위해 캡처를 중지했습니다.",
            japanese: "リアルタイム音声転送が入力に追いつかなかったため、字幕の欠落を防ぐためにキャプチャを停止しました。",
            chineseSimplified: "实时音频传输无法跟上输入，已停止捕获以避免字幕缺失。"
        )
    }
}

private final class AudioSamplePipelineRegistry: @unchecked Sendable {
    private struct Pipeline {
        let generation: UInt64
        let transcriber: LiveSpeechTranscriber
        let openAITranscriber: OpenAIRealtimeTranscriber
        let geminiLiveTranslator: GeminiLiveTranslationService
        let azureMAITranscriber: AzureMAITranscriber
        let metaVoiceTranscriber: MetaVoiceTranscribeService
        let grokTranscriber: GrokRealtimeTranscriber
        let nariTranscriber: NariRealtimeTranscriber
        let qwenTranslator: QwenRealtimeTranslationService
    }

    private let lock = NSLock()
    private var pipeline: Pipeline?

    func publish(
        generation: UInt64,
        transcriber: LiveSpeechTranscriber,
        openAITranscriber: OpenAIRealtimeTranscriber,
        geminiLiveTranslator: GeminiLiveTranslationService,
        metaVoiceTranscriber: MetaVoiceTranscribeService,
        azureMAITranscriber: AzureMAITranscriber,
        grokTranscriber: GrokRealtimeTranscriber,
        nariTranscriber: NariRealtimeTranscriber,
        qwenTranslator: QwenRealtimeTranslationService
    ) {
        lock.lock()
        pipeline = Pipeline(
            generation: generation,
            transcriber: transcriber,
            openAITranscriber: openAITranscriber,
            geminiLiveTranslator: geminiLiveTranslator,
            azureMAITranscriber: azureMAITranscriber,
            metaVoiceTranscriber: metaVoiceTranscriber,
            grokTranscriber: grokTranscriber,
            nariTranscriber: nariTranscriber,
            qwenTranslator: qwenTranslator
        )
        lock.unlock()
    }

    func clear() {
        lock.lock()
        pipeline = nil
        lock.unlock()
    }

    func append(_ sampleBuffer: CMSampleBuffer, generation: UInt64) {
        lock.lock()
        defer { lock.unlock() }
        guard let pipeline, pipeline.generation == generation else { return }

        // clear() waits for any in-flight append to finish before the MainActor
        // stops or replaces these backends.
        pipeline.transcriber.append(sampleBuffer)
        pipeline.openAITranscriber.append(sampleBuffer)
        pipeline.geminiLiveTranslator.append(sampleBuffer)
        pipeline.metaVoiceTranscriber.append(sampleBuffer)
        pipeline.azureMAITranscriber.append(sampleBuffer)
        pipeline.grokTranscriber.append(sampleBuffer)
        pipeline.nariTranscriber.append(sampleBuffer)
        pipeline.qwenTranslator.append(sampleBuffer)
    }
}

private struct OpenAITerminalTranscript: Sendable {
    let text: String
    let language: LanguageOption
    let confidence: Double
    let transcriber: OpenAIRealtimeTranscriber
}

private final class OpenAITerminalTranscriptMailbox: @unchecked Sendable {
    private let lock = NSLock()
    private var transcripts: [OpenAITerminalTranscript] = []

    func append(_ transcript: OpenAITerminalTranscript) {
        lock.lock()
        transcripts.append(transcript)
        lock.unlock()
    }

    func drain() -> [OpenAITerminalTranscript] {
        lock.lock()
        let drained = transcripts
        transcripts.removeAll()
        lock.unlock()
        return drained
    }
}

struct AutoDetectionLanguageChangeConfirmation: Equatable {
    let currentLanguage: LanguageOption
    let detectedLanguage: LanguageOption
    let targetLanguage: LanguageOption
    let sourceText: String
    let confidence: Double
}

enum AutoDetectionLanguageChangePolicy {
    static func shouldRequestConfirmation(
        isAutoDetectionEnabled: Bool,
        activeLanguage: LanguageOption?,
        detectedLanguage: LanguageOption,
        confidence: Double,
        hadLongSilence: Bool,
        hasVisibleTranscript: Bool,
        minimumSwitchConfidence: Double
    ) -> Bool {
        guard isAutoDetectionEnabled,
              hasVisibleTranscript,
              hadLongSilence,
              confidence >= minimumSwitchConfidence,
              let activeLanguage,
              activeLanguage != detectedLanguage
        else {
            return false
        }

        return true
    }
}

@Observable
@MainActor
final class TranslationSessionStore {
    private static let maxTranslationCacheEntries = 2_000
    private static let largeTranscriptPresentationCharacterLimit = 4_000
    private static let largeTranscriptPresentationInterval: TimeInterval = 0.35
    private static let largeTranscriptRecognitionDeliveryInterval: TimeInterval = 0.25
    private static let appleCaptionRolloverCharacterLimit = 600
    private static let appleCaptionRolloverSilenceCharacterLimit = 160
    private static let appleCaptionRolloverMinimumUnits = 2
    private static let appleRolloverReplayGuardUnitCount = 2
    private static let translationCacheHitYieldInterval = 32
    private static let largeTranscriptTranslationCharacterLimit = 4_000
    private static let veryLargeTranscriptTranslationCharacterLimit = 10_000
    private static let defaultTranscriptCheckpointInterval: TimeInterval = 30
    private static let transcribeOnlyNoticeDisplayDuration: TimeInterval = 10
    static let geminiSessionRefreshInterval: TimeInterval = 570
    static let metaSessionRefreshInterval: TimeInterval = 3_300
    private static let appleAutoDetectionMinimumConfidence = 0.35
    private static let appleAutoDetectionLanguageSwitchMinimumConfidence = 0.72
    private static let isAppleSourceAutoDetectionTemporarilyDisabled = true

    private enum CaptionRolloverContext {
        case sentenceBoundary
        case longSilence
    }

    var isRunning = false
    var isStarting = false
    var isPaused = false
    var isDubbingEnabled = false {
        didSet {
            if !isApplyingVoiceOutputDefault {
                rememberVoiceOutputPreference(isDubbingEnabled)
            }
            persistSelectedSettings()
            if isDubbingEnabled {
                if isUsingProviderRealtimeTranslation {
                    openAIRealtimeAudioOutput.stop()
                } else {
                    primeDubbingBaselineToCurrentTranslation()
                }
            } else {
                stopSpeaking()
                dubbingSpeechProgress.reset()
            }
        }
    }
    var translatedVoiceVolume = 1.0 {
        didSet {
            let clampedVolume = Self.clampedVolume(translatedVoiceVolume)
            guard translatedVoiceVolume == clampedVolume else {
                translatedVoiceVolume = clampedVolume
                return
            }

            persistSelectedSettings()
            applyTranslatedVoiceVolume()
        }
    }
    var sourceLanguage = LanguageOption.supported[0] {
        didSet {
            persistSelectedSettings()
            resetTranslationCache()
            resetDubbingProgress()
            refreshModelAvailability()
            syncLiveOutputModeWithLanguagePair()
        }
    }
    var targetLanguage = LanguageOption.supported[1] {
        didSet {
            persistSelectedSettings()
            resetTranslationCache()
            resetDubbingProgress()
            refreshModelAvailability()
            syncLiveOutputModeWithLanguagePair()
        }
    }
    var selectedModel = IntelligenceModel.appleSystem {
        didSet {
            persistSelectedSettings()
            resetTranslationCache()
            resetDubbingProgress()
            refreshModelAvailability()
        }
    }
    var hasOpenAIAPIKey = OpenAIAPIKeyStore.hasAPIKey()
    var hasGeminiAPIKey = GeminiAPIKeyStore.hasAPIKey()
    var hasAzureSpeechAPIKey = AzureSpeechAPIKeyStore.hasAPIKey()
    var hasNariAPIKey = NariAPIKeyStore.hasAPIKey()
    var nariTranscriptionModel = NariTranscriptionModel.off {
        didSet {
            if nariTranscriptionModel.isEnabled {
                qwenTranslationModel = .off
                grokTranscriptionModel = .off
                isUsingAzureMAI = false
                openAITranscriptionModel = .off
                openAITranslationModel = .off
                geminiTranslationModel = .off
                metaTranscriptionModel = .off
                isTranscriptLintEnabled = false
            }
            persistSelectedSettings()
            resetTranslationCache()
            resetDubbingProgress()
            refreshModelAvailability()
            if !nariTranscriptionModel.isLegacyFreeEndpoint,
               statusMessage == NariCopy.legacyFreeModelEnded {
                dismissCaptureStartFailure()
                statusMessage = AppText.ready
            }
        }
    }
    var isNariSourceAutoDetectionEnabled = false {
        didSet { persistSelectedSettings() }
    }
    var isFinishingNariSTT = false
    var isReconnectingNariSTT = false
    @ObservationIgnored private var nariTranscriber = NariRealtimeTranscriber()
    @ObservationIgnored private var nariTransitionTask: Task<Void, Never>?
#if DEBUG
    var nariTranslationForTesting: (@MainActor (String) async throws -> String)?
#endif
    private var nariTurnLineIDs: [String: UUID] = [:]
    private var nariFinalizedItemIDs: Set<String> = []
    private var nariItemOrder: [String] = []
    private var nariSavedTranscriptText = ""
    var hasQwenAPIKey = QwenAPIKeyStore.hasAPIKey()
    var qwenWorkspaceID = "" {
        didSet { persistSelectedSettings() }
    }
    private(set) var preferredQwenModel = QwenTranslationModel.liveTranslateFlashRealtime
    var qwenTranslationModel = QwenTranslationModel.off {
        didSet {
            if qwenTranslationModel.isEnabled {
                preferredQwenModel = qwenTranslationModel
                grokTranscriptionModel = .off
                nariTranscriptionModel = .off
                isUsingAzureMAI = false
                openAITranscriptionModel = .off
                openAITranslationModel = .off
                geminiTranslationModel = .off
                metaTranscriptionModel = .off
                selectedModel = .appleSystem
                isTranscriptLintEnabled = false
                restoreFloatingCaptionDisplayModeAfterTranscribeOnly()
            }
            persistSelectedSettings()
            resetTranslationCache()
            resetDubbingProgress()
            refreshModelAvailability()
            if oldValue.isEnabled, !isRunning, !isStarting,
               captureStartFailureMessage == QwenCopy.configurationRequired(for: oldValue) {
                if qwenTranslationModel.isEnabled && !hasQwenConfiguration {
                    presentCaptureStartFailure(
                        QwenCopy.configurationRequired(for: qwenTranslationModel),
                        recoveryAction: .apiKeys
                    )
                } else {
                    dismissCaptureStartFailure()
                    if statusMessage == QwenCopy.configurationRequired(for: oldValue) { statusMessage = AppText.ready }
                }
            }
        }
    }
    var isFinishingQwenTranslation = false
    var isReconnectingQwenTranslation = false
    private var qwenVoiceOutputEnabled = false
    @ObservationIgnored private var qwenTranslator = QwenRealtimeTranslationService()
    @ObservationIgnored private var qwenTransitionTask: Task<Void, Never>?
    private var qwenSourceTranscript = QwenCaptionTranscript()
    private var qwenTranslationTranscript = QwenCaptionTranscript()

    var isUsingQwenTranslation: Bool { qwenTranslationModel.isEnabled }
    var hasQwenConfiguration: Bool {
        let model = qwenTranslationModel.isEnabled ? qwenTranslationModel : preferredQwenModel
        let hasRequiredWorkspace = model == .audio31RealtimePlus || QwenTranslationModel.isValidWorkspaceID(qwenWorkspaceID)
        return hasQwenAPIKey && hasRequiredWorkspace
    }

    var hasGrokAPIKey = GrokAPIKeyStore.hasAPIKey()
    var grokTranscriptionModel = GrokTranscriptionModel.off {
        didSet {
            if grokTranscriptionModel.isEnabled {
                qwenTranslationModel = .off
                nariTranscriptionModel = .off
                isUsingAzureMAI = false
                openAITranscriptionModel = .off
                openAITranslationModel = .off
                geminiTranslationModel = .off
                metaTranscriptionModel = .off
                isTranscriptLintEnabled = false
            }
            persistSelectedSettings()
            resetTranslationCache()
            resetDubbingProgress()
            refreshModelAvailability()
            if oldValue.isEnabled, !grokTranscriptionModel.isEnabled,
               !isRunning, !isStarting,
               let failure = captureStartFailureMessage,
               failure == GrokCopy.configurationRequired || failure == GrokCopy.languageUnsupported {
                dismissCaptureStartFailure()
                if statusMessage == failure { statusMessage = AppText.ready }
            }
        }
    }
    var isGrokSourceAutoDetectionEnabled = true {
        didSet { persistSelectedSettings() }
    }
    var isFinishingGrokSTT = false
    var isReconnectingGrokSTT = false
    @ObservationIgnored private var grokTranscriber = GrokRealtimeTranscriber()
    @ObservationIgnored private var grokTransitionTask: Task<Void, Never>?
#if DEBUG
    var grokTranslationForTesting: (@MainActor (String) async throws -> String)?
#endif
    private var grokTurnLineIDs: [String: UUID] = [:]
    private var grokFinalizedItemIDs: Set<String> = []
    private var grokItemOrder: [String] = []
    private var grokSavedTranscriptText = ""
    var azureSpeechEndpoint = "" {
        didSet { persistSelectedSettings() }
    }
    var isUsingAzureMAI = false {
        didSet {
            if isUsingAzureMAI {
                qwenTranslationModel = .off
                grokTranscriptionModel = .off
                nariTranscriptionModel = .off
                selectedModel = .appleSystem
                openAITranscriptionModel = .off
                openAITranslationModel = .off
                geminiTranslationModel = .off
                metaTranscriptionModel = .off
                isTranscriptLintEnabled = false
            }
            persistSelectedSettings()
            refreshModelAvailability()
        }
    }
    var isFinishingAzureMAI = false
    @ObservationIgnored private var azureMAITranscriber = AzureMAITranscriber()
    @ObservationIgnored private var azureFinishTask: Task<Void, Never>?
    private var azureSavedTranscriptText = ""
    var hasMetaAPIKey = MetaAPIKeyStore.hasAPIKey()
    var requestedSettingsCategoryID: String?
    var requestedAPIKeyProvider: CredentialProvider?
    private(set) var preferredOpenAIOutputMode = LiveOutputMode.translation {
        didSet { persistSelectedSettings() }
    }

    var openAIOutputMode: LiveOutputMode {
        isUsingOpenAIRealtime ? liveOutputMode : preferredOpenAIOutputMode
    }

    var openAITranscriptionModel = OpenAIRealtimeTranscriptionModel.off {
        didSet {
            if openAITranscriptionModel.isEnabled {
                qwenTranslationModel = .off
                grokTranscriptionModel = .off
                nariTranscriptionModel = .off
                isUsingAzureMAI = false
                isTranscriptLintEnabled = false
                geminiTranslationModel = .off
                metaTranscriptionModel = .off
            }
            persistSelectedSettings()
            resetTranslationCache()
            refreshModelAvailability()
        }
    }
    var openAITranslationModel = OpenAIRealtimeTranslationModel.off {
        didSet {
            if openAITranslationModel.isEnabled {
                qwenTranslationModel = .off
                grokTranscriptionModel = .off
                nariTranscriptionModel = .off
                isUsingAzureMAI = false
                guard openAITranslationModel.isSupportedLiveTranslationModel else {
                    openAITranslationModel = .gptRealtimeTranslate
                    return
                }
                isTranscriptLintEnabled = false
                geminiTranslationModel = .off
                metaTranscriptionModel = .off
            }
            persistSelectedSettings()
            resetTranslationCache()
            resetDubbingProgress()
            refreshModelAvailability()
        }
    }
    var geminiTranslationModel = GeminiTranslationModel.off {
        didSet {
            if geminiTranslationModel.isEnabled {
                qwenTranslationModel = .off
                grokTranscriptionModel = .off
                nariTranscriptionModel = .off
                isUsingAzureMAI = false
                isTranscriptLintEnabled = false
                selectedModel = .appleSystem
                openAITranscriptionModel = .off
                openAITranslationModel = .off
                metaTranscriptionModel = .off
                preferredGeminiModel = geminiTranslationModel
                if geminiTranslationModel.isTranscription {
                    prepareTranscribeOnlyPresentation()
                } else {
                    restoreFloatingCaptionDisplayModeAfterTranscribeOnly()
                }
            }
            persistSelectedSettings()
            resetTranslationCache()
            resetDubbingProgress()
            refreshModelAvailability()
        }
    }
    private(set) var preferredGeminiModel = GeminiTranslationModel.gemini35LiveTranslate
    var metaTranscriptionModel = MetaTranscriptionModel.off {
        didSet {
            if metaTranscriptionModel.isEnabled {
                qwenTranslationModel = .off
                grokTranscriptionModel = .off
                nariTranscriptionModel = .off
                isUsingAzureMAI = false
                isTranscriptLintEnabled = false
                selectedModel = .appleSystem
                openAITranscriptionModel = .off
                openAITranslationModel = .off
                geminiTranslationModel = .off
                restoreFloatingCaptionDisplayModeAfterTranscribeOnly()
            }
            persistSelectedSettings()
            resetTranslationCache()
            resetDubbingProgress()
            refreshModelAvailability()
        }
    }
    var isMetaSpeakerLabelsEnabled = true {
        didSet { persistSelectedSettings() }
    }
    var isTranscriptLintEnabled = false {
        didSet { persistSelectedSettings() }
    }
    var isTranscriptPersistenceEnabled = false {
        didSet {
            persistSelectedSettings()
            guard !isTranscriptPersistenceEnabled else { return }

            transcriptCheckpointTask?.cancel()
            transcriptCheckpointTask = nil
            activeAutosaveSourceText = ""
            activeAutosaveTranslatedText = ""
            activeAutosaveBaseFileName = nil
        }
    }
    var floatingCaptionDisplayMode = FloatingCaptionDisplayMode.originalAndTranslation {
        didSet {
            if isTranscribeOnlyMode, floatingCaptionDisplayMode != .original {
                floatingCaptionDisplayMode = .original
                return
            }
            persistSelectedSettings()
        }
    }
    var floatingCaptionTextSize = FloatingCaptionTextSize.medium {
        didSet { persistSelectedSettings() }
    }
    var floatingCaptionCustomPointSize = FloatingCaptionAppearance.defaultCustomPointSize {
        didSet {
            let clamped = FloatingCaptionAppearance.clampedCustomPointSize(floatingCaptionCustomPointSize)
            guard floatingCaptionCustomPointSize == clamped else {
                floatingCaptionCustomPointSize = clamped
                return
            }
            persistSelectedSettings()
        }
    }
    var floatingCaptionLineCount = FloatingCaptionLineCount.three {
        didSet { persistSelectedSettings() }
    }
    var keepsFloatingCaptionAboveOtherWindows = true {
        didSet { persistSelectedSettings() }
    }
    var floatingCaptionStability = FloatingCaptionStability.balanced {
        didSet { persistSelectedSettings() }
    }
    var floatingCaptionTextAlignment = FloatingCaptionTextAlignment.center {
        didSet { persistSelectedSettings() }
    }
    var floatingCaptionStyle = FloatingCaptionStyle.standard {
        didSet { persistSelectedSettings() }
    }
    var isPreviewingFloatingCaptions = false
    var floatingCaptionTextColorHex = FloatingCaptionAppearance.defaultTextColorHex {
        didSet { persistSelectedSettings() }
    }
    var floatingCaptionBackgroundColorHex = FloatingCaptionAppearance.defaultBackgroundColorHex {
        didSet { persistSelectedSettings() }
    }
    var floatingCaptionBackgroundOpacity = FloatingCaptionAppearance.defaultBackgroundOpacity {
        didSet {
            let clamped = FloatingCaptionAppearance.clampedOpacity(floatingCaptionBackgroundOpacity)
            guard floatingCaptionBackgroundOpacity == clamped else {
                floatingCaptionBackgroundOpacity = clamped
                return
            }
            persistSelectedSettings()
        }
    }
    /// Text width the floating window currently offers, reported by the view so
    /// captions wrap to the real width instead of a per-size estimate. `0` means
    /// unknown and falls back to the estimate.
    var floatingCaptionMeasuredTextWidth: CGFloat = 0
    /// Available caption content height reported by the floating window. Extreme
    /// font and line-count combinations reduce their effective line count to
    /// stay inside the current window instead of clipping a fixed block.
    var floatingCaptionMeasuredContentHeight: CGFloat = 0
    var paragraphBreakSilenceInterval = 5.0 {
        didSet { persistSelectedSettings() }
    }
    var savedTranscriptContentMode = SavedTranscriptContentMode.original {
        didSet { persistSelectedSettings() }
    }
    var sessionDurationMode = SessionDurationMode.standard {
        didSet { persistSelectedSettings() }
    }
    var isAppleSourceAutoDetectionEnabled = false {
        didSet {
            persistSelectedSettings()
            resetTranslationCache()
            resetDubbingProgress()
            refreshModelAvailability()
        }
    }
    var audioInputSource = AudioInputSource.systemAudio {
        didSet { persistSelectedSettings() }
    }
    var selectedMicrophoneInputDeviceID = MicrophoneInputDevice.systemDefaultID {
        didSet { persistSelectedSettings() }
    }
    var microphoneInputDevices = MicrophoneDeviceCatalog.availableInputDevices()
    var statusMessage = AppText.ready
    var captureStartFailureMessage: String?
    var captureStartRecoveryAction: CaptureStartRecoveryAction?
    var toastMessage: String?
    var toastSequence = 0
    var floatingNoticeText: String?
    var lines: [CaptionLine] = []
    var savedTranscripts: [SavedTranscript] = []
    var selectedSavedTranscriptID: String?
    var savedDraftSourceText = ""
    var savedDraftTranslationText = ""
    var pendingAutoDetectionLanguageChange: AutoDetectionLanguageChangeConfirmation?
    var isFoundationTranscriptCleanupRunning = false
    private(set) var latestAudioLevel: Float?
    var modelAvailabilityByModelID = Dictionary(
        uniqueKeysWithValues: IntelligenceModel.allCases.map {
            ($0.id, ModelAvailability.checking(for: $0))
        }
    )

    private let systemAudioCapture = SystemAudioCapture()
    private let microphoneAudioCapture = MicrophoneAudioCapture()
    @ObservationIgnored private var transcriber = LiveSpeechTranscriber()
    @ObservationIgnored private var openAITranscriber = OpenAIRealtimeTranscriber()
    @ObservationIgnored private var geminiLiveTranslator = GeminiLiveTranslationService()
    @ObservationIgnored private var geminiSessionRefreshTask: Task<Void, Never>?
    @ObservationIgnored private var metaVoiceTranscriber = MetaVoiceTranscribeService()
    @ObservationIgnored private var metaSessionRefreshTask: Task<Void, Never>?
    @ObservationIgnored nonisolated private let audioSamplePipelineRegistry = AudioSamplePipelineRegistry()
    @ObservationIgnored nonisolated private let openAITerminalTranscriptMailbox =
        OpenAITerminalTranscriptMailbox()
    private let translator = AppleTranslationService()
    private let openAITranslator = OpenAITranslationService()
    private let foundationTranscriptPolisher = FoundationTranscriptPolisher()
    private let speechOutput = TranslatedSpeechOutput()
    private let openAIRealtimeAudioOutput = OpenAIRealtimeAudioOutput()
    private let spellChecker = NSSpellChecker.shared
    private let spellDocumentTag = NSSpellChecker.uniqueSpellDocumentTag()
    private let modelAvailabilityProvider: (LanguageOption, LanguageOption) async -> [String: ModelAvailability]
    private let modelAssetDownloader: ((IntelligenceModel, LanguageOption, LanguageOption) async throws -> Void)?
    private let translationAssetDownloader = TranslationAssetDownloader()
    private let translationSessionPreparer: (
        @Sendable (LanguageOption, LanguageOption, IntelligenceModel) async throws -> Void
    )?
    private let transcriptsDirectoryOverride: URL?
    private let settingsDefaults: UserDefaults
    private var audioSampleCount = 0
    private var lastRecognizedText = ""
    private var lastRecognizedWasFinal = false
    private var lastRecognitionAt = Date.distantPast
    private var currentLineID: UUID?
    private var lastCaptionPresentationUpdateAt = Date.distantPast
    private var pendingCaptionPresentation: PendingCaptionPresentation?
    private var captionPresentationTask: Task<Void, Never>?
    private var pendingRecognizedCaption: PendingRecognizedCaption?
    private var recognizedCaptionDeliveryTask: Task<Void, Never>?
    private var lastRecognizedCaptionDeliveryAt = Date.distantPast
    private var isLargeTranscriptRecognitionCoalescingActive = false
#if DEBUG
    var usesManualCaptionDeliveryForTesting = false

    func receiveCaptionForTesting(_ text: String, metadata: AppleSpeechRecognitionMetadata? = nil) {
        enqueueRecognizedCaption(sourceText: text, recognizedLanguage: .english, confidence: 0.9, metadata: metadata)
    }

    func flushCaptionDeliveryForTesting() {
        flushPendingRecognizedCaption()
        flushPendingCaptionPresentation()
    }

    func completeAppleTranslationForTesting(_ text: String, requestedLine: CaptionLine, metadata: AppleSpeechRecognitionMetadata) {
        updateTranslation(text, for: requestedLine, matching: requestedLine.sourceText, appleIdentity: AppleTranslationRequestIdentity(
            lineID: requestedLine.id, sourceText: requestedLine.sourceText,
            segmentID: metadata.segmentID, revision: metadata.revision, isFinal: metadata.isFinal
        ))
    }

    func unspokenAppleTextForTesting(_ text: String, lineID: UUID) -> String? {
        unspokenTranslatedText(text, isFinal: true, appleLineID: lineID)
    }
#endif
    private var transcriptCleanupTask: Task<Void, Never>?
    private var translationTask: Task<Void, Never>?
    private var translationTaskGeneration = 0
    private var translationSessionWarmupTask: Task<Void, Never>?
    private var translationSessionWarmupGeneration: UInt64?
    private var latestTranslationRequest: TranslationRequest?
    private var orderedTranslationRequests: [TranslationRequest] = []
    private var translationBurstStartedAt = Date.distantPast
    private var committedSourceText = ""
    private var currentPartialText = ""
    private var currentPartialLanguage: LanguageOption?
    private var appleRolloverReplayGuard: (lineID: UUID, units: [TranscriptUnit])?
    private var pendingParagraphBreakBeforePartial = false
    private var floatingCommittedSourceText = ""
    private var floatingCurrentPartialText = ""
    private var pendingFloatingParagraphBreakBeforePartial = false
    private var floatingPresentedSourceText = ""
    private var floatingQueuedSourceText = ""
    private var floatingPresentedAt = Date.distantPast
    private var floatingPresentedUnreadLength = 0
    private var appleAutoDetectionPreferredLanguage: LanguageOption?
    private var floatingDisplayTranslationText = ""
    private var floatingDisplayTranslationSourceText = ""
    private var floatingQueuedTranslationText = ""
    private var floatingQueuedTranslationSourceText = ""
    private var floatingTranslationPresentedAt = Date.distantPast
    private var floatingTranslationUnreadLength = 0
    private var floatingTranslationHoldTask: Task<Void, Never>?
    private var floatingPresentationTask: Task<Void, Never>?
    private var sourceLanguageByLineID: [UUID: LanguageOption] = [:]
    private var pendingTranslationSourceText = ""
    private var translationSegmentCache = TranslationSegmentCache(
        capacity: TranslationSessionStore.maxTranslationCacheEntries
    )
    private let appleRecognitionTranslationPolicy = AppleRecognitionTranslationPolicy()
    private var appleRecognitionTranslationState = AppleRecognitionTranslationPolicy.State()
    private var appleSpeechSegmentIDByLineID: [UUID: String] = [:]
    private var appleSpeechRevisionByLineID: [UUID: Int] = [:]
    private var appleSmallPartialFlushTask: Task<Void, Never>?
    private var realtimeTranslationSourceText = ""
    private var realtimeTranslationOnlyText = ""
    private var geminiLiveInputTranscriptText = ""
    private var geminiLiveOutputTranscriptText = ""
    private var metaActiveTurnID: Int32?
    private var metaTurnLineIDs: [Int32: UUID] = [:]
    private var metaTurnSpeakerLabels: [Int32: String] = [:]
    private var metaSavedTranscriptText = ""
    private var activeAutosaveSourceText = ""
    private var activeAutosaveTranslatedText = ""
    private var activeAutosaveBaseFileName: String?
    private var transcriptCheckpointTask: Task<Void, Never>?
    private let transcriptCheckpointInterval: TimeInterval
    private var isRestoringSelectedSettings = false
    private var isUpdatingLanguagePair = false
    private var modelAvailabilityTask: Task<Void, Never>?
    private var modelAssetDownloadTask: Task<Void, Never>?
    private var modelAssetDownloadRequest: ModelAssetDownloadRequest?

    private struct ModelAssetDownloadRequest {
        let id = UUID()
        let model: IntelligenceModel
        let configuration: StartConfiguration
        let startsAfterDownload: Bool

        var affectedModels: [IntelligenceModel] {
            model == .appleSystem ? [.appleSystem, .appleSpeechOnly, .appleOnDevice] : [model, .appleSystem]
        }
    }

    var isDownloadingModelAssets: Bool { modelAssetDownloadRequest != nil }
    private var toastDismissTask: Task<Void, Never>?
    private var transcribeOnlyNoticeDismissTask: Task<Void, Never>?
    private var captureStartTask: Task<Void, Never>?
    private var activeCaptureStartGeneration: UInt64?
#if DEBUG
    private var permissionSuspendedStartContinuations: [UInt64: CheckedContinuation<Void, Never>] = [:]
#endif
    private var captureStopTask: Task<Void, Never>?
    private var pipelineLifecycle = PipelineLifecycleState()
    private var activeCaptionerGeneration: UInt64?
    private var dubbingSpeechProgress = DubbingSpeechProgress()
    private var appleDubbingProgressByLineID: [UUID: DubbingSpeechProgress] = [:]
    private var appleDubbingLineOrder: [UUID] = []
    private var hasShownTranscribeOnlyNoticeForCurrentActivation = false
    private var floatingCaptionDisplayModeBeforeTranscribeOnly: FloatingCaptionDisplayMode?
    private var appleVoiceOutputEnabled = false
    private var providerVoiceOutputEnabled = true
    private var isApplyingVoiceOutputDefault = false

    private enum SavedTranscriptPart {
        case original
        case translation
    }

    private var usesLongSessionMode: Bool {
        sessionDurationMode == .thirtyMinutesOrMore
    }

    var shouldCoalesceTranscriptAutoScroll: Bool {
        isRunning || usesLongSessionMode
    }

    var isUsingOpenAIRealtime: Bool {
        openAITranscriptionModel.isEnabled || openAITranslationModel.isSupportedLiveTranslationModel
    }

    var isUsingGPTTranscriptionMode: Bool {
        openAITranscriptionModel == .gptLiveTranscribe
    }

    var isUsingOpenAIRealtimeTranslation: Bool {
        openAITranslationModel.usesRealtimeAudioTranslation
    }

    var isUsingGeminiTranslation: Bool {
        geminiTranslationModel.isTranslation
    }

    var isUsingGemini: Bool {
        geminiTranslationModel.isEnabled
    }

    var isUsingGeminiTranscriptionMode: Bool {
        geminiTranslationModel.isTranscription
    }

    var isUsingMetaScribe: Bool {
        metaTranscriptionModel.isEnabled
    }

    var isUsingNariSTT: Bool {
        nariTranscriptionModel.isEnabled
    }

    var isUsingGrokSTT: Bool {
        grokTranscriptionModel.isEnabled
    }

    private var usesAppleCaptionRollover: Bool {
        isRunning
            && !isUsingOpenAIRealtime
            && !isUsingGeminiTranscriptionMode
            && !isUsingMetaScribe
            && !isUsingAzureMAI
            && !isUsingNariSTT
            && !isUsingGrokSTT
            && !isUsingQwenTranslation
    }

    var isUsingProviderTranscriptionMode: Bool {
        isUsingGPTTranscriptionMode || isUsingGeminiTranscriptionMode
    }

    var isUsingProviderRealtimeTranslation: Bool {
        isUsingQwenTranslation || isUsingOpenAIRealtimeTranslation || isUsingGeminiTranslation
    }

    var isTranscribeOnlyMode: Bool {
        selectedModel == .appleSpeechOnly || isUsingProviderTranscriptionMode
    }

    var liveOutputMode: LiveOutputMode {
        isTranscribeOnlyMode ? .transcription : .translation
    }

    private struct SavedTranscriptFile {
        let fileName: String
        let previewText: String
        let updatedAt: Date
    }

    private struct PartialSavedTranscript {
        var original: SavedTranscriptFile?
        var translation: SavedTranscriptFile?
    }

    init(
        modelAvailabilityProvider: @escaping (LanguageOption, LanguageOption) async -> [String: ModelAvailability] = { source, target in
            await ModelAvailabilityChecker.availability(source: source, target: target)
        },
        modelAssetDownloader: ((IntelligenceModel, LanguageOption, LanguageOption) async throws -> Void)? = nil,
        translationSessionPreparer: (
            @Sendable (LanguageOption, LanguageOption, IntelligenceModel) async throws -> Void
        )? = nil,
        settingsDefaults: UserDefaults = .standard,
        transcriptsDirectoryURL: URL? = nil,
        transcriptCheckpointInterval: TimeInterval = TranslationSessionStore.defaultTranscriptCheckpointInterval
    ) {
        self.modelAvailabilityProvider = modelAvailabilityProvider
        self.modelAssetDownloader = modelAssetDownloader
        self.translationSessionPreparer = translationSessionPreparer
        self.settingsDefaults = settingsDefaults
        self.transcriptsDirectoryOverride = transcriptsDirectoryURL
        self.transcriptCheckpointInterval = transcriptCheckpointInterval
        restoreSelectedSettings()
        applyTranslatedVoiceVolume()
        syncLiveOutputModeWithLanguagePair()
        systemAudioCapture.delegate = self
        microphoneAudioCapture.delegate = self
        transcriber.delegate = self
        openAITranscriber.delegate = self
        configureOpenAITerminalTranscriptDelivery(for: openAITranscriber)
        geminiLiveTranslator.delegate = self
        metaVoiceTranscriber.delegate = self
        loadSavedTranscripts()
        loadProductHuntScreenshotDemoIfRequested()
        refreshModelAvailability()
    }

    private func loadProductHuntScreenshotDemoIfRequested() {
        guard ProcessInfo.processInfo.environment["AIRTRANSLATE_PRODUCT_HUNT_SCREENSHOTS"] == "1" else {
            return
        }

        let now = Date()
        hasOpenAIAPIKey = false
        lines = [
            CaptionLine(
                sourceText: "The speaker is explaining how the product roadmap changes when customers need live translation during meetings.",
                translatedText: "The speaker is explaining how the product roadmap changes when customers need live translation during meetings.",
                translatedSourceText: "The speaker is explaining how the product roadmap changes when customers need live translation during meetings.",
                createdAt: now.addingTimeInterval(-12),
                isFinal: true
            ),
            CaptionLine(
                sourceText: "AirTranslate keeps captions visible while you watch a lecture, interview, stream, or video on your Mac.",
                translatedText: "AirTranslate keeps captions visible while you watch a lecture, interview, stream, or video on your Mac.",
                translatedSourceText: "AirTranslate keeps captions visible while you watch a lecture, interview, stream, or video on your Mac.",
                createdAt: now,
                isFinal: true
            ),
        ]

        let demoTranscript = SavedTranscript(
            id: "product-hunt-demo",
            sourceFileName: "product-hunt-demo_original.txt",
            translationFileName: "product-hunt-demo_translation.txt",
            sourceText: "AirTranslate keeps captions visible while you watch a lecture, interview, stream, or video on your Mac.",
            translatedText: "AirTranslate keeps captions visible while you watch a lecture, interview, stream, or video on your Mac.",
            updatedAt: now
        )
        savedTranscripts = [demoTranscript]
        selectedSavedTranscriptID = demoTranscript.id
        savedDraftSourceText = demoTranscript.sourceText
        savedDraftTranslationText = demoTranscript.translatedText ?? ""
    }

    func start() {
        isPreviewingFloatingCaptions = false
        guard !isRunning, !isStarting else { return }

        let readiness = startReadinessAssessment()
        guard readiness.canStart else {
            if readiness.issue == .localAssetsDownloadRequired,
               let model = requiredLocalModelForStart {
                dismissCaptureStartFailure()
                downloadRequiredModelAssetsThenStart(model)
                return
            }
            presentCaptureStartFailure(
                statusMessage(for: readiness),
                recoveryAction: recoveryAction(for: readiness)
            )
            return
        }

        captureStartFailureMessage = nil
        captureStartRecoveryAction = nil
        invalidateCaptureStartAttempt()
        let configuration = currentStartConfiguration()
        let generation = pipelineLifecycle.beginStart(configuration: configuration)
        activeCaptureStartGeneration = generation
        isPaused = false
        setCaptionersPaused(false)
        isStarting = true
        statusMessage = configuration.audioInputSource == .microphone
            ? AppText.checkingMicrophonePermission
            : AppText.checkingScreenPermission

        captureStartTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.completeCaptureStartAttempt(generation: generation) }
            do {
                if let captureStopTask {
                    await captureStopTask.value
                    self.captureStopTask = nil
                }
                try validatePipelineStart(generation: generation, configuration: configuration)
                if configuration.audioInputSource == .systemAudio {
                    try systemAudioCapture.requestScreenRecordingAccess()
                }
                try validatePipelineStart(generation: generation, configuration: configuration)
                if configuration.isUsingGPTTranscriptionMode {
                    statusMessage = AppText.connectingGPTTranscription
                } else if configuration.geminiTranslationModel.isEnabled {
                    statusMessage = AppText.connectingGeminiLiveTranslation
                } else if configuration.metaTranscriptionModel.isEnabled {
                    statusMessage = AppText.connectingMetaScribe
                } else if configuration.qwenTranslationModel.isEnabled {
                    statusMessage = QwenCopy.connecting
                } else if configuration.grokTranscriptionModel.isEnabled {
                    statusMessage = GrokCopy.connecting
                } else if configuration.nariTranscriptionModel.isEnabled {
                    statusMessage = NariCopy.connecting
                } else {
                    statusMessage = AppText.checkingSpeechPermission
                }
                try await startCaptioners(
                    configuration: configuration,
                    generation: generation
                )
                try validatePipelineStart(generation: generation, configuration: configuration)
                audioSamplePipelineRegistry.publish(
                    generation: generation,
                    transcriber: transcriber,
                    openAITranscriber: openAITranscriber,
                    geminiLiveTranslator: geminiLiveTranslator,
                    metaVoiceTranscriber: metaVoiceTranscriber,
                    azureMAITranscriber: azureMAITranscriber,
                    grokTranscriber: grokTranscriber,
                    nariTranscriber: nariTranscriber,
                    qwenTranslator: qwenTranslator
                )

                statusMessage = AppText.startingCapture(for: configuration.audioInputSource)
                switch configuration.audioInputSource {
                case .systemAudio:
                    try await systemAudioCapture.start(
                        sampleRate: configuration.sampleRate,
                        generation: generation
                    )
                case .microphone:
                    try await microphoneAudioCapture.start(
                        sampleRate: configuration.sampleRate,
                        deviceUniqueID: configuration.microphoneDeviceUniqueID,
                        generation: generation
                    )
                }
                try validatePipelineStart(generation: generation, configuration: configuration)
                let promotion = pipelineLifecycle.markRunning(
                    generation: generation,
                    currentConfiguration: currentStartConfiguration()
                )
                switch promotion {
                case .valid:
                    break
                case .configurationChanged:
                    throw PipelineStartError.configurationChanged
                case .staleGeneration:
                    throw CancellationError()
                }
                resetLiveSessionState(clearsVisibleLines: true)
                isRunning = true
                isStarting = false
                captureStartFailureMessage = nil
                captureStartRecoveryAction = nil
                statusMessage = AppText.listeningForSpeech(from: configuration.audioInputSource)
                warmTranslationSession()
            } catch let error as CancellationError {
                await handleCancelledCaptureStart(
                    generation: generation,
                    error: error
                )
            } catch let error as PipelineStartError {
                await handlePipelineStartError(
                    error,
                    generation: generation
                )
            } catch {
                await handleCaptureStartFailure(
                    error,
                    generation: generation,
                    configuration: configuration
                )
            }
        }
    }

    func stop() {
        guard isRunning || isStarting else { return }
        if isUsingQwenTranslation, isRunning {
            finishQwenCapture()
            return
        }
        if isUsingGrokSTT, isRunning {
            finishGrokCapture()
            return
        }
        if isUsingNariSTT, isRunning {
            finishNariCapture()
            return
        }
        if isUsingAzureMAI, isRunning {
            guard !isFinishingAzureMAI else { return }
            isFinishingAzureMAI = true
            statusMessage = AzureMAICopy.finishing
            audioSamplePipelineRegistry.clear()
            let service = azureMAITranscriber
            azureFinishTask = Task { @MainActor [weak self] in
                guard let self else { return }
                await stopCapture()
                await service.finish()
                guard !Task.isCancelled, service === azureMAITranscriber, isRunning else { return }
                isFinishingAzureMAI = false
                pipelineLifecycle.stop()
                finishPipeline(statusOverride: nil)
                azureFinishTask = nil
            }
            return
        }
        pipelineLifecycle.stop()
        finishPipeline(statusOverride: nil)
    }

    private func finishPipeline(statusOverride: String?) {
        isFinishingQwenTranslation = false
        isReconnectingQwenTranslation = false
        isFinishingGrokSTT = false
        isReconnectingGrokSTT = false
        isFinishingNariSTT = false
        isReconnectingNariSTT = false
        isFinishingAzureMAI = false
        invalidateCaptureStartAttempt()
        cancelTranslationSessionWarmup()
        if cancelModelAssetDownload() {
            refreshModelAvailability()
        }
        transcriptCheckpointTask?.cancel()
        transcriptCheckpointTask = nil
        openAITranscriber.stop()
        flushOpenAITerminalTranscriptMailbox()
        flushPendingRecognizedCaption()
        flushPendingCaptionPresentation()
        let hadTranscriptToSave = isTranscriptPersistenceEnabled
            && (!visibleTranscript().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !activeAutosaveSourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            )
        let didSaveTranscript = flushPendingTranscriptSave()
        resetLiveSessionState(clearsVisibleLines: false)
        isPaused = false
        setCaptionersPaused(false)
        isStarting = false
        isRunning = false
        if let statusOverride {
            statusMessage = statusOverride
        } else if didSaveTranscript {
            statusMessage = AppText.transcriptSavedToast
        } else if !hadTranscriptToSave {
            statusMessage = AppText.stopped
        }
        stopCaptioners(openAITranscriberAlreadyStopped: true)
        if didSaveTranscript {
            showToast(AppText.transcriptSavedToast)
        }

        let previousStopTask = captureStopTask
        captureStopTask = Task { @MainActor in
            if let previousStopTask {
                await previousStopTask.value
            }
            await stopCapture()
        }
    }

    private func invalidateCaptureStartAttempt() {
        activeCaptureStartGeneration = nil
        captureStartTask?.cancel()
        captureStartTask = nil
    }

    private func completeCaptureStartAttempt(generation: UInt64) {
        guard activeCaptureStartGeneration == generation else { return }
        activeCaptureStartGeneration = nil
        captureStartTask = nil
        if !isRunning {
            isStarting = false
        }
    }

    private func handleCancelledCaptureStart(
        generation: UInt64,
        error: Error
    ) async {
        guard pipelineLifecycle.fail(generation: generation) else {
            // stop() may have invalidated this task while a permission prompt
            // was suspended. It must not affect a newer generation, but it can
            // still have resumed and initialized the old captioners.
            stopCaptionersIfOwned(by: generation)
            return
        }

        isStarting = false
        isRunning = false
        stopCaptioners()
        await stopCapture()
        statusMessage = AppText.startFailed(error.localizedDescription)
    }

    private func handlePipelineStartError(
        _ error: PipelineStartError,
        generation: UInt64
    ) async {
        if pipelineLifecycle.isActive(generation: generation) {
            _ = pipelineLifecycle.fail(generation: generation)
        }
        guard activeCaptureStartGeneration == generation else {
            stopCaptionersIfOwned(by: generation)
            return
        }

        isStarting = false
        isRunning = false
        stopCaptioners()
        await stopCapture()
        presentCaptureStartFailure(
            AppText.startFailed(error.localizedDescription),
            recoveryAction: .retry
        )
    }

    private func stopCaptionersIfOwned(by generation: UInt64) {
        guard activeCaptionerGeneration == generation else { return }
        stopCaptioners()
    }

    private func currentStartConfiguration() -> StartConfiguration {
        StartConfiguration(
            audioInputSource: audioInputSource,
            microphoneDeviceUniqueID: selectedMicrophoneDevice.uniqueID,
            sourceLanguage: sourceLanguage,
            targetLanguage: targetLanguage,
            selectedModel: selectedModel,
            openAITranscriptionModel: openAITranscriptionModel,
            openAITranslationModel: openAITranslationModel,
            geminiTranslationModel: geminiTranslationModel,
            metaTranscriptionModel: metaTranscriptionModel,
            qwenTranslationModel: qwenTranslationModel,
            qwenWorkspaceID: qwenWorkspaceID,
            qwenAudioOutputEnabled: isUsingQwenTranslation && isDubbingEnabled,
            grokTranscriptionModel: grokTranscriptionModel,
            usesGrokSourceAutoDetection: isGrokSourceAutoDetectionEnabled,
            nariTranscriptionModel: nariTranscriptionModel,
            usesNariSourceAutoDetection: isNariSourceAutoDetectionEnabled,
            azureMAIEnabled: isUsingAzureMAI,
            azureSpeechEndpoint: azureSpeechEndpoint,
            usesMetaSpeakerLabels: isMetaSpeakerLabelsEnabled,
            usesAppleSourceAutoDetection: isUsingAppleSourceAutoDetection
        )
    }

    private func validatePipelineStart(
        generation: UInt64,
        configuration: StartConfiguration
    ) throws {
        guard !Task.isCancelled, isStarting else {
            throw CancellationError()
        }

        switch pipelineLifecycle.validateStart(
            generation: generation,
            currentConfiguration: currentStartConfiguration()
        ) {
        case .valid:
            guard configuration == currentStartConfiguration() else {
                throw PipelineStartError.configurationChanged
            }
        case .staleGeneration:
            throw CancellationError()
        case .configurationChanged:
            throw PipelineStartError.configurationChanged
        }
    }

    private func handleFatalPipelineError(
        _ error: Error,
        generation: UInt64? = nil
    ) {
        let didEndLifecycle: Bool
        if let generation {
            didEndLifecycle = pipelineLifecycle.fail(generation: generation)
        } else {
            didEndLifecycle = pipelineLifecycle.failCurrent()
        }
        guard didEndLifecycle, isRunning || isStarting else { return }

        finishPipeline(statusOverride: error.localizedDescription)
    }

    private func handleSystemAudioCaptureStoppedByUser(generation: UInt64) {
        if isUsingQwenTranslation, isRunning, pipelineLifecycle.acceptsSample(generation: generation) {
            finishQwenCapture()
            return
        }
        if isUsingGrokSTT, isRunning, pipelineLifecycle.acceptsSample(generation: generation) {
            finishGrokCapture()
            return
        }
        if isUsingNariSTT, isRunning, pipelineLifecycle.acceptsSample(generation: generation) {
            finishNariCapture()
            return
        }
        guard pipelineLifecycle.fail(generation: generation),
              isRunning || isStarting
        else {
            return
        }

        finishPipeline(statusOverride: nil)
    }

    private func handleCaptureStartFailure(
        _ error: Error,
        generation: UInt64,
        configuration: StartConfiguration
    ) async {
        if configuration.audioInputSource == .systemAudio,
           SystemAudioCapture.isUserStoppedError(error) {
            handleSystemAudioCaptureStoppedByUser(generation: generation)
            return
        }

        guard pipelineLifecycle.fail(generation: generation) else {
            // A capture/provider callback already ended this generation.
            return
        }
        isStarting = false
        isRunning = false
        stopCaptioners()
        await stopCapture()
        presentCaptureStartFailure(
            AppText.startFailed(error.localizedDescription),
            recoveryAction: .forFailure(error, audioInputSource: configuration.audioInputSource)
        )
    }

    func startReadinessAssessment() -> StartReadinessAssessment {
        if isUsingQwenTranslation, !hasQwenConfiguration {
            return .init(issue: .qwenConfigurationMissing)
        }
        if isUsingGrokSTT {
            if !hasGrokAPIKey { return .init(issue: .grokAPIKeyMissing) }
            if !isGrokSourceAutoDetectionEnabled, GrokTranscriptionModel.languageCode(for: sourceLanguage) == nil {
                return .init(issue: .grokLanguageUnsupported)
            }
        }
        if isUsingNariSTT {
            if nariTranscriptionModel.isLegacyFreeEndpoint {
                return StartReadinessAssessment(issue: .nariLegacyFreeModelSelected)
            }
            if !hasNariAPIKey {
                return StartReadinessAssessment(issue: .nariAPIKeyMissing)
            }
            if !isNariSourceAutoDetectionEnabled,
               NariTranscriptionModel.languageCode(for: sourceLanguage) == nil {
                return StartReadinessAssessment(issue: .nariLanguageUnsupported)
            }
        }
        if isUsingAzureMAI, !hasAzureSpeechAPIKey || (try? AzureMAITranscriber.endpointURL(azureSpeechEndpoint)) == nil {
            return StartReadinessAssessment(issue: .azureConfigurationMissing)
        }
        return StartReadinessPolicy.assess(
            requiresOpenAIAPIKey: isUsingOpenAIRealtime,
            hasOpenAIAPIKey: hasOpenAIAPIKey,
            requiresGeminiAPIKey: isUsingGemini,
            hasGeminiAPIKey: hasGeminiAPIKey,
            requiresMetaAPIKey: isUsingMetaScribe,
            hasMetaAPIKey: hasMetaAPIKey,
            requiredLocalModelAvailability: requiredLocalModelForStart.map { modelAvailability(for: $0) }
        )
    }

    private var requiredLocalModelForStart: IntelligenceModel? {
        if isUsingQwenTranslation { return nil }
        if isUsingNariSTT || isUsingGrokSTT {
            return isTranscribeOnlyMode ? nil : .appleOnDevice
        }
        if openAITranslationModel.usesRealtimeAudioTranslation {
            return nil
        }
        if openAITranscriptionModel.isEnabled {
            return isTranscribeOnlyMode ? nil : .appleOnDevice
        }
        if isUsingMetaScribe || isUsingAzureMAI {
            return .appleOnDevice
        }
        if isUsingGemini {
            return nil
        }
        return selectedModel
    }

    private func statusMessage(for readiness: StartReadinessAssessment) -> String {
        switch readiness.issue {
        case nil:
            return AppText.ready
        case .openAIAPIKeyMissing:
            return AppText.openAIAPIKeyRequiredForGPTMode
        case .geminiAPIKeyMissing:
            return AppText.geminiAPIKeyMissing
        case .azureConfigurationMissing:
            return AzureMAICopy.configurationRequired
        case .metaAPIKeyMissing:
            return AppText.metaAPIKeyMissing
        case .qwenConfigurationMissing:
            return QwenCopy.configurationRequired(for: qwenTranslationModel)
        case .grokAPIKeyMissing:
            return GrokCopy.configurationRequired
        case .grokLanguageUnsupported:
            return GrokCopy.languageUnsupported
        case .nariAPIKeyMissing:
            return NariCopy.configurationRequired
        case .nariLanguageUnsupported:
            return NariCopy.languageUnsupported
        case .nariLegacyFreeModelSelected:
            return NariCopy.legacyFreeModelEnded
        case .localAssetsChecking:
            return AppText.startBlockedLocalAssetsChecking
        case .localAssetsDownloadRequired:
            return AppText.startBlockedLocalAssetsDownloadRequired
        case .localAssetsUnavailable(let detail):
            return AppText.startBlockedLocalAssetsUnavailable(detail)
        }
    }

    private func recoveryAction(for readiness: StartReadinessAssessment) -> CaptureStartRecoveryAction? {
        CaptureStartRecoveryAction.forReadiness(readiness)
    }

    func dismissCaptureStartFailure() {
        captureStartFailureMessage = nil
        captureStartRecoveryAction = nil
    }

    private func presentCaptureStartFailure(
        _ message: String,
        recoveryAction: CaptureStartRecoveryAction?
    ) {
        statusMessage = message
        captureStartFailureMessage = message
        captureStartRecoveryAction = recoveryAction
    }

    func pause() {
        guard isRunning, !isPaused, !isFinishingAzureMAI, !isFinishingNariSTT, !isFinishingGrokSTT, !isFinishingQwenTranslation, !isReconnectingQwenTranslation else { return }

        if isUsingQwenTranslation {
            pauseQwenCapture()
            return
        }
        if isUsingGrokSTT {
            pauseGrokCapture()
            return
        }
        if isUsingNariSTT {
            pauseNariCapture()
            return
        }

        flushPendingRecognizedCaption()
        flushPendingCaptionPresentation()
        transcriptCleanupTask?.cancel()
        transcriptCleanupTask = nil
        commitCurrentPartial()
        organizeCurrentTranscript(sourceTextOverride: visibleTranscript())
        _ = checkpointPendingTranscriptSave()
        setCaptionersPaused(true)
        stopSpeaking()
        isPaused = true
        statusMessage = AppText.paused
    }

    func resume() {
        guard isRunning, isPaused, !isFinishingAzureMAI, !isFinishingNariSTT, !isReconnectingNariSTT, !isFinishingGrokSTT, !isReconnectingGrokSTT, !isFinishingQwenTranslation, !isReconnectingQwenTranslation else { return }
        if isUsingQwenTranslation {
            resumeQwenCapture()
            return
        }
        if isUsingGrokSTT {
            resumeGrokCapture()
            return
        }
        if isUsingNariSTT {
            resumeNariCapture()
            return
        }
        pendingAutoDetectionLanguageChange = nil

        setCaptionersPaused(false)
        isPaused = false
        lastRecognitionAt = Date()
        statusMessage = AppText.listeningForSpeech(from: audioInputSource)
    }

    func confirmAutoDetectionLanguageChange() {
        guard let pendingAutoDetectionLanguageChange else { return }

        self.pendingAutoDetectionLanguageChange = nil
        let detectedLanguage = pendingAutoDetectionLanguageChange.detectedLanguage
        let bufferedSourceText = pendingAutoDetectionLanguageChange.sourceText
        let bufferedConfidence = pendingAutoDetectionLanguageChange.confidence
        let didSaveTranscript = flushPendingTranscriptSave()

        resetLiveSessionState(clearsVisibleLines: true)
        appleAutoDetectionPreferredLanguage = detectedLanguage
        setCaptionersPaused(false)
        isPaused = false
        lastRecognitionAt = Date()
        statusMessage = AppText.listeningForSpeech(from: audioInputSource)

        if didSaveTranscript {
            showToast(AppText.transcriptSavedToast)
        }

        Task { @MainActor in
            appendCaption(
                sourceText: bufferedSourceText,
                recognizedLanguage: detectedLanguage,
                confidence: bufferedConfidence,
                isFinal: false
            )
        }
    }

    func keepCurrentAutoDetectionLanguage() {
        guard pendingAutoDetectionLanguageChange != nil else { return }

        pendingAutoDetectionLanguageChange = nil
        setCaptionersPaused(false)
        isPaused = false
        lastRecognitionAt = Date()
        statusMessage = AppText.listeningForSpeech(from: audioInputSource)
    }

    func showAppleSourceAutoDetectionUnavailableNotice() {
        isAppleSourceAutoDetectionEnabled = false
        showToast(AppText.appleAutoLanguageModeUnavailableToast)
    }

    func prepareForTermination() {
        cancelModelAssetDownload()
        cancelTranslationSessionWarmup()
        transcriptCheckpointTask?.cancel()
        transcriptCheckpointTask = nil
        flushPendingRecognizedCaption()
        flushPendingCaptionPresentation()
        _ = flushPendingTranscriptSave()
    }

    func openPrivacySettings() {
        openPrivacySettings(audioInputSource == .microphone ? .microphone : .screenRecording)
    }

    func openPrivacySettings(_ pane: PrivacySettingsPane) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane.anchor)") else {
            return
        }

        NSWorkspace.shared.open(url)
    }

    var selectedMicrophoneDevice: MicrophoneInputDevice {
        microphoneInputDevices.first { $0.id == selectedMicrophoneInputDeviceID }
            ?? .systemDefault
    }

    func refreshMicrophoneInputDevices() {
        microphoneInputDevices = MicrophoneDeviceCatalog.availableInputDevices()
        if !microphoneInputDevices.contains(where: { $0.id == selectedMicrophoneInputDeviceID }) {
            selectedMicrophoneInputDeviceID = MicrophoneInputDevice.systemDefaultID
        }
    }

    func saveOpenAIAPIKey(_ key: String) throws {
        try OpenAIAPIKeyStore.saveAPIKey(key)
        hasOpenAIAPIKey = true
        statusMessage = AppText.openAIAPIKeySaved
        refreshModelAvailability()
    }

    func removeOpenAIAPIKey() throws {
        try OpenAIAPIKeyStore.deleteAPIKey()
        hasOpenAIAPIKey = false
        statusMessage = AppText.openAIAPIKeyRemoved
        refreshModelAvailability()
    }

    func saveGeminiAPIKey(_ key: String) throws {
        try GeminiAPIKeyStore.saveAPIKey(key)
        hasGeminiAPIKey = true
        statusMessage = AppText.geminiAPIKeySaved
        refreshModelAvailability()
    }

    func removeGeminiAPIKey() throws {
        try GeminiAPIKeyStore.deleteAPIKey()
        hasGeminiAPIKey = false
        statusMessage = AppText.geminiAPIKeyRemoved
        refreshModelAvailability()
    }

    func saveMetaAPIKey(_ key: String) throws {
        try MetaAPIKeyStore.saveAPIKey(key)
        hasMetaAPIKey = true
        statusMessage = AppText.metaAPIKeySaved
        refreshModelAvailability()
    }

    func removeMetaAPIKey() throws {
        try MetaAPIKeyStore.deleteAPIKey()
        hasMetaAPIKey = false
        statusMessage = AppText.metaAPIKeyRemoved
        refreshModelAvailability()
    }

    func openTranscriptsFolder() {
        do {
            try FileManager.default.createDirectory(
                at: transcriptsDirectoryURL,
                withIntermediateDirectories: true
            )
            NSWorkspace.shared.open(transcriptsDirectoryURL)
        } catch {
            statusMessage = AppText.saveLibraryFailed(error.localizedDescription)
        }
    }

    var languageSummary: String {
        if isUsingQwenTranslation { return AppText.openAILanguageSummary(target: targetLanguage.localizedTitle) }
        if isUsingGeminiTranscriptionMode || (isUsingNariSTT && isNariSourceAutoDetectionEnabled) || (isUsingGrokSTT && isGrokSourceAutoDetectionEnabled) {
            return AppText.localized(
                english: "Automatic language detection",
                korean: "입력 언어 자동 감지",
                japanese: "入力言語を自動検出",
                chineseSimplified: "自动检测输入语言"
            )
        }
        if isTranscribeOnlyMode {
            return AppText.transcribeLanguageSummary(source: sourceLanguage.localizedTitle)
        }
        if isUsingOpenAIRealtimeTranslation {
            return AppText.openAILanguageSummary(target: targetLanguage.localizedTitle)
        }
        if isUsingAppleSourceAutoDetection {
            return AppText.openAILanguageSummary(target: targetLanguage.localizedTitle)
        }
        return AppText.languageSummary(source: sourceLanguage.localizedTitle, target: targetLanguage.localizedTitle)
    }

    var isUsingAppleSourceAutoDetection: Bool {
        isAppleSourceAutoDetectionAvailable
            && isAppleSourceAutoDetectionEnabled
            && !openAITranscriptionModel.isEnabled
            && !openAITranslationModel.isEnabled
            && !isUsingGeminiTranslation
            && !isUsingQwenTranslation
    }

    var isAppleSourceAutoDetectionAvailable: Bool {
        !Self.isAppleSourceAutoDetectionTemporarilyDisabled
    }

    func usePreferredLanguageForOpenAIOutput() {
        let preferredLanguage = LanguageOption.preferredSystemLanguage(fallback: targetLanguage)
        if targetLanguage != preferredLanguage {
            targetLanguage = preferredLanguage
        }
    }

    func useQuickSourceLanguage(_ language: LanguageOption) {
        guard !isRunning else { return }
        guard !isTranscribeOnlyMode else {
            sourceLanguage = language
            return
        }

        let previousSourceLanguage = sourceLanguage
        let nextTargetLanguage = language == targetLanguage
            ? fallbackTargetLanguage(excluding: language, preferred: previousSourceLanguage)
            : targetLanguage
        updateLanguagePair(source: language, target: nextTargetLanguage)
    }

    func useQuickTargetLanguage(_ language: LanguageOption) {
        guard !isRunning else { return }
        guard !isTranscribeOnlyMode else { return }
        guard isUsingQwenTranslation || language != sourceLanguage else {
            showToast(AppText.sameLanguageTranslationUnavailable)
            return
        }

        updateLanguagePair(source: sourceLanguage, target: language)
    }

    func swapQuickLanguagePair() {
        guard !isRunning, !isTranscribeOnlyMode else { return }

        updateLanguagePair(
            source: targetLanguage,
            target: fallbackTargetLanguage(excluding: targetLanguage, preferred: sourceLanguage)
        )
    }

    func requestAPIKeySettings(provider: CredentialProvider? = nil) {
        requestedAPIKeyProvider = provider
        requestedSettingsCategoryID = "apiKeys"
    }

    func requestGeneralSettings() {
        requestedAPIKeyProvider = nil
        requestedSettingsCategoryID = "general"
    }

    func useAppleDefaultMode() {
        qwenTranslationModel = .off
        grokTranscriptionModel = .off
        nariTranscriptionModel = .off
        isUsingAzureMAI = false
        clearTranscribeOnlyNotice(resetActivation: true)
        selectedModel = .appleSystem
        openAITranscriptionModel = .off
        openAITranslationModel = .off
        geminiTranslationModel = .off
        metaTranscriptionModel = .off
        applyAppleVoiceOutputDefault()
        restoreFloatingCaptionDisplayModeAfterTranscribeOnly()
    }

    // 제공자는 OpenAI로 유지하고 출력 목적에 맞는 기존 음성 모델을 선택한다.
    func useOpenAIMode(_ mode: LiveOutputMode? = nil) {
        guard !isRunning, !isStarting else { return }
        let mode = mode ?? openAIOutputMode
        let wasUsingOpenAI = isUsingOpenAIRealtime
        if preferredOpenAIOutputMode != mode {
            preferredOpenAIOutputMode = mode
        }
        guard !wasUsingOpenAI || liveOutputMode != mode else { return }
        switch mode {
        case .translation:
            useGPTRealtimeMode(model: .gptRealtimeTranslate, preservePreferences: wasUsingOpenAI)
        case .transcription:
            useGPTTranscriptionMode()
        }
    }

    func useGPTRealtimeMode() {
        useGPTRealtimeMode(model: openAITranslationModel.isEnabled ? openAITranslationModel : .gptRealtimeTranslate)
    }

    func useGPTRealtimeMode(model: OpenAIRealtimeTranslationModel, preservePreferences: Bool = false) {
        preferredOpenAIOutputMode = .translation
        let selectedOpenAIModel = model.isSupportedLiveTranslationModel ? model : .gptRealtimeTranslate
        clearTranscribeOnlyNotice(resetActivation: true)
        selectedModel = .appleSystem
        geminiTranslationModel = .off
        metaTranscriptionModel = .off
        openAITranscriptionModel = .off
        isTranscriptLintEnabled = false
        if openAITranslationModel != selectedOpenAIModel {
            openAITranslationModel = selectedOpenAIModel
        }
        if preservePreferences {
            applyRestoredVoiceOutputPreference()
        } else {
            applyProviderVoiceOutputDefault()
        }
        restoreFloatingCaptionDisplayModeAfterTranscribeOnly()
        if !preservePreferences { usePreferredLanguageForOpenAIOutput() }
    }

    func useGPTTranscriptionMode() {
        preferredOpenAIOutputMode = .transcription
        if floatingCaptionDisplayModeBeforeTranscribeOnly == nil {
            floatingCaptionDisplayModeBeforeTranscribeOnly = floatingCaptionDisplayMode
        }
        selectedModel = .appleSpeechOnly
        geminiTranslationModel = .off
        metaTranscriptionModel = .off
        openAITranslationModel = .off
        if openAITranscriptionModel != .gptLiveTranscribe {
            openAITranscriptionModel = .gptLiveTranscribe
        }
        isTranscriptLintEnabled = false
        floatingCaptionDisplayMode = .original
        isDubbingEnabled = false
        clearTranscribeOnlyNotice(resetActivation: true)
    }

    func useGeminiTranslationMode() {
        useGeminiMode(.gemini35LiveTranslate)
    }

    func usePreferredGeminiMode() {
        useGeminiMode(preferredGeminiModel)
    }

    func useGeminiMode(_ model: GeminiTranslationModel) {
        guard !isRunning, !isStarting else { return }
        guard model.isEnabled else { return }
        clearTranscribeOnlyNotice(resetActivation: true)
        selectedModel = .appleSystem
        openAITranscriptionModel = .off
        openAITranslationModel = .off
        metaTranscriptionModel = .off
        if model.isTranscription {
            prepareTranscribeOnlyPresentation()
        }
        if geminiTranslationModel != model {
            geminiTranslationModel = model
        } else if model.isTranslation {
            restoreFloatingCaptionDisplayModeAfterTranscribeOnly()
        }
        if model.isTranslation {
            applyProviderVoiceOutputDefault()
        } else {
            applyVoiceOutputDefault(false)
        }
    }

    func useAzureMAIMode() {
        guard !isRunning, !isStarting else { return }
        clearTranscribeOnlyNotice(resetActivation: true)
        isUsingAzureMAI = true
        applyAppleVoiceOutputDefault()
        restoreFloatingCaptionDisplayModeAfterTranscribeOnly()
    }

    func useNariSTTMode() {
        guard !isRunning, !isStarting else { return }
        selectedModel = .appleSpeechOnly
        if !isUsingNariSTT {
            nariTranscriptionModel = .qwen3ASRFast
        }
        prepareTranscribeOnlyPresentation()
        clearTranscribeOnlyNotice(resetActivation: true)
    }

    func saveNariAPIKey(_ key: String) throws {
        guard !isRunning, !isStarting else { return }
        try NariAPIKeyStore.saveAPIKey(key)
        hasNariAPIKey = true
    }

    func removeNariAPIKey() throws {
        guard !isRunning, !isStarting else { return }
        try NariAPIKeyStore.deleteAPIKey()
        hasNariAPIKey = false
    }

    func useQwenTranslationMode() {
        guard !isRunning, !isStarting else { return }
        if !qwenTranslationModel.isEnabled {
            qwenTranslationModel = preferredQwenModel
        }
        clearTranscribeOnlyNotice(resetActivation: true)
        applyVoiceOutputDefault(qwenVoiceOutputEnabled)
    }

    func saveQwenAPIKey(_ key: String) throws {
        guard !isRunning, !isStarting else { return }
        try QwenAPIKeyStore.saveAPIKey(key)
        hasQwenAPIKey = true
    }

    func removeQwenAPIKey() throws {
        guard !isRunning, !isStarting else { return }
        try QwenAPIKeyStore.deleteAPIKey()
        hasQwenAPIKey = false
    }

    func useGrokSTTMode() {
        guard !isRunning, !isStarting else { return }
        selectedModel = .appleSpeechOnly
        if !isUsingGrokSTT {
            grokTranscriptionModel = .voiceTranscribe2
        }
        prepareTranscribeOnlyPresentation()
        clearTranscribeOnlyNotice(resetActivation: true)
    }

    func saveGrokAPIKey(_ key: String) throws {
        guard !isRunning, !isStarting else { return }
        try GrokAPIKeyStore.saveAPIKey(key)
        hasGrokAPIKey = true
    }

    func removeGrokAPIKey() throws {
        guard !isRunning, !isStarting else { return }
        try GrokAPIKeyStore.deleteAPIKey()
        hasGrokAPIKey = false
    }

    func saveAzureSpeechAPIKey(_ key: String) throws {
        try AzureSpeechAPIKeyStore.saveAPIKey(key)
        hasAzureSpeechAPIKey = true
    }

    func removeAzureSpeechAPIKey() throws {
        try AzureSpeechAPIKeyStore.deleteAPIKey()
        hasAzureSpeechAPIKey = false
    }

    func useMetaScribeMode() {
        guard !isRunning, !isStarting else { return }
        clearTranscribeOnlyNotice(resetActivation: true)
        selectedModel = .appleSystem
        openAITranscriptionModel = .off
        openAITranslationModel = .off
        geminiTranslationModel = .off
        if metaTranscriptionModel != .museVoiceTranscribe {
            metaTranscriptionModel = .museVoiceTranscribe
        }
        applyAppleVoiceOutputDefault()
        restoreFloatingCaptionDisplayModeAfterTranscribeOnly()
    }

    func useLiveOutputMode(_ mode: LiveOutputMode) {
        guard !isRunning, !isStarting else { return }
        if isUsingOpenAIRealtime {
            useOpenAIMode(mode)
            return
        }
        switch mode {
        case .translation:
            useTranslationMode()
        case .transcription:
            useTranscribeOnlyMode()
        }
    }

    func useTranslationMode() {
        clearTranscribeOnlyNotice(resetActivation: true)
        if isTranscribeOnlyMode {
            selectedModel = .appleSystem
        }
        if (isUsingNariSTT || isUsingGrokSTT), sourceLanguage == targetLanguage {
            updateLanguagePair(source: sourceLanguage, target: fallbackTargetLanguage(excluding: sourceLanguage, preferred: .korean))
        }
        if openAITranscriptionModel.isEnabled || openAITranslationModel.isEnabled {
            openAITranscriptionModel = .off
            if !openAITranslationModel.isEnabled {
                openAITranslationModel = .gptRealtimeTranslate
            }
            applyProviderVoiceOutputDefault()
        }
        restoreFloatingCaptionDisplayModeAfterTranscribeOnly()
    }

    func useTranscribeOnlyMode() {
        qwenTranslationModel = .off
        isUsingAzureMAI = false
        if floatingCaptionDisplayModeBeforeTranscribeOnly == nil {
            floatingCaptionDisplayModeBeforeTranscribeOnly = floatingCaptionDisplayMode
        }
        floatingCaptionDisplayMode = .original
        if openAITranslationModel.isEnabled {
            openAITranslationModel = .off
        }
        if openAITranscriptionModel.isEnabled {
            openAITranscriptionModel = .off
        }
        if geminiTranslationModel.isEnabled {
            geminiTranslationModel = .off
        }
        if metaTranscriptionModel.isEnabled {
            metaTranscriptionModel = .off
        }
        isDubbingEnabled = false
        selectedModel = .appleSpeechOnly
        clearTranscribeOnlyNotice(resetActivation: true)
    }

    private func syncLiveOutputModeWithLanguagePair() {
        guard !isRestoringSelectedSettings, !isUpdatingLanguagePair, !isRunning else { return }

        // OpenAI 전사는 번역 대상 언어를 숨길 뿐, 다음 번역에 쓸 선택을 지우지 않는다.
        guard !isUsingGPTTranscriptionMode else { return }

        if selectedModel == .appleSpeechOnly {
            if targetLanguage != sourceLanguage {
                targetLanguage = sourceLanguage
            }
            return
        }

        guard !isUsingProviderRealtimeTranslation else { return }

        if sourceLanguage == targetLanguage {
            useTranscribeOnlyMode()
            return
        }
    }

    private func updateLanguagePair(source: LanguageOption, target: LanguageOption) {
        isUpdatingLanguagePair = true
        sourceLanguage = source
        targetLanguage = target
        isUpdatingLanguagePair = false
        syncLiveOutputModeWithLanguagePair()
    }

    private func fallbackTargetLanguage(excluding excludedLanguage: LanguageOption, preferred: LanguageOption) -> LanguageOption {
        if preferred != excludedLanguage {
            return preferred
        }
        return LanguageOption.supported.first { $0 != excludedLanguage } ?? preferred
    }

    private func applyAppleVoiceOutputDefault() {
        appleVoiceOutputEnabled = false
        applyVoiceOutputDefault(false)
    }

    private func applyProviderVoiceOutputDefault() {
        providerVoiceOutputEnabled = true
        applyVoiceOutputDefault(true)
    }

    private func applyRestoredVoiceOutputPreference() {
        applyVoiceOutputDefault(isUsingQwenTranslation ? qwenVoiceOutputEnabled : (isUsingProviderRealtimeTranslation ? providerVoiceOutputEnabled : appleVoiceOutputEnabled))
    }

    private func applyVoiceOutputDefault(_ isEnabled: Bool) {
        isApplyingVoiceOutputDefault = true
        isDubbingEnabled = isEnabled
        isApplyingVoiceOutputDefault = false
    }

    private func rememberVoiceOutputPreference(_ isEnabled: Bool) {
        if isUsingQwenTranslation {
            qwenVoiceOutputEnabled = isEnabled
            return
        }
        if isUsingProviderRealtimeTranslation {
            providerVoiceOutputEnabled = isEnabled
        } else if !isTranscribeOnlyMode {
            appleVoiceOutputEnabled = isEnabled
        }
    }

    private func restoreFloatingCaptionDisplayModeAfterTranscribeOnly() {
        guard let previousMode = floatingCaptionDisplayModeBeforeTranscribeOnly else { return }

        floatingCaptionDisplayModeBeforeTranscribeOnly = nil
        floatingCaptionDisplayMode = previousMode
    }

    private func prepareTranscribeOnlyPresentation() {
        if floatingCaptionDisplayModeBeforeTranscribeOnly == nil {
            floatingCaptionDisplayModeBeforeTranscribeOnly = floatingCaptionDisplayMode
        }
        floatingCaptionDisplayMode = .original
        isDubbingEnabled = false
    }

    private func showTranscribeOnlyNoticeForCurrentActivation() {
        guard isTranscribeOnlyMode,
              !hasShownTranscribeOnlyNoticeForCurrentActivation
        else {
            return
        }

        hasShownTranscribeOnlyNoticeForCurrentActivation = true
        floatingNoticeText = AppText.translationDisabledForSpeechOnly
        statusMessage = AppText.translationDisabledForSpeechOnly
        transcribeOnlyNoticeDismissTask?.cancel()

        transcribeOnlyNoticeDismissTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(Int(Self.transcribeOnlyNoticeDisplayDuration * 1_000)))
            guard !Task.isCancelled else { return }

            if floatingNoticeText == AppText.translationDisabledForSpeechOnly {
                floatingNoticeText = nil
            }
            if statusMessage == AppText.translationDisabledForSpeechOnly {
                statusMessage = isRunning ? AppText.listeningForSpeech(from: audioInputSource) : AppText.ready
            }
            transcribeOnlyNoticeDismissTask = nil
        }
    }

    private func clearTranscribeOnlyNotice(resetActivation: Bool) {
        transcribeOnlyNoticeDismissTask?.cancel()
        transcribeOnlyNoticeDismissTask = nil
        if floatingNoticeText == AppText.translationDisabledForSpeechOnly {
            floatingNoticeText = nil
        }
        if resetActivation {
            hasShownTranscribeOnlyNoticeForCurrentActivation = false
        }
    }

    func modelAvailability(for model: IntelligenceModel) -> ModelAvailability {
        modelAvailabilityByModelID[model.id] ?? ModelAvailability.checking(for: model)
    }

    func downloadModelAssets(for model: IntelligenceModel) {
        beginModelAssetDownload(model, startsAfterDownload: false)
    }

    private func downloadRequiredModelAssetsThenStart(_ model: IntelligenceModel) {
        beginModelAssetDownload(model, startsAfterDownload: true)
    }

    private func beginModelAssetDownload(_ model: IntelligenceModel, startsAfterDownload: Bool) {
        guard modelAssetDownloadRequest == nil,
              modelAvailability(for: model).state.canDownload else { return }

        let request = ModelAssetDownloadRequest(
            model: model, configuration: currentStartConfiguration(), startsAfterDownload: startsAfterDownload
        )
        modelAvailabilityTask?.cancel()
        modelAssetDownloadRequest = request
        markModelAssetsDownloading(request)
        if startsAfterDownload {
            isPaused = false
            setCaptionersPaused(false)
            isStarting = true
            statusMessage = "\(AppText.modelStatusDownloading): \(model.title)"
        }

        modelAssetDownloadTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try Task.checkCancellation()
                let source = request.configuration.sourceLanguage
                let target = request.configuration.targetLanguage
                if let modelAssetDownloader {
                    try await modelAssetDownloader(model, source, target)
                } else {
                    try await ModelAvailabilityChecker.downloadAssets(
                        for: model, source: source, target: target,
                        translationDownloader: { [translationAssetDownloader] source, target in
                            try await translationAssetDownloader.download(source: source, target: target)
                        }
                    )
                }
                try Task.checkCancellation()
                let availability = await modelAvailabilityProvider(source, target)
                try Task.checkCancellation()
                guard isCurrentModelAssetDownload(request) else { return }
                modelAvailabilityTask?.cancel()
                modelAssetDownloadRequest = nil
                modelAssetDownloadTask = nil
                modelAvailabilityByModelID = availability
                guard startsAfterDownload else { return }
                isStarting = false
                let readiness = startReadinessAssessment()
                guard readiness.canStart else {
                    presentCaptureStartFailure(statusMessage(for: readiness), recoveryAction: recoveryAction(for: readiness))
                    return
                }
                start()
            } catch {
                guard isCurrentModelAssetDownload(request) else { return }
                if error is CancellationError || Task.isCancelled {
                    modelAssetDownloadRequest = nil
                    modelAssetDownloadTask = nil
                    if startsAfterDownload { isStarting = false }
                    if startsAfterDownload { statusMessage = AppText.ready }
                    refreshModelAvailability()
                } else {
                    // 다른 자산 행도 다운로드 중 표시에서 벗어나도록 현재 상태를 다시 읽는다.
                    let availability = await modelAvailabilityProvider(
                        request.configuration.sourceLanguage, request.configuration.targetLanguage
                    )
                    guard !Task.isCancelled, isCurrentModelAssetDownload(request) else { return }
                    modelAvailabilityTask?.cancel()
                    modelAssetDownloadRequest = nil
                    modelAssetDownloadTask = nil
                    if startsAfterDownload { isStarting = false }
                    modelAvailabilityByModelID = availability
                    modelAvailabilityByModelID[model.id] = ModelAvailability(
                        state: .failed, detail: error.localizedDescription
                    )
                    if startsAfterDownload {
                        presentCaptureStartFailure(AppText.startFailed(error.localizedDescription), recoveryAction: .retry)
                    }
                }
            }
        }
    }

    private func isCurrentModelAssetDownload(_ request: ModelAssetDownloadRequest) -> Bool {
        guard modelAssetDownloadRequest?.id == request.id else { return false }
        guard request.configuration == currentStartConfiguration() else {
            cancelModelAssetDownload()
            refreshModelAvailability()
            return false
        }
        return true
    }

    private func markModelAssetsDownloading(_ request: ModelAssetDownloadRequest) {
        for model in request.affectedModels {
            modelAvailabilityByModelID[model.id] = ModelAvailability(state: .downloading, detail: model.detail)
        }
    }

    @discardableResult
    private func cancelModelAssetDownload() -> Bool {
        guard let request = modelAssetDownloadRequest else { return false }
        modelAssetDownloadRequest = nil
        modelAssetDownloadTask?.cancel()
        modelAssetDownloadTask = nil
        translationAssetDownloader.cancel()
        if request.startsAfterDownload {
            isStarting = false
            statusMessage = AppText.ready
        }
        return true
    }

    var floatingSourceText: String {
        let displayText = floatingPresentedSourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !displayText.isEmpty {
            return floatingCaptionText(from: displayText, usesPrimaryFont: floatingSourceUsesPrimaryFont)
        }

        let liveDisplayText = floatingVisibleSourceTranscript()
        if !liveDisplayText.isEmpty {
            return floatingCaptionText(from: liveDisplayText, usesPrimaryFont: floatingSourceUsesPrimaryFont)
        }

        return floatingCaptionText(from: lines.last?.sourceText, usesPrimaryFont: floatingSourceUsesPrimaryFont)
    }

    var floatingTranslationText: String {
        let displaySourceText = floatingPresentedSourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !displaySourceText.isEmpty {
            let translatedText = floatingDisplayTranslationText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !translatedText.isEmpty, translatedText != AppText.translating else {
                return ""
            }

            // A translation whose source has already been replaced stays on
            // screen until its replacement arrives (or the hold times out) so the
            // translation line never blinks empty between sentences.
            return floatingCaptionText(from: translatedText)
        }

        guard let lineTranslatedText = lines.last?.translatedText.trimmingCharacters(in: .whitespacesAndNewlines),
              lineTranslatedText != AppText.translating
        else {
            return ""
        }

        return floatingCaptionText(from: lineTranslatedText)
    }

    var hasFloatingCaptionContent: Bool {
        !floatingSourceText.isEmpty || !floatingTranslationText.isEmpty
    }

    var hasTranscriptContent: Bool {
        !lines.isEmpty
    }

    var shouldShowTranscript: Bool {
        isRunning || !lines.isEmpty
    }

    var shouldShowTranslationPane: Bool {
        !isTranscribeOnlyMode
    }

    var availableFloatingCaptionDisplayModes: [FloatingCaptionDisplayMode] {
        isTranscribeOnlyMode ? [.original] : FloatingCaptionDisplayMode.allCases
    }

    var floatingCaptionPrimaryPointSize: CGFloat {
        floatingCaptionCustomPointSize > 0
            ? floatingCaptionCustomPointSize
            : floatingCaptionTextSize.primaryPointSize
    }

    var floatingCaptionSecondaryPointSize: CGFloat {
        floatingCaptionCustomPointSize > 0
            ? FloatingCaptionAppearance.secondaryPointSize(for: floatingCaptionCustomPointSize)
            : floatingCaptionTextSize.secondaryPointSize
    }

    var floatingCaptionPrimaryFont: Font {
        .system(size: floatingCaptionPrimaryPointSize, weight: floatingCaptionStyle.fontWeight.primary, design: floatingCaptionStyle.fontFamily.design)
    }

    var floatingCaptionSecondaryFont: Font {
        .system(size: floatingCaptionSecondaryPointSize, weight: floatingCaptionStyle.fontWeight.secondary, design: floatingCaptionStyle.fontFamily.design)
    }

    var floatingCaptionPrimaryLineHeight: CGFloat {
        floatingCaptionPrimaryPointSize * floatingCaptionStyle.fontFamily.lineHeightScale
    }

    var floatingCaptionSecondaryLineHeight: CGFloat {
        floatingCaptionSecondaryPointSize * max(1.28, floatingCaptionStyle.fontFamily.lineHeightScale)
    }

    var floatingCaptionEffectiveLineCount: Int {
        let configured = floatingCaptionLineCount.rawValue
        guard floatingCaptionMeasuredContentHeight.isFinite,
              floatingCaptionMeasuredContentHeight > 0
        else { return configured }

        let usesTwoBlocks = floatingCaptionDisplayMode == .originalAndTranslation
        if usesTwoBlocks {
            for candidate in stride(from: configured, through: 1, by: -1) {
                let height = FloatingCaptionAppearance.blockHeight(
                    lineHeight: floatingCaptionPrimaryLineHeight,
                    lineCount: candidate,
                    lineSpacing: floatingCaptionStyle.lineSpacing.points
                ) + FloatingCaptionAppearance.blockHeight(
                    lineHeight: floatingCaptionSecondaryLineHeight,
                    lineCount: candidate,
                    lineSpacing: floatingCaptionStyle.lineSpacing.points
                ) + FloatingCaptionAppearance.captionBlockSpacing
                if height <= floatingCaptionMeasuredContentHeight {
                    return candidate
                }
            }
            return 1
        }

        let lineHeight = floatingCaptionPrimaryLineHeight
        let spacing = floatingCaptionStyle.lineSpacing.points
        let possibleLines = Int(floor((floatingCaptionMeasuredContentHeight + spacing) / (lineHeight + spacing)))
        return min(configured, max(1, possibleLines))
    }

    var floatingCaptionMinimumWindowHeight: CGFloat {
        let usesTwoBlocks = floatingCaptionDisplayMode == .originalAndTranslation
        let textHeight = usesTwoBlocks
            ? FloatingCaptionAppearance.blockHeight(lineHeight: floatingCaptionPrimaryLineHeight, lineCount: 1)
                + FloatingCaptionAppearance.blockHeight(lineHeight: floatingCaptionSecondaryLineHeight, lineCount: 1)
                + FloatingCaptionAppearance.captionBlockSpacing
            : FloatingCaptionAppearance.blockHeight(lineHeight: floatingCaptionPrimaryLineHeight, lineCount: 1)
        return max(90, textHeight + FloatingCaptionAppearance.windowVerticalPadding)
    }

    var floatingCaptionMinimumWindowSize: NSSize {
        NSSize(width: 420, height: floatingCaptionMinimumWindowHeight)
    }

    var floatingCaptionTextColor: Color {
        FloatingCaptionAppearance.color(
            hex: floatingCaptionTextColorHex,
            fallback: FloatingCaptionAppearance.defaultTextColorHex
        )
    }

    var floatingCaptionBackgroundColor: Color {
        FloatingCaptionAppearance.color(
            hex: floatingCaptionBackgroundColorHex,
            fallback: FloatingCaptionAppearance.defaultBackgroundColorHex
        )
    }

    func resetFloatingCaptionAppearance() {
        floatingCaptionStyle = .standard
        floatingCaptionTextSize = .medium
        floatingCaptionLineCount = .three
        floatingCaptionStability = .balanced
        floatingCaptionTextAlignment = .center
        floatingCaptionCustomPointSize = FloatingCaptionAppearance.defaultCustomPointSize
        floatingCaptionTextColorHex = FloatingCaptionAppearance.defaultTextColorHex
        floatingCaptionBackgroundColorHex = FloatingCaptionAppearance.defaultBackgroundColorHex
        floatingCaptionBackgroundOpacity = FloatingCaptionAppearance.defaultBackgroundOpacity
    }

    func selectFloatingCaptionTextSizePreset(_ size: FloatingCaptionTextSize) {
        floatingCaptionTextSize = size
        floatingCaptionCustomPointSize = FloatingCaptionAppearance.defaultCustomPointSize
    }

    var selectedFloatingCaptionPreset: FloatingCaptionPreset? {
        FloatingCaptionPreset.allCases.first {
            floatingCaptionStyle.captionTextMatches($0.style) && floatingCaptionTextSize == $0.textSize
                && floatingCaptionCustomPointSize == 0 && floatingCaptionLineCount == $0.lineCount
                && floatingCaptionTextAlignment == $0.alignment
                && floatingCaptionTextColorHex.uppercased() == $0.textColorHex
        }
    }

    func applyFloatingCaptionPreset(_ preset: FloatingCaptionPreset) {
        let wasRestoring = isRestoringSelectedSettings
        isRestoringSelectedSettings = true
        defer {
            isRestoringSelectedSettings = wasRestoring
            persistSelectedSettings()
        }
        let retainedBackgroundShape = floatingCaptionStyle.backgroundShape
        floatingCaptionStyle = preset.style
        floatingCaptionStyle.backgroundShape = retainedBackgroundShape
        selectFloatingCaptionTextSizePreset(preset.textSize)
        floatingCaptionLineCount = preset.lineCount
        floatingCaptionTextAlignment = preset.alignment
        floatingCaptionTextColorHex = preset.textColorHex
    }

    func requestFloatingCaptionSettings() {
        requestedSettingsCategoryID = "floatingCaptions"
    }

    var effectiveSavedTranscriptContentMode: SavedTranscriptContentMode {
        isTranscribeOnlyMode ? .original : savedTranscriptContentMode
    }

    var availableSavedTranscriptContentModes: [SavedTranscriptContentMode] {
        isTranscribeOnlyMode ? [.original] : SavedTranscriptContentMode.allCases
    }

    var selectedSavedTranscript: SavedTranscript? {
        guard let selectedSavedTranscriptID else { return nil }
        return savedTranscripts.first { $0.id == selectedSavedTranscriptID }
    }

    func selectSavedTranscript(_ id: String) {
        guard let transcript = savedTranscripts.first(where: { $0.id == id }) else { return }

        selectedSavedTranscriptID = id
        savedDraftSourceText = loadTranscriptText(fileName: transcript.sourceFileName) ?? transcript.sourceText
        if let translationFileName = transcript.translationFileName,
           let translatedText = loadTranscriptText(fileName: translationFileName) {
            savedDraftTranslationText = translatedText
        } else {
            savedDraftTranslationText = transcript.translatedText ?? ""
        }
    }

    func saveSelectedTranscriptEdits() {
        guard let selectedTranscript = selectedSavedTranscript else { return }

        let sourceText = savedDraftSourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sourceText.isEmpty else { return }

        if selectedTranscript.isOriginalAndTranslation,
           let translationFileName = selectedTranscript.translationFileName {
            let translatedText = savedDraftTranslationText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard writeTranscriptText(sourceText, fileName: selectedTranscript.sourceFileName),
                  writeTranscriptText(translatedText, fileName: translationFileName)
            else {
                return
            }
        } else {
            guard writeTranscriptText(sourceText, fileName: selectedTranscript.sourceFileName) else { return }
        }

        let selectedID = selectedTranscript.id
        loadSavedTranscripts()
        selectSavedTranscript(selectedID)
    }

    func polishSelectedTranscriptDraftWithFoundationModel() {
        guard !isFoundationTranscriptCleanupRunning,
              let selectedTranscript = selectedSavedTranscript
        else {
            return
        }

        let selectedID = selectedTranscript.id
        let sourceText = savedDraftSourceText
        let translationText = savedDraftTranslationText
        let shouldPolishTranslation = selectedTranscript.isOriginalAndTranslation
            && translationText.rangeOfCharacter(from: .whitespacesAndNewlines.inverted) != nil
        guard sourceText.rangeOfCharacter(from: .whitespacesAndNewlines.inverted) != nil
            || shouldPolishTranslation
        else {
            return
        }

        isFoundationTranscriptCleanupRunning = true
        statusMessage = AppText.foundationModelCleanupRunning

        Task { @MainActor in
            do {
                let cleanedSource = try await foundationTranscriptPolisher.polishTranscript(sourceText)
                let cleanedTranslation = shouldPolishTranslation
                    ? try await foundationTranscriptPolisher.polishTranscript(translationText)
                    : ""

                if selectedSavedTranscriptID == selectedID {
                    if !cleanedSource.isEmpty {
                        savedDraftSourceText = cleanedSource
                    }
                    if shouldPolishTranslation {
                        savedDraftTranslationText = cleanedTranslation
                    }
                    statusMessage = AppText.foundationModelCleanupComplete
                }
            } catch {
                statusMessage = AppText.foundationModelCleanupFailed(error.localizedDescription)
            }

            isFoundationTranscriptCleanupRunning = false
        }
    }

    func deleteSelectedTranscript() {
        guard let selectedTranscript = selectedSavedTranscript else { return }

        savedTranscripts.removeAll { $0.id == selectedTranscript.id }
        try? FileManager.default.removeItem(at: transcriptURL(fileName: selectedTranscript.sourceFileName))
        if let translationFileName = selectedTranscript.translationFileName {
            try? FileManager.default.removeItem(at: transcriptURL(fileName: translationFileName))
        }
        self.selectedSavedTranscriptID = nil
        savedDraftSourceText = ""
        savedDraftTranslationText = ""
    }

    func deleteAllSavedTranscripts() {
        do {
            try FileManager.default.createDirectory(
                at: transcriptsDirectoryURL,
                withIntermediateDirectories: true
            )
            let fileURLs = try FileManager.default.contentsOfDirectory(
                at: transcriptsDirectoryURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
            for fileURL in fileURLs where fileURL.pathExtension == "txt" {
                try FileManager.default.removeItem(at: fileURL)
            }
            savedTranscripts.removeAll()
            selectedSavedTranscriptID = nil
            savedDraftSourceText = ""
            savedDraftTranslationText = ""
            activeAutosaveSourceText = ""
            activeAutosaveTranslatedText = ""
            activeAutosaveBaseFileName = nil
        } catch {
            statusMessage = AppText.saveLibraryFailed(error.localizedDescription)
        }
    }

    private func startCaptioners(
        configuration: StartConfiguration,
        generation: UInt64
    ) async throws {
        if usesAppleSpeechTranscriber(for: configuration) {
            try await startAppleSpeechTranscriber(
                configuration: configuration,
                generation: generation
            )
            return
        }

        stopCaptioners()
        transcriber = LiveSpeechTranscriber()
        transcriber.delegate = self
        openAITranscriber = OpenAIRealtimeTranscriber()
        openAITranscriber.delegate = self
        configureOpenAITerminalTranscriptDelivery(for: openAITranscriber)
        openAITranscriber.onAudioTransportDegraded = { [weak self, weak openAITranscriber] degradation in
            Task { @MainActor in
                guard let self,
                      let openAITranscriber,
                      openAITranscriber === self.openAITranscriber
                else {
                    return
                }
                self.handleFatalPipelineError(
                    RealtimeAudioTransportError(degradation: degradation),
                    generation: generation
                )
            }
        }
        geminiLiveTranslator = GeminiLiveTranslationService()
        geminiLiveTranslator.delegate = self
        geminiLiveTranslator.onAudioTransportDegraded = { [weak self, weak geminiLiveTranslator] degradation in
            Task { @MainActor in
                guard let self,
                      let geminiLiveTranslator,
                      geminiLiveTranslator === self.geminiLiveTranslator
                else {
                    return
                }
                self.handleFatalPipelineError(
                    RealtimeAudioTransportError(degradation: degradation),
                    generation: generation
                )
            }
        }
        geminiLiveTranslator.onSessionReconnectRecommended = {
            [weak self, weak geminiLiveTranslator] resumptionHandle in
            Task { @MainActor in
                guard let self,
                      let geminiLiveTranslator,
                      geminiLiveTranslator === self.geminiLiveTranslator,
                      self.pipelineLifecycle.acceptsSample(generation: generation),
                      self.currentStartConfiguration() == configuration
                else {
                    return
                }
                self.scheduleGeminiSessionReconnect(
                    service: geminiLiveTranslator,
                    configuration: configuration,
                    generation: generation,
                    resumptionHandle: resumptionHandle
                )
            }
        }
        metaVoiceTranscriber = MetaVoiceTranscribeService()
        metaVoiceTranscriber.delegate = self
        metaVoiceTranscriber.onAudioTransportDegraded = { [weak self, weak metaVoiceTranscriber] degradation in
            Task { @MainActor in
                guard let self,
                      let metaVoiceTranscriber,
                      metaVoiceTranscriber === self.metaVoiceTranscriber
                else {
                    return
                }
                self.handleFatalPipelineError(
                    RealtimeAudioTransportError(degradation: degradation),
                    generation: generation
                )
            }
        }
        metaVoiceTranscriber.onSessionClosed = { [weak self, weak metaVoiceTranscriber] code, reason in
            Task { @MainActor in
                guard let self,
                      let metaVoiceTranscriber,
                      metaVoiceTranscriber === self.metaVoiceTranscriber,
                      self.pipelineLifecycle.acceptsSample(generation: generation),
                      self.currentStartConfiguration() == configuration
                else {
                    return
                }
                if code == 1011 || code == 1013 {
                    self.scheduleMetaSessionReconnect(
                        service: metaVoiceTranscriber,
                        configuration: configuration,
                        generation: generation,
                        delay: code == 1013 ? 5 : 2
                    )
                } else if code == 1008 {
                    self.handleFatalPipelineError(
                        MetaVoiceTranscribeError.invalidRequest,
                        generation: generation
                    )
                } else if code != 1000 {
                    self.handleFatalPipelineError(
                        MetaVoiceTranscribeError.connectionFailed,
                        generation: generation
                    )
                }
                _ = reason
            }
        }
        activeCaptionerGeneration = generation

        if configuration.isTranscribeOnlyMode, configuration.openAITranscriptionModel.isEnabled {
            try await openAITranscriber.start(
                language: configuration.sourceLanguage,
                model: configuration.openAITranscriptionModel
            )
        } else if configuration.geminiTranslationModel.isEnabled {
            try await geminiLiveTranslator.start(
                targetLanguage: configuration.targetLanguage,
                model: configuration.geminiTranslationModel
            )
            scheduleGeminiSessionRefresh(
                service: geminiLiveTranslator,
                configuration: configuration,
                generation: generation
            )
        } else if configuration.qwenTranslationModel.isEnabled {
            qwenTranslator = QwenRealtimeTranslationService()
            configureQwenCallbacks(service: qwenTranslator, generation: generation)
            try await qwenTranslator.start(workspaceID: configuration.qwenWorkspaceID,
                targetLanguage: configuration.targetLanguage, audioOutputEnabled: configuration.qwenAudioOutputEnabled,
                model: configuration.qwenTranslationModel)
        } else if configuration.nariTranscriptionModel.isEnabled {
            nariTranscriber = NariRealtimeTranscriber()
            configureNariCallbacks(service: nariTranscriber, generation: generation)
            try await nariTranscriber.start(
                model: configuration.nariTranscriptionModel,
                sourceLanguage: configuration.sourceLanguage,
                autoDetectLanguage: configuration.usesNariSourceAutoDetection
            )
        } else if configuration.grokTranscriptionModel.isEnabled {
            grokTranscriber = GrokRealtimeTranscriber()
            configureGrokCallbacks(service: grokTranscriber, generation: generation)
            try await grokTranscriber.start(
                model: configuration.grokTranscriptionModel,
                sourceLanguage: configuration.sourceLanguage,
                autoDetectLanguage: configuration.usesGrokSourceAutoDetection
            )
        } else if configuration.azureMAIEnabled {
            azureMAITranscriber = AzureMAITranscriber()
            let service = azureMAITranscriber
            try service.start(
                endpoint: configuration.azureSpeechEndpoint,
                key: try AzureSpeechAPIKeyStore.readAPIKey() ?? "",
                language: configuration.sourceLanguage.id.split(separator: "-").first.map(String.init)
            ) { [weak self, weak service] result in
                await self?.receiveAzureMAI(result, service: service, generation: generation)
            }
        } else if configuration.metaTranscriptionModel.isEnabled {
            try await metaVoiceTranscriber.start(
                model: configuration.metaTranscriptionModel,
                sourceLanguage: configuration.sourceLanguage,
                usesSpeakerLabels: configuration.usesMetaSpeakerLabels,
                languageBias: configuration.usesAppleSourceAutoDetection
                    ? nil
                    : configuration.sourceLanguage.metaLanguageBiasName.map { [$0] },
                keywords: []
            )
            scheduleMetaSessionRefresh(
                service: metaVoiceTranscriber,
                configuration: configuration,
                generation: generation
            )
        } else if configuration.openAITranslationModel.usesRealtimeAudioTranslation {
            try await openAITranscriber.startRealtimeTranslationOnly(
                language: configuration.targetLanguage,
                model: configuration.openAITranslationModel
            )
        } else if configuration.openAITranscriptionModel.isEnabled {
            try await openAITranscriber.start(
                language: configuration.sourceLanguage,
                model: configuration.openAITranscriptionModel
            )
        }
    }

    private func usesAppleSpeechTranscriber(for configuration: StartConfiguration) -> Bool {
        !configuration.openAITranscriptionModel.isEnabled
            && !configuration.geminiTranslationModel.isEnabled
            && !configuration.metaTranscriptionModel.isEnabled
            && !configuration.nariTranscriptionModel.isEnabled
            && !configuration.qwenTranslationModel.isEnabled
            && !configuration.grokTranscriptionModel.isEnabled
            && !configuration.azureMAIEnabled
            && !configuration.openAITranslationModel.usesRealtimeAudioTranslation
    }

    private func startAppleSpeechTranscriber(
        configuration: StartConfiguration,
        generation: UInt64
    ) async throws {
        // Keep this candidate entirely local until all cancellation and
        // generation checks pass. A non-cooperative speech-permission callback
        // from an older start must never replace or stop a newer pipeline.
        let candidate = LiveSpeechTranscriber()
        candidate.delegate = self
        do {
            // stopCaptioners() intentionally returns synchronously so Stop
            // never blocks MainActor. Before a replacement can reserve Speech
            // assets, suspend until the old analyzer has cancelled and all of
            // its locales have been released.
            await transcriber.stopAndWaitForCleanup()
            try Task.checkCancellation()
            try validatePipelineStart(generation: generation, configuration: configuration)

            let languages = await appleSpeechLanguages(for: configuration)
            try Task.checkCancellation()
            try await candidate.start(languages: languages)
            try validatePipelineStart(generation: generation, configuration: configuration)

            stopCaptioners()
            transcriber = candidate
            transcriber.delegate = self
            activeCaptionerGeneration = generation
        } catch {
            candidate.delegate = nil
            candidate.stop()
            throw error
        }
    }

    private func appleSpeechLanguages(for configuration: StartConfiguration) async -> [LanguageOption] {
        guard configuration.usesAppleSourceAutoDetection else {
            return [configuration.sourceLanguage]
        }

        let candidates = LanguageOption.prioritizedAutoDetectionCandidates(
            sourceLanguage: configuration.sourceLanguage,
            targetLanguage: configuration.targetLanguage
        )
        let installedCandidates = await LiveSpeechTranscriber.installedSupportedLanguages(from: candidates)
        let selectedCandidates = installedCandidates.isEmpty
            ? [candidates.first ?? configuration.sourceLanguage]
            : installedCandidates
        appleAutoDetectionPreferredLanguage = selectedCandidates.first
        return selectedCandidates
    }

    func prioritizedAutoDetectionLanguages() -> [LanguageOption] {
        LanguageOption.prioritizedAutoDetectionCandidates(
            sourceLanguage: sourceLanguage,
            targetLanguage: targetLanguage
        )
    }

    private func stopCaptioners(openAITranscriberAlreadyStopped: Bool = false) {
        qwenTransitionTask?.cancel()
        qwenTransitionTask = nil
        qwenTranslator.onSourceTranscript = nil
        qwenTranslator.onTranslation = nil
        qwenTranslator.onAudio = nil
        qwenTranslator.onError = nil
        qwenTranslator.stop()
        grokTransitionTask?.cancel()
        grokTransitionTask = nil
        nariTransitionTask?.cancel()
        nariTransitionTask = nil
        geminiSessionRefreshTask?.cancel()
        geminiSessionRefreshTask = nil
        metaSessionRefreshTask?.cancel()
        metaSessionRefreshTask = nil
        audioSamplePipelineRegistry.clear()
        activeCaptionerGeneration = nil
        openAITranscriber.onAudioTransportDegraded = nil
        geminiLiveTranslator.onAudioTransportDegraded = nil
        geminiLiveTranslator.onSessionReconnectRecommended = nil
        metaVoiceTranscriber.onAudioTransportDegraded = nil
        metaVoiceTranscriber.onSessionClosed = nil
        transcriber.delegate = nil
        openAITranscriber.delegate = nil
        geminiLiveTranslator.delegate = nil
        metaVoiceTranscriber.delegate = nil
        transcriber.stop()
        if !openAITranscriberAlreadyStopped {
            openAITranscriber.stop()
        }
        geminiLiveTranslator.stop()
        metaVoiceTranscriber.stop()
        azureMAITranscriber.stop()
        grokTranscriber.onTranscript = nil
        grokTranscriber.onError = nil
        grokTranscriber.stop()
        nariTranscriber.onTranscript = nil
        nariTranscriber.onError = nil
        nariTranscriber.stop()
    }

    private func scheduleGeminiSessionRefresh(
        service: GeminiLiveTranslationService,
        configuration: StartConfiguration,
        generation: UInt64
    ) {
        geminiSessionRefreshTask?.cancel()
        geminiSessionRefreshTask = Task { @MainActor [weak self, weak service] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Self.geminiSessionRefreshInterval))
                guard !Task.isCancelled,
                      let self,
                      let service,
                      service === self.geminiLiveTranslator,
                      self.pipelineLifecycle.acceptsSample(generation: generation),
                      self.currentStartConfiguration() == configuration
                else {
                    return
                }

                do {
                    let resumptionHandle = service.latestSessionResumptionHandle
                    try await service.start(
                        targetLanguage: configuration.targetLanguage,
                        model: configuration.geminiTranslationModel,
                        resumptionHandle: resumptionHandle
                    )
                    service.setPaused(self.isPaused)
                } catch is CancellationError {
                    return
                } catch {
                    self.handleFatalPipelineError(error, generation: generation)
                    return
                }
            }
        }
    }

    private func scheduleGeminiSessionReconnect(
        service: GeminiLiveTranslationService,
        configuration: StartConfiguration,
        generation: UInt64,
        resumptionHandle: String?
    ) {
        geminiSessionRefreshTask?.cancel()
        geminiSessionRefreshTask = Task { @MainActor [weak self, weak service] in
            guard !Task.isCancelled,
                  let self,
                  let service,
                  service === self.geminiLiveTranslator,
                  self.pipelineLifecycle.acceptsSample(generation: generation),
                  self.currentStartConfiguration() == configuration
            else {
                return
            }

            do {
                try await service.start(
                    targetLanguage: configuration.targetLanguage,
                    model: configuration.geminiTranslationModel,
                    resumptionHandle: resumptionHandle
                )
                service.setPaused(self.isPaused)
                self.scheduleGeminiSessionRefresh(
                    service: service,
                    configuration: configuration,
                    generation: generation
                )
            } catch is CancellationError {
                return
            } catch {
                self.handleFatalPipelineError(error, generation: generation)
            }
        }
    }

    private func scheduleMetaSessionRefresh(
        service: MetaVoiceTranscribeService,
        configuration: StartConfiguration,
        generation: UInt64
    ) {
        metaSessionRefreshTask?.cancel()
        metaSessionRefreshTask = Task { @MainActor [weak self, weak service] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Self.metaSessionRefreshInterval))
                guard !Task.isCancelled,
                      let self,
                      let service,
                      service === self.metaVoiceTranscriber,
                      self.pipelineLifecycle.acceptsSample(generation: generation),
                      self.currentStartConfiguration() == configuration
                else {
                    return
                }
                do {
                    try await self.restartMetaSession(
                        service,
                        configuration: configuration
                    )
                    service.setPaused(self.isPaused)
                } catch is CancellationError {
                    return
                } catch {
                    self.handleFatalPipelineError(error, generation: generation)
                    return
                }
            }
        }
    }

    private func scheduleMetaSessionReconnect(
        service: MetaVoiceTranscribeService,
        configuration: StartConfiguration,
        generation: UInt64,
        delay: TimeInterval
    ) {
        metaSessionRefreshTask?.cancel()
        metaSessionRefreshTask = Task { @MainActor [weak self, weak service] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled,
                  let self,
                  let service,
                  service === self.metaVoiceTranscriber,
                  self.pipelineLifecycle.acceptsSample(generation: generation),
                  self.currentStartConfiguration() == configuration
            else {
                return
            }
            do {
                try await self.restartMetaSession(service, configuration: configuration)
                service.setPaused(self.isPaused)
                self.scheduleMetaSessionRefresh(
                    service: service,
                    configuration: configuration,
                    generation: generation
                )
            } catch is CancellationError {
                return
            } catch {
                self.handleFatalPipelineError(error, generation: generation)
            }
        }
    }

    private func restartMetaSession(
        _ service: MetaVoiceTranscribeService,
        configuration: StartConfiguration
    ) async throws {
        try await service.start(
            model: configuration.metaTranscriptionModel,
            sourceLanguage: configuration.sourceLanguage,
            usesSpeakerLabels: configuration.usesMetaSpeakerLabels,
            languageBias: configuration.usesAppleSourceAutoDetection
                ? nil
                : configuration.sourceLanguage.metaLanguageBiasName.map { [$0] },
            keywords: []
        )
    }

    private func flushOpenAITerminalTranscriptMailbox() {
        openAITerminalTranscriptMailbox.drain().forEach { transcript in
            guard transcript.transcriber === openAITranscriber,
                  isRunning || isStarting
            else {
                return
            }
            enqueueRecognizedCaption(
                sourceText: transcript.text,
                recognizedLanguage: transcript.language,
                confidence: transcript.confidence
            )
        }
    }

    private func configureOpenAITerminalTranscriptDelivery(
        for transcriber: OpenAIRealtimeTranscriber
    ) {
        let terminalTranscriptMailbox = openAITerminalTranscriptMailbox
        transcriber.onTerminalTranscriptReady = { [weak self, weak transcriber] text, language, confidence in
            guard let transcriber else { return }
            terminalTranscriptMailbox.append(
                OpenAITerminalTranscript(
                    text: text,
                    language: language,
                    confidence: confidence,
                    transcriber: transcriber
                )
            )
            Task { @MainActor [weak self] in
                self?.flushOpenAITerminalTranscriptMailbox()
            }
        }
    }

    private func setCaptionersPaused(_ isPaused: Bool) {
        transcriber.setPaused(isPaused)
        openAITranscriber.setPaused(isPaused)
        geminiLiveTranslator.setPaused(isPaused)
        metaVoiceTranscriber.setPaused(isPaused)
        azureMAITranscriber.setPaused(isPaused)
        grokTranscriber.setPaused(isPaused)
        nariTranscriber.setPaused(isPaused)
        qwenTranslator.setPaused(isPaused)
    }

    private func configureNariCallbacks(service: NariRealtimeTranscriber, generation: UInt64) {
        service.onTranscript = { [weak self, weak service] update in
            await self?.receiveNariTranscript(update, service: service, generation: generation)
        }
        service.onError = { [weak self, weak service] error in
            await self?.receiveNariError(error, service: service, generation: generation)
        }
    }

    private func receiveNariError(_ error: Error, service: NariRealtimeTranscriber?, generation: UInt64) {
        guard let service, service === nariTranscriber else { return }
        // 시작 오류는 start()의 throw 경로가 복구 버튼과 함께 표시한다.
        guard !isStarting else { return }
        handleFatalPipelineError(error, generation: generation)
    }

    private func pauseNariCapture() {
        audioSamplePipelineRegistry.clear()
        nariTranscriber.setPaused(true)
        isPaused = true
        stopSpeaking()
        statusMessage = AppText.paused
        let service = nariTranscriber
        let generation = pipelineLifecycle.generation
        nariTransitionTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await service.finish()
                guard !Task.isCancelled, service === nariTranscriber,
                      pipelineLifecycle.acceptsSample(generation: generation) else { return }
                _ = checkpointPendingTranscriptSave()
            } catch is CancellationError {
            } catch {
                receiveNariError(error, service: service, generation: generation)
            }
        }
    }

    private func resumeNariCapture() {
        isReconnectingNariSTT = true
        statusMessage = NariCopy.reconnecting
        let previousTransition = nariTransitionTask
        let service = nariTranscriber
        let configuration = currentStartConfiguration()
        let generation = pipelineLifecycle.generation
        nariTransitionTask = Task { @MainActor [weak self] in
            guard let self else { return }
            if let previousTransition { await previousTransition.value }
            guard !Task.isCancelled, service === nariTranscriber, isPaused,
                  pipelineLifecycle.acceptsSample(generation: generation),
                  configuration == currentStartConfiguration() else { return }
            do {
                try await service.start(
                    model: configuration.nariTranscriptionModel,
                    sourceLanguage: configuration.sourceLanguage,
                    autoDetectLanguage: configuration.usesNariSourceAutoDetection
                )
                guard !Task.isCancelled, service === nariTranscriber,
                      pipelineLifecycle.acceptsSample(generation: generation),
                      configuration == currentStartConfiguration() else { return }
                audioSamplePipelineRegistry.publish(
                    generation: generation, transcriber: transcriber,
                    openAITranscriber: openAITranscriber, geminiLiveTranslator: geminiLiveTranslator,
                    metaVoiceTranscriber: metaVoiceTranscriber, azureMAITranscriber: azureMAITranscriber,
                    grokTranscriber: grokTranscriber,
                    nariTranscriber: service,
                    qwenTranslator: qwenTranslator
                )
                isReconnectingNariSTT = false
                isPaused = false
                statusMessage = AppText.listeningForSpeech(from: audioInputSource)
            } catch is CancellationError {
            } catch {
                receiveNariError(error, service: service, generation: generation)
            }
        }
    }

    private func finishNariCapture() {
        guard !isFinishingNariSTT else { return }
        if isReconnectingNariSTT {
            nariTransitionTask?.cancel()
            pipelineLifecycle.stop()
            finishPipeline(statusOverride: nil)
            return
        }
        isFinishingNariSTT = true
        statusMessage = NariCopy.finishing
        audioSamplePipelineRegistry.clear()
        nariTranscriber.setPaused(true)
        let previousTransition = nariTransitionTask
        let service = nariTranscriber
        let generation = pipelineLifecycle.generation
        nariTransitionTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await stopCapture()
            if let previousTransition { await previousTransition.value }
            guard !Task.isCancelled, service === nariTranscriber,
                  pipelineLifecycle.acceptsSample(generation: generation) else { return }
            do {
                try await service.finish()
                try await drainNariTranslations()
                guard !Task.isCancelled, service === nariTranscriber,
                      pipelineLifecycle.acceptsSample(generation: generation) else { return }
                pipelineLifecycle.stop()
                finishPipeline(statusOverride: nil)
            } catch is CancellationError {
            } catch {
                receiveNariError(error, service: service, generation: generation)
            }
        }
    }

    private func drainNariTranslations() async throws {
        guard !isTranscribeOnlyMode else { return }
        let deadline = ContinuousClock.now.advanced(by: .seconds(15))
        while translationTask != nil, ContinuousClock.now < deadline {
            try Task.checkCancellation()
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    private func configureGrokCallbacks(service: GrokRealtimeTranscriber, generation: UInt64) {
        service.onTranscript = { [weak self, weak service] update in
            await self?.receiveGrokTranscript(update, service: service, generation: generation)
        }
        service.onError = { [weak self, weak service] error in
            await self?.receiveGrokError(error, service: service, generation: generation)
        }
    }

    private func configureQwenCallbacks(service: QwenRealtimeTranslationService, generation: UInt64) {
        service.onSourceTranscript = { [weak self, weak service] text, isFinal in
            await self?.receiveQwenText(text, isFinal: isFinal, isTranslation: false, service: service, generation: generation)
        }
        service.onTranslation = { [weak self, weak service] text, isFinal in
            await self?.receiveQwenText(text, isFinal: isFinal, isTranslation: true, service: service, generation: generation)
        }
        service.onAudio = { [weak self, weak service] audio in
            await self?.receiveQwenAudio(audio, service: service, generation: generation)
        }
        service.onError = { [weak self, weak service] error in
            await self?.receiveQwenError(error, service: service, generation: generation)
        }
    }

    private func receiveQwenText(_ text: String, isFinal: Bool, isTranslation: Bool,
                                 service: QwenRealtimeTranslationService?, generation: UInt64) {
        guard let service, service === qwenTranslator, isUsingQwenTranslation, isRunning,
              pipelineLifecycle.acceptsSample(generation: generation) else { return }
        // pause/stop 직전에 보낸 오디오의 마지막 응답도 보존한다.
        if isTranslation { qwenTranslationTranscript.receive(text, isFinal: isFinal) }
        else { qwenSourceTranscript.receive(text, isFinal: isFinal) }
        refreshQwenCaptionLine()
    }

    private func receiveQwenAudio(_ audio: Data, service: QwenRealtimeTranslationService?, generation: UInt64) {
        guard let service, service === qwenTranslator, isUsingQwenTranslation,
              pipelineLifecycle.acceptsSample(generation: generation), isRunning, !isPaused, isDubbingEnabled else { return }
        openAIRealtimeAudioOutput.playPCM16Base64(audio.base64EncodedString(), sampleRate: 24_000)
    }

    private func refreshQwenCaptionLine() {
        let source = qwenSourceTranscript.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let translated = qwenTranslationTranscript.text.trimmingCharacters(in: .whitespacesAndNewlines)
        // 빈 final이 이전 부분 결과를 철회하면 화면과 저장 대기도 갱신한다.
        if source.isEmpty {
            floatingPresentedSourceText = ""
            floatingQueuedSourceText = ""
        } else { presentFloatingSourceText(source) }
        if translated.isEmpty || source.isEmpty {
            setFloatingDisplayTranslation("", sourceText: "", resetsDwell: true)
        } else { updateFloatingTranslationPresentation(translated, sourceText: source) }
        // 임시 인식은 철회될 수 있으므로 기록 파일에는 확정 결과만 반영한다.
        if isTranscriptPersistenceEnabled {
            activeAutosaveSourceText = qwenSourceTranscript.completed
            activeAutosaveTranslatedText = qwenTranslationTranscript.completed
            scheduleTranscriptCheckpointIfNeeded()
        }
        if source.isEmpty && translated.isEmpty {
            if let currentLineID { lines.removeAll { $0.id == currentLineID } }
            currentLineID = nil
            return
        }
        lastRecognizedText = source.isEmpty ? translated : source
        lastRecognitionAt = Date()
        transcriptCleanupTask?.cancel()
        let final = qwenSourceTranscript.isFinal && qwenTranslationTranscript.isFinal
        if let currentLineID, let index = lines.firstIndex(where: { $0.id == currentLineID }) {
            let line = lines[index]
            lines[index] = CaptionLine(id: line.id, sourceText: source, translatedText: translated,
                translatedSourceText: source, createdAt: line.createdAt, isFinal: final,
                revision: line.revision + 1, usesLongSessionDisplay: usesLongSessionMode)
        } else {
            let line = CaptionLine(sourceText: source, translatedText: translated,
                translatedSourceText: source, createdAt: Date(), isFinal: final, revision: 1,
                usesLongSessionDisplay: usesLongSessionMode)
            currentLineID = line.id
            lines.append(line)
        }
    }

    private func receiveQwenError(_ error: Error, service: QwenRealtimeTranslationService?, generation: UInt64) {
        guard let service, service === qwenTranslator else { return }
        // 시작 오류는 start()의 throw 경로가 복구 버튼과 함께 표시한다.
        guard !isStarting else { return }
        handleFatalPipelineError(error, generation: generation)
    }

    private func pauseQwenCapture() {
        audioSamplePipelineRegistry.clear()
        qwenTranslator.setPaused(true)
        isPaused = true
        stopSpeaking()
        statusMessage = AppText.paused
        let service = qwenTranslator
        let generation = pipelineLifecycle.generation
        qwenTransitionTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await service.finish()
                guard !Task.isCancelled, service === qwenTranslator,
                      pipelineLifecycle.acceptsSample(generation: generation) else { return }
                _ = checkpointPendingTranscriptSave()
            } catch is CancellationError {
            } catch {
                receiveQwenError(error, service: service, generation: generation)
            }
        }
    }

    private func resumeQwenCapture() {
        isReconnectingQwenTranslation = true
        statusMessage = QwenCopy.reconnecting
        let previousTransition = qwenTransitionTask
        let service = qwenTranslator
        let configuration = currentStartConfiguration()
        let generation = pipelineLifecycle.generation
        qwenTransitionTask = Task { @MainActor [weak self] in
            guard let self else { return }
            if let previousTransition { await previousTransition.value }
            guard !Task.isCancelled, service === qwenTranslator, isPaused,
                  pipelineLifecycle.acceptsSample(generation: generation),
                  configuration == currentStartConfiguration() else { return }
            do {
                try await service.start(
                    workspaceID: configuration.qwenWorkspaceID,
                    targetLanguage: configuration.targetLanguage,
                    audioOutputEnabled: configuration.qwenAudioOutputEnabled,
                    model: configuration.qwenTranslationModel
                )
                guard !Task.isCancelled, service === qwenTranslator,
                      pipelineLifecycle.acceptsSample(generation: generation),
                      configuration == currentStartConfiguration() else { return }
                audioSamplePipelineRegistry.publish(
                    generation: generation, transcriber: transcriber,
                    openAITranscriber: openAITranscriber, geminiLiveTranslator: geminiLiveTranslator,
                    metaVoiceTranscriber: metaVoiceTranscriber, azureMAITranscriber: azureMAITranscriber,
                    grokTranscriber: grokTranscriber,
                    nariTranscriber: nariTranscriber,
                    qwenTranslator: service
                )
                isReconnectingQwenTranslation = false
                isPaused = false
                statusMessage = AppText.listeningForSpeech(from: audioInputSource)
            } catch is CancellationError {
            } catch {
                receiveQwenError(error, service: service, generation: generation)
            }
        }
    }

    private func finishQwenCapture() {
        guard !isFinishingQwenTranslation else { return }
        if isReconnectingQwenTranslation {
            qwenTransitionTask?.cancel()
            pipelineLifecycle.stop()
            finishPipeline(statusOverride: nil)
            return
        }
        isFinishingQwenTranslation = true
        statusMessage = QwenCopy.finishing
        audioSamplePipelineRegistry.clear()
        qwenTranslator.setPaused(true)
        let previousTransition = qwenTransitionTask
        let service = qwenTranslator
        let generation = pipelineLifecycle.generation
        qwenTransitionTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await stopCapture()
            if let previousTransition { await previousTransition.value }
            guard !Task.isCancelled, service === qwenTranslator,
                  pipelineLifecycle.acceptsSample(generation: generation) else { return }
            do {
                try await service.finish()
                guard !Task.isCancelled, service === qwenTranslator,
                      pipelineLifecycle.acceptsSample(generation: generation) else { return }
                pipelineLifecycle.stop()
                finishPipeline(statusOverride: nil)
            } catch is CancellationError {
            } catch {
                receiveQwenError(error, service: service, generation: generation)
            }
        }
    }

    private func receiveGrokError(_ error: Error, service: GrokRealtimeTranscriber?, generation: UInt64) {
        guard let service, service === grokTranscriber else { return }
        // 시작 오류는 start()의 throw 경로가 복구 버튼과 함께 표시한다.
        guard !isStarting else { return }
        handleFatalPipelineError(error, generation: generation)
    }

    private func pauseGrokCapture() {
        audioSamplePipelineRegistry.clear()
        grokTranscriber.setPaused(true)
        isPaused = true
        stopSpeaking()
        statusMessage = AppText.paused
        let service = grokTranscriber
        let generation = pipelineLifecycle.generation
        grokTransitionTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await service.finish()
                guard !Task.isCancelled, service === grokTranscriber,
                      pipelineLifecycle.acceptsSample(generation: generation) else { return }
                _ = checkpointPendingTranscriptSave()
            } catch is CancellationError {
            } catch {
                receiveGrokError(error, service: service, generation: generation)
            }
        }
    }

    private func resumeGrokCapture() {
        isReconnectingGrokSTT = true
        statusMessage = GrokCopy.reconnecting
        let previousTransition = grokTransitionTask
        let service = grokTranscriber
        let configuration = currentStartConfiguration()
        let generation = pipelineLifecycle.generation
        grokTransitionTask = Task { @MainActor [weak self] in
            guard let self else { return }
            if let previousTransition { await previousTransition.value }
            guard !Task.isCancelled, service === grokTranscriber, isPaused,
                  pipelineLifecycle.acceptsSample(generation: generation),
                  configuration == currentStartConfiguration() else { return }
            do {
                try await service.start(
                    model: configuration.grokTranscriptionModel,
                    sourceLanguage: configuration.sourceLanguage,
                    autoDetectLanguage: configuration.usesGrokSourceAutoDetection
                )
                guard !Task.isCancelled, service === grokTranscriber,
                      pipelineLifecycle.acceptsSample(generation: generation),
                      configuration == currentStartConfiguration() else { return }
                audioSamplePipelineRegistry.publish(
                    generation: generation, transcriber: transcriber,
                    openAITranscriber: openAITranscriber, geminiLiveTranslator: geminiLiveTranslator,
                    metaVoiceTranscriber: metaVoiceTranscriber, azureMAITranscriber: azureMAITranscriber,
                    grokTranscriber: service,
                    nariTranscriber: nariTranscriber,
                    qwenTranslator: qwenTranslator
                )
                isReconnectingGrokSTT = false
                isPaused = false
                statusMessage = AppText.listeningForSpeech(from: audioInputSource)
            } catch is CancellationError {
            } catch {
                receiveGrokError(error, service: service, generation: generation)
            }
        }
    }

    private func finishGrokCapture() {
        guard !isFinishingGrokSTT else { return }
        if isReconnectingGrokSTT {
            grokTransitionTask?.cancel()
            pipelineLifecycle.stop()
            finishPipeline(statusOverride: nil)
            return
        }
        isFinishingGrokSTT = true
        statusMessage = GrokCopy.finishing
        audioSamplePipelineRegistry.clear()
        grokTranscriber.setPaused(true)
        let previousTransition = grokTransitionTask
        let service = grokTranscriber
        let generation = pipelineLifecycle.generation
        grokTransitionTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await stopCapture()
            if let previousTransition { await previousTransition.value }
            guard !Task.isCancelled, service === grokTranscriber,
                  pipelineLifecycle.acceptsSample(generation: generation) else { return }
            do {
                try await service.finish()
                try await drainGrokTranslations()
                guard !Task.isCancelled, service === grokTranscriber,
                      pipelineLifecycle.acceptsSample(generation: generation) else { return }
                pipelineLifecycle.stop()
                finishPipeline(statusOverride: nil)
            } catch is CancellationError {
            } catch {
                receiveGrokError(error, service: service, generation: generation)
            }
        }
    }

    private func drainGrokTranslations() async throws {
        guard !isTranscribeOnlyMode else { return }
        let deadline = ContinuousClock.now.advanced(by: .seconds(15))
        while translationTask != nil, ContinuousClock.now < deadline {
            try Task.checkCancellation()
            try await Task.sleep(for: .milliseconds(20))
        }
        if translationTask != nil { throw GrokTranscriptionError.finishTimeout }
    }

    private func resetLiveSessionState(clearsVisibleLines: Bool) {
        grokTurnLineIDs.removeAll()
        grokFinalizedItemIDs.removeAll()
        grokItemOrder.removeAll()
        if clearsVisibleLines { grokSavedTranscriptText = "" }
        nariTurnLineIDs.removeAll()
        nariFinalizedItemIDs.removeAll()
        nariItemOrder.removeAll()
        if clearsVisibleLines { nariSavedTranscriptText = "" }
        if clearsVisibleLines { azureSavedTranscriptText = "" }
        audioSampleCount = 0
        latestAudioLevel = nil
        lastRecognizedText = ""
        lastRecognizedWasFinal = false
        currentLineID = nil
        lastCaptionPresentationUpdateAt = Date.distantPast
        pendingCaptionPresentation = nil
        captionPresentationTask?.cancel()
        captionPresentationTask = nil
        pendingRecognizedCaption = nil
        recognizedCaptionDeliveryTask?.cancel()
        recognizedCaptionDeliveryTask = nil
        lastRecognizedCaptionDeliveryAt = Date.distantPast
        isLargeTranscriptRecognitionCoalescingActive = false
        appleRecognitionTranslationState = AppleRecognitionTranslationPolicy.State()
        appleSpeechSegmentIDByLineID.removeAll()
        appleSpeechRevisionByLineID.removeAll()
        appleDubbingProgressByLineID.removeAll()
        appleDubbingLineOrder.removeAll()
        appleSmallPartialFlushTask?.cancel()
        appleSmallPartialFlushTask = nil
        committedSourceText = ""
        currentPartialText = ""
        currentPartialLanguage = nil
        appleRolloverReplayGuard = nil
        appleAutoDetectionPreferredLanguage = nil
        pendingAutoDetectionLanguageChange = nil
        pendingParagraphBreakBeforePartial = false
        floatingPresentationTask?.cancel()
        floatingPresentationTask = nil
        floatingTranslationHoldTask?.cancel()
        floatingTranslationHoldTask = nil
        if clearsVisibleLines {
            sourceLanguageByLineID.removeAll()
            floatingCommittedSourceText = ""
            floatingCurrentPartialText = ""
            pendingFloatingParagraphBreakBeforePartial = false
            floatingPresentedSourceText = ""
            floatingQueuedSourceText = ""
            floatingPresentedAt = Date.distantPast
            floatingPresentedUnreadLength = 0
            floatingDisplayTranslationText = ""
            floatingDisplayTranslationSourceText = ""
            floatingQueuedTranslationText = ""
            floatingQueuedTranslationSourceText = ""
            floatingTranslationPresentedAt = Date.distantPast
            floatingTranslationUnreadLength = 0
        } else {
            rehydrateFloatingCaptionDisplayFromCurrentLine()
        }
        pendingTranslationSourceText = ""
        latestTranslationRequest = nil
        orderedTranslationRequests = []
        translationBurstStartedAt = Date.distantPast
        if !clearsVisibleLines {
            clearPendingTranslationPlaceholders(message: AppText.translationCancelled)
        }
        resetTranslationCache()
        qwenSourceTranscript = QwenCaptionTranscript()
        qwenTranslationTranscript = QwenCaptionTranscript()
        realtimeTranslationSourceText = ""
        realtimeTranslationOnlyText = ""
        geminiLiveInputTranscriptText = ""
        geminiLiveOutputTranscriptText = ""
        metaActiveTurnID = nil
        metaTurnLineIDs = [:]
        metaTurnSpeakerLabels = [:]
        metaSavedTranscriptText = ""
        activeAutosaveSourceText = ""
        activeAutosaveTranslatedText = ""
        activeAutosaveBaseFileName = nil
        transcriptCheckpointTask?.cancel()
        transcriptCheckpointTask = nil
        stopSpeaking()
        dubbingSpeechProgress.reset()
        translationTask?.cancel()
        translationTask = nil
        transcriptCleanupTask?.cancel()
        transcriptCleanupTask = nil
        clearTranscribeOnlyNotice(resetActivation: clearsVisibleLines)

        if clearsVisibleLines {
            lines.removeAll()
        }
    }

    private func clearPendingTranslationPlaceholders(message: String) {
        for index in lines.indices where lines[index].translatedText == AppText.translating {
            let line = lines[index]
            lines[index] = CaptionLine(
                id: line.id,
                sourceText: line.sourceText,
                translatedText: message,
                translatedSourceText: line.sourceText,
                createdAt: line.createdAt,
                isFinal: line.isFinal,
                revision: line.revision + 1,
                speakerLabel: line.speakerLabel,
                usesLongSessionDisplay: usesLongSessionMode
            )
        }

        if floatingDisplayTranslationText == AppText.translating {
            floatingDisplayTranslationText = message
        }
        if floatingQueuedTranslationText == AppText.translating {
            floatingQueuedTranslationText = message
        }
    }

    private func warmTranslationSession() {
        cancelTranslationSessionWarmup()
        guard !isUsingQwenTranslation, !openAITranslationModel.isEnabled, !geminiTranslationModel.isEnabled else { return }

        let warmSourceLanguage = sourceLanguage
        let warmTargetLanguage = targetLanguage
        let warmSelectedModel = selectedModel
        let warmGeneration = pipelineLifecycle.generation
        let warmConfiguration = currentStartConfiguration()

        translationSessionWarmupGeneration = warmGeneration
        translationSessionWarmupTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                if let translationSessionPreparer {
                    try await translationSessionPreparer(
                        warmSourceLanguage,
                        warmTargetLanguage,
                        warmSelectedModel
                    )
                } else {
                    try await translator.prepare(
                        source: warmSourceLanguage,
                        target: warmTargetLanguage,
                        model: warmSelectedModel
                    )
                }
            } catch {
                guard !Task.isCancelled,
                      translationSessionWarmupGeneration == warmGeneration,
                      pipelineLifecycle.acceptsSample(generation: warmGeneration),
                      currentStartConfiguration() == warmConfiguration
                else {
                    return
                }
                statusMessage = error.localizedDescription
            }

            if translationSessionWarmupGeneration == warmGeneration {
                translationSessionWarmupTask = nil
                translationSessionWarmupGeneration = nil
            }
        }
    }

    private func cancelTranslationSessionWarmup() {
        translationSessionWarmupTask?.cancel()
        translationSessionWarmupTask = nil
        translationSessionWarmupGeneration = nil
    }

    func refreshModelAvailability() {
        if let request = modelAssetDownloadRequest,
           request.configuration != currentStartConfiguration() {
            cancelModelAssetDownload()
        }
        let sourceLanguage = sourceLanguage
        let targetLanguage = targetLanguage

        modelAvailabilityTask?.cancel()
        modelAvailabilityByModelID = Dictionary(
            uniqueKeysWithValues: IntelligenceModel.allCases.map {
                ($0.id, ModelAvailability.checking(for: $0))
            }
        )
        if let request = modelAssetDownloadRequest { markModelAssetsDownloading(request) }

        modelAvailabilityTask = Task { @MainActor [weak self, sourceLanguage, targetLanguage] in
            let availabilityByModelID = await self?.modelAvailabilityProvider(sourceLanguage, targetLanguage) ?? [:]
            guard !Task.isCancelled, let self,
                  sourceLanguage == self.sourceLanguage, targetLanguage == self.targetLanguage else { return }
            self.modelAvailabilityByModelID = availabilityByModelID
            if let request = self.modelAssetDownloadRequest { self.markModelAssetsDownloading(request) }
        }
    }

    private func restoreSelectedSettings() {
        isRestoringSelectedSettings = true
        defer { isRestoringSelectedSettings = false }

        let defaults = settingsDefaults
        if let sourceLanguageID = defaults.string(forKey: SettingsKey.sourceLanguageID),
           let language = LanguageOption.supported.first(where: { $0.id == sourceLanguageID }) {
            sourceLanguage = language
        }
        if let targetLanguageID = defaults.string(forKey: SettingsKey.targetLanguageID),
           let language = LanguageOption.supported.first(where: { $0.id == targetLanguageID }) {
            targetLanguage = language
        }
        if let modelID = defaults.string(forKey: SettingsKey.selectedModelID),
           let model = IntelligenceModel(rawValue: modelID) {
            selectedModel = model == .appleOnDevice ? .appleSystem : model
        }
        if let modelID = defaults.string(forKey: SettingsKey.openAITranscriptionModelID),
           let model = OpenAIRealtimeTranscriptionModel(rawValue: modelID) {
            openAITranscriptionModel = model
        }
        if defaults.string(forKey: SettingsKey.openAITranslationModelID) == "gpt-realtime-translate-only" {
            openAITranslationModel = .gptRealtimeTranslate
        } else if let modelID = defaults.string(forKey: SettingsKey.openAITranslationModelID),
                  let model = OpenAIRealtimeTranslationModel(rawValue: modelID) {
            openAITranslationModel = (model.isEnabled && !model.isSupportedLiveTranslationModel)
                ? .gptRealtimeTranslate
                : model
        }
        if let modelID = defaults.string(forKey: SettingsKey.geminiTranslationModelID),
           let model = GeminiTranslationModel(rawValue: modelID) {
            geminiTranslationModel = model
        }
        if let modelID = defaults.string(forKey: SettingsKey.preferredGeminiModelID),
           let model = GeminiTranslationModel(rawValue: modelID),
           model.isEnabled {
            preferredGeminiModel = model
        } else if geminiTranslationModel.isEnabled {
            preferredGeminiModel = geminiTranslationModel
        }
        if let modelID = defaults.string(forKey: SettingsKey.metaTranscriptionModelID),
           let model = MetaTranscriptionModel(rawValue: modelID) {
            metaTranscriptionModel = model
        }
        if defaults.object(forKey: SettingsKey.metaSpeakerLabelsEnabled) != nil {
            isMetaSpeakerLabelsEnabled = defaults.bool(forKey: SettingsKey.metaSpeakerLabelsEnabled)
        }
        if defaults.object(forKey: SettingsKey.appleVoiceOutputEnabled) != nil {
            appleVoiceOutputEnabled = defaults.bool(forKey: SettingsKey.appleVoiceOutputEnabled)
        }
        if defaults.object(forKey: SettingsKey.providerVoiceOutputEnabled) != nil {
            providerVoiceOutputEnabled = defaults.bool(forKey: SettingsKey.providerVoiceOutputEnabled)
        } else if defaults.object(forKey: SettingsKey.isDubbingEnabled) != nil {
            providerVoiceOutputEnabled = defaults.bool(forKey: SettingsKey.isDubbingEnabled)
        }
        if defaults.object(forKey: SettingsKey.translatedVoiceVolume) != nil {
            translatedVoiceVolume = Self.clampedVolume(defaults.double(forKey: SettingsKey.translatedVoiceVolume))
        }
        if defaults.object(forKey: SettingsKey.isTranscriptLintEnabled) != nil {
            isTranscriptLintEnabled = defaults.bool(forKey: SettingsKey.isTranscriptLintEnabled)
        }
        if defaults.object(forKey: SettingsKey.isTranscriptPersistenceEnabled) != nil {
            isTranscriptPersistenceEnabled = defaults.bool(forKey: SettingsKey.isTranscriptPersistenceEnabled)
        }
        if let modeID = defaults.string(forKey: SettingsKey.floatingCaptionDisplayMode),
           let mode = FloatingCaptionDisplayMode(rawValue: modeID) {
            if isTranscribeOnlyMode {
                floatingCaptionDisplayModeBeforeTranscribeOnly = mode
                floatingCaptionDisplayMode = .original
            } else {
                floatingCaptionDisplayMode = mode
            }
        }
        if let sizeID = defaults.string(forKey: SettingsKey.floatingCaptionTextSize),
           let size = FloatingCaptionTextSize(rawValue: sizeID) {
            floatingCaptionTextSize = size
        }
        if let lineCountID = defaults.string(forKey: SettingsKey.floatingCaptionLineCount),
           let rawValue = Int(lineCountID),
           let lineCount = FloatingCaptionLineCount(rawValue: rawValue) {
            floatingCaptionLineCount = lineCount
        }
        if defaults.object(forKey: SettingsKey.keepsFloatingCaptionAboveOtherWindows) != nil {
            keepsFloatingCaptionAboveOtherWindows = defaults.bool(forKey: SettingsKey.keepsFloatingCaptionAboveOtherWindows)
        }
        if let stabilityID = defaults.string(forKey: SettingsKey.floatingCaptionStability),
           let stability = FloatingCaptionStability(rawValue: stabilityID) {
            floatingCaptionStability = stability
        }
        if let alignmentID = defaults.string(forKey: SettingsKey.floatingCaptionTextAlignment),
           let alignment = FloatingCaptionTextAlignment(rawValue: alignmentID) {
            floatingCaptionTextAlignment = alignment
        }
        if let data = defaults.data(forKey: SettingsKey.floatingCaptionStyle),
           let style = try? JSONDecoder().decode(FloatingCaptionStyle.self, from: data) {
            floatingCaptionStyle = style
        }
        if defaults.object(forKey: SettingsKey.floatingCaptionCustomPointSize) != nil {
            floatingCaptionCustomPointSize = CGFloat(defaults.double(forKey: SettingsKey.floatingCaptionCustomPointSize))
        }
        if let textColorHex = defaults.string(forKey: SettingsKey.floatingCaptionTextColorHex) {
            floatingCaptionTextColorHex = FloatingCaptionAppearance.normalizedHex(
                textColorHex,
                fallback: FloatingCaptionAppearance.defaultTextColorHex
            )
        }
        if let backgroundColorHex = defaults.string(forKey: SettingsKey.floatingCaptionBackgroundColorHex) {
            floatingCaptionBackgroundColorHex = FloatingCaptionAppearance.normalizedHex(
                backgroundColorHex,
                fallback: FloatingCaptionAppearance.defaultBackgroundColorHex
            )
        }
        if defaults.object(forKey: SettingsKey.floatingCaptionBackgroundOpacity) != nil {
            floatingCaptionBackgroundOpacity = FloatingCaptionAppearance.clampedOpacity(
                defaults.double(forKey: SettingsKey.floatingCaptionBackgroundOpacity)
            )
        }
        if defaults.object(forKey: SettingsKey.paragraphBreakSilenceInterval) != nil {
            paragraphBreakSilenceInterval = min(
                max(defaults.double(forKey: SettingsKey.paragraphBreakSilenceInterval), 1),
                15
            )
        }
        if let contentModeID = defaults.string(forKey: SettingsKey.savedTranscriptContentMode),
           let contentMode = SavedTranscriptContentMode(rawValue: contentModeID) {
            savedTranscriptContentMode = contentMode
        }
        if let durationModeID = defaults.string(forKey: SettingsKey.sessionDurationMode),
           let durationMode = SessionDurationMode(rawValue: durationModeID) {
            sessionDurationMode = durationMode
        }
        if let audioInputSourceID = defaults.string(forKey: SettingsKey.audioInputSource),
           let source = AudioInputSource(rawValue: audioInputSourceID) {
            audioInputSource = source
        }
        if let deviceID = defaults.string(forKey: SettingsKey.selectedMicrophoneInputDeviceID) {
            selectedMicrophoneInputDeviceID = deviceID
        }
        isAppleSourceAutoDetectionEnabled = isAppleSourceAutoDetectionAvailable
            && defaults.bool(forKey: SettingsKey.isAppleSourceAutoDetectionEnabled)
        refreshMicrophoneInputDevices()
        azureSpeechEndpoint = defaults.string(forKey: "azureSpeechEndpoint") ?? ""
        let restoredAzureMode = defaults.bool(forKey: "azureMAIEnabled")
        let restoredGPTTranscriptionMode =
            defaults.string(forKey: SettingsKey.openAITranscriptionModelID)
            == OpenAIRealtimeTranscriptionModel.gptLiveTranscribe.rawValue
        let restoredGeminiTranscriptionMode = geminiTranslationModel.isTranscription
        let restoredMetaTranscriptionMode = metaTranscriptionModel.isEnabled
        let restoredNariModel = defaults.string(forKey: SettingsKey.nariTranscriptionModelID)
            .flatMap(NariTranscriptionModel.init(rawValue:)) ?? .off
        isNariSourceAutoDetectionEnabled = defaults.bool(forKey: SettingsKey.nariSourceAutoDetectionEnabled)
        let restoredGrokModel = defaults.string(forKey: SettingsKey.grokTranscriptionModelID)
            .flatMap(GrokTranscriptionModel.init(rawValue:)) ?? .off
        isGrokSourceAutoDetectionEnabled = defaults.object(forKey: SettingsKey.grokSourceAutoDetectionEnabled) as? Bool ?? true
        qwenWorkspaceID = defaults.string(forKey: "qwenWorkspaceID") ?? ""
        qwenVoiceOutputEnabled = defaults.bool(forKey: "qwenVoiceOutputEnabled")
        let restoredQwenModel = defaults.string(forKey: "qwenTranslationModelID")
            .flatMap(QwenTranslationModel.init(rawValue:)) ?? .off
        let restoredPreferredQwenModel = defaults.string(forKey: "preferredQwenTranslationModelID")
            .flatMap(QwenTranslationModel.init(rawValue:))
        if let restoredPreferredQwenModel, restoredPreferredQwenModel.isEnabled {
            preferredQwenModel = restoredPreferredQwenModel
        } else if restoredQwenModel.isEnabled {
            preferredQwenModel = restoredQwenModel
        }
        if restoredQwenModel.isEnabled {
            qwenTranslationModel = restoredQwenModel
        } else if restoredGrokModel.isEnabled {
            grokTranscriptionModel = restoredGrokModel
            if selectedModel == .appleSpeechOnly { prepareTranscribeOnlyPresentation() }
        } else if restoredNariModel.isEnabled {
            nariTranscriptionModel = restoredNariModel
            if selectedModel == .appleSpeechOnly { prepareTranscribeOnlyPresentation() }
        } else if restoredAzureMode {
            isUsingAzureMAI = true
        } else if restoredGPTTranscriptionMode {
            if floatingCaptionDisplayModeBeforeTranscribeOnly == nil {
                floatingCaptionDisplayModeBeforeTranscribeOnly = floatingCaptionDisplayMode
            }
            selectedModel = .appleSpeechOnly
            openAITranslationModel = .off
            geminiTranslationModel = .off
            metaTranscriptionModel = .off
            openAITranscriptionModel = .gptLiveTranscribe
            floatingCaptionDisplayMode = .original
            isDubbingEnabled = false
        } else if restoredGeminiTranscriptionMode {
            if floatingCaptionDisplayModeBeforeTranscribeOnly == nil {
                floatingCaptionDisplayModeBeforeTranscribeOnly = floatingCaptionDisplayMode
            }
            selectedModel = .appleSystem
            openAITranscriptionModel = .off
            openAITranslationModel = .off
            metaTranscriptionModel = .off
            floatingCaptionDisplayMode = .original
            isDubbingEnabled = false
        } else if restoredMetaTranscriptionMode {
            selectedModel = .appleSystem
            openAITranscriptionModel = .off
            openAITranslationModel = .off
            geminiTranslationModel = .off
        } else if openAITranslationModel.isEnabled {
            openAITranscriptionModel = .off
        } else if openAITranscriptionModel == .gptRealtimeWhisper {
            openAITranscriptionModel = .off
        }
        if isUsingOpenAIRealtime {
            preferredOpenAIOutputMode = liveOutputMode
        } else {
            preferredOpenAIOutputMode = defaults.string(forKey: SettingsKey.preferredOpenAIOutputMode)
                .flatMap(LiveOutputMode.init(rawValue:))
                ?? (restoredGPTTranscriptionMode ? .transcription : .translation)
        }
        if isUsingQwenTranslation {
            applyVoiceOutputDefault(qwenVoiceOutputEnabled)
        } else if ((restoredNariModel.isEnabled || restoredGrokModel.isEnabled) && isTranscribeOnlyMode) || restoredGPTTranscriptionMode || restoredGeminiTranscriptionMode {
            applyVoiceOutputDefault(false)
        } else {
            applyRestoredVoiceOutputPreference()
        }
    }

    private func persistSelectedSettings() {
        guard !isRestoringSelectedSettings else { return }

        if let request = modelAssetDownloadRequest,
           request.configuration != currentStartConfiguration() {
            cancelModelAssetDownload()
            refreshModelAvailability()
        }

        let defaults = settingsDefaults
        defaults.set(sourceLanguage.id, forKey: SettingsKey.sourceLanguageID)
        defaults.set(targetLanguage.id, forKey: SettingsKey.targetLanguageID)
        defaults.set(selectedModel.id, forKey: SettingsKey.selectedModelID)
        defaults.set(openAITranscriptionModel.id, forKey: SettingsKey.openAITranscriptionModelID)
        defaults.set(openAITranslationModel.id, forKey: SettingsKey.openAITranslationModelID)
        defaults.set(geminiTranslationModel.id, forKey: SettingsKey.geminiTranslationModelID)
        defaults.set(preferredOpenAIOutputMode.rawValue, forKey: SettingsKey.preferredOpenAIOutputMode)
        defaults.set(preferredGeminiModel.id, forKey: SettingsKey.preferredGeminiModelID)
        defaults.set(isUsingAzureMAI, forKey: "azureMAIEnabled")
        defaults.set(azureSpeechEndpoint, forKey: "azureSpeechEndpoint")
        defaults.set(metaTranscriptionModel.id, forKey: SettingsKey.metaTranscriptionModelID)
        defaults.set(qwenTranslationModel.rawValue, forKey: "qwenTranslationModelID")
        defaults.set((qwenTranslationModel.isEnabled ? qwenTranslationModel : preferredQwenModel).rawValue,
                     forKey: "preferredQwenTranslationModelID")
        defaults.set(qwenWorkspaceID, forKey: "qwenWorkspaceID")
        defaults.set(qwenVoiceOutputEnabled, forKey: "qwenVoiceOutputEnabled")
        defaults.set(grokTranscriptionModel.rawValue, forKey: SettingsKey.grokTranscriptionModelID)
        defaults.set(isGrokSourceAutoDetectionEnabled, forKey: SettingsKey.grokSourceAutoDetectionEnabled)
        defaults.set(nariTranscriptionModel.rawValue, forKey: SettingsKey.nariTranscriptionModelID)
        defaults.set(isNariSourceAutoDetectionEnabled, forKey: SettingsKey.nariSourceAutoDetectionEnabled)
        defaults.set(isMetaSpeakerLabelsEnabled, forKey: SettingsKey.metaSpeakerLabelsEnabled)
        defaults.set(isDubbingEnabled, forKey: SettingsKey.isDubbingEnabled)
        defaults.set(appleVoiceOutputEnabled, forKey: SettingsKey.appleVoiceOutputEnabled)
        defaults.set(providerVoiceOutputEnabled, forKey: SettingsKey.providerVoiceOutputEnabled)
        defaults.set(translatedVoiceVolume, forKey: SettingsKey.translatedVoiceVolume)
        defaults.set(isTranscriptLintEnabled, forKey: SettingsKey.isTranscriptLintEnabled)
        defaults.set(isTranscriptPersistenceEnabled, forKey: SettingsKey.isTranscriptPersistenceEnabled)
        defaults.set(
            (floatingCaptionDisplayModeBeforeTranscribeOnly ?? floatingCaptionDisplayMode).id,
            forKey: SettingsKey.floatingCaptionDisplayMode
        )
        defaults.set(floatingCaptionTextSize.id, forKey: SettingsKey.floatingCaptionTextSize)
        defaults.set(floatingCaptionLineCount.id, forKey: SettingsKey.floatingCaptionLineCount)
        defaults.set(keepsFloatingCaptionAboveOtherWindows, forKey: SettingsKey.keepsFloatingCaptionAboveOtherWindows)
        defaults.set(floatingCaptionStability.id, forKey: SettingsKey.floatingCaptionStability)
        defaults.set(floatingCaptionTextAlignment.id, forKey: SettingsKey.floatingCaptionTextAlignment)
        if let data = try? JSONEncoder().encode(floatingCaptionStyle) {
            defaults.set(data, forKey: SettingsKey.floatingCaptionStyle)
        }
        defaults.set(Double(floatingCaptionCustomPointSize), forKey: SettingsKey.floatingCaptionCustomPointSize)
        defaults.set(floatingCaptionTextColorHex, forKey: SettingsKey.floatingCaptionTextColorHex)
        defaults.set(floatingCaptionBackgroundColorHex, forKey: SettingsKey.floatingCaptionBackgroundColorHex)
        defaults.set(floatingCaptionBackgroundOpacity, forKey: SettingsKey.floatingCaptionBackgroundOpacity)
        defaults.set(paragraphBreakSilenceInterval, forKey: SettingsKey.paragraphBreakSilenceInterval)
        defaults.set(savedTranscriptContentMode.id, forKey: SettingsKey.savedTranscriptContentMode)
        defaults.set(sessionDurationMode.id, forKey: SettingsKey.sessionDurationMode)
        defaults.set(audioInputSource.id, forKey: SettingsKey.audioInputSource)
        defaults.set(selectedMicrophoneInputDeviceID, forKey: SettingsKey.selectedMicrophoneInputDeviceID)
        defaults.set(isAppleSourceAutoDetectionEnabled, forKey: SettingsKey.isAppleSourceAutoDetectionEnabled)
    }

    private func stopCapture() async {
        await systemAudioCapture.stop()
        await microphoneAudioCapture.stop()
    }

    func floatingCaptionText(from text: String?, usesPrimaryFont: Bool = true) -> String {
        guard let text else { return "" }
        if floatingCaptionMeasuredTextWidth > 0 {
            let pointSize = usesPrimaryFont ? floatingCaptionPrimaryPointSize : floatingCaptionSecondaryPointSize
            return text.floatingCaptionTail(
                maxLines: floatingCaptionEffectiveLineCount,
                availableWidth: floatingCaptionMeasuredTextWidth,
                font: floatingCaptionStyle.nativeFont(size: pointSize, primary: usesPrimaryFont)
            )
        }
        return text.floatingCaptionTail(
            maxLines: floatingCaptionEffectiveLineCount,
            lineWidthUnits: floatingCaptionLineWidthUnits(usesPrimaryFont: usesPrimaryFont)
        )
    }

    func floatingCaptionLineWidthUnits(usesPrimaryFont: Bool) -> Double {
        let textSize = floatingCaptionTextSize
        let pointSize = usesPrimaryFont ? floatingCaptionPrimaryPointSize : floatingCaptionSecondaryPointSize
        let measuredUnits = FloatingCaptionTextSize.lineWidthUnits(
            forAvailableWidth: floatingCaptionMeasuredTextWidth,
            pointSize: pointSize * floatingCaptionStyle.fontFamily.widthScale
        )
        guard measuredUnits > 0 else {
            let fallback = textSize.floatingLineWidthUnits
            return usesPrimaryFont
                ? fallback
                : fallback * Double(floatingCaptionPrimaryPointSize / floatingCaptionSecondaryPointSize)
        }
        return measuredUnits
    }

    private var floatingSourceUsesPrimaryFont: Bool {
        floatingCaptionDisplayMode != .originalAndTranslation
    }

    private func loadSavedTranscripts() {
        do {
            try FileManager.default.createDirectory(
                at: transcriptsDirectoryURL,
                withIntermediateDirectories: true
            )
            let fileURLs = try FileManager.default.contentsOfDirectory(
                at: transcriptsDirectoryURL,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )
            let transcriptFiles = fileURLs
                .filter { $0.pathExtension == "txt" }
                .compactMap { fileURL -> SavedTranscriptFile? in
                    let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey])
                    return SavedTranscriptFile(
                        fileName: fileURL.lastPathComponent,
                        previewText: transcriptPreview(fileURL: fileURL),
                        updatedAt: values?.contentModificationDate ?? Date.distantPast
                    )
                }
            savedTranscripts = groupedSavedTranscripts(from: transcriptFiles)
            sortSavedTranscripts()
        } catch {
            savedTranscripts = []
        }
    }

    private func transcriptPreview(fileURL: URL) -> String {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return "" }
        defer { try? handle.close() }

        let data = (try? handle.read(upToCount: 4_096)) ?? Data()
        return String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func loadTranscriptText(fileName: String) -> String? {
        try? String(contentsOf: transcriptURL(fileName: fileName), encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func groupedSavedTranscripts(from files: [SavedTranscriptFile]) -> [SavedTranscript] {
        var standaloneTranscripts: [SavedTranscript] = []
        var partialTranscripts: [String: PartialSavedTranscript] = [:]

        for file in files {
            if let variant = transcriptVariantInfo(file.fileName) {
                var partial = partialTranscripts[variant.baseFileName] ?? PartialSavedTranscript()
                switch variant.part {
                case .original:
                    partial.original = file
                case .translation:
                    partial.translation = file
                }
                partialTranscripts[variant.baseFileName] = partial
            } else {
                standaloneTranscripts.append(
                    SavedTranscript(
                        fileName: file.fileName,
                        sourceText: file.previewText,
                        updatedAt: file.updatedAt
                    )
                )
            }
        }

        for (baseFileName, partial) in partialTranscripts {
            if let original = partial.original, let translation = partial.translation {
                standaloneTranscripts.append(
                    SavedTranscript(
                        id: baseFileName,
                        sourceFileName: original.fileName,
                        translationFileName: translation.fileName,
                        sourceText: original.previewText,
                        translatedText: translation.previewText,
                        updatedAt: max(original.updatedAt, translation.updatedAt)
                    )
                )
            } else if let original = partial.original {
                standaloneTranscripts.append(
                    SavedTranscript(
                        fileName: original.fileName,
                        sourceText: original.previewText,
                        updatedAt: original.updatedAt
                    )
                )
            } else if let translation = partial.translation {
                standaloneTranscripts.append(
                    SavedTranscript(
                        fileName: translation.fileName,
                        sourceText: translation.previewText,
                        updatedAt: translation.updatedAt
                    )
                )
            }
        }

        return standaloneTranscripts
    }

    private func stageTranscriptForSave(_ sourceText: String, translatedText: String? = nil) {
        guard isTranscriptPersistenceEnabled else { return }

        // 전체 이력 조합은 체크포인트에서만 수행해 매 부분 결과의 비용을 제한한다.
        let sourceText = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sourceText.isEmpty else { return }

        activeAutosaveSourceText = sourceText
        if let translatedText {
            let translatedText = translatedText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !translatedText.isEmpty, translatedText != AppText.translating {
                activeAutosaveTranslatedText = translatedText
            }
        }
        scheduleTranscriptCheckpointIfNeeded()
    }

    private func scheduleTranscriptCheckpointIfNeeded() {
        guard isTranscriptPersistenceEnabled, isRunning, transcriptCheckpointTask == nil else { return }

        let intervalMilliseconds = max(Int(transcriptCheckpointInterval * 1_000), 1)
        transcriptCheckpointTask = Task { @MainActor [weak self] in
            while let self, !Task.isCancelled, self.isRunning {
                try? await Task.sleep(for: .milliseconds(intervalMilliseconds))
                guard !Task.isCancelled, self.isRunning else { break }
                if !self.isPaused {
                    _ = self.checkpointPendingTranscriptSave()
                }
            }
        }
    }

    @discardableResult
    private func checkpointPendingTranscriptSave() -> Bool {
        guard isTranscriptPersistenceEnabled else { return false }
        return persistPendingTranscriptSave(clearsStagedText: false, reloadsLibrary: false)
    }

    @discardableResult
    private func flushPendingTranscriptSave() -> Bool {
        guard isTranscriptPersistenceEnabled else { return false }
        return persistPendingTranscriptSave(clearsStagedText: true, reloadsLibrary: true)
    }

    @discardableResult
    private func persistPendingTranscriptSave(
        clearsStagedText: Bool,
        reloadsLibrary: Bool
    ) -> Bool {
        guard isTranscriptPersistenceEnabled else { return false }

        let currentSourceText = usesAppleCaptionRollover && lines.count > 1
            ? appleSavedSourceTranscriptText
            : visibleTranscript().trimmingCharacters(in: .whitespacesAndNewlines)
        if !currentSourceText.isEmpty {
            activeAutosaveSourceText = currentSourceText
        }
        if usesAppleCaptionRollover && lines.count > 1 {
            let translatedText = appleSavedTranslatedTranscriptText
            if !translatedText.isEmpty {
                activeAutosaveTranslatedText = translatedText
            }
        }
        if isUsingGrokSTT || isUsingNariSTT {
            activeAutosaveSourceText = isUsingGrokSTT ? grokSavedTranscriptText : nariSavedTranscriptText
            activeAutosaveTranslatedText = lines.filter {
                $0.isFinal && $0.translatedSourceText == $0.sourceText
                    && !$0.translatedText.isEmpty && $0.translatedText != AppText.translating
                    && $0.translatedText != AppText.translationCancelled
            }.map(\.translatedText).joined(separator: "\n")
        }

        if isUsingQwenTranslation {
            // 어떤 저장 진입점에서도 아직 철회 가능한 delta를 파일에 확정하지 않는다.
            activeAutosaveSourceText = qwenSourceTranscript.completed
            activeAutosaveTranslatedText = qwenTranslationTranscript.completed
        }

        let sourceText = activeAutosaveSourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sourceText.isEmpty else { return false }

        let updatedAt = Date()
        let baseFileName = activeAutosaveBaseFileName
            ?? makeTranscriptFileName(for: sourceText, date: updatedAt)
        activeAutosaveBaseFileName = baseFileName
        let savedFiles = savedTranscriptFiles(
            sourceText: sourceText,
            translatedText: activeAutosaveTranslatedText,
            baseFileName: baseFileName
        )

        for savedFile in savedFiles {
            guard writeTranscriptText(savedFile.text, fileName: savedFile.fileName) else {
                return false
            }
        }

        if clearsStagedText {
            activeAutosaveSourceText = ""
            activeAutosaveTranslatedText = ""
            activeAutosaveBaseFileName = nil
        }
        if reloadsLibrary {
            loadSavedTranscripts()
        }
        return true
    }

    private var appleSavedSourceTranscriptText: String {
        lines
            .map { $0.sourceText.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }

    private var appleSavedTranslatedTranscriptText: String {
        lines
            .map { $0.translatedText.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0 != AppText.translating }
            .joined(separator: "\n\n")
    }

    private func savedTranscriptFiles(
        sourceText: String,
        translatedText: String,
        baseFileName: String
    ) -> [(fileName: String, text: String)] {
        let sourceText = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        let translatedText = translatedText.trimmingCharacters(in: .whitespacesAndNewlines)

        switch effectiveSavedTranscriptContentMode {
        case .original:
            return [(baseFileName, sourceText)]
        case .translation:
            return [(baseFileName, translatedText.isEmpty ? sourceText : translatedText)]
        case .originalAndTranslation:
            var files = [
                (transcriptVariantFileName(baseFileName, suffix: "original"), sourceText)
            ]
            if !translatedText.isEmpty {
                files.append(
                    (transcriptVariantFileName(baseFileName, suffix: "translation"), translatedText)
                )
            }
            return files
        }
    }

    @discardableResult
    private func writeTranscriptText(_ text: String, fileName: String) -> Bool {
        do {
            try FileManager.default.createDirectory(
                at: transcriptsDirectoryURL,
                withIntermediateDirectories: true
            )
            try text.write(
                to: transcriptURL(fileName: fileName),
                atomically: true,
                encoding: .utf8
            )
            return true
        } catch {
            statusMessage = AppText.saveLibraryFailed(error.localizedDescription)
            return false
        }
    }

    private func showToast(_ message: String) {
        toastDismissTask?.cancel()
        toastMessage = message
        toastSequence += 1

        let sequence = toastSequence
        toastDismissTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            guard toastSequence == sequence else { return }
            toastMessage = nil
        }
    }

    private func sortSavedTranscripts() {
        savedTranscripts.sort { $0.updatedAt > $1.updatedAt }
    }

    private var transcriptsDirectoryURL: URL {
        if let transcriptsDirectoryOverride {
            return transcriptsDirectoryOverride
        }

        let supportDirectory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        return supportDirectory
            .appendingPathComponent("AirTranslate", isDirectory: true)
            .appendingPathComponent("Transcripts", isDirectory: true)
    }

    private func transcriptURL(fileName: String) -> URL {
        transcriptsDirectoryURL.appendingPathComponent(fileName)
    }

    private func transcriptVariantFileName(_ fileName: String, suffix: String) -> String {
        let stem = fileName.hasSuffix(".txt") ? String(fileName.dropLast(4)) : fileName
        return "\(stem)_\(suffix).txt"
    }

    private func legacyTranscriptVariantFileName(_ fileName: String, suffix: String) -> String {
        let stem = fileName.hasSuffix(".txt") ? String(fileName.dropLast(4)) : fileName
        return "\(stem)-\(suffix).txt"
    }

    private func transcriptVariantInfo(_ fileName: String) -> (baseFileName: String, part: SavedTranscriptPart)? {
        let variants: [(suffix: String, part: SavedTranscriptPart)] = [
            ("_original.txt", .original),
            ("_translation.txt", .translation),
            ("-original.txt", .original),
            ("-translation.txt", .translation)
        ]

        for variant in variants where fileName.hasSuffix(variant.suffix) {
            let stem = String(fileName.dropLast(variant.suffix.count))
            return ("\(stem).txt", variant.part)
        }

        return nil
    }

    private func makeTranscriptFileName(for sourceText: String, date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HH-mm"
        let timestamp = formatter.string(from: date)
        let baseName = "\(timestamp)_\(shortFileTitle(from: sourceText))"
        var fileName = "\(baseName).txt"
        var suffix = 2

        while transcriptFileExists(fileName) {
            fileName = "\(baseName)_\(suffix).txt"
            suffix += 1
        }

        return fileName
    }

    private func transcriptFileExists(_ fileName: String) -> Bool {
        let fileNames = [
            fileName,
            transcriptVariantFileName(fileName, suffix: "original"),
            transcriptVariantFileName(fileName, suffix: "translation"),
            legacyTranscriptVariantFileName(fileName, suffix: "original"),
            legacyTranscriptVariantFileName(fileName, suffix: "translation")
        ]
        return fileNames.contains { FileManager.default.fileExists(atPath: transcriptURL(fileName: $0).path) }
    }

    private func shortFileTitle(from sourceText: String) -> String {
        let firstLine = sourceText
            .split(separator: "\n", omittingEmptySubsequences: true)
            .first
            .map(String.init) ?? AppText.untitledTranscript
        let allowedCharacters = CharacterSet.letters
            .union(.decimalDigits)
            .union(.whitespacesAndNewlines)
            .union(CharacterSet(charactersIn: "-_"))
        let readableText = String(firstLine.unicodeScalars.map { scalar in
            allowedCharacters.contains(scalar) ? Character(scalar) : " "
        })
        let sanitized = readableText
            .replacingOccurrences(of: #"\s+"#, with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".-_ "))

        guard !sanitized.isEmpty else {
            return AppText.untitledTranscript.replacingOccurrences(of: " ", with: "-")
        }

        return String(sanitized.prefix(32))
    }

    private func appendCaption(
        sourceText: String,
        recognizedLanguage: LanguageOption,
        confidence: Double,
        isFinal: Bool,
        metadata: AppleSpeechRecognitionMetadata? = nil
    ) {
        guard isRunning, !isPaused else { return }
        guard sourceText != lastRecognizedText || isFinal != lastRecognizedWasFinal || metadata != nil else { return }
        guard appleRecognitionTranslationPolicy.acceptsRecognition(
            metadata,
            state: appleRecognitionTranslationState
        ) else {
            return
        }

        let now = Date()
        let hadLongSilence = now.timeIntervalSince(lastRecognitionAt) > paragraphBreakSilenceInterval
        if shouldRequestAutoDetectionLanguageChange(
            recognizedLanguage: recognizedLanguage,
            confidence: confidence,
            hadLongSilence: hadLongSilence
        ) {
            pauseForAutoDetectionLanguageChange(
                detectedLanguage: recognizedLanguage,
                sourceText: sourceText,
                confidence: confidence
            )
            return
        }
        guard shouldAcceptRecognizedLanguage(
            recognizedLanguage: recognizedLanguage,
            confidence: confidence,
            hadLongSilence: hadLongSilence
        ) else {
            return
        }
        let direction = translationDirection(recognizedLanguage: recognizedLanguage)
        let updatedSourceText: String
        if metadata != nil {
            updatedSourceText = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
            prepareAppleSpeechSegmentForAuthoritativeUpdate(
                sourceText: updatedSourceText,
                language: direction.source,
                metadata: metadata
            )
        } else {
            updatedSourceText = accumulatedTranscript(
                incoming: sourceText,
                hadLongSilence: hadLongSilence,
                isFinal: isFinal,
                language: direction.source
            )
        }
        guard !updatedSourceText.isEmpty else { return }

        lastRecognizedText = sourceText
        lastRecognizedWasFinal = isFinal
        lastRecognitionAt = now
        transcriptCleanupTask?.cancel()

        if let currentLineID,
           let index = lines.firstIndex(where: { $0.id == currentLineID }) {
            let existingLine = lines[index]
            let sourceLanguageChanged = sourceLanguageByLineID[existingLine.id] != direction.source
            sourceLanguageByLineID[existingLine.id] = direction.source
            updateAppleSpeechIdentity(lineID: existingLine.id, metadata: metadata)
            guard updatedSourceText != existingLine.sourceText || sourceLanguageChanged || metadata != nil else { return }
            if sourceLanguageChanged, updatedSourceText == existingLine.sourceText {
                pendingTranslationSourceText = ""
                requestTranslationForAppleRecognition(
                    for: existingLine,
                    source: direction.source,
                    target: direction.target,
                    metadata: metadata
                )
                finalizeAppleSpeechSegmentIfNeeded(lineID: existingLine.id, metadata: metadata)
                return
            }

            if shouldPresentCaptionUpdate(sourceText: updatedSourceText, isFinal: isFinal) {
                clearPendingCaptionPresentation()
                let updatedLine = presentCaptionLineUpdate(
                    lineID: existingLine.id,
                    sourceText: updatedSourceText,
                    isFinal: isFinal,
                    source: direction.source,
                    target: direction.target,
                    metadata: metadata
                )
                if let updatedLine {
                    requestTranslationForAppleRecognition(
                        for: updatedLine,
                        source: direction.source,
                        target: direction.target,
                        metadata: metadata
                    )
                    finalizeAppleSpeechSegmentIfNeeded(lineID: updatedLine.id, metadata: metadata)
                }
            } else {
                scheduleCaptionPresentation(
                    lineID: existingLine.id,
                    sourceText: updatedSourceText,
                    isFinal: isFinal,
                    source: direction.source,
                    target: direction.target,
                    metadata: metadata
                )
            }
        } else {
            clearPendingCaptionPresentation()
            let line = CaptionLine(
                sourceText: updatedSourceText,
                translatedText: AppText.translating,
                createdAt: Date(),
                isFinal: isFinal,
                revision: 1,
                usesLongSessionDisplay: usesLongSessionMode
            )
            currentLineID = line.id
            sourceLanguageByLineID[line.id] = direction.source
            updateAppleSpeechIdentity(lineID: line.id, metadata: metadata)
            lines.append(line)
            lastCaptionPresentationUpdateAt = Date()
            stageTranscriptForSave(line.sourceText)
            requestTranslationForAppleRecognition(
                for: line,
                source: direction.source,
                target: direction.target,
                metadata: metadata
            )
            finalizeAppleSpeechSegmentIfNeeded(lineID: line.id, metadata: metadata)
        }
    }

    private func enqueueRecognizedCaption(
        sourceText: String,
        recognizedLanguage: LanguageOption,
        confidence: Double,
        metadata: AppleSpeechRecognitionMetadata? = nil
    ) {
        let isFinal = metadata?.isFinal ?? false
        if isFinal {
            flushPendingRecognizedCaption()
        }

        if !isLargeTranscriptRecognitionCoalescingActive {
            let currentSourceLength = lines.last?.sourceText.utf16.count ?? 0
            isLargeTranscriptRecognitionCoalescingActive = usesLongSessionMode
                || currentSourceLength >= Self.largeTranscriptPresentationCharacterLimit
                || sourceText.utf16.count >= Self.largeTranscriptPresentationCharacterLimit
        }

        guard isLargeTranscriptRecognitionCoalescingActive, !isFinal else {
            lastRecognizedCaptionDeliveryAt = Date()
            appendCaption(
                sourceText: sourceText,
                recognizedLanguage: recognizedLanguage,
                confidence: confidence,
                isFinal: isFinal,
                metadata: metadata
            )
            return
        }

        pendingRecognizedCaption = PendingRecognizedCaption(
            sourceText: sourceText,
            recognizedLanguage: recognizedLanguage,
            confidence: confidence,
            metadata: metadata
        )
        guard recognizedCaptionDeliveryTask == nil else { return }

        let elapsed = Date().timeIntervalSince(lastRecognizedCaptionDeliveryAt)
        let delay = max(0, Self.largeTranscriptRecognitionDeliveryInterval - elapsed)
        guard delay > 0 else {
            flushPendingRecognizedCaption()
            return
        }

#if DEBUG
        if usesManualCaptionDeliveryForTesting { return }
#endif
        recognizedCaptionDeliveryTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(Int(delay * 1_000)))
            guard !Task.isCancelled else { return }
            self?.flushPendingRecognizedCaption()
        }
    }

    private func flushPendingRecognizedCaption() {
        recognizedCaptionDeliveryTask?.cancel()
        recognizedCaptionDeliveryTask = nil
        guard let pendingRecognizedCaption else { return }

        self.pendingRecognizedCaption = nil
        lastRecognizedCaptionDeliveryAt = Date()
        appendCaption(
            sourceText: pendingRecognizedCaption.sourceText,
            recognizedLanguage: pendingRecognizedCaption.recognizedLanguage,
            confidence: pendingRecognizedCaption.confidence,
            isFinal: pendingRecognizedCaption.metadata?.isFinal ?? false,
            metadata: pendingRecognizedCaption.metadata
        )
    }

    private var currentAutoDetectedSourceLanguage: LanguageOption? {
        if let currentPartialLanguage {
            return currentPartialLanguage
        }

        if let currentLineID,
           let lineLanguage = sourceLanguageByLineID[currentLineID] {
            return lineLanguage
        }

        return lines.last.flatMap { sourceLanguageByLineID[$0.id] }
    }

    private func shouldRequestAutoDetectionLanguageChange(
        recognizedLanguage: LanguageOption,
        confidence: Double,
        hadLongSilence: Bool
    ) -> Bool {
        AutoDetectionLanguageChangePolicy.shouldRequestConfirmation(
            isAutoDetectionEnabled: isUsingAppleSourceAutoDetection,
            activeLanguage: currentAutoDetectedSourceLanguage,
            detectedLanguage: recognizedLanguage,
            confidence: confidence,
            hadLongSilence: hadLongSilence,
            hasVisibleTranscript: !visibleTranscript().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            minimumSwitchConfidence: Self.appleAutoDetectionLanguageSwitchMinimumConfidence
        )
    }

    private func pauseForAutoDetectionLanguageChange(
        detectedLanguage: LanguageOption,
        sourceText: String,
        confidence: Double
    ) {
        guard pendingAutoDetectionLanguageChange == nil,
              let currentLanguage = currentAutoDetectedSourceLanguage
        else {
            return
        }

        flushPendingCaptionPresentation()
        transcriptCleanupTask?.cancel()
        transcriptCleanupTask = nil
        commitCurrentPartial()
        organizeCurrentTranscript(sourceTextOverride: visibleTranscript())
        pendingAutoDetectionLanguageChange = AutoDetectionLanguageChangeConfirmation(
            currentLanguage: currentLanguage,
            detectedLanguage: detectedLanguage,
            targetLanguage: targetLanguage,
            sourceText: sourceText,
            confidence: confidence
        )
        setCaptionersPaused(true)
        stopSpeaking()
        isPaused = true
        statusMessage = AppText.autoDetectionLanguageChangePaused(
            current: currentLanguage.localizedTitle,
            detected: detectedLanguage.localizedTitle
        )
    }

    private func shouldPresentCaptionUpdate(sourceText: String, isFinal: Bool) -> Bool {
        let sourceLength = sourceText.utf16.count
        guard sourceLength >= Self.largeTranscriptPresentationCharacterLimit else { return true }

        let elapsed = Date().timeIntervalSince(lastCaptionPresentationUpdateAt)
        let interval = isFinal
            ? Self.largeTranscriptPresentationInterval / 2
            : Self.largeTranscriptPresentationInterval
        return elapsed >= interval
    }

    private func shouldAcceptRecognizedLanguage(
        recognizedLanguage: LanguageOption,
        confidence: Double,
        hadLongSilence: Bool
    ) -> Bool {
        guard isUsingAppleSourceAutoDetection else { return true }
        guard confidence >= Self.appleAutoDetectionMinimumConfidence else { return false }
        if currentPartialLanguage == nil,
           let appleAutoDetectionPreferredLanguage,
           appleAutoDetectionPreferredLanguage != recognizedLanguage {
            return confidence >= Self.appleAutoDetectionLanguageSwitchMinimumConfidence
        }
        guard let currentPartialLanguage else { return true }
        guard currentPartialLanguage != recognizedLanguage else { return true }

        return false
    }

    private func scheduleCaptionPresentation(
        lineID: UUID,
        sourceText: String,
        isFinal: Bool,
        source: LanguageOption,
        target: LanguageOption,
        metadata: AppleSpeechRecognitionMetadata?
    ) {
        pendingCaptionPresentation = PendingCaptionPresentation(
            lineID: lineID,
            sourceText: sourceText,
            isFinal: isFinal,
            source: source,
            target: target,
            metadata: metadata
        )
        captionPresentationTask?.cancel()

        let elapsed = Date().timeIntervalSince(lastCaptionPresentationUpdateAt)
        let delay = max(0, Self.largeTranscriptPresentationInterval - elapsed)
#if DEBUG
        if usesManualCaptionDeliveryForTesting { return }
#endif
        captionPresentationTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(Int(delay * 1_000)))
            guard !Task.isCancelled else { return }
            flushPendingCaptionPresentation()
        }
    }

    private func flushPendingCaptionPresentation() {
        guard let pendingCaptionPresentation else { return }

        self.pendingCaptionPresentation = nil
        captionPresentationTask?.cancel()
        captionPresentationTask = nil
        let line = presentCaptionLineUpdate(
            lineID: pendingCaptionPresentation.lineID,
            sourceText: pendingCaptionPresentation.sourceText,
            isFinal: pendingCaptionPresentation.isFinal,
            source: pendingCaptionPresentation.source,
            target: pendingCaptionPresentation.target,
            metadata: pendingCaptionPresentation.metadata
        )
        if let line {
            requestTranslationForAppleRecognition(
                for: line,
                source: pendingCaptionPresentation.source,
                target: pendingCaptionPresentation.target,
                metadata: pendingCaptionPresentation.metadata
            )
            finalizeAppleSpeechSegmentIfNeeded(
                lineID: line.id,
                metadata: pendingCaptionPresentation.metadata
            )
        }
    }

    private func clearPendingCaptionPresentation() {
        pendingCaptionPresentation = nil
        captionPresentationTask?.cancel()
        captionPresentationTask = nil
    }

    @discardableResult
    private func presentCaptionLineUpdate(
        lineID: UUID,
        sourceText: String,
        isFinal: Bool,
        source: LanguageOption,
        target: LanguageOption,
        metadata: AppleSpeechRecognitionMetadata? = nil
    ) -> CaptionLine? {
        if PipelineDiagnostics.isEnabled {
            PipelineDiagnostics.record("caption.present", id: lineID.uuidString, values: ["characters": Double(sourceText.count)])
        }
        guard let index = lines.firstIndex(where: { $0.id == lineID }) else { return nil }

        let existingLine = lines[index]
        guard sourceText != existingLine.sourceText || isFinal != existingLine.isFinal || metadata != nil else {
            updateAppleSpeechIdentity(lineID: existingLine.id, metadata: metadata)
            return existingLine
        }

        let line = CaptionLine(
            id: existingLine.id,
            sourceText: sourceText,
            translatedText: existingLine.translatedText,
            translatedSourceText: existingLine.translatedSourceText,
            createdAt: existingLine.createdAt,
            isFinal: isFinal,
            revision: existingLine.revision + 1,
            usesLongSessionDisplay: usesLongSessionMode
        )
        lines[index] = line
        updateAppleSpeechIdentity(lineID: line.id, metadata: metadata)
        lastCaptionPresentationUpdateAt = Date()
        stageTranscriptForSave(line.sourceText)
        return line
    }

    private func accumulatedTranscript(
        incoming: String,
        hadLongSilence: Bool,
        isFinal: Bool,
        language: LanguageOption
    ) -> String {
        let trimmedIncoming = incoming.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedIncoming.isEmpty else { return visibleTranscript() }

        if hadLongSilence, !currentPartialText.isEmpty {
            commitCurrentPartial(rolloverContext: .longSilence)
            pendingParagraphBreakBeforePartial = !committedSourceText.isEmpty
            pendingFloatingParagraphBreakBeforePartial = !floatingCommittedSourceText.isEmpty
        }

        let incomingPartial = uncommittedIncomingText(
            from: trimmedIncoming,
            allowsCommittedRevision: !hadLongSilence,
            allowsCommittedReplay: !hadLongSilence,
            language: language
        )
        guard !incomingPartial.isEmpty else { return visibleTranscript() }

        if currentPartialText.isEmpty {
            currentPartialText = incomingPartial
            currentPartialLanguage = language
            setFloatingCurrentPartialText(incomingPartial)
            return visibleTranscript()
        }

        if currentPartialLanguage != language {
            commitCurrentPartial(rolloverContext: .sentenceBoundary)
            pendingParagraphBreakBeforePartial = hadLongSilence && !committedSourceText.isEmpty
            pendingFloatingParagraphBreakBeforePartial = hadLongSilence && !floatingCommittedSourceText.isEmpty
            currentPartialText = incomingPartial
            currentPartialLanguage = language
            setFloatingCurrentPartialText(currentPartialText)
            return visibleTranscript()
        }

        if isRevisionOfCurrentPartial(incomingPartial) {
            currentPartialText = preferredPartialText(current: currentPartialText, incoming: incomingPartial)
            setFloatingCurrentPartialText(currentPartialText)
            return visibleTranscript()
        }

        if !hadLongSilence,
           !isFinal,
           isVolatileFragmentSuperseded(by: incomingPartial) {
            currentPartialText = incomingPartial
            setFloatingCurrentPartialText(currentPartialText)
            return visibleTranscript()
        }

        commitCurrentPartial(rolloverContext: .sentenceBoundary)
        pendingParagraphBreakBeforePartial = hadLongSilence && !committedSourceText.isEmpty
        pendingFloatingParagraphBreakBeforePartial = hadLongSilence && !floatingCommittedSourceText.isEmpty
        currentPartialText = uncommittedIncomingText(
            from: trimmedIncoming,
            allowsCommittedRevision: true,
            allowsCommittedReplay: true,
            language: language
        )
        currentPartialLanguage = language
        setFloatingCurrentPartialText(currentPartialText)
        return visibleTranscript()
    }

    private func uncommittedIncomingText(
        from incoming: String,
        allowsCommittedRevision: Bool,
        allowsCommittedReplay: Bool,
        language: LanguageOption
    ) -> String {
        if allowsCommittedReplay,
           let replayTail = incomingTailAfterRecentCommittedReplay(incoming, language: language) {
            syncFloatingCommittedSourceTextToCommittedSourceText()
            return replayTail
        }

        if allowsCommittedReplay,
           TranscriptTextProcessor.committedTranscriptAlreadyMatches(
               incoming,
               in: replayComparisonCommittedText()
           ) {
            return ""
        }

        if allowsCommittedRevision,
           replaceCommittedUnitsIfRevision(with: incoming, language: language, allowsBackfill: true) {
            syncFloatingCommittedSourceTextToCommittedSourceText()
            return ""
        }

        if let tail = incomingTailAfterCommittedText(
            incoming,
            allowsCommittedReplay: allowsCommittedReplay
        ) {
            return tail
        }

        return incoming
    }

    private func incomingTailAfterRecentCommittedReplay(_ incoming: String, language: LanguageOption) -> String? {
        guard let replay = TranscriptTextProcessor.incomingTailAfterRecentCommittedReplay(
            incoming,
            committedText: replayComparisonCommittedText(),
            languageID: language.id
        ) else {
            return nil
        }

        applyReplayComparisonCommittedText(replay.committedText, language: language)
        return replay.tailText
    }

    private func incomingTailAfterCommittedText(
        _ incoming: String,
        allowsCommittedReplay: Bool
    ) -> String? {
        TranscriptTextProcessor.incomingTailAfterCommittedText(
            incoming,
            committedText: replayComparisonCommittedText(),
            allowsCommittedReplay: allowsCommittedReplay
        )
    }

    private func isRevisionOfCurrentPartial(_ incomingPartial: String) -> Bool {
        TranscriptTextProcessor.isRevisionOfCurrentPartial(
            current: currentPartialText,
            incoming: incomingPartial
        )
    }

    private func preferredPartialText(current: String, incoming: String) -> String {
        TranscriptTextProcessor.preferredPartialText(current: current, incoming: incoming)
    }

    private func isVolatileFragmentSuperseded(by incomingPartial: String) -> Bool {
        TranscriptTextProcessor.isVolatileFragmentSuperseded(
            current: currentPartialText,
            incoming: incomingPartial
        )
    }

    private func isWholeTextPrefix(_ prefix: String, of text: String) -> Bool {
        TranscriptTextProcessor.isWholeTextPrefix(prefix, of: text)
    }

    private func commitCurrentPartial(rolloverContext: CaptionRolloverContext? = nil) {
        let language = currentPartialLanguage ?? sourceLanguage
        let partial = isUsingOpenAIRealtime
            ? currentPartialText.trimmingCharacters(in: .whitespacesAndNewlines)
            : organizeTranscript(currentPartialText, language: language)
        guard !partial.isEmpty else { return }

        var didAppendCommittedPartial = false
        var didReplaceCommittedPartial = false
        if committedSourceText.isEmpty {
            committedSourceText = partial
            didAppendCommittedPartial = true
        } else if replaceCommittedUnitsIfRevision(with: partial, language: language, allowsBackfill: false) {
            // The speech recognizer can resend the last phrase with better wording after
            // cleanup. Treat that as a replacement, not a new line.
            didReplaceCommittedPartial = true
        } else if shouldAppendCommittedPartial(partial) {
            let separator = pendingParagraphBreakBeforePartial ? "\n\n" : "\n"
            committedSourceText += separator + partial
            didAppendCommittedPartial = true
        }
        pendingParagraphBreakBeforePartial = false
        currentPartialText = ""
        currentPartialLanguage = nil

        if didAppendCommittedPartial {
            commitFloatingCurrentPartial()
        } else if didReplaceCommittedPartial {
            syncFloatingCommittedSourceTextToCommittedSourceText(keepsCurrentPartial: false)
        } else {
            discardFloatingCurrentPartial()
        }

        dropAppleRolloverReplayGuardIfNeeded()
        guard let rolloverContext, usesAppleCaptionRollover else { return }
        let units = transcriptUnits(from: committedSourceText)
        let characterLimit = rolloverContext == .longSilence
            ? Self.appleCaptionRolloverSilenceCharacterLimit
            : Self.appleCaptionRolloverCharacterLimit
        guard units.count >= Self.appleCaptionRolloverMinimumUnits,
              committedSourceText.utf16.count >= characterLimit
        else {
            return
        }
        rolloverAppleCaptionLine()
    }

    private func rolloverAppleCaptionLine() {
        appleRolloverReplayGuard = nil
        defer {
            committedSourceText = ""
            pendingParagraphBreakBeforePartial = false
            currentLineID = nil
            floatingCommittedSourceText = ""
            pendingFloatingParagraphBreakBeforePartial = false
        }

        guard let currentLineID,
              let index = lines.firstIndex(where: { $0.id == currentLineID })
        else {
            return
        }

        let existingLine = lines[index]
        let language = sourceLanguageByLineID[currentLineID] ?? sourceLanguage
        let finalizedSourceText = organizeTranscript(
            committedSourceText,
            language: language,
            appliesLint: isTranscriptLintEnabled
        )
        let finalizedLine = CaptionLine(
            id: existingLine.id,
            sourceText: finalizedSourceText,
            translatedText: existingLine.translatedText,
            translatedSourceText: existingLine.translatedSourceText,
            createdAt: existingLine.createdAt,
            isFinal: true,
            revision: existingLine.revision + 1,
            speakerLabel: existingLine.speakerLabel,
            usesLongSessionDisplay: usesLongSessionMode
        )
        lines[index] = finalizedLine
        stageTranscriptForSave(finalizedSourceText)

        if finalizedLine.translatedSourceText != finalizedLine.sourceText {
            pendingTranslationSourceText = ""
            requestTranslation(
                for: finalizedLine,
                source: language,
                target: targetLanguage,
                preservesOrdering: true
            )
        }

        appleRolloverReplayGuard = (
            lineID: finalizedLine.id,
            units: normalizedReplayGuardUnits(
                Array(transcriptUnits(from: finalizedSourceText).suffix(Self.appleRolloverReplayGuardUnitCount))
            )
        )
    }

    private func commitFloatingCurrentPartial() {
        let partial = floatingCurrentPartialText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !partial.isEmpty else { return }

        if floatingCommittedSourceText.isEmpty {
            floatingCommittedSourceText = partial
        } else if shouldAppendCommittedPartial(
            partial,
            to: floatingCommittedSourceText,
            pendingParagraphBreak: pendingFloatingParagraphBreakBeforePartial
        ) {
            let separator = pendingFloatingParagraphBreakBeforePartial ? "\n\n" : "\n"
            floatingCommittedSourceText += separator + partial
        }
        pendingFloatingParagraphBreakBeforePartial = false
        floatingCurrentPartialText = ""
        refreshFloatingCaptionPresentation()
    }

    private func setFloatingCurrentPartialText(_ text: String) {
        floatingCurrentPartialText = text
        refreshFloatingCaptionPresentation()
    }

    private func syncFloatingCommittedSourceTextToCommittedSourceText(keepsCurrentPartial: Bool = true) {
        floatingCommittedSourceText = committedSourceText
        if !keepsCurrentPartial {
            floatingCurrentPartialText = ""
            pendingFloatingParagraphBreakBeforePartial = false
        }
        refreshFloatingCaptionPresentation()
    }

    private func discardFloatingCurrentPartial() {
        floatingCurrentPartialText = ""
        pendingFloatingParagraphBreakBeforePartial = false
        refreshFloatingCaptionPresentation()
    }

    private func rehydrateFloatingCaptionDisplayFromCurrentLine() {
        guard let line = lines.last else {
            floatingCommittedSourceText = ""
            floatingCurrentPartialText = ""
            pendingFloatingParagraphBreakBeforePartial = false
            floatingPresentedSourceText = ""
            floatingQueuedSourceText = ""
            floatingPresentedAt = Date.distantPast
            floatingPresentedUnreadLength = 0
            floatingDisplayTranslationText = ""
            floatingDisplayTranslationSourceText = ""
            floatingQueuedTranslationText = ""
            floatingQueuedTranslationSourceText = ""
            floatingTranslationPresentedAt = Date.distantPast
            floatingTranslationUnreadLength = 0
            return
        }

        floatingCommittedSourceText = line.sourceText
        floatingCurrentPartialText = ""
        pendingFloatingParagraphBreakBeforePartial = false
        floatingPresentedSourceText = isUsingOpenAIRealtime
            ? realtimeFloatingCaptionText(from: line.sourceText)
            : line.sourceText
        floatingQueuedSourceText = ""
        floatingPresentedAt = Date()
        floatingPresentedUnreadLength = normalizedTranscriptForComparison(floatingPresentedSourceText).count

        let translatedText = line.translatedText.trimmingCharacters(in: .whitespacesAndNewlines)
        if translatedText.isEmpty || translatedText == AppText.translating {
            floatingDisplayTranslationText = ""
            floatingDisplayTranslationSourceText = ""
        } else {
            floatingDisplayTranslationText = isUsingOpenAIRealtime
                ? realtimeFloatingCaptionText(from: translatedText)
                : translatedText
            floatingDisplayTranslationSourceText = floatingPresentedSourceText
        }
        floatingQueuedTranslationText = ""
        floatingQueuedTranslationSourceText = ""
        floatingTranslationPresentedAt = Date()
        floatingTranslationUnreadLength = normalizedTranscriptForComparison(floatingDisplayTranslationText).count
    }

    private func refreshFloatingCaptionPresentation() {
        let candidate = floatingVisibleSourceTranscript()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty else { return }

        if floatingPresentedSourceText.isEmpty {
            presentFloatingSourceText(candidate)
            return
        }

        let normalizedCandidate = normalizedTranscriptForComparison(candidate)
        let normalizedPresented = normalizedTranscriptForComparison(floatingPresentedSourceText)
        guard normalizedCandidate != normalizedPresented else { return }

        if isWholeTextPrefix(normalizedPresented, of: normalizedCandidate) {
            // Extensions keep the already-read text in place, so they can render
            // immediately. Keeping the dwell clock running prevents a stream of
            // extensions from postponing queued replacements forever.
            presentFloatingSourceText(candidate, resetsDwell: false)
            return
        }

        let now = Date()
        if canUpdateFloatingPresentationImmediately(now: now)
            || canAdvanceFloatingPresentation(now: now) {
            presentFloatingSourceText(candidate)
            return
        }

        floatingQueuedSourceText = candidate
        scheduleFloatingPresentationAdvance()
    }

    private var floatingStabilityProfile: FloatingCaptionStabilityProfile {
        floatingCaptionStability.profile
    }

    private func canUpdateFloatingPresentationImmediately(now: Date) -> Bool {
        now.timeIntervalSince(floatingPresentedAt) <= floatingStabilityProfile.earlyRevisionWindow
    }

    private func canAdvanceFloatingPresentation(now: Date = Date()) -> Bool {
        guard !floatingPresentedSourceText.isEmpty else { return true }
        return now.timeIntervalSince(floatingPresentedAt) >= floatingCaptionDwellDuration()
    }

    private func floatingCaptionDwellDuration() -> TimeInterval {
        floatingStabilityProfile.dwell(forUnreadLength: floatingPresentedUnreadLength)
    }

    private func canAdvanceFloatingTranslation(now: Date = Date()) -> Bool {
        guard !floatingDisplayTranslationText.isEmpty else { return true }
        return now.timeIntervalSince(floatingTranslationPresentedAt) >= floatingTranslationDwellDuration()
    }

    private func floatingTranslationDwellDuration() -> TimeInterval {
        floatingStabilityProfile.dwell(forUnreadLength: floatingTranslationUnreadLength)
    }

    /// The displayed translation belongs to a source that has since been replaced.
    private var isFloatingTranslationDisplayStale: Bool {
        guard !floatingDisplayTranslationText.isEmpty,
              !floatingDisplayTranslationSourceText.isEmpty
        else {
            return false
        }
        return !translationSource(floatingDisplayTranslationSourceText, matches: floatingPresentedSourceText)
    }

    func presentFloatingSourceText(_ text: String, resetsDwell: Bool = true) {
        if PipelineDiagnostics.isEnabled {
            PipelineDiagnostics.record("floating.source", values: ["characters": Double(text.count)])
        }
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        let normalizedText = normalizedTranscriptForComparison(text)
        let normalizedPresented = normalizedTranscriptForComparison(floatingPresentedSourceText)
        let unreadLength = max(0, normalizedText.count - commonPrefixLength(normalizedPresented, normalizedText))
        floatingPresentedSourceText = text
        floatingQueuedSourceText = ""
        if resetsDwell {
            floatingPresentedAt = Date()
            floatingPresentedUnreadLength = unreadLength
        } else {
            floatingPresentedUnreadLength += unreadLength
        }
        promoteQueuedFloatingTranslationIfPossible()
        if isFloatingTranslationDisplayStale {
            scheduleFloatingTranslationHoldExpiry()
        }
    }

    private func scheduleFloatingPresentationAdvance() {
        floatingPresentationTask?.cancel()

        let now = Date()
        var remaining = TimeInterval.greatestFiniteMagnitude
        if !floatingQueuedSourceText.isEmpty {
            remaining = min(remaining, floatingCaptionDwellDuration() - now.timeIntervalSince(floatingPresentedAt))
        }
        if !floatingQueuedTranslationText.isEmpty {
            remaining = min(
                remaining,
                floatingTranslationDwellDuration() - now.timeIntervalSince(floatingTranslationPresentedAt)
            )
        }
        if remaining == .greatestFiniteMagnitude {
            remaining = 0.05
        }
        let delayMilliseconds = max(50, Int(max(0.05, remaining) * 1_000))
        floatingPresentationTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(delayMilliseconds))
            guard !Task.isCancelled else { return }
            promoteQueuedFloatingPresentationIfReady()
        }
    }

    private func promoteQueuedFloatingPresentationIfReady() {
        if !floatingQueuedSourceText.isEmpty, canAdvanceFloatingPresentation() {
            presentFloatingSourceText(floatingQueuedSourceText)
        }
        if !floatingQueuedTranslationText.isEmpty {
            promoteQueuedFloatingTranslationIfPossible()
        }

        if !floatingQueuedSourceText.isEmpty || !floatingQueuedTranslationText.isEmpty {
            scheduleFloatingPresentationAdvance()
        } else {
            floatingPresentationTask = nil
        }
    }

    private func scheduleFloatingTranslationHoldExpiry() {
        guard floatingTranslationHoldTask == nil else { return }

        let timeout = floatingStabilityProfile.translationHoldTimeout
        // MainActor 작업 시작 지연이 자막 유지 시간을 늘리지 않도록 요청 시점에 고정한다.
        let deadline = ContinuousClock.now.advanced(by: .seconds(timeout))
        floatingTranslationHoldTask = Task { @MainActor in
            try? await Task.sleep(until: deadline, clock: .continuous)
            guard !Task.isCancelled else { return }
            floatingTranslationHoldTask = nil
            guard isFloatingTranslationDisplayStale else { return }
            floatingDisplayTranslationText = ""
            floatingDisplayTranslationSourceText = ""
        }
    }

    private func replaceCommittedUnitsIfRevision(
        with text: String,
        language: LanguageOption,
        allowsBackfill: Bool
    ) -> Bool {
        guard let updatedText = TranscriptTextProcessor.committedTextByReplacingRevision(
            with: text,
            committedText: replayComparisonCommittedText(),
            languageID: language.id,
            allowsBackfill: allowsBackfill
        ) else {
            return false
        }

        applyReplayComparisonCommittedText(updatedText, language: language)
        return true
    }

    private func replayComparisonCommittedText() -> String {
        guard let appleRolloverReplayGuard else {
            return committedSourceText
        }

        return transcriptText(
            from: appleRolloverReplayGuard.units + transcriptUnits(from: committedSourceText)
        )
    }

    private func applyReplayComparisonCommittedText(_ text: String, language: LanguageOption) {
        guard let replayGuard = appleRolloverReplayGuard else {
            committedSourceText = text
            return
        }

        let units = transcriptUnits(from: text)
        let guardUnitCount = min(replayGuard.units.count, units.count)
        let updatedGuardUnits = normalizedReplayGuardUnits(Array(units.prefix(guardUnitCount)))
        let remainingUnits = Array(units.dropFirst(guardUnitCount))
        committedSourceText = transcriptText(from: remainingUnits)

        if updatedGuardUnits != replayGuard.units,
           let index = lines.firstIndex(where: { $0.id == replayGuard.lineID }) {
            let line = lines[index]
            var lineUnits = transcriptUnits(from: line.sourceText)
            let replacedUnitCount = min(replayGuard.units.count, lineUnits.count)
            let suffixStartIndex = lineUnits.count - replacedUnitCount
            let originalSeparator = lineUnits[suffixStartIndex].separatorBefore
            lineUnits.removeLast(replacedUnitCount)

            var replacementUnits = updatedGuardUnits
            if !replacementUnits.isEmpty {
                replacementUnits[0].separatorBefore = lineUnits.isEmpty ? "" : originalSeparator
            }
            lineUnits.append(contentsOf: replacementUnits)
            let updatedSourceText = transcriptText(from: lineUnits)

            if updatedSourceText != line.sourceText {
                let updatedLine = CaptionLine(
                    id: line.id,
                    sourceText: updatedSourceText,
                    translatedText: line.translatedText,
                    translatedSourceText: line.translatedSourceText,
                    createdAt: line.createdAt,
                    isFinal: true,
                    revision: line.revision + 1,
                    speakerLabel: line.speakerLabel,
                    usesLongSessionDisplay: usesLongSessionMode
                )
                lines[index] = updatedLine
                stageTranscriptForSave(updatedSourceText)
                pendingTranslationSourceText = ""
                requestTranslation(
                    for: updatedLine,
                    source: sourceLanguageByLineID[line.id] ?? language,
                    target: targetLanguage,
                    preservesOrdering: true
                )
            }
        }

        appleRolloverReplayGuard = (
            lineID: replayGuard.lineID,
            units: updatedGuardUnits
        )
        dropAppleRolloverReplayGuardIfNeeded()
    }

    private func normalizedReplayGuardUnits(_ units: [TranscriptUnit]) -> [TranscriptUnit] {
        guard !units.isEmpty else { return units }

        var normalizedUnits = units
        normalizedUnits[0].separatorBefore = ""
        return normalizedUnits
    }

    private func dropAppleRolloverReplayGuardIfNeeded() {
        guard transcriptUnits(from: committedSourceText).count >= 4 else { return }
        appleRolloverReplayGuard = nil
    }

    private func shouldAppendCommittedPartial(_ partial: String) -> Bool {
        shouldAppendCommittedPartial(
            partial,
            to: committedSourceText,
            pendingParagraphBreak: pendingParagraphBreakBeforePartial
        )
    }

    private func shouldAppendCommittedPartial(
        _ partial: String,
        to committedText: String,
        pendingParagraphBreak: Bool
    ) -> Bool {
        TranscriptTextProcessor.shouldAppendCommittedPartial(
            partial,
            to: committedText,
            pendingParagraphBreak: pendingParagraphBreak
        )
    }

    private func transcriptUnits(from text: String) -> [TranscriptUnit] {
        TranscriptTextProcessor.transcriptUnits(from: text)
    }

    private func transcriptText(from units: [TranscriptUnit]) -> String {
        TranscriptTextProcessor.transcriptText(from: units)
    }

    private func realtimeFloatingCaptionText(from text: String) -> String {
        let units = transcriptUnits(from: text)
        guard let latestUnit = units.last else {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return latestUnit.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizedTranscriptForComparison(_ text: String) -> String {
        TranscriptTextProcessor.normalizedForComparison(text)
    }

    private func visibleTranscript() -> String {
        let committed = committedSourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        let partial = currentPartialText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !committed.isEmpty else {
            return partial
        }
        guard !partial.isEmpty else {
            return committed
        }

        let separator = pendingParagraphBreakBeforePartial ? "\n\n" : "\n"
        return committed + separator + partial
    }

    private func floatingVisibleSourceTranscript() -> String {
        let committed = floatingCommittedSourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        let partial = floatingCurrentPartialText.trimmingCharacters(in: .whitespacesAndNewlines)

        if isUsingOpenAIRealtime {
            if !partial.isEmpty {
                return realtimeFloatingCaptionText(from: partial)
            }
            return realtimeFloatingCaptionText(from: committed)
        }

        guard !committed.isEmpty else {
            return partial
        }
        guard !partial.isEmpty else {
            return committed
        }

        let separator = pendingFloatingParagraphBreakBeforePartial ? "\n\n" : "\n"
        return committed + separator + partial
    }

    private func scheduleTranscriptCleanup() {
        guard isRunning, currentLineID != nil else { return }
        guard !isUsingOpenAIRealtime else { return }
        guard Date().timeIntervalSince(lastRecognitionAt) > 1.5 else { return }

        if let pendingCleanup = transcriptCleanupTask, !pendingCleanup.isCancelled {
            return
        }
        transcriptCleanupTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            transcriptCleanupTask = nil
            organizeCurrentTranscript()
        }
    }

    private func organizeCurrentTranscript(sourceTextOverride: String? = nil) {
        guard !isUsingQwenTranslation, !isUsingOpenAIRealtime else { return }

        if sourceTextOverride == nil {
            flushPendingCaptionPresentation()
        }

        guard isRunning,
              let currentLineID,
              let index = lines.firstIndex(where: { $0.id == currentLineID })
        else {
            return
        }

        let line = lines[index]
        let sourceText = sourceTextOverride ?? line.sourceText
        let sourceLanguage = sourceLanguageByLineID[line.id] ?? self.sourceLanguage
        let organizedSourceText = organizeTranscript(
            sourceText,
            language: sourceLanguage,
            appliesLint: isTranscriptLintEnabled
        )
        let organizedTranslatedText = organizeTranslatedText(line.translatedText)
        let sourceChanged = organizedSourceText != line.sourceText
        let translationChanged = organizedTranslatedText != line.translatedText
        let needsTranslationRefresh = line.translatedSourceText != organizedSourceText

        if !sourceChanged,
           !translationChanged,
           needsTranslationRefresh,
           pendingTranslationSourceText == organizedSourceText {
            return
        }

        guard sourceChanged || translationChanged || needsTranslationRefresh else {
            return
        }

        committedSourceText = organizedSourceText
        currentPartialText = ""
        lines[index] = CaptionLine(
            id: line.id,
            sourceText: organizedSourceText,
            translatedText: organizedTranslatedText,
            translatedSourceText: line.translatedSourceText,
            createdAt: line.createdAt,
            isFinal: line.isFinal,
            revision: line.revision + 1,
            usesLongSessionDisplay: usesLongSessionMode
        )

        // Keep floating captions stable while cleanup rewrites the saved transcript.
        let updatedLine = lines[index]
        sourceLanguageByLineID[updatedLine.id] = sourceLanguage
        stageTranscriptForSave(updatedLine.sourceText)
        if updatedLine.translatedSourceText != updatedLine.sourceText {
            requestTranslation(for: updatedLine, source: sourceLanguage, target: targetLanguage)
        }
    }

    private func organizeTranslatedText(_ text: String) -> String {
        guard text != AppText.translating else { return text }
        return organizeTranscript(text, language: targetLanguage)
    }

    private func organizeTranscript(_ text: String, language: LanguageOption) -> String {
        organizeTranscript(text, language: language, appliesLint: false)
    }

    private func organizeTranscript(
        _ text: String,
        language: LanguageOption,
        appliesLint: Bool
    ) -> String {
        if !appliesLint {
            return TranscriptTextProcessor.organizeTranscript(text, languageID: language.id)
        }

        return paragraphParts(from: text)
            .map {
                let organized = organizeParagraph($0, language: language)
                return lintParagraph(organized, language: language)
            }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }

    private func organizeParagraph(_ text: String, language: LanguageOption) -> String {
        TranscriptTextProcessor.organizeParagraph(text, languageID: language.id)
    }

    private func lintParagraph(_ text: String, language: LanguageOption) -> String {
        text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { lintLine(String($0), language: language) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    private func lintLine(_ text: String, language: LanguageOption) -> String {
        var linted = text
            .replacingOccurrences(of: #"(^|[\s,，])[,，]{1,}(\s*[,，]+)*"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+([,.!?。！？])"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"([,.!?])(?=\S)"#, with: "$1 ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        linted = correctUnknownWords(in: linted, language: language)

        if language.id == "en-US" {
            linted = capitalizeSentenceStarts(linted)
        }

        return linted.trimmingCharacters(in: CharacterSet(charactersIn: " ,，"))
    }

    private func correctUnknownWords(in text: String, language: LanguageOption) -> String {
        guard let spellLanguage = spellCheckerLanguage(for: language) else { return text }

        var corrected = text
        var searchLocation = 0

        while searchLocation < (corrected as NSString).length {
            var wordCount = 0
            let misspelledRange = spellChecker.checkSpelling(
                of: corrected,
                startingAt: searchLocation,
                language: spellLanguage,
                wrap: false,
                inSpellDocumentWithTag: spellDocumentTag,
                wordCount: &wordCount
            )
            guard misspelledRange.location != NSNotFound, misspelledRange.length > 0 else { break }

            let textValue = corrected as NSString
            let word = textValue.substring(with: misspelledRange)
            if let replacement = safeSpellingReplacement(
                for: word,
                in: corrected,
                range: misspelledRange,
                language: spellLanguage
            ) {
                corrected = textValue.replacingCharacters(in: misspelledRange, with: replacement)
                searchLocation = misspelledRange.location + (replacement as NSString).length
            } else {
                searchLocation = misspelledRange.location + misspelledRange.length
            }
        }

        return corrected
    }

    private func spellCheckerLanguage(for language: LanguageOption) -> String? {
        let availableLanguages = spellChecker.availableLanguages
        let normalizedID = language.id.replacingOccurrences(of: "-", with: "_")
        if availableLanguages.contains(language.id) {
            return language.id
        }
        if availableLanguages.contains(normalizedID) {
            return normalizedID
        }
        if let baseID = language.id.split(separator: "-").first.map(String.init),
           availableLanguages.contains(baseID) {
            return baseID
        }
        return nil
    }

    private func safeSpellingReplacement(
        for word: String,
        in text: String,
        range: NSRange,
        language: String
    ) -> String? {
        guard shouldCorrectSpelledWord(word, language: language),
              let guesses = spellChecker.guesses(
                  forWordRange: range,
                  in: text,
                  language: language,
                  inSpellDocumentWithTag: spellDocumentTag
              ),
              let replacement = guesses.first?.trimmingCharacters(in: .whitespacesAndNewlines),
              isConservativeReplacement(original: word, replacement: replacement)
        else {
            return nil
        }

        return replacement
    }

    private func shouldCorrectSpelledWord(_ word: String, language: String) -> Bool {
        let trimmed = word.trimmingCharacters(in: .punctuationCharacters)
        guard trimmed.count > 1 else { return false }
        guard trimmed.rangeOfCharacter(from: .decimalDigits) == nil else { return false }
        guard trimmed.range(of: #"[/\\@#_]"#, options: .regularExpression) == nil else { return false }

        if language.hasPrefix("en"),
           let first = trimmed.first,
           first.isUppercase {
            return false
        }

        return true
    }

    private func isConservativeReplacement(original: String, replacement: String) -> Bool {
        guard !replacement.isEmpty, !replacement.contains("\n") else { return false }
        let originalLength = max((original as NSString).length, 1)
        let replacementLength = (replacement as NSString).length
        guard replacementLength <= originalLength + 4 else { return false }
        guard replacementLength * 3 >= originalLength else { return false }
        return true
    }

    private func capitalizeSentenceStarts(_ text: String) -> String {
        var result = ""
        var shouldCapitalize = true

        for character in text {
            if shouldCapitalize, character.isLetter {
                result.append(String(character).uppercased())
                shouldCapitalize = false
                continue
            }

            result.append(character)
            if ".!?".contains(character) {
                shouldCapitalize = true
            } else if !character.isWhitespace {
                shouldCapitalize = false
            }
        }

        return result
    }

    private func paragraphParts(from text: String) -> [String] {
        TranscriptTextProcessor.paragraphParts(from: text)
    }

    private func translateTranscript(
        _ text: String,
        source: LanguageOption,
        target: LanguageOption,
        progress: @escaping @MainActor @Sendable (String) -> Void = { _ in }
    ) async throws -> String {
#if DEBUG
        if isUsingGrokSTT, let grokTranslationForTesting {
            return try await grokTranslationForTesting(text)
        }
        if isUsingNariSTT, let nariTranslationForTesting {
            return try await nariTranslationForTesting(text)
        }
#endif
        let paragraphSegments = try await Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            return Self.translationSegmentGroups(from: text)
        }.value

        guard !paragraphSegments.isEmpty else { return "" }

        var translatedParagraphs: [String] = []
        var consecutiveCacheHitCount = 0
        for segments in paragraphSegments {
            var translatedSegments: [String] = []

            for segment in segments {
                try Task.checkCancellation()
                let cacheKey = translationCacheKey(segment: segment, source: source, target: target)
                if let cachedSegment = translationSegmentCache.value(forKey: cacheKey) {
                    consecutiveCacheHitCount += 1
                    if consecutiveCacheHitCount.isMultiple(of: Self.translationCacheHitYieldInterval) {
                        await Task.yield()
                        try Task.checkCancellation()
                    }
                    translatedSegments.append(cachedSegment)
                    continue
                }
                consecutiveCacheHitCount = 0

                let translatedSegment: String
                if openAITranslationModel.isEnabled && !openAITranslationModel.usesRealtimeAudioTranslation {
                    let completedParagraphs = translatedParagraphs
                    let completedSegments = translatedSegments
                    translatedSegment = try await openAITranslator.translate(
                        segment,
                        source: source,
                        target: target,
                        model: openAITranslationModel,
                        progress: { partialSegment in
                            let partialText = (completedParagraphs + [(completedSegments + [partialSegment]).joined(separator: "\n")])
                                .joined(separator: "\n\n")
                                .trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !partialText.isEmpty else { return }
                            progress(partialText)
                        }
                    )
                } else {
                    translatedSegment = try await translator.translate(
                        segment,
                        source: source,
                        target: target,
                        model: selectedModel
                    )
                }
                try Task.checkCancellation()
                let organizedSegment = organizeTranscript(translatedSegment, language: target)
                cacheTranslatedSegment(organizedSegment, forKey: cacheKey)
                translatedSegments.append(organizedSegment)

                let partialText = (translatedParagraphs + [translatedSegments.joined(separator: "\n")])
                    .joined(separator: "\n\n")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !partialText.isEmpty {
                    progress(partialText)
                }
            }

            translatedParagraphs.append(translatedSegments.joined(separator: "\n"))
        }

        return translatedParagraphs.joined(separator: "\n\n")
    }

    nonisolated private static func translationSegmentGroups(from text: String) -> [[String]] {
        TranscriptTextProcessor.paragraphParts(from: text)
            .map { translationSegments(from: $0) }
            .filter { !$0.isEmpty }
    }

    nonisolated private static func translationSegments(from paragraph: String) -> [String] {
        paragraph
            .split(separator: "\n", omittingEmptySubsequences: true)
            .flatMap { splitTranslationSegment(String($0)) }
    }

    nonisolated private static func splitTranslationSegment(_ text: String) -> [String] {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return [] }
        guard trimmedText.utf16.count > 240 else { return [trimmedText] }

        var segments: [String] = []
        var current = ""

        for character in trimmedText {
            current.append(character)
            let shouldBreakAtSentence = ".!?。！？".contains(character)
                && current.utf16.count >= 80
            let shouldBreakAtWhitespace = character.isWhitespace
                && current.utf16.count >= 240

            if shouldBreakAtSentence || shouldBreakAtWhitespace {
                let segment = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !segment.isEmpty {
                    segments.append(segment)
                }
                current = ""
            }
        }

        let tail = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty {
            segments.append(tail)
        }
        return segments
    }

    private func translationCacheKey(segment: String, source: LanguageOption, target: LanguageOption) -> String {
        "\(source.id)\t\(target.id)\t\(translationEngineCacheID)\t\(segment)"
    }

    private var translationEngineCacheID: String {
        if openAITranslationModel.isEnabled {
            return "openai:\(openAITranslationModel.id)"
        }
        return "apple:\(selectedModel.id)"
    }

    private func cacheTranslatedSegment(_ segment: String, forKey key: String) {
        translationSegmentCache.insert(segment, forKey: key)
    }

    private func resetTranslationCache() {
        translationSegmentCache.removeAll()
    }

    private func updateRealtimeTranslationSourceTranscript(_ text: String) {
        guard isRunning, !isPaused else { return }
        guard isUsingOpenAIRealtimeTranslation else { return }

        guard text.rangeOfCharacter(from: .whitespacesAndNewlines.inverted) != nil
            || !realtimeTranslationSourceText.isEmpty else { return }

        realtimeTranslationSourceText = accumulatedRealtimeText(
            current: realtimeTranslationSourceText,
            next: text
        )
        refreshOpenAIRealtimeTranslationLine()
    }

    private func appendRealtimeTranslationOnly(_ text: String) {
        guard isRunning, !isPaused else { return }
        guard isUsingOpenAIRealtimeTranslation else { return }

        guard text.rangeOfCharacter(from: .whitespacesAndNewlines.inverted) != nil
            || !realtimeTranslationOnlyText.isEmpty else { return }

        realtimeTranslationOnlyText = accumulatedRealtimeText(
            current: realtimeTranslationOnlyText,
            next: text
        )
        refreshOpenAIRealtimeTranslationLine()
    }

    private func refreshOpenAIRealtimeTranslationLine() {
        let inputText = realtimeTranslationSourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        let translatedText = realtimeTranslationOnlyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !inputText.isEmpty || !translatedText.isEmpty else { return }

        lastRecognizedText = inputText.isEmpty ? translatedText : inputText
        lastRecognitionAt = Date()
        transcriptCleanupTask?.cancel()

        let sourceText = inputText.isEmpty ? AppText.openAIRealtimeTranslationOnlySource : inputText
        let visibleTranslatedText = translatedText.isEmpty ? AppText.translating : translatedText

        if let currentLineID,
           let index = lines.firstIndex(where: { $0.id == currentLineID }) {
            let existingLine = lines[index]
            lines[index] = CaptionLine(
                id: existingLine.id,
                sourceText: sourceText,
                translatedText: visibleTranslatedText,
                translatedSourceText: sourceText,
                createdAt: existingLine.createdAt,
                isFinal: false,
                revision: existingLine.revision + 1,
                usesLongSessionDisplay: usesLongSessionMode
            )
        } else {
            let line = CaptionLine(
                sourceText: sourceText,
                translatedText: visibleTranslatedText,
                translatedSourceText: sourceText,
                createdAt: Date(),
                isFinal: false,
                revision: 1,
                usesLongSessionDisplay: usesLongSessionMode
            )
            currentLineID = line.id
            lines.append(line)
        }

        if !inputText.isEmpty {
            presentFloatingSourceText(inputText)
        }
        if !translatedText.isEmpty {
            stageTranscriptForSave(sourceText, translatedText: translatedText)
            updateFloatingTranslationPresentation(translatedText, sourceText: sourceText)
            speakTranslatedDeltaIfNeeded(translatedText)
        }
    }

    private func updateGeminiLiveInputTranscript(_ text: String) {
        guard isRunning, !isPaused else { return }
        guard isUsingGeminiTranslation else { return }
        guard text.rangeOfCharacter(from: .whitespacesAndNewlines.inverted) != nil
            || !geminiLiveInputTranscriptText.isEmpty else { return }

        geminiLiveInputTranscriptText = accumulatedRealtimeText(
            current: geminiLiveInputTranscriptText,
            next: text
        )
        refreshGeminiLiveCaptionLine()
    }

    private func updateGeminiLiveOutputTranscript(_ text: String) {
        guard isRunning, !isPaused else { return }
        guard isUsingGeminiTranslation else { return }
        guard text.rangeOfCharacter(from: .whitespacesAndNewlines.inverted) != nil
            || !geminiLiveOutputTranscriptText.isEmpty else { return }

        geminiLiveOutputTranscriptText = accumulatedRealtimeText(
            current: geminiLiveOutputTranscriptText,
            next: text
        )
        refreshGeminiLiveCaptionLine()
    }

    func updateGeminiLiveTranscription(_ text: String, isFinal: Bool) {
        guard isRunning, !isPaused, isUsingGeminiTranscriptionMode else { return }

        let sourceText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sourceText.isEmpty else { return }

        lastRecognizedText = sourceText
        lastRecognizedWasFinal = isFinal
        lastRecognitionAt = Date()
        transcriptCleanupTask?.cancel()

        if let currentLineID,
           let index = lines.firstIndex(where: { $0.id == currentLineID }) {
            let existingLine = lines[index]
            lines[index] = CaptionLine(
                id: existingLine.id,
                sourceText: sourceText,
                translatedText: "",
                createdAt: existingLine.createdAt,
                isFinal: isFinal,
                revision: existingLine.revision + 1,
                usesLongSessionDisplay: usesLongSessionMode
            )
            sourceLanguageByLineID[existingLine.id] = sourceLanguage
        } else {
            let line = CaptionLine(
                sourceText: sourceText,
                translatedText: "",
                createdAt: Date(),
                isFinal: isFinal,
                revision: 1,
                usesLongSessionDisplay: usesLongSessionMode
            )
            currentLineID = line.id
            sourceLanguageByLineID[line.id] = sourceLanguage
            lines.append(line)
        }

        stageTranscriptForSave(sourceText)
        presentFloatingSourceText(sourceText)

        if isFinal {
            currentLineID = nil
            geminiLiveInputTranscriptText = ""
        }
    }

    private func startMetaTurn(_ turnId: Int32) {
        guard isRunning, !isPaused, isUsingMetaScribe else { return }
        metaActiveTurnID = turnId
    }

    private func updateMetaPartialTranscript(_ text: String) {
        guard isRunning, !isPaused, isUsingMetaScribe, let turnId = metaActiveTurnID else { return }
        let sourceText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sourceText.isEmpty else { return }

        lastRecognizedText = sourceText
        lastRecognizedWasFinal = false
        lastRecognitionAt = Date()
        transcriptCleanupTask?.cancel()
        let speakerLabel = metaTurnSpeakerLabels[turnId]

        if let lineID = metaTurnLineIDs[turnId],
           let index = lines.firstIndex(where: { $0.id == lineID }) {
            let existingLine = lines[index]
            lines[index] = CaptionLine(
                id: existingLine.id,
                sourceText: sourceText,
                translatedText: existingLine.translatedText,
                translatedSourceText: existingLine.translatedSourceText,
                createdAt: existingLine.createdAt,
                isFinal: false,
                revision: existingLine.revision + 1,
                speakerLabel: speakerLabel,
                usesLongSessionDisplay: usesLongSessionMode
            )
        } else {
            let line = CaptionLine(
                sourceText: sourceText,
                translatedText: AppText.translating,
                createdAt: Date(),
                isFinal: false,
                revision: 1,
                speakerLabel: speakerLabel,
                usesLongSessionDisplay: usesLongSessionMode
            )
            metaTurnLineIDs[turnId] = line.id
            sourceLanguageByLineID[line.id] = sourceLanguage
            lines.append(line)
        }
        presentFloatingSourceText(sourceText)
    }

    private func labelMetaSpeaker(_ label: String) {
        guard isRunning, !isPaused, isUsingMetaScribe, let turnId = metaActiveTurnID else { return }
        metaTurnSpeakerLabels[turnId] = label
        guard let lineID = metaTurnLineIDs[turnId],
              let index = lines.firstIndex(where: { $0.id == lineID })
        else {
            return
        }
        let line = lines[index]
        lines[index] = CaptionLine(
            id: line.id,
            sourceText: line.sourceText,
            translatedText: line.translatedText,
            translatedSourceText: line.translatedSourceText,
            createdAt: line.createdAt,
            isFinal: line.isFinal,
            revision: line.revision + 1,
            speakerLabel: label,
            usesLongSessionDisplay: usesLongSessionMode
        )
    }

    private func receiveNariTranscript(_ update: NariTranscriptUpdate, service: NariRealtimeTranscriber?, generation: UInt64) {
        guard let service, service === nariTranscriber,
              pipelineLifecycle.acceptsSample(generation: generation), isRunning, isUsingNariSTT,
              !nariFinalizedItemIDs.contains(update.itemID) else { return }
        let text = update.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let detectedLanguage = update.languageCode.flatMap { code in
            LanguageOption.supported.first { NariTranscriptionModel.languageCode(for: $0) == code }
        }
        let language = detectedLanguage ?? sourceLanguage
        let unknownDetectedLanguage = isNariSourceAutoDetectionEnabled && update.isFinal && detectedLanguage == nil
        let existingIndex = nariTurnLineIDs[update.itemID].flatMap { id in lines.firstIndex { $0.id == id } }
        if nariTurnLineIDs[update.itemID] == nil && !nariItemOrder.contains(update.itemID) {
            nariItemOrder.append(update.itemID)
        }
        if update.isFinal { nariFinalizedItemIDs.insert(update.itemID) }

        // 오래된 완료 ID만 비워 늦은 중복과 현재 진행 중 발화를 구분한다.
        while nariItemOrder.count > 256,
              let oldest = nariItemOrder.first, nariFinalizedItemIDs.contains(oldest) {
            nariItemOrder.removeFirst()
            nariFinalizedItemIDs.remove(oldest)
            nariTurnLineIDs.removeValue(forKey: oldest)
        }
        if text.isEmpty {
            if let index = existingIndex {
                let removed = lines.remove(at: index)
                sourceLanguageByLineID.removeValue(forKey: removed.id)
                nariTurnLineIDs.removeValue(forKey: update.itemID)
                rehydrateFloatingCaptionDisplayFromCurrentLine()
            }
            return
        }
        let previous = existingIndex.map { lines[$0] }
        let line = CaptionLine(
            id: previous?.id ?? UUID(), sourceText: text,
            translatedText: isTranscribeOnlyMode ? "" : (unknownDetectedLanguage ? NariCopy.translationLanguageUnavailable : AppText.translating),
            createdAt: previous?.createdAt ?? Date(), isFinal: update.isFinal,
            revision: (previous?.revision ?? 0) + 1, usesLongSessionDisplay: usesLongSessionMode
        )
        if let index = existingIndex { lines[index] = line } else { lines.append(line) }
        nariTurnLineIDs[update.itemID] = line.id
        sourceLanguageByLineID[line.id] = language
        lastRecognizedText = text
        lastRecognizedWasFinal = update.isFinal
        lastRecognitionAt = Date()
        presentFloatingSourceText(text)
        if update.isFinal {
            nariSavedTranscriptText = nariSavedTranscriptText.isEmpty ? text : nariSavedTranscriptText + "\n" + text
            stageTranscriptForSave(nariSavedTranscriptText)
            if !isTranscribeOnlyMode, !unknownDetectedLanguage {
                requestTranslation(for: line, source: language, target: targetLanguage, preservesOrdering: true)
            }
        }
    }

    private func receiveGrokTranscript(_ update: GrokTranscriptUpdate, service: GrokRealtimeTranscriber?, generation: UInt64) {
        guard let service, service === grokTranscriber,
              pipelineLifecycle.acceptsSample(generation: generation), isRunning, isUsingGrokSTT,
              !grokFinalizedItemIDs.contains(update.itemID) else { return }
        let text = update.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let detectedLanguage = update.languageCode.flatMap { code in
            LanguageOption.supported.first { GrokTranscriptionModel.languageCode(for: $0) == code }
        }
        let language = detectedLanguage ?? sourceLanguage
        let unknownDetectedLanguage = isGrokSourceAutoDetectionEnabled && update.isFinal && detectedLanguage == nil
        let existingIndex = grokTurnLineIDs[update.itemID].flatMap { id in lines.firstIndex { $0.id == id } }
        if grokTurnLineIDs[update.itemID] == nil && !grokItemOrder.contains(update.itemID) {
            grokItemOrder.append(update.itemID)
        }
        if update.isFinal { grokFinalizedItemIDs.insert(update.itemID) }

        // 오래된 완료 ID만 비워 늦은 중복과 현재 진행 중 발화를 구분한다.
        while grokItemOrder.count > 256,
              let oldest = grokItemOrder.first, grokFinalizedItemIDs.contains(oldest) {
            grokItemOrder.removeFirst()
            grokFinalizedItemIDs.remove(oldest)
            grokTurnLineIDs.removeValue(forKey: oldest)
        }
        if text.isEmpty {
            if let index = existingIndex {
                let removed = lines.remove(at: index)
                sourceLanguageByLineID.removeValue(forKey: removed.id)
                grokTurnLineIDs.removeValue(forKey: update.itemID)
                rehydrateFloatingCaptionDisplayFromCurrentLine()
            }
            return
        }
        let previous = existingIndex.map { lines[$0] }
        let line = CaptionLine(
            id: previous?.id ?? UUID(), sourceText: text,
            translatedText: isTranscribeOnlyMode ? "" : (unknownDetectedLanguage ? GrokCopy.translationLanguageUnavailable : AppText.translating),
            createdAt: previous?.createdAt ?? Date(), isFinal: update.isFinal,
            revision: (previous?.revision ?? 0) + 1, usesLongSessionDisplay: usesLongSessionMode
        )
        if let index = existingIndex { lines[index] = line } else { lines.append(line) }
        grokTurnLineIDs[update.itemID] = line.id
        sourceLanguageByLineID[line.id] = isGrokSourceAutoDetectionEnabled ? detectedLanguage : language
        lastRecognizedText = text
        lastRecognizedWasFinal = update.isFinal
        lastRecognitionAt = Date()
        presentFloatingSourceText(text)
        if update.isFinal {
            grokSavedTranscriptText = grokSavedTranscriptText.isEmpty ? text : grokSavedTranscriptText + "\n" + text
            stageTranscriptForSave(grokSavedTranscriptText)
            if !isTranscribeOnlyMode, !unknownDetectedLanguage {
                requestTranslation(for: line, source: language, target: targetLanguage, preservesOrdering: true)
            }
        }
    }

    private func receiveAzureMAI(_ result: Result<String, AzureMAIError>, service: AzureMAITranscriber?, generation: UInt64) {
        guard let service, service === azureMAITranscriber,
              pipelineLifecycle.acceptsSample(generation: generation), isRunning, isUsingAzureMAI else { return }
        switch result {
        case .failure(let error):
            azureFinishTask?.cancel()
            isFinishingAzureMAI = false
            pipelineLifecycle.stop()
            finishPipeline(statusOverride: error.localizedDescription)
        case .success(let text):
            let line = CaptionLine(sourceText: text, translatedText: AppText.translating,
                                   createdAt: Date(), isFinal: true, revision: 1,
                                   usesLongSessionDisplay: usesLongSessionMode)
            lines.append(line)
            sourceLanguageByLineID[line.id] = sourceLanguage
            lastRecognizedText = text
            lastRecognizedWasFinal = true
            lastRecognitionAt = Date()
            presentFloatingSourceText(text)
            azureSavedTranscriptText = azureSavedTranscriptText.isEmpty ? text : azureSavedTranscriptText + "\n" + text
            stageTranscriptForSave(azureSavedTranscriptText)
            requestTranslation(for: line, source: sourceLanguage, target: targetLanguage)
        }
    }

    private func completeMetaTurn(_ turnId: Int32, transcript: String) {
        guard isRunning, !isPaused, isUsingMetaScribe else { return }
        let sourceText = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sourceText.isEmpty else { return }
        let speakerLabel = metaTurnSpeakerLabels[turnId]
        let line: CaptionLine
        if let lineID = metaTurnLineIDs[turnId],
           let index = lines.firstIndex(where: { $0.id == lineID }) {
            let existingLine = lines[index]
            line = CaptionLine(
                id: existingLine.id,
                sourceText: sourceText,
                translatedText: AppText.translating,
                createdAt: existingLine.createdAt,
                isFinal: true,
                revision: existingLine.revision + 1,
                speakerLabel: speakerLabel,
                usesLongSessionDisplay: usesLongSessionMode
            )
            lines[index] = line
        } else {
            line = CaptionLine(
                sourceText: sourceText,
                translatedText: AppText.translating,
                createdAt: Date(),
                isFinal: true,
                revision: 1,
                speakerLabel: speakerLabel,
                usesLongSessionDisplay: usesLongSessionMode
            )
            metaTurnLineIDs[turnId] = line.id
            lines.append(line)
        }
        sourceLanguageByLineID[line.id] = sourceLanguage
        lastRecognizedText = sourceText
        lastRecognizedWasFinal = true
        lastRecognitionAt = Date()
        presentFloatingSourceText(sourceText)

        let savedTurn = speakerLabel.map { "\($0): \(sourceText)" } ?? sourceText
        metaSavedTranscriptText = metaSavedTranscriptText.isEmpty
            ? savedTurn
            : metaSavedTranscriptText + "\n" + savedTurn
        stageTranscriptForSave(metaSavedTranscriptText)
        requestTranslation(for: line, source: sourceLanguage, target: targetLanguage)

        if metaActiveTurnID == turnId {
            metaActiveTurnID = nil
        }
    }

    private func accumulatedRealtimeText(current: String, next: String) -> String {
        if next.hasPrefix(current) {
            return next
        }
        if current.hasSuffix(next) {
            return current
        }
        return current + next
    }

    private func refreshGeminiLiveCaptionLine() {
        let inputText = geminiLiveInputTranscriptText.trimmingCharacters(in: .whitespacesAndNewlines)
        let outputText = geminiLiveOutputTranscriptText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !inputText.isEmpty || !outputText.isEmpty else { return }

        lastRecognizedText = inputText.isEmpty ? outputText : inputText
        lastRecognitionAt = Date()
        transcriptCleanupTask?.cancel()

        let sourceText = inputText.isEmpty ? AppText.geminiLiveTranslationSource : inputText
        let translatedText = outputText.isEmpty ? AppText.translating : outputText

        if let currentLineID,
           let index = lines.firstIndex(where: { $0.id == currentLineID }) {
            let existingLine = lines[index]
            lines[index] = CaptionLine(
                id: existingLine.id,
                sourceText: sourceText,
                translatedText: translatedText,
                translatedSourceText: sourceText,
                createdAt: existingLine.createdAt,
                isFinal: false,
                revision: existingLine.revision + 1,
                usesLongSessionDisplay: usesLongSessionMode
            )
            sourceLanguageByLineID[existingLine.id] = sourceLanguage
        } else {
            let line = CaptionLine(
                sourceText: sourceText,
                translatedText: translatedText,
                translatedSourceText: sourceText,
                createdAt: Date(),
                isFinal: false,
                revision: 1,
                usesLongSessionDisplay: usesLongSessionMode
            )
            currentLineID = line.id
            sourceLanguageByLineID[line.id] = sourceLanguage
            lines.append(line)
        }

        if !inputText.isEmpty {
            stageTranscriptForSave(inputText, translatedText: outputText)
            presentFloatingSourceText(inputText)
        }
        if !outputText.isEmpty {
            updateFloatingTranslationPresentation(outputText, sourceText: sourceText)
            speakTranslatedDeltaIfNeeded(outputText)
        }
    }

    private func requestTranslationForAppleRecognition(
        for line: CaptionLine,
        source: LanguageOption,
        target: LanguageOption,
        metadata: AppleSpeechRecognitionMetadata?
    ) {
        guard let metadata else {
            requestTranslation(for: line, source: source, target: target)
            return
        }

        let decision = appleRecognitionTranslationPolicy.receive(
            sourceText: line.sourceText,
            lineID: line.id,
            metadata: metadata,
            now: Date(),
            state: &appleRecognitionTranslationState
        )
        handleAppleTranslationDecision(
            decision,
            line: line,
            source: source,
            target: target,
            metadata: metadata
        )
    }

    private func handleAppleTranslationDecision(
        _ decision: AppleRecognitionTranslationPolicy.Decision,
        line: CaptionLine,
        source: LanguageOption,
        target: LanguageOption,
        metadata: AppleSpeechRecognitionMetadata
    ) {
        switch decision {
        case .requestNow(let identity):
            appleSmallPartialFlushTask?.cancel()
            appleSmallPartialFlushTask = nil
            requestTranslation(
                for: line,
                source: source,
                target: target,
                preservesOrdering: identity.isFinal ? true : nil,
                bypassesDebounce: true,
                force: identity.isFinal,
                appleIdentity: identity
            )
        case .hold(let until):
            scheduleAppleRecognitionTranslationRetry(
                lineID: line.id,
                source: source,
                target: target,
                metadata: metadata,
                dueAt: until
            )
        case .ignoreStale, .unchanged:
            break
        }
    }

    private func scheduleAppleRecognitionTranslationRetry(
        lineID: UUID,
        source: LanguageOption,
        target: LanguageOption,
        metadata: AppleSpeechRecognitionMetadata,
        dueAt: Date
    ) {
        appleSmallPartialFlushTask?.cancel()
        let delay = max(0, dueAt.timeIntervalSince(Date()))
        appleSmallPartialFlushTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(Int(delay * 1_000)))
            guard let self, !Task.isCancelled, self.isRunning, !self.isPaused else { return }
            guard let index = self.lines.firstIndex(where: { $0.id == lineID }) else { return }
            guard self.appleSpeechSegmentIDByLineID[lineID] == metadata.segmentID,
                  !self.lines[index].isFinal || metadata.isFinal
            else {
                return
            }
            self.requestTranslationForAppleRecognition(
                for: self.lines[index],
                source: source,
                target: target,
                metadata: metadata
            )
        }
    }

    private func updateAppleSpeechIdentity(
        lineID: UUID,
        metadata: AppleSpeechRecognitionMetadata?
    ) {
        guard let metadata else { return }
        appleSpeechSegmentIDByLineID[lineID] = metadata.segmentID
        appleSpeechRevisionByLineID[lineID] = metadata.revision
    }

    private func prepareAppleSpeechSegmentForAuthoritativeUpdate(
        sourceText: String,
        language: LanguageOption,
        metadata: AppleSpeechRecognitionMetadata?
    ) {
        guard let metadata else {
            return
        }

        let trimmedSourceText = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSourceText.isEmpty else { return }

        if let currentLineID,
           let currentSegmentID = appleSpeechSegmentIDByLineID[currentLineID],
           currentSegmentID != metadata.segmentID {
            self.currentLineID = nil
            committedSourceText = ""
            currentPartialText = ""
            currentPartialLanguage = nil
            pendingParagraphBreakBeforePartial = false
            floatingCommittedSourceText = ""
            floatingCurrentPartialText = ""
            pendingFloatingParagraphBreakBeforePartial = false
        }

        currentPartialText = trimmedSourceText
        currentPartialLanguage = language
        setFloatingCurrentPartialText(trimmedSourceText)
    }

    private func finalizeAppleSpeechSegmentIfNeeded(
        lineID: UUID,
        metadata: AppleSpeechRecognitionMetadata?
    ) {
        guard metadata?.isFinal == true, currentLineID == lineID else { return }
        flushPendingCaptionPresentation()
        commitCurrentPartial()
        currentLineID = nil
        committedSourceText = ""
        currentPartialText = ""
        currentPartialLanguage = nil
        pendingParagraphBreakBeforePartial = false
        floatingCommittedSourceText = ""
        floatingCurrentPartialText = ""
        pendingFloatingParagraphBreakBeforePartial = false
    }

    private func requestTranslation(
        for line: CaptionLine,
        source: LanguageOption,
        target: LanguageOption,
        preservesOrdering: Bool? = nil,
        bypassesDebounce: Bool = false,
        force: Bool = false,
        appleIdentity: AppleTranslationRequestIdentity? = nil
    ) {
        guard !openAITranslationModel.usesRealtimeAudioTranslation else { return }
        guard !isUsingQwenTranslation, !isUsingGeminiTranslation else { return }

        guard !isTranscribeOnlyMode else {
            showTranscribeOnlyNoticeForCurrentActivation()
            return
        }

        guard source.id != target.id else {
            markTranslationUnavailable(
                AppText.sameLanguageTranslationUnavailable,
                for: line,
                matching: line.sourceText
            )
            return
        }

        let sourceText = line.sourceText
        let preservesOrdering = preservesOrdering ?? (isUsingMetaScribe || isUsingAzureMAI || isUsingNariSTT || isUsingGrokSTT)
        if !preservesOrdering {
            guard force || pendingTranslationSourceText != sourceText else { return }
            pendingTranslationSourceText = sourceText
        }
        if latestTranslationRequest == nil, orderedTranslationRequests.isEmpty {
            translationBurstStartedAt = Date()
        }
        let request = TranslationRequest(
            line: line,
            sourceText: sourceText,
            translationSourceText: sourceText,
            source: source,
            target: target,
            preservesOrdering: preservesOrdering,
            bypassesDebounce: bypassesDebounce,
            appleIdentity: appleIdentity
        )
        if preservesOrdering {
            if appleIdentity?.isFinal == true, latestTranslationRequest?.line.id == line.id {
                latestTranslationRequest = nil
            }
            orderedTranslationRequests.append(request)
        } else {
            latestTranslationRequest = request
        }

        guard translationTask == nil else {
            return
        }

        translationTaskGeneration += 1
        let generation = translationTaskGeneration
        translationTask = Task { @MainActor in
            await processPendingTranslationRequests(generation: generation)
        }
    }

    private func processPendingTranslationRequests(generation: Int) async {
        while !Task.isCancelled, let request = nextTranslationRequest() {

            do {
                let delay = request.bypassesDebounce ? 0 : translationDebounceDelay(for: request.sourceText)
                if delay > 0 {
                    try await Task.sleep(for: .milliseconds(delay))
                }

                if !request.preservesOrdering, latestTranslationRequest != nil {
                    continue
                }

                translationBurstStartedAt = .distantPast
                let translationSourceText = try await preparedTranslationSourceText(
                    request.translationSourceText,
                    language: request.source
                )
                try Task.checkCancellation()
                if !request.preservesOrdering, latestTranslationRequest != nil {
                    continue
                }
                if PipelineDiagnostics.isEnabled {
                    PipelineDiagnostics.record("translation.start", id: request.line.id.uuidString, values: ["characters": Double(request.sourceText.count)])
                }
                let translatedText = try await translateTranscript(
                    translationSourceText,
                    source: request.source,
                    target: request.target,
                    progress: { [weak self] partialText in
                        self?.updateTranslation(
                            partialText,
                            for: request.line,
                            matching: request.sourceText,
                            finalizesRequest: false,
                            appleIdentity: request.appleIdentity
                        )
                    }
                )
                if PipelineDiagnostics.isEnabled {
                    PipelineDiagnostics.record("translation.result", id: request.line.id.uuidString, values: ["characters": Double(request.sourceText.count)])
                }
                try Task.checkCancellation()
                updateTranslation(
                    translatedText,
                    for: request.line,
                    matching: request.sourceText,
                    appleIdentity: request.appleIdentity
                )
            } catch is CancellationError {
                // A cancelled loop can resume after a newer loop was registered;
                // only clear its own registration to avoid spawning a concurrent loop.
                if generation == translationTaskGeneration {
                    translationTask = nil
                }
                return
            } catch {
                if pendingTranslationSourceText == request.sourceText {
                    pendingTranslationSourceText = ""
                }
                markTranslationUnavailable(error.localizedDescription, for: request.line, matching: request.sourceText)
            }
        }

        if generation == translationTaskGeneration {
            translationTask = nil
        }
    }

    private func nextTranslationRequest() -> TranslationRequest? {
        if !orderedTranslationRequests.isEmpty {
            return orderedTranslationRequests.removeFirst()
        }
        defer { latestTranslationRequest = nil }
        return latestTranslationRequest
    }

#if DEBUG
    func verifyOrderedMetaTranslationLineIDsForTesting(_ lineIDs: [UUID]) -> [UUID] {
        let requests = lineIDs.map { lineID in
            let line = CaptionLine(
                id: lineID,
                sourceText: lineID.uuidString,
                translatedText: "",
                createdAt: Date(),
                isFinal: true
            )
            return TranslationRequest(
                line: line,
                sourceText: line.sourceText,
                translationSourceText: line.sourceText,
                source: sourceLanguage,
                target: targetLanguage,
                preservesOrdering: true,
                bypassesDebounce: false,
                appleIdentity: nil
            )
        }
        orderedTranslationRequests.append(contentsOf: requests)
        var result: [UUID] = []
        while let request = nextTranslationRequest() {
            result.append(request.line.id)
        }
        return result
    }
#endif

    private func preparedTranslationSourceText(
        _ sourceText: String,
        language: LanguageOption
    ) async throws -> String {
        guard usesLongSessionMode, !isUsingOpenAIRealtime else { return sourceText }

        let languageID = language.id
        let organizedSourceText = try await Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            return TranscriptTextProcessor.organizeTranscript(sourceText, languageID: languageID)
        }.value
        guard !organizedSourceText.isEmpty else { return sourceText }
        return organizedSourceText
    }

    private func translationDebounceDelay(for sourceText: String) -> Int {
        if usesLongSessionMode {
            let sourceLength = sourceText.utf16.count
            if sourceLength >= Self.veryLargeTranscriptTranslationCharacterLimit {
                return 900
            }
            if sourceLength >= Self.largeTranscriptTranslationCharacterLimit {
                return 450
            }
        }

        guard translationBurstStartedAt != .distantPast else { return 45 }
        let burstAge = Date().timeIntervalSince(translationBurstStartedAt)
        return burstAge >= 0.45 ? 0 : 70
    }

    nonisolated static func isCompatibleLiveSource(current: String, requested: String) -> Bool {
        let currentText = current.trimmingCharacters(in: .whitespacesAndNewlines)
        let requestedText = requested.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !requestedText.isEmpty else { return currentText.isEmpty }
        if currentText == requestedText || currentText.hasPrefix(requestedText) {
            return true
        }

        let normalizedCurrentText = currentText.replacingOccurrences(
            of: #"\s+"#,
            with: " ",
            options: .regularExpression
        )
        let normalizedRequestedText = requestedText.replacingOccurrences(
            of: #"\s+"#,
            with: " ",
            options: .regularExpression
        )
        return normalizedCurrentText == normalizedRequestedText
            || normalizedCurrentText.hasPrefix(normalizedRequestedText)
    }

    private func updateTranslation(
        _ translatedText: String,
        for line: CaptionLine,
        matching sourceText: String,
        finalizesRequest: Bool = true,
        appleIdentity: AppleTranslationRequestIdentity? = nil
    ) {
        guard let index = lines.firstIndex(where: { $0.id == line.id }) else { return }
        let currentSourceText = lines[index].sourceText
        if let appleIdentity {
            guard let currentIdentity = appleTranslationLineIdentity(for: line.id),
                  appleRecognitionTranslationPolicy.acceptsTranslationResult(
                      request: appleIdentity,
                      current: currentIdentity
                  )
            else {
                if PipelineDiagnostics.isEnabled {
                    PipelineDiagnostics.record("translation.discard", id: line.id.uuidString, values: ["characters": Double(sourceText.count)])
                }
                if finalizesRequest, pendingTranslationSourceText == sourceText {
                    pendingTranslationSourceText = ""
                }
                return
            }
        }
        guard Self.isCompatibleLiveSource(current: currentSourceText, requested: sourceText) else {
            if PipelineDiagnostics.isEnabled {
                PipelineDiagnostics.record("translation.discard", id: line.id.uuidString, values: ["characters": Double(sourceText.count)])
            }
            if finalizesRequest, pendingTranslationSourceText == sourceText {
                pendingTranslationSourceText = ""
            }
            return
        }
        let organizedTranslatedText = organizeTranscript(translatedText, language: targetLanguage)
        if PipelineDiagnostics.isEnabled {
            PipelineDiagnostics.record("translation.apply", id: line.id.uuidString, values: ["characters": Double(sourceText.count)])
        }
        let floatingTranslatedText = translatedText.trimmingCharacters(in: .whitespacesAndNewlines)
        if finalizesRequest, pendingTranslationSourceText == sourceText {
            pendingTranslationSourceText = ""
        }
        stageTranscriptForSave(
            isUsingGrokSTT ? grokSavedTranscriptText : isUsingNariSTT ? nariSavedTranscriptText : (isUsingAzureMAI ? azureSavedTranscriptText : (isUsingMetaScribe ? metaSavedTranscriptText : currentSourceText)),
            translatedText: organizedTranslatedText
        )

        lines[index] = CaptionLine(
            id: line.id,
            sourceText: currentSourceText,
            translatedText: organizedTranslatedText,
            translatedSourceText: sourceText,
            createdAt: line.createdAt,
            isFinal: lines[index].isFinal,
            revision: lines[index].revision + 1,
            speakerLabel: lines[index].speakerLabel,
            usesLongSessionDisplay: usesLongSessionMode
        )

        updateFloatingTranslationPresentation(floatingTranslatedText, sourceText: sourceText)
        speakTranslatedDeltaIfNeeded(organizedTranslatedText, isFinal: finalizesRequest, appleLineID: appleIdentity?.lineID)
    }

    private func appleTranslationLineIdentity(for lineID: UUID) -> AppleTranslationLineIdentity? {
        guard let index = lines.firstIndex(where: { $0.id == lineID }) else { return nil }
        let line = lines[index]
        return AppleTranslationLineIdentity(
            lineID: line.id,
            sourceText: line.sourceText,
            segmentID: appleSpeechSegmentIDByLineID[line.id],
            revision: appleSpeechRevisionByLineID[line.id] ?? 0,
            isFinal: line.isFinal
        )
    }

    private func markTranslationUnavailable(_ message: String, for line: CaptionLine, matching sourceText: String) {
        guard let index = lines.firstIndex(where: { $0.id == line.id }) else {
            statusMessage = message
            return
        }
        let currentSourceText = lines[index].sourceText
        guard Self.isCompatibleLiveSource(current: currentSourceText, requested: sourceText) else {
            if lines[index].translatedText == AppText.translating {
                let line = lines[index]
                lines[index] = CaptionLine(
                    id: line.id,
                    sourceText: line.sourceText,
                    translatedText: message,
                    translatedSourceText: line.sourceText,
                    createdAt: line.createdAt,
                    isFinal: line.isFinal,
                    revision: line.revision + 1,
                    speakerLabel: line.speakerLabel,
                    usesLongSessionDisplay: usesLongSessionMode
                )
            }
            statusMessage = message
            return
        }

        let existingTranslation = lines[index].translatedText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !existingTranslation.isEmpty, existingTranslation != AppText.translating {
            if pendingTranslationSourceText == sourceText {
                pendingTranslationSourceText = ""
            }
            statusMessage = message
            return
        }

        if pendingTranslationSourceText == sourceText {
            pendingTranslationSourceText = ""
        }

        lines[index] = CaptionLine(
            id: line.id,
            sourceText: currentSourceText,
            translatedText: message,
            translatedSourceText: sourceText,
            createdAt: line.createdAt,
            isFinal: line.isFinal,
            revision: lines[index].revision + 1,
            speakerLabel: lines[index].speakerLabel,
            usesLongSessionDisplay: usesLongSessionMode
        )
        updateFloatingTranslationPresentation(message, sourceText: sourceText)
        statusMessage = message
    }

    func updateFloatingTranslationPresentation(_ translatedText: String, sourceText: String) {
        let displaySourceText = isUsingOpenAIRealtime
            ? realtimeFloatingCaptionText(from: sourceText)
            : sourceText
        let displayTranslatedText = isUsingOpenAIRealtime
            ? realtimeFloatingCaptionText(from: translatedText)
            : translatedText

        guard !displaySourceText.isEmpty,
              !displayTranslatedText.isEmpty,
              displayTranslatedText != AppText.translating
        else {
            return
        }

        if shouldUpdateFloatingTranslationDisplay(for: displaySourceText) {
            applyFloatingTranslationCandidate(displayTranslatedText, sourceText: displaySourceText)
            return
        }

        if shouldUpdateQueuedFloatingTranslationDisplay(for: displaySourceText) {
            floatingQueuedTranslationText = displayTranslatedText
            floatingQueuedTranslationSourceText = displaySourceText
            scheduleFloatingPresentationAdvance()
        }
    }

    /// Decides whether a translation for the currently presented source may
    /// replace the displayed one now or has to wait for the translation dwell.
    ///
    /// Extensions of the visible translation and translations that replace a
    /// stale (already-superseded) translation render immediately; every other
    /// rewrite is held so retranslations of a growing sentence do not flicker.
    private func applyFloatingTranslationCandidate(_ translatedText: String, sourceText: String) {
        let normalizedDisplayed = normalizedTranscriptForComparison(floatingDisplayTranslationText)
        let normalizedCandidate = normalizedTranscriptForComparison(translatedText)

        if floatingDisplayTranslationText.isEmpty || isFloatingTranslationDisplayStale {
            setFloatingDisplayTranslation(translatedText, sourceText: sourceText, resetsDwell: true)
            return
        }

        if normalizedDisplayed == normalizedCandidate {
            floatingDisplayTranslationText = translatedText
            floatingDisplayTranslationSourceText = sourceText
            clearQueuedFloatingTranslation()
            return
        }

        if isWholeTextPrefix(normalizedDisplayed, of: normalizedCandidate) {
            setFloatingDisplayTranslation(translatedText, sourceText: sourceText, resetsDwell: false)
            return
        }

        if canAdvanceFloatingTranslation() {
            setFloatingDisplayTranslation(translatedText, sourceText: sourceText, resetsDwell: true)
            return
        }

        floatingQueuedTranslationText = translatedText
        floatingQueuedTranslationSourceText = sourceText
        scheduleFloatingPresentationAdvance()
    }

    private func setFloatingDisplayTranslation(_ translatedText: String, sourceText: String, resetsDwell: Bool) {
        if PipelineDiagnostics.isEnabled {
            PipelineDiagnostics.record("floating.translation", values: ["characters": Double(sourceText.count)])
        }
        let normalizedDisplayed = normalizedTranscriptForComparison(floatingDisplayTranslationText)
        let normalizedCandidate = normalizedTranscriptForComparison(translatedText)
        let unreadLength = max(
            0,
            normalizedCandidate.count - commonPrefixLength(normalizedDisplayed, normalizedCandidate)
        )

        floatingDisplayTranslationText = translatedText
        floatingDisplayTranslationSourceText = sourceText
        if resetsDwell {
            floatingTranslationPresentedAt = Date()
            floatingTranslationUnreadLength = unreadLength
        } else {
            floatingTranslationUnreadLength += unreadLength
        }
        clearQueuedFloatingTranslation()
        floatingTranslationHoldTask?.cancel()
        floatingTranslationHoldTask = nil
    }

    private func clearQueuedFloatingTranslation() {
        floatingQueuedTranslationText = ""
        floatingQueuedTranslationSourceText = ""
    }

    private func promoteQueuedFloatingTranslationIfPossible() {
        guard !floatingQueuedTranslationText.isEmpty else { return }
        guard shouldUpdateFloatingTranslationDisplay(for: floatingQueuedTranslationSourceText) else {
            if floatingQueuedSourceText.isEmpty {
                clearQueuedFloatingTranslation()
            }
            return
        }

        guard floatingDisplayTranslationText.isEmpty
            || isFloatingTranslationDisplayStale
            || canAdvanceFloatingTranslation()
        else {
            return
        }

        setFloatingDisplayTranslation(
            floatingQueuedTranslationText,
            sourceText: floatingQueuedTranslationSourceText,
            resetsDwell: true
        )
    }

    private func shouldUpdateFloatingTranslationDisplay(for sourceText: String) -> Bool {
        translationSource(sourceText, matches: floatingPresentedSourceText)
    }

    private func shouldUpdateQueuedFloatingTranslationDisplay(for sourceText: String) -> Bool {
        translationSource(sourceText, matches: floatingQueuedSourceText)
    }

    private func translationSource(_ sourceText: String, matches displaySourceText: String) -> Bool {
        guard !displaySourceText.isEmpty else { return false }

        if sourceText == displaySourceText || isWholeTextPrefix(sourceText, of: displaySourceText) {
            return true
        }

        let normalizedSourceText = normalizedTranscriptForComparison(sourceText)
        let normalizedDisplaySourceText = normalizedTranscriptForComparison(displaySourceText)
        if normalizedSourceText == normalizedDisplaySourceText
            || isWholeTextPrefix(normalizedSourceText, of: normalizedDisplaySourceText) {
            return true
        }

        let organizedDisplaySourceText = organizeTranscript(
            displaySourceText,
            language: sourceLanguage,
            appliesLint: false
        )
        let normalizedOrganizedDisplaySourceText = normalizedTranscriptForComparison(organizedDisplaySourceText)
        return normalizedSourceText == normalizedOrganizedDisplaySourceText
            || isWholeTextPrefix(normalizedSourceText, of: normalizedOrganizedDisplaySourceText)
    }

    private func translationDirection(recognizedLanguage: LanguageOption) -> (source: LanguageOption, target: LanguageOption) {
        (isUsingAppleSourceAutoDetection ? recognizedLanguage : sourceLanguage, targetLanguage)
    }

    private func speak(_ text: String) {
        guard !text.isEmpty else { return }
        speechOutput.speak(text, language: targetLanguage)
    }

    private func speakTranslatedDeltaIfNeeded(_ translatedText: String, isFinal: Bool = false, appleLineID: UUID? = nil) {
        guard isRunning, !isPaused, isDubbingEnabled else { return }
        guard !isUsingProviderRealtimeTranslation else { return }
        guard translatedText != AppText.translating else { return }

        if let text = unspokenTranslatedText(translatedText, isFinal: isFinal, appleLineID: appleLineID) {
            speak(text)
        }
    }

    private func unspokenTranslatedText(_ translatedText: String, isFinal: Bool, appleLineID: UUID?) -> String? {
        let unspokenText: String?
        if let appleLineID {
            if appleDubbingProgressByLineID[appleLineID] == nil {
                appleDubbingProgressByLineID[appleLineID] = DubbingSpeechProgress()
                appleDubbingLineOrder.append(appleLineID)
                while appleDubbingLineOrder.count > 8 {
                    appleDubbingProgressByLineID[appleDubbingLineOrder.removeFirst()] = nil
                }
            }
            unspokenText = appleDubbingProgressByLineID[appleLineID]?.unspokenText(
                from: translatedText, languageID: targetLanguage.id, isFinal: isFinal
            )
        } else {
            unspokenText = dubbingSpeechProgress.unspokenText(
                from: translatedText, languageID: targetLanguage.id, isFinal: isFinal
            )
        }
        return unspokenText
    }

    private func commonPrefixLength(_ lhs: String, _ rhs: String) -> Int {
        var length = 0
        for (leftCharacter, rightCharacter) in zip(lhs, rhs) {
            guard leftCharacter == rightCharacter else { break }
            length += 1
        }
        return length
    }

    private func resetDubbingProgress() {
        dubbingSpeechProgress.reset()
        appleDubbingProgressByLineID.removeAll()
        appleDubbingLineOrder.removeAll()
        stopSpeaking()
    }

    private func primeDubbingBaselineToCurrentTranslation() {
        dubbingSpeechProgress.prime(
            with: lines.last?.translatedText ?? "",
            languageID: targetLanguage.id
        )
    }

    private func stopSpeaking() {
        speechOutput.stop()
        openAIRealtimeAudioOutput.stop()
    }

    private func applyTranslatedVoiceVolume() {
        speechOutput.setVolume(translatedVoiceVolume)
        openAIRealtimeAudioOutput.setVolume(translatedVoiceVolume)
    }

    private static func clampedVolume(_ volume: Double, minimum: Double = 0) -> Double {
        min(max(volume, minimum), 1)
    }

    private func activeGeneration(
        for transcriber: LiveSpeechTranscriber,
        requiresRunning: Bool
    ) -> UInt64? {
        guard let generation = activeCaptionerGeneration else {
            // Presentation-policy tests and preview harnesses can intentionally
            // drive the delegate while manually owning `isRunning`. Production
            // starts always publish a captioner generation before setting it.
            guard requiresRunning,
                  isRunning,
                  pipelineLifecycle.phase == .stopped
            else {
                return nil
            }
            return pipelineLifecycle.generation
        }
        let isCurrentProducer = transcriber === self.transcriber
            || openAITranscriber.ownsDelegateProxy(transcriber)
        guard isCurrentProducer else { return nil }
        if requiresRunning {
            return pipelineLifecycle.acceptsSample(generation: generation) ? generation : nil
        }
        return pipelineLifecycle.isActive(generation: generation) ? generation : nil
    }

    private func activeGeneration(
        for service: GeminiLiveTranslationService,
        requiresRunning: Bool
    ) -> UInt64? {
        guard let generation = activeCaptionerGeneration else {
            guard requiresRunning,
                  isRunning,
                  pipelineLifecycle.phase == .stopped
            else {
                return nil
            }
            return pipelineLifecycle.generation
        }
        guard service === geminiLiveTranslator else {
            return nil
        }
        if requiresRunning {
            return pipelineLifecycle.acceptsSample(generation: generation) ? generation : nil
        }
        return pipelineLifecycle.isActive(generation: generation) ? generation : nil
    }

    private func activeGeneration(
        for service: MetaVoiceTranscribeService,
        requiresRunning: Bool
    ) -> UInt64? {
        guard let generation = activeCaptionerGeneration else {
            guard requiresRunning,
                  isRunning,
                  pipelineLifecycle.phase == .stopped
            else {
                return nil
            }
            return pipelineLifecycle.generation
        }
        guard service === metaVoiceTranscriber else { return nil }
        if requiresRunning {
            return pipelineLifecycle.acceptsSample(generation: generation) ? generation : nil
        }
        return pipelineLifecycle.isActive(generation: generation) ? generation : nil
    }

#if DEBUG
    func deliverNariTranscriptForTesting(_ update: NariTranscriptUpdate, generation: UInt64) {
        receiveNariTranscript(update, service: nariTranscriber, generation: generation)
    }

    func finishNariPipelineForTesting() {
        pipelineLifecycle.stop()
        finishPipeline(statusOverride: nil)
    }

    func drainNariTranslationsForTesting() async throws {
        try await drainNariTranslations()
    }

    func stopNariFromSystemMenuForTesting(generation: UInt64) {
        handleSystemAudioCaptureStoppedByUser(generation: generation)
    }

    func beginPermissionSuspendedStartForTesting() -> UInt64? {
        guard !isRunning, !isStarting else { return nil }

        invalidateCaptureStartAttempt()
        let configuration = currentStartConfiguration()
        let generation = pipelineLifecycle.beginStart(configuration: configuration)
        activeCaptureStartGeneration = generation
        isStarting = true
        statusMessage = AppText.checkingSpeechPermission
        captureStartTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.completeCaptureStartAttempt(generation: generation) }
            do {
                await withCheckedContinuation { continuation in
                    self.permissionSuspendedStartContinuations[generation] = continuation
                }
                self.permissionSuspendedStartContinuations[generation] = nil
                try self.validatePipelineStart(
                    generation: generation,
                    configuration: configuration
                )
            } catch let error as CancellationError {
                await self.handleCancelledCaptureStart(
                    generation: generation,
                    error: error
                )
            } catch {
                guard self.pipelineLifecycle.fail(generation: generation) else { return }
                self.isStarting = false
                self.isRunning = false
                self.stopCaptioners()
                await self.stopCapture()
                self.statusMessage = AppText.startFailed(error.localizedDescription)
            }
        }
        return generation
    }

    func resumePermissionSuspendedStartForTesting() {
        guard permissionSuspendedStartContinuations.count == 1,
              let generation = permissionSuspendedStartContinuations.keys.first
        else {
            return
        }
        resumePermissionSuspendedStartForTesting(generation: generation)
    }

    func resumePermissionSuspendedStartForTesting(generation: UInt64) {
        let continuation = permissionSuspendedStartContinuations.removeValue(forKey: generation)
        continuation?.resume()
    }

    var isPermissionSuspendedStartForTesting: Bool {
        !permissionSuspendedStartContinuations.isEmpty
    }

    func isPermissionSuspendedStartForTesting(generation: UInt64) -> Bool {
        permissionSuspendedStartContinuations[generation] != nil
    }

    func simulatePipelineStartConfigurationErrorForTesting(
        generation: UInt64
    ) async {
        await handlePipelineStartError(
            .configurationChanged,
            generation: generation
        )
    }

    func activateLiveCallbackPipelineForTesting() -> (
        generation: UInt64,
        transcriber: LiveSpeechTranscriber,
        openAITranscriber: OpenAIRealtimeTranscriber
    ) {
        pipelineLifecycle.stop()
        stopCaptioners()

        let configuration = currentStartConfiguration()
        let generation = pipelineLifecycle.beginStart(configuration: configuration)
        transcriber = LiveSpeechTranscriber()
        transcriber.delegate = self
        openAITranscriber = OpenAIRealtimeTranscriber()
        openAITranscriber.delegate = self
        configureOpenAITerminalTranscriptDelivery(for: openAITranscriber)
        activeCaptionerGeneration = generation
        _ = pipelineLifecycle.markRunning(
            generation: generation,
            currentConfiguration: configuration
        )
        isStarting = false
        isRunning = true
        return (generation, transcriber, openAITranscriber)
    }

    func warmTranslationSessionForTesting() {
        warmTranslationSession()
    }

    var systemAudioCaptureForTesting: SystemAudioCapture {
        systemAudioCapture
    }

    func simulateSystemAudioStartFailureForTesting(_ error: Error) async -> UInt64? {
        guard !isRunning, !isStarting, audioInputSource == .systemAudio else {
            return nil
        }

        let configuration = currentStartConfiguration()
        let generation = pipelineLifecycle.beginStart(configuration: configuration)
        activeCaptureStartGeneration = generation
        isStarting = true
        statusMessage = AppText.startingCapture(for: .systemAudio)
        await handleCaptureStartFailure(
            error,
            generation: generation,
            configuration: configuration
        )
        completeCaptureStartAttempt(generation: generation)
        return generation
    }

    func deliverQwenTextForTesting(_ text: String, isFinal: Bool, isTranslation: Bool, generation: UInt64) {
        receiveQwenText(text, isFinal: isFinal, isTranslation: isTranslation, service: qwenTranslator, generation: generation)
    }

    @discardableResult
    func checkpointQwenTranscriptForTesting() -> Bool {
        checkpointPendingTranscriptSave()
    }

    func stopQwenFromSystemMenuForTesting(generation: UInt64) {
        handleSystemAudioCaptureStoppedByUser(generation: generation)
    }

    func finishQwenPipelineForTesting() {
        pipelineLifecycle.stop()
        finishPipeline(statusOverride: nil)
    }

    func deliverGrokTranscriptForTesting(_ update: GrokTranscriptUpdate, generation: UInt64) {
        receiveGrokTranscript(update, service: grokTranscriber, generation: generation)
    }

    func finishGrokPipelineForTesting() {
        pipelineLifecycle.stop()
        finishPipeline(statusOverride: nil)
    }

    func drainGrokTranslationsForTesting() async throws {
        try await drainGrokTranslations()
    }

    func stopGrokFromSystemMenuForTesting(generation: UInt64) {
        handleSystemAudioCaptureStoppedByUser(generation: generation)
    }

#endif
}

extension TranslationSessionStore: SystemAudioCaptureDelegate {
    nonisolated func systemAudioCapture(
        _ capture: SystemAudioCapture,
        didOutput sampleBuffer: CMSampleBuffer,
        generation: UInt64
    ) {
        audioSamplePipelineRegistry.append(sampleBuffer, generation: generation)
    }

    nonisolated func systemAudioCapture(
        _ capture: SystemAudioCapture,
        didReceiveAudioSampleCount count: Int,
        level: Float?,
        generation: UInt64
    ) {
        Task { @MainActor in
            guard capture === systemAudioCapture,
                  pipelineLifecycle.acceptsSample(generation: generation)
            else {
                return
            }
            audioSampleCount = count
            latestAudioLevel = level
            guard !isPaused else {
                statusMessage = AppText.paused
                return
            }
            if isRunning, lines.isEmpty {
                statusMessage = audioStatusMessage(sampleCount: count, level: level)
            }
            if let level, level < -50 {
                scheduleTranscriptCleanup()
            }
        }
    }

    nonisolated func systemAudioCapture(
        _ capture: SystemAudioCapture,
        didFail error: Error,
        generation: UInt64
    ) {
        Task { @MainActor in
            guard capture === systemAudioCapture else { return }
            handleFatalPipelineError(error, generation: generation)
        }
    }

    nonisolated func systemAudioCaptureDidStopByUser(
        _ capture: SystemAudioCapture,
        generation: UInt64
    ) {
        Task { @MainActor in
            guard capture === systemAudioCapture else { return }
            handleSystemAudioCaptureStoppedByUser(generation: generation)
        }
    }

    private func audioStatusMessage(sampleCount: Int, level: Float?) -> String {
        guard let level else {
            return AppText.receivingAudioWaiting(sampleCount: sampleCount, source: audioInputSource)
        }

        let roundedLevel = Int(level.rounded())
        if level < -55 {
            return AppText.receivingSilentAudio(
                sampleCount: sampleCount,
                level: roundedLevel,
                source: audioInputSource
            )
        }

        return AppText.receivingAudioTranscribing(
            sampleCount: sampleCount,
            level: roundedLevel,
            source: audioInputSource
        )
    }
}

extension TranslationSessionStore: MicrophoneAudioCaptureDelegate {
    nonisolated func microphoneAudioCapture(
        _ capture: MicrophoneAudioCapture,
        didOutput sampleBuffer: CMSampleBuffer,
        generation: UInt64
    ) {
        audioSamplePipelineRegistry.append(sampleBuffer, generation: generation)
    }

    nonisolated func microphoneAudioCapture(
        _ capture: MicrophoneAudioCapture,
        didReceiveAudioSampleCount count: Int,
        level: Float?,
        generation: UInt64
    ) {
        Task { @MainActor in
            guard capture === microphoneAudioCapture,
                  pipelineLifecycle.acceptsSample(generation: generation)
            else {
                return
            }
            audioSampleCount = count
            latestAudioLevel = level
            guard !isPaused else {
                statusMessage = AppText.paused
                return
            }
            if isRunning, lines.isEmpty {
                statusMessage = audioStatusMessage(sampleCount: count, level: level)
            }
            if let level, level < -50 {
                scheduleTranscriptCleanup()
            }
        }
    }

    nonisolated func microphoneAudioCapture(
        _ capture: MicrophoneAudioCapture,
        didFail error: Error,
        generation: UInt64
    ) {
        Task { @MainActor in
            guard capture === microphoneAudioCapture else { return }
            handleFatalPipelineError(error, generation: generation)
        }
    }
}

extension TranslationSessionStore: LiveSpeechTranscriberDelegate {
    nonisolated func liveSpeechTranscriber(
        _ transcriber: LiveSpeechTranscriber,
        didRecognize text: String,
        language: LanguageOption,
        confidence: Double
    ) {
        Task { @MainActor in
            if PipelineDiagnostics.isEnabled {
                PipelineDiagnostics.record("speech.received", values: ["characters": Double(text.count)])
            }
            guard activeGeneration(for: transcriber, requiresRunning: true) != nil else {
                return
            }
            enqueueRecognizedCaption(
                sourceText: text,
                recognizedLanguage: language,
                confidence: confidence
            )
        }
    }

    nonisolated func liveSpeechTranscriber(
        _ transcriber: LiveSpeechTranscriber,
        didRecognize text: String,
        language: LanguageOption,
        confidence: Double,
        metadata: AppleSpeechRecognitionMetadata
    ) {
        Task { @MainActor in
            if PipelineDiagnostics.isEnabled {
                let nowUptime = ProcessInfo.processInfo.systemUptime
                PipelineDiagnostics.record("speech.received", values: [
                    "characters": Double(text.count),
                    "final": metadata.isFinal ? 1 : 0,
                    "audio_start": metadata.audioStartSeconds,
                    "audio_end": metadata.audioEndSeconds,
                    "dispatch_ms": max(0, (nowUptime - metadata.emittedAtUptime) * 1_000)
                ])
            }
            guard activeGeneration(for: transcriber, requiresRunning: true) != nil else {
                return
            }
            enqueueRecognizedCaption(
                sourceText: text,
                recognizedLanguage: language,
                confidence: confidence,
                metadata: metadata
            )
        }
    }

    nonisolated func liveSpeechTranscriber(
        _ transcriber: LiveSpeechTranscriber,
        didTranslate text: String,
        language: LanguageOption,
        confidence: Double
    ) {
        Task { @MainActor in
            guard activeGeneration(for: transcriber, requiresRunning: true) != nil else {
                return
            }
            appendRealtimeTranslationOnly(text)
        }
    }

    nonisolated func liveSpeechTranscriber(
        _ transcriber: LiveSpeechTranscriber,
        didRecognizeSourceTranscript text: String,
        confidence: Double
    ) {
        Task { @MainActor in
            guard activeGeneration(for: transcriber, requiresRunning: true) != nil else {
                return
            }
            updateRealtimeTranslationSourceTranscript(text)
        }
    }

    nonisolated func liveSpeechTranscriber(
        _ transcriber: LiveSpeechTranscriber,
        didOutputAudioPCM16Base64 audio: String,
        sampleRate: Double
    ) {
        Task { @MainActor in
            guard activeGeneration(for: transcriber, requiresRunning: true) != nil,
                  isRunning,
                  !isPaused,
                  isDubbingEnabled,
                  openAITranslationModel.usesRealtimeAudioTranslation
            else {
                return
            }

            openAIRealtimeAudioOutput.playPCM16Base64(audio, sampleRate: sampleRate)
        }
    }

    nonisolated func liveSpeechTranscriber(_ transcriber: LiveSpeechTranscriber, didFail error: Error) {
        Task { @MainActor in
            guard let generation = activeGeneration(
                for: transcriber,
                requiresRunning: false
            ) else {
                return
            }
            handleFatalPipelineError(error, generation: generation)
        }
    }
}

extension TranslationSessionStore: GeminiLiveTranslationServiceDelegate {
    nonisolated func geminiLiveTranslationService(
        _ service: GeminiLiveTranslationService,
        didReceiveInputTranscript text: String,
        languageCode _: String?,
        isFinal: Bool
    ) {
        Task { @MainActor in
            guard activeGeneration(for: service, requiresRunning: true) != nil else {
                return
            }
            if isUsingGeminiTranscriptionMode {
                updateGeminiLiveTranscription(text, isFinal: isFinal)
            } else {
                updateGeminiLiveInputTranscript(text)
            }
        }
    }

    nonisolated func geminiLiveTranslationService(
        _ service: GeminiLiveTranslationService,
        didReceiveOutputTranscript text: String,
        languageCode _: String?
    ) {
        Task { @MainActor in
            guard activeGeneration(for: service, requiresRunning: true) != nil else {
                return
            }
            updateGeminiLiveOutputTranscript(text)
        }
    }

    nonisolated func geminiLiveTranslationService(
        _ service: GeminiLiveTranslationService,
        didOutputAudioPCM16Base64 audio: String,
        sampleRate: Double
    ) {
        Task { @MainActor in
            guard activeGeneration(for: service, requiresRunning: true) != nil,
                  isRunning,
                  !isPaused,
                  isDubbingEnabled,
                  isUsingGeminiTranslation
            else {
                return
            }

            openAIRealtimeAudioOutput.playPCM16Base64(audio, sampleRate: sampleRate)
        }
    }

    nonisolated func geminiLiveTranslationServiceDidInterruptOutputAudio(
        _ service: GeminiLiveTranslationService
    ) {
        Task { @MainActor in
            guard activeGeneration(for: service, requiresRunning: true) != nil else {
                return
            }
            openAIRealtimeAudioOutput.stop()
        }
    }

    nonisolated func geminiLiveTranslationService(
        _ service: GeminiLiveTranslationService,
        didFail error: Error
    ) {
        Task { @MainActor in
            guard let generation = activeGeneration(
                for: service,
                requiresRunning: false
            ) else {
                return
            }
            handleFatalPipelineError(error, generation: generation)
        }
    }
}

extension TranslationSessionStore: MetaVoiceTranscribeServiceDelegate {
    nonisolated func metaVoiceTranscribeService(
        _ service: MetaVoiceTranscribeService,
        didStartTurn turnId: Int32
    ) {
        Task { @MainActor in
            guard activeGeneration(for: service, requiresRunning: true) != nil else { return }
            startMetaTurn(turnId)
        }
    }

    nonisolated func metaVoiceTranscribeService(
        _ service: MetaVoiceTranscribeService,
        didReceivePartialTranscript text: String
    ) {
        Task { @MainActor in
            guard activeGeneration(for: service, requiresRunning: true) != nil else { return }
            updateMetaPartialTranscript(text)
        }
    }

    nonisolated func metaVoiceTranscribeService(
        _ service: MetaVoiceTranscribeService,
        didLabelSpeaker label: String
    ) {
        Task { @MainActor in
            guard activeGeneration(for: service, requiresRunning: true) != nil else { return }
            labelMetaSpeaker(label)
        }
    }

    nonisolated func metaVoiceTranscribeService(
        _ service: MetaVoiceTranscribeService,
        didCompleteTurn turnId: Int32,
        transcript: String
    ) {
        Task { @MainActor in
            guard activeGeneration(for: service, requiresRunning: true) != nil else { return }
            completeMetaTurn(turnId, transcript: transcript)
        }
    }

    nonisolated func metaVoiceTranscribeService(
        _ service: MetaVoiceTranscribeService,
        didFail error: Error
    ) {
        Task { @MainActor in
            guard let generation = activeGeneration(for: service, requiresRunning: false) else {
                return
            }
            handleFatalPipelineError(error, generation: generation)
        }
    }
}
