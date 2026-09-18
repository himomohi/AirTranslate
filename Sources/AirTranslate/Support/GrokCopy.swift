import Foundation

enum GrokCopy {
    static let title = "Grok STT"
    static let modelLabel = AppText.localized(
        english: "Grok transcription model", korean: "Grok 전사 모델",
        japanese: "Grok文字起こしモデル", chineseSimplified: "Grok 转写模型"
    )
    static let configurationRequired = AppText.localized(
        english: "Save a SpaceXAI (xAI) API key in API Keys settings.",
        korean: "API 키 설정에서 SpaceXAI(xAI) API 키를 저장하세요.",
        japanese: "APIキー設定でSpaceXAI (xAI) APIキーを保存してください。",
        chineseSimplified: "请在 API 密钥设置中保存 SpaceXAI (xAI) API 密钥。"
    )
    static let configureSpeech = AppText.localized(
        english: "Configure Grok STT", korean: "Grok STT 설정",
        japanese: "Grok STTを設定", chineseSimplified: "配置 Grok STT"
    )
    static let keyInvalid = AppText.localized(
        english: "Enter a valid SpaceXAI (xAI) API key.", korean: "올바른 SpaceXAI(xAI) API 키를 입력하세요.",
        japanese: "有効なSpaceXAI (xAI) APIキーを入力してください。", chineseSimplified: "请输入有效的 SpaceXAI (xAI) API 密钥。"
    )
    static let languageUnsupported = AppText.localized(
        english: "Choose a source language supported by Grok STT.",
        korean: "Grok STT가 지원하는 원문 언어를 선택하세요.",
        japanese: "Grok STTに対応した原文言語を選択してください。",
        chineseSimplified: "请选择 Grok STT 支持的源语言。"
    )
    static let connecting = AppText.localized(
        english: "Connecting to Grok STT…", korean: "Grok STT 연결 중…",
        japanese: "Grok STTに接続中…", chineseSimplified: "正在连接 Grok STT…"
    )
    static let finishing = AppText.localized(
        english: "Finishing the last Grok audio segment…", korean: "Grok 마지막 오디오 구간 처리 중…",
        japanese: "最後のGrok音声区間を処理中…", chineseSimplified: "正在处理最后的 Grok 音频片段…"
    )
    static let reconnecting = AppText.localized(
        english: "Reconnecting to Grok STT…", korean: "Grok STT 다시 연결 중…",
        japanese: "Grok STTに再接続中…", chineseSimplified: "正在重新连接 Grok STT…"
    )
    static let interrupted = AppText.localized(
        english: "The Grok STT connection was interrupted. Check your connection and restart transcription.",
        korean: "Grok STT 연결이 끊겼습니다. 네트워크를 확인하고 전사를 다시 시작하세요.",
        japanese: "Grok STTの接続が切断されました。ネットワークを確認して文字起こしを再開してください。",
        chineseSimplified: "Grok STT 连接已中断。请检查网络并重新开始转写。"
    )
    static let provider = "SpaceXAI (xAI)"
    static let detail = AppText.localized(
        english: "Grok Voice Transcribe 2.0 sends microphone or Mac audio to SpaceXAI (xAI) for live transcription. API usage may incur charges. Translation optionally uses Apple translation.",
        korean: "마이크나 Mac 오디오를 SpaceXAI(xAI)로 보내 Grok Voice Transcribe 2.0으로 실시간 전사합니다. API 사용 요금이 발생할 수 있습니다. 번역을 켜면 Apple 번역을 사용합니다.",
        japanese: "マイクまたはMac音声をSpaceXAI (xAI)に送り、Grok Voice Transcribe 2.0でリアルタイムに文字起こしします。API利用料金が発生する場合があります。翻訳にはApple翻訳を使用します。",
        chineseSimplified: "将麦克风或 Mac 音频发送到 SpaceXAI (xAI)，使用 Grok Voice Transcribe 2.0 实时转写。API 使用可能产生费用。可选翻译使用 Apple 翻译。"
    )
    static let autoDetectDetail = AppText.localized(
        english: "Grok recognizes speech automatically. Turn this off to use the selected source language for number, currency and unit formatting; it does not restrict recognition to that language.",
        korean: "Grok은 음성 언어를 자동으로 인식합니다. 끄면 선택한 원문 언어를 숫자·통화·단위 표기에 사용하며, 인식 언어를 제한하지는 않습니다.",
        japanese: "Grokは音声言語を自動認識します。オフにすると選択した原文言語を数字・通貨・単位の表記に使用しますが、認識言語は制限しません。",
        chineseSimplified: "Grok 自动识别语音语言。关闭后，所选源语言用于数字、货币和单位的格式化，不会限制识别语言。"
    )
    static let translationLanguageUnavailable = AppText.localized(
        english: "Grok did not return a supported language. Original captions are preserved; select a source language to translate.",
        korean: "Grok이 지원 가능한 언어 정보를 반환하지 않았습니다. 원문 자막은 보존됩니다. 번역하려면 원문 언어를 선택하세요.",
        japanese: "Grokが対応する言語情報を返しませんでした。原文字幕は保持されます。翻訳には原文言語を選択してください。",
        chineseSimplified: "Grok 未返回支持的语言信息。原文字幕已保留；请选择源语言进行翻译。"
    )
}
