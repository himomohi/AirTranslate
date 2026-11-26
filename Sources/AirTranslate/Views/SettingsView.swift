import AppKit
import SwiftUI

struct SettingsView: View {
    @Bindable var session: TranslationSessionStore
    @SceneStorage("AirTranslate.SettingsView.selectedCategory") private var selectedCategoryID = SettingsCategory.general.rawValue
    @State private var credentialScrollTarget: String?
    @State private var credentialScrollRequest = UUID()
    @State private var screenRecordingPermission: CapturePermissionStatus = .unknown
    @State private var microphonePermission: CapturePermissionStatus = .unknown
    @State private var speechRecognitionPermission: CapturePermissionStatus = .unknown
    @State private var showsAudioFileTools = false
    @State private var showsInactiveAppleSettings = false

    var body: some View {
        NavigationSplitView {
            SettingsSidebar(selection: selectedCategory, savedAPIKeyBadge: savedAPIKeyBadge)
                .navigationSplitViewColumnWidth(
                    min: AirTranslateDesign.settingsSidebarMinimum,
                    ideal: AirTranslateDesign.settingsSidebarIdeal,
                    max: AirTranslateDesign.settingsSidebarMaximum
                )
        } detail: {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: AirTranslateDesign.Spacing.lg) {
                        SettingsPageHeader(category: selectedCategory.wrappedValue)

                        selectedContent
                    }
                    .frame(maxWidth: AirTranslateDesign.settingsDetailMaximum, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(.horizontal, AirTranslateDesign.Spacing.lg)
                    .padding(.vertical, AirTranslateDesign.Spacing.xl)
                }
                .id(selectedCategoryID)
                .scrollIndicators(.automatic)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AirTranslateDesign.Palette.canvas)
                .task(id: credentialScrollRequest) {
                    guard let credentialScrollTarget else { return }
                    await Task.yield()
                    proxy.scrollTo(credentialScrollTarget, anchor: .top)
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .tint(AirTranslateDesign.Palette.accent)
        .background(AirTranslateDesign.Palette.canvas)
        .frame(
            minWidth: AirTranslateDesign.settingsWindowMinimumWidth,
            maxWidth: .infinity,
            minHeight: AirTranslateDesign.settingsWindowMinimumHeight,
            maxHeight: .infinity
        )
        .onAppear(perform: applyRequestedSettingsCategory)
        .onChange(of: session.requestedSettingsCategoryID) { _, _ in
            applyRequestedSettingsCategory()
        }
    }

    private var selectedCategory: Binding<SettingsCategory> {
        Binding {
            SettingsCategory(rawValue: selectedCategoryID) ?? .general
        } set: { category in
            selectedCategoryID = category.rawValue
        }
    }

    @ViewBuilder
    private var selectedContent: some View {
        switch selectedCategory.wrappedValue {
        case .general:
            generalSettings
            SettingsGroup(title: SettingsCopy.shortcuts) { ReadScreenShortcutRow() }
            if session.isUsingAppleTextTranslation {
                AppleTranslationSettingsView(session: session)
            } else {
                DisclosureGroup(AppleTranslationCopy.title, isExpanded: $showsInactiveAppleSettings) {
                    AppleTranslationSettingsView(session: session)
                        .padding(.top, AirTranslateDesign.Spacing.xs)
                }
                .padding(AirTranslateDesign.Spacing.md)
                .airRaisedSurface()
            }
            DisclosureGroup(
                AppText.localized(
                    english: "Audio File Transcription Tools",
                    korean: "오디오 파일 전사 도구",
                    japanese: "音声ファイル文字起こしツール",
                    chineseSimplified: "音频文件转写工具"
                ),
                isExpanded: $showsAudioFileTools
            ) {
                EmbeddingGemmaTranscriptionView(isCaptureActive: session.isRunning || session.isStarting)
                    .padding(.top, AirTranslateDesign.Spacing.xs)
            }
            .padding(AirTranslateDesign.Spacing.md)
            .airRaisedSurface()
        case .apiKeys:
            apiKeySettings
        case .audio:
            audioSettings
        case .output:
            outputSettings
        case .transcript:
            transcriptSettings
        case .floatingCaptions:
            floatingCaptionSettings
        case .assets:
            assetSettings
        case .permissions:
            permissionSettings
        case .info:
            infoSettings
        }
    }

    private var generalSettings: some View {
        SettingsGroup(title: SettingsCopy.modeSettings) {
            if isSessionConfigurationLocked {
                SettingsNoticeRow(text: SettingsCopy.captureRunningDisabledReason, systemImage: "pause.circle")
            }

            SettingsControlRow(
                title: SettingsCopy.processingEngine,
                detail: SettingsCopy.processingEngineDetail,
                systemImage: "switch.2"
            ) {
                Picker(SettingsCopy.processingEngine, selection: processingModeSelection) {
                    ForEach(SettingsProcessingMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(minWidth: 190, idealWidth: 220, maxWidth: 260)
                .allowsHitTesting(segmentedControlAllowsHitTesting())
                .accessibilityRespondsToUserInteraction(segmentedControlAllowsHitTesting())
                .opacity(isSessionConfigurationLocked ? 0.6 : 1)
                .help(SettingsCopy.processingEngineDetail)
                .accessibilityLabel(SettingsCopy.processingEngine)
                .accessibilityValue(processingModeSelection.wrappedValue.title)
                .accessibilityHint(
                    isSessionConfigurationLocked
                        ? SettingsCopy.captureRunningDisabledReason
                        : SettingsCopy.processingEngineDetail
                )
            }

            SettingsToggleRow(
                title: JevCopy.title,
                detail: session.isJevSelectionAvailable ? JevCopy.detail : JevCopy.appleOnly,
                systemImage: "text.badge.checkmark",
                detailLineLimit: nil,
                isOn: lockedSessionConfigurationBinding($session.isJevSelectionEnabled)
            )
            .disabled(isSessionConfigurationLocked || !session.isJevSelectionAvailable)
            .accessibilityIdentifier("jevSelectionToggle")

            if session.isUsingJevSelection {
                SettingsNoticeRow(
                    text: session.hasJevAPIKey ? session.jevSelectionStatus : JevCopy.keyRequired,
                    systemImage: session.hasJevAPIKey ? "info.circle" : "key"
                )
            }

            if session.isUsingJevSelection && !session.hasJevAPIKey {
                Button(JevCopy.keySettings) { session.requestAPIKeySettings(provider: .jev) }
                    .disabled(isSessionConfigurationLocked)
                    .accessibilityIdentifier("jevAPIKeySettings")
            }

            if processingModeSelection.wrappedValue == .gemini {
                SettingsControlRow(
                    title: SettingsCopy.geminiLiveMode,
                    detail: SettingsCopy.geminiLiveModeDetail,
                    systemImage: "waveform.badge.mic"
                ) {
                    Picker(SettingsCopy.geminiLiveMode, selection: geminiModelSelection) {
                        ForEach(GeminiTranslationModel.selectableCases) { model in
                            Text(model.isTranscription ? SettingsCopy.transcribe : SettingsCopy.translate)
                                .tag(model)
                        }
                    }
                    .pickerStyle(.segmented)
                    .tint(AirTranslateDesign.Palette.accent)
                    .labelsHidden()
                    .frame(minWidth: 230, idealWidth: 300, maxWidth: .infinity)
                    .allowsHitTesting(segmentedControlAllowsHitTesting())
                    .accessibilityRespondsToUserInteraction(segmentedControlAllowsHitTesting())
                    .opacity(isSessionConfigurationLocked ? 0.6 : 1)
                    .accessibilityLabel(SettingsCopy.geminiLiveMode)
                    .accessibilityValue(geminiModelSelection.wrappedValue.title)
                    .accessibilityHint(
                        isSessionConfigurationLocked
                            ? SettingsCopy.captureRunningDisabledReason
                            : SettingsCopy.geminiLiveModeDetail
                    )
                }
            }

            if processingModeSelection.wrappedValue == .openAI, !session.hasOpenAIAPIKey {
                SettingsNoticeActionRow(
                    text: AppText.openAIAPIKeyRequiredForGPTMode,
                    systemImage: "key",
                    actionTitle: SettingsCopy.enterOpenAIAPIKey
                ) {
                    selectedCategory.wrappedValue = .apiKeys
                }
            }

            if processingModeSelection.wrappedValue == .openAI {
                openAIOutputControl
            }

            if processingModeSelection.wrappedValue == .gemini, !session.hasGeminiAPIKey {
                SettingsNoticeActionRow(
                    text: AppText.geminiAPIKeyMissing,
                    systemImage: "key",
                    actionTitle: SettingsCopy.enterGeminiAPIKey
                ) {
                    selectedCategory.wrappedValue = .apiKeys
                }
            }

            if processingModeSelection.wrappedValue == .azure {
                Picker(AzureMAICopy.modelLabel, selection: lockedSessionConfigurationBinding($session.azureTranscriptionModel)) {
                    ForEach(AzureTranscriptionModel.allCases) { model in Text(model.title).tag(model) }
                }
                .disabled(isSessionConfigurationLocked)
                .accessibilityIdentifier("settingsAzureModelPicker")
                SettingsNoticeRow(text: AzureMAICopy.detail(for: session.azureTranscriptionModel), systemImage: "waveform")
                if let azureConfigurationIssue {
                    SettingsNoticeActionRow(
                        text: azureConfigurationIssue,
                        systemImage: "key",
                        actionTitle: AzureMAICopy.configureSpeech
                    ) {
                        selectedCategory.wrappedValue = .apiKeys
                    }
                }
            }
            if processingModeSelection.wrappedValue == .nari {
                nariGeneralSettings
            }
            if processingModeSelection.wrappedValue == .hyMT {
                HyMTSettingsView(session: session)
            }
            if processingModeSelection.wrappedValue == .qwen {
                qwenGeneralSettings
            }

            if processingModeSelection.wrappedValue == .grok {
                grokGeneralSettings
            }
            if processingModeSelection.wrappedValue == .meta {
                SettingsControlRow(
                    title: AppText.metaScribe,
                    detail: AppText.metaScribeDetail,
                    systemImage: "person.2.wave.2"
                ) {
                    Text(MetaTranscriptionModel.museVoiceTranscribe.title)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(AirTranslateDesign.Palette.accent)
                }

                SettingsControlRow(
                    title: SettingsCopy.speakerLabels,
                    detail: SettingsCopy.speakerLabelsDetail,
                    systemImage: "person.2"
                ) {
                    Toggle("", isOn: $session.isMetaSpeakerLabelsEnabled)
                        .labelsHidden()
                        .disabled(isSessionConfigurationLocked)
                        .tint(AirTranslateDesign.Palette.accent)
                        .accessibilityLabel(SettingsCopy.speakerLabels)
                }
            }

            if processingModeSelection.wrappedValue == .meta, !session.hasMetaAPIKey {
                SettingsNoticeActionRow(
                    text: AppText.metaAPIKeyMissing,
                    systemImage: "key",
                    actionTitle: SettingsCopy.enterMetaAPIKey
                ) {
                    selectedCategory.wrappedValue = .apiKeys
                }
            }

            if !session.isUsingOpenAIRealtime && !session.isUsingHyMT {
                SettingsControlRow(
                    title: SettingsCopy.sessionWorkflow,
                    detail: SettingsCopy.sessionWorkflowDetail,
                    systemImage: "captions.bubble"
                ) {
                    Picker(AppText.model, selection: modelSelection) {
                        ForEach(IntelligenceModel.allCases) { model in
                            Text(model.title).tag(model)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 220)
                    .disabled(isSessionConfigurationLocked || session.isUsingProviderRealtimeTranslation || session.isUsingProviderTranscriptionMode)
                }

                if session.isUsingProviderRealtimeTranslation {
                    SettingsNoticeRow(text: SettingsCopy.realtimeTranslationOutputOnly, systemImage: "waveform")
                } else if session.isUsingProviderTranscriptionMode {
                    SettingsNoticeRow(text: AppText.gptTranscriptionSourceOnly, systemImage: "text.quote")
                }
            }

            SettingsValueRow(
                title: AppText.languages,
                detail: SettingsCopy.languagePairDetail,
                systemImage: "globe",
                value: session.languageSummary
            )

            SettingsValueRow(
                title: AppText.autoDetectInput,
                detail: autoDetectionDetail,
                systemImage: "sparkles",
                value: autoDetectionStatus
            )
        }
    }

    private var apiKeySettings: some View {
        APIKeySettingsView(session: session) { provider in
            credentialScrollTarget = provider.rawValue
            credentialScrollRequest = UUID()
        }
    }

    private var audioSettings: some View {
        SettingsGroup(title: AppText.audioInputSource) {
            if isSessionConfigurationLocked {
                SettingsNoticeRow(text: SettingsCopy.captureRunningDisabledReason, systemImage: "pause.circle")
            }

            SettingsControlRow(
                title: AppText.audioInputSource,
                detail: SettingsCopy.audioInputDetail,
                systemImage: "waveform.badge.magnifyingglass"
            ) {
                Picker(AppText.audioInputSource, selection: lockedSessionConfigurationBinding($session.audioInputSource)) {
                    ForEach(AudioInputSource.allCases) { source in
                        Text(source.title).tag(source)
                    }
                }
                .pickerStyle(.segmented)
                .tint(AirTranslateDesign.Palette.accent)
                .labelsHidden()
                .fixedSize()
                .allowsHitTesting(segmentedControlAllowsHitTesting())
                .accessibilityRespondsToUserInteraction(segmentedControlAllowsHitTesting())
                .opacity(isSessionConfigurationLocked ? 0.6 : 1)
                .accessibilityLabel(AppText.audioInputSource)
                .accessibilityHint(
                    isSessionConfigurationLocked
                        ? SettingsCopy.captureRunningDisabledReason
                        : SettingsCopy.audioInputDetail
                )
            }

            SettingsControlRow(
                title: AppText.microphoneInputDevice,
                detail: session.audioInputSource == .microphone
                    ? SettingsCopy.microphoneDeviceDetail
                    : SettingsCopy.microphoneDeviceUnavailableForSystemAudioDetail,
                systemImage: "mic"
            ) {
                Picker(AppText.microphoneInputDevice, selection: lockedSessionConfigurationBinding($session.selectedMicrophoneInputDeviceID)) {
                    ForEach(session.microphoneInputDevices) { device in
                        Text(device.name).tag(device.id)
                    }
                }
                .labelsHidden()
                .frame(width: 220)
                .disabled(isSessionConfigurationLocked || session.audioInputSource != .microphone)
            }
        }
    }

    private var outputSettings: some View {
        SettingsGroup(title: AppText.output) {
            if isSessionConfigurationLocked {
                SettingsNoticeRow(text: SettingsCopy.captureRunningDisabledReason, systemImage: "pause.circle")
            }

            if session.isUsingOpenAIRealtime {
                openAIOutputControl
            } else if session.isTranscribeOnlyMode {
                SettingsValueRow(
                    title: AppText.outputMode,
                    detail: transcribeOnlyOutputDetail,
                    systemImage: "rectangle.split.2x1",
                    value: SettingsCopy.originalOnly
                )
            } else {
                SettingsControlRow(
                    title: AppText.outputMode,
                    detail: SettingsCopy.outputModeDetail,
                    systemImage: "rectangle.split.2x1"
                ) {
                    Picker(AppText.outputMode, selection: liveOutputModeBinding) {
                        ForEach(LiveOutputMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .tint(AirTranslateDesign.Palette.accent)
                    .labelsHidden()
                    .fixedSize()
                    .allowsHitTesting(
                        segmentedControlAllowsHitTesting(
                            isOtherwiseAvailable: !session.isUsingProviderRealtimeTranslation
                        )
                    )
                    .accessibilityRespondsToUserInteraction(
                        segmentedControlAllowsHitTesting(
                            isOtherwiseAvailable: !session.isUsingProviderRealtimeTranslation
                        )
                    )
                    .opacity(
                        segmentedControlAllowsHitTesting(
                            isOtherwiseAvailable: !session.isUsingProviderRealtimeTranslation
                        ) ? 1 : 0.6
                    )
                    .accessibilityLabel(AppText.outputMode)
                    .accessibilityHint(
                        isSessionConfigurationLocked
                            ? SettingsCopy.captureRunningDisabledReason
                            : session.isUsingProviderRealtimeTranslation
                                ? SettingsCopy.realtimeTranslationOutputOnly
                                : SettingsCopy.outputModeDetail
                    )
                }
            }

            if session.isUsingProviderRealtimeTranslation && !session.isUsingOpenAIRealtime {
                SettingsNoticeRow(text: SettingsCopy.realtimeTranslationOutputOnly, systemImage: "waveform")
            }

            if !session.isTranscribeOnlyMode {
                SettingsToggleRow(
                    title: AppText.voiceOutput,
                    detail: SettingsCopy.dubbingDetail,
                    systemImage: "speaker.wave.2",
                    isOn: lockedSessionConfigurationBinding($session.isDubbingEnabled)
                )
                .disabled(isSessionConfigurationLocked)

                SettingsControlRow(
                    title: SettingsCopy.translatedSpeechModel,
                    detail: SettingsCopy.translatedSpeechModelDetail,
                    systemImage: "waveform"
                ) {
                    Picker(
                        SettingsCopy.translatedSpeechModel,
                        selection: lockedSessionConfigurationBinding($session.speechSynthesisModel)
                    ) {
                        ForEach(SpeechSynthesisModel.allCases) { model in
                            Text(model.title).tag(model)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .fixedSize()
                    .disabled(isSessionConfigurationLocked)
                    .accessibilityLabel(SettingsCopy.translatedSpeechModel)
                    .accessibilityValue(session.speechSynthesisModel.title)
                    .accessibilityHint(SettingsCopy.translatedSpeechModelDetail)
                }
                .disabled(isSessionConfigurationLocked)

                if session.speechSynthesisModel.isMAIVoice {
                    SettingsControlRow(title: MAIVoiceCopy.voice, detail: MAIVoiceCopy.detail, systemImage: "person.wave.2") {
                        Picker(MAIVoiceCopy.voice, selection: lockedSessionConfigurationBinding($session.maiVoiceName)) {
                            Text(MAIVoiceCopy.automaticVoice).tag("")
                            if !session.maiVoiceName.isEmpty, !session.availableMAIVoices.contains(session.maiVoiceName) {
                                Text(session.maiVoiceName).tag(session.maiVoiceName)
                            }
                            ForEach(session.availableMAIVoices, id: \.self) { voice in Text(voice).tag(voice) }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .disabled(isSessionConfigurationLocked)
                        .accessibilityLabel(MAIVoiceCopy.voice)
                        .accessibilityIdentifier("maiVoicePicker")
                    }
                    .task(id: session.speechSynthesisModel.rawValue + session.targetLanguage.id) {
                        await session.refreshMAIVoices()
                    }
                    if let message = session.maiVoiceCatalogMessage {
                        SettingsNoticeRow(text: message, systemImage: "info.circle")
                    }
                    if !session.maiVoiceName.isEmpty, !session.availableMAIVoices.isEmpty,
                       !session.availableMAIVoices.contains(session.maiVoiceName) {
                        SettingsNoticeRow(text: MAIVoiceCopy.languageUnsupported, systemImage: "exclamationmark.circle")
                    }
                    if !session.hasOpenRouterAPIKey {
                        SettingsNoticeActionRow(text: MAIVoiceCopy.keyRequired, systemImage: "key", actionTitle: MAIVoiceCopy.configure) {
                            session.requestedAPIKeyProvider = .openRouter
                            selectedCategory.wrappedValue = .apiKeys
                        }
                    }
                }

                if session.speechSynthesisModel.isGeminiTTS,
                   !session.hasGeminiAPIKey,
                   processingModeSelection.wrappedValue != .gemini {
                    SettingsNoticeActionRow(
                        text: AppText.geminiTTSAPIKeyMissing,
                        systemImage: "key",
                        actionTitle: SettingsCopy.enterGeminiAPIKey
                    ) {
                        selectedCategory.wrappedValue = .apiKeys
                    }
                }

                SettingsControlRow(
                    title: SettingsCopy.liveTranslationVolume,
                    detail: session.isDubbingEnabled
                        ? SettingsCopy.liveTranslationVolumeDetail
                        : SettingsCopy.voiceOutputDisabledReason,
                    systemImage: "speaker.wave.3"
                ) {
                    SettingsVolumeSlider(
                        value: lockedSessionConfigurationBinding($session.translatedVoiceVolume),
                        range: 0...1,
                        accessibilityLabel: SettingsCopy.liveTranslationVolume
                    )
                }
                .disabled(isSessionConfigurationLocked || !session.isDubbingEnabled)
            }

            SettingsControlRow(
                title: SettingsCopy.speaker,
                detail: SettingsCopy.speakerDetail,
                systemImage: "hifispeaker"
            ) {
                Picker(SettingsCopy.speaker, selection: $session.speechOutputDeviceID) {
                    ForEach(session.speechOutputDevices) { device in
                        Text(device.isConnected ? device.name : SettingsCopy.speakerNotConnected(device.name))
                            .tag(device.id)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .fixedSize()
                .accessibilityLabel(SettingsCopy.speaker)
            }

            if session.selectedSpeechOutputDevice?.isConnected == false {
                SettingsNoticeRow(text: SettingsCopy.speakerNotConnectedNote, systemImage: "info.circle")
            }
        }
    }

    private var openAIOutputControl: some View {
        HStack(spacing: 12) {
            Text(AppText.openAIAudio).font(.callout.weight(.medium))
            InlineHelpIcon(symbol: "info.circle", help: AppText.openAIAudioDescription)
            Spacer()
            OpenAIOutputPicker(session: session)
        }
        .padding(.vertical, 6)
    }

    private var transcribeOnlyOutputDetail: String {
        if session.isUsingGeminiTranscriptionMode {
            return SettingsCopy.geminiTranscribeSourceOnlyDetail
        }
        if session.isUsingGPTTranscriptionMode {
            return AppText.gptTranscriptionModeDescription
        }
        return SettingsCopy.appleTranscribeSourceOnlyDetail
    }

    private var transcriptSettings: some View {
        SettingsGroup(title: AppText.transcript) {
            if isSessionConfigurationLocked {
                SettingsNoticeRow(text: SettingsCopy.captureRunningDisabledReason, systemImage: "pause.circle")
            }

            if session.isUsingOpenAIRealtime {
                SettingsNoticeRow(text: SettingsCopy.openAIRealtimeDisabledReason, systemImage: "info.circle")
            }

            SettingsControlRow(
                title: AppText.sessionLength,
                detail: session.sessionDurationMode.detail,
                systemImage: "timer"
            ) {
                Picker(AppText.sessionLength, selection: lockedSessionConfigurationBinding($session.sessionDurationMode)) {
                    ForEach(SessionDurationMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .tint(AirTranslateDesign.Palette.accent)
                .labelsHidden()
                .fixedSize()
                .allowsHitTesting(segmentedControlAllowsHitTesting())
                .accessibilityRespondsToUserInteraction(segmentedControlAllowsHitTesting())
                .opacity(isSessionConfigurationLocked ? 0.6 : 1)
                .accessibilityLabel(AppText.sessionLength)
                .accessibilityHint(
                    isSessionConfigurationLocked
                        ? SettingsCopy.captureRunningDisabledReason
                        : session.sessionDurationMode.detail
                )
            }

            SettingsControlRow(
                title: AppText.paragraphBreakSilenceInterval,
                detail: AppText.paragraphBreakSilenceDescription,
                systemImage: "text.append"
            ) {
                Stepper(
                    AppText.seconds(session.paragraphBreakSilenceInterval),
                    value: lockedSessionConfigurationBinding($session.paragraphBreakSilenceInterval),
                    in: 1...15,
                    step: 0.5
                )
                .frame(width: 104)
                .disabled(isSessionConfigurationLocked)
            }

            SettingsToggleRow(
                title: AppText.transcriptPersistence,
                detail: AppText.transcriptPersistenceDescription,
                systemImage: "externaldrive",
                isOn: lockedSessionConfigurationBinding($session.isTranscriptPersistenceEnabled)
            )
            .disabled(isSessionConfigurationLocked)

            SettingsToggleRow(
                title: AppText.transcriptLint,
                detail: AppText.transcriptLintDescription,
                systemImage: "wand.and.sparkles",
                isOn: lockedSessionConfigurationBinding($session.isTranscriptLintEnabled)
            )
            .disabled(isSessionConfigurationLocked || session.isUsingOpenAIRealtime)

            SettingsControlRow(
                title: AppText.savedTranscriptContent,
                detail: AppText.autoSaveDescription,
                systemImage: "archivebox"
            ) {
                if session.isTranscribeOnlyMode {
                    Text(session.effectiveSavedTranscriptContentMode.title)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.secondary)
                } else {
                    Picker(AppText.savedTranscriptContent, selection: lockedSessionConfigurationBinding($session.savedTranscriptContentMode)) {
                        ForEach(session.availableSavedTranscriptContentModes) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .frame(minWidth: 150, idealWidth: 170, maxWidth: .infinity)
                    .disabled(isSessionConfigurationLocked)
                }
            }
        }
    }

    private var floatingCaptionSettings: some View {
        FloatingCaptionSettingsView(session: session)
    }

    private var assetSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsGroup(title: AppText.requiredAssets) {
                SettingsAssetAvailabilityRow(
                    title: AppText.speechLanguagePack,
                    availability: session.modelAvailability(for: .appleSpeechOnly)
                ) {
                    session.downloadModelAssets(for: .appleSpeechOnly)
                }

                SettingsAssetAvailabilityRow(
                    title: AppText.translationLanguagePack,
                    availability: session.modelAvailability(for: .appleOnDevice)
                ) {
                    session.downloadModelAssets(for: .appleOnDevice)
                }
            }
            .disabled(session.isDownloadingModelAssets)

            Label(SettingsCopy.assetDownloadNotice, systemImage: "internaldrive")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var permissionSettings: some View {
        SettingsGroup(title: AppText.permissions) {
            SettingsControlRow(
                title: PermissionSetupCopy.title,
                detail: session.capturePermissionSteps.map(permissionTitle).joined(separator: " · "),
                systemImage: "checkmark.shield"
            ) {
                switch permissionSetupState {
                case .requesting(let pane):
                    ProgressView { Text(PermissionSetupCopy.checking(permissionTitle(pane))) }
                        .controlSize(.small)
                default:
                    if session.capturePermissionSteps.allSatisfy({ permissionStatus($0) == .allowed }) {
                        Label(PermissionSetupCopy.ready, systemImage: "checkmark.circle.fill")
                            .foregroundStyle(AirTranslateDesign.Palette.live)
                    } else {
                        Button(PermissionSetupCopy.start, action: session.startCapturePermissionSetup)
                            .buttonStyle(.borderedProminent)
                            .disabled(isSessionConfigurationLocked || session.capturePermissionSetup.isRequesting)
                            .accessibilityIdentifier("capturePermissionSetup")
                            .accessibilityHint(PermissionSetupCopy.instruction)
                    }
                }
            }

            if case .waiting(let pane, let result) = permissionSetupState,
               permissionStatus(pane) != .allowed {
                if result == .restricted {
                    SettingsNoticeRow(text: PermissionSetupCopy.restricted(permissionTitle(pane)), systemImage: "lock")
                } else {
                    SettingsNoticeActionRow(
                        text: pane == .screenRecording
                            ? PermissionSetupCopy.screenInstruction
                            : PermissionSetupCopy.resumeInstruction(permissionTitle(pane)),
                        systemImage: "lock.shield",
                        actionTitle: AppText.openPrivacySettings
                    ) {
                        session.openPrivacySettings(pane)
                    }
                }
            }

            SettingsPermissionRow(
                title: SettingsCopy.screenRecording,
                detail: SettingsCopy.screenRecordingPermissionDetail,
                systemImage: "rectangle.dashed.badge.record",
                status: screenRecordingPermission
            ) {
                session.openPrivacySettings(.screenRecording)
            }

            SettingsPermissionRow(
                title: SettingsCopy.microphonePermission,
                detail: SettingsCopy.microphonePermissionDetail,
                systemImage: "mic",
                status: microphonePermission
            ) {
                session.openPrivacySettings(.microphone)
            }

            SettingsPermissionRow(
                title: SettingsCopy.speechRecognitionPermission,
                detail: SettingsCopy.speechRecognitionPermissionDetail,
                systemImage: "quote.bubble",
                status: speechRecognitionPermission
            ) {
                session.openPrivacySettings(.speechRecognition)
            }

            HStack {
                Label(PermissionSetupCopy.instruction, systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 16)

                Button(action: refreshPermissionStatuses) {
                    Label(SettingsCopy.refreshPermissionStatus, systemImage: "arrow.clockwise")
                }
            }
            .padding(.vertical, 8)
        }
        .onAppear(perform: refreshPermissionStatuses)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshPermissionStatuses()
        }
        .onChange(of: permissionSetupState) { _, _ in
            refreshPermissionStatuses()
        }
    }

    private var permissionSetupState: CapturePermissionSetup.State {
        session.capturePermissionSetup.state(for: session.capturePermissionSteps)
    }

    private func permissionTitle(_ pane: PrivacySettingsPane) -> String {
        switch pane {
        case .screenRecording: SettingsCopy.screenRecording
        case .microphone: SettingsCopy.microphonePermission
        case .speechRecognition: SettingsCopy.speechRecognitionPermission
        }
    }

    private func permissionStatus(_ pane: PrivacySettingsPane) -> CapturePermissionStatus {
        switch pane {
        case .screenRecording: screenRecordingPermission
        case .microphone: microphonePermission
        case .speechRecognition: speechRecognitionPermission
        }
    }

    private var infoSettings: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsGroup(title: SettingsCopy.aboutAirTranslate) {
                SettingsValueRow(
                    title: AppText.appName,
                    detail: AppText.appTagline,
                    systemImage: "waveform.and.magnifyingglass",
                    value: SettingsCopy.localFirst
                )

                SettingsValueRow(
                    title: SettingsCopy.version,
                    detail: SettingsCopy.versionDetail,
                    systemImage: "number",
                    value: appVersionSummary
                )

                SettingsValueRow(
                    title: SettingsCopy.privacy,
                    detail: SettingsCopy.privacyDetail,
                    systemImage: "lock.shield",
                    value: SettingsCopy.macOSKeychain
                )
            }

        }
    }

    @ViewBuilder
    private var nariGeneralSettings: some View {
        SettingsControlRow(
            title: NariCopy.modelLabel,
            detail: NariCopy.modelDetail + "\n" + session.nariTranscriptionModel.billingSummary,
            systemImage: "waveform.badge.mic"
        ) {
            Picker(NariCopy.modelLabel, selection: lockedSessionConfigurationBinding($session.nariTranscriptionModel)) {
                ForEach(NariTranscriptionModel.selectableCases) { model in
                    Text(model.title).tag(model)
                }
            }
            .labelsHidden()
            .frame(minWidth: 210, idealWidth: 250, maxWidth: 300)
            .disabled(isSessionConfigurationLocked)
            .accessibilityLabel(NariCopy.modelLabel)
            .accessibilityValue(session.nariTranscriptionModel.title)
        }

        SettingsControlRow(
            title: AppText.autoDetectInput,
            detail: NariCopy.autoDetectDetail,
            systemImage: "globe"
        ) {
            Toggle("", isOn: lockedSessionConfigurationBinding($session.isNariSourceAutoDetectionEnabled))
                .labelsHidden()
                .disabled(isSessionConfigurationLocked)
                .accessibilityLabel(AppText.autoDetectInput)
        }

        SettingsNoticeRow(text: NariCopy.detail, systemImage: "waveform")
        if !session.hasNariAPIKey {
            SettingsNoticeActionRow(
                text: NariCopy.configurationRequired,
                systemImage: "key",
                actionTitle: NariCopy.configureSpeech
            ) {
                selectedCategory.wrappedValue = .apiKeys
            }
        }
    }

    @ViewBuilder
    private var grokGeneralSettings: some View {
        SettingsControlRow(
            title: GrokCopy.modelLabel,
            detail: GrokCopy.detail,
            systemImage: "waveform.badge.mic"
        ) {
            Picker(GrokCopy.modelLabel, selection: lockedSessionConfigurationBinding($session.grokTranscriptionModel)) {
                ForEach(GrokTranscriptionModel.selectableCases) { model in
                    Text(model.title).tag(model)
                }
            }
            .labelsHidden()
            .frame(minWidth: 210, idealWidth: 250, maxWidth: 300)
            .disabled(isSessionConfigurationLocked)
            .accessibilityLabel(GrokCopy.modelLabel)
            .accessibilityValue(session.grokTranscriptionModel.title)
        }

        SettingsControlRow(
            title: AppText.autoDetectInput,
            detail: GrokCopy.autoDetectDetail,
            systemImage: "globe"
        ) {
            Toggle("", isOn: lockedSessionConfigurationBinding($session.isGrokSourceAutoDetectionEnabled))
                .labelsHidden()
                .disabled(isSessionConfigurationLocked)
                .accessibilityLabel(AppText.autoDetectInput)
        }

        SettingsNoticeRow(text: GrokCopy.detail, systemImage: "waveform")
        if !session.hasGrokAPIKey {
            SettingsNoticeActionRow(
                text: GrokCopy.configurationRequired,
                systemImage: "key",
                actionTitle: GrokCopy.configureSpeech
            ) {
                selectedCategory.wrappedValue = .apiKeys
            }
        }
    }

    private var selectedProcessingMode: SettingsProcessingMode {
        if session.isUsingHyMT { return .hyMT }
        if session.isUsingQwenTranslation { return .qwen }
        if session.isUsingGrokSTT { return .grok }
        if session.isUsingNariSTT { return .nari }
        if session.isUsingAzureMAI { return .azure }
        if session.isUsingMetaScribe {
            return .meta
        }
        if session.isUsingOpenAIRealtime {
            return .openAI
        }
        if session.isUsingGemini {
            return .gemini
        }
        return .apple
    }

    private var azureConfigurationIssue: String? {
        let hasValidEndpoint = session.hasAzureConfiguration
        switch (hasValidEndpoint, session.hasAzureSpeechAPIKey) {
        case (false, false):
            return AzureMAICopy.configurationRequired
        case (false, true):
            return session.azureTranscriptionModel.isStreaming ? AzureMAICopy.configurationRequired : AzureMAICopy.endpointRequired
        case (true, false):
            return AzureMAICopy.keyRequired
        case (true, true):
            return nil
        }
    }

    private var autoDetectionDetail: String {
        if session.isUsingQwenTranslation { return QwenCopy.detail(for: session.qwenTranslationModel) }
        if session.isUsingGrokSTT { return GrokCopy.autoDetectDetail }
        if session.isUsingNariSTT { return NariCopy.autoDetectDetail }
        if session.isUsingMetaScribe { return SettingsCopy.metaAutoDetectDetail }
        if session.isUsingGeminiTranscriptionMode { return SettingsCopy.geminiAutoDetectDetail }
        return SettingsCopy.autoDetectDetail
    }

    private var autoDetectionStatus: String {
        if session.isUsingQwenTranslation { return SettingsCopy.enabled }
        if session.isUsingGrokSTT { return session.isGrokSourceAutoDetectionEnabled ? SettingsCopy.enabled : SettingsCopy.disabled }
        if session.isUsingNariSTT {
            return session.isNariSourceAutoDetectionEnabled ? SettingsCopy.enabled : SettingsCopy.disabled
        }
        return session.isUsingGeminiTranscriptionMode || session.isUsingMetaScribe
            ? SettingsCopy.enabled : SettingsCopy.comingSoon
    }

    private var isSessionConfigurationLocked: Bool {
        session.isRunning || session.isStarting
    }

    /// Keeps AppKit's segmented control enabled state stable while capture starts.
    /// The guarded bindings below remain the accessibility and programmatic write barrier.
    private func segmentedControlAllowsHitTesting(isOtherwiseAvailable: Bool = true) -> Bool {
        SettingsSegmentedControlAccess.allowsHitTesting(
            isRunning: session.isRunning,
            isStarting: session.isStarting,
            isOtherwiseAvailable: isOtherwiseAvailable
        )
    }

    private func lockedSessionConfigurationBinding<Value>(_ binding: Binding<Value>) -> Binding<Value> {
        Binding(
            get: { binding.wrappedValue },
            set: { value in
                guard !isSessionConfigurationLocked else { return }
                binding.wrappedValue = value
            }
        )
    }

    private var processingModeSelection: Binding<SettingsProcessingMode> {
        Binding {
            selectedProcessingMode
        } set: { mode in
            guard !isSessionConfigurationLocked else { return }
            switch mode {
            case .hyMT:
                session.useHyMTMode()
            case .apple:
                session.useAppleDefaultMode()
            case .openAI:
                session.useOpenAIMode()
            case .gemini:
                session.usePreferredGeminiMode()
            case .azure:
                session.useAzureMAIMode()
            case .qwen:
                session.useQwenTranslationMode()
            case .grok:
                session.useGrokSTTMode()
            case .nari:
                session.useNariSTTMode()
            case .meta:
                session.useMetaScribeMode()
            }
        }
    }

    private var geminiModelSelection: Binding<GeminiTranslationModel> {
        Binding {
            session.geminiTranslationModel.isEnabled
                ? session.geminiTranslationModel
                : session.preferredGeminiModel
        } set: { model in
            guard !isSessionConfigurationLocked else { return }
            session.useGeminiMode(model)
        }
    }

    @ViewBuilder
    private var qwenGeneralSettings: some View {
        SettingsControlRow(
            title: QwenCopy.modelLabel,
            detail: QwenCopy.modelDetail,
            systemImage: "waveform"
        ) {
            Picker(QwenCopy.modelLabel, selection: lockedSessionConfigurationBinding($session.qwenTranslationModel)) {
                ForEach(QwenTranslationModel.selectableCases) { model in
                    Text(model.title).tag(model)
                }
            }
            .labelsHidden()
            .frame(minWidth: 210, idealWidth: 250, maxWidth: 300)
            .disabled(isSessionConfigurationLocked)
            .accessibilityLabel(QwenCopy.modelLabel)
            .accessibilityValue(session.qwenTranslationModel.title)
            .accessibilityIdentifier("qwenRealtimeModelPicker")
        }

        SettingsNoticeRow(
            text: QwenCopy.detail(for: session.qwenTranslationModel) + "\n" + QwenCopy.price(for: session.qwenTranslationModel),
            systemImage: "waveform"
        )
        if !session.hasQwenConfiguration {
            let model = session.qwenTranslationModel.isEnabled ? session.qwenTranslationModel : session.preferredQwenModel
            SettingsNoticeActionRow(text: QwenCopy.configurationRequired(for: model), systemImage: "key", actionTitle: AppText.translationSettings) {
                session.requestAPIKeySettings(provider: .qwen)
                selectedCategory.wrappedValue = .apiKeys
            }
        }
        QwenAudioFileTranscriptionView(hasAPIKey: session.hasQwenAPIKey)
    }

    private var liveOutputModeBinding: Binding<LiveOutputMode> {
        Binding {
            session.liveOutputMode
        } set: { mode in
            guard segmentedControlAllowsHitTesting(
                isOtherwiseAvailable: !session.isUsingProviderRealtimeTranslation
            ) else { return }
            session.useLiveOutputMode(mode)
        }
    }

    private var modelSelection: Binding<IntelligenceModel> {
        Binding {
            session.selectedModel
        } set: { model in
            guard !isSessionConfigurationLocked else { return }
            switch model {
            case .appleSpeechOnly:
                session.useTranscribeOnlyMode()
            case .appleSystem, .appleOnDevice:
                session.useTranslationMode()
            }
        }
    }

    private var appVersionSummary: String {
        RunningAppVersion.current().summary ?? SettingsCopy.versionUnavailable
    }

    private func refreshPermissionStatuses() {
        screenRecordingPermission = .read(.screenRecording)
        microphonePermission = .read(.microphone)
        speechRecognitionPermission = .read(.speechRecognition)
    }

    private var savedAPIKeyBadge: String {
        let keys = [
            session.hasOpenAIAPIKey,
            session.hasGeminiAPIKey,
            session.hasMetaAPIKey,
            session.hasAzureSpeechAPIKey,
            session.hasNariAPIKey,
            session.hasGrokAPIKey,
            session.hasQwenAPIKey,
            session.hasOpenRouterAPIKey,
            session.hasJevAPIKey
        ]
        return "\(keys.filter { $0 }.count)/\(keys.count)"
    }

    private func applyRequestedSettingsCategory() {
        guard let requestedCategoryID = session.requestedSettingsCategoryID,
              let category = SettingsCategory(rawValue: requestedCategoryID)
        else { return }

        selectedCategory.wrappedValue = category
        session.requestedSettingsCategoryID = nil
    }
}

private enum SettingsProcessingMode: String, CaseIterable, Identifiable {
    case hyMT
    case apple
    case openAI
    case gemini
    case meta
    case azure
    case nari
    case grok
    case qwen

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hyMT:
            HyMTCopy.title
        case .apple:
            "Apple"
        case .openAI:
            AppText.openAIAudio
        case .gemini:
            "Gemini"
        case .azure:
            "Azure MAI"
        case .qwen:
            QwenCopy.title
        case .grok:
            GrokCopy.title
        case .nari:
            NariCopy.title
        case .meta:
            "Meta"
        }
    }
}

private enum SettingsCategory: String, CaseIterable, Hashable, Identifiable {
    case general
    case apiKeys
    case audio
    case output
    case transcript
    case floatingCaptions
    case assets
    case permissions
    case info

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general:
            SettingsCopy.general
        case .apiKeys:
            SettingsCopy.apiKeys
        case .audio:
            SettingsCopy.audio
        case .output:
            AppText.output
        case .transcript:
            AppText.transcript
        case .floatingCaptions:
            AppText.floatingCaptions
        case .assets:
            SettingsCopy.assets
        case .permissions:
            AppText.permissions
        case .info:
            SettingsCopy.info
        }
    }

    var detail: String {
        switch self {
        case .general:
            SettingsCopy.generalDetail
        case .apiKeys:
            SettingsCopy.apiKeysDetail
        case .audio:
            SettingsCopy.audioDetail
        case .output:
            SettingsCopy.outputDetail
        case .transcript:
            SettingsCopy.transcriptDetail
        case .floatingCaptions:
            SettingsCopy.floatingDetail
        case .assets:
            SettingsCopy.assetsDetail
        case .permissions:
            SettingsCopy.permissionsDetail
        case .info:
            SettingsCopy.infoDetail
        }
    }

    var systemImage: String {
        switch self {
        case .general:
            "slider.horizontal.3"
        case .apiKeys:
            "key.fill"
        case .audio:
            "mic"
        case .output:
            "waveform"
        case .transcript:
            "doc.text"
        case .floatingCaptions:
            "captions.bubble"
        case .assets:
            "cube.box"
        case .permissions:
            "shield.lefthalf.filled"
        case .info:
            "info.circle"
        }
    }
}

enum SettingsSegmentedControlAccess {
    static func allowsHitTesting(
        isRunning: Bool,
        isStarting: Bool,
        isOtherwiseAvailable: Bool = true
    ) -> Bool {
        !isRunning && !isStarting && isOtherwiseAvailable
    }
}

enum SettingsCopy {
    static let general = AppText.localized(english: "General", korean: "일반")
    static let apiKeys = AppText.localized(english: "API Keys", korean: "API 키")
    static let audio = AppText.localized(english: "Audio", korean: "오디오")
    static let assets = AppText.localized(english: "Assets", korean: "자산")
    static let info = AppText.localized(english: "Info", korean: "정보")
    static let shortcuts = AppText.localized(english: "Shortcuts", korean: "단축키", japanese: "ショートカット", chineseSimplified: "快捷键")
    static let readScreenShortcut = AppText.localized(
        english: "Read Screen Shortcut", korean: "화면 읽기 단축키",
        japanese: "画面読み上げショートカット", chineseSimplified: "朗读屏幕快捷键"
    )
    static let readScreenShortcutDetail = AppText.localized(
        english: "Starts or stops Read Screen Text from any app. Needs ⌘, ⌥ or ⌃.",
        korean: "어느 앱에서든 화면 텍스트 읽기를 시작하거나 중지합니다. ⌘, ⌥ 또는 ⌃가 필요합니다.",
        japanese: "どのアプリからでも画面テキストの読み上げを開始/停止します。⌘、⌥、⌃のいずれかが必要です。",
        chineseSimplified: "在任何应用中开始或停止朗读屏幕文字。需要包含 ⌘、⌥ 或 ⌃。"
    )
    static let typeShortcut = AppText.localized(
        english: "Type shortcut", korean: "단축키 입력", japanese: "ショートカットを入力", chineseSimplified: "输入快捷键"
    )
    static let shortcutOff = AppText.localized(english: "Off", korean: "끔", japanese: "オフ", chineseSimplified: "关闭")
    static let clearShortcut = AppText.localized(
        english: "Disable shortcut", korean: "단축키 해제", japanese: "ショートカットを無効にする", chineseSimplified: "停用快捷键"
    )
    static let resetShortcut = AppText.localized(
        english: "Reset to ⌥⌘O", korean: "⌥⌘O로 재설정", japanese: "⌥⌘Oに戻す", chineseSimplified: "重置为 ⌥⌘O"
    )
    static let shortcutUnavailable = AppText.localized(
        english: "That shortcut is already in use. Try another.",
        korean: "이미 사용 중인 단축키입니다. 다른 조합을 시도하세요.",
        japanese: "そのショートカットは既に使用されています。別の組み合わせをお試しください。",
        chineseSimplified: "该快捷键已被占用，请尝试其他组合。"
    )
    static let shortcutNeedsModifier = AppText.localized(
        english: "Include ⌘, ⌥ or ⌃ in the shortcut.",
        korean: "단축키에 ⌘, ⌥ 또는 ⌃를 포함하세요.",
        japanese: "ショートカットに⌘、⌥、⌃のいずれかを含めてください。",
        chineseSimplified: "快捷键需包含 ⌘、⌥ 或 ⌃。"
    )
    static let generalDetail = AppText.localized(
        english: "Set the default translation mode and language behavior.",
        korean: "기본 번역 방식과 언어 동작을 설정합니다."
    )
    static let apiKeysDetail = CredentialsCopy.pageDetail
    static let audioDetail = AppText.localized(
        english: "Choose where AirTranslate listens from.",
        korean: "AirTranslate가 어떤 오디오를 들을지 선택합니다."
    )
    static let outputDetail = AppText.localized(
        english: "Control what appears and whether translated speech plays.",
        korean: "표시할 결과와 번역 음성 출력을 조정합니다."
    )
    static let transcriptDetail = AppText.localized(
        english: "Tune paragraphing, long sessions, and optional transcript file saving.",
        korean: "문단 나누기, 긴 세션, 선택적 기록 파일 저장을 조정합니다."
    )
    static let floatingDetail = AppText.localized(
        english: "Configure the detachable floating caption window.",
        korean: "별도 창으로 표시되는 플로팅 자막을 설정합니다."
    )
    static let assetsDetail = AppText.localized(
        english: "Check local speech and translation assets.",
        korean: "로컬 음성 인식 및 번역 자산을 확인합니다."
    )
    static let permissionsDetail = AppText.localized(
        english: "Set up and check permissions for the selected input and engine.",
        korean: "선택한 입력과 엔진에 필요한 권한을 설정하고 확인합니다.",
        japanese: "選択した入力とエンジンに必要な権限を設定・確認します。",
        chineseSimplified: "设置并检查所选输入和引擎所需的权限。"
    )
    static let infoDetail = AppText.localized(
        english: "Review local-first behavior and privacy notes.",
        korean: "로컬 우선 동작과 개인정보 안내를 확인합니다."
    )
    static let modeSettings = AppText.localized(english: "Mode Settings", korean: "모드 설정")
    static let processingEngine = AppText.localized(english: "Processing Mode", korean: "처리 방식")
    static let processingEngineDetail = AppText.localized(
        english: "Choose exactly one active engine: local Apple mode, Hy-MT2, OpenAI Audio, Gemini Live, Meta Scribe, Azure MAI, Nari STT, Grok STT, or Qwen LiveTranslate.",
        korean: "Apple 기본 모드, Hy-MT2, OpenAI 음성, Gemini Live, Meta 스크라이브, Azure MAI, Nari STT, Grok STT, Qwen LiveTranslate 중 하나만 활성화합니다.",
        japanese: "Appleローカルモード、Hy-MT2、OpenAI音声、Gemini Live、Meta Scribe、Azure MAI、Nari STT、Grok STT、Qwen LiveTranslateから1つだけ有効にします。",
        chineseSimplified: "仅启用一种处理方式：Apple 本地模式、Hy-MT2、OpenAI 语音、Gemini Live、Meta Scribe、Azure MAI、Nari STT、Grok STT 或 Qwen LiveTranslate。"
    )
    static let enterOpenAIAPIKey = AppText.localized(
        english: "Enter OpenAI API key",
        korean: "OpenAI API 키 입력",
        japanese: "OpenAI APIキーを入力",
        chineseSimplified: "输入 OpenAI API key"
    )
    static let enterGeminiAPIKey = AppText.localized(
        english: "Enter Gemini API key",
        korean: "Gemini API 키 입력",
        japanese: "Gemini APIキーを入力",
        chineseSimplified: "输入 Gemini API key"
    )
    static let enterMetaAPIKey = AppText.localized(
        english: "Enter Meta Model API key",
        korean: "Meta Model API 키 입력",
        japanese: "Meta Model APIキーを入力",
        chineseSimplified: "输入 Meta Model API key"
    )
    static let sessionWorkflow = AppText.localized(english: "Session Workflow", korean: "세션 처리 방식")
    static let sessionWorkflowDetail = AppText.localized(
        english: "Choose translated captions or source-only transcription.",
        korean: "번역 자막 또는 원문 전사만 중에서 선택합니다."
    )
    static let realtimeTranslationOutputOnly = AppText.localized(
        english: "API live translation modes produce translated captions. For source-only captions, choose Apple transcription, OpenAI Audio → Transcribe, or Gemini Transcribe.",
        korean: "API 실시간 번역 모드는 번역 자막을 만듭니다. 원문 자막만 필요하면 Apple 전사, OpenAI 음성 → 전사 또는 Gemini 전사를 선택하세요.",
        japanese: "APIライブ翻訳モードは翻訳字幕を生成します。原文字幕のみの場合はApple文字起こし、OpenAI音声の文字起こし、またはGemini文字起こしを選択してください。",
        chineseSimplified: "API 实时翻译模式会生成翻译字幕。若只需原文字幕，请选择 Apple 转写、OpenAI 语音的转写或 Gemini 转写。"
    )
    static let languagePairDetail = AppText.localized(
        english: "Change the language pair from the console bar at the bottom of the main window.",
        korean: "언어 조합은 메인 창 하단 콘솔 바에서 변경합니다.",
        japanese: "言語の組み合わせはメインウインドウ下部のコンソールバーで変更します。",
        chineseSimplified: "语言组合可在主窗口底部的控制栏中更改。"
    )
    static let autoDetectDetail = AppText.localized(
        english: "Temporarily unavailable while automatic detection is improved.",
        korean: "자동 감지 개선 중이라 잠시 비활성화되어 있습니다."
    )
    static let geminiAutoDetectDetail = AppText.localized(
        english: "Gemini detects supported spoken languages automatically, including language changes within a session.",
        korean: "Gemini가 지원하는 음성 언어와 세션 중 언어 전환을 자동으로 감지합니다.",
        japanese: "Geminiが対応する音声言語とセッション中の言語切り替えを自動検出します。",
        chineseSimplified: "Gemini 会自动检测支持的口语及会话中的语言切换。"
    )
    static let metaAutoDetectDetail = AppText.localized(
        english: "Muse Voice Transcribe detects 25 languages automatically, including code-switching within a sentence.",
        korean: "Muse Voice Transcribe가 문장 안의 코드 스위칭을 포함해 25개 언어를 자동 감지합니다.",
        japanese: "Muse Voice Transcribeは文中のコードスイッチングを含む25言語を自動検出します。",
        chineseSimplified: "Muse Voice Transcribe 可自动检测 25 种语言，包括句内语码转换。"
    )
    static let speakerLabels = AppText.localized(
        english: "Speaker labels",
        korean: "화자 라벨",
        japanese: "話者ラベル",
        chineseSimplified: "说话人标签"
    )
    static let speakerLabelsDetail = AppText.localized(
        english: "Labels turns as Speaker A, B… Turn off for lower-latency single-speaker transcription.",
        korean: "발화 차례를 화자 A, B…로 표시합니다. 단일 화자의 지연을 낮추려면 끄세요.",
        japanese: "発話を話者A、B…と表示します。単一話者で低遅延にする場合はオフにしてください。",
        chineseSimplified: "将轮次标记为说话人 A、B…。单人转写需要更低延迟时可关闭。"
    )
    static let enabled = AppText.localized(
        english: "On",
        korean: "켜짐",
        japanese: "オン",
        chineseSimplified: "已开启"
    )
    static let disabled = AppText.localized(
        english: "Off", korean: "꺼짐", japanese: "オフ", chineseSimplified: "已关闭"
    )
    static let comingSoon = AppText.localized(
        english: "Coming soon",
        korean: "지원 예정",
        japanese: "近日対応",
        chineseSimplified: "即将支持"
    )
    static let captureRunningDisabledReason = AppText.localized(
        english: "Stop capture before changing this setting.",
        korean: "이 설정을 바꾸려면 먼저 캡처를 중지하세요."
    )
    static let openAIRealtimeDisabledReason = AppText.localized(
        english: "Transcript cleanup is disabled while OpenAI Realtime is active.",
        korean: "OpenAI Realtime이 켜져 있을 때는 기록 다듬기를 사용할 수 없습니다."
    )
    static let gptRealtimeModel = AppText.localized(
        english: "GPT Realtime Model",
        korean: "GPT Realtime 모델"
    )
    static let gptRealtimeModelDetail = AppText.localized(
        english: "Choose the translation-endpoint model used by GPT Realtime.",
        korean: "GPT Realtime에서 사용할 번역 엔드포인트 모델을 선택합니다.",
        japanese: "GPT Realtimeで使用する翻訳エンドポイントモデルを選択します。",
        chineseSimplified: "选择 GPT Realtime 使用的翻译端点模型。"
    )
    static let openAIVoiceAgentModelNotice = AppText.localized(
        english: "gpt-realtime-2.1 and 2.1-mini are voice-agent models for /v1/realtime. AirTranslate live interpretation uses gpt-realtime-translate on the translation endpoint.",
        korean: "gpt-realtime-2.1과 2.1-mini는 /v1/realtime용 보이스 에이전트 모델입니다. AirTranslate 실시간 통역은 번역 전용 엔드포인트의 gpt-realtime-translate를 사용합니다."
    )
    static let currentGPTRealtimeModel = AppText.localized(
        english: "Current GPT Realtime model",
        korean: "현재 GPT Realtime 모델"
    )
    static let currentGPTRealtimeModelDetail = AppText.localized(
        english: "Change this from General after selecting GPT Realtime.",
        korean: "GPT Realtime을 선택한 뒤 일반 설정에서 변경합니다."
    )
    static let openAIVoiceAgentModels = AppText.localized(
        english: "Voice-agent models",
        korean: "보이스 에이전트 모델"
    )
    static let openAIVoiceAgentModelsDetail = AppText.localized(
        english: "Documented OpenAI Realtime voice-agent models. They are not used for AirTranslate's live interpreter path yet.",
        korean: "공식 문서에 등록된 OpenAI Realtime 보이스 에이전트 모델입니다. 아직 AirTranslate의 실시간 통역 경로에는 사용하지 않습니다."
    )
    static let geminiTranslationDetail = AppText.localized(
        english: "Use Gemini 3.5 Live Translate for direct audio-to-live-translation sessions.",
        korean: "Gemini 3.5 Live Translate로 오디오를 직접 실시간 번역합니다."
    )
    static let geminiLiveMode = AppText.localized(
        english: "Gemini Live Mode",
        korean: "Gemini Live 모드",
        japanese: "Gemini Liveモード",
        chineseSimplified: "Gemini Live 模式"
    )
    static let geminiLiveModeDetail = AppText.localized(
        english: "Translate produces source and target captions. Transcribe detects the spoken language and keeps original captions only.",
        korean: "번역은 원문과 번역 자막을 만들고, 전사는 말하는 언어를 감지해 원문 자막만 유지합니다.",
        japanese: "翻訳は原文と翻訳字幕を生成し、文字起こしは話し言葉を検出して原文字幕のみを保持します。",
        chineseSimplified: "翻译会生成原文和译文字幕，转写会检测口语并仅保留原文字幕。"
    )
    static let translate = AppText.localized(
        english: "Translate",
        korean: "번역",
        japanese: "翻訳",
        chineseSimplified: "翻译"
    )
    static let transcribe = AppText.localized(
        english: "Transcribe",
        korean: "전사",
        japanese: "文字起こし",
        chineseSimplified: "转写"
    )
    static let originalOnly = AppText.localized(
        english: "Original only",
        korean: "원문만",
        japanese: "原文のみ",
        chineseSimplified: "仅原文"
    )
    static let geminiTranscribeSourceOnlyDetail = AppText.localized(
        english: "Gemini detects the spoken language automatically and shows original captions only.",
        korean: "Gemini가 말하는 언어를 자동 감지하고 원문 자막만 표시합니다.",
        japanese: "Geminiが話し言葉を自動検出し、原文字幕のみを表示します。",
        chineseSimplified: "Gemini 会自动检测口语，并仅显示原文字幕。"
    )
    static let appleTranscribeSourceOnlyDetail = AppText.localized(
        english: "Apple Speech shows original captions only in Transcribe mode.",
        korean: "Apple Speech 전사 모드에서는 원문 자막만 표시합니다.",
        japanese: "Apple Speechの文字起こしモードでは原文字幕のみを表示します。",
        chineseSimplified: "Apple Speech 转写模式仅显示原文字幕。"
    )
    static let audioInputDetail = AppText.localized(
        english: "Mac audio captures system playback. Microphone captures the selected input device.",
        korean: "PC 소리는 시스템 재생음을, 마이크는 선택한 입력 장치를 캡처합니다."
    )
    static let microphoneDeviceDetail = AppText.localized(
        english: "Available only when microphone input is selected.",
        korean: "마이크 입력을 선택했을 때 사용할 수 있습니다.",
        japanese: "マイク入力を選択したときに使用できます。",
        chineseSimplified: "仅在选择麦克风输入时可用。"
    )
    static let microphoneDeviceUnavailableForSystemAudioDetail = AppText.localized(
        english: "Not used for Mac Audio. Switch the audio input to Microphone to choose a device.",
        korean: "PC 소리에서는 마이크 장치를 사용하지 않습니다. 장치를 선택하려면 오디오 입력을 마이크로 바꾸세요.",
        japanese: "Mac音声ではマイクデバイスを使用しません。デバイスを選ぶには入力をマイクに切り替えてください。",
        chineseSimplified: "Mac 音频不使用麦克风设备。要选择设备，请将音频输入切换为麦克风。"
    )
    static let outputModeDetail = AppText.localized(
        english: "Translation shows source and target text. Transcribe Only keeps the source text.",
        korean: "번역은 원문과 번역을 표시하고, 전사만은 원문 기록만 유지합니다."
    )
    static let dubbingDetail = AppText.localized(
        english: "Speak translated output when a stable translated segment is available.",
        korean: "안정된 번역 문장이 생기면 번역 음성을 재생합니다."
    )
    static let translatedSpeechModel = AppText.localized(
        english: "Translated Speech Model",
        korean: "번역 음성 모델",
        japanese: "翻訳音声モデル",
        chineseSimplified: "译文语音模型"
    )
    static let translatedSpeechModelDetail = AppText.localized(
        english: "Choose how AirTranslate reads translated text in its Apple or local Hy-MT2 text translation workflow, including text transcribed by STT providers: Apple system speech, Gemini 3.8 Flash / Flash-Lite TTS, or MAI Voice 2.1 / Flash through OpenRouter. Realtime speech-translation providers use their own audio output.",
        korean: "Apple 또는 로컬 Hy-MT2로 텍스트를 번역하는 흐름(전사 제공자의 결과를 번역하는 경우 포함)에서 번역문을 읽을 음성을 선택합니다(Apple 시스템 음성, Gemini 3.8 Flash·Flash-Lite TTS 또는 OpenRouter의 MAI Voice 2.1·Flash). 실시간 음성 번역 제공자는 자체 오디오 출력을 사용합니다.",
        japanese: "AppleまたはローカルHy-MT2でテキストを翻訳するフロー（音声認識プロバイダーの文字起こし結果を翻訳する場合を含む）で読み上げる音声を選択します（Appleシステム音声、Gemini 3.8 Flash / Flash-Lite TTS または OpenRouter の MAI Voice 2.1 / Flash）。リアルタイム音声翻訳プロバイダーは独自の音声出力を使用します。",
        chineseSimplified: "选择在 Apple 或本地 Hy-MT2 文本翻译流程中朗读译文的语音，也包括翻译语音识别提供方转写出的文本（Apple 系统语音、Gemini 3.8 Flash / Flash-Lite TTS 或 OpenRouter 的 MAI Voice 2.1 / Flash）。实时语音翻译提供方使用自己的音频输出。"
    )
    static let liveTranslationVolume = AppText.localized(
        english: "Volume",
        korean: "음량"
    )
    static let liveTranslationVolumeDetail = AppText.localized(
        english: "Controls the translated speech AirTranslate plays in live translation modes.",
        korean: "실시간 번역 모드에서 AirTranslate가 재생하는 번역 음성 크기를 조절합니다."
    )
    static let speaker = AppText.localized(
        english: "Speaker", korean: "스피커", japanese: "スピーカー", chineseSimplified: "扬声器"
    )
    static let speakerDetail = AppText.localized(
        english: "Choose where translated speech plays, including Read Screen Text. You can change it during capture.",
        korean: "번역 음성(화면 텍스트 읽기 포함)이 재생될 스피커를 선택합니다. 캡처 중에도 바꿀 수 있습니다.",
        japanese: "翻訳音声（画面のテキストの読み上げを含む）の再生先を選択します。キャプチャ中も変更できます。",
        chineseSimplified: "选择译文语音（包括朗读屏幕文字）的播放设备，捕获过程中也可以更改。"
    )
    static func speakerNotConnected(_ name: String) -> String {
        AppText.localized(
            english: "\(name) (Not connected)",
            korean: "\(name) (연결되지 않음)",
            japanese: "\(name)（未接続）",
            chineseSimplified: "\(name)（未连接）"
        )
    }
    static let speakerNotConnectedNote = AppText.localized(
        english: "This speaker is not connected. Speech plays on the system default for now and switches back when it reconnects.",
        korean: "이 스피커가 연결되어 있지 않아 지금은 시스템 기본값으로 재생되며, 다시 연결되면 자동으로 전환됩니다.",
        japanese: "このスピーカーは接続されていません。今はシステムのデフォルトで再生され、再接続すると自動的に切り替わります。",
        chineseSimplified: "此扬声器未连接，目前使用系统默认设备播放，重新连接后会自动切换回来。"
    )
    static let voiceOutputDisabledReason = AppText.localized(
        english: "Turn on Voice Output to adjust translated speech volume.",
        korean: "번역 음성의 음량을 조절하려면 음성 출력을 켜세요.",
        japanese: "翻訳音声の音量を調整するには音声出力をオンにしてください。",
        chineseSimplified: "开启语音输出后才能调整译文语音音量。"
    )
    static let displaySettings = AppText.localized(english: "Display Settings", korean: "표시 설정")
    static let displayContent = AppText.localized(english: "Display Content", korean: "표시 내용")
    static let floatingTextSizeDetail = AppText.localized(
        english: "Controls the optical size used in the floating caption window.",
        korean: "플로팅 자막 창에 쓰이는 글자 크기를 조정합니다."
    )
    static let floatingCustomTextSizeDetail = AppText.localized(
        english: "Fine-tunes the caption point size without changing the saved preset.",
        korean: "저장된 preset은 유지한 채 자막 포인트 크기만 세밀하게 조정합니다.",
        japanese: "保存済みのプリセットを保ったまま、字幕のポイントサイズだけを細かく調整します。",
        chineseSimplified: "保留已保存的预设，只精细调整字幕字号。"
    )
    static let floatingLineCountDetail = AppText.localized(
        english: "Limits how many wrapped lines stay visible at once.",
        korean: "한 번에 표시되는 줄 수를 제한합니다."
    )
    static let floatingTextColorDetail = AppText.localized(
        english: "Uses one readable foreground color for source and translation text.",
        korean: "원문과 번역에 공통으로 쓰는 읽기 쉬운 글자 색상입니다.",
        japanese: "原文と翻訳に共通で使う読みやすい前景色です。",
        chineseSimplified: "源文和译文共用的易读前景颜色。"
    )
    static let floatingBackgroundColorDetail = AppText.localized(
        english: "Sets the caption box background color.",
        korean: "자막 박스 배경 색상을 설정합니다.",
        japanese: "字幕ボックスの背景色を設定します。",
        chineseSimplified: "设置字幕框背景颜色。"
    )
    static let floatingBackgroundOpacityDetail = AppText.localized(
        english: "Adjusts only the caption background opacity. Text and resize handles stay visible.",
        korean: "자막 배경 불투명도만 조정합니다. 글자와 크기 조절 핸들은 계속 보입니다.",
        japanese: "字幕背景の不透明度だけを調整します。文字とリサイズハンドルは表示されたままです。",
        chineseSimplified: "仅调整字幕背景不透明度。文字和大小调整手柄保持可见。"
    )
    static let usePresetTextSize = AppText.localized(
        english: "Use Preset",
        korean: "프리셋 사용",
        japanese: "プリセットを使用",
        chineseSimplified: "使用预设"
    )
    static let keepOnTop = AppText.localized(english: "Always On Top", korean: "항상 위에 표시")
    static let keepOnTopDetail = AppText.localized(
        english: "Keep floating captions above other windows.",
        korean: "다른 창 위에 플로팅 자막을 고정합니다."
    )
    static let floatingFooter = AppText.localized(
        english: "Floating captions appear in a separate movable window.",
        korean: "플로팅 자막은 별도 창으로 표시되며 원하는 위치로 이동할 수 있습니다."
    )
    static let floatingPreviewAccessibilityLabel = AppText.localized(
        english: "Floating caption preview. Original: We're going to focus on real-time translation. Translation: We will focus on real-time translation.",
        korean: "플로팅 자막 미리보기. 원문: We're going to focus on real-time translation. 번역: 우리는 실시간 번역에 집중할 것입니다."
    )
    static let screenRecording = AppText.localized(
        english: "Screen & System Audio Recording",
        korean: "화면 및 시스템 오디오 기록",
        japanese: "画面とシステムオーディオの収録",
        chineseSimplified: "屏幕与系统音频录制"
    )
    static let microphonePermission = AppText.localized(
        english: "Microphone",
        korean: "마이크",
        japanese: "マイク",
        chineseSimplified: "麦克风"
    )
    static let speechRecognitionPermission = AppText.localized(
        english: "Speech Recognition",
        korean: "음성 인식",
        japanese: "音声認識",
        chineseSimplified: "语音识别"
    )
    static let screenRecordingPermissionDetail = AppText.localized(
        english: "Screen recording access is required for Mac audio. To test audio input, start Mac Audio capture and play a video.",
        korean: "PC 소리 캡처에 필요한 화면 기록 권한입니다. 소리가 들어오는지 확인하려면 PC 소리로 시작한 뒤 영상을 재생하세요.",
        japanese: "Macの音声キャプチャに必要な画面収録の許可です。音声入力を確認するには、Macの音声のキャプチャを開始し、動画を再生してください。",
        chineseSimplified: "捕获 Mac 音频需要屏幕录制权限。要检查音频输入，请开始捕获 Mac 音频并播放视频。"
    )
    static let microphonePermissionDetail = AppText.localized(
        english: "Required only when Microphone is selected as the audio input.",
        korean: "오디오 입력으로 마이크를 선택할 때만 필요합니다.",
        japanese: "音声入力にマイクを選択した場合のみ必要です。",
        chineseSimplified: "仅在音频输入选择麦克风时需要。"
    )
    static let speechRecognitionPermissionDetail = AppText.localized(
        english: "Required for Apple speech recognition modes.",
        korean: "Apple 음성 인식 모드에 필요합니다.",
        japanese: "Apple音声認識モードに必要です。",
        chineseSimplified: "Apple 语音识别模式需要此权限。"
    )
    static let refreshPermissionStatus = AppText.localized(
        english: "Refresh Status",
        korean: "상태 새로고침",
        japanese: "状態を更新",
        chineseSimplified: "刷新状态"
    )
    static let openSystemSettings = AppText.localized(
        english: "Open Settings",
        korean: "설정 열기",
        japanese: "設定を開く",
        chineseSimplified: "打开设置"
    )
    static let permissionAllowed = AppText.localized(
        english: "Allowed",
        korean: "허용됨",
        japanese: "許可済み",
        chineseSimplified: "已允许"
    )
    static let permissionNotGranted = AppText.localized(
        english: "Not Allowed",
        korean: "허용 안 됨",
        japanese: "未許可",
        chineseSimplified: "未允许"
    )
    static let permissionNotDetermined = AppText.localized(
        english: "Not Requested",
        korean: "요청 전",
        japanese: "未要求",
        chineseSimplified: "尚未请求"
    )
    static let permissionRestricted = AppText.localized(
        english: "Restricted",
        korean: "제한됨",
        japanese: "制限あり",
        chineseSimplified: "受限"
    )
    static let permissionUnknown = AppText.localized(
        english: "Check in Settings",
        korean: "설정에서 확인",
        japanese: "設定で確認",
        chineseSimplified: "在设置中确认"
    )
    static let replaceSavedAPIKeyHint = AppText.localized(
        english: "A key is already saved. Entering and saving a new key replaces it.",
        korean: "키가 이미 저장되어 있습니다. 새 키를 입력해 저장하면 기존 키를 교체합니다.",
        japanese: "キーは保存済みです。新しいキーを入力して保存すると置き換えます。",
        chineseSimplified: "已有密钥。输入并保存新密钥会替换旧密钥。"
    )
    static let saveNewAPIKeyHint = AppText.localized(
        english: "Enter a provider API key, then save it to macOS Keychain.",
        korean: "제공자 API 키를 입력한 뒤 macOS 키체인에 저장합니다.",
        japanese: "プロバイダーのAPIキーを入力し、macOSキーチェーンに保存します。",
        chineseSimplified: "输入提供商 API 密钥，然后保存到 macOS 钥匙串。"
    )
    static let replaceSavedOpenAIKeyDetail = AppText.localized(
        english: "An OpenAI key is saved in macOS Keychain. Enter and save a new key to replace it.",
        korean: "OpenAI 키가 macOS 키체인에 저장되어 있습니다. 새 키를 입력하고 저장하면 교체됩니다.",
        japanese: "OpenAIキーはmacOSキーチェーンに保存済みです。新しいキーを入力して保存すると置き換えます。",
        chineseSimplified: "OpenAI 密钥已保存在 macOS 钥匙串中。输入并保存新密钥即可替换。"
    )
    static let replaceSavedGeminiKeyDetail = AppText.localized(
        english: "A Gemini key is saved in macOS Keychain. Enter and save a new key to replace it.",
        korean: "Gemini 키가 macOS 키체인에 저장되어 있습니다. 새 키를 입력하고 저장하면 교체됩니다.",
        japanese: "GeminiキーはmacOSキーチェーンに保存済みです。新しいキーを入力して保存すると置き換えます。",
        chineseSimplified: "Gemini 密钥已保存在 macOS 钥匙串中。输入并保存新密钥即可替换。"
    )
    static let required = AppText.localized(english: "Required", korean: "필수")
    static let aboutAirTranslate = AppText.localized(english: "About AirTranslate", korean: "AirTranslate 정보")
    static let localFirst = AppText.localized(english: "Local first", korean: "로컬 우선")
    static let version = AppText.localized(
        english: "Version",
        korean: "버전",
        japanese: "バージョン",
        chineseSimplified: "版本"
    )
    static let versionDetail = AppText.localized(
        english: "App version and build number.",
        korean: "앱 버전과 빌드 번호입니다.",
        japanese: "アプリのバージョンとビルド番号です。",
        chineseSimplified: "应用版本和构建编号。"
    )
    static let versionUnavailable = AppText.localized(
        english: "Unavailable",
        korean: "확인할 수 없음",
        japanese: "確認できません",
        chineseSimplified: "无法获取"
    )
    static let privacy = AppText.localized(english: "Privacy", korean: "개인정보")
    static let privacyDetail = AppText.localized(
        english: "Apple mode runs locally. Cloud providers receive audio only after you save their API key, choose the mode, and start capture.",
        korean: "Apple 모드는 로컬에서 실행됩니다. 클라우드 제공업체는 해당 API 키를 저장하고 모드를 선택한 뒤 캡처를 시작하면 오디오를 받습니다.",
        japanese: "Appleモードはローカルで動作します。クラウドサービスにはAPIキーを保存し、モードを選択してキャプチャを開始したときに音声が送信されます。",
        chineseSimplified: "Apple 模式在本地运行。保存对应 API 密钥、选择模式并开始采集后，音频才会发送给云服务。"
    )
    static let macOSKeychain = AppText.localized(
        english: "macOS Keychain",
        korean: "macOS 키체인",
        japanese: "macOSキーチェーン",
        chineseSimplified: "macOS 钥匙串"
    )
    static let retry = AppText.localized(
        english: "Retry",
        korean: "다시 시도",
        japanese: "再試行",
        chineseSimplified: "重试"
    )
    static let assetDownloadNotice = AppText.localized(
        english: "Language assets download to this Mac. Size varies by language and macOS version; progress and errors appear here.",
        korean: "언어 자산은 이 Mac에 내려받습니다. 크기는 언어와 macOS 버전에 따라 달라지며 진행 및 오류 상태는 이 화면에 표시됩니다.",
        japanese: "言語アセットはこのMacにダウンロードされます。容量は言語とmacOSのバージョンにより異なり、進行状況とエラーはここに表示されます。",
        chineseSimplified: "语言资源会下载到这台 Mac。大小因语言和 macOS 版本而异，进度和错误会显示在此处。"
    )
    static let sidebarHint = AppText.localized(
        english: "Opens this settings category.",
        korean: "이 설정 카테고리를 엽니다."
    )
}

private struct SettingsSidebar: View {
    @Binding var selection: SettingsCategory
    let savedAPIKeyBadge: String

    var body: some View {
        List {
            ForEach(SettingsCategory.allCases) { category in
                SettingsSidebarRow(
                    category: category,
                    badge: category == .apiKeys ? savedAPIKeyBadge : nil,
                    isSelected: selection == category
                ) {
                    selection = category
                }
                .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .contentMargins(.top, AirTranslateDesign.Spacing.xs, for: .scrollContent)
        .background(AirTranslateDesign.Palette.canvas)
    }
}

private struct SettingsSidebarRow: View {
    let category: SettingsCategory
    let badge: String?
    let isSelected: Bool
    let action: () -> Void
    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: action) {
            HStack(spacing: AirTranslateDesign.Spacing.sm) {
                Image(systemName: category.systemImage)
                    .font(.system(size: AirTranslateDesign.iconRegular, weight: .semibold))
                    .foregroundStyle(isSelected ? AirTranslateDesign.Palette.accent : AirTranslateDesign.Palette.textSecondary)
                    .frame(width: 20, height: 20)

                Text(category.title)
                    .font(AirTranslateDesign.Typography.label)
                    .foregroundStyle(isSelected ? AirTranslateDesign.Palette.accent : AirTranslateDesign.Palette.textSecondary)
                    .lineLimit(1)

                Spacer(minLength: 0)

                if let badge {
                    Text(badge)
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .foregroundStyle(isSelected ? AirTranslateDesign.Palette.accent : AirTranslateDesign.Palette.textTertiary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(AirTranslateDesign.Palette.raisedHover, in: Capsule())
                }
            }
            .padding(.horizontal, AirTranslateDesign.Spacing.sm)
            .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
            .background(
                isSelected ? AirTranslateDesign.Palette.accentSoft : AirTranslateDesign.Palette.transparent,
                in: RoundedRectangle(cornerRadius: AirTranslateDesign.Radius.control, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: AirTranslateDesign.Radius.control, style: .continuous))
        }
        .buttonStyle(.plain)
        .airFocusRing(focus: $isFocused)
        .accessibilityLabel(category.title)
        .accessibilityHint(SettingsCopy.sidebarHint)
    }
}

private struct SettingsPageHeader: View {
    let category: SettingsCategory

    var body: some View {
        HStack(alignment: .center, spacing: AirTranslateDesign.Spacing.md) {
            Image(systemName: category.systemImage)
                .font(.system(size: AirTranslateDesign.iconLarge, weight: .semibold))
                .foregroundStyle(AirTranslateDesign.Palette.accent)
                .frame(width: 40, height: 40)
                .background(
                    AirTranslateDesign.Palette.accentSoft,
                    in: RoundedRectangle(cornerRadius: AirTranslateDesign.Radius.control, style: .continuous)
                )

            VStack(alignment: .leading, spacing: AirTranslateDesign.Spacing.xxs) {
                Text(category.title)
                    .font(AirTranslateDesign.Typography.settingsTitle)
                    .foregroundStyle(AirTranslateDesign.Palette.textPrimary)

                Text(category.detail)
                    .font(AirTranslateDesign.Typography.label)
                    .foregroundStyle(AirTranslateDesign.Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
    }
}

private extension CapturePermissionStatus {
    var title: String {
        switch self {
        case .allowed:
            SettingsCopy.permissionAllowed
        case .notGranted, .denied:
            SettingsCopy.permissionNotGranted
        case .restricted:
            SettingsCopy.permissionRestricted
        case .notDetermined:
            SettingsCopy.permissionNotDetermined
        case .unknown:
            SettingsCopy.permissionUnknown
        }
    }

    var color: Color {
        switch self {
        case .allowed:
            AirTranslateDesign.Palette.live
        case .notDetermined, .unknown:
            AirTranslateDesign.Palette.warning
        case .notGranted, .denied, .restricted:
            AirTranslateDesign.Palette.danger
        }
    }

    var systemImage: String {
        switch self {
        case .allowed:
            "checkmark.circle.fill"
        case .notDetermined, .unknown:
            "questionmark.circle.fill"
        case .notGranted, .denied, .restricted:
            "xmark.circle.fill"
        }
    }
}

private struct SettingsPermissionRow: View {
    let title: String
    let detail: String
    let systemImage: String
    let status: CapturePermissionStatus
    let openSettings: () -> Void

    var body: some View {
        SettingsControlRow(title: title, detail: detail, systemImage: systemImage) {
            HStack(spacing: 10) {
                Label(status.title, systemImage: status.systemImage)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(status.color)
                    .accessibilityLabel("\(title): \(status.title)")

                if status != .allowed && status != .notDetermined {
                    Button(action: openSettings) {
                        Label(SettingsCopy.openSystemSettings, systemImage: "arrow.up.right.square")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityLabel("\(title), \(SettingsCopy.openSystemSettings)")
                }
            }
        }
    }
}

struct SettingsNoticeRow: View {
    let text: String
    let systemImage: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .font(.body.weight(.medium))
                .foregroundStyle(AirTranslateDesign.Palette.warning)
                .frame(width: 28, height: 28)

            Text(text)
                .font(AirTranslateDesign.Typography.meta.weight(.semibold))
                .foregroundStyle(AirTranslateDesign.Palette.warning)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(AirTranslateDesign.Spacing.sm)
        .background(
            AirTranslateDesign.Palette.pausedSoft,
            in: RoundedRectangle(cornerRadius: AirTranslateDesign.Radius.control, style: .continuous)
        )
        .padding(.vertical, AirTranslateDesign.Spacing.xxs)
        .accessibilityElement(children: .combine)
    }
}

private struct SettingsNoticeActionRow: View {
    let text: String
    let systemImage: String
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 10) {
                noticeLabel

                Spacer(minLength: 12)

                actionButton
            }
            .frame(minWidth: 520)

            VStack(alignment: .leading, spacing: 10) {
                noticeLabel
                actionButton
            }
        }
        .padding(AirTranslateDesign.Spacing.sm)
        .background(
            AirTranslateDesign.Palette.pausedSoft,
            in: RoundedRectangle(cornerRadius: AirTranslateDesign.Radius.control, style: .continuous)
        )
        .padding(.vertical, AirTranslateDesign.Spacing.xxs)
    }

    private var noticeLabel: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .font(.body.weight(.medium))
                .foregroundStyle(AirTranslateDesign.Palette.warning)
                .frame(width: 28, height: 28)

            Text(text)
                .font(AirTranslateDesign.Typography.meta.weight(.semibold))
                .foregroundStyle(AirTranslateDesign.Palette.warning)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var actionButton: some View {
        Button(action: action) {
            Label(actionTitle, systemImage: "arrow.right.circle.fill")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .accessibilityLabel(actionTitle)
    }
}

struct SettingsGroup<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: AirTranslateDesign.Spacing.xs) {
            Text(title)
                .font(AirTranslateDesign.Typography.sectionLabel)
                .tracking(0.6)
                .textCase(.uppercase)
                .foregroundStyle(AirTranslateDesign.Palette.textSecondary)

            VStack(spacing: 0) {
                content
            }
            .padding(.horizontal, AirTranslateDesign.Spacing.md)
            .padding(.vertical, AirTranslateDesign.Spacing.xxs)
            .airRaisedSurface()
        }
    }
}

struct SettingsControlRow<Trailing: View>: View {
    let title: String
    let detail: String
    let systemImage: String
    var detailLineLimit: Int? = 3
    @ViewBuilder let trailing: Trailing

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 10) {
                SettingsRowLabel(title: title, detail: detail, systemImage: systemImage, detailLineLimit: detailLineLimit)

                Spacer(minLength: 16)

                trailing
                    .controlSize(.regular)
                    .frame(maxWidth: 360, alignment: .trailing)
            }
            .frame(minWidth: AirTranslateDesign.settingsRowBreakpoint)

            VStack(alignment: .leading, spacing: 10) {
                SettingsRowLabel(title: title, detail: detail, systemImage: systemImage, detailLineLimit: detailLineLimit)
                    .frame(maxWidth: .infinity, alignment: .leading)

                trailing
                    .controlSize(.regular)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(minHeight: 64)
        .padding(.vertical, AirTranslateDesign.Spacing.xs)
        .settingsRowSeparator()
    }
}

private struct SettingsToggleRow: View {
    let title: String
    let detail: String
    let systemImage: String
    var detailLineLimit: Int? = 3
    @Binding var isOn: Bool

    var body: some View {
        SettingsControlRow(title: title, detail: detail, systemImage: systemImage, detailLineLimit: detailLineLimit) {
            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(AirTranslateDesign.Palette.accent)
        }
    }
}

private struct SettingsVolumeSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let accessibilityLabel: String

    var body: some View {
        HStack(spacing: 10) {
            Slider(value: $value, in: range, step: 0.05)
                .frame(width: 150)
                .tint(AirTranslateDesign.Palette.accent)
                .accessibilityLabel(accessibilityLabel)
                .accessibilityValue("\(Int((value * 100).rounded()))%")

            Text("\(Int((value * 100).rounded()))%")
                .font(.callout.monospacedDigit().weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .trailing)
                .accessibilityHidden(true)
        }
    }
}

private struct SettingsValueRow: View {
    let title: String
    let detail: String
    let systemImage: String
    let value: String

    var body: some View {
        SettingsControlRow(title: title, detail: detail, systemImage: systemImage) {
            Text(value)
                .font(.callout.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
    }
}

private struct SettingsRowLabel: View {
    let title: String
    let detail: String
    let systemImage: String

    var detailLineLimit: Int? = 3

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: systemImage)
                .font(.system(size: AirTranslateDesign.iconRegular, weight: .medium))
                .foregroundStyle(AirTranslateDesign.Palette.textSecondary)
                .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(AirTranslateDesign.Typography.label.weight(.semibold))
                    .foregroundStyle(AirTranslateDesign.Palette.textPrimary)

                Text(detail)
                    .font(AirTranslateDesign.Typography.meta)
                    .foregroundStyle(AirTranslateDesign.Palette.textSecondary)
                    .lineLimit(detailLineLimit)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(minWidth: 210, idealWidth: 230, maxWidth: 300, alignment: .leading)
        .layoutPriority(1)
    }
}

private struct SettingsAssetAvailabilityRow: View {
    let title: String
    let availability: ModelAvailability
    let download: () -> Void

    var body: some View {
        SettingsControlRow(
            title: title,
            detail: availability.detail,
            systemImage: symbolName
        ) {
            if availability.state == .checking || availability.state == .downloading {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityHidden(true)

                    assetStateLabel
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(title) \(availability.state.title)")
            } else if availability.state.canDownload {
                HStack(spacing: 10) {
                    assetStateLabel

                    Button(availability.state == .failed ? SettingsCopy.retry : AppText.download) {
                        download()
                    }
                    .accessibilityLabel(
                        "\(title) \(availability.state == .failed ? SettingsCopy.retry : AppText.download)"
                    )
                }
            } else {
                assetStateLabel
                    .accessibilityLabel("\(title) \(availability.state.title)")
            }
        }
        .help(availability.detail)
    }

    private var assetStateLabel: some View {
        Text(availability.state.title)
            .font(.callout.weight(.semibold))
            .foregroundStyle(color)
    }

    private var symbolName: String {
        switch availability.state {
        case .checking:
            "clock"
        case .installed:
            "checkmark.seal.fill"
        case .downloadRequired, .downloading:
            "arrow.down.circle.fill"
        case .unsupported, .unavailable, .failed:
            "exclamationmark.triangle.fill"
        }
    }

    private var color: Color {
        switch availability.state {
        case .checking:
            AirTranslateDesign.Palette.textSecondary
        case .installed:
            AirTranslateDesign.Palette.live
        case .downloadRequired, .downloading:
            AirTranslateDesign.Palette.warning
        case .unsupported, .unavailable, .failed:
            AirTranslateDesign.Palette.danger
        }
    }
}

private extension View {
    func settingsRowSeparator() -> some View {
        overlay(alignment: .bottom) {
            Rectangle()
                .fill(AirTranslateDesign.Palette.hairline)
                .frame(height: 1)
                .padding(.leading, 42)
        }
    }
}
