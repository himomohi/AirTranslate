import SwiftUI

struct ProcessingModePicker: View {
    @Bindable var session: TranslationSessionStore
    @Environment(\.openSettings) private var openSettings
    @State private var isPresented = false

    private var currentEngine: ProcessingEngine { .current(for: session) }

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "cpu")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AirTranslateDesign.Palette.textSecondary)
                Text(currentModelTitle)
                    .font(AirTranslateDesign.Typography.label)
                    .foregroundStyle(AirTranslateDesign.Palette.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(AirTranslateDesign.Palette.textSecondary)
            }
            .frame(minWidth: 100, maxWidth: 210, minHeight: 32)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .airFocusRing(cornerRadius: 12)
        .help(ModePickerCopy.chooseProviderAndModel)
        .accessibilityLabel(ModePickerCopy.chooseProviderAndModel)
        .accessibilityValue(currentModelTitle)
        .accessibilityIdentifier("processingModePicker")
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    Text(ModePickerCopy.chooseProviderAndModel)
                        .font(.headline)
                    Spacer()
                    if session.isRunning || session.isStarting {
                        InlineHelpIcon(symbol: "lock.fill", help: AppText.lockedDuringSession)
                            .accessibilityIdentifier("processingModeLockInfo")
                    }
                    InlineHelpIcon(symbol: "dollarsign.circle", help: ProcessingModeInfo.pricingNote)
                        .accessibilityIdentifier("processingModePricingInfo")
                }
                .padding(.leading, 10)
                .padding(.trailing, 5)
                ScrollView(.vertical) {
                    VStack(spacing: 4) {
                        ForEach(ProcessingEngine.allCases) { engine in
                            ProcessingModeRow(
                                engine: engine,
                                information: engine.information(in: session),
                                isSelected: engine == currentEngine,
                                hasKey: engine.hasRequiredKey(in: session),
                                canSelect: engine.canSelect(in: session),
                                select: {
                                    guard engine.select(in: session) else { return }
                                    isPresented = false
                                },
                                settings: {
                                    engine.requestSettings(in: session)
                                    isPresented = false
                                    openSettings()
                                }
                            )
                        }
                    }
                }
                .frame(height: 220)
                .accessibilityIdentifier("processingProviderList")

                Divider()
                    .padding(.vertical, 3)

                HStack(spacing: 8) {
                    Text(ModePickerCopy.model)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AirTranslateDesign.Palette.textSecondary)
                    Spacer(minLength: 4)
                    providerModelPicker
                }
                .accessibilityIdentifier("mainProviderModelSelection")

                if !session.isTranscribeOnlyMode && !session.isUsingProviderRealtimeTranslation {
                    HStack(spacing: 8) {
                        Text(ModePickerCopy.speechModel)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(AirTranslateDesign.Palette.textSecondary)
                        Spacer(minLength: 4)
                        Picker(ModePickerCopy.speechModel, selection: $session.speechSynthesisModel) {
                            ForEach(SpeechSynthesisModel.allCases) { model in
                                Text(model.title).tag(model)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .disabled(session.isRunning || session.isStarting)
                        .accessibilityLabel(ModePickerCopy.speechModel)
                        .accessibilityValue(session.speechSynthesisModel.title)
                        .accessibilityIdentifier("mainSpeechSynthesisModelPicker")
                    }
                }
            }
            .padding(10)
            .frame(width: 330)
            .background(AirTranslateDesign.Palette.raised)
        }
    }

    private var currentModelTitle: String {
        switch currentEngine {
        case .apple:
            session.isTranscribeOnlyMode ? IntelligenceModel.appleSpeechOnly.title : AppText.appleProcessingMode
        case .openAI:
            session.openAIOutputMode == .translation ? "gpt-realtime-translate" : "gpt-live-transcribe"
        case .gemini:
            (session.geminiTranslationModel.isEnabled ? session.geminiTranslationModel : session.preferredGeminiModel).title
        case .meta:
            MetaTranscriptionModel.museVoiceTranscribe.title
        case .azure:
            "MAI-Transcribe-2"
        case .nari:
            (session.nariTranscriptionModel.isEnabled ? session.nariTranscriptionModel : .qwen3ASRFast).title
        case .grok:
            GrokTranscriptionModel.voiceTranscribe2.title
        case .qwen:
            (session.qwenTranslationModel.isEnabled ? session.qwenTranslationModel : session.preferredQwenModel).title
        }
    }

    @ViewBuilder
    private var providerModelPicker: some View {
        Group {
            switch currentEngine {
            case .apple:
                Picker(ModePickerCopy.model, selection: appleModelSelection) {
                    Text(AppText.appleProcessingMode).tag(IntelligenceModel.appleSystem)
                    Text(IntelligenceModel.appleSpeechOnly.title).tag(IntelligenceModel.appleSpeechOnly)
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .accessibilityIdentifier("mainProviderModelPicker.apple")
            case .openAI:
                Picker(ModePickerCopy.model, selection: openAIModelSelection) {
                    Text("gpt-realtime-translate").tag(LiveOutputMode.translation)
                    Text("gpt-live-transcribe").tag(LiveOutputMode.transcription)
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .accessibilityIdentifier("mainProviderModelPicker.openAI")
            case .gemini:
                Picker(ModePickerCopy.model, selection: geminiModelSelection) {
                    ForEach(GeminiTranslationModel.selectableCases) { model in
                        Text(model.title).tag(model)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .accessibilityIdentifier("mainProviderModelPicker.gemini")
            case .qwen:
                Picker(ModePickerCopy.model, selection: qwenModelSelection) {
                    ForEach(QwenTranslationModel.selectableCases) { model in
                        Text(model.title).tag(model)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .accessibilityIdentifier("mainProviderModelPicker.qwen")
            case .nari:
                Picker(ModePickerCopy.model, selection: nariModelSelection) {
                    if session.nariTranscriptionModel.isLegacyFreeEndpoint {
                        Text(session.nariTranscriptionModel.title)
                            .tag(session.nariTranscriptionModel)
                            .disabled(true)
                    }
                    ForEach(NariTranscriptionModel.selectableCases.filter(\.canStart)) { model in
                        Text(model.title).tag(model)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .accessibilityIdentifier("mainProviderModelPicker.nari")
            case .grok:
                Text(GrokTranscriptionModel.voiceTranscribe2.title)
                    .accessibilityLabel(ModePickerCopy.model)
                    .accessibilityValue(GrokTranscriptionModel.voiceTranscribe2.title)
                    .accessibilityIdentifier("mainProviderModelPicker.grok")
            case .meta:
                Text(MetaTranscriptionModel.museVoiceTranscribe.title)
                    .accessibilityLabel(ModePickerCopy.model)
                    .accessibilityValue(MetaTranscriptionModel.museVoiceTranscribe.title)
                    .accessibilityIdentifier("mainProviderModelPicker.meta")
            case .azure:
                Text("MAI-Transcribe-2")
                    .accessibilityLabel(ModePickerCopy.model)
                    .accessibilityValue("MAI-Transcribe-2")
                    .accessibilityIdentifier("mainProviderModelPicker.azure")
            }
        }
        .frame(maxWidth: 210, alignment: .trailing)
        .disabled(session.isRunning || session.isStarting)
        .accessibilityLabel(ModePickerCopy.model)
        .accessibilityValue(currentModelTitle)
    }

    private var appleModelSelection: Binding<IntelligenceModel> {
        Binding {
            session.isTranscribeOnlyMode ? .appleSpeechOnly : .appleSystem
        } set: { model in
            guard !session.isRunning, !session.isStarting else { return }
            if model == .appleSpeechOnly {
                session.useTranscribeOnlyMode()
            } else {
                session.useAppleDefaultMode()
            }
        }
    }

    private var openAIModelSelection: Binding<LiveOutputMode> {
        Binding {
            session.openAIOutputMode
        } set: { mode in
            guard !session.isRunning, !session.isStarting else { return }
            session.useOpenAIMode(mode)
        }
    }

    private var geminiModelSelection: Binding<GeminiTranslationModel> {
        Binding {
            session.geminiTranslationModel.isEnabled ? session.geminiTranslationModel : session.preferredGeminiModel
        } set: { model in
            guard !session.isRunning, !session.isStarting else { return }
            session.useGeminiMode(model)
        }
    }

    private var qwenModelSelection: Binding<QwenTranslationModel> {
        Binding {
            session.qwenTranslationModel.isEnabled ? session.qwenTranslationModel : session.preferredQwenModel
        } set: { model in
            guard !session.isRunning, !session.isStarting else { return }
            session.qwenTranslationModel = model
        }
    }

    private var nariModelSelection: Binding<NariTranscriptionModel> {
        Binding {
            session.nariTranscriptionModel.isEnabled ? session.nariTranscriptionModel : .qwen3ASRFast
        } set: { model in
            guard !session.isRunning, !session.isStarting else { return }
            session.nariTranscriptionModel = model
        }
    }
}

private struct ProcessingModeRow: View {
    let engine: ProcessingEngine
    let information: ProcessingModeInfo
    let isSelected: Bool
    let hasKey: Bool
    let canSelect: Bool
    let select: () -> Void
    let settings: () -> Void
    @State private var isHovered = false

    private var status: String {
        if !hasKey { return ModePickerCopy.keyRequired }
        return engine == .apple ? ModePickerCopy.noKeyRequired : ModePickerCopy.keySaved
    }

    var body: some View {
        HStack(spacing: 4) {
            // 키 없는 선택 버튼 바깥에 도움말을 두고 설정 아이콘과 영역을 분리한다.
            HStack(spacing: 0) {
                Button(action: select) {
                    HStack(spacing: 10) {
                        Image(systemName: isSelected ? "checkmark" : (engine.credentialProvider?.symbol ?? "cpu"))
                            .font(.system(size: 13, weight: .semibold))
                            .frame(width: 20)
                        Text(engine.title)
                            .font(.system(size: 13, weight: .medium))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(canSelect ? AirTranslateDesign.Palette.textPrimary : AirTranslateDesign.Palette.textSecondary)
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(ModeSelectionButtonStyle())
                .disabled(!canSelect)
                .airFocusRing(cornerRadius: 8)
                .accessibilityLabel(engine.title)
                .accessibilityHint(information.tooltip)
                .accessibilityValue(isSelected ? "\(ModePickerCopy.selected), \(status)" : status)
                .accessibilityIdentifier("processingMode.\(engine.rawValue)")
            }
            .help(information.tooltip)

            InlineHelpIcon(
                symbol: engine == .apple ? "desktopcomputer" : (hasKey ? "checkmark.circle.fill" : "key"),
                help: "\(engine.title) · \(status)",
                tint: hasKey ? AirTranslateDesign.Palette.accent : AirTranslateDesign.Palette.textSecondary
            )
            .accessibilityIdentifier("processingModeKeyStatus.\(engine.rawValue)")

            InlineHelpIcon(symbol: "info.circle", help: information.tooltip)
                .accessibilityIdentifier("processingModeInfo.\(engine.rawValue)")

            Button(action: settings) {
                Image(systemName: "gearshape")
                    .font(.system(size: 12))
                    .foregroundStyle(AirTranslateDesign.Palette.textSecondary)
                    .frame(width: 30, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .airFocusRing(cornerRadius: 8)
            .help("\(engine.title) · \(AppText.translationSettings)")
            .accessibilityLabel("\(engine.title) · \(AppText.translationSettings)")
            .accessibilityIdentifier("processingModeSettings.\(engine.rawValue)")
            .padding(.trailing, 5)
        }
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? AirTranslateDesign.Palette.accent.opacity(0.12)
                      : (isHovered ? AirTranslateDesign.Palette.textSecondary.opacity(0.08) : Color.clear))
        }
        .onHover { isHovered = $0 }
    }
}

// 비활성 상태는 회색으로 구분하되 기본 plain 스타일의 추가 감광은 피한다.
private struct ModeSelectionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.75 : 1)
    }
}

private enum ModePickerCopy {
    static let chooseProviderAndModel = AppText.localized(english: "Choose Provider and Model", korean: "공급자와 모델 선택", japanese: "プロバイダーとモデルを選択", chineseSimplified: "选择提供商和模型")
    static let model = AppText.localized(english: "Model", korean: "모델", japanese: "モデル", chineseSimplified: "模型")
    static let speechModel = AppText.localized(english: "Translation Voice", korean: "번역 음성", japanese: "翻訳音声", chineseSimplified: "翻译语音")
    static let keyRequired = AppText.localized(english: "API key required", korean: "API 키 필요", japanese: "APIキーが必要", chineseSimplified: "需要 API 密钥")
    static let keySaved = AppText.localized(english: "API key saved", korean: "API 키 저장됨", japanese: "APIキー保存済み", chineseSimplified: "API 密钥已保存")
    static let noKeyRequired = AppText.localized(english: "No API key needed", korean: "API 키 없이 사용", japanese: "APIキー不要", chineseSimplified: "无需 API 密钥")
    static let selected = AppText.localized(english: "Selected", korean: "선택됨", japanese: "選択中", chineseSimplified: "已选择")
}
