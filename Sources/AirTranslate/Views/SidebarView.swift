import SwiftUI

// Kept as a compatibility wrapper for call sites outside the main window.
struct SidebarView: View {
    @Bindable var session: TranslationSessionStore

    var body: some View {
        ConsoleBarView(session: session, isCompact: false)
    }
}

enum SidebarSessionConfigurationAccess {
    static func isLocked(isRunning: Bool, isStarting: Bool) -> Bool {
        isRunning || isStarting
    }

    static func segmentedControlPresentation(
        isRunning: Bool,
        isStarting: Bool
    ) -> SidebarSegmentedControlPresentation {
        isLocked(isRunning: isRunning, isStarting: isStarting) ? .lockedSummary : .picker
    }
}

enum SidebarSegmentedControlPresentation: Equatable {
    case picker
    case lockedSummary
}

enum ProcessingEngine: String, CaseIterable, Identifiable {
    case apple
    case gpt
    case gptTranscription
    case gemini
    case meta
    case azure
    case nari

    var id: String { rawValue }

    var title: String {
        switch self {
        case .apple: AppText.appleProcessingMode
        case .gpt: AppText.gptMode
        case .gptTranscription: AppText.gptTranscriptionMode
        case .gemini: AppText.geminiModels
        case .azure: AzureMAICopy.title
        case .nari: NariCopy.title
        case .meta: AppText.metaScribe
        }
    }

    @MainActor
    static func current(for session: TranslationSessionStore) -> ProcessingEngine {
        if session.isUsingNariSTT { return .nari }
        if session.isUsingAzureMAI { return .azure }
        if session.isUsingMetaScribe { return .meta }
        if session.isUsingGPTTranscriptionMode { return .gptTranscription }
        if session.openAITranscriptionModel.isEnabled || session.openAITranslationModel.isEnabled {
            return .gpt
        }
        if session.isUsingGemini { return .gemini }
        return .apple
    }
}

struct StageHeaderView: View {
    @Bindable var session: TranslationSessionStore
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        HStack(spacing: AirTranslateDesign.Spacing.sm) {
            SessionStatusPill(session: session)

            Rectangle()
                .fill(AirTranslateDesign.Palette.hairline)
                .frame(width: 1, height: 20)

            Label(session.languageSummary, systemImage: "arrow.triangle.swap")
                .font(AirTranslateDesign.Typography.label)
                .foregroundStyle(AirTranslateDesign.Palette.textPrimary)
                .lineLimit(1)

            Spacer(minLength: AirTranslateDesign.Spacing.sm)

            Button {
                if needsAPIKey {
                    session.requestAPIKeySettings()
                }
                openSettings()
            } label: {
                AirChip(
                    text: ProcessingEngine.current(for: session).title,
                    systemImage: needsAPIKey ? "key.fill" : "cpu",
                    tint: needsAPIKey
                        ? AirTranslateDesign.Palette.warning
                        : AirTranslateDesign.Palette.accent
                )
            }
            .buttonStyle(.plain)
            .airFocusRing(cornerRadius: 12)
            .help(needsAPIKey ? missingAPIKeyTitle : AppText.configureTranslationSettings)
            .accessibilityLabel(AppText.translationSettings)
            .accessibilityValue(
                needsAPIKey
                    ? "\(ProcessingEngine.current(for: session).title), \(missingAPIKeyTitle)"
                    : ProcessingEngine.current(for: session).title
            )

            if session.isUsingMetaScribe && session.isMetaSpeakerLabelsEnabled {
                AirChip(
                    text: AppText.speakerLabelsOn,
                    systemImage: "person.2.fill",
                    tint: AirTranslateDesign.Palette.textSecondary
                )
            }

            PermissionActionButton(session: session)
        }
        .padding(.horizontal, AirTranslateDesign.Spacing.lg)
        .frame(height: 52)
        .background(AirTranslateDesign.Palette.canvas)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AirTranslateDesign.Palette.hairline)
                .frame(height: 1)
        }
    }

    private var needsAPIKey: Bool {
        switch ProcessingEngine.current(for: session) {
        case .gpt, .gptTranscription: !session.hasOpenAIAPIKey
        case .gemini: !session.hasGeminiAPIKey
        case .azure: !session.hasAzureSpeechAPIKey || (try? AzureMAITranscriber.endpointURL(session.azureSpeechEndpoint)) == nil
        case .nari: !session.hasNariAPIKey
        case .meta: !session.hasMetaAPIKey
        case .apple: false
        }
    }

    private var missingAPIKeyTitle: String {
        switch ProcessingEngine.current(for: session) {
        case .gpt, .gptTranscription: AppText.openAIAPIKeyNotConfigured
        case .gemini: AppText.geminiAPIKeyNotConfigured
        case .azure: AzureMAICopy.configurationRequired
        case .nari: NariCopy.configurationRequired
        case .meta: AppText.metaAPIKeyNotConfigured
        case .apple: AppText.configureTranslationSettings
        }
    }
}

struct ConsoleBarView: View {
    @Bindable var session: TranslationSessionStore
    let isCompact: Bool
    @Environment(\.openSettings) private var openSettings
    @State private var showsVolume = false
    @FocusState private var isCaptureFocused: Bool

    var body: some View {
        HStack(spacing: AirTranslateDesign.Spacing.sm) {
            captureButton
            pauseButton

            consoleDivider
            if !isConfigurationAvailable {
                lockGroupIndicator
            }
            audioSourceControl

            if session.audioInputSource == .microphone {
                microphoneControl
            }

            if isCompact {
                compactMenu
            } else {
                consoleDivider
                languageControl
                outputControl
                voiceControl
            }

            Spacer(minLength: 0)
            engineButton
        }
        .padding(.horizontal, AirTranslateDesign.Spacing.sm)
        .padding(.vertical, AirTranslateDesign.Spacing.xs)
        .frame(maxWidth: 1120)
        .airConsoleSurface()
        .onAppear {
            Task { @MainActor in
                await Task.yield()
                isCaptureFocused = true
            }
            session.refreshModelAvailability()
            guard isConfigurationAvailable else { return }
            session.refreshMicrophoneInputDevices()
            if usesOpenAIAutoLanguageFlow {
                session.usePreferredLanguageForOpenAIOutput()
            }
        }
        .popover(isPresented: $showsVolume, arrowEdge: .bottom) {
            volumePopover
        }
    }

    private var captureButton: some View {
        Button {
            if session.isRunning || session.isStarting {
                session.stop()
            } else {
                session.start()
            }
        } label: {
            HStack(spacing: AirTranslateDesign.Spacing.xs) {
                if session.isStarting {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: session.isRunning ? "stop.fill" : "play.fill")
                }

                Text(captureTitle)
                    .lineLimit(1)

                if session.isRunning && !session.isPaused {
                    AudioLevelWaveform(
                        level: session.latestAudioLevel,
                        date: Date(),
                        barCount: 5,
                        width: 40,
                        height: 14,
                        barWidth: 3,
                        barSpacing: 2.5,
                        tint: AirTranslateDesign.Palette.danger
                    )
                }
            }
        }
        .buttonStyle(AirPillButtonStyle(kind: captureButtonKind))
        .airFocusRing(cornerRadius: 22, focus: $isCaptureFocused)
        .defaultFocus($isCaptureFocused, true)
        .help(captureTitle)
        .accessibilityLabel(captureTitle)
        .accessibilityValue(captureStateDescription)
    }

    private var pauseButton: some View {
        Button {
            session.isPaused ? session.resume() : session.pause()
        } label: {
            Image(systemName: session.isPaused ? "play.fill" : "pause.fill")
        }
        .buttonStyle(AirIconButton())
        .airFocusRing(cornerRadius: 18)
        .disabled(!session.isRunning || session.isFinishingNariSTT)
        .help(session.isPaused ? AppText.resume : AppText.pause)
        .accessibilityLabel(session.isPaused ? AppText.resume : AppText.pause)
    }

    @ViewBuilder
    private var audioSourceControl: some View {
        if segmentedControlPresentation == .lockedSummary {
            LockedConsoleSummary(
                title: AppText.audioInputSource,
                value: session.audioInputSource.title,
                systemImage: session.audioInputSource == .microphone ? "mic.fill" : "speaker.wave.2.fill"
            )
        } else {
            Picker(AppText.audioInputSource, selection: audioInputSourceBinding) {
                ForEach(AudioInputSource.allCases) { source in
                    Text(source.title).tag(source)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 168)
            .allowsHitTesting(isConfigurationAvailable)
            .accessibilityRespondsToUserInteraction(isConfigurationAvailable)
            .accessibilityLabel(AppText.audioInputSource)
        }
    }

    @ViewBuilder
    private var microphoneControl: some View {
        if segmentedControlPresentation == .lockedSummary {
            LockedConsoleSummary(
                title: AppText.microphoneInputDevice,
                value: selectedMicrophoneName,
                systemImage: "mic.circle.fill"
            )
        } else {
            Menu {
                ForEach(session.microphoneInputDevices) { device in
                    Button(device.name) {
                        guard isConfigurationAvailable else { return }
                        session.selectedMicrophoneInputDeviceID = device.id
                    }
                }
            } label: {
                Label(selectedMicrophoneName, systemImage: "mic.circle.fill")
                    .font(AirTranslateDesign.Typography.label)
                    .lineLimit(1)
                    .frame(maxWidth: 128)
            }
            .menuIndicator(.hidden)
            .airFocusRing(cornerRadius: AirTranslateDesign.Radius.control)
            .allowsHitTesting(isConfigurationAvailable)
            .accessibilityRespondsToUserInteraction(isConfigurationAvailable)
            .accessibilityLabel(AppText.microphoneInputDevice)
            .accessibilityValue(selectedMicrophoneName)
        }
    }

    @ViewBuilder
    private var languageControl: some View {
        if segmentedControlPresentation == .lockedSummary {
            LockedConsoleSummary(
                title: AppText.languagePair,
                value: session.languageSummary,
                systemImage: "arrow.right"
            )
        } else {
            HStack(spacing: AirTranslateDesign.Spacing.xxs) {
                languageMenu
                if !session.isTranscribeOnlyMode {
                    Button {
                        guard isConfigurationAvailable else { return }
                        session.swapQuickLanguagePair()
                    } label: {
                        Image(systemName: "arrow.left.arrow.right")
                    }
                    .buttonStyle(AirIconButton())
                    .airFocusRing(cornerRadius: 18)
                    .allowsHitTesting(isConfigurationAvailable && !usesAutomaticSource)
                    .accessibilityRespondsToUserInteraction(isConfigurationAvailable && !usesAutomaticSource)
                    .help(AppText.swapLanguages)
                    .accessibilityLabel(AppText.swapLanguages)
                }
            }
        }
    }

    private var languageMenu: some View {
        Menu {
            if !usesAutomaticSource {
                Picker(AppText.from, selection: sourceLanguageBinding) {
                    ForEach(LanguageOption.supported) { language in
                        Text(language.localizedTitle).tag(language)
                    }
                }
            }

            if !session.isTranscribeOnlyMode {
                Picker(AppText.to, selection: targetLanguageBinding) {
                    ForEach(LanguageOption.supported.filter { $0 != session.sourceLanguage }) { language in
                        Text(language.localizedTitle).tag(language)
                    }
                }
            }
        } label: {
            AirChip(
                text: session.languageSummary,
                systemImage: "globe",
                tint: AirTranslateDesign.Palette.textPrimary
            )
        }
        .menuIndicator(.hidden)
        .airFocusRing(cornerRadius: 12)
        .allowsHitTesting(isConfigurationAvailable)
        .accessibilityRespondsToUserInteraction(isConfigurationAvailable)
        .accessibilityLabel(AppText.languagePair)
        .accessibilityValue(session.languageSummary)
    }

    @ViewBuilder
    private var outputControl: some View {
        if session.isUsingNariSTT && segmentedControlPresentation != .lockedSummary {
            Menu {
                Picker(AppText.model, selection: nariWorkflowBinding) {
                    ForEach(IntelligenceModel.allCases) { model in
                        Text(model.title).tag(model)
                    }
                }
            } label: {
                AirChip(
                    text: session.isTranscribeOnlyMode ? NariCopy.sourceOnly : AppText.liveTranslation,
                    systemImage: "text.alignleft",
                    tint: AirTranslateDesign.Palette.textPrimary
                )
            }
            .menuIndicator(.hidden)
            .airFocusRing(cornerRadius: 12)
            .accessibilityLabel(AppText.outputMode)
            .accessibilityValue(session.selectedModel.title)
        } else if session.isTranscribeOnlyMode {
            AirChip(
                text: sourceOnlyOutputTitle,
                systemImage: "text.alignleft",
                tint: AirTranslateDesign.Palette.textSecondary
            )
        } else if segmentedControlPresentation == .lockedSummary {
            LockedConsoleSummary(
                title: AppText.outputMode,
                value: usesAPIModeOutputControl ? AppText.liveTranslation : session.liveOutputMode.title,
                systemImage: "waveform"
            )
        } else if usesAPIModeOutputControl {
            Button {
                guard isConfigurationAvailable else { return }
                session.useTranslationMode()
            } label: {
                AirChip(
                    text: AppText.liveTranslation,
                    systemImage: "waveform.badge.magnifyingglass",
                    tint: AirTranslateDesign.Palette.accent
                )
            }
            .buttonStyle(.plain)
            .airFocusRing(cornerRadius: 12)
            .allowsHitTesting(isConfigurationAvailable)
            .accessibilityRespondsToUserInteraction(isConfigurationAvailable)
            .accessibilityLabel(AppText.liveTranslation)
        } else {
            Picker(AppText.outputMode, selection: liveOutputModeBinding) {
                ForEach(LiveOutputMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 150)
            .allowsHitTesting(isConfigurationAvailable)
            .accessibilityRespondsToUserInteraction(isConfigurationAvailable)
            .accessibilityLabel(AppText.outputMode)
        }
    }

    @ViewBuilder
    private var voiceControl: some View {
        if !session.isTranscribeOnlyMode {
            if segmentedControlPresentation == .lockedSummary {
                LockedConsoleSummary(
                    title: AppText.voiceOutput,
                    value: AppText.voiceShort,
                    systemImage: session.isDubbingEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill",
                    spokenValue: session.isDubbingEnabled
                        ? AppText.floatingCaptionPowerOn
                        : AppText.floatingCaptionPowerOff
                )
            } else {
                HStack(spacing: AirTranslateDesign.Spacing.xxs) {
                    Button {
                        guard isConfigurationAvailable else { return }
                        session.isDubbingEnabled.toggle()
                    } label: {
                        Image(systemName: session.isDubbingEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                    }
                    .buttonStyle(AirIconButton())
                    .airFocusRing(cornerRadius: 18)
                    .allowsHitTesting(isConfigurationAvailable)
                    .accessibilityRespondsToUserInteraction(isConfigurationAvailable)
                    .accessibilityLabel(AppText.voiceOutput)
                    .accessibilityValue(session.isDubbingEnabled ? AppText.floatingCaptionPowerOn : AppText.floatingCaptionPowerOff)

                    if session.isDubbingEnabled {
                        Button {
                            showsVolume.toggle()
                        } label: {
                            Text(volumePercent)
                                .font(AirTranslateDesign.Typography.meta.monospacedDigit())
                                .foregroundStyle(AirTranslateDesign.Palette.textSecondary)
                        }
                        .buttonStyle(.plain)
                        .airFocusRing(cornerRadius: AirTranslateDesign.Radius.control)
                        .allowsHitTesting(isConfigurationAvailable)
                        .accessibilityRespondsToUserInteraction(isConfigurationAvailable)
                        .accessibilityLabel(AppText.volume)
                        .accessibilityValue(volumePercent)
                    }
                }
            }
        }
    }

    private var compactMenu: some View {
        Menu {
            Section(AppText.languages) {
                if segmentedControlPresentation == .lockedSummary {
                    Text(session.languageSummary)
                } else {
                    if !usesAutomaticSource {
                        Picker(AppText.from, selection: sourceLanguageBinding) {
                            ForEach(LanguageOption.supported) { language in
                                Text(language.localizedTitle).tag(language)
                            }
                        }
                    } else {
                        Text(AppText.autoDetectInput)
                    }
                    if !session.isTranscribeOnlyMode {
                        Picker(AppText.to, selection: targetLanguageBinding) {
                            ForEach(LanguageOption.supported.filter { $0 != session.sourceLanguage }) { language in
                                Text(language.localizedTitle).tag(language)
                            }
                        }
                    }
                }
            }

            Section(AppText.output) {
                if session.isUsingNariSTT && segmentedControlPresentation != .lockedSummary {
                    Picker(AppText.model, selection: nariWorkflowBinding) {
                        ForEach(IntelligenceModel.allCases) { model in
                            Text(model.title).tag(model)
                        }
                    }
                } else if session.isTranscribeOnlyMode {
                    Text(sourceOnlyOutputTitle)
                } else if segmentedControlPresentation == .lockedSummary {
                    Text(session.liveOutputMode.title)
                } else if usesAPIModeOutputControl {
                    Button(AppText.liveTranslation) {
                        guard isConfigurationAvailable else { return }
                        session.useTranslationMode()
                    }
                } else {
                    Picker(AppText.outputMode, selection: liveOutputModeBinding) {
                        ForEach(LiveOutputMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                }
            }

            if !session.isTranscribeOnlyMode {
                Section(AppText.voiceOutput) {
                    if segmentedControlPresentation == .lockedSummary {
                        Text(session.isDubbingEnabled ? AppText.floatingCaptionPowerOn : AppText.floatingCaptionPowerOff)
                    } else {
                        Button(session.isDubbingEnabled ? AppText.turnVoiceOutputOff : AppText.turnVoiceOutputOn) {
                            guard isConfigurationAvailable else { return }
                            session.isDubbingEnabled.toggle()
                        }
                        if session.isDubbingEnabled {
                            Button("\(AppText.volume) · \(volumePercent)") {
                                showsVolume = true
                            }
                        }
                    }
                }
            }
        } label: {
            Label(AppText.moreControls, systemImage: "ellipsis")
                .font(AirTranslateDesign.Typography.label)
                .frame(height: 36)
        }
        .menuIndicator(.hidden)
        .airFocusRing(cornerRadius: AirTranslateDesign.Radius.control)
        .help(AppText.moreControls)
        .accessibilityLabel(AppText.moreControls)
    }

    private var engineButton: some View {
        Button {
            openSettings()
        } label: {
            AirChip(
                text: ProcessingEngine.current(for: session).title,
                systemImage: "cpu",
                tint: AirTranslateDesign.Palette.textSecondary
            )
        }
        .buttonStyle(.plain)
        .airFocusRing(cornerRadius: 12)
        .help(AppText.configureTranslationSettings)
        .accessibilityLabel(AppText.translationSettings)
        .accessibilityValue(ProcessingEngine.current(for: session).title)
    }

    private var volumePopover: some View {
        VStack(alignment: .leading, spacing: AirTranslateDesign.Spacing.sm) {
            Label(AppText.voiceOutput, systemImage: "speaker.wave.2.fill")
                .font(AirTranslateDesign.Typography.label)
                .foregroundStyle(AirTranslateDesign.Palette.textPrimary)
            HStack {
                Image(systemName: "speaker.fill")
                    .foregroundStyle(AirTranslateDesign.Palette.textSecondary)
                Slider(value: translatedVoiceVolumeBinding, in: 0...1, step: 0.05)
                    .frame(width: 180)
                    .allowsHitTesting(isConfigurationAvailable)
                    .accessibilityRespondsToUserInteraction(isConfigurationAvailable)
                Text(volumePercent)
                    .font(AirTranslateDesign.Typography.meta.monospacedDigit())
                    .foregroundStyle(AirTranslateDesign.Palette.textSecondary)
                    .frame(width: 38)
            }
        }
        .padding(AirTranslateDesign.Spacing.md)
        .background(AirTranslateDesign.Palette.raised)
    }

    private var consoleDivider: some View {
        Rectangle()
            .fill(AirTranslateDesign.Palette.hairline)
            .frame(width: 1, height: 28)
    }

    private var lockGroupIndicator: some View {
        Image(systemName: "lock.fill")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(AirTranslateDesign.Palette.textTertiary)
            .help(AppText.lockedDuringSession)
            .accessibilityLabel(AppText.lockedDuringSession)
    }

    private var isConfigurationAvailable: Bool {
        !SidebarSessionConfigurationAccess.isLocked(
            isRunning: session.isRunning,
            isStarting: session.isStarting
        )
    }

    private var segmentedControlPresentation: SidebarSegmentedControlPresentation {
        SidebarSessionConfigurationAccess.segmentedControlPresentation(
            isRunning: session.isRunning,
            isStarting: session.isStarting
        )
    }

    private var captureTitle: String {
        session.isRunning || session.isStarting ? AppText.stop : AppText.start
    }

    private var captureStateDescription: String {
        if session.isStarting { return session.statusMessage }
        if session.isPaused { return AppText.paused }
        if session.isRunning { return AppText.listening }
        return session.statusMessage
    }

    private var captureButtonKind: AirPillButtonKind {
        if session.isPaused { return .paused }
        if session.isRunning || session.isStarting { return .stop }
        return .start
    }

    private var audioInputSourceBinding: Binding<AudioInputSource> {
        guardedBinding($session.audioInputSource)
    }

    private var liveOutputModeBinding: Binding<LiveOutputMode> {
        Binding(
            get: { session.liveOutputMode },
            set: { mode in
                guard isConfigurationAvailable else { return }
                session.useLiveOutputMode(mode)
            }
        )
    }

    private var sourceLanguageBinding: Binding<LanguageOption> {
        Binding(
            get: { session.sourceLanguage },
            set: { language in
                guard isConfigurationAvailable else { return }
                session.useQuickSourceLanguage(language)
            }
        )
    }

    private var targetLanguageBinding: Binding<LanguageOption> {
        Binding(
            get: { session.targetLanguage },
            set: { language in
                guard isConfigurationAvailable else { return }
                session.useQuickTargetLanguage(language)
            }
        )
    }

    private var translatedVoiceVolumeBinding: Binding<Double> {
        guardedBinding($session.translatedVoiceVolume)
    }

    private var nariWorkflowBinding: Binding<IntelligenceModel> {
        Binding(
            get: { session.isTranscribeOnlyMode ? .appleSpeechOnly : .appleSystem },
            set: { model in
                guard isConfigurationAvailable else { return }
                if model == .appleSpeechOnly {
                    session.useTranscribeOnlyMode()
                } else {
                    session.useTranslationMode()
                }
            }
        )
    }

    private func guardedBinding<Value>(_ binding: Binding<Value>) -> Binding<Value> {
        Binding(
            get: { binding.wrappedValue },
            set: { value in
                guard isConfigurationAvailable else { return }
                binding.wrappedValue = value
            }
        )
    }

    private var usesOpenAIAutoLanguageFlow: Bool {
        ProcessingEngine.current(for: session) == .gpt && session.isUsingOpenAIRealtimeTranslation
    }

    private var usesAutomaticSource: Bool {
        if session.isUsingNariSTT { return session.isNariSourceAutoDetectionEnabled }
        return session.isAppleSourceAutoDetectionEnabled
            || usesOpenAIAutoLanguageFlow
            || session.isUsingGeminiTranscriptionMode
            || session.isUsingMetaScribe
    }

    private var usesAPIModeOutputControl: Bool {
        ProcessingEngine.current(for: session) != .apple
    }

    private var sourceOnlyOutputTitle: String {
        session.isUsingGeminiTranscriptionMode || session.isUsingNariSTT ? AppText.originalOnly : AppText.gptTranscriptionSourceOnly
    }

    private var selectedMicrophoneName: String {
        session.microphoneInputDevices.first { $0.id == session.selectedMicrophoneInputDeviceID }?.name
            ?? MicrophoneInputDevice.systemDefault.name
    }

    private var volumePercent: String {
        "\(Int((session.translatedVoiceVolume * 100).rounded()))%"
    }
}

private struct SessionStatusPill: View {
    let session: TranslationSessionStore

    var body: some View {
        AirChip(text: title, systemImage: symbolName, tint: tint)
            .accessibilityLabel(title)
            .accessibilityValue(session.statusMessage)
    }

    private var title: String {
        if session.isPaused { return AppText.paused }
        if session.isRunning { return AppText.listening }
        return session.statusMessage
    }

    private var symbolName: String {
        if session.isPaused { return "pause.circle.fill" }
        if session.isRunning { return "waveform.circle.fill" }
        if session.statusMessage == AppText.ready { return "checkmark.circle.fill" }
        return "circle.dotted"
    }

    private var tint: Color {
        if session.isPaused { return AirTranslateDesign.Palette.paused }
        if session.isRunning || session.statusMessage == AppText.ready {
            return AirTranslateDesign.Palette.live
        }
        return AirTranslateDesign.Palette.textSecondary
    }
}

struct PermissionActionButton: View {
    let session: TranslationSessionStore

    var body: some View {
        if needsPermissionAction {
            Button {
                session.openPrivacySettings()
            } label: {
                Label(AppText.openPrivacySettings, systemImage: "lock.shield.fill")
                    .font(AirTranslateDesign.Typography.label)
                    .foregroundStyle(AirTranslateDesign.Palette.warning)
            }
            .buttonStyle(.plain)
            .airFocusRing(cornerRadius: AirTranslateDesign.Radius.control)
            .help(AppText.openPrivacySettings)
            .accessibilityLabel(AppText.openPrivacySettings)
        }
    }

    var needsPermissionAction: Bool {
        session.statusMessage.localizedCaseInsensitiveContains("permission")
            || session.statusMessage.localizedCaseInsensitiveContains("권한")
            || session.statusMessage.localizedCaseInsensitiveContains("権限")
            || session.statusMessage.localizedCaseInsensitiveContains("权限")
    }
}

private struct LockedConsoleSummary: View {
    let title: String
    let value: String
    let systemImage: String
    var spokenValue: String? = nil

    var body: some View {
        Label(value, systemImage: systemImage)
            .font(AirTranslateDesign.Typography.label)
            .foregroundStyle(AirTranslateDesign.Palette.textTertiary)
            .lineLimit(1)
            .padding(.horizontal, AirTranslateDesign.Spacing.xs)
            .frame(height: 32)
            .background(AirTranslateDesign.Palette.raisedHover, in: Capsule())
            .opacity(0.7)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title)
            .accessibilityValue("\(spokenValue ?? value), \(AppText.lockedDuringSession)")
    }
}
