import SwiftUI

struct APIKeySettingsView: View {
    @Bindable var session: TranslationSessionStore
    @State private var expandedProvider: CredentialProvider?
    @State private var showsStorageInfo = false

    private var isLocked: Bool { session.isRunning || session.isStarting }
    private var validAzureEndpoint: Bool {
        (try? AzureMAITranscriber.endpointURL(session.azureSpeechEndpoint)) != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(CredentialsCopy.providers)
                    .font(AirTranslateDesign.Typography.sectionLabel)
                Spacer()
                Text(CredentialsCopy.summary(saved: CredentialProvider.allCases.filter(hasKey).count, total: CredentialProvider.allCases.count))
                    .font(.caption.monospacedDigit())
            }
            .foregroundStyle(.secondary)

            if isLocked {
                Label(CredentialsCopy.locked, systemImage: "lock")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 0) {
                ForEach(CredentialProvider.allCases) { provider in
                    ProviderCredentialRow(
                        name: provider.title,
                        symbol: provider.symbol,
                        model: model(for: provider),
                        detail: detail(for: provider),
                        consoleURL: provider.consoleURL,
                        hasKey: hasKey(provider),
                        needsConfiguration: provider == .azure && !validAzureEndpoint,
                        isCurrent: activeProvider == provider,
                        isLocked: isLocked,
                        isExpanded: Binding(
                            get: { expandedProvider == provider },
                            set: { expandedProvider = $0 ? provider : nil }
                        ),
                        saveKey: { try save($0, for: provider) },
                        removeKey: { try remove(provider) }
                    ) {
                        if provider == .azure { azureConfiguration }
                    }
                    if provider != CredentialProvider.allCases.last {
                        Rectangle()
                            .fill(AirTranslateDesign.Palette.hairline)
                            .frame(height: 1)
                            .padding(.horizontal, 16)
                            .accessibilityHidden(true)
                    }
                }
            }
            .airTranslateSurface()

            HStack(spacing: 6) {
                Label(CredentialsCopy.keychain, systemImage: "lock.shield")
                    .font(.caption)
                Button { showsStorageInfo.toggle() } label: {
                    Image(systemName: "info.circle").frame(width: 28, height: 28)
                }
                .buttonStyle(.borderless)
                .help(CredentialsCopy.savedDoesNotVerify)
                .accessibilityLabel(CredentialsCopy.storageInfo)
                .popover(isPresented: $showsStorageInfo) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(CredentialsCopy.keychain).font(.headline)
                        Text(CredentialsCopy.savedDoesNotVerify).font(.callout)
                        Text(CredentialsCopy.keyHint).font(.caption).foregroundStyle(.secondary)
                        HStack {
                            Spacer()
                            Button(CredentialsCopy.done) { showsStorageInfo = false }
                                .keyboardShortcut(.cancelAction)
                        }
                    }
                    .padding(20)
                    .frame(width: 330)
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(.secondary)
        }
        .onAppear { expandedProvider = activeProvider ?? .openAI }
        .onChange(of: activeProvider) { _, provider in
            if let provider { expandedProvider = provider }
        }
    }

    private var azureConfiguration: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(CredentialsCopy.endpoint).font(.caption.weight(.medium))
            TextField("https://….cognitiveservices.azure.com", text: Binding(
                get: { session.azureSpeechEndpoint },
                set: { if !isLocked { session.azureSpeechEndpoint = $0 } }
            ))
            .textFieldStyle(.roundedBorder)
            .disabled(isLocked)
            .accessibilityLabel(AzureMAICopy.endpointLabel)
            .help(CredentialsCopy.endpointRequired)
            if !validAzureEndpoint {
                Label(CredentialsCopy.endpointRequired, systemImage: "exclamationmark.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var activeProvider: CredentialProvider? {
        if session.isUsingGrokSTT { return .grok }
        if session.isUsingNariSTT { return .nari }
        if session.isUsingAzureMAI { return .azure }
        if session.isUsingMetaScribe { return .meta }
        if session.isUsingGemini { return .gemini }
        if session.isUsingOpenAIRealtime || session.isUsingGPTTranscriptionMode { return .openAI }
        return nil
    }

    private func hasKey(_ provider: CredentialProvider) -> Bool {
        switch provider {
        case .openAI: session.hasOpenAIAPIKey
        case .gemini: session.hasGeminiAPIKey
        case .meta: session.hasMetaAPIKey
        case .azure: session.hasAzureSpeechAPIKey
        case .nari: session.hasNariAPIKey
        case .grok: session.hasGrokAPIKey
        }
    }

    private func model(for provider: CredentialProvider) -> String {
        switch provider {
        case .openAI:
            session.isUsingGPTTranscriptionMode
                ? OpenAIRealtimeTranscriptionModel.gptLiveTranscribe.title
                : (session.openAITranslationModel.isEnabled ? session.openAITranslationModel.title : OpenAIRealtimeTranslationModel.gptRealtimeTranslate.title)
        case .gemini: (session.geminiTranslationModel.isEnabled ? session.geminiTranslationModel : session.preferredGeminiModel).title
        case .meta: MetaTranscriptionModel.museVoiceTranscribe.title
        case .azure: "MAI-Transcribe-2"
        case .nari: "Qwen3-ASR"
        case .grok: GrokTranscriptionModel.voiceTranscribe2.title
        }
    }

    private func detail(for provider: CredentialProvider) -> String {
        switch provider {
        case .openAI: AppText.openAIAPIKeyDescription
        case .gemini: AppText.geminiAPIKeyDescription
        case .meta: AppText.metaScribeDetail
        case .azure: AzureMAICopy.detail
        case .nari: NariCopy.detail + "\n\n" + NariCopy.modelDetail
        case .grok: GrokCopy.detail
        }
    }

    private func save(_ key: String, for provider: CredentialProvider) throws {
        guard !isLocked else { return }
        switch provider {
        case .openAI: try session.saveOpenAIAPIKey(key)
        case .gemini: try session.saveGeminiAPIKey(key)
        case .meta: try session.saveMetaAPIKey(key)
        case .azure: try session.saveAzureSpeechAPIKey(key)
        case .nari: try session.saveNariAPIKey(key)
        case .grok: try session.saveGrokAPIKey(key)
        }
    }

    private func remove(_ provider: CredentialProvider) throws {
        guard !isLocked else { return }
        switch provider {
        case .openAI: try session.removeOpenAIAPIKey()
        case .gemini: try session.removeGeminiAPIKey()
        case .meta: try session.removeMetaAPIKey()
        case .azure: try session.removeAzureSpeechAPIKey()
        case .nari: try session.removeNariAPIKey()
        case .grok: try session.removeGrokAPIKey()
        }
    }
}

private enum CredentialProvider: String, CaseIterable, Identifiable {
    case openAI, gemini, meta, azure, nari, grok
    var id: String { rawValue }
    var title: String {
        switch self {
        case .openAI: "OpenAI"
        case .gemini: "Gemini"
        case .meta: "Meta"
        case .azure: "Azure"
        case .nari: "Nari"
        case .grok: GrokCopy.provider
        }
    }
    var symbol: String {
        switch self {
        case .openAI: "waveform"
        case .gemini: "sparkles"
        case .meta: "person.2.wave.2"
        case .azure: "cloud"
        case .nari: "waveform.badge.mic"
        case .grok: "waveform"
        }
    }
    var consoleURL: URL {
        let address: String = switch self {
        case .openAI: "https://platform.openai.com/api-keys"
        case .gemini: "https://aistudio.google.com/apikey"
        case .meta: "https://dev.meta.ai"
        case .azure: "https://portal.azure.com"
        case .nari: "https://app.narilabs.com/keys"
        case .grok: "https://console.x.ai"
        }
        return URL(string: address)!
    }
}
