import SwiftUI

struct SettingsView: View {
    @Bindable var session: TranslationSessionStore
    @State private var openAIAPIKey = ""
    @State private var azureEndpoint = ""
    @State private var azureAPIKey = ""
    @State private var configurationNotice: String?
    @State private var shouldFocusAPIKey = false
    @State private var saveAlert: SaveAlert?

    private struct SaveAlert: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                openAIRealtimeSection
                transcriptSection
                floatingCaptionsSection
                requiredAssetsSection
                permissionsSection
            }
            .padding(16)
        }
        .frame(minWidth: 460, idealWidth: 520, maxWidth: .infinity)
        .frame(minHeight: 560)
        .background(.regularMaterial)
        .onAppear {
            azureEndpoint = session.azureOpenAIEndpoint
            session.refreshModelAvailability()
        }
        .onChange(of: session.openAIProvider) { _, _ in
            configurationNotice = nil
            shouldFocusAPIKey = false
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

    private var openAIRealtimeSection: some View {
        SettingsInlineGroup(
            systemImage: "bolt.horizontal.circle.fill",
            title: AppText.gptModels
        ) {
            VStack(spacing: 6) {
                OpenAIRealtimeModelPickers(session: session) { _ in
                    configurationNotice = nil
                    shouldFocusAPIKey = false
                }

                switch session.openAIProvider {
                case .openAI:
                    SettingsAPIKeyRow(
                        apiKey: $openAIAPIKey,
                        shouldFocusAPIKey: $shouldFocusAPIKey,
                        hasAPIKey: session.hasOpenAIAPIKey,
                        notice: configurationNotice,
                        save: saveOpenAIAPIKey,
                        remove: removeOpenAIAPIKey
                    )
                case .azure:
                    SettingsAzureConfigRow(
                        endpoint: $azureEndpoint,
                        apiKey: $azureAPIKey,
                        shouldFocusAPIKey: $shouldFocusAPIKey,
                        hasConfig: session.hasAzureOpenAIConfig,
                        notice: configurationNotice,
                        save: saveAzureOpenAIConfig,
                        remove: removeAzureOpenAIConfig
                    )
                }

                advancedModelOverridesGroup

                Text(AppText.gptModelsDescription)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 8)

                providerAccessLink
            }
        }
    }

    @ViewBuilder
    private var advancedModelOverridesGroup: some View {
        OpenAIAdvancedOverridesView(session: session)
    }

    private var transcriptSection: some View {
        SettingsInlineGroup(systemImage: "text.alignleft", title: AppText.transcript) {
            VStack(spacing: 6) {
                SettingsSessionDurationRadioGroup(
                    selection: $session.sessionDurationMode,
                    isDisabled: session.isRunning
                )

                SettingsStepperRow(
                    title: AppText.paragraphBreakSilenceInterval,
                    systemImage: "timer",
                    valueText: AppText.seconds(session.paragraphBreakSilenceInterval),
                    value: $session.paragraphBreakSilenceInterval
                )

                Text(AppText.paragraphBreakSilenceDescription)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 8)
            }
        }
    }

    private var floatingCaptionsSection: some View {
        SettingsInlineGroup(systemImage: "captions.bubble.fill", title: AppText.floatingCaptions) {
            VStack(spacing: 6) {
                SettingsSegmentedPickerRow(
                    title: AppText.floatingDisplay,
                    systemImage: "rectangle.split.2x1",
                    selection: $session.floatingCaptionDisplayMode
                ) {
                    ForEach(FloatingCaptionDisplayMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }

                SettingsSegmentedPickerRow(
                    title: AppText.floatingTextAlignment,
                    systemImage: "text.alignleft",
                    selection: $session.floatingCaptionTextAlignment
                ) {
                    ForEach(FloatingCaptionTextAlignment.allCases) { alignment in
                        Text(alignment.title).tag(alignment)
                    }
                }

                SettingsCompactMenuRow(
                    title: AppText.floatingTextSize,
                    systemImage: "textformat.size",
                    value: session.floatingCaptionTextSize.title
                ) {
                    ForEach(FloatingCaptionTextSize.allCases) { size in
                        Button(size.title) {
                            session.floatingCaptionTextSize = size
                        }
                    }
                }

                SettingsCompactMenuRow(
                    title: AppText.floatingLineCount,
                    systemImage: "line.3.horizontal",
                    value: session.floatingCaptionLineCount.title
                ) {
                    ForEach(FloatingCaptionLineCount.allCases) { lineCount in
                        Button(lineCount.title) {
                            session.floatingCaptionLineCount = lineCount
                        }
                    }
                }

                SettingsCompactToggleRow(
                    title: AppText.floatingImmediateDisplay,
                    systemImage: "bolt.fill",
                    isOn: $session.isFloatingCaptionImmediateDisplayEnabled
                )

                Text(AppText.floatingImmediateDisplayDescription)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 8)
            }
        }
    }

    private var requiredAssetsSection: some View {
        SettingsInlineGroup(systemImage: "arrow.down.circle.fill", title: AppText.requiredAssets) {
            VStack(spacing: 6) {
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
        }
    }

    private var permissionsSection: some View {
        SettingsInlineGroup(systemImage: "lock.shield.fill", title: AppText.permissions) {
            SettingsCompactInfoRow(
                title: AppText.permissions,
                detail: AppText.permissionsHelp,
                systemImage: "hand.raised.fill"
            )
        }
    }

    private var providerAccessLink: some View {
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

    private func saveOpenAIAPIKey() {
        if session.saveOpenAIAPIKey(openAIAPIKey) {
            openAIAPIKey = ""
            configurationNotice = nil
            shouldFocusAPIKey = false
        } else {
            configurationNotice = session.statusMessage
            shouldFocusAPIKey = true
        }
    }

    private func removeOpenAIAPIKey() {
        session.removeOpenAIAPIKey()
        openAIAPIKey = ""
        configurationNotice = nil
    }

    private func saveAzureOpenAIConfig() {
        if session.saveAzureOpenAIConfig(endpoint: azureEndpoint, apiKey: azureAPIKey) {
            azureAPIKey = ""
            azureEndpoint = session.azureOpenAIEndpoint
            configurationNotice = nil
            shouldFocusAPIKey = false
            saveAlert = SaveAlert(
                title: AppText.azureOpenAIConfigSavedTitle,
                message: session.statusMessage
            )
        } else {
            configurationNotice = session.statusMessage
            shouldFocusAPIKey = true
            saveAlert = SaveAlert(
                title: AppText.azureOpenAIConfigSaveFailedTitle,
                message: session.statusMessage
            )
        }
    }

    private func removeAzureOpenAIConfig() {
        session.removeAzureOpenAIConfig()
        azureAPIKey = ""
        azureEndpoint = ""
        configurationNotice = nil
    }
}

private struct SettingsSessionDurationRadioGroup: View {
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
