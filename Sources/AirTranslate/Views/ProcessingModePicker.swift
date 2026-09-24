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

                if !session.isTranscribeOnlyMode {
                    HStack(spacing: 8) {
                        Text(ModePickerCopy.speechModel)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(AirTranslateDesign.Palette.textSecondary)
                        InlineHelpIcon(symbol: "info.circle", help: ModePickerCopy.speechModelAvailabilityDetail)
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
                    Section(ModePickerCopy.realtimeTranslationModels) {
                        Text("gpt-realtime-translate").tag(LiveOutputMode.translation)
                    }
                    Section(ModePickerCopy.realtimeTranscriptionModels) {
                        Text("gpt-live-transcribe").tag(LiveOutputMode.transcription)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .accessibilityIdentifier("mainProviderModelPicker.openAI")
            case .gemini:
                Menu {
                    Section(ModePickerCopy.realtimeTranslationModels) {
                        Button {
                            selectGeminiRealtimeModel(.gemini35LiveTranslate)
                        } label: {
                            modelMenuLabel(
                                GeminiTranslationModel.gemini35LiveTranslate.title,
                                isSelected: selectedGeminiRealtimeModel == .gemini35LiveTranslate
                            )
                        }
                        .disabled(session.isRunning || session.isStarting)
                    }

                    Section(ModePickerCopy.realtimeTranscriptionModels) {
                        Button {
                            selectGeminiRealtimeModel(.gemini35TranscribeLive)
                        } label: {
                            modelMenuLabel(
                                GeminiTranslationModel.gemini35TranscribeLive.title,
                                isSelected: selectedGeminiRealtimeModel == .gemini35TranscribeLive
                            )
                        }
                        .disabled(session.isRunning || session.isStarting)
                    }
                }
                label: {
                    HStack(spacing: 6) {
                        Text(currentModelTitle)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                    }
                }
                .menuStyle(.borderlessButton)
                .accessibilityLabel(ModePickerCopy.model)
                .accessibilityValue(currentModelTitle)
                .accessibilityIdentifier("mainProviderModelPicker.gemini")
            case .qwen:
                Menu {
                    Section(ModePickerCopy.qwenDedicatedTranslation) {
                        Button {
                            qwenModelSelection.wrappedValue = .liveTranslateFlashRealtime
                        } label: {
                            modelMenuLabel(
                                QwenTranslationModel.liveTranslateFlashRealtime.title,
                                isSelected: selectedQwenRealtimeModel == .liveTranslateFlashRealtime
                            )
                        }
                        .disabled(session.isRunning || session.isStarting)
                    }

                    Section(ModePickerCopy.qwenPromptedVoiceConversation) {
                        Button {
                            qwenModelSelection.wrappedValue = .audio31RealtimePlus
                        } label: {
                            modelMenuLabel(
                                QwenTranslationModel.audio31RealtimePlus.title,
                                isSelected: selectedQwenRealtimeModel == .audio31RealtimePlus
                            )
                        }
                        .disabled(session.isRunning || session.isStarting)
                    }
                }
                label: {
                    HStack(spacing: 6) {
                        Text(currentModelTitle)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                    }
                }
                .menuStyle(.borderlessButton)
                .accessibilityLabel(ModePickerCopy.model)
                .accessibilityValue(currentModelTitle)
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

    private var selectedGeminiRealtimeModel: GeminiTranslationModel {
        session.geminiTranslationModel.isEnabled ? session.geminiTranslationModel : session.preferredGeminiModel
    }

    private var selectedQwenRealtimeModel: QwenTranslationModel {
        session.qwenTranslationModel.isEnabled ? session.qwenTranslationModel : session.preferredQwenModel
    }

    private func selectGeminiRealtimeModel(_ model: GeminiTranslationModel) {
        guard !session.isRunning, !session.isStarting else { return }
        session.useGeminiMode(model)
    }

    @ViewBuilder
    private func modelMenuLabel(_ title: String, isSelected: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark")
                .opacity(isSelected ? 1 : 0)
                .frame(width: 12)
            Text(title)
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
    static let speechModel = AppText.localized(english: "Text Translation Voice", korean: "텍스트 번역 음성", japanese: "テキスト翻訳の音声", chineseSimplified: "文本翻译语音")
    static let realtimeTranslationModels = AppText.localized(english: "Realtime speech translation", korean: "실시간 음성 번역", japanese: "リアルタイム音声翻訳", chineseSimplified: "实时语音翻译")
    static let realtimeTranscriptionModels = AppText.localized(english: "Realtime transcription", korean: "실시간 음성 전사", japanese: "リアルタイム音声文字起こし", chineseSimplified: "实时语音转写")
    static let qwenDedicatedTranslation = AppText.localized(english: "Dedicated realtime translation", korean: "실시간 번역 전용", japanese: "リアルタイム翻訳専用", chineseSimplified: "专用实时翻译")
    static let qwenPromptedVoiceConversation = AppText.localized(english: "Voice conversation · app translation instructions", korean: "음성 대화 · 앱 번역 지시 적용", japanese: "音声会話 · アプリの翻訳指示を適用", chineseSimplified: "语音对话 · 应用翻译指令")
    static let speechModelAvailabilityDetail = AppText.localized(
        english: "Choose how AirTranslate reads translated text in its Apple TranslationSession workflow, including text transcribed by STT providers: Apple system speech or Gemini TTS. Realtime speech-translation providers use their own audio output.",
        korean: "Apple TranslationSession으로 텍스트를 번역하는 흐름(전사 제공자의 결과를 번역하는 경우 포함)에서 번역문을 읽을 음성을 선택합니다(Apple 시스템 음성 또는 Gemini TTS). 실시간 음성 번역 제공자는 자체 오디오 출력을 사용합니다.",
        japanese: "Apple TranslationSessionでテキストを翻訳するフロー（音声認識プロバイダーの文字起こし結果を翻訳する場合を含む）で読み上げる音声を選択します（Appleシステム音声またはGemini TTS）。リアルタイム音声翻訳プロバイダーは独自の音声出力を使用します。",
        chineseSimplified: "选择在 Apple TranslationSession 文本翻译流程中朗读译文的语音，也包括翻译语音识别提供方转写出的文本（Apple 系统语音或 Gemini TTS）。实时语音翻译提供方使用自己的音频输出。"
    )
    static let keyRequired = AppText.localized(english: "API key required", korean: "API 키 필요", japanese: "APIキーが必要", chineseSimplified: "需要 API 密钥")
    static let keySaved = AppText.localized(english: "API key saved", korean: "API 키 저장됨", japanese: "APIキー保存済み", chineseSimplified: "API 密钥已保存")
    static let noKeyRequired = AppText.localized(english: "No API key needed", korean: "API 키 없이 사용", japanese: "APIキー不要", chineseSimplified: "无需 API 密钥")
    static let selected = AppText.localized(english: "Selected", korean: "선택됨", japanese: "選択中", chineseSimplified: "已选择")
}
