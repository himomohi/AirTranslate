import Foundation

enum NariCopy {
    static let title = "Nari STT"
    static let detail = AppText.localized(
        english: "Qwen3-ASR sends microphone or Mac audio to Nari for live transcription. GA models use paid Nari credits. Translation uses the existing Apple translation workflow.",
        korean: "마이크나 Mac 오디오를 Nari로 보내 Qwen3-ASR로 실시간 전사합니다. GA 모델은 유료 Nari 크레딧을 사용합니다. 번역은 기존 Apple 번역 흐름을 사용합니다.",
        japanese: "マイクまたはMacの音声をNariに送信し、Qwen3-ASRでリアルタイムに文字起こしします。GAモデルは有料のNariクレジットを使用します。翻訳には既存のApple翻訳を使用します。",
        chineseSimplified: "将麦克风或 Mac 音频发送到 Nari，使用 Qwen3-ASR 实时转写。GA 模型会使用付费 Nari 额度。翻译使用现有的 Apple 翻译流程。"
    )
    static let modelLabel = AppText.localized(
        english: "Nari transcription model", korean: "Nari 전사 모델",
        japanese: "Nari文字起こしモデル", chineseSimplified: "Nari 转写模型"
    )
    static let modelDetail = AppText.localized(
        english: "Free Public Beta endpoints stop accepting requests starting September 17, 2026 PT. Choose a GA model only when you intend to use Nari credits.",
        korean: "Free Public Beta 엔드포인트는 2026년 9월 17일 PT부터 요청을 받지 않습니다. Nari 크레딧 사용을 이해한 경우에만 GA 모델을 선택하세요.",
        japanese: "Free Public Betaエンドポイントは2026年9月17日 PT以降リクエストを受け付けません。Nariクレジットの使用を理解している場合のみGAモデルを選択してください。",
        chineseSimplified: "Free Public Beta 端点自 2026 年 9 月 17 日 PT 起停止接受请求。仅在明确会使用 Nari 额度时选择 GA 模型。"
    )
    static let standardBilling = AppText.localized(
        english: "GA Standard: qwen3-asr, $0.06 per input audio hour. Uses Nari credits.",
        korean: "GA Standard: qwen3-asr, 입력 오디오 시간당 $0.06. Nari 크레딧을 사용합니다.",
        japanese: "GA Standard: qwen3-asr、入力音声1時間あたり$0.06。Nariクレジットを使用します。",
        chineseSimplified: "GA Standard：qwen3-asr，每输入音频小时 $0.06。使用 Nari 额度。"
    )
    static let fastBilling = AppText.localized(
        english: "GA Fast: qwen3-asr-fast, $0.12 per input audio hour. Uses Nari credits.",
        korean: "GA Fast: qwen3-asr-fast, 입력 오디오 시간당 $0.12. Nari 크레딧을 사용합니다.",
        japanese: "GA Fast: qwen3-asr-fast、入力音声1時間あたり$0.12。Nariクレジットを使用します。",
        chineseSimplified: "GA Fast：qwen3-asr-fast，每输入音频小时 $0.12。使用 Nari 额度。"
    )
    static let legacyFreeModelEnded = AppText.localized(
        english: "The selected Free Public Beta model is preserved but blocked. Select a GA model to start Nari STT.",
        korean: "선택되어 있던 Free Public Beta 모델은 보존되지만 시작할 수 없습니다. Nari STT를 시작하려면 GA 모델을 선택하세요.",
        japanese: "選択済みのFree Public Betaモデルは保持されますが開始できません。Nari STTを開始するにはGAモデルを選択してください。",
        chineseSimplified: "已选择的 Free Public Beta 模型会保留，但无法启动。请选择 GA 模型来启动 Nari STT。"
    )
    static let chooseGAModel = AppText.localized(
        english: "Choose GA Nari model",
        korean: "Nari GA 모델 선택",
        japanese: "Nari GAモデルを選択",
        chineseSimplified: "选择 Nari GA 模型"
    )
    static let configurationRequired = AppText.localized(
        english: "Save a Nari API key in API Keys settings.",
        korean: "API 키 설정에서 Nari API 키를 저장하세요.",
        japanese: "APIキー設定でNari APIキーを保存してください。",
        chineseSimplified: "请在 API 密钥设置中保存 Nari API 密钥。"
    )
    static let keyRequired = configurationRequired
    static let configureSpeech = AppText.localized(
        english: "Configure Nari STT", korean: "Nari STT 설정",
        japanese: "Nari STTを設定", chineseSimplified: "配置 Nari STT"
    )
    static let apiKeyLabel = AppText.localized(
        english: "Nari API key", korean: "Nari API 키",
        japanese: "Nari APIキー", chineseSimplified: "Nari API 密钥"
    )
    static let keyDescription = AppText.localized(
        english: "Your personal key is stored only in macOS Keychain and sent to the Nari API when this mode is used. Enter and save a new key to replace it.",
        korean: "개인 키는 macOS Keychain에만 저장되며 이 모드를 사용할 때 Nari API에 전송됩니다. 새 키를 입력하고 저장하면 교체됩니다.",
        japanese: "個人キーはmacOS Keychainにのみ保存され、このモードの利用時にNari APIへ送信されます。新しいキーを入力して保存すると置き換えます。",
        chineseSimplified: "个人密钥仅保存在 macOS 钥匙串中，使用此模式时会发送到 Nari API。输入并保存新密钥即可替换。"
    )
    static let saveKey = AppText.localized(
        english: "Save Nari key", korean: "Nari 키 저장",
        japanese: "Nariキーを保存", chineseSimplified: "保存 Nari 密钥"
    )
    static let removeKey = AppText.localized(
        english: "Remove Nari key", korean: "Nari 키 삭제",
        japanese: "Nariキーを削除", chineseSimplified: "删除 Nari 密钥"
    )
    static let removeKeyConfirmation = AppText.localized(
        english: "Remove the Nari API key from Keychain?", korean: "Keychain의 Nari API 키를 삭제할까요?",
        japanese: "KeychainからNari APIキーを削除しますか？", chineseSimplified: "要从钥匙串中删除 Nari API 密钥吗？"
    )
    static let keySaved = AppText.localized(
        english: "Nari key saved in Keychain. Service access has not been verified.",
        korean: "Nari 키를 Keychain에 저장했습니다. 서비스 연결은 아직 검증하지 않았습니다.",
        japanese: "NariキーをKeychainに保存しました。サービス接続は未検証です。",
        chineseSimplified: "Nari 密钥已保存到钥匙串。尚未验证服务访问。"
    )
    static let keyRemoved = AppText.localized(
        english: "Nari key removed.", korean: "Nari 키를 삭제했습니다.",
        japanese: "Nariキーを削除しました。", chineseSimplified: "Nari 密钥已删除。"
    )
    static let keyConfiguredUnverified = AppText.localized(
        english: "Nari key saved. Service access has not been verified.",
        korean: "Nari 키가 저장되어 있습니다. 서비스 연결은 아직 검증하지 않았습니다.",
        japanese: "Nariキーは保存済みです。サービス接続は未検証です。",
        chineseSimplified: "Nari 密钥已保存。尚未验证服务访问。"
    )
    static let keyInvalid = AppText.localized(
        english: "Enter a valid Nari API key.", korean: "올바른 Nari API 키를 입력하세요.",
        japanese: "有効なNari APIキーを入力してください。", chineseSimplified: "请输入有效的 Nari API 密钥。"
    )
    static let documentation = AppText.localized(
        english: "Nari STT documentation", korean: "Nari STT 문서",
        japanese: "Nari STTドキュメント", chineseSimplified: "Nari STT 文档"
    )
    static let manageKeys = AppText.localized(
        english: "Create or manage Nari keys", korean: "Nari 키 발급 및 관리",
        japanese: "Nariキーの作成と管理", chineseSimplified: "创建或管理 Nari 密钥"
    )
    static let languageUnsupported = AppText.localized(
        english: "Choose a source language supported by Nari STT.",
        korean: "Nari STT가 지원하는 원문 언어를 선택하세요.",
        japanese: "Nari STTに対応した原文言語を選択してください。",
        chineseSimplified: "请选择 Nari STT 支持的源语言。"
    )
    static let autoDetectDetail = AppText.localized(
        english: "Nari can recognize supported spoken languages automatically.",
        korean: "Nari가 지원하는 음성 언어를 자동으로 감지합니다.",
        japanese: "Nariが対応する音声言語を自動検出します。",
        chineseSimplified: "Nari 可以自动识别支持的口语。"
    )
    static let sourceOnly = AppText.originalOnly
    static let connecting = AppText.localized(
        english: "Connecting to Nari STT…", korean: "Nari STT 연결 중…",
        japanese: "Nari STTに接続中…", chineseSimplified: "正在连接 Nari STT…"
    )
    static let finishing = AppText.localized(
        english: "Finishing the last Nari audio segment…", korean: "Nari 마지막 오디오 구간 처리 중…",
        japanese: "最後のNari音声区間を処理中…", chineseSimplified: "正在处理最后的 Nari 音频片段…"
    )
    static let reconnecting = AppText.localized(
        english: "Reconnecting to Nari STT…", korean: "Nari STT 다시 연결 중…",
        japanese: "Nari STTに再接続中…", chineseSimplified: "正在重新连接 Nari STT…"
    )
    static let interrupted = AppText.localized(
        english: "The Nari STT connection was interrupted. Check your connection and restart transcription.",
        korean: "Nari STT 연결이 끊겼습니다. 네트워크를 확인하고 전사를 다시 시작하세요.",
        japanese: "Nari STTの接続が切断されました。ネットワークを確認して文字起こしを再開してください。",
        chineseSimplified: "Nari STT 连接已中断。请检查网络并重新开始转写。"
    )
    static let translationLanguageUnavailable = AppText.localized(
        english: "The recognized language is not available in this app’s Apple translation workflow. Original captions are preserved.",
        korean: "감지된 언어는 이 앱의 Apple 번역 흐름에서 지원하지 않습니다. 원문 자막은 보존됩니다.",
        japanese: "検出された言語は、このアプリのApple翻訳に対応していません。原文字幕は保持されます。",
        chineseSimplified: "识别出的语言不在此应用的 Apple 翻译支持范围内。原文字幕会保留。"
    )
}
