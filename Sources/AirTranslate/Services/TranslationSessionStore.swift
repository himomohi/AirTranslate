import AVFAudio
import AppKit
import AirTranslateCore
import Foundation
import Observation

private enum SettingsKey {
    static let sourceLanguageID = "sourceLanguageID"
    static let targetLanguageID = "targetLanguageID"
    static let selectedModelID = "selectedModelID"
    static let openAITranscriptionModelID = "openAITranscriptionModelID"
    static let openAITranslationModelID = "openAITranslationModelID"
    static let isDubbingEnabled = "isDubbingEnabled"
    static let isTranscriptLintEnabled = "isTranscriptLintEnabled"
    static let floatingCaptionDisplayMode = "floatingCaptionDisplayMode"
    static let floatingCaptionTextSize = "floatingCaptionTextSize"
    static let floatingCaptionLineCount = "floatingCaptionLineCount"
    static let floatingCaptionTextAlignment = "floatingCaptionTextAlignment"
    static let isFloatingCaptionImmediateDisplayEnabled = "isFloatingCaptionImmediateDisplayEnabled"
    static let paragraphBreakSilenceInterval = "paragraphBreakSilenceInterval"
    static let savedTranscriptContentMode = "savedTranscriptContentMode"
    static let sessionDurationMode = "sessionDurationMode"
    static let audioInputSource = "audioInputSource"
    static let selectedMicrophoneInputDeviceID = "selectedMicrophoneInputDeviceID"
    static let isAppleSourceAutoDetectionEnabled = "isAppleSourceAutoDetectionEnabled"
    static let openAIProvider = "openAIProvider"
    static let customAzureTranscriptionModelName = "customAzureTranscriptionModelName"
    static let customAzureTranslationModelName = "customAzureTranslationModelName"
}

private struct TranslationRequest {
    let line: CaptionLine
    let sourceText: String
    let translationSourceText: String
    let source: LanguageOption
    let target: LanguageOption
}

private struct PendingCaptionPresentation {
    let lineID: UUID
    let sourceText: String
    let isFinal: Bool
    let source: LanguageOption
    let target: LanguageOption
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
    private static let largeTranscriptTranslationCharacterLimit = 4_000
    private static let veryLargeTranscriptTranslationCharacterLimit = 10_000
    private static let appleAutoDetectionMinimumConfidence = 0.35
    private static let appleAutoDetectionLanguageSwitchMinimumConfidence = 0.72
    private static let isAppleSourceAutoDetectionTemporarilyDisabled = true

    var isRunning = false
    var isPaused = false
    var isDubbingEnabled = false {
        didSet {
            persistSelectedSettings()
            if isDubbingEnabled {
                if isUsingOpenAIRealtimeTranslation {
                    openAIRealtimeAudioOutput.stop()
                } else {
                    primeDubbingBaselineToCurrentTranslation()
                }
            } else {
                stopSpeaking()
                lastSpokenTranslatedText = ""
                clearSpokenTranslationUnits()
            }
        }
    }
    var sourceLanguage = LanguageOption.supported[0] {
        didSet {
            persistSelectedSettings()
            resetTranslationCache()
            resetDubbingProgress()
            refreshModelAvailability()
        }
    }
    var targetLanguage = LanguageOption.supported[1] {
        didSet {
            persistSelectedSettings()
            resetTranslationCache()
            resetDubbingProgress()
            refreshModelAvailability()
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
    var hasAzureOpenAIConfig = AzureOpenAIConfigStore.hasConfig()
    var azureOpenAIEndpoint: String = AzureOpenAIConfigStore.readEndpoint() ?? ""
    var openAIProvider: OpenAIProvider = .openAI {
        didSet {
            persistSelectedSettings()
            refreshModelAvailability()
        }
    }
    var customAzureTranscriptionModelName: String = "" {
        didSet { persistSelectedSettings() }
    }
    var customAzureTranslationModelName: String = "" {
        didSet { persistSelectedSettings() }
    }
    var openAITranscriptionModel = OpenAIRealtimeTranscriptionModel.off {
        didSet {
            if openAITranscriptionModel.isEnabled {
                isTranscriptLintEnabled = false
            }
            persistSelectedSettings()
            resetTranslationCache()
            refreshModelAvailability()
        }
    }
    var openAITranslationModel = OpenAIRealtimeTranslationModel.off {
        didSet {
            if openAITranslationModel.isEnabled {
                isTranscriptLintEnabled = false
            }
            persistSelectedSettings()
            resetTranslationCache()
            resetDubbingProgress()
            refreshModelAvailability()
        }
    }
    var isTranscriptLintEnabled = false {
        didSet { persistSelectedSettings() }
    }
    var floatingCaptionDisplayMode = FloatingCaptionDisplayMode.originalAndTranslation {
        didSet { persistSelectedSettings() }
    }
    var floatingCaptionTextSize = FloatingCaptionTextSize.medium {
        didSet { persistSelectedSettings() }
    }
    var floatingCaptionLineCount = FloatingCaptionLineCount.three {
        didSet { persistSelectedSettings() }
    }
    var floatingCaptionTextAlignment = FloatingCaptionTextAlignment.center {
        didSet { persistSelectedSettings() }
    }
    var isFloatingCaptionImmediateDisplayEnabled = false {
        didSet {
            persistSelectedSettings()
            if isFloatingCaptionImmediateDisplayEnabled {
                promoteQueuedFloatingPresentationIfReady()
            }
        }
    }
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
    var toastMessage: String?
    var toastSequence = 0
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
    private var microphoneAudioCapture = MicrophoneAudioCapture()
    @ObservationIgnored nonisolated(unsafe) private var transcriber = LiveSpeechTranscriber()
    @ObservationIgnored nonisolated(unsafe) private var openAITranscriber = OpenAIRealtimeTranscriber()
    private let translator = AppleTranslationService()
    private let openAITranslator = OpenAITranslationService()
    private let foundationTranscriptPolisher = FoundationTranscriptPolisher()
    private let speechOutput = TranslatedSpeechOutput()
    private let openAIRealtimeAudioOutput = OpenAIRealtimeAudioOutput()
    private let spellChecker = NSSpellChecker.shared
    private let spellDocumentTag = NSSpellChecker.uniqueSpellDocumentTag()
    private var audioSampleCount = 0
    private var lastRecognizedText = ""
    private var lastRecognizedWasFinal = false
    private var lastRecognitionAt = Date.distantPast
    private var currentLineID: UUID?
    private var lastCaptionPresentationUpdateAt = Date.distantPast
    private var pendingCaptionPresentation: PendingCaptionPresentation?
    private var captionPresentationTask: Task<Void, Never>?
    private var transcriptCleanupTask: Task<Void, Never>?
    private var translationTask: Task<Void, Never>?
    private var latestTranslationRequest: TranslationRequest?
    private var translationBurstStartedAt = Date.distantPast
    private var committedSourceText = ""
    private var currentPartialText = ""
    private var currentPartialLanguage: LanguageOption?
    private var pendingParagraphBreakBeforePartial = false
    private var floatingCommittedSourceText = ""
    private var floatingCurrentPartialText = ""
    private var pendingFloatingParagraphBreakBeforePartial = false
    private var floatingPresentedSourceText = ""
    private var floatingQueuedSourceText = ""
    private var floatingPresentedAt = Date.distantPast
    private var appleAutoDetectionPreferredLanguage: LanguageOption?
    private var floatingDisplayTranslationText = ""
    private var floatingDisplayTranslationSourceText = ""
    private var floatingQueuedTranslationText = ""
    private var floatingQueuedTranslationSourceText = ""
    private var floatingPresentationTask: Task<Void, Never>?
    private var sourceLanguageByLineID: [UUID: LanguageOption] = [:]
    private var pendingTranslationSourceText = ""
    private var translatedSegmentsBySource: [String: String] = [:]
    private var translationCacheKeyOrder: [String] = []
    private var realtimeTranslationOnlyText = ""
    private var activeAutosaveSourceText = ""
    private var activeAutosaveTranslatedText = ""
    private var isRestoringSelectedSettings = false
    private var modelAvailabilityTask: Task<Void, Never>?
    private var toastDismissTask: Task<Void, Never>?
    private var captureStartTask: Task<Void, Never>?
    private var lastSpokenTranslatedText = ""
    private var spokenTranslationUnitKeys: Set<String> = []
    private var spokenTranslationUnitKeyOrder: [String] = []

    private enum SavedTranscriptPart {
        case original
        case translation
    }

    private var usesLongSessionMode: Bool {
        sessionDurationMode == .thirtyMinutesOrMore
    }

    var shouldCoalesceTranscriptAutoScroll: Bool {
        usesLongSessionMode && !isUsingOpenAIRealtime
    }

    var isUsingOpenAIRealtime: Bool {
        openAITranscriptionModel.isEnabled || openAITranslationModel.isEnabled
    }

    var isUsingOpenAIRealtimeTranslation: Bool {
        openAITranslationModel.usesRealtimeAudioTranslation
    }

    private struct SavedTranscriptFile {
        let fileName: String
        let text: String
        let updatedAt: Date
    }

    private struct PartialSavedTranscript {
        var original: SavedTranscriptFile?
        var translation: SavedTranscriptFile?
    }

    init() {
        restoreSelectedSettings()
        systemAudioCapture.delegate = self
        microphoneAudioCapture.delegate = self
        transcriber.delegate = self
        openAITranscriber.delegate = self
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
        hasAzureOpenAIConfig = false
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
        guard !isRunning else { return }

        resetLiveSessionState(clearsVisibleLines: true)
        isPaused = false
        setCaptionersPaused(false)
        isRunning = true
        captureStartTask?.cancel()
        statusMessage = audioInputSource == .microphone
            ? AppText.checkingMicrophonePermission
            : AppText.checkingScreenPermission

        captureStartTask = Task { @MainActor in
            do {
                if audioInputSource == .systemAudio {
                    try systemAudioCapture.requestScreenRecordingAccess()
                }
                guard !Task.isCancelled, isRunning else { return }
                statusMessage = AppText.checkingSpeechPermission
                try await startCaptioners()
                guard !Task.isCancelled, isRunning else {
                    stopCaptioners()
                    return
                }
                statusMessage = AppText.startingCapture(for: audioInputSource)
                let usesOpenAIRealtimeAudio = openAITranscriptionModel.isEnabled
                    || openAITranslationModel.usesRealtimeAudioTranslation
                let sampleRate = usesOpenAIRealtimeAudio ? 24_000 : 16_000
                switch audioInputSource {
                case .systemAudio:
                    try await systemAudioCapture.start(sampleRate: sampleRate)
                case .microphone:
                    try await microphoneAudioCapture.start(
                        sampleRate: sampleRate,
                        deviceUniqueID: selectedMicrophoneDevice.uniqueID
                    )
                }
                guard !Task.isCancelled, isRunning else {
                    await stopCapture()
                    stopCaptioners()
                    return
                }
                statusMessage = AppText.listeningForSpeech(from: audioInputSource)
                warmTranslationSession()
            } catch {
                guard !Task.isCancelled else { return }
                isRunning = false
                stopCaptioners()
                await stopCapture()
                statusMessage = AppText.startFailed(error.localizedDescription)
            }
        }
    }

    func stop() {
        guard isRunning else { return }

        captureStartTask?.cancel()
        captureStartTask = nil
        flushPendingCaptionPresentation()
        let didSaveTranscript = flushPendingTranscriptSave()
        resetLiveSessionState(clearsVisibleLines: false)
        isPaused = false
        setCaptionersPaused(false)
        isRunning = false
        statusMessage = AppText.stopped
        stopCaptioners()
        if didSaveTranscript {
            showToast(AppText.transcriptSavedToast)
        }

        Task {
            await stopCapture()
        }
    }

    func pause() {
        guard isRunning, !isPaused else { return }

        flushPendingCaptionPresentation()
        transcriptCleanupTask?.cancel()
        transcriptCleanupTask = nil
        commitCurrentPartial()
        organizeCurrentTranscript(sourceTextOverride: visibleTranscript())
        setCaptionersPaused(true)
        isPaused = true
        statusMessage = AppText.paused
    }

    func resume() {
        guard isRunning, isPaused else { return }
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
            await appendCaption(
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
        flushPendingCaptionPresentation()
        _ = flushPendingTranscriptSave()
    }

    func openPrivacySettings() {
        let privacyPane = audioInputSource == .microphone ? "Privacy_Microphone" : "Privacy_ScreenCapture"
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(privacyPane)") else {
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

    @discardableResult
    func saveOpenAIAPIKey(_ key: String) -> Bool {
        do {
            try OpenAIAPIKeyStore.saveAPIKey(key)
            hasOpenAIAPIKey = true
            statusMessage = AppText.openAIAPIKeySaved
            refreshModelAvailability()
            return true
        } catch {
            statusMessage = error.localizedDescription
            return false
        }
    }

    func removeOpenAIAPIKey() {
        do {
            try OpenAIAPIKeyStore.deleteAPIKey()
            hasOpenAIAPIKey = false
            statusMessage = AppText.openAIAPIKeyRemoved
            refreshModelAvailability()
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    @discardableResult
    func saveAzureOpenAIConfig(endpoint: String, apiKey: String) -> Bool {
        do {
            try AzureOpenAIConfigStore.saveConfig(endpoint: endpoint, apiKey: apiKey)
            hasAzureOpenAIConfig = AzureOpenAIConfigStore.hasConfig()
            azureOpenAIEndpoint = AzureOpenAIConfigStore.readEndpoint() ?? ""
            statusMessage = AppText.azureOpenAIConfigSaved
            refreshModelAvailability()
            return true
        } catch {
            statusMessage = error.localizedDescription
            return false
        }
    }

    func removeAzureOpenAIConfig() {
        do {
            try AzureOpenAIConfigStore.deleteConfig()
            hasAzureOpenAIConfig = false
            azureOpenAIEndpoint = ""
            statusMessage = AppText.azureOpenAIConfigRemoved
            refreshModelAvailability()
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    var hasOpenAIRealtimeCredentials: Bool {
        switch openAIProvider {
        case .openAI: hasOpenAIAPIKey
        case .azure: hasAzureOpenAIConfig
        }
    }

    private func resolveOpenAIRealtimeProviderConfig() throws -> OpenAIRealtimeProviderConfig {
        switch openAIProvider {
        case .openAI:
            guard let key = try OpenAIAPIKeyStore.readAPIKey(), !key.isEmpty else {
                throw OpenAITranslationError.missingAPIKey
            }
            return .openAI(apiKey: key)
        case .azure:
            guard let endpoint = AzureOpenAIConfigStore.readEndpoint(),
                  let host = AzureOpenAIEndpoint.host(from: endpoint) else {
                throw OpenAITranslationError.missingAzureEndpoint
            }
            guard let key = try AzureOpenAIConfigStore.readAPIKey(), !key.isEmpty else {
                throw OpenAITranslationError.missingAzureAPIKey
            }
            return .azure(host: host, apiKey: key)
        }
    }

    private func resolvedCustomTranscriptionModelName() -> String? {
        guard openAIProvider == .azure else { return nil }
        let value = customAzureTranscriptionModelName
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private func resolvedCustomTranslationModelName() -> String? {
        guard openAIProvider == .azure else { return nil }
        let value = customAzureTranslationModelName
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
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

    func useAppleDefaultMode() {
        selectedModel = .appleSystem
        openAITranscriptionModel = .off
        openAITranslationModel = .off
    }

    func useGPTRealtimeMode() {
        selectedModel = .appleSystem
        isTranscriptLintEnabled = false
        if !openAITranscriptionModel.isEnabled {
            openAITranscriptionModel = .gptRealtimeWhisper
        }
        if !openAITranslationModel.isEnabled {
            openAITranslationModel = .gptRealtimeTranslate
        }
        usePreferredLanguageForOpenAIOutput()
    }

    func modelAvailability(for model: IntelligenceModel) -> ModelAvailability {
        modelAvailabilityByModelID[model.id] ?? ModelAvailability.checking(for: model)
    }

    func downloadModelAssets(for model: IntelligenceModel) {
        guard modelAvailability(for: model).state.canDownload else { return }

        let sourceLanguage = sourceLanguage
        let targetLanguage = targetLanguage
        modelAvailabilityByModelID[model.id] = ModelAvailability(
            state: .downloading,
            detail: model.detail
        )

        Task { @MainActor in
            do {
                try await ModelAvailabilityChecker.downloadAssets(
                    for: model,
                    source: sourceLanguage,
                    target: targetLanguage
                )
                refreshModelAvailability()
            } catch {
                modelAvailabilityByModelID[model.id] = ModelAvailability(
                    state: .failed,
                    detail: error.localizedDescription
                )
            }
        }
    }

    var floatingSourceText: String {
        let displayText = floatingPresentedSourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !displayText.isEmpty {
            return floatingCaptionText(from: displayText)
        }

        let liveDisplayText = floatingVisibleSourceTranscript()
        if !liveDisplayText.isEmpty {
            return floatingCaptionText(from: liveDisplayText)
        }

        return floatingCaptionText(from: lines.last?.sourceText)
    }

    var floatingTranslationText: String {
        let displaySourceText = floatingPresentedSourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !displaySourceText.isEmpty {
            let translatedText = floatingDisplayTranslationText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !translatedText.isEmpty, translatedText != AppText.translating else {
                return ""
            }
            guard floatingDisplayTranslationSourceText.isEmpty
                || translationSource(floatingDisplayTranslationSourceText, matches: displaySourceText)
            else {
                return ""
            }

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

    var selectedSavedTranscript: SavedTranscript? {
        guard let selectedSavedTranscriptID else { return nil }
        return savedTranscripts.first { $0.id == selectedSavedTranscriptID }
    }

    func selectSavedTranscript(_ id: String) {
        guard let transcript = savedTranscripts.first(where: { $0.id == id }) else { return }

        selectedSavedTranscriptID = id
        savedDraftSourceText = transcript.sourceText
        savedDraftTranslationText = transcript.translatedText ?? ""
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
        } catch {
            statusMessage = AppText.saveLibraryFailed(error.localizedDescription)
        }
    }

    private func startCaptioners() async throws {
        stopCaptioners()
        transcriber = LiveSpeechTranscriber()
        transcriber.delegate = self
        openAITranscriber = OpenAIRealtimeTranscriber()
        openAITranscriber.delegate = self

        let customTranscription = resolvedCustomTranscriptionModelName()
        let customTranslation = resolvedCustomTranslationModelName()

        if openAITranslationModel.usesRealtimeAudioTranslation {
            let providerConfig = try resolveOpenAIRealtimeProviderConfig()
            try await openAITranscriber.startRealtimeTranslationOnly(
                language: targetLanguage,
                model: openAITranslationModel,
                modelIDOverride: customTranslation,
                providerConfig: providerConfig
            )
        } else if openAITranscriptionModel.isEnabled {
            let providerConfig = try resolveOpenAIRealtimeProviderConfig()
            try await openAITranscriber.start(
                language: sourceLanguage,
                model: openAITranscriptionModel,
                modelIDOverride: customTranscription,
                providerConfig: providerConfig
            )
        } else {
            try await transcriber.start(languages: await appleSpeechLanguagesForCurrentMode())
        }
    }

    private func appleSpeechLanguagesForCurrentMode() async -> [LanguageOption] {
        guard isUsingAppleSourceAutoDetection else { return [sourceLanguage] }

        let candidates = prioritizedAutoDetectionLanguages()
        let installedCandidates = await LiveSpeechTranscriber.installedSupportedLanguages(from: candidates)
        let selectedCandidates = installedCandidates.isEmpty
            ? [candidates.first ?? sourceLanguage]
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

    private func stopCaptioners() {
        transcriber.delegate = nil
        openAITranscriber.delegate = nil
        transcriber.stop()
        openAITranscriber.stop()
    }

    private func setCaptionersPaused(_ isPaused: Bool) {
        transcriber.setPaused(isPaused)
        openAITranscriber.setPaused(isPaused)
    }

    private func resetLiveSessionState(clearsVisibleLines: Bool) {
        audioSampleCount = 0
        latestAudioLevel = nil
        lastRecognizedText = ""
        lastRecognizedWasFinal = false
        currentLineID = nil
        lastCaptionPresentationUpdateAt = Date.distantPast
        pendingCaptionPresentation = nil
        captionPresentationTask?.cancel()
        captionPresentationTask = nil
        committedSourceText = ""
        currentPartialText = ""
        currentPartialLanguage = nil
        appleAutoDetectionPreferredLanguage = nil
        pendingAutoDetectionLanguageChange = nil
        pendingParagraphBreakBeforePartial = false
        floatingPresentationTask?.cancel()
        floatingPresentationTask = nil
        if clearsVisibleLines {
            sourceLanguageByLineID.removeAll()
            floatingCommittedSourceText = ""
            floatingCurrentPartialText = ""
            pendingFloatingParagraphBreakBeforePartial = false
            floatingPresentedSourceText = ""
            floatingQueuedSourceText = ""
            floatingPresentedAt = Date.distantPast
            floatingDisplayTranslationText = ""
            floatingDisplayTranslationSourceText = ""
            floatingQueuedTranslationText = ""
            floatingQueuedTranslationSourceText = ""
        } else {
            rehydrateFloatingCaptionDisplayFromCurrentLine()
        }
        pendingTranslationSourceText = ""
        latestTranslationRequest = nil
        translationBurstStartedAt = Date.distantPast
        resetTranslationCache()
        realtimeTranslationOnlyText = ""
        activeAutosaveSourceText = ""
        activeAutosaveTranslatedText = ""
        stopSpeaking()
        lastSpokenTranslatedText = ""
        clearSpokenTranslationUnits()
        translationTask?.cancel()
        translationTask = nil
        transcriptCleanupTask?.cancel()
        transcriptCleanupTask = nil

        if clearsVisibleLines {
            lines.removeAll()
        }
    }

    private func warmTranslationSession() {
        guard !openAITranslationModel.isEnabled else { return }

        let warmSourceLanguage = sourceLanguage
        let warmTargetLanguage = targetLanguage
        let warmSelectedModel = selectedModel

        Task { @MainActor in
            do {
                try await translator.prepare(
                    source: warmSourceLanguage,
                    target: warmTargetLanguage,
                    model: warmSelectedModel
                )
            } catch {
                statusMessage = error.localizedDescription
            }
        }
    }

    func refreshModelAvailability() {
        let sourceLanguage = sourceLanguage
        let targetLanguage = targetLanguage

        modelAvailabilityTask?.cancel()
        modelAvailabilityByModelID = Dictionary(
            uniqueKeysWithValues: IntelligenceModel.allCases.map {
                ($0.id, ModelAvailability.checking(for: $0))
            }
        )

        modelAvailabilityTask = Task { [weak self, sourceLanguage, targetLanguage] in
            let availabilityByModelID = await ModelAvailabilityChecker.availability(
                source: sourceLanguage,
                target: targetLanguage
            )
            guard !Task.isCancelled else { return }

            await MainActor.run {
                self?.modelAvailabilityByModelID = availabilityByModelID
            }
        }
    }

    private func restoreSelectedSettings() {
        isRestoringSelectedSettings = true
        defer { isRestoringSelectedSettings = false }

        let defaults = UserDefaults.standard
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
        if let modelID = defaults.string(forKey: SettingsKey.openAITranslationModelID),
           let model = OpenAIRealtimeTranslationModel(rawValue: modelID) {
            openAITranslationModel = model
        }
        if defaults.object(forKey: SettingsKey.isDubbingEnabled) != nil {
            isDubbingEnabled = defaults.bool(forKey: SettingsKey.isDubbingEnabled)
        }
        if defaults.object(forKey: SettingsKey.isTranscriptLintEnabled) != nil {
            isTranscriptLintEnabled = defaults.bool(forKey: SettingsKey.isTranscriptLintEnabled)
        }
        if let modeID = defaults.string(forKey: SettingsKey.floatingCaptionDisplayMode),
           let mode = FloatingCaptionDisplayMode(rawValue: modeID) {
            floatingCaptionDisplayMode = mode
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
        if let alignmentID = defaults.string(forKey: SettingsKey.floatingCaptionTextAlignment),
           let alignment = FloatingCaptionTextAlignment(rawValue: alignmentID) {
            floatingCaptionTextAlignment = alignment
        }
        if defaults.object(forKey: SettingsKey.isFloatingCaptionImmediateDisplayEnabled) != nil {
            isFloatingCaptionImmediateDisplayEnabled = defaults.bool(
                forKey: SettingsKey.isFloatingCaptionImmediateDisplayEnabled
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
        if let providerID = defaults.string(forKey: SettingsKey.openAIProvider),
           let provider = OpenAIProvider(rawValue: providerID) {
            openAIProvider = provider
        }
        if let value = defaults.string(forKey: SettingsKey.customAzureTranscriptionModelName) {
            customAzureTranscriptionModelName = value
        }
        if let value = defaults.string(forKey: SettingsKey.customAzureTranslationModelName) {
            customAzureTranslationModelName = value
        }
        refreshMicrophoneInputDevices()
    }

    private func persistSelectedSettings() {
        guard !isRestoringSelectedSettings else { return }

        let defaults = UserDefaults.standard
        defaults.set(sourceLanguage.id, forKey: SettingsKey.sourceLanguageID)
        defaults.set(targetLanguage.id, forKey: SettingsKey.targetLanguageID)
        defaults.set(selectedModel.id, forKey: SettingsKey.selectedModelID)
        defaults.set(openAITranscriptionModel.id, forKey: SettingsKey.openAITranscriptionModelID)
        defaults.set(openAITranslationModel.id, forKey: SettingsKey.openAITranslationModelID)
        defaults.set(isDubbingEnabled, forKey: SettingsKey.isDubbingEnabled)
        defaults.set(isTranscriptLintEnabled, forKey: SettingsKey.isTranscriptLintEnabled)
        defaults.set(floatingCaptionDisplayMode.id, forKey: SettingsKey.floatingCaptionDisplayMode)
        defaults.set(floatingCaptionTextSize.id, forKey: SettingsKey.floatingCaptionTextSize)
        defaults.set(floatingCaptionLineCount.id, forKey: SettingsKey.floatingCaptionLineCount)
        defaults.set(floatingCaptionTextAlignment.id, forKey: SettingsKey.floatingCaptionTextAlignment)
        defaults.set(
            isFloatingCaptionImmediateDisplayEnabled,
            forKey: SettingsKey.isFloatingCaptionImmediateDisplayEnabled
        )
        defaults.set(paragraphBreakSilenceInterval, forKey: SettingsKey.paragraphBreakSilenceInterval)
        defaults.set(savedTranscriptContentMode.id, forKey: SettingsKey.savedTranscriptContentMode)
        defaults.set(sessionDurationMode.id, forKey: SettingsKey.sessionDurationMode)
        defaults.set(audioInputSource.id, forKey: SettingsKey.audioInputSource)
        defaults.set(selectedMicrophoneInputDeviceID, forKey: SettingsKey.selectedMicrophoneInputDeviceID)
        defaults.set(isAppleSourceAutoDetectionEnabled, forKey: SettingsKey.isAppleSourceAutoDetectionEnabled)
        defaults.set(openAIProvider.rawValue, forKey: SettingsKey.openAIProvider)
        defaults.set(customAzureTranscriptionModelName, forKey: SettingsKey.customAzureTranscriptionModelName)
        defaults.set(customAzureTranslationModelName, forKey: SettingsKey.customAzureTranslationModelName)
    }

    private func stopCapture() async {
        await systemAudioCapture.stop()
        microphoneAudioCapture.delegate = nil
        microphoneAudioCapture.stop()
        microphoneAudioCapture = MicrophoneAudioCapture()
        microphoneAudioCapture.delegate = self
    }

    private func floatingCaptionText(from text: String?) -> String {
        guard let text else { return "" }

        return text.floatingCaptionTail(maxLines: floatingCaptionLineCount.rawValue)
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
                    guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else {
                        return nil
                    }
                    let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey])
                    return SavedTranscriptFile(
                        fileName: fileURL.lastPathComponent,
                        text: text.trimmingCharacters(in: .whitespacesAndNewlines),
                        updatedAt: values?.contentModificationDate ?? Date.distantPast
                    )
                }
            savedTranscripts = groupedSavedTranscripts(from: transcriptFiles)
            sortSavedTranscripts()
        } catch {
            savedTranscripts = []
        }
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
                        sourceText: file.text,
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
                        sourceText: original.text,
                        translatedText: translation.text,
                        updatedAt: max(original.updatedAt, translation.updatedAt)
                    )
                )
            } else if let original = partial.original {
                standaloneTranscripts.append(
                    SavedTranscript(
                        fileName: original.fileName,
                        sourceText: original.text,
                        updatedAt: original.updatedAt
                    )
                )
            } else if let translation = partial.translation {
                standaloneTranscripts.append(
                    SavedTranscript(
                        fileName: translation.fileName,
                        sourceText: translation.text,
                        updatedAt: translation.updatedAt
                    )
                )
            }
        }

        return standaloneTranscripts
    }

    private func stageTranscriptForSave(_ sourceText: String, translatedText: String? = nil) {
        let sourceText = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sourceText.isEmpty else { return }

        activeAutosaveSourceText = sourceText
        if let translatedText {
            let translatedText = translatedText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !translatedText.isEmpty, translatedText != AppText.translating {
                activeAutosaveTranslatedText = translatedText
            }
        }
    }

    @discardableResult
    private func flushPendingTranscriptSave() -> Bool {
        let currentSourceText = visibleTranscript().trimmingCharacters(in: .whitespacesAndNewlines)
        if !currentSourceText.isEmpty {
            activeAutosaveSourceText = currentSourceText
        }

        let sourceText = activeAutosaveSourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sourceText.isEmpty else { return false }

        let updatedAt = Date()
        let baseFileName = makeTranscriptFileName(for: sourceText, date: updatedAt)
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

        activeAutosaveSourceText = ""
        activeAutosaveTranslatedText = ""
        loadSavedTranscripts()
        return true
    }

    private func savedTranscriptFiles(
        sourceText: String,
        translatedText: String,
        baseFileName: String
    ) -> [(fileName: String, text: String)] {
        let sourceText = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        let translatedText = translatedText.trimmingCharacters(in: .whitespacesAndNewlines)

        switch savedTranscriptContentMode {
        case .original:
            return [(baseFileName, sourceText)]
        case .translation:
            return [(baseFileName, translatedText.isEmpty ? sourceText : translatedText)]
        case .originalAndTranslation:
            guard !translatedText.isEmpty else {
                return [(baseFileName, sourceText)]
            }

            return [
                (transcriptVariantFileName(baseFileName, suffix: "original"), sourceText),
                (transcriptVariantFileName(baseFileName, suffix: "translation"), translatedText)
            ]
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
        isFinal: Bool
    ) async {
        guard isRunning, !isPaused else { return }
        guard sourceText != lastRecognizedText || isFinal != lastRecognizedWasFinal else { return }

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

        let updatedSourceText = accumulatedTranscript(
            incoming: sourceText,
            hadLongSilence: hadLongSilence,
            isFinal: isFinal,
            language: direction.source
        )
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
            guard updatedSourceText != existingLine.sourceText || sourceLanguageChanged else { return }
            if sourceLanguageChanged, updatedSourceText == existingLine.sourceText {
                pendingTranslationSourceText = ""
                requestTranslation(for: existingLine, source: direction.source, target: direction.target)
                return
            }

            if shouldPresentCaptionUpdate(sourceText: updatedSourceText, isFinal: isFinal) {
                clearPendingCaptionPresentation()
                presentCaptionLineUpdate(
                    lineID: existingLine.id,
                    sourceText: updatedSourceText,
                    isFinal: isFinal,
                    source: direction.source,
                    target: direction.target
                )
            } else {
                scheduleCaptionPresentation(
                    lineID: existingLine.id,
                    sourceText: updatedSourceText,
                    isFinal: isFinal,
                    source: direction.source,
                    target: direction.target
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
            lines.append(line)
            lastCaptionPresentationUpdateAt = Date()
            stageTranscriptForSave(line.sourceText)
            requestTranslation(for: line, source: direction.source, target: direction.target)
        }
    }

    private var currentAutoDetectedSourceLanguage: LanguageOption? {
        if let currentPartialLanguage {
            return currentPartialLanguage
        }

        if let currentLineID,
           let lineLanguage = sourceLanguageByLineID[currentLineID] {
            return lineLanguage
        }

        return nil
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
        isPaused = true
        statusMessage = AppText.autoDetectionLanguageChangePaused(
            current: currentLanguage.localizedTitle,
            detected: detectedLanguage.localizedTitle
        )
    }

    private func shouldPresentCaptionUpdate(sourceText: String, isFinal: Bool) -> Bool {
        guard usesLongSessionMode else { return true }

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
        target: LanguageOption
    ) {
        pendingCaptionPresentation = PendingCaptionPresentation(
            lineID: lineID,
            sourceText: sourceText,
            isFinal: isFinal,
            source: source,
            target: target
        )
        captionPresentationTask?.cancel()

        let elapsed = Date().timeIntervalSince(lastCaptionPresentationUpdateAt)
        let delay = max(0, Self.largeTranscriptPresentationInterval - elapsed)
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
        presentCaptionLineUpdate(
            lineID: pendingCaptionPresentation.lineID,
            sourceText: pendingCaptionPresentation.sourceText,
            isFinal: pendingCaptionPresentation.isFinal,
            source: pendingCaptionPresentation.source,
            target: pendingCaptionPresentation.target
        )
    }

    private func clearPendingCaptionPresentation() {
        pendingCaptionPresentation = nil
        captionPresentationTask?.cancel()
        captionPresentationTask = nil
    }

    private func presentCaptionLineUpdate(
        lineID: UUID,
        sourceText: String,
        isFinal: Bool,
        source: LanguageOption,
        target: LanguageOption
    ) {
        guard let index = lines.firstIndex(where: { $0.id == lineID }) else { return }

        let existingLine = lines[index]
        guard sourceText != existingLine.sourceText || isFinal != existingLine.isFinal else { return }

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
        lastCaptionPresentationUpdateAt = Date()
        stageTranscriptForSave(line.sourceText)
        requestTranslation(for: line, source: source, target: target)
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
            commitCurrentPartial()
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
            commitCurrentPartial()
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

        commitCurrentPartial()
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
           TranscriptTextProcessor.committedTranscriptAlreadyMatches(incoming, in: committedSourceText) {
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
            committedText: committedSourceText,
            languageID: language.id
        ) else {
            return nil
        }

        committedSourceText = replay.committedText
        return replay.tailText
    }

    private func incomingTailAfterCommittedText(
        _ incoming: String,
        allowsCommittedReplay: Bool
    ) -> String? {
        TranscriptTextProcessor.incomingTailAfterCommittedText(
            incoming,
            committedText: committedSourceText,
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

    private func commitCurrentPartial() {
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
            floatingDisplayTranslationText = ""
            floatingDisplayTranslationSourceText = ""
            floatingQueuedTranslationText = ""
            floatingQueuedTranslationSourceText = ""
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
    }

    private func refreshFloatingCaptionPresentation() {
        let candidate = floatingVisibleSourceTranscript()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty else { return }

        if floatingPresentedSourceText.isEmpty {
            presentFloatingSourceText(candidate)
            return
        }

        if FloatingCaptionPresentationPolicy.canPresentUpdate(
            isImmediateDisplayEnabled: isFloatingCaptionImmediateDisplayEnabled,
            presentedText: floatingPresentedSourceText,
            translatedText: floatingDisplayTranslationText,
            candidateText: candidate,
            presentedAt: floatingPresentedAt
        ) {
            presentFloatingSourceText(candidate)
            return
        }

        floatingQueuedSourceText = candidate
        scheduleFloatingPresentationAdvance()
    }

    private func canAdvanceFloatingPresentation(now: Date = Date()) -> Bool {
        FloatingCaptionPresentationPolicy.canAdvance(
            isImmediateDisplayEnabled: isFloatingCaptionImmediateDisplayEnabled,
            presentedText: floatingPresentedSourceText,
            translatedText: floatingDisplayTranslationText,
            presentedAt: floatingPresentedAt,
            now: now
        )
    }

    private func floatingCaptionDwellDuration() -> TimeInterval {
        FloatingCaptionPresentationPolicy.dwellDuration(
            presentedText: floatingPresentedSourceText,
            translatedText: floatingDisplayTranslationText
        )
    }

    private func presentFloatingSourceText(_ text: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        floatingPresentedSourceText = text
        floatingQueuedSourceText = ""
        floatingPresentedAt = Date()
        if !floatingDisplayTranslationSourceText.isEmpty,
           !translationSource(floatingDisplayTranslationSourceText, matches: text) {
            floatingDisplayTranslationText = ""
            floatingDisplayTranslationSourceText = ""
        }
        promoteQueuedFloatingTranslationIfPossible()
    }

    private func scheduleFloatingPresentationAdvance() {
        floatingPresentationTask?.cancel()

        let remaining = max(
            0.05,
            floatingCaptionDwellDuration() - Date().timeIntervalSince(floatingPresentedAt)
        )
        let delayMilliseconds = max(50, Int(remaining * 1_000))
        floatingPresentationTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(delayMilliseconds))
            promoteQueuedFloatingPresentationIfReady()
        }
    }

    private func promoteQueuedFloatingPresentationIfReady() {
        guard canAdvanceFloatingPresentation() else {
            scheduleFloatingPresentationAdvance()
            return
        }

        if !floatingQueuedSourceText.isEmpty {
            presentFloatingSourceText(floatingQueuedSourceText)
        } else {
            promoteQueuedFloatingTranslationIfPossible()
        }

        if !floatingQueuedSourceText.isEmpty || !floatingQueuedTranslationText.isEmpty {
            scheduleFloatingPresentationAdvance()
        } else {
            floatingPresentationTask = nil
        }
    }

    private func replaceCommittedUnitsIfRevision(
        with text: String,
        language: LanguageOption,
        allowsBackfill: Bool
    ) -> Bool {
        guard let updatedText = TranscriptTextProcessor.committedTextByReplacingRevision(
            with: text,
            committedText: committedSourceText,
            languageID: language.id,
            allowsBackfill: allowsBackfill
        ) else {
            return false
        }

        committedSourceText = updatedText
        return true
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

        transcriptCleanupTask?.cancel()
        transcriptCleanupTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(700))
            organizeCurrentTranscript()
        }
    }

    private func organizeCurrentTranscript(sourceTextOverride: String? = nil) {
        guard !isUsingOpenAIRealtime else { return }

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
        target: LanguageOption
    ) async throws -> String {
        let paragraphs = paragraphParts(from: text)

        guard !paragraphs.isEmpty else { return "" }

        var translatedParagraphs: [String] = []
        for paragraph in paragraphs {
            let segments = paragraph
                .split(separator: "\n", omittingEmptySubsequences: true)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            var translatedSegments: [String] = []

            for segment in segments {
                try Task.checkCancellation()
                let cacheKey = translationCacheKey(segment: segment, source: source, target: target)
                if let cachedSegment = translatedSegmentsBySource[cacheKey] {
                    rememberTranslationCacheKey(cacheKey)
                    translatedSegments.append(cachedSegment)
                    continue
                }

                let translatedSegment: String
                if openAITranslationModel.isEnabled && !openAITranslationModel.usesRealtimeAudioTranslation {
                    translatedSegment = try await openAITranslator.translate(
                        segment,
                        source: source,
                        target: target,
                        model: openAITranslationModel
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
            }

            translatedParagraphs.append(translatedSegments.joined(separator: "\n"))
        }

        return translatedParagraphs.joined(separator: "\n\n")
    }

    private func translationCacheKey(segment: String, source: LanguageOption, target: LanguageOption) -> String {
        "\(source.id)\t\(target.id)\t\(selectedModel.id)\t\(segment)"
    }

    private func cacheTranslatedSegment(_ segment: String, forKey key: String) {
        translatedSegmentsBySource[key] = segment
        rememberTranslationCacheKey(key)

        while translationCacheKeyOrder.count > Self.maxTranslationCacheEntries {
            let removedKey = translationCacheKeyOrder.removeFirst()
            if !translationCacheKeyOrder.contains(removedKey) {
                translatedSegmentsBySource.removeValue(forKey: removedKey)
            }
        }
    }

    private func rememberTranslationCacheKey(_ key: String) {
        translationCacheKeyOrder.removeAll { $0 == key }
        translationCacheKeyOrder.append(key)
    }

    private func resetTranslationCache() {
        translatedSegmentsBySource.removeAll()
        translationCacheKeyOrder.removeAll()
    }

    private func appendRealtimeTranslationOnly(_ text: String) {
        guard isRunning, !isPaused else { return }

        guard text.rangeOfCharacter(from: .whitespacesAndNewlines.inverted) != nil
            || !realtimeTranslationOnlyText.isEmpty else { return }

        if text.hasPrefix(realtimeTranslationOnlyText) {
            realtimeTranslationOnlyText = text
        } else if !realtimeTranslationOnlyText.hasSuffix(text) {
            realtimeTranslationOnlyText += text
        }

        let translatedText = realtimeTranslationOnlyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !translatedText.isEmpty else { return }

        lastRecognizedText = translatedText
        lastRecognitionAt = Date()
        transcriptCleanupTask?.cancel()

        let sourceText = AppText.openAIRealtimeTranslationOnlySource

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
            lines.append(line)
        }

        stageTranscriptForSave(sourceText, translatedText: translatedText)
        let floatingTranslatedText = isUsingOpenAIRealtimeTranslation
            ? text.trimmingCharacters(in: .whitespacesAndNewlines)
            : translatedText
        updateFloatingTranslationPresentation(floatingTranslatedText, sourceText: sourceText)
        speakTranslatedDeltaIfNeeded(translatedText)
    }

    private func requestTranslation(for line: CaptionLine, source: LanguageOption, target: LanguageOption) {
        guard !openAITranslationModel.usesRealtimeAudioTranslation else { return }

        guard selectedModel != .appleSpeechOnly else {
            markTranslationUnavailable(
                AppText.translationDisabledForSpeechOnly,
                for: line,
                matching: line.sourceText
            )
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
        guard pendingTranslationSourceText != sourceText else { return }
        let translationSourceText = translationSourceText(for: sourceText, language: source)
        pendingTranslationSourceText = sourceText
        if latestTranslationRequest == nil {
            translationBurstStartedAt = Date()
        }
        latestTranslationRequest = TranslationRequest(
            line: line,
            sourceText: sourceText,
            translationSourceText: translationSourceText,
            source: source,
            target: target
        )

        guard translationTask == nil else {
            return
        }

        translationTask = Task { @MainActor in
            await processPendingTranslationRequests()
        }
    }

    private func processPendingTranslationRequests() async {
        while !Task.isCancelled, let request = latestTranslationRequest {
            latestTranslationRequest = nil

            do {
                let delay = translationDebounceDelay(for: request.sourceText)
                if delay > 0 {
                    try await Task.sleep(for: .milliseconds(delay))
                }

                if latestTranslationRequest != nil {
                    continue
                }

                translationBurstStartedAt = .distantPast
                let translatedText = try await translateTranscript(
                    request.translationSourceText,
                    source: request.source,
                    target: request.target
                )
                try Task.checkCancellation()
                updateTranslation(translatedText, for: request.line, matching: request.sourceText)
            } catch is CancellationError {
                translationTask = nil
                return
            } catch {
                if pendingTranslationSourceText == request.sourceText {
                    pendingTranslationSourceText = ""
                }
                markTranslationUnavailable(error.localizedDescription, for: request.line, matching: request.sourceText)
            }
        }

        translationTask = nil
    }

    private func translationSourceText(for sourceText: String, language: LanguageOption) -> String {
        guard usesLongSessionMode, !isUsingOpenAIRealtime else { return sourceText }

        let organizedSourceText = organizeTranscript(sourceText, language: language)
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

    private func updateTranslation(_ translatedText: String, for line: CaptionLine, matching sourceText: String) {
        guard let index = lines.firstIndex(where: { $0.id == line.id }) else { return }
        guard lines[index].sourceText == sourceText else {
            if pendingTranslationSourceText == sourceText {
                pendingTranslationSourceText = ""
            }
            return
        }
        let organizedTranslatedText = organizeTranscript(translatedText, language: targetLanguage)
        let floatingTranslatedText = translatedText.trimmingCharacters(in: .whitespacesAndNewlines)
        if pendingTranslationSourceText == sourceText {
            pendingTranslationSourceText = ""
        }
        stageTranscriptForSave(sourceText, translatedText: organizedTranslatedText)

        lines[index] = CaptionLine(
            id: line.id,
            sourceText: sourceText,
            translatedText: organizedTranslatedText,
            translatedSourceText: sourceText,
            createdAt: line.createdAt,
            isFinal: line.isFinal,
            revision: lines[index].revision + 1,
            usesLongSessionDisplay: usesLongSessionMode
        )

        updateFloatingTranslationPresentation(floatingTranslatedText, sourceText: sourceText)
        speakTranslatedDeltaIfNeeded(organizedTranslatedText)
    }

    private func markTranslationUnavailable(_ message: String, for line: CaptionLine, matching sourceText: String) {
        guard let index = lines.firstIndex(where: { $0.id == line.id }) else {
            statusMessage = message
            return
        }
        guard lines[index].sourceText == sourceText else {
            statusMessage = message
            return
        }

        if pendingTranslationSourceText == sourceText {
            pendingTranslationSourceText = ""
        }

        lines[index] = CaptionLine(
            id: line.id,
            sourceText: sourceText,
            translatedText: message,
            translatedSourceText: sourceText,
            createdAt: line.createdAt,
            isFinal: line.isFinal,
            revision: lines[index].revision + 1,
            usesLongSessionDisplay: usesLongSessionMode
        )
        updateFloatingTranslationPresentation(message, sourceText: sourceText)
        statusMessage = message
    }

    private func updateFloatingTranslationPresentation(_ translatedText: String, sourceText: String) {
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
            if floatingDisplayTranslationText.isEmpty || canAdvanceFloatingPresentation() {
                floatingDisplayTranslationText = displayTranslatedText
                floatingDisplayTranslationSourceText = displaySourceText
            } else {
                floatingQueuedTranslationText = displayTranslatedText
                floatingQueuedTranslationSourceText = displaySourceText
                scheduleFloatingPresentationAdvance()
            }
            return
        }

        if shouldUpdateQueuedFloatingTranslationDisplay(for: displaySourceText) {
            floatingQueuedTranslationText = displayTranslatedText
            floatingQueuedTranslationSourceText = displaySourceText
            scheduleFloatingPresentationAdvance()
        }
    }

    private func promoteQueuedFloatingTranslationIfPossible() {
        guard !floatingQueuedTranslationText.isEmpty else { return }
        guard shouldUpdateFloatingTranslationDisplay(for: floatingQueuedTranslationSourceText) else {
            if floatingQueuedSourceText.isEmpty {
                floatingQueuedTranslationText = ""
                floatingQueuedTranslationSourceText = ""
            }
            return
        }

        floatingDisplayTranslationText = floatingQueuedTranslationText
        floatingDisplayTranslationSourceText = floatingQueuedTranslationSourceText
        floatingQueuedTranslationText = ""
        floatingQueuedTranslationSourceText = ""
    }

    private func shouldUpdateFloatingTranslationDisplay(for sourceText: String) -> Bool {
        translationSource(sourceText, matches: floatingPresentedSourceText)
    }

    private func shouldUpdateQueuedFloatingTranslationDisplay(for sourceText: String) -> Bool {
        translationSource(sourceText, matches: floatingQueuedSourceText)
    }

    private func translationSource(_ sourceText: String, matches displaySourceText: String) -> Bool {
        guard !displaySourceText.isEmpty else { return false }

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

    private func speakTranslatedDeltaIfNeeded(_ translatedText: String) {
        guard isRunning, isDubbingEnabled else { return }
        guard !openAITranslationModel.usesRealtimeAudioTranslation else { return }

        let currentText = speechReadyText(translatedText)
        guard !currentText.isEmpty else { return }

        let previousText = lastSpokenTranslatedText
        lastSpokenTranslatedText = currentText

        guard let delta = speechDelta(previous: previousText, current: currentText),
              let unspokenDelta = unspokenSpeechText(from: delta)
        else {
            return
        }

        speak(unspokenDelta)
    }

    private func speechReadyText(_ text: String) -> String {
        guard text != AppText.translating else { return "" }

        return text
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func speechDelta(previous: String, current: String) -> String? {
        guard previous != current else { return nil }
        guard !current.isEmpty else { return nil }

        if previous.isEmpty {
            return current
        }

        if current.hasPrefix(previous) {
            return speakableText(String(current.dropFirst(previous.count)))
        }

        let sharedPrefixLength = commonPrefixLength(previous, current)
        if sharedPrefixLength > previous.count / 2 {
            return speakableText(String(current.dropFirst(sharedPrefixLength)))
        }

        return nil
    }

    private func commonPrefixLength(_ lhs: String, _ rhs: String) -> Int {
        var length = 0
        for (leftCharacter, rightCharacter) in zip(lhs, rhs) {
            guard leftCharacter == rightCharacter else { break }
            length += 1
        }
        return length
    }

    private func speakableText(_ text: String) -> String? {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedText.rangeOfCharacter(from: .letters.union(.decimalDigits)) != nil else {
            return nil
        }
        return trimmedText
    }

    private func unspokenSpeechText(from text: String) -> String? {
        let units = speechUnits(from: text)
        guard !units.isEmpty else { return nil }

        var unspokenUnits: [String] = []
        for unit in units {
            let key = normalizedSpeechUnitKey(unit)
            guard !key.isEmpty, !spokenTranslationUnitKeys.contains(key) else {
                continue
            }

            rememberSpokenTranslationUnitKey(key)
            unspokenUnits.append(unit)
        }

        guard !unspokenUnits.isEmpty else { return nil }
        return unspokenUnits.joined(separator: " ")
    }

    private func speechUnits(from text: String) -> [String] {
        var units: [String] = []
        var currentUnit = ""
        let terminators = CharacterSet(charactersIn: ".!?。！？\n")

        for scalar in text.unicodeScalars {
            currentUnit.unicodeScalars.append(scalar)
            if terminators.contains(scalar) {
                let unit = speechReadyText(currentUnit)
                if !unit.isEmpty {
                    units.append(unit)
                }
                currentUnit = ""
            }
        }

        let remainingUnit = speechReadyText(currentUnit)
        if !remainingUnit.isEmpty {
            units.append(remainingUnit)
        }

        return units
    }

    private func normalizedSpeechUnitKey(_ text: String) -> String {
        let foldedText = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: targetLanguage.locale)
        let allowedCharacters = CharacterSet.letters
            .union(.decimalDigits)
            .union(.whitespacesAndNewlines)
        let filteredText = String(foldedText.unicodeScalars.map { scalar in
            allowedCharacters.contains(scalar) ? Character(scalar) : " "
        })

        return filteredText
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func rememberSpokenTranslationUnitKey(_ key: String) {
        spokenTranslationUnitKeys.insert(key)
        spokenTranslationUnitKeyOrder.append(key)

        while spokenTranslationUnitKeyOrder.count > 160 {
            let removedKey = spokenTranslationUnitKeyOrder.removeFirst()
            if !spokenTranslationUnitKeyOrder.contains(removedKey) {
                spokenTranslationUnitKeys.remove(removedKey)
            }
        }
    }

    private func rememberSpokenTranslationUnits(in text: String) {
        for unit in speechUnits(from: text) {
            let key = normalizedSpeechUnitKey(unit)
            if !key.isEmpty {
                rememberSpokenTranslationUnitKey(key)
            }
        }
    }

    private func clearSpokenTranslationUnits() {
        spokenTranslationUnitKeys.removeAll()
        spokenTranslationUnitKeyOrder.removeAll()
    }

    private func resetDubbingProgress() {
        lastSpokenTranslatedText = ""
        clearSpokenTranslationUnits()
        stopSpeaking()
    }

    private func primeDubbingBaselineToCurrentTranslation() {
        let currentTranslation = speechReadyText(lines.last?.translatedText ?? "")
        lastSpokenTranslatedText = currentTranslation
        clearSpokenTranslationUnits()
        rememberSpokenTranslationUnits(in: currentTranslation)
    }

    private func stopSpeaking() {
        speechOutput.stop()
        openAIRealtimeAudioOutput.stop()
    }
}

extension TranslationSessionStore: SystemAudioCaptureDelegate {
    nonisolated func systemAudioCapture(_ capture: SystemAudioCapture, didOutput sampleBuffer: CMSampleBuffer) {
        transcriber.append(sampleBuffer)
        openAITranscriber.append(sampleBuffer)
    }

    nonisolated func systemAudioCapture(_ capture: SystemAudioCapture, didReceiveAudioSampleCount count: Int, level: Float?) {
        Task { @MainActor in
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
    nonisolated func microphoneAudioCapture(_ capture: MicrophoneAudioCapture, didOutput sampleBuffer: CMSampleBuffer) {
        transcriber.append(sampleBuffer)
        openAITranscriber.append(sampleBuffer)
    }

    nonisolated func microphoneAudioCapture(
        _ capture: MicrophoneAudioCapture,
        didReceiveAudioSampleCount count: Int,
        level: Float?
    ) {
        Task { @MainActor in
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
}

extension TranslationSessionStore: LiveSpeechTranscriberDelegate {
    nonisolated func liveSpeechTranscriber(
        _ transcriber: LiveSpeechTranscriber,
        didRecognize text: String,
        language: LanguageOption,
        confidence: Double
    ) {
        Task { @MainActor in
            await appendCaption(
                sourceText: text,
                recognizedLanguage: language,
                confidence: confidence,
                isFinal: false
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
            appendRealtimeTranslationOnly(text)
        }
    }

    nonisolated func liveSpeechTranscriber(
        _ transcriber: LiveSpeechTranscriber,
        didOutputAudioPCM16Base64 audio: String,
        sampleRate: Double
    ) {
        Task { @MainActor in
            guard isRunning,
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
            statusMessage = error.localizedDescription
        }
    }
}
