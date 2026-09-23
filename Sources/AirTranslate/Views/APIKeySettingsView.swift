import SwiftUI

struct APIKeySettingsView: View {
    @Bindable var session: TranslationSessionStore
    var onExpandProvider: (CredentialProvider) -> Void = { _ in }
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
                if isLocked {
                    InlineHelpIcon(symbol: "lock.fill", help: CredentialsCopy.locked)
                }
                InlineHelpIcon(
                    symbol: "checkmark.shield",
                    help: CredentialsCopy.summary(saved: CredentialProvider.allCases.filter(hasKey).count, total: CredentialProvider.allCases.count)
                )
                storageInfoButton
            }
            .foregroundStyle(.secondary)

            VStack(spacing: 0) {
                ForEach(CredentialProvider.allCases) { provider in
                    ProviderCredentialRow(
                        name: provider.title,
                        symbol: provider.symbol,
                        model: model(for: provider),
                        detail: detail(for: provider),
                        consoleURL: provider.consoleURL,
                        hasKey: hasKey(provider),
                        needsConfiguration: (provider == .azure && !validAzureEndpoint) || (provider == .qwen && !session.hasQwenConfiguration),
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
                        if provider == .qwen { qwenConfiguration }
                    }
                    .id(provider.rawValue)
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
        }
        .onAppear {
            expandedProvider = session.requestedAPIKeyProvider ?? activeProvider ?? .openAI
            session.requestedAPIKeyProvider = nil
            if let expandedProvider { onExpandProvider(expandedProvider) }
        }
        .onChange(of: session.requestedAPIKeyProvider) { _, provider in
            guard let provider else { return }
            expandedProvider = provider
            session.requestedAPIKeyProvider = nil
            onExpandProvider(provider)
        }
        .onChange(of: expandedProvider) { _, provider in
            if let provider { onExpandProvider(provider) }
        }
        .onChange(of: activeProvider) { _, provider in
            if let provider { expandedProvider = provider }
        }
    }

    private var storageInfoButton: some View {
        Button { showsStorageInfo.toggle() } label: {
            Image(systemName: "lock.shield").frame(width: 28, height: 28)
        }
        .buttonStyle(.borderless)
        .help("\(CredentialsCopy.keychain)\n\(CredentialsCopy.savedDoesNotVerify)")
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
    }

    private var qwenConfiguration: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(QwenCopy.workspaceLabel).font(.caption.weight(.medium))
            TextField("Workspace ID", text: Binding(
                get: { session.qwenWorkspaceID },
                set: { if !isLocked { session.qwenWorkspaceID = $0.trimmingCharacters(in: .whitespacesAndNewlines) } }
            ))
            .textFieldStyle(.roundedBorder)
            .disabled(isLocked)
            .accessibilityLabel(QwenCopy.workspaceLabel)
            .accessibilityIdentifier("qwenWorkspaceID")
            .help(QwenCopy.workspaceHint)
            Text(QwenCopy.workspaceHint).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
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
        if session.isUsingQwenTranslation { return .qwen }
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
        case .qwen: session.hasQwenAPIKey
        case .grok: session.hasGrokAPIKey
        }
    }

    private func model(for provider: CredentialProvider) -> String {
        switch provider {
        case .openAI:
            ProcessingEngine.openAI.information(in: session).modelID
        case .gemini: (session.geminiTranslationModel.isEnabled ? session.geminiTranslationModel : session.preferredGeminiModel).title
        case .meta: MetaTranscriptionModel.museVoiceTranscribe.title
        case .azure: "MAI-Transcribe-2"
        case .nari: "Qwen3-ASR"
        case .qwen: selectedQwenModel.rawValue
        case .grok: GrokTranscriptionModel.voiceTranscribe2.title
        }
    }

    private func detail(for provider: CredentialProvider) -> String {
        switch provider {
        case .openAI: AppText.openAIAudioDescription
        case .gemini: AppText.geminiAPIKeyDescription
        case .meta: AppText.metaScribeDetail
        case .azure: AzureMAICopy.detail
        case .nari: NariCopy.detail + "\n\n" + NariCopy.modelDetail
        case .qwen: QwenCopy.detail(for: selectedQwenModel) + "\n\n" + QwenCopy.price(for: selectedQwenModel)
        case .grok: GrokCopy.detail
        }
    }

    private var selectedQwenModel: QwenTranslationModel {
        session.qwenTranslationModel.isEnabled ? session.qwenTranslationModel : .liveTranslateFlashRealtime
    }

    private func save(_ key: String, for provider: CredentialProvider) throws {
        guard !isLocked else { return }
        switch provider {
        case .openAI: try session.saveOpenAIAPIKey(key)
        case .gemini: try session.saveGeminiAPIKey(key)
        case .meta: try session.saveMetaAPIKey(key)
        case .azure: try session.saveAzureSpeechAPIKey(key)
        case .nari: try session.saveNariAPIKey(key)
        case .qwen: try session.saveQwenAPIKey(key)
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
        case .qwen: try session.removeQwenAPIKey()
        case .grok: try session.removeGrokAPIKey()
        }
    }
}

enum CredentialProvider: String, CaseIterable, Identifiable {
    case openAI, gemini, meta, azure, nari, grok, qwen
    var id: String { rawValue }
    var title: String {
        switch self {
        case .openAI: "OpenAI"
        case .gemini: "Gemini"
        case .meta: "Meta"
        case .azure: "Azure"
        case .nari: "Nari"
        case .qwen: QwenCopy.provider
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
        case .qwen: "globe"
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
        case .qwen: "https://modelstudio.console.alibabacloud.com"
        case .grok: "https://console.x.ai"
        }
        return URL(string: address)!
    }
}
