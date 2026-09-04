import AVFoundation
import CoreGraphics
import Speech
import SwiftUI

struct SettingsView: View {
    @Bindable var session: TranslationSessionStore
    @SceneStorage("AirTranslate.SettingsView.selectedCategory") private var selectedCategoryID = SettingsCategory.general.rawValue
    @State private var openAIAPIKey = ""
    @State private var openAIKeyFeedback: APIKeyFeedback?
    @State private var isConfirmingOpenAIKeyRemoval = false
    @State private var geminiAPIKey = ""
    @State private var geminiKeyFeedback: APIKeyFeedback?
    @State private var isConfirmingGeminiKeyRemoval = false
    @State private var metaAPIKey = ""
    @State private var metaKeyFeedback: APIKeyFeedback?
    @State private var isConfirmingMetaKeyRemoval = false
    @State private var screenRecordingPermission: SettingsPermissionState = .unknown
    @State private var microphonePermission: SettingsPermissionState = .unknown
    @State private var speechRecognitionPermission: SettingsPermissionState = .unknown

    var body: some View {
        NavigationSplitView {
            SettingsSidebar(selection: selectedCategory)
                .navigationSplitViewColumnWidth(
                    min: AirTranslateDesign.settingsSidebarMinimum,
                    ideal: AirTranslateDesign.settingsSidebarIdeal,
                    max: AirTranslateDesign.settingsSidebarMaximum
                )
        } detail: {
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
        .task(id: selectedCategoryID) {
            if selectedCategory.wrappedValue == .permissions {
                refreshPermissionStatuses()
            }
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

            if (processingModeSelection.wrappedValue == .openAI || processingModeSelection.wrappedValue == .gptTranscription), !session.hasOpenAIAPIKey {
                SettingsNoticeActionRow(
                    text: AppText.openAIAPIKeyRequiredForGPTMode,
                    systemImage: "key",
                    actionTitle: SettingsCopy.enterOpenAIAPIKey
                ) {
                    selectedCategory.wrappedValue = .apiKeys
                }
            }

            if processingModeSelection.wrappedValue == .openAI {
                SettingsControlRow(
                    title: SettingsCopy.gptRealtimeModel,
                    detail: SettingsCopy.gptRealtimeModelDetail,
                    systemImage: "waveform.badge.magnifyingglass"
                ) {
                    Picker(SettingsCopy.gptRealtimeModel, selection: openAIRealtimeModelSelection) {
                        ForEach(OpenAIRealtimeTranslationModel.liveTranslationCases) { model in
                            Text(model.title).tag(model)
                        }
                    }
                    .labelsHidden()
                    .frame(minWidth: 260, idealWidth: 320, maxWidth: 360)
                    .disabled(isSessionConfigurationLocked)
                    .accessibilityLabel(SettingsCopy.gptRealtimeModel)
                }

                SettingsNoticeRow(text: SettingsCopy.openAIVoiceAgentModelNotice, systemImage: "info.circle")
            }

            if processingModeSelection.wrappedValue == .gptTranscription {
                SettingsControlRow(
                    title: AppText.gptTranscriptionModel,
                    detail: AppText.gptTranscriptionModeDescription,
                    systemImage: "waveform.badge.mic"
                ) {
                    Text(OpenAIRealtimeTranscriptionModel.gptLiveTranscribe.title)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(AirTranslateDesign.Palette.accent)
                }
                SettingsNoticeRow(text: AppText.gptTranscriptionSourceOnly, systemImage: "text.quote")
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

            SettingsValueRow(
                title: AppText.languages,
                detail: SettingsCopy.languagePairDetail,
                systemImage: "globe",
                value: session.languageSummary
            )

            SettingsValueRow(
                title: AppText.autoDetectInput,
                detail: session.isUsingMetaScribe
                    ? SettingsCopy.metaAutoDetectDetail
                    : session.isUsingGeminiTranscriptionMode
                        ? SettingsCopy.geminiAutoDetectDetail
                        : SettingsCopy.autoDetectDetail,
                systemImage: "sparkles",
                value: session.isUsingGeminiTranscriptionMode || session.isUsingMetaScribe
                    ? SettingsCopy.enabled
                    : SettingsCopy.comingSoon
            )
        }
    }

    private var apiSettings: some View {
        SettingsGroup(title: AppText.openAIAPIKey) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "key.fill")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(session.hasOpenAIAPIKey ? AirTranslateDesign.Palette.live : AirTranslateDesign.Palette.textSecondary)
                        .frame(width: 24)

                    SecureField(AppText.openAIAPIKeyPlaceholder, text: $openAIAPIKey)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(saveOpenAIAPIKey)
                        .accessibilityLabel(AppText.openAIAPIKey)
                        .accessibilityHint(
                            session.hasOpenAIAPIKey
                                ? SettingsCopy.replaceSavedAPIKeyHint
                                : SettingsCopy.saveNewAPIKeyHint
                        )

                    Button {
                        saveOpenAIAPIKey()
                    } label: {
                        Image(systemName: "checkmark.circle.fill")
                    }
                    .disabled(openAIAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .help(AppText.saveOpenAIAPIKey)
                    .accessibilityLabel(AppText.saveOpenAIAPIKey)

                    Button {
                        isConfirmingOpenAIKeyRemoval = true
                    } label: {
                        Image(systemName: "trash")
                    }
                    .disabled(!session.hasOpenAIAPIKey)
                    .help(AppText.removeOpenAIAPIKey)
                    .accessibilityLabel(AppText.removeOpenAIAPIKey)
                    .confirmationDialog(
                        AppText.localized(
                            english: "Remove the saved OpenAI API key from Keychain?",
                            korean: "Keychain에 저장된 OpenAI API 키를 삭제할까요?",
                            japanese: "Keychainに保存されたOpenAI APIキーを削除しますか？",
                            chineseSimplified: "要从 Keychain 中删除已保存的 OpenAI API key 吗？"
                        ),
                        isPresented: $isConfirmingOpenAIKeyRemoval
                    ) {
                        Button(AppText.removeOpenAIAPIKey, role: .destructive) {
                            removeOpenAIAPIKey()
                        }
                        Button(AppText.cancel, role: .cancel) {}
                    }
                }

                APIKeyStatusRow(
                    feedback: $openAIKeyFeedback,
                    fallback: APIKeyFeedback(
                        kind: session.hasOpenAIAPIKey ? .success : .warning,
                        message: session.hasOpenAIAPIKey ? AppText.openAIAPIKeyConfigured : AppText.openAIAPIKeyNotConfigured
                    )
                )

                Text(
                    session.hasOpenAIAPIKey
                        ? SettingsCopy.replaceSavedOpenAIKeyDetail
                        : AppText.openAIAPIKeyDescription
                )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 34)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 3)

            SettingsControlRow(
                title: SettingsCopy.currentGPTRealtimeModel,
                detail: SettingsCopy.currentGPTRealtimeModelDetail,
                systemImage: "waveform"
            ) {
                Text(session.openAITranslationModel.isEnabled ? session.openAITranslationModel.title : OpenAIRealtimeTranslationModel.gptRealtimeTranslate.title)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(AirTranslateDesign.Palette.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }

            SettingsValueRow(
                title: SettingsCopy.openAIVoiceAgentModels,
                detail: SettingsCopy.openAIVoiceAgentModelsDetail,
                systemImage: "person.wave.2",
                value: OpenAIRealtimeTranslationModel.voiceAgentCases.map(\.rawValue).joined(separator: ", ")
            )
        }
    }

    private var apiKeySettings: some View {
        VStack(alignment: .leading, spacing: 24) {
            apiSettings
            geminiSettings
            metaSettings
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
                .frame(width: 190)
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

            if session.isTranscribeOnlyMode {
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
                    .frame(width: 170)
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

            if session.isUsingProviderRealtimeTranslation {
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
        }
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
                .frame(width: 190)
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
        VStack(alignment: .leading, spacing: 24) {
            FloatingCaptionPreview(
                displayMode: session.floatingCaptionDisplayMode,
                textSize: session.floatingCaptionTextSize,
                lineCount: session.floatingCaptionLineCount,
                alignment: session.floatingCaptionTextAlignment
            )

            SettingsGroup(title: SettingsCopy.presentationQuality) {
                if isSessionConfigurationLocked {
                    SettingsNoticeRow(text: SettingsCopy.captureRunningDisabledReason, systemImage: "pause.circle")
                }

                SettingsToggleRow(
                    title: SettingsCopy.presentationQualityMode,
                    detail: SettingsCopy.presentationQualityModeDetail,
                    systemImage: "person.crop.rectangle.badge.checkmark",
                    isOn: lockedSessionConfigurationBinding($session.isPresentationQualityModeEnabled)
                )
                .disabled(isSessionConfigurationLocked)

                if session.isPresentationQualityModeEnabled {
                    SettingsControlRow(
                        title: SettingsCopy.presentationContext,
                        detail: SettingsCopy.presentationContextDetail,
                        systemImage: "text.book.closed"
                    ) {
                        TextField(
                            SettingsCopy.presentationContextPlaceholder,
                            text: lockedSessionConfigurationBinding($session.presentationContext),
                            axis: .vertical
                        )
                        .lineLimit(2...4)
                        .textFieldStyle(.roundedBorder)
                        .frame(minWidth: 260, maxWidth: 360)
                        .disabled(isSessionConfigurationLocked)
                    }

                    SettingsControlRow(
                        title: SettingsCopy.presentationGlossary,
                        detail: SettingsCopy.presentationGlossaryDetail,
                        systemImage: "character.book.closed"
                    ) {
                        TextField(
                            SettingsCopy.presentationGlossaryPlaceholder,
                            text: lockedSessionConfigurationBinding($session.presentationGlossary),
                            axis: .vertical
                        )
                        .lineLimit(4...8)
                        .font(.callout.monospaced())
                        .textFieldStyle(.roundedBorder)
                        .frame(minWidth: 260, maxWidth: 360)
                        .disabled(isSessionConfigurationLocked)
                    }

                    SettingsNoticeRow(
                        text: SettingsCopy.presentationQualityNotice,
                        systemImage: "checkmark.seal"
                    )
                }
            }

            SettingsGroup(title: SettingsCopy.displaySettings) {
                SettingsControlRow(
                    title: SettingsCopy.displayContent,
                    detail: AppText.floatingDisplayDescription,
                    systemImage: "captions.bubble"
                ) {
                    Picker(AppText.floatingDisplay, selection: $session.floatingCaptionDisplayMode) {
                        ForEach(session.availableFloatingCaptionDisplayModes) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 168)
                }

                SettingsControlRow(
                    title: AppText.floatingTextSize,
                    detail: SettingsCopy.floatingTextSizeDetail,
                    systemImage: "textformat.size"
                ) {
                    Picker(AppText.floatingTextSize, selection: $session.floatingCaptionTextSize) {
                        ForEach(FloatingCaptionTextSize.allCases) { size in
                            Text(size.title).tag(size)
                        }
                    }
                    .pickerStyle(.segmented)
                    .tint(AirTranslateDesign.Palette.accent)
                    .labelsHidden()
                    .frame(width: 232)
                }

                SettingsControlRow(
                    title: AppText.floatingLineCount,
                    detail: SettingsCopy.floatingLineCountDetail,
                    systemImage: "line.3.horizontal"
                ) {
                    Picker(AppText.floatingLineCount, selection: $session.floatingCaptionLineCount) {
                        ForEach(FloatingCaptionLineCount.allCases) { lineCount in
                            Text(lineCount.title).tag(lineCount)
                        }
                    }
                    .pickerStyle(.segmented)
                    .tint(AirTranslateDesign.Palette.accent)
                    .labelsHidden()
                    .frame(width: 252)
                }

                SettingsControlRow(
                    title: AppText.captionStability,
                    detail: AppText.captionStabilityDescription,
                    systemImage: "waveform.path.ecg"
                ) {
                    Picker(AppText.captionStability, selection: $session.floatingCaptionStability) {
                        ForEach(FloatingCaptionStability.allCases) { stability in
                            Text(stability.title).tag(stability)
                        }
                    }
                    .pickerStyle(.segmented)
                    .tint(AirTranslateDesign.Palette.accent)
                    .labelsHidden()
                    .frame(width: 232)
                }

                SettingsControlRow(
                    title: AppText.captionAlignment,
                    detail: AppText.captionAlignmentDescription,
                    systemImage: "text.aligncenter"
                ) {
                    Picker(AppText.captionAlignment, selection: $session.floatingCaptionTextAlignment) {
                        ForEach(FloatingCaptionTextAlignment.allCases) { alignment in
                            Text(alignment.title).tag(alignment)
                        }
                    }
                    .pickerStyle(.segmented)
                    .tint(AirTranslateDesign.Palette.accent)
                    .labelsHidden()
                    .frame(width: 168)
                }

                SettingsToggleRow(
                    title: SettingsCopy.keepOnTop,
                    detail: SettingsCopy.keepOnTopDetail,
                    systemImage: "pin",
                    isOn: $session.keepsFloatingCaptionAboveOtherWindows
                )
            }

            Label(SettingsCopy.floatingFooter, systemImage: "info.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
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

            Label(SettingsCopy.assetDownloadNotice, systemImage: "internaldrive")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var permissionSettings: some View {
        SettingsGroup(title: AppText.permissions) {
            SettingsPermissionRow(
                title: SettingsCopy.screenRecording,
                detail: SettingsCopy.screenRecordingPermissionDetail,
                systemImage: "rectangle.dashed.badge.record",
                status: screenRecordingPermission
            ) {
                session.openPrivacySettings(.screenRecording)
            }

            SettingsPermissionRow(
                title: SettingsCopy.systemAudioRecording,
                detail: SettingsCopy.systemAudioPermissionDetail,
                systemImage: "speaker.wave.2",
                status: .unknown
            ) {
                session.openPrivacySettings(.systemAudioRecording)
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
                Label(SettingsCopy.permissionReadOnlyNotice, systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 16)

                Button(action: refreshPermissionStatuses) {
                    Label(SettingsCopy.refreshPermissionStatus, systemImage: "arrow.clockwise")
                }
                .accessibilityHint(SettingsCopy.permissionReadOnlyNotice)
            }
            .padding(.vertical, 8)
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

    private var geminiSettings: some View {
        SettingsGroup(title: AppText.geminiModels) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "key.fill")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(session.hasGeminiAPIKey ? AirTranslateDesign.Palette.live : AirTranslateDesign.Palette.textSecondary)
                        .frame(width: 24)

                    SecureField(AppText.geminiAPIKeyPlaceholder, text: $geminiAPIKey)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(saveGeminiAPIKey)
                        .accessibilityLabel(AppText.geminiAPIKey)
                        .accessibilityHint(
                            session.hasGeminiAPIKey
                                ? SettingsCopy.replaceSavedAPIKeyHint
                                : SettingsCopy.saveNewAPIKeyHint
                        )

                    Button {
                        saveGeminiAPIKey()
                    } label: {
                        Image(systemName: "checkmark.circle.fill")
                    }
                    .disabled(geminiAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .help(AppText.saveGeminiAPIKey)
                    .accessibilityLabel(AppText.saveGeminiAPIKey)

                    Button {
                        isConfirmingGeminiKeyRemoval = true
                    } label: {
                        Image(systemName: "trash")
                    }
                    .disabled(!session.hasGeminiAPIKey)
                    .help(AppText.removeGeminiAPIKey)
                    .accessibilityLabel(AppText.removeGeminiAPIKey)
                    .confirmationDialog(
                        AppText.localized(
                            english: "Remove the saved Gemini API key from Keychain?",
                            korean: "Keychain에 저장된 Gemini API 키를 삭제할까요?",
                            japanese: "Keychainに保存されたGemini APIキーを削除しますか？",
                            chineseSimplified: "要从 Keychain 中删除已保存的 Gemini API key 吗？"
                        ),
                        isPresented: $isConfirmingGeminiKeyRemoval
                    ) {
                        Button(AppText.removeGeminiAPIKey, role: .destructive) {
                            removeGeminiAPIKey()
                        }
                        Button(AppText.cancel, role: .cancel) {}
                    }
                }

                APIKeyStatusRow(
                    feedback: $geminiKeyFeedback,
                    fallback: APIKeyFeedback(
                        kind: session.hasGeminiAPIKey ? .success : .warning,
                        message: session.hasGeminiAPIKey ? AppText.geminiAPIKeyConfigured : AppText.geminiAPIKeyNotConfigured
                    )
                )

                Text(
                    session.hasGeminiAPIKey
                        ? SettingsCopy.replaceSavedGeminiKeyDetail
                        : AppText.geminiAPIKeyDescription
                )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 34)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 3)

            SettingsControlRow(
                title: AppText.geminiTranslationModel,
                detail: SettingsCopy.geminiLiveModeDetail,
                systemImage: "sparkles"
            ) {
                Text(
                    session.geminiTranslationModel.isEnabled
                        ? session.geminiTranslationModel.title
                        : session.preferredGeminiModel.title
                )
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(selectedProcessingMode == .gemini ? AirTranslateDesign.Palette.accent : AirTranslateDesign.Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var metaSettings: some View {
        SettingsGroup(title: AppText.metaScribe) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "key.fill")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(session.hasMetaAPIKey ? AirTranslateDesign.Palette.live : AirTranslateDesign.Palette.textSecondary)
                        .frame(width: 24)

                    SecureField(AppText.metaAPIKeyPlaceholder, text: $metaAPIKey)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(saveMetaAPIKey)
                        .accessibilityLabel(AppText.metaAPIKey)
                        .accessibilityHint(
                            session.hasMetaAPIKey
                                ? SettingsCopy.replaceSavedAPIKeyHint
                                : SettingsCopy.saveNewAPIKeyHint
                        )

                    Button {
                        saveMetaAPIKey()
                    } label: {
                        Image(systemName: "checkmark.circle.fill")
                    }
                    .disabled(metaAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .help(AppText.saveMetaAPIKey)
                    .accessibilityLabel(AppText.saveMetaAPIKey)

                    Button {
                        isConfirmingMetaKeyRemoval = true
                    } label: {
                        Image(systemName: "trash")
                    }
                    .disabled(!session.hasMetaAPIKey)
                    .help(AppText.removeMetaAPIKey)
                    .accessibilityLabel(AppText.removeMetaAPIKey)
                    .confirmationDialog(
                        AppText.localized(
                            english: "Remove the saved Meta Model API key from Keychain?",
                            korean: "Keychain에 저장된 Meta Model API 키를 삭제할까요?",
                            japanese: "Keychainに保存されたMeta Model APIキーを削除しますか？",
                            chineseSimplified: "要从 Keychain 中删除已保存的 Meta Model API key 吗？"
                        ),
                        isPresented: $isConfirmingMetaKeyRemoval
                    ) {
                        Button(AppText.removeMetaAPIKey, role: .destructive) {
                            removeMetaAPIKey()
                        }
                        Button(AppText.cancel, role: .cancel) {}
                    }
                }

                APIKeyStatusRow(
                    feedback: $metaKeyFeedback,
                    fallback: APIKeyFeedback(
                        kind: session.hasMetaAPIKey ? .success : .warning,
                        message: session.hasMetaAPIKey
                            ? AppText.metaAPIKeyConfigured
                            : AppText.metaAPIKeyNotConfigured
                    )
                )

                Text(
                    session.hasMetaAPIKey
                        ? AppText.replaceSavedMetaAPIKeyDescription
                        : AppText.metaAPIKeyDescription
                )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 34)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 3)

            SettingsControlRow(
                title: AppText.metaScribe,
                detail: AppText.metaScribeDetail,
                systemImage: "person.2.wave.2"
            ) {
                Text(MetaTranscriptionModel.museVoiceTranscribe.title)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(selectedProcessingMode == .meta ? AirTranslateDesign.Palette.accent : AirTranslateDesign.Palette.textSecondary)
            }

            HStack(spacing: 6) {
                Text(AppText.metaAPIKeyPlatformPrompt)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Link(
                    AppText.metaAPIKeyPlatformLink,
                    destination: URL(string: "https://dev.meta.ai")!
                )
                .tint(AirTranslateDesign.Palette.accent)
                .font(.caption.weight(.semibold))
            }
            .padding(.vertical, 9)
            .settingsRowSeparator()
        }
    }

    private var selectedProcessingMode: SettingsProcessingMode {
        if session.isUsingMetaScribe {
            return .meta
        }
        if session.isUsingGPTTranscriptionMode {
            return .gptTranscription
        }
        if session.isUsingOpenAIRealtime {
            return .openAI
        }
        if session.isUsingGemini {
            return .gemini
        }
        return .apple
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
            case .apple:
                session.useAppleDefaultMode()
            case .openAI:
                session.useGPTRealtimeMode()
            case .gptTranscription:
                session.useGPTTranscriptionMode()
            case .gemini:
                session.usePreferredGeminiMode()
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

    private var openAIRealtimeModelSelection: Binding<OpenAIRealtimeTranslationModel> {
        Binding {
            session.openAITranslationModel.isSupportedLiveTranslationModel ? session.openAITranslationModel : .gptRealtimeTranslate
        } set: { model in
            guard !isSessionConfigurationLocked else { return }
            session.useGPTRealtimeMode(model: model)
        }
    }

    private func saveOpenAIAPIKey() {
        let trimmedKey = openAIAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            openAIKeyFeedback = APIKeyFeedback(kind: .error, message: AppText.openAIAPIKeyEmpty)
            return
        }

        do {
            try session.saveOpenAIAPIKey(trimmedKey)
        } catch {
            openAIKeyFeedback = APIKeyFeedback(kind: .error, message: error.localizedDescription)
            return
        }

        openAIKeyFeedback = APIKeyFeedback(kind: .success, message: AppText.openAIAPIKeySaved)
        openAIAPIKey = ""
    }

    private func removeOpenAIAPIKey() {
        do {
            try session.removeOpenAIAPIKey()
        } catch {
            openAIKeyFeedback = APIKeyFeedback(kind: .error, message: error.localizedDescription)
            return
        }

        openAIKeyFeedback = APIKeyFeedback(kind: .warning, message: AppText.openAIAPIKeyRemoved)
        openAIAPIKey = ""
    }

    private func saveGeminiAPIKey() {
        let trimmedKey = geminiAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            geminiKeyFeedback = APIKeyFeedback(kind: .error, message: AppText.geminiAPIKeyEmpty)
            return
        }

        do {
            try session.saveGeminiAPIKey(trimmedKey)
        } catch {
            geminiKeyFeedback = APIKeyFeedback(kind: .error, message: error.localizedDescription)
            return
        }

        geminiKeyFeedback = APIKeyFeedback(kind: .success, message: AppText.geminiAPIKeySaved)
        geminiAPIKey = ""
    }

    private func removeGeminiAPIKey() {
        do {
            try session.removeGeminiAPIKey()
        } catch {
            geminiKeyFeedback = APIKeyFeedback(kind: .error, message: error.localizedDescription)
            return
        }

        geminiKeyFeedback = APIKeyFeedback(kind: .warning, message: AppText.geminiAPIKeyRemoved)
        geminiAPIKey = ""
    }

    private func saveMetaAPIKey() {
        let trimmedKey = metaAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            metaKeyFeedback = APIKeyFeedback(kind: .error, message: AppText.metaAPIKeyEmpty)
            return
        }
        do {
            try session.saveMetaAPIKey(trimmedKey)
        } catch {
            metaKeyFeedback = APIKeyFeedback(kind: .error, message: error.localizedDescription)
            return
        }
        metaKeyFeedback = APIKeyFeedback(kind: .success, message: AppText.metaAPIKeySaved)
        metaAPIKey = ""
    }

    private func removeMetaAPIKey() {
        do {
            try session.removeMetaAPIKey()
        } catch {
            metaKeyFeedback = APIKeyFeedback(kind: .error, message: error.localizedDescription)
            return
        }
        metaKeyFeedback = APIKeyFeedback(kind: .warning, message: AppText.metaAPIKeyRemoved)
        metaAPIKey = ""
    }

    private var appVersionSummary: String {
        RunningAppVersion.current().summary ?? SettingsCopy.versionUnavailable
    }

    private func refreshPermissionStatuses() {
        screenRecordingPermission = CGPreflightScreenCaptureAccess() ? .allowed : .notGranted

        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            microphonePermission = .allowed
        case .denied:
            microphonePermission = .denied
        case .restricted:
            microphonePermission = .restricted
        case .notDetermined:
            microphonePermission = .notDetermined
        @unknown default:
            microphonePermission = .unknown
        }

        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            speechRecognitionPermission = .allowed
        case .denied:
            speechRecognitionPermission = .denied
        case .restricted:
            speechRecognitionPermission = .restricted
        case .notDetermined:
            speechRecognitionPermission = .notDetermined
        @unknown default:
            speechRecognitionPermission = .unknown
        }
    }

    private func applyRequestedSettingsCategory() {
        guard let requestedCategoryID = session.requestedSettingsCategoryID,
              let category = SettingsCategory(rawValue: requestedCategoryID)
        else { return }

        selectedCategory.wrappedValue = category
        session.requestedSettingsCategoryID = nil
    }
}

private struct APIKeyFeedback: Equatable {
    enum Kind: Equatable {
        case success
        case warning
        case error
    }

    let kind: Kind
    let message: String
    private let token = UUID()

    var color: Color {
        switch kind {
        case .success:
            AirTranslateDesign.Palette.live
        case .warning:
            AirTranslateDesign.Palette.warning
        case .error:
            AirTranslateDesign.Palette.danger
        }
    }
}

private struct APIKeyStatusRow: View {
    @Binding var feedback: APIKeyFeedback?
    let fallback: APIKeyFeedback

    private var current: APIKeyFeedback {
        feedback ?? fallback
    }

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(current.color)
                .frame(width: 7, height: 7)

            Text(current.message)
                .font(.caption.weight(.semibold))
                .foregroundStyle(current.color)
        }
        .padding(.leading, 34)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(current.message)
        .task(id: feedback) {
            guard feedback != nil else { return }
            guard (try? await Task.sleep(for: .seconds(6))) != nil else { return }
            feedback = nil
        }
    }
}

private enum SettingsProcessingMode: String, CaseIterable, Identifiable {
    case apple
    case openAI
    case gptTranscription
    case gemini
    case meta

    var id: String { rawValue }

    var title: String {
        switch self {
        case .apple:
            "Apple"
        case .openAI:
            AppText.localized(
                english: "GPT Realtime",
                korean: "GPT Realtime",
                japanese: "GPT Realtime",
                chineseSimplified: "GPT Realtime"
            )
        case .gptTranscription:
            AppText.localized(
                english: "GPT Transcribe",
                korean: "GPT 전사",
                japanese: "GPT文字起こし",
                chineseSimplified: "GPT 转写"
            )
        case .gemini:
            "Gemini"
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

private enum SettingsCopy {
    static let general = AppText.localized(english: "General", korean: "일반")
    static let apiKeys = AppText.localized(english: "API Keys", korean: "API 키")
    static let audio = AppText.localized(english: "Audio", korean: "오디오")
    static let assets = AppText.localized(english: "Assets", korean: "자산")
    static let info = AppText.localized(english: "Info", korean: "정보")
    static let generalDetail = AppText.localized(
        english: "Set the default translation mode and language behavior.",
        korean: "기본 번역 방식과 언어 동작을 설정합니다."
    )
    static let apiKeysDetail = AppText.localized(
        english: "Save provider keys for OpenAI, Gemini Live, and Meta Scribe modes.",
        korean: "OpenAI, Gemini Live, Meta 스크라이브 모드에 사용할 키를 저장합니다.",
        japanese: "OpenAI、Gemini Live、Meta Scribeモードで使用するキーを保存します。",
        chineseSimplified: "保存 OpenAI、Gemini Live 和 Meta Scribe 模式使用的密钥。"
    )
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
        english: "Open macOS privacy controls required for capture.",
        korean: "캡처에 필요한 macOS 개인정보 보호 권한을 엽니다."
    )
    static let infoDetail = AppText.localized(
        english: "Review local-first behavior and privacy notes.",
        korean: "로컬 우선 동작과 개인정보 안내를 확인합니다."
    )
    static let modeSettings = AppText.localized(english: "Mode Settings", korean: "모드 설정")
    static let presentationQuality = AppText.localized(
        english: "Presentation Quality",
        korean: "프레젠테이션 품질",
        japanese: "プレゼンテーション品質",
        chineseSimplified: "演示质量"
    )
    static let presentationQualityMode = AppText.localized(
        english: "Presentation Quality Mode",
        korean: "프레젠테이션 품질 모드",
        japanese: "プレゼンテーション品質モード",
        chineseSimplified: "演示质量模式"
    )
    static let presentationQualityModeDetail = AppText.localized(
        english: "Starts with audience defaults: translation only, two large steady lines, left aligned, with smarter clause timing.",
        korean: "번역만 표시되는 크고 안정적인 두 줄, 왼쪽 정렬, 더 자연스러운 구절 타이밍을 청중용 기본값으로 적용합니다.",
        japanese: "翻訳のみ・大きな2行・安定表示・左揃え・自然な節のタイミングを観客向け初期設定として適用します。",
        chineseSimplified: "以观众字幕默认设置开始：仅译文、两行大字、稳定左对齐，并采用更自然的分句时机。"
    )
    static let presentationContext = AppText.localized(
        english: "Talk Context",
        korean: "발표 맥락",
        japanese: "講演の背景",
        chineseSimplified: "演讲背景"
    )
    static let presentationContextDetail = AppText.localized(
        english: "Describe the audience and topic in up to 1,000 characters. GPT text translation sends this to OpenAI to choose meaning and tone.",
        korean: "청중과 주제를 1,000자 이내로 설명하세요. GPT 텍스트 번역은 의미와 어조를 선택하기 위해 이 내용을 OpenAI로 전송합니다.",
        japanese: "聴衆とテーマを1,000文字以内で説明します。GPTテキスト翻訳では意味と語調を選ぶため、この内容をOpenAIへ送信します。",
        chineseSimplified: "用不超过 1,000 个字符描述听众和主题。GPT 文本翻译会将其发送至 OpenAI，以选择合适的语义和语气。"
    )
    static let presentationContextPlaceholder = AppText.localized(
        english: "Example: Practical AI workshop for Japanese ecommerce business owners",
        korean: "예: 일본 이커머스 사업자를 위한 실전 AI 워크숍",
        japanese: "例：日本のEC事業者向け実践AIワークショップ",
        chineseSimplified: "例如：面向日本电商经营者的实用 AI 工作坊"
    )
    static let presentationGlossary = AppText.localized(
        english: "Terminology Glossary",
        korean: "용어집",
        japanese: "用語集",
        chineseSimplified: "术语表"
    )
    static let presentationGlossaryDetail = AppText.localized(
        english: "Up to 50 lines; 120 characters per term. Add likely speech-recognition mistakes as separate aliases.",
        korean: "최대 50줄, 용어당 120자까지 입력할 수 있습니다. 예상되는 음성 인식 오류는 별칭으로 따로 추가하세요.",
        japanese: "最大50行、各用語120文字までです。想定される音声認識ミスは別名として追加してください。",
        chineseSimplified: "最多 50 行，每个术语不超过 120 个字符。可能的语音识别错误请另加一行作为别名。"
    )
    static let presentationGlossaryPlaceholder = AppText.localized(
        english: "Gary Hong = ゲイリー・ウォン\nAI for Business = ビジネス向けAI",
        korean: "Gary Hong = 게리 웡\nAI for Business = 비즈니스용 AI",
        japanese: "Gary Hong = ゲイリー・ウォン\nAI for Business = ビジネス向けAI",
        chineseSimplified: "Gary Hong = Gary Wong\nAI for Business = 商业 AI"
    )
    static let presentationQualityNotice = AppText.localized(
        english: "Cloud note: GPT text translation sends the context and glossary to OpenAI. Meta Scribe receives glossary source terms as recognition hints. Apple processing stays on this Mac.",
        korean: "클라우드 안내: GPT 텍스트 번역은 맥락과 용어집을 OpenAI로 전송합니다. Meta Scribe는 원문 용어를 인식 힌트로 받습니다. Apple 처리는 이 Mac에서만 실행됩니다.",
        japanese: "クラウド利用について：GPTテキスト翻訳では背景と用語集をOpenAIへ送信します。Meta Scribeには原語を認識ヒントとして渡します。Apple処理はこのMac内で行われます。",
        chineseSimplified: "云端说明：GPT 文本翻译会将背景和术语表发送至 OpenAI；Meta Scribe 会接收原词作为识别提示；Apple 处理仅在本机进行。"
    )
    static let processingEngine = AppText.localized(english: "Processing Mode", korean: "처리 방식")
    static let processingEngineDetail = AppText.localized(
        english: "Choose exactly one active engine: local Apple mode, GPT Realtime, GPT Transcription, Gemini Live, or Meta Scribe.",
        korean: "Apple 기본 모드, GPT Realtime, GPT 전사, Gemini Live, Meta 스크라이브 중 하나만 활성화합니다.",
        japanese: "Appleローカルモード、GPT Realtime、GPT文字起こし、Gemini Live、Meta Scribeから1つだけ有効にします。",
        chineseSimplified: "仅启用一种处理方式：Apple 本地模式、GPT Realtime、GPT 转写、Gemini Live 或 Meta Scribe。"
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
        english: "Apple mode can switch between translation and source-only transcription.",
        korean: "Apple 모드에서 번역 자막 또는 원문 전사만 중에서 선택합니다."
    )
    static let realtimeTranslationOutputOnly = AppText.localized(
        english: "API live translation modes produce translated captions. For source-only captions, choose Apple transcription, GPT Transcription, or Gemini Transcribe.",
        korean: "API 실시간 번역 모드는 번역 자막을 만듭니다. 원문 자막만 필요하면 Apple 전사, GPT 전사 또는 Gemini 전사를 선택하세요.",
        japanese: "APIライブ翻訳モードは翻訳字幕を生成します。原文字幕のみの場合はApple文字起こし、GPT文字起こし、またはGemini文字起こしを選択してください。",
        chineseSimplified: "API 实时翻译模式会生成翻译字幕。若只需原文字幕，请选择 Apple 转写、GPT 转写或 Gemini 转写。"
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
    static let liveTranslationVolume = AppText.localized(
        english: "Volume",
        korean: "음량"
    )
    static let liveTranslationVolumeDetail = AppText.localized(
        english: "Controls the translated speech AirTranslate plays in live translation modes.",
        korean: "실시간 번역 모드에서 AirTranslate가 재생하는 번역 음성 크기를 조절합니다."
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
    static let floatingLineCountDetail = AppText.localized(
        english: "Limits how many wrapped lines stay visible at once.",
        korean: "한 번에 표시되는 줄 수를 제한합니다."
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
        english: "Screen Recording",
        korean: "화면 기록",
        japanese: "画面収録",
        chineseSimplified: "屏幕录制"
    )
    static let systemAudioRecording = AppText.localized(
        english: "System Audio Recording",
        korean: "시스템 오디오 녹음",
        japanese: "システムオーディオ録音",
        chineseSimplified: "系统音频录制"
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
        english: "Required to capture Mac audio. This check never requests permission.",
        korean: "PC 소리를 캡처하는 데 필요합니다. 이 확인 과정에서는 권한을 요청하지 않습니다.",
        japanese: "Mac音声のキャプチャに必要です。この確認では権限を要求しません。",
        chineseSimplified: "捕获 Mac 音频时需要。此检查不会请求权限。"
    )
    static let systemAudioPermissionDetail = AppText.localized(
        english: "macOS can allow screen and audio together or audio only. Confirm the exact choice in System Settings.",
        korean: "macOS에서는 화면과 오디오를 함께 또는 오디오만 허용할 수 있습니다. 정확한 상태는 시스템 설정에서 확인하세요.",
        japanese: "macOSでは画面と音声の両方、または音声のみを許可できます。正確な状態はシステム設定で確認してください。",
        chineseSimplified: "macOS 可允许屏幕和音频，或仅允许音频。请在系统设置中确认确切状态。"
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
    static let permissionReadOnlyNotice = AppText.localized(
        english: "Statuses are read-only. Permission prompts are never shown from this page.",
        korean: "상태만 확인하며 이 화면에서 권한 요청 창을 띄우지 않습니다.",
        japanese: "状態の確認のみ行い、この画面から権限要求は表示しません。",
        chineseSimplified: "这里只读取状态，不会从此页面弹出权限请求。"
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
        english: "Apple mode runs locally. OpenAI and Gemini Live are used only after you provide a matching API key and select that mode.",
        korean: "Apple 모드는 로컬에서 실행됩니다. OpenAI와 Gemini Live는 해당 API 키를 저장하고 해당 모드를 선택했을 때만 사용됩니다."
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

    var body: some View {
        List {
            ForEach(SettingsCategory.allCases) { category in
                SettingsSidebarRow(
                    category: category,
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

private struct FloatingCaptionPreview: View {
    let displayMode: FloatingCaptionDisplayMode
    let textSize: FloatingCaptionTextSize
    let lineCount: FloatingCaptionLineCount
    var alignment: FloatingCaptionTextAlignment = .center

    private let originalText = "We're going to focus on real-time translation."
    private let translationText = "우리는 실시간 번역에 집중할 것입니다."

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(AppText.localized(english: "Preview", korean: "미리보기"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                Text("\(displayMode.title) · \(textSize.title) · \(lineCount.title)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(
                        "\(AppText.floatingDisplay): \(displayMode.title), \(AppText.floatingTextSize): \(textSize.title), \(AppText.floatingLineCount): \(lineCount.title)"
                    )
            }

            ZStack {
                RoundedRectangle(cornerRadius: AirTranslateDesign.surfaceRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                AirTranslateDesign.Palette.floatingScrimTop,
                                AirTranslateDesign.Palette.floatingScrimBottom
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                VStack(alignment: alignment.horizontalAlignment, spacing: 8) {
                    if displayMode == .original || displayMode == .originalAndTranslation {
                        Text(originalText)
                            .font(displayMode == .original ? previewPrimaryFont : previewSecondaryFont)
                            .foregroundStyle(AirTranslateDesign.Palette.floatingTextPrimary)
                            .lineLimit(lineCount.rawValue)
                            .frame(maxWidth: .infinity, alignment: alignment.frameAlignment(vertical: .center))
                            .accessibilityLabel("\(AppText.original): \(originalText)")
                    }

                    if displayMode == .translation || displayMode == .originalAndTranslation {
                        Text(translationText)
                            .font(previewPrimaryFont)
                            .foregroundStyle(AirTranslateDesign.Palette.accentBright)
                            .lineLimit(lineCount.rawValue)
                            .frame(maxWidth: .infinity, alignment: alignment.frameAlignment(vertical: .center))
                            .accessibilityLabel("\(AppText.translation): \(translationText)")
                    }
                }
                .multilineTextAlignment(alignment.textAlignment)
                .padding(.horizontal, 22)
                .padding(.vertical, 16)
                .background(AirTranslateDesign.Palette.floatingScrimBottom, in: RoundedRectangle(cornerRadius: AirTranslateDesign.surfaceRadius, style: .continuous))
                .accessibilityElement(children: .contain)
            }
            .frame(minHeight: previewHeight)
            .clipShape(RoundedRectangle(cornerRadius: AirTranslateDesign.Radius.surface, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AirTranslateDesign.Radius.surface, style: .continuous)
                    .strokeBorder(AirTranslateDesign.Palette.floatingOutline)
            }
        }
    }

    private var previewPrimaryFont: Font {
        switch textSize {
        case .small:
            .system(size: 14, weight: .semibold)
        case .medium:
            .system(size: 17, weight: .semibold)
        case .large:
            .system(size: 20, weight: .semibold)
        case .extraLarge:
            .system(size: 23, weight: .semibold)
        }
    }

    private var previewSecondaryFont: Font {
        switch textSize {
        case .small:
            .system(size: 11, weight: .medium)
        case .medium:
            .system(size: 13, weight: .medium)
        case .large:
            .system(size: 15, weight: .medium)
        case .extraLarge:
            .system(size: 17, weight: .medium)
        }
    }

    private var previewHeight: CGFloat {
        let lineContribution = CGFloat(max(0, lineCount.rawValue - 2)) * 5
        let sizeContribution: CGFloat
        switch textSize {
        case .small:
            sizeContribution = 0
        case .medium:
            sizeContribution = 4
        case .large:
            sizeContribution = 10
        case .extraLarge:
            sizeContribution = 18
        }

        return 112 + lineContribution + sizeContribution
    }
}

private enum SettingsPermissionState: Equatable {
    case allowed
    case notGranted
    case denied
    case restricted
    case notDetermined
    case unknown

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
    let status: SettingsPermissionState
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

private struct SettingsNoticeRow: View {
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

private struct SettingsGroup<Content: View>: View {
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

private struct SettingsControlRow<Trailing: View>: View {
    let title: String
    let detail: String
    let systemImage: String
    @ViewBuilder let trailing: Trailing

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 10) {
                SettingsRowLabel(title: title, detail: detail, systemImage: systemImage)

                Spacer(minLength: 16)

                trailing
                    .controlSize(.regular)
                    .frame(maxWidth: 360, alignment: .trailing)
            }
            .frame(minWidth: AirTranslateDesign.settingsRowBreakpoint)

            VStack(alignment: .leading, spacing: 10) {
                SettingsRowLabel(title: title, detail: detail, systemImage: systemImage)
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
    @Binding var isOn: Bool

    var body: some View {
        SettingsControlRow(title: title, detail: detail, systemImage: systemImage) {
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
                    .lineLimit(3)
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
