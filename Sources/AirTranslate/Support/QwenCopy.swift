import Foundation

enum QwenCopy {
    static let title = "Qwen LiveTranslate"
    static let provider = "Alibaba Cloud · Qwen"
    static let detail = copy("Qwen3.8 live translation with automatic source detection and optional speech. Audio is sent to Alibaba Cloud in Singapore.", "입력 언어를 자동 감지하는 Qwen3.8 실시간 번역입니다. 음성 출력을 선택할 수 있으며, 오디오는 Alibaba Cloud 싱가포르로 전송됩니다.", "入力言語を自動検出するQwen3.8リアルタイム翻訳。音声出力を選択でき、音声はAlibaba Cloudのシンガポールに送信されます。", "Qwen3.8 实时翻译，自动检测源语言，可选语音输出。音频发送至阿里云新加坡。")
    static let configurationRequired = copy("Add a Singapore API key and workspace ID in Settings → API Keys → Qwen.", "설정 → API 키 → Qwen에서 싱가포르 API 키와 워크스페이스 ID를 입력해 주세요.", "設定 → APIキー → QwenでシンガポールのAPIキーとワークスペースIDを入力してください。", "请在设置 → API 密钥 → Qwen 中输入新加坡 API 密钥和工作空间 ID。")
    static let workspaceLabel = copy("Workspace ID · Singapore", "워크스페이스 ID · 싱가포르", "ワークスペースID · シンガポール", "工作空间 ID · 新加坡")
    static let workspaceHint = copy("Use the workspace that issued your Singapore Model Studio API key. Enter the ID, not a URL.", "싱가포르 Model Studio API 키를 발급한 워크스페이스의 ID를 입력하세요. URL은 입력하지 않습니다.", "シンガポールのModel Studio APIキーを発行したワークスペースのIDを入力してください。URLではありません。", "请输入创建新加坡 Model Studio API 密钥的工作空间 ID，不是 URL。")
    static let keyInvalid = copy("Enter a valid Qwen API key.", "올바른 Qwen API 키를 입력해 주세요.", "有効なQwen APIキーを入力してください。", "请输入有效的 Qwen API 密钥。")
    static let connecting = copy("Connecting to Qwen LiveTranslate…", "Qwen LiveTranslate 연결 중…", "Qwen LiveTranslateに接続中…", "正在连接 Qwen LiveTranslate…")
    static let finishing = copy("Finishing Qwen translation…", "마지막 Qwen 번역을 받는 중…", "Qwenの最後の翻訳を受信中…", "正在接收最后的 Qwen 翻译…")
    static let reconnecting = copy("Reconnecting to Qwen…", "Qwen 다시 연결 중…", "Qwenに再接続中…", "正在重新连接 Qwen…")
    static let price = copy("Singapore · input $0.189/hour + translated text $20/1M tokens; speech output +$1.35/hour. Source transcript is free. Checked 2026-09-20.", "싱가포르 · 입력 $0.189/시간 + 번역문 $20/100만 토큰 · 음성 출력 추가 $1.35/시간. 원문 전사는 무료. 2026-09-20 확인.", "シンガポール · 入力 $0.189/時間 + 翻訳文 $20/100万トークン · 音声出力 +$1.35/時間。原文文字起こしは無料。2026-09-20確認。", "新加坡 · 输入 $0.189/小时 + 译文 $20/百万 token；语音输出另加 $1.35/小时。原文转写免费。2026-09-20 确认。")
    private static func copy(_ en: String, _ ko: String, _ ja: String, _ zh: String) -> String {
        AppText.localized(english: en, korean: ko, japanese: ja, chineseSimplified: zh)
    }
}
