import Foundation

enum AzureTranscriptionModel: String, CaseIterable, Identifiable, Sendable {
    case transcribe2 = "MAI-Transcribe-2"
    case transcribe2Streaming = "MAI-Transcribe-2-Streaming"

    var id: String { rawValue }
    var title: String { rawValue }
    var isStreaming: Bool { self == .transcribe2Streaming }

    func validateEndpoint(_ endpoint: String) throws {
        if isStreaming {
            _ = try AzureMAIStreamingTranscriber.endpointURL(endpoint)
        } else {
            _ = try AzureMAITranscriber.endpointURL(endpoint)
        }
    }
}

enum MAIVoiceCopy {
    static let detail = AppText.localized(
        english: "MAI Voice reads translated text through OpenRouter. Requires an OpenRouter key; usage is billed separately. Voices follow the target language. Realtime translation providers keep their own audio output.",
        korean: "MAI Voice는 번역문을 OpenRouter로 보내 읽습니다. OpenRouter 키가 필요하며 사용료는 별도입니다. 번역 언어에 맞는 음성을 사용합니다. 실시간 번역 제공자는 자체 오디오를 출력합니다.",
        japanese: "MAI Voice は翻訳文を OpenRouter に送信して読み上げます。OpenRouter キーが必要で、利用料金は別途発生します。翻訳先の言語に合う音声を使用します。リアルタイム翻訳プロバイダーは独自の音声を出力します。",
        chineseSimplified: "MAI Voice 将译文发送到 OpenRouter 进行朗读。需要 OpenRouter 密钥，费用另行计费。语音与目标语言匹配。实时翻译提供方使用自身的音频输出。"
    )
    static let keyRequired = AppText.localized(
        english: "Save an OpenRouter key in API Keys settings to use MAI Voice.",
        korean: "MAI Voice를 사용하려면 API 키 설정에서 OpenRouter 키를 저장하세요.",
        japanese: "MAI Voice を使うには API キー設定で OpenRouter キーを保存してください。",
        chineseSimplified: "请在 API 密钥设置中保存 OpenRouter 密钥以使用 MAI Voice。"
    )
    static let languageUnsupported = AppText.localized(
        english: "The selected MAI voice does not support the target language. Choose another voice or speech model. Captions remain available.",
        korean: "선택한 MAI 음성은 번역 언어를 지원하지 않습니다. 다른 음성 또는 음성 모델을 선택하세요. 자막은 계속 사용할 수 있습니다.",
        japanese: "選択した MAI 音声は翻訳先の言語に対応していません。別の音声か音声モデルを選んでください。字幕は引き続き利用できます。",
        chineseSimplified: "所选 MAI 语音不支持目标语言。请选择其他语音或语音模型。字幕仍可使用。"
    )
    static let automaticVoice = AppText.localized(english: "Automatic · target language", korean: "자동 · 번역 언어", japanese: "自動 · 翻訳先の言語", chineseSimplified: "自动 · 目标语言")
    static let voice = AppText.localized(english: "MAI voice", korean: "MAI 음성", japanese: "MAI 音声", chineseSimplified: "MAI 语音")
    static let loadingVoices = AppText.localized(english: "Loading available voices…", korean: "사용 가능한 음성 확인 중…", japanese: "利用可能な音声を確認中…", chineseSimplified: "正在查询可用语音…")
    static let catalogFailed = AppText.localized(english: "Could not load the OpenRouter voice list. Check your connection and try again.", korean: "OpenRouter 음성 목록을 불러오지 못했습니다. 연결을 확인하고 다시 시도하세요.", japanese: "OpenRouter の音声一覧を取得できません。接続を確認して再試行してください。", chineseSimplified: "无法加载 OpenRouter 语音列表。请检查连接后重试。")
    static let configure = AppText.localized(english: "Configure OpenRouter", korean: "OpenRouter 설정", japanese: "OpenRouter を設定", chineseSimplified: "配置 OpenRouter")
}
