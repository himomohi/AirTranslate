import AppKit
import SwiftUI

struct SidebarView: View {
    @Bindable var session: TranslationSessionStore
    @State private var isLibraryPresented = false
    @State private var isConfigurationPresented = false
    @State private var openAIAPIKey = ""
    @State private var configurationNotice: String?
    @State private var shouldFocusOpenAIAPIKey = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                brandHeader
                sessionCard
                libraryCard
            }
            .padding(12)
        }
        .background(.bar)
        .navigationTitle("AirTranslate")
        .sheet(isPresented: $isLibraryPresented) {
            TranscriptLibraryView(session: session)
        }
        .sheet(isPresented: $isConfigurationPresented) {
            ConfigurationSheetView(
                session: session,
                openAIAPIKey: $openAIAPIKey,
                configurationNotice: $configurationNotice,
                shouldFocusOpenAIAPIKey: $shouldFocusOpenAIAPIKey,
                dismiss: { isConfigurationPresented = false }
            )
        }
    }

    private var brandHeader: some View {
        HStack(spacing: 12) {
            AppIconMark()

            VStack(alignment: .leading, spacing: 3) {
                Text(AppText.appName)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(AppText.appTagline)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                CaptureStatusIndicator(
                    symbolName: statusSymbolName,
                    color: statusColor,
                    statusMessage: session.statusMessage
                )

                Button {
                    session.openPrivacySettings()
                } label: {
                    Image(systemName: "gear")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .help(AppText.openPrivacySettings)
                .accessibilityLabel(AppText.openPrivacySettings)
                .opacity(needsPermissionAction ? 1 : 0)
                .disabled(!needsPermissionAction)
                .accessibilityHidden(!needsPermissionAction)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06))
        }
    }

    private var sessionCard: some View {
        SidebarCard(
            title: AppText.translationSettings,
            headerAccessory: {
                openConfigurationButton
            }
        ) {
            VStack(spacing: 10) {
                languageControls

                ProcessingEnginePicker(
                    selection: processingEngineBinding,
                    isDisabled: session.isRunning
                )

                AudioInputSourcePicker(
                    selection: $session.audioInputSource,
                    isDisabled: session.isRunning
                )

                if session.audioInputSource == .microphone {
                    MicrophoneInputDevicePicker(
                        selection: $session.selectedMicrophoneInputDeviceID,
                        devices: session.microphoneInputDevices,
                        isDisabled: session.isRunning
                    )
                }

                SessionDurationRadioGroup(
                    selection: $session.sessionDurationMode,
                    isDisabled: session.isRunning
                )
            }
        }
        .onAppear {
            session.refreshModelAvailability()
            session.refreshMicrophoneInputDevices()
            if usesOpenAIAutoLanguageFlow {
                session.usePreferredLanguageForOpenAIOutput()
            }
        }
    }

    @ViewBuilder
    private var languageControls: some View {
        if usesOpenAIAutoLanguageFlow {
            VStack(alignment: .leading, spacing: 6) {
                AutoLanguageRow(helpText: AppText.openAILanguageModeDescription)
                PreferredLanguageRow(
                    selection: $session.targetLanguage,
                    isDisabled: session.isRunning
                )
                OpenAIVoiceOutputRow(isOn: $session.isDubbingEnabled)

                Text(AppText.openAILanguageModeDescription)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    if session.isAppleSourceAutoDetectionEnabled {
                        CompactAutoLanguagePicker(title: AppText.from)
                    } else {
                        CompactLanguagePicker(title: AppText.from, selection: $session.sourceLanguage)
                    }

                    Button {
                        swapLanguages()
                    } label: {
                        Image(systemName: "arrow.left.arrow.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 24, height: 24)
                            .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(session.isRunning || session.isAppleSourceAutoDetectionEnabled)
                    .help(AppText.swapLanguages)
                    .accessibilityLabel(AppText.swapLanguages)

                    CompactLanguagePicker(title: AppText.to, selection: $session.targetLanguage)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                CompactToggleRow(
                    title: AppText.autoDetectInput,
                    systemImage: "sparkles",
                    isOn: appleSourceAutoDetectionBinding
                )
                .disabled(session.isRunning)
                .help(
                    session.isAppleSourceAutoDetectionAvailable
                        ? AppText.appleAutoLanguageModeDescription
                        : AppText.appleAutoLanguageModeUnavailableDescription
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var appleSourceAutoDetectionBinding: Binding<Bool> {
        Binding(
            get: {
                session.isAppleSourceAutoDetectionAvailable
                    && session.isAppleSourceAutoDetectionEnabled
            },
            set: { isEnabled in
                guard session.isAppleSourceAutoDetectionAvailable else {
                    session.showAppleSourceAutoDetectionUnavailableNotice()
                    return
                }

                session.isAppleSourceAutoDetectionEnabled = isEnabled
            }
        )
    }

    private var gptCredentialsRequiredNotice: String {
        session.openAIProvider == .azure
            ? AppText.azureOpenAIConfigRequiredForGPTMode
            : AppText.openAIAPIKeyRequiredForGPTMode
    }

    private var openConfigurationButton: some View {
        Button {
            if ProcessingEngine.current(for: session) == .gpt && !session.hasOpenAIRealtimeCredentials {
                configurationNotice = gptCredentialsRequiredNotice
                shouldFocusOpenAIAPIKey = true
            }
            isConfigurationPresented = true
        } label: {
            Image(systemName: "gearshape.fill")
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 26, height: 26)
                .background(Color.accentColor.opacity(0.13), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(Color.accentColor.opacity(0.22), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .help(AppText.configureTranslationSettings)
        .accessibilityLabel(AppText.configureTranslationSettings)
    }

    private var processingEngineBinding: Binding<ProcessingEngine> {
        Binding(
            get: {
                ProcessingEngine.current(for: session)
            },
            set: { engine in
                switch engine {
                case .apple:
                    session.useAppleDefaultMode()
                case .gpt:
                    session.useGPTRealtimeMode()
                    if !session.hasOpenAIRealtimeCredentials {
                        configurationNotice = gptCredentialsRequiredNotice
                        shouldFocusOpenAIAPIKey = true
                        isConfigurationPresented = true
                    }
                }
            }
        )
    }

    private func swapLanguages() {
        let sourceLanguage = session.sourceLanguage
        session.sourceLanguage = session.targetLanguage
        session.targetLanguage = sourceLanguage
    }

    private var usesOpenAIAutoLanguageFlow: Bool {
        ProcessingEngine.current(for: session) == .gpt && session.isUsingOpenAIRealtimeTranslation
    }

    private var libraryCard: some View {
        SidebarCard(title: AppText.library) {
            VStack(alignment: .leading, spacing: 10) {
                Text(AppText.librarySummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button {
                    isLibraryPresented = true
                } label: {
                    Label(AppText.manageSavedTranscripts, systemImage: "tray.full")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .controlSize(.small)
            }
        }
    }

    private var needsPermissionAction: Bool {
        session.statusMessage.localizedCaseInsensitiveContains("permission")
            || session.statusMessage.localizedCaseInsensitiveContains("권한")
    }

    private var statusSymbolName: String {
        if session.isPaused {
            return "pause.circle.fill"
        }
        if session.isRunning {
            return "waveform.circle.fill"
        }
        return "circle.dotted"
    }

    private var statusColor: Color {
        if session.isPaused {
            return .orange
        }
        if session.isRunning {
            return .green
        }
        return .secondary
    }
}

private enum ProcessingEngine: String, CaseIterable, Identifiable {
    case apple
    case gpt

    var id: String { rawValue }

    var title: String {
        switch self {
        case .apple:
            AppText.localized(
                english: "Apple Mode",
                korean: "Apple 기본 모드",
                japanese: "Apple標準モード",
                chineseSimplified: "Apple 默认模式"
            )
        case .gpt:
            AppText.localized(
                english: "GPT Mode",
                korean: "GPT 모드",
                japanese: "GPTモード",
                chineseSimplified: "GPT 模式"
            )
        }
    }

    @MainActor
    static func current(for session: TranslationSessionStore) -> ProcessingEngine {
        session.openAITranscriptionModel.isEnabled || session.openAITranslationModel.isEnabled ? .gpt : .apple
    }
}

private struct ConfigurationSheetView: View {
    @Bindable var session: TranslationSessionStore
    @Binding var openAIAPIKey: String
    @Binding var configurationNotice: String?
    @Binding var shouldFocusOpenAIAPIKey: Bool
    let dismiss: () -> Void

    @State private var azureEndpoint: String = ""
    @State private var azureAPIKey: String = ""
    @State private var saveAlert: SaveAlert?

    private struct SaveAlert: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "gearshape.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 34, height: 34)
                    .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(AppText.localized(
                        english: "Session Options",
                        korean: "세부 설정",
                        japanese: "詳細設定",
                        chineseSimplified: "详细设置"
                    ))
                        .font(.headline.weight(.semibold))

                    Text("\(ProcessingEngine.current(for: session).title) · \(session.sessionDurationMode.title)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(AppText.close)
                .accessibilityLabel(AppText.close)
            }
            .padding(16)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    appleProcessingSection
                    openAIModelsSection
                    liveOutputSection
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 28)
            }

            Divider()

            HStack {
                Spacer()

                Button(AppText.close) {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 460)
        .frame(minHeight: 560)
        .onAppear {
            session.refreshModelAvailability()
            azureEndpoint = session.azureOpenAIEndpoint
        }
        .alert(item: $saveAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private var appleProcessingSection: some View {
        InlineSettingsGroup(
            systemImage: "apple.logo",
            title: AppText.appleProcessingMode
        ) {
            VStack(spacing: 6) {
                ForEach(IntelligenceModel.allCases) { model in
                    Button {
                        session.selectedModel = model
                    } label: {
                        ModelModeRow(
                            model: model,
                            isSelected: session.selectedModel == model
                        )
                    }
                    .buttonStyle(.plain)
                    .help(model.detail)
                }

                Text(AppText.appleProcessingModeDescription)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 8)
            }
        }
    }

    private var openAIModelsSection: some View {
        InlineSettingsGroup(
            systemImage: "bolt.horizontal.circle.fill",
            title: AppText.gptModels
        ) {
            VStack(spacing: 6) {
                OpenAIRealtimeModelPickers(session: session) { _ in
                    configurationNotice = nil
                    shouldFocusOpenAIAPIKey = false
                }

                switch session.openAIProvider {
                case .openAI:
                    GPTAPIKeyRow(
                        apiKey: $openAIAPIKey,
                        shouldFocusAPIKey: $shouldFocusOpenAIAPIKey,
                        hasAPIKey: session.hasOpenAIAPIKey,
                        notice: configurationNotice,
                        save: {
                            session.saveOpenAIAPIKey(openAIAPIKey)
                            openAIAPIKey = ""
                            configurationNotice = nil
                            shouldFocusOpenAIAPIKey = false
                        },
                        remove: {
                            session.removeOpenAIAPIKey()
                            openAIAPIKey = ""
                            if ProcessingEngine.current(for: session) == .gpt {
                                configurationNotice = AppText.openAIAPIKeyRequiredForGPTMode
                                shouldFocusOpenAIAPIKey = true
                            }
                        }
                    )
                case .azure:
                    GPTAzureConfigRow(
                        endpoint: $azureEndpoint,
                        apiKey: $azureAPIKey,
                        shouldFocusAPIKey: $shouldFocusOpenAIAPIKey,
                        hasConfig: session.hasAzureOpenAIConfig,
                        notice: configurationNotice,
                        save: {
                            let ok = session.saveAzureOpenAIConfig(endpoint: azureEndpoint, apiKey: azureAPIKey)
                            azureAPIKey = ""
                            if ok {
                                azureEndpoint = session.azureOpenAIEndpoint
                                configurationNotice = nil
                                shouldFocusOpenAIAPIKey = false
                                saveAlert = SaveAlert(
                                    title: AppText.azureOpenAIConfigSavedTitle,
                                    message: session.statusMessage
                                )
                            } else {
                                configurationNotice = session.statusMessage
                                shouldFocusOpenAIAPIKey = true
                                saveAlert = SaveAlert(
                                    title: AppText.azureOpenAIConfigSaveFailedTitle,
                                    message: session.statusMessage
                                )
                            }
                        },
                        remove: {
                            session.removeAzureOpenAIConfig()
                            azureAPIKey = ""
                            azureEndpoint = ""
                            if ProcessingEngine.current(for: session) == .gpt {
                                configurationNotice = AppText.azureOpenAIConfigRequiredForGPTMode
                                shouldFocusOpenAIAPIKey = true
                            }
                        }
                    )
                }

                OpenAIAdvancedOverridesView(session: session)

                Text(AppText.gptModelsDescription)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 8)

                HStack(spacing: 5) {
                    switch session.openAIProvider {
                    case .openAI:
                        Text(AppText.openAIAPIKeyPlatformPrompt)
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        Link(
                            AppText.openAIAPIKeyPlatformLink,
                            destination: URL(string: "https://platform.openai.com/api-keys")!
                        )
                        .font(.caption2.weight(.semibold))
                    case .azure:
                        Text(AppText.azureOpenAIPlatformPrompt)
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        Link(
                            AppText.azureOpenAIPlatformLink,
                            destination: URL(string: "https://ai.azure.com/")!
                        )
                        .font(.caption2.weight(.semibold))
                    }
                }
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var liveOutputSection: some View {
        InlineSettingsGroup(
            systemImage: "waveform.and.person.filled",
            title: AppText.liveOutput
        ) {
            VStack(spacing: 6) {
                if ProcessingEngine.current(for: session) == .gpt {
                    CompactInfoRow(
                        title: AppText.openAINativeOutput,
                        detail: AppText.openAINativeOutputDescription,
                        systemImage: "sparkles"
                    )
                } else {
                    CompactToggleRow(
                        title: AppText.transcriptPolish,
                        systemImage: "text.badge.checkmark",
                        isOn: $session.isTranscriptLintEnabled
                    )
                    .help(AppText.transcriptLintDescription)
                }

                CompactToggleRow(
                    title: session.isUsingOpenAIRealtimeTranslation
                        ? AppText.translatedVoiceOutput
                        : AppText.voiceOutput,
                    systemImage: "speaker.wave.2.fill",
                    isOn: $session.isDubbingEnabled
                )
            }
        }
    }
}

private struct AutoLanguageRow: View {
    let helpText: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 16)

            Text(AppText.autoDetectInput)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.82)

            Spacer(minLength: 6)

            Text(AppText.autoDetectShort)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.accentColor.opacity(0.12), in: Capsule())
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .help(helpText)
        .accessibilityLabel(AppText.autoDetectInput)
    }
}

private struct PreferredLanguageRow: View {
    @Binding var selection: LanguageOption
    let isDisabled: Bool

    var body: some View {
        Menu {
            ForEach(LanguageOption.supported) { language in
                Button(language.localizedTitle) {
                    selection = language
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "globe")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 16)

                Text(AppText.preferredLanguage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                Spacer(minLength: 6)

                Text(selection.localizedTitle)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)

                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .help(AppText.preferredLanguage)
        .accessibilityLabel(AppText.preferredLanguage)
        .accessibilityValue(selection.localizedTitle)
    }
}

private struct OpenAIVoiceOutputRow: View {
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: isOn ? "speaker.wave.2.fill" : "speaker")
                .font(.caption.weight(.bold))
                .foregroundStyle(isOn ? Color.accentColor : Color.secondary)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(AppText.translatedVoiceOutput)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(AppText.translatedVoiceOutputDescription)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Toggle(AppText.translatedVoiceOutput, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .help(AppText.translatedVoiceOutputDescription)
        .accessibilityLabel(AppText.translatedVoiceOutput)
        .accessibilityValue(isOn ? AppText.floatingCaptionPowerOn : AppText.floatingCaptionPowerOff)
    }
}

private struct ProcessingEnginePicker: View {
    @Binding var selection: ProcessingEngine
    let isDisabled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                Image(systemName: "switch.2")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 14)

                Text(AppText.model)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)
            }

            Picker(AppText.model, selection: $selection) {
                ForEach(ProcessingEngine.allCases) { engine in
                    Text(engine.title).tag(engine)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: .infinity)
            .disabled(isDisabled)
            .accessibilityLabel(AppText.model)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }
}

private struct AudioInputSourcePicker: View {
    @Binding var selection: AudioInputSource
    let isDisabled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                Image(systemName: "waveform.badge.magnifyingglass")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 14)

                Text(AppText.audioInputSource)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)
            }

            Picker(AppText.audioInputSource, selection: $selection) {
                ForEach(AudioInputSource.allCases) { source in
                    Text(source.title).tag(source)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: .infinity)
            .disabled(isDisabled)
            .accessibilityLabel(AppText.audioInputSource)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }
}

private struct MicrophoneInputDevicePicker: View {
    @Binding var selection: String
    let devices: [MicrophoneInputDevice]
    let isDisabled: Bool

    var body: some View {
        Menu {
            ForEach(devices) { device in
                Button(device.name) {
                    selection = device.id
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "mic.circle.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 16)

                Text(AppText.microphoneInputDevice)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                Spacer(minLength: 6)

                Text(selectedDeviceName)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)

                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .help(AppText.microphoneInputDevice)
        .accessibilityLabel(AppText.microphoneInputDevice)
        .accessibilityValue(selectedDeviceName)
    }

    private var selectedDeviceName: String {
        devices.first { $0.id == selection }?.name ?? MicrophoneInputDevice.systemDefault.name
    }
}

private struct InlineSettingsGroup<Content: View>: View {
    let systemImage: String
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 9) {
                Image(systemName: systemImage)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 16, height: 16)

                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)
            }

            content
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.055), lineWidth: 1)
        }
    }
}

private struct CompactToggleRow: View {
    let title: String
    let systemImage: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.caption.weight(.bold))
                .foregroundStyle(isOn ? Color.accentColor : Color.secondary)
                .frame(width: 18, height: 18)

            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Spacer(minLength: 12)

            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
        .accessibilityLabel(title)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct CompactInfoRow: View {
    let title: String
    let detail: String
    let systemImage: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 18, height: 18)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
        .background(Color.accentColor.opacity(0.07), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct GPTModelMenuRow<MenuContent: View>: View {
    let title: String
    let systemImage: String
    let value: String
    @ViewBuilder let menuContent: MenuContent

    var body: some View {
        Menu {
            menuContent
        } label: {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 16)

                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)

                Spacer(minLength: 6)

                Text(value)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)

                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(title)
    }
}

private struct GPTAPIKeyRow: View {
    @Binding var apiKey: String
    @Binding var shouldFocusAPIKey: Bool
    @FocusState private var isAPIKeyFocused: Bool
    let hasAPIKey: Bool
    let notice: String?
    let save: () -> Void
    let remove: () -> Void

    private var trimmedAPIKey: String {
        apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Image(systemName: "key.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(hasAPIKey ? Color.green : Color.secondary)
                    .frame(width: 16)

                SecureField(AppText.openAIAPIKeyPlaceholder, text: $apiKey)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                    .focused($isAPIKeyFocused)

                Button {
                    save()
                } label: {
                    Image(systemName: "checkmark.circle.fill")
                }
                .buttonStyle(.borderless)
                .disabled(trimmedAPIKey.isEmpty)
                .help(AppText.saveOpenAIAPIKey)
                .accessibilityLabel(AppText.saveOpenAIAPIKey)

                Button {
                    remove()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .disabled(!hasAPIKey)
                .help(AppText.removeOpenAIAPIKey)
                .accessibilityLabel(AppText.removeOpenAIAPIKey)
            }

            if let notice, !hasAPIKey {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Color.orange)

                    Text(notice)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.leading, 24)
            }

            Text(hasAPIKey ? AppText.openAIAPIKeyConfigured : AppText.openAIAPIKeyNotConfigured)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(hasAPIKey ? Color.green : Color.secondary)
                .padding(.leading, 24)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onAppear {
            focusAPIKeyIfNeeded()
        }
        .onChange(of: shouldFocusAPIKey) { _, _ in
            focusAPIKeyIfNeeded()
        }
    }

    private func focusAPIKeyIfNeeded() {
        guard shouldFocusAPIKey else { return }
        Task { @MainActor in
            isAPIKeyFocused = true
            shouldFocusAPIKey = false
        }
    }
}

private struct GPTAzureConfigRow: View {
    @Binding var endpoint: String
    @Binding var apiKey: String
    @Binding var shouldFocusAPIKey: Bool
    @FocusState private var isAPIKeyFocused: Bool
    let hasConfig: Bool
    let notice: String?
    let save: () -> Void
    let remove: () -> Void

    private var trimmedEndpoint: String {
        endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedAPIKey: String {
        apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Image(systemName: "link")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(hasConfig ? Color.green : Color.secondary)
                    .frame(width: 16)

                TextField(AppText.azureOpenAIEndpointPlaceholder, text: $endpoint)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                    .textContentType(.URL)
                    .autocorrectionDisabled(true)
            }

            Text(AppText.azureOpenAIEndpointFormatHint)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 24)

            HStack(spacing: 8) {
                Image(systemName: "key.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(hasConfig ? Color.green : Color.secondary)
                    .frame(width: 16)

                SecureField(AppText.azureOpenAIAPIKeyPlaceholder, text: $apiKey)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                    .focused($isAPIKeyFocused)

                Button {
                    save()
                } label: {
                    Image(systemName: "checkmark.circle.fill")
                }
                .buttonStyle(.borderless)
                .disabled(trimmedAPIKey.isEmpty || trimmedEndpoint.isEmpty)
                .help(AppText.saveAzureOpenAIConfig)
                .accessibilityLabel(AppText.saveAzureOpenAIConfig)

                Button {
                    remove()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .disabled(!hasConfig)
                .help(AppText.removeAzureOpenAIConfig)
                .accessibilityLabel(AppText.removeAzureOpenAIConfig)
            }

            if let notice, !hasConfig {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Color.orange)

                    Text(notice)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.leading, 24)
            }

            Text(hasConfig ? AppText.azureOpenAIConfigConfigured : AppText.azureOpenAIConfigNotConfigured)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(hasConfig ? Color.green : Color.secondary)
                .padding(.leading, 24)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onAppear {
            focusAPIKeyIfNeeded()
        }
        .onChange(of: shouldFocusAPIKey) { _, _ in
            focusAPIKeyIfNeeded()
        }
    }

    private func focusAPIKeyIfNeeded() {
        guard shouldFocusAPIKey else { return }
        Task { @MainActor in
            isAPIKeyFocused = true
            shouldFocusAPIKey = false
        }
    }
}

private struct SessionDurationRadioGroup: View {
    @Binding var selection: SessionDurationMode
    let isDisabled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                Image(systemName: "timer")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 14)

                Text(AppText.sessionLength)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)
            }

            Picker(AppText.sessionLength, selection: $selection) {
                ForEach(SessionDurationMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()
            .disabled(isDisabled)
            .accessibilityLabel(AppText.sessionLength)

            Text(selection.detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }
}

private struct CompactLanguagePicker: View {
    let title: String
    @Binding var selection: LanguageOption

    var body: some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 24, alignment: .trailing)
                .lineLimit(1)

            Menu {
                ForEach(LanguageOption.supported) { language in
                    Button(language.localizedTitle) {
                        selection = language
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(selection.localizedTitle)
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 7)
                .frame(width: 72)
                .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .help(title)
            .accessibilityLabel(title)
            .accessibilityValue(selection.localizedTitle)
        }
        .frame(width: 100)
    }
}

private struct CompactAutoLanguagePicker: View {
    let title: String

    var body: some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 24, alignment: .trailing)
                .lineLimit(1)

            HStack(spacing: 4) {
                Text(AppText.autoDetectShort)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)

                Image(systemName: "sparkles")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.accentColor)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .frame(width: 72)
            .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .frame(width: 100)
        .help(AppText.appleAutoLanguageModeUnavailableDescription)
        .accessibilityLabel(AppText.autoDetectInput)
    }
}

private struct AppIconMark: View {
    private var appIcon: NSImage {
        NSImage(named: "AppIcon") ?? NSApp.applicationIconImage
    }

    var body: some View {
        Image(nsImage: appIcon)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 46, height: 46)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .shadow(color: Color.black.opacity(0.16), radius: 5, x: 0, y: 2)
            .accessibilityHidden(true)
    }
}

private struct CaptureStatusIndicator: View {
    let symbolName: String
    let color: Color
    let statusMessage: String

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.14))

            Circle()
                .strokeBorder(color.opacity(0.36), lineWidth: 1)

            Image(systemName: symbolName)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(color)
        }
        .frame(width: 30, height: 30)
        .help(statusMessage)
        .accessibilityLabel(AppText.capture)
        .accessibilityValue(statusMessage)
    }
}

private struct ModelModeRow: View {
    let model: IntelligenceModel
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: modelSymbolName)
                .font(.callout.weight(.semibold))
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                .frame(width: 18, height: 18)

            Text(model.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Spacer(minLength: 0)

            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.callout.weight(.semibold))
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary.opacity(0.55))
                .frame(width: 18, height: 18)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background((isSelected ? Color.accentColor : Color.primary).opacity(isSelected ? 0.11 : 0.045), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder((isSelected ? Color.accentColor : Color.primary).opacity(isSelected ? 0.24 : 0.06), lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
    }

    private var modelSymbolName: String {
        switch model {
        case .appleSystem:
            "captions.bubble.fill"
        case .appleOnDevice:
            "arrow.down.circle.fill"
        case .appleSpeechOnly:
            "waveform"
        }
    }
}

private struct AssetAvailabilityRow: View {
    let title: String
    let availability: ModelAvailability
    let helpText: String
    let download: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: assetSymbolName)
                .font(.callout.weight(.semibold))
                .foregroundStyle(availabilityColor)
                .frame(width: 28, height: 28)
                .background(availabilityColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(availability.detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 4)

            trailingStatus
        }
        .padding(10)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        }
        .help(helpText)
    }

    @ViewBuilder
    private var trailingStatus: some View {
        if availability.state == .downloading || availability.state == .checking {
            ProgressView()
                .controlSize(.small)
                .help(availability.state.title)
        } else if availability.state.canDownload {
            Button {
                download()
            } label: {
                Label(AppText.download, systemImage: "arrow.down.circle")
                    .labelStyle(.iconOnly)
                    .font(.title3)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(availabilityColor)
            .help(AppText.downloadModelAssets)
        } else {
            Text(availability.state.title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(availabilityColor)
                .lineLimit(1)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(availabilityColor.opacity(0.12), in: Capsule())
        }
    }

    private var assetSymbolName: String {
        switch availability.state {
        case .checking:
            "clock"
        case .installed:
            "checkmark.seal.fill"
        case .downloadRequired:
            "arrow.down.circle"
        case .downloading:
            "arrow.down.circle"
        case .unsupported, .unavailable, .failed:
            "exclamationmark.triangle.fill"
        }
    }

    private var availabilityColor: Color {
        switch availability.state {
        case .checking:
            .secondary
        case .installed:
            .green
        case .downloadRequired, .downloading:
            .orange
        case .unsupported, .unavailable, .failed:
            .red
        }
    }
}

private struct SidebarCard<Content: View, HeaderAccessory: View>: View {
    let title: String?
    @ViewBuilder let headerAccessory: HeaderAccessory
    @ViewBuilder let content: Content

    init(title: String? = nil, @ViewBuilder content: () -> Content) where HeaderAccessory == EmptyView {
        self.title = title
        self.headerAccessory = EmptyView()
        self.content = content()
    }

    init(
        title: String? = nil,
        @ViewBuilder headerAccessory: () -> HeaderAccessory,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.headerAccessory = headerAccessory()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)

                    Spacer(minLength: 0)

                    headerAccessory
                }
            }

            content
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06))
        }
    }
}
