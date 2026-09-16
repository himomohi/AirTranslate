import Foundation
import Security

enum AppText {
    private enum InterfaceLanguage {
        case english
        case korean
        case japanese
        case chineseSimplified
    }

    private static var interfaceLanguage: InterfaceLanguage {
        if ProcessInfo.processInfo.environment["AIRTRANSLATE_PRODUCT_HUNT_SCREENSHOTS"] == "1" {
            return .english
        }

        let languageCode = Locale.preferredLanguages.first?.lowercased() ?? ""
        if languageCode.hasPrefix("ko") {
            return .korean
        }
        if languageCode.hasPrefix("ja") {
            return .japanese
        }
        if languageCode.hasPrefix("zh") {
            return .chineseSimplified
        }
        return .english
    }

    static func localized(english: String, korean: String) -> String {
        localized(
            english: english,
            korean: korean,
            japanese: english,
            chineseSimplified: english
        )
    }

    static func localized(
        english: String,
        korean: String,
        japanese: String,
        chineseSimplified: String
    ) -> String {
        switch interfaceLanguage {
        case .english:
            english
        case .korean:
            korean
        case .japanese:
            japanese
        case .chineseSimplified:
            chineseSimplified
        }
    }

    static let appName = "AirTranslate"
    static let appTagline = localized(
        english: "Live transcript translator",
        korean: "실시간 기록 번역",
        japanese: "リアルタイム記録翻訳",
        chineseSimplified: "实时转写翻译"
    )
    static let readyToStartListening = localized(
        english: "Ready to start listening",
        korean: "듣기 시작할 준비가 됐어요",
        japanese: "リスニングを始める準備ができました",
        chineseSimplified: "已准备好开始聆听"
    )
    static let startListening = localized(
        english: "Start Listening",
        korean: "듣기 시작",
        japanese: "リスニングを開始",
        chineseSimplified: "开始聆听"
    )
    static let permissionRequired = localized(
        english: "Permission required",
        korean: "권한이 필요합니다",
        japanese: "権限が必要です",
        chineseSimplified: "需要权限"
    )
    static let moreControls = localized(
        english: "More Controls",
        korean: "더보기",
        japanese: "その他のコントロール",
        chineseSimplified: "更多控制"
    )
    static let languagePair = localized(
        english: "Language Pair",
        korean: "언어 조합",
        japanese: "言語ペア",
        chineseSimplified: "语言组合"
    )
    static let volume = localized(
        english: "Volume",
        korean: "음량",
        japanese: "音量",
        chineseSimplified: "音量"
    )
    static let lockedDuringCapture = localized(
        english: "Locked during capture",
        korean: "캡처 중 잠김",
        japanese: "キャプチャ中はロック中",
        chineseSimplified: "采集期间已锁定"
    )
    static let lockedDuringSession = localized(
        english: "Locked during session",
        korean: "세션 중 잠김",
        japanese: "セッション中はロック中",
        chineseSimplified: "会话期间已锁定"
    )
    static let voiceShort = localized(
        english: "Voice",
        korean: "음성",
        japanese: "音声",
        chineseSimplified: "语音"
    )
    static let turnVoiceOutputOn = localized(
        english: "Turn Voice Output On",
        korean: "음성 출력 켜기",
        japanese: "音声出力をオン",
        chineseSimplified: "开启语音输出"
    )
    static let turnVoiceOutputOff = localized(
        english: "Turn Voice Output Off",
        korean: "음성 출력 끄기",
        japanese: "音声出力をオフ",
        chineseSimplified: "关闭语音输出"
    )
    static let speakerLabelsOn = localized(
        english: "Speaker labels on",
        korean: "화자 라벨 켜짐",
        japanese: "話者ラベル オン",
        chineseSimplified: "说话人标签已开启"
    )
    static let gptMode = localized(
        english: "GPT Mode",
        korean: "GPT 모드",
        japanese: "GPTモード",
        chineseSimplified: "GPT 模式"
    )
    static let ready = localized(english: "Ready", korean: "준비됨", japanese: "準備完了", chineseSimplified: "就绪")
    static let stopped = localized(english: "Stopped", korean: "중지됨", japanese: "停止中", chineseSimplified: "已停止")
    static let paused = localized(english: "Paused", korean: "일시정지됨", japanese: "一時停止中", chineseSimplified: "已暂停")
    static let capture = localized(english: "Capture", korean: "캡처", japanese: "キャプチャ", chineseSimplified: "捕获")
    static let start = localized(english: "Start", korean: "시작", japanese: "開始", chineseSimplified: "开始")
    static let stop = localized(english: "Stop", korean: "중지", japanese: "停止", chineseSimplified: "停止")
    static let close = localized(english: "Close", korean: "닫기", japanese: "閉じる", chineseSimplified: "关闭")
    static let cancel = localized(english: "Cancel", korean: "취소", japanese: "キャンセル", chineseSimplified: "取消")
    static let pause = localized(english: "Pause", korean: "일시정지", japanese: "一時停止", chineseSimplified: "暂停")
    static let resume = localized(english: "Resume", korean: "재개", japanese: "再開", chineseSimplified: "继续")
    static let languages = localized(english: "Languages", korean: "언어", japanese: "言語", chineseSimplified: "语言")
    static let from = localized(english: "From", korean: "원문", japanese: "原文", chineseSimplified: "原文")
    static let to = localized(english: "To", korean: "번역", japanese: "翻訳", chineseSimplified: "译文")
    static let autoDetectShort = localized(english: "Auto", korean: "자동", japanese: "自動", chineseSimplified: "自动")
    static let autoDetectInput = localized(
        english: "Auto-detect input",
        korean: "입력 언어 자동 감지",
        japanese: "入力言語を自動検出",
        chineseSimplified: "自动检测输入语言"
    )
    static let autoDetectionLanguageChangeTitle = localized(
        english: "New input language detected",
        korean: "새 입력 언어가 감지되었습니다",
        japanese: "新しい入力言語を検出しました",
        chineseSimplified: "检测到新的输入语言"
    )
    static let startNewAutoDetectionSession = localized(
        english: "Start New Session",
        korean: "새 세션 시작",
        japanese: "新しいセッションを開始",
        chineseSimplified: "开始新会话"
    )
    static let keepCurrentAutoDetectionLanguage = localized(
        english: "Keep Current Session",
        korean: "현재 세션 유지",
        japanese: "現在のセッションを維持",
        chineseSimplified: "保留当前会话"
    )
    static let preferredLanguageShort = localized(english: "Pref.", korean: "선호", japanese: "優先", chineseSimplified: "首选")
    static let preferredLanguage = localized(
        english: "Preferred language",
        korean: "선호 언어",
        japanese: "優先言語",
        chineseSimplified: "首选语言"
    )
    static let swapLanguages = localized(english: "Swap Languages", korean: "언어 바꾸기", japanese: "言語を入れ替え", chineseSimplified: "交换语言")
    static let model = localized(english: "Mode", korean: "처리 방식", japanese: "処理方式", chineseSimplified: "处理方式")
    static let audioInputSource = localized(
        english: "Audio Input",
        korean: "오디오 입력",
        japanese: "オーディオ入力",
        chineseSimplified: "音频输入"
    )
    static let systemAudioInput = localized(
        english: "Mac Audio",
        korean: "PC 소리",
        japanese: "Mac音声",
        chineseSimplified: "Mac 音频"
    )
    static let microphoneInput = localized(
        english: "Microphone",
        korean: "마이크",
        japanese: "マイク",
        chineseSimplified: "麦克风"
    )
    static let microphoneInputDevice = localized(
        english: "Input Device",
        korean: "입력 장치",
        japanese: "入力デバイス",
        chineseSimplified: "输入设备"
    )
    static let systemDefaultMicrophone = localized(
        english: "System Default",
        korean: "시스템 기본값",
        japanese: "システム標準",
        chineseSimplified: "系统默认"
    )
    static let modelStatusChecking = localized(english: "Checking", korean: "확인 중", japanese: "確認中", chineseSimplified: "正在检查")
    static let modelStatusInstalled = localized(english: "Installed", korean: "설치됨", japanese: "インストール済み", chineseSimplified: "已安装")
    static let modelStatusDownloadRequired = localized(english: "Download Needed", korean: "다운로드 필요", japanese: "ダウンロードが必要", chineseSimplified: "需要下载")
    static let modelStatusDownloading = localized(english: "Downloading", korean: "다운로드 중", japanese: "ダウンロード中", chineseSimplified: "正在下载")
    static let modelStatusUnsupported = localized(english: "Unsupported", korean: "미지원", japanese: "未対応", chineseSimplified: "不支持")
    static let modelStatusUnavailable = localized(english: "Unavailable", korean: "사용 불가", japanese: "利用不可", chineseSimplified: "不可用")
    static let modelStatusFailed = localized(english: "Check Failed", korean: "확인 실패", japanese: "確認失敗", chineseSimplified: "检查失败")
    static let download = localized(english: "Download", korean: "다운로드", japanese: "ダウンロード", chineseSimplified: "下载")
    static let downloadModelAssets = localized(
        english: "Download model assets",
        korean: "모델 자산 다운로드"
    )
    static let requiredAssets = localized(english: "Required Assets", korean: "필요 자산")
    static let speechLanguagePack = localized(
        english: "Speech Recognition Pack",
        korean: "음성 인식 언어팩"
    )
    static let translationLanguagePack = localized(
        english: "Translation Language Pack",
        korean: "번역 언어팩"
    )
    static let openAIAPIKey = localized(english: "OpenAI API Key", korean: "OpenAI API 키")
    static let openAIAPIKeyDescription = localized(
        english: "Enter your API key in the app. AirTranslate stores it in macOS Keychain and uses it only for OpenAI translation and GPT transcription.",
        korean: "앱에서 API 키를 입력하세요. AirTranslate는 키를 macOS Keychain에 저장하고 OpenAI 번역과 GPT 전사에만 사용합니다.",
        japanese: "アプリでAPIキーを入力してください。AirTranslateはキーをmacOS Keychainに保存し、OpenAI翻訳とGPT文字起こしにのみ使用します。",
        chineseSimplified: "请在应用中输入 API key。AirTranslate 会将密钥保存在 macOS Keychain 中，并且仅用于 OpenAI 翻译和 GPT 转写。"
    )
    static let openAIAPIKeyPlaceholder = localized(
        english: "Paste API key",
        korean: "API 키 붙여넣기",
        japanese: "APIキーを貼り付け",
        chineseSimplified: "粘贴 API key"
    )
    static let saveOpenAIAPIKey = localized(english: "Save API Key", korean: "API 키 저장", japanese: "APIキーを保存", chineseSimplified: "保存 API key")
    static let removeOpenAIAPIKey = localized(english: "Remove API Key", korean: "API 키 삭제", japanese: "APIキーを削除", chineseSimplified: "删除 API key")
    static let geminiAPIKeyPlaceholder = localized(
        english: "Paste Gemini API key",
        korean: "Gemini API 키 붙여넣기",
        japanese: "Gemini APIキーを貼り付け",
        chineseSimplified: "粘贴 Gemini API key"
    )
    static let saveGeminiAPIKey = localized(
        english: "Save Gemini API Key",
        korean: "Gemini API 키 저장",
        japanese: "Gemini APIキーを保存",
        chineseSimplified: "保存 Gemini API key"
    )
    static let removeGeminiAPIKey = localized(
        english: "Remove Gemini API Key",
        korean: "Gemini API 키 삭제",
        japanese: "Gemini APIキーを削除",
        chineseSimplified: "删除 Gemini API key"
    )
    static let metaAPIKeyPlaceholder = localized(
        english: "Paste Meta Model API key",
        korean: "Meta Model API 키 붙여넣기",
        japanese: "Meta Model APIキーを貼り付け",
        chineseSimplified: "粘贴 Meta Model API key"
    )
    static let saveMetaAPIKey = localized(
        english: "Save Meta Model API Key",
        korean: "Meta Model API 키 저장",
        japanese: "Meta Model APIキーを保存",
        chineseSimplified: "保存 Meta Model API key"
    )
    static let removeMetaAPIKey = localized(
        english: "Remove Meta Model API Key",
        korean: "Meta Model API 키 삭제",
        japanese: "Meta Model APIキーを削除",
        chineseSimplified: "删除 Meta Model API key"
    )
    static let openAIAPIKeySaved = localized(
        english: "OpenAI API key saved in Keychain.",
        korean: "OpenAI API 키가 Keychain에 저장되었습니다."
    )
    static let openAIAPIKeyRemoved = localized(
        english: "OpenAI API key removed.",
        korean: "OpenAI API 키가 삭제되었습니다."
    )
    static let openAIAPIKeyConfigured = localized(
        english: "API key saved",
        korean: "API 키 저장됨",
        japanese: "APIキー保存済み",
        chineseSimplified: "API key 已保存"
    )
    static let openAIAPIKeyNotConfigured = localized(
        english: "API key required",
        korean: "API 키 필요",
        japanese: "APIキーが必要",
        chineseSimplified: "需要 API key"
    )
    static let openAIAPIKeyMissing = localized(
        english: "Add an OpenAI API key in Settings before using OpenAI Translation.",
        korean: "OpenAI 번역을 사용하려면 설정에서 OpenAI API 키를 먼저 입력하세요."
    )
    static let geminiAPIKey = localized(english: "Gemini API Key", korean: "Gemini API 키")
    static let geminiAPIKeyDescription = localized(
        english: "AirTranslate stores this key in macOS Keychain and uses it only for the selected Gemini Live mode.",
        korean: "AirTranslate는 이 키를 macOS Keychain에 저장하고 선택한 Gemini Live 모드에서만 사용합니다.",
        japanese: "AirTranslateはこのキーをmacOS Keychainに保存し、選択したGemini Liveモードでのみ使用します。",
        chineseSimplified: "AirTranslate 会将此密钥存储在 macOS Keychain 中，并且仅在所选 Gemini Live 模式下使用。"
    )
    static let geminiAPIKeySaved = localized(
        english: "Gemini API key saved in Keychain.",
        korean: "Gemini API 키가 Keychain에 저장되었습니다."
    )
    static let geminiAPIKeyRemoved = localized(
        english: "Gemini API key removed.",
        korean: "Gemini API 키가 삭제되었습니다."
    )
    static let geminiAPIKeyConfigured = localized(
        english: "Gemini API key saved",
        korean: "Gemini API 키 저장됨",
        japanese: "Gemini APIキー保存済み",
        chineseSimplified: "Gemini API key 已保存"
    )
    static let geminiAPIKeyNotConfigured = localized(
        english: "Gemini API key required",
        korean: "Gemini API 키 필요",
        japanese: "Gemini APIキーが必要",
        chineseSimplified: "需要 Gemini API key"
    )
    static let geminiAPIKeyMissing = localized(
        english: "Add a Gemini API key in Settings before using Gemini Live.",
        korean: "Gemini Live를 사용하려면 설정에서 Gemini API 키를 먼저 입력하세요.",
        japanese: "Gemini Liveを使用する前に、設定でGemini APIキーを追加してください。",
        chineseSimplified: "使用 Gemini Live 前，请先在设置中添加 Gemini API key。"
    )
    static let metaAPIKey = localized(
        english: "Meta Model API Key",
        korean: "Meta Model API 키",
        japanese: "Meta Model APIキー",
        chineseSimplified: "Meta Model API Key"
    )
    static let metaAPIKeyDescription = localized(
        english: "AirTranslate stores this key in macOS Keychain and uses it only for Meta Scribe.",
        korean: "AirTranslate는 이 키를 macOS Keychain에 저장하고 Meta 스크라이브에만 사용합니다.",
        japanese: "AirTranslateはこのキーをmacOS Keychainに保存し、Meta Scribeでのみ使用します。",
        chineseSimplified: "AirTranslate 会将此密钥存储在 macOS Keychain 中，并且仅用于 Meta Scribe。"
    )
    static let replaceSavedMetaAPIKeyDescription = localized(
        english: "A Meta Model key is saved in macOS Keychain. Enter and save a new key to replace it.",
        korean: "Meta Model 키가 macOS Keychain에 저장되어 있습니다. 새 키를 입력하고 저장하면 교체됩니다.",
        japanese: "Meta ModelキーはmacOS Keychainに保存済みです。新しいキーを入力して保存すると置き換えます。",
        chineseSimplified: "Meta Model 密钥已保存在 macOS Keychain 中。输入并保存新密钥即可替换。"
    )
    static let metaAPIKeySaved = localized(
        english: "Meta Model API key saved in Keychain.",
        korean: "Meta Model API 키가 Keychain에 저장되었습니다.",
        japanese: "Meta Model APIキーをKeychainに保存しました。",
        chineseSimplified: "Meta Model API key 已保存到 Keychain。"
    )
    static let metaAPIKeyRemoved = localized(
        english: "Meta Model API key removed.",
        korean: "Meta Model API 키가 삭제되었습니다.",
        japanese: "Meta Model APIキーを削除しました。",
        chineseSimplified: "Meta Model API key 已删除。"
    )
    static let metaAPIKeyConfigured = localized(
        english: "Meta Model API key saved",
        korean: "Meta Model API 키 저장됨",
        japanese: "Meta Model APIキー保存済み",
        chineseSimplified: "Meta Model API key 已保存"
    )
    static let metaAPIKeyNotConfigured = localized(
        english: "Meta Model API key required",
        korean: "Meta Model API 키 필요",
        japanese: "Meta Model APIキーが必要",
        chineseSimplified: "需要 Meta Model API key"
    )
    static let metaAPIKeyMissing = localized(
        english: "Add a Meta Model API key in Settings before using Meta Scribe.",
        korean: "Meta 스크라이브를 사용하려면 설정에서 Meta Model API 키를 먼저 입력하세요.",
        japanese: "Meta Scribeを使用する前に、設定でMeta Model APIキーを追加してください。",
        chineseSimplified: "使用 Meta Scribe 前，请先在设置中添加 Meta Model API key。"
    )
    static let startBlockedLocalAssetsChecking = localized(
        english: "Still checking local language assets. Try again in a moment.",
        korean: "로컬 언어 자산을 아직 확인하는 중입니다. 잠시 후 다시 시작하세요."
    )
    static let startBlockedLocalAssetsDownloadRequired = localized(
        english: "Download the required language assets before starting.",
        korean: "시작하기 전에 필요한 언어 자산을 다운로드하세요."
    )
    static func startBlockedLocalAssetsUnavailable(_ detail: String) -> String {
        localized(
            english: "Required language assets are unavailable: \(detail)",
            korean: "필요한 언어 자산을 사용할 수 없습니다: \(detail)"
        )
    }
    static let openAIAPIKeyRequiredForGPTMode = localized(
        english: "Enter an OpenAI API key to use GPT translation or GPT transcription.",
        korean: "GPT 번역 또는 GPT 전사를 사용하려면 OpenAI API 키를 입력하세요.",
        japanese: "GPT翻訳またはGPT文字起こしを使うにはOpenAI APIキーを入力してください。",
        chineseSimplified: "要使用 GPT 翻译或 GPT 转写，请输入 OpenAI API key。"
    )
    static let openAIAPIKeyEmpty = localized(
        english: "Enter an OpenAI API key before saving.",
        korean: "저장하기 전에 OpenAI API 키를 입력하세요."
    )
    static let openAIAPIKeyInvalidStoredValue = localized(
        english: "The stored OpenAI API key could not be read.",
        korean: "저장된 OpenAI API 키를 읽을 수 없습니다."
    )
    static let geminiAPIKeyEmpty = localized(
        english: "Enter a Gemini API key before saving.",
        korean: "저장하기 전에 Gemini API 키를 입력하세요."
    )
    static let geminiAPIKeyInvalidStoredValue = localized(
        english: "The stored Gemini API key could not be read.",
        korean: "저장된 Gemini API 키를 읽을 수 없습니다."
    )
    static let metaAPIKeyEmpty = localized(
        english: "Enter a Meta Model API key before saving.",
        korean: "저장하기 전에 Meta Model API 키를 입력하세요.",
        japanese: "保存する前にMeta Model APIキーを入力してください。",
        chineseSimplified: "保存前请输入 Meta Model API key。"
    )
    static let metaAPIKeyInvalidStoredValue = localized(
        english: "The stored Meta Model API key could not be read.",
        korean: "저장된 Meta Model API 키를 읽을 수 없습니다.",
        japanese: "保存されたMeta Model APIキーを読み取れませんでした。",
        chineseSimplified: "无法读取已保存的 Meta Model API key。"
    )
    static let appleProcessingMode = localized(english: "Apple Mode", korean: "Apple 기본 모드", japanese: "Apple標準モード", chineseSimplified: "Apple 默认模式")
    static let appleProcessingModeDescription = localized(
        english: "The default local workflow. Keep this as the base, then add OpenAI Realtime below only when needed.",
        korean: "기본 로컬 처리 흐름입니다. 이 설정을 기준으로 두고, 필요한 경우 아래 OpenAI Realtime만 추가하세요."
    )
    static let gptModels = localized(english: "OpenAI Realtime", korean: "OpenAI Realtime", japanese: "OpenAI Realtime", chineseSimplified: "OpenAI Realtime")
    static let geminiModels = localized(
        english: "Gemini Live",
        korean: "Gemini Live",
        japanese: "Gemini Live",
        chineseSimplified: "Gemini Live"
    )
    static let metaScribe = localized(
        english: "Meta Scribe",
        korean: "Meta 스크라이브",
        japanese: "Meta Scribe",
        chineseSimplified: "Meta Scribe"
    )
    static let metaScribeDetail = localized(
        english: "Muse Voice Transcribe · realtime transcription with speaker labels, 25 languages with code-switching",
        korean: "Muse Voice Transcribe · 화자 라벨과 코드 스위칭을 지원하는 25개 언어 실시간 전사",
        japanese: "Muse Voice Transcribe · 話者ラベルとコードスイッチング対応の25言語リアルタイム文字起こし",
        chineseSimplified: "Muse Voice Transcribe · 支持说话人标签与语码转换的 25 种语言实时转写"
    )
    static func speakerLabel(_ label: String) -> String {
        localized(
            english: "Speaker \(label)",
            korean: "화자 \(label)",
            japanese: "話者 \(label)",
            chineseSimplified: "说话人 \(label)"
        )
    }
    static let geminiTranslationModel = localized(
        english: "Gemini Live Model",
        korean: "Gemini Live 모델",
        japanese: "Gemini Liveモデル",
        chineseSimplified: "Gemini Live 模型"
    )
    static let gptTranscriptionModel = localized(
        english: "Transcription",
        korean: "전사",
        japanese: "文字起こし",
        chineseSimplified: "转写"
    )
    static let gptTranscriptionMode = localized(
        english: "GPT Transcription",
        korean: "GPT 전사",
        japanese: "GPT文字起こし",
        chineseSimplified: "GPT 转写"
    )
    static let gptTranscriptionModeDescription = localized(
        english: "Streams 24 kHz audio to gpt-live-transcribe for source-language captions only.",
        korean: "24kHz 오디오를 gpt-live-transcribe로 전송해 원문 자막만 만듭니다.",
        japanese: "24 kHz音声をgpt-live-transcribeに送信し、原文字幕のみを作成します。",
        chineseSimplified: "将 24 kHz 音频传输至 gpt-live-transcribe，仅生成原文字幕。"
    )
    static let gptTranscriptionSourceOnly = localized(
        english: "Source transcription only",
        korean: "원문 전사만",
        japanese: "原文文字起こしのみ",
        chineseSimplified: "仅原文转写"
    )
    static let gptModelsDescription = localized(
        english: "GPT mode streams audio through OpenAI Realtime Translation and shows the returned translated stream.",
        korean: "GPT 모드는 오디오를 OpenAI Realtime Translation으로 스트리밍하고 반환된 실시간 번역 흐름을 표시합니다."
    )
    static let geminiModelsDescription = localized(
        english: "Gemini Live streams audio directly to Gemini and shows source-only or translated captions for the selected mode.",
        korean: "Gemini Live는 오디오를 Gemini로 직접 스트리밍하고 선택한 모드에 따라 원문 또는 번역 자막을 표시합니다.",
        japanese: "Gemini Liveは音声をGeminiへ直接ストリーミングし、選択したモードに応じて原文または翻訳字幕を表示します。",
        chineseSimplified: "Gemini Live 会将音频直接传输到 Gemini，并根据所选模式显示原文或翻译字幕。"
    )
    static let openAINativeOutput = localized(
        english: "OpenAI native output",
        korean: "OpenAI 본연의 출력",
        japanese: "OpenAIネイティブ出力",
        chineseSimplified: "OpenAI 原生输出"
    )
    static let openAINativeOutputDescription = localized(
        english: "Transcript cleanup is disabled in GPT mode so the realtime API output is shown as-is.",
        korean: "GPT 모드에서는 실시간 API 결과를 그대로 보여주도록 기록 다듬기를 사용하지 않습니다.",
        japanese: "GPTモードではリアルタイムAPIの出力をそのまま表示するため、記録の整形は使いません。",
        chineseSimplified: "GPT 模式会直接显示实时 API 输出，不使用记录润色。"
    )
    static let openAILanguageModeDescription = localized(
        english: "OpenAI detects the input language and translates it to your preferred language.",
        korean: "OpenAI가 입력 언어를 자동 감지하고 선호 언어로 번역합니다.",
        japanese: "OpenAIが入力言語を自動検出し、優先言語へ翻訳します。",
        chineseSimplified: "OpenAI 会自动检测输入语言并翻译为首选语言。"
    )
    static let appleAutoLanguageModeDescription = localized(
        english: "Apple Speech listens with installed supported language models and translates from the detected source language.",
        korean: "Apple Speech가 설치된 지원 언어 모델로 듣고 감지된 원문 언어에서 번역합니다.",
        japanese: "Apple Speechがインストール済みの対応言語モデルで聞き取り、検出した原文言語から翻訳します。",
        chineseSimplified: "Apple Speech 会使用已安装的受支持语言模型收听，并从检测到的原文语言翻译。"
    )
    static let appleAutoLanguageModeUnavailableDescription = localized(
        english: "Auto-detect input is temporarily disabled and will be improved in a future update.",
        korean: "입력 언어 자동 감지는 잠시 비활성화되어 있으며 추후 업데이트에서 개선될 예정입니다.",
        japanese: "入力言語の自動検出は一時的に無効化されており、今後のアップデートで改善予定です。",
        chineseSimplified: "输入语言自动检测已暂时停用，将在后续更新中改进。"
    )
    static let appleAutoLanguageModeUnavailableToast = localized(
        english: "Auto-detect input will be improved in a future update.",
        korean: "입력 언어 자동 감지는 추후 업데이트에서 개선될 예정입니다.",
        japanese: "入力言語の自動検出は今後のアップデートで改善予定です。",
        chineseSimplified: "输入语言自动检测将在后续更新中改进。"
    )
    static let translatedVoiceOutput = localized(
        english: "GPT translated voice",
        korean: "GPT 번역 음성",
        japanese: "翻訳音声",
        chineseSimplified: "译文语音"
    )
    static let translatedVoiceOutputDescription = localized(
        english: "Play OpenAI's translated audio stream directly.",
        korean: "OpenAI 번역 음성 스트림을 직접 재생합니다.",
        japanese: "OpenAIの翻訳音声ストリームを直接再生します。",
        chineseSimplified: "直接播放 OpenAI 翻译语音流。"
    )
    static let openAIAPIKeyPlatformPrompt = localized(
        english: "No API key yet?",
        korean: "API 키가 없다면",
        japanese: "APIキーがない場合",
        chineseSimplified: "还没有 API key？"
    )
    static let openAIAPIKeyPlatformLink = localized(
        english: "Open OpenAI API Platform",
        korean: "OpenAI API 플랫폼 열기",
        japanese: "OpenAI API Platformを開く",
        chineseSimplified: "打开 OpenAI API 平台"
    )
    static let geminiAPIKeyPlatformPrompt = localized(
        english: "Need a key?",
        korean: "키가 필요하신가요?",
        japanese: "キーが必要ですか？",
        chineseSimplified: "需要 key 吗？"
    )
    static let geminiAPIKeyPlatformLink = localized(
        english: "Open Google AI Studio",
        korean: "Google AI Studio 열기",
        japanese: "Google AI Studioを開く",
        chineseSimplified: "打开 Google AI Studio"
    )
    static let metaAPIKeyPlatformPrompt = localized(
        english: "Need a key?",
        korean: "키가 필요하신가요?",
        japanese: "キーが必要ですか？",
        chineseSimplified: "需要 key 吗？"
    )
    static let metaAPIKeyPlatformLink = localized(
        english: "Open Meta Developer Dashboard",
        korean: "Meta 개발자 대시보드 열기",
        japanese: "Meta開発者ダッシュボードを開く",
        chineseSimplified: "打开 Meta 开发者控制台"
    )
    static let openAIRealtimeTranslationOnlySource = localized(
        english: "OpenAI realtime translation",
        korean: "OpenAI 실시간 번역"
    )
    static let geminiLiveTranslationSource = localized(
        english: "Gemini Live input audio",
        korean: "Gemini Live 입력 오디오"
    )
    static let output = localized(english: "Output", korean: "출력", japanese: "出力", chineseSimplified: "输出")
    static let outputMode = localized(english: "Output Mode", korean: "출력 모드", japanese: "出力モード", chineseSimplified: "输出模式")
    static let transcribeOnly = localized(
        english: "Transcribe Only",
        korean: "전사만",
        japanese: "文字起こしのみ",
        chineseSimplified: "仅转写"
    )
    static let transcriptionSettings = localized(
        english: "Transcription Settings",
        korean: "전사 설정",
        japanese: "文字起こし設定",
        chineseSimplified: "转写设置"
    )
    static let translationSettings = localized(english: "Translation Settings", korean: "번역 설정", japanese: "翻訳設定", chineseSimplified: "翻译设置")
    static let configureTranslationSettings = localized(
        english: "Configure Translation Settings",
        korean: "번역 설정 구성"
    )
    static let transcript = localized(english: "Transcript", korean: "기록", japanese: "記録", chineseSimplified: "记录")
    static let liveOutput = localized(english: "Live Output", korean: "실시간 출력", japanese: "リアルタイム出力", chineseSimplified: "实时输出")
    static let liveTranslation = localized(
        english: "LIVE Translation",
        korean: "LIVE 번역",
        japanese: "LIVE翻訳",
        chineseSimplified: "LIVE 翻译"
    )
    static let library = localized(english: "Library", korean: "저장소", japanese: "ライブラリ", chineseSimplified: "资料库")
    static let dubbing = localized(english: "Dubbing", korean: "더빙", japanese: "音声出力", chineseSimplified: "配音")
    static let voiceOutput = localized(english: "Voice Output", korean: "음성 출력", japanese: "音声出力", chineseSimplified: "语音输出")
    static let menuBarTitle = localized(english: "Captions", korean: "자막")
    static let menuBarRunningTitle = localized(english: "Live", korean: "기록 중")
    static let menuBarPausedTitle = localized(english: "Paused", korean: "일시정지")
    static let floatingCaptions = localized(english: "Floating Captions", korean: "플로팅 자막")
    static let showFloatingCaptions = localized(
        english: "Show Floating Captions",
        korean: "플로팅 자막 보기",
        japanese: "フローティング字幕を表示",
        chineseSimplified: "显示悬浮字幕"
    )
    static let floatingCaptionPowerOn = localized(english: "ON", korean: "켜짐")
    static let floatingCaptionPowerOff = localized(english: "OFF", korean: "꺼짐")
    static let captionsWindow = localized(english: "Caption Window", korean: "자막 창")
    static let hideFloatingCaptions = localized(
        english: "Hide Floating Captions",
        korean: "플로팅 자막 숨기기",
        japanese: "フローティング字幕を隠す",
        chineseSimplified: "隐藏悬浮字幕"
    )
    static let openMainWindow = localized(english: "Open Main Window", korean: "메인 창 열기")
    static let openAirTranslate = localized(
        english: "Open AirTranslate",
        korean: "AirTranslate 열기",
        japanese: "AirTranslateを開く",
        chineseSimplified: "打开 AirTranslate"
    )
    static let mainWindow = localized(
        english: "Main window",
        korean: "메인 윈도우",
        japanese: "メインウインドウ",
        chineseSimplified: "主窗口"
    )
    static let selected = localized(
        english: "Selected",
        korean: "선택됨",
        japanese: "選択中",
        chineseSimplified: "已选择"
    )
    static let captionStyle = localized(
        english: "Caption Style",
        korean: "자막 스타일",
        japanese: "字幕スタイル",
        chineseSimplified: "字幕样式"
    )
    static let size = localized(
        english: "Size",
        korean: "크기",
        japanese: "サイズ",
        chineseSimplified: "大小"
    )
    static let lines = localized(
        english: "Lines",
        korean: "줄 수",
        japanese: "行数",
        chineseSimplified: "行数"
    )
    static let stability = localized(
        english: "Stability",
        korean: "안정화",
        japanese: "安定化",
        chineseSimplified: "稳定"
    )
    static let settings = localized(
        english: "Settings",
        korean: "설정",
        japanese: "設定",
        chineseSimplified: "设置"
    )
    static let openSettings = localized(
        english: "Open Settings",
        korean: "설정 열기",
        japanese: "設定を開く",
        chineseSimplified: "打开设置"
    )
    static let quit = localized(
        english: "Quit",
        korean: "종료",
        japanese: "終了",
        chineseSimplified: "退出"
    )
    static let quitAirTranslate = localized(
        english: "Quit AirTranslate",
        korean: "AirTranslate 종료",
        japanese: "AirTranslateを終了",
        chineseSimplified: "退出 AirTranslate"
    )
    static let both = localized(
        english: "Both",
        korean: "원문+번역",
        japanese: "両方",
        chineseSimplified: "两者"
    )
    static let floatingDisplay = localized(english: "Floating Display", korean: "플로팅 표시")
    static let floatingDisplayDescription = localized(
        english: "Choose what appears in the detachable floating caption window.",
        korean: "따로 띄우는 플로팅 자막 창에 표시할 내용을 선택합니다."
    )
    static let floatingTextSize = localized(english: "Floating Text Size", korean: "플로팅 글자 크기")
    static let floatingCustomTextSize = localized(
        english: "Custom Text Size",
        korean: "사용자 지정 글자 크기",
        japanese: "カスタム文字サイズ",
        chineseSimplified: "自定义文字大小"
    )
    static let floatingColorCode = localized(
        english: "color code", korean: "색상 코드", japanese: "カラーコード", chineseSimplified: "颜色代码"
    )
    static let applyFloatingColor = localized(
        english: "Apply", korean: "적용", japanese: "適用", chineseSimplified: "应用"
    )
    static let floatingTextColor = localized(
        english: "Caption Text Color",
        korean: "자막 글자 색상",
        japanese: "字幕テキストカラー",
        chineseSimplified: "字幕文字颜色"
    )
    static let floatingBackgroundColor = localized(
        english: "Caption Background Color",
        korean: "자막 배경 색상",
        japanese: "字幕背景カラー",
        chineseSimplified: "字幕背景颜色"
    )
    static let floatingBackgroundOpacity = localized(
        english: "Background Opacity",
        korean: "배경 불투명도",
        japanese: "背景の不透明度",
        chineseSimplified: "背景不透明度"
    )
    static let resetFloatingCaptionAppearance = localized(
        english: "Reset Appearance",
        korean: "외형 초기화",
        japanese: "外観をリセット",
        chineseSimplified: "重置外观"
    )
    static let resetFloatingCaptionSize = localized(
        english: "Reset Window Size",
        korean: "창 크기 초기화",
        japanese: "ウインドウサイズをリセット",
        chineseSimplified: "重置窗口大小"
    )
    static let floatingCaptionDragHandle = localized(
        english: "Floating caption drag handle",
        korean: "플로팅 자막 드래그 핸들",
        japanese: "フローティング字幕ドラッグハンドル",
        chineseSimplified: "悬浮字幕拖动手柄"
    )
    static let floatingCaptionResizeHandle = localized(
        english: "Floating caption resize handle",
        korean: "플로팅 자막 크기 조절 핸들",
        japanese: "フローティング字幕リサイズハンドル",
        chineseSimplified: "悬浮字幕大小调整手柄"
    )
    static let floatingLineCount = localized(english: "Floating Lines", korean: "플로팅 표시 줄 수")
    static let originalOnly = localized(english: "Original", korean: "원문", japanese: "原文", chineseSimplified: "原文")
    static let originalAndTranslation = localized(english: "Original + Translation", korean: "원문 + 번역", japanese: "原文 + 翻訳", chineseSimplified: "原文 + 译文")
    static let translationOnly = localized(english: "Translation", korean: "번역", japanese: "翻訳", chineseSimplified: "译文")
    static let textSizeSmall = localized(english: "Small", korean: "작게", japanese: "小", chineseSimplified: "小")
    static let textSizeMedium = localized(english: "Medium", korean: "보통", japanese: "中", chineseSimplified: "中")
    static let textSizeLarge = localized(english: "Large", korean: "크게", japanese: "大", chineseSimplified: "大")
    static let textSizeExtraLarge = localized(english: "Extra Large", korean: "아주 크게", japanese: "特大", chineseSimplified: "特大")
    static let captionStability = localized(english: "Caption Stability", korean: "자막 안정화", japanese: "字幕の安定化", chineseSimplified: "字幕稳定")
    static let captionStabilityDescription = localized(
        english: "Holds already-shown captions longer before a rewrite replaces them. Steadier settings shake less but react a little later.",
        korean: "이미 보인 자막을 재작성으로 바꾸기 전에 더 오래 유지합니다. 안정 쪽일수록 덜 흔들리지만 반응이 조금 늦어집니다.",
        japanese: "表示済みの字幕を書き換えで置き換える前に、より長く保持します。安定側ほど揺れが減り、反応は少し遅くなります。",
        chineseSimplified: "在重写替换之前更长时间地保留已显示的字幕。越稳定抖动越少，但反应会稍慢。"
    )
    static let captionStabilityResponsive = localized(english: "Responsive", korean: "빠름", japanese: "即応", chineseSimplified: "灵敏")
    static let captionStabilityBalanced = localized(english: "Balanced", korean: "기본", japanese: "標準", chineseSimplified: "均衡")
    static let captionStabilitySteady = localized(english: "Steady", korean: "안정", japanese: "安定", chineseSimplified: "稳定")
    static let captionAlignment = localized(english: "Caption Alignment", korean: "자막 정렬", japanese: "字幕の配置", chineseSimplified: "字幕对齐")
    static let captionAlignmentDescription = localized(
        english: "Left alignment keeps the start of each line fixed while words stream in, so lines do not slide sideways.",
        korean: "왼쪽 정렬은 단어가 추가될 때 줄의 시작점이 고정되어 자막이 좌우로 밀리지 않습니다.",
        japanese: "左揃えでは単語が追加されても行の開始位置が固定され、字幕が左右にずれません。",
        chineseSimplified: "左对齐时，逐词出现的字幕行起点保持固定，不会左右滑动。"
    )
    static let captionAlignmentCenter = localized(english: "Center", korean: "가운데", japanese: "中央", chineseSimplified: "居中")
    static let captionAlignmentLeading = localized(english: "Left", korean: "왼쪽", japanese: "左", chineseSimplified: "左")
    static let noFloatingCaptionsYet = localized(
        english: "Live captions will appear here.",
        korean: "실시간 자막이 여기에 표시됩니다."
    )
    static let transcriptLint = localized(english: "Transcript Word Lint", korean: "기록 단어 다듬기", japanese: "記録単語の補正", chineseSimplified: "记录词语修正")
    static let transcriptPolish = localized(english: "Transcript Polish", korean: "기록 다듬기", japanese: "記録を整える", chineseSimplified: "整理记录")
    static let transcriptLintDescription = localized(
        english: "During silence, conservatively fixes transcription words when macOS spelling suggestions are confident. It does not remove repeated sentences or transcript content.",
        korean: "침묵 시간에 macOS 맞춤법 후보가 확실한 기록 단어만 보수적으로 고칩니다. 반복 문장이나 기록 내용은 제거하지 않습니다."
    )
    static let paragraphBreakSilenceInterval = localized(
        english: "Paragraph Break Silence",
        korean: "문단 개행 숨고르기"
    )
    static let paragraphBreakSilenceDescription = localized(
        english: "When speech resumes after this much silence, the transcript starts a new paragraph.",
        korean: "이 시간만큼 말이 멈춘 뒤 다시 시작되면 기록을 새 문단으로 나눕니다."
    )
    static let sessionLength = localized(english: "Session Length", korean: "세션 길이", japanese: "セッション長", chineseSimplified: "会话时长")
    static let sessionLengthStandard = localized(english: "Standard", korean: "일반", japanese: "標準", chineseSimplified: "标准")
    static let sessionLengthThirtyMinutesOrMore = localized(english: "30+ minutes", korean: "30분 이상", japanese: "30分以上", chineseSimplified: "30 分钟以上")
    static let sessionLengthStandardDescription = localized(
        english: "Keeps live updates as immediate as possible for short sessions.",
        korean: "짧은 세션에서 실시간 반응성을 최대한 유지합니다."
    )
    static let sessionLengthThirtyMinutesOrMoreDescription = localized(
        english: "Uses long-session safeguards: less frequent full-text UI updates, delayed translation bursts, and tail rendering for very long transcripts.",
        korean: "긴 세션 보호 모드를 사용합니다. 전체 텍스트 화면 갱신과 번역 폭주를 줄이고, 아주 긴 기록은 최근 부분만 렌더링합니다."
    )
    static let savedTranscripts = localized(english: "Saved Transcripts", korean: "저장된 기록", japanese: "保存済み記録", chineseSimplified: "已保存记录")
    static let transcriptPersistence = localized(
        english: "Save Transcript Files",
        korean: "기록 파일 저장",
        japanese: "記録ファイルを保存",
        chineseSimplified: "保存记录文件"
    )
    static let transcriptPersistenceDescription = localized(
        english: "When on, transcript text is saved as dated plain .txt files when capture stops or the app quits. When off, it stays in memory only.",
        korean: "켜면 캡처 중지 또는 앱 종료 시 기록을 날짜가 붙은 일반 .txt 파일로 저장합니다. 끄면 메모리에만 유지됩니다.",
        japanese: "オンにすると、キャプチャ停止時またはアプリ終了時に記録を日付付きのプレーンな .txt ファイルとして保存します。オフの場合はメモリ上だけに保持します。",
        chineseSimplified: "开启后，停止采集或退出应用时会将记录保存为带日期的纯文本 .txt 文件。关闭后仅保留在内存中。"
    )
    static let savedTranscriptContent = localized(
        english: "Saved Content",
        korean: "저장 내용"
    )
    static let autoSave = localized(english: "Auto-save", korean: "자동 저장")
    static let autoSaveDescription = localized(
        english: "Choose which transcript text to save when transcript file saving is enabled.",
        korean: "기록 파일 저장을 켰을 때 어떤 기록 텍스트를 저장할지 선택합니다."
    )
    static let openSaveFolder = localized(
        english: "Open Save Folder",
        korean: "저장 폴더 열기"
    )
    static let openLibrary = localized(
        english: "Open Library",
        korean: "저장소 열기"
    )
    static let manageSavedTranscripts = localized(
        english: "Manage Saved Transcripts",
        korean: "저장된 기록 관리",
        japanese: "保存済み記録を管理",
        chineseSimplified: "管理已保存记录"
    )
    static let librarySummary = localized(
        english: "Review, edit, delete, or open saved transcript files in a focused library window.",
        korean: "저장된 기록 확인, 수정, 삭제, 폴더 열기는 별도 관리 창에서 처리합니다."
    )
    static let savedEmpty = localized(
        english: "Saved transcript files will appear here when file saving is enabled.",
        korean: "기록 파일 저장을 켜면 저장된 기록이 여기에 표시됩니다."
    )
    static let noSavedTranscriptSelected = localized(
        english: "Select a saved transcript.",
        korean: "저장된 기록을 선택하세요."
    )
    static let deleteAllSavedTranscripts = localized(
        english: "Delete All",
        korean: "모두 지우기"
    )
    static let deleteAllSavedTranscriptsConfirmation = localized(
        english: "Delete all saved transcript files? This cannot be undone.",
        korean: "저장된 기록 파일을 모두 지울까요? 이 작업은 되돌릴 수 없습니다."
    )
    static let deleteAllSavedTranscriptsHelp = localized(
        english: "Delete every saved transcript file.",
        korean: "저장된 모든 기록 파일을 삭제합니다."
    )
    static let editSaved = localized(english: "Edit Saved", korean: "저장본 편집")
    static let title = localized(english: "Title", korean: "제목")
    static let original = localized(english: "Original", korean: "원문")
    static let originalDescription = localized(
        english: "Incoming speech with live paragraph cleanup.",
        korean: "들어오는 음성을 실시간 문단 정리와 함께 보여줍니다."
    )
    static let transcriptText = localized(english: "Transcript Text", korean: "기록 텍스트")
    static let deleteSavedTranscript = localized(english: "Delete Transcript", korean: "기록 삭제")
    static let deleteSavedTranscriptConfirmation = localized(
        english: "Delete this saved transcript? This cannot be undone.",
        korean: "이 저장 기록을 삭제할까요? 이 작업은 되돌릴 수 없습니다.",
        japanese: "この保存済み文字起こしを削除しますか？この操作は取り消せません。",
        chineseSimplified: "要删除这份已保存的转写记录吗？此操作无法撤销。"
    )
    static let translation = localized(english: "Translation", korean: "번역")
    static let translationDescription = localized(
        english: "Translated output aligned to the same transcript flow.",
        korean: "같은 기록 흐름에 맞춰 번역 결과를 정렬해 보여줍니다."
    )
    static let saveEdits = localized(english: "Save Edits", korean: "수정 저장")
    static let liveCaptions = localized(english: "Live Captions", korean: "실시간 기록")
    static let transcriptWorkspace = localized(english: "Transcript Workspace", korean: "실시간 기록")
    static let delete = localized(english: "Delete", korean: "삭제")
    static let waitingForTranscript = localized(
        english: "Captions will appear here.",
        korean: "기록이 시작되면 여기에 표시됩니다."
    )
    static let transcriptSavedToast = localized(
        english: "Transcript saved",
        korean: "기록이 저장되었습니다"
    )
    static let copy = localized(english: "Copy", korean: "복사")
    static let copied = localized(english: "Copied", korean: "복사됨")
    static let appleIntelligenceWritingTools = localized(
        english: "Apple Intelligence Writing Tools",
        korean: "Apple Intelligence 글쓰기 도구"
    )
    static let foundationModelCleanup = localized(
        english: "Clean with Foundation Model",
        korean: "Foundation Model로 전체 정리"
    )
    static let foundationModelCleanupShort = localized(
        english: "Foundation Clean",
        korean: "Foundation 정리"
    )
    static let foundationModelCleanupHelp = localized(
        english: "Use Apple's on-device Foundation Model to clean the selected saved transcript draft. Review the result, then save edits.",
        korean: "Apple 온디바이스 Foundation Model로 선택한 저장 기록 draft 전체를 정리합니다. 결과를 확인한 뒤 수정 저장하세요."
    )
    static let foundationModelCleanupRunning = localized(
        english: "Cleaning transcript with Foundation Model...",
        korean: "Foundation Model로 기록 정리 중..."
    )
    static let foundationModelCleanupComplete = localized(
        english: "Foundation Model cleanup complete. Review and save edits.",
        korean: "Foundation Model 정리가 완료되었습니다. 확인 후 수정 저장하세요."
    )
    static func foundationModelCleanupFailed(_ reason: String) -> String {
        localized(
            english: "Foundation Model cleanup failed: \(reason)",
            korean: "Foundation Model 정리 실패: \(reason)"
        )
    }
    static let foundationModelCleanupFrameworkUnavailable = localized(
        english: "Foundation Models is not available in this build.",
        korean: "이 빌드에서는 Foundation Models를 사용할 수 없습니다."
    )
    static func foundationModelCleanupUnavailable(_ reason: String) -> String {
        localized(
            english: "Foundation Model is unavailable: \(reason)",
            korean: "Foundation Model을 사용할 수 없습니다: \(reason)"
        )
    }
    static func copyTranscriptPane(_ title: String) -> String {
        localized(english: "Copy \(title)", korean: "\(title) 복사")
    }
    static let listening = localized(english: "Listening", korean: "듣는 중")
    static let idle = localized(english: "Idle", korean: "대기")
    static let noCaptionsYet = localized(english: "No captions yet", korean: "아직 기록 없음")
    static let noCaptionsDescription = localized(
        english: "Start capture, play audio on this Mac, and grant Screen Recording, System Audio Recording, and Speech permissions.",
        korean: "캡처를 시작하고 이 Mac에서 오디오를 재생한 뒤 화면 기록, 시스템 오디오 녹음, 음성 인식 권한을 허용하세요."
    )
    static func gptTranscriptionNoCaptionsDescription(for source: AudioInputSource) -> String {
        switch source {
        case .systemAudio:
            localized(
                english: "Start capture, play audio on this Mac, and grant Screen Recording and System Audio Recording permissions.",
                korean: "캡처를 시작하고 이 Mac에서 오디오를 재생한 뒤 화면 기록과 시스템 오디오 녹음 권한을 허용하세요.",
                japanese: "キャプチャを開始してMacで音声を再生し、画面収録とシステムオーディオ収録を許可してください。",
                chineseSimplified: "开始捕获并在这台 Mac 上播放音频，然后允许屏幕录制和系统音频录制。"
            )
        case .microphone:
            localized(
                english: "Start capture and grant Microphone access when macOS asks.",
                korean: "캡처를 시작하고 macOS가 요청하면 마이크 접근을 허용하세요.",
                japanese: "キャプチャを開始し、macOSから求められたらマイクへのアクセスを許可してください。",
                chineseSimplified: "开始捕获，并在 macOS 提示时允许麦克风访问。"
            )
        }
    }
    static let openPrivacySettings = localized(
        english: "Open Privacy Settings",
        korean: "개인정보 보호 설정 열기"
    )
    static let openAPIKeySettings = localized(
        english: "Open API Key Settings",
        korean: "API 키 설정 열기",
        japanese: "APIキー設定を開く",
        chineseSimplified: "打开 API key 设置"
    )
    static let retry = localized(
        english: "Retry",
        korean: "다시 시도",
        japanese: "再試行",
        chineseSimplified: "重试"
    )
    static let dismiss = localized(
        english: "Dismiss",
        korean: "닫기",
        japanese: "閉じる",
        chineseSimplified: "关闭"
    )
    static let dismissStartFailure = localized(
        english: "Dismiss start failure",
        korean: "시작 실패 안내 닫기",
        japanese: "開始失敗の案内を閉じる",
        chineseSimplified: "关闭启动失败提示"
    )
    static let permissions = localized(english: "Permissions", korean: "권한")
    static let permissionsHelp = localized(
        english: "AirTranslate needs Screen Recording, System Audio Recording, and Speech Recognition permission. After changing privacy settings, quit and relaunch the app.",
        korean: "AirTranslate에는 화면 기록, 시스템 오디오 녹음, 음성 인식 권한이 필요합니다. 개인정보 보호 설정을 변경한 뒤 앱을 종료하고 다시 실행하세요."
    )
    static let checkingScreenPermission = localized(
        english: "Checking screen recording permission...",
        korean: "화면 기록 권한 확인 중..."
    )
    static let checkingMicrophonePermission = localized(
        english: "Checking microphone permission...",
        korean: "마이크 권한 확인 중..."
    )
    static let checkingSpeechPermission = localized(
        english: "Checking speech recognition permission...",
        korean: "음성 인식 권한 확인 중..."
    )
    static let connectingGeminiLiveTranslation = localized(
        english: "Connecting to Gemini Live Translate...",
        korean: "Gemini 실시간 번역에 연결 중..."
    )
    static let connectingMetaScribe = localized(
        english: "Connecting to Meta Scribe...",
        korean: "Meta 스크라이브에 연결 중...",
        japanese: "Meta Scribeに接続中...",
        chineseSimplified: "正在连接 Meta Scribe..."
    )
    static let connectingGPTTranscription = localized(
        english: "Connecting to GPT transcription...",
        korean: "GPT 전사에 연결 중...",
        japanese: "GPT文字起こしに接続中...",
        chineseSimplified: "正在连接 GPT 转写..."
    )
    static func startingCapture(for source: AudioInputSource) -> String {
        switch source {
        case .systemAudio:
            localized(english: "Starting Mac audio capture...", korean: "Mac 오디오 캡처 시작 중...")
        case .microphone:
            localized(english: "Starting microphone capture...", korean: "마이크 캡처 시작 중...")
        }
    }
    static func listeningForSpeech(from source: AudioInputSource) -> String {
        switch source {
        case .systemAudio:
            localized(english: "Listening to Mac audio, waiting for speech...", korean: "Mac 오디오를 듣는 중, 음성을 기다리는 중...")
        case .microphone:
            localized(english: "Listening to microphone, waiting for speech...", korean: "마이크를 듣는 중, 음성을 기다리는 중...")
        }
    }
    static let translating = localized(english: "Translating...", korean: "번역 중...")
    static let translationDisabledForSpeechOnly = localized(
        english: "Translation is off in Transcribe Only mode.",
        korean: "전사만 모드에서는 번역이 꺼져 있습니다."
    )
    static let sameLanguageTranslationUnavailable = localized(
        english: "Choose different source and target languages to translate.",
        korean: "번역하려면 원문과 번역 언어를 다르게 선택하세요."
    )
    static let untitledTranscript = localized(english: "Untitled Transcript", korean: "제목 없는 기록")

    static func languageSummary(source: String, target: String) -> String {
        localized(english: "\(source) to \(target)", korean: "\(source) → \(target)")
    }

    static func transcribeLanguageSummary(source: String) -> String {
        localized(
            english: "Transcribe \(source)",
            korean: "\(source) 전사",
            japanese: "\(source) の文字起こし",
            chineseSimplified: "转写\(source)"
        )
    }

    static func openAILanguageSummary(target: String) -> String {
        localized(
            english: "Auto-detect to \(target)",
            korean: "자동 감지 → \(target)",
            japanese: "自動検出 → \(target)",
            chineseSimplified: "自动检测 → \(target)"
        )
    }

    static func autoDetectionLanguageChangePaused(current: String, detected: String) -> String {
        localized(
            english: "\(detected) detected after \(current). Waiting for confirmation.",
            korean: "\(current) 다음에 \(detected)이 감지되었습니다. 확인을 기다리는 중입니다.",
            japanese: "\(current)の後に\(detected)を検出しました。確認待ちです。",
            chineseSimplified: "在\(current)之后检测到\(detected)。正在等待确认。"
        )
    }

    static func autoDetectionLanguageChangeMessage(current: String, detected: String, target: String) -> String {
        localized(
            english: "AirTranslate was translating \(current) to \(target), then detected \(detected) after a pause. Start a new session to avoid mixing languages in the same transcript.",
            korean: "AirTranslate가 \(current)에서 \(target)으로 번역하던 중, 잠시 멈춘 뒤 \(detected)이 감지되었습니다. 같은 기록에 언어가 섞이지 않도록 새 세션으로 시작하세요.",
            japanese: "AirTranslateは\(current)から\(target)へ翻訳中でしたが、一時停止後に\(detected)を検出しました。同じ記録で言語が混ざらないよう、新しいセッションを開始してください。",
            chineseSimplified: "AirTranslate 原本正在将\(current)翻译为\(target)，暂停后检测到\(detected)。请开始新会话，避免同一记录中混合语言。"
        )
    }

    static func lineCount(_ count: Int) -> String {
        localized(english: "\(count) lines", korean: "\(count)줄")
    }

    static func seconds(_ seconds: Double) -> String {
        let value = seconds.rounded(.toNearestOrAwayFromZero) == seconds
            ? String(Int(seconds))
            : String(format: "%.1f", seconds)
        return localized(english: "\(value) sec", korean: "\(value)초")
    }

    static func speechModelAvailabilityDetail(source: String, status: String) -> String {
        localized(
            english: "Source: \(source). Local asset: \(status).",
            korean: "원문: \(source). 로컬 자산: \(status)."
        )
    }

    static func translationModelAvailabilityDetail(source: String, target: String, status: String) -> String {
        localized(
            english: "\(source) to \(target). Local asset: \(status).",
            korean: "\(source) → \(target). 로컬 자산: \(status)."
        )
    }

    static func combinedModelAvailabilityDetail(
        model: String,
        speechStatus: String,
        translationStatus: String
    ) -> String {
        localized(
            english: "Speech: \(speechStatus). Translation: \(translationStatus).",
            korean: "음성 인식: \(speechStatus). 번역: \(translationStatus)."
        )
    }

    static func openAIModelAvailabilityDetail(hasAPIKey: Bool) -> String {
        localized(
            english: hasAPIKey ? "OpenAI API key is saved in Keychain." : "Save an OpenAI API key in Settings.",
            korean: hasAPIKey ? "OpenAI API 키가 Keychain에 저장되어 있습니다." : "설정에서 OpenAI API 키를 저장하세요."
        )
    }

    static func openAITranslationInstructions(source: String, target: String) -> String {
        localized(
            english: "Translate from \(source) to \(target). Return only the translated text. Preserve paragraph breaks and line breaks.",
            korean: "\(source)에서 \(target)로 번역하세요. 번역문만 반환하고 문단과 줄바꿈은 유지하세요."
        )
    }

    static func openAIAPIKeychainFailed(_ status: OSStatus) -> String {
        localized(
            english: "Keychain operation failed: \(status).",
            korean: "Keychain 작업 실패: \(status)."
        )
    }

    static func geminiAPIKeychainFailed(_ status: OSStatus) -> String {
        localized(
            english: "Keychain operation failed: \(status).",
            korean: "Keychain 작업 실패: \(status)."
        )
    }

    static func metaAPIKeychainFailed(_ status: OSStatus) -> String {
        localized(
            english: "Keychain operation failed: \(status).",
            korean: "Keychain 작업 실패: \(status).",
            japanese: "Keychain操作に失敗しました: \(status)。",
            chineseSimplified: "Keychain 操作失败：\(status)。"
        )
    }

    static let openAIInvalidResponse = localized(
        english: "OpenAI returned an invalid response.",
        korean: "OpenAI가 올바르지 않은 응답을 반환했습니다."
    )
    static let openAIRealtimeConnectionFailed = localized(
        english: "OpenAI Realtime connection failed. Check your network and API key, then try again.",
        korean: "OpenAI Realtime 연결에 실패했습니다. 네트워크와 API 키를 확인한 뒤 다시 시도하세요.",
        japanese: "OpenAI Realtimeへの接続に失敗しました。ネットワークとAPIキーを確認して、もう一度お試しください。",
        chineseSimplified: "OpenAI Realtime 连接失败。请检查网络和 API key 后重试。"
    )
    static let openAIEmptyOutput = localized(
        english: "OpenAI returned no translated text.",
        korean: "OpenAI가 번역 텍스트를 반환하지 않았습니다."
    )

    static func openAIRequestFailed(statusCode: Int, message: String?) -> String {
        let detail = message.map { ": \($0)" } ?? ""
        return localized(
            english: "OpenAI request failed (\(statusCode))\(detail)",
            korean: "OpenAI 요청 실패(\(statusCode))\(detail)"
        )
    }

    static let geminiInvalidResponse = localized(
        english: "Gemini returned an invalid response.",
        korean: "Gemini가 올바르지 않은 응답을 반환했습니다."
    )
    static let geminiConnectionFailed = localized(
        english: "Gemini Live connection failed. Check your network and API key, then try again.",
        korean: "Gemini Live 연결에 실패했습니다. 네트워크와 API 키를 확인한 뒤 다시 시도하세요."
    )
    static let metaInvalidResponse = localized(
        english: "Meta Scribe returned an invalid response.",
        korean: "Meta 스크라이브가 올바르지 않은 응답을 반환했습니다.",
        japanese: "Meta Scribeから無効な応答が返されました。",
        chineseSimplified: "Meta Scribe 返回了无效响应。"
    )
    static let metaConnectionFailed = localized(
        english: "Meta Scribe connection failed. Check your network and API key, then try again.",
        korean: "Meta 스크라이브 연결에 실패했습니다. 네트워크와 API 키를 확인한 뒤 다시 시도하세요.",
        japanese: "Meta Scribeへの接続に失敗しました。ネットワークとAPIキーを確認してください。",
        chineseSimplified: "Meta Scribe 连接失败。请检查网络和 API key 后重试。"
    )
    static let metaRateLimited = localized(
        english: "Meta Scribe is rate limited. Wait a moment, then try again.",
        korean: "Meta 스크라이브 요청 한도에 도달했습니다. 잠시 후 다시 시도하세요.",
        japanese: "Meta Scribeの利用制限に達しました。しばらくしてから再試行してください。",
        chineseSimplified: "Meta Scribe 已达到速率限制。请稍后重试。"
    )
    static let metaInvalidRequest = localized(
        english: "Meta Scribe rejected the session configuration.",
        korean: "Meta 스크라이브가 세션 구성을 거부했습니다.",
        japanese: "Meta Scribeがセッション設定を拒否しました。",
        chineseSimplified: "Meta Scribe 拒绝了会话配置。"
    )

    static let translationCancelled = localized(
        english: "Translation cancelled.",
        korean: "번역이 취소되었습니다."
    )

    static func startFailed(_ message: String) -> String {
        localized(english: "Start failed: \(message)", korean: "시작 실패: \(message)")
    }

    static func saveLibraryFailed(_ message: String) -> String {
        localized(
            english: "Could not save transcript library: \(message)",
            korean: "기록 저장소를 저장할 수 없습니다: \(message)"
        )
    }

    static func receivingAudioWaiting(sampleCount: Int, source: AudioInputSource) -> String {
        switch source {
        case .systemAudio:
            localized(
                english: "Receiving Mac audio (\(sampleCount) samples), waiting for speech...",
                korean: "Mac 오디오 수신 중(\(sampleCount) 샘플), 음성을 기다리는 중..."
            )
        case .microphone:
            localized(
                english: "Receiving microphone audio (\(sampleCount) samples), waiting for speech...",
                korean: "마이크 오디오 수신 중(\(sampleCount) 샘플), 음성을 기다리는 중..."
            )
        }
    }

    static func receivingSilentAudio(sampleCount: Int, level: Int, source: AudioInputSource) -> String {
        switch source {
        case .systemAudio:
            localized(
                english: "Receiving silent audio (\(sampleCount) samples, \(level) dB). Check System Audio Recording.",
                korean: "무음 오디오 수신 중(\(sampleCount) 샘플, \(level) dB). 시스템 오디오 녹음 권한을 확인하세요."
            )
        case .microphone:
            localized(
                english: "Receiving quiet microphone audio (\(sampleCount) samples, \(level) dB). Check Microphone permission or input level.",
                korean: "마이크 무음에 가까운 오디오 수신 중(\(sampleCount) 샘플, \(level) dB). 마이크 권한 또는 입력 레벨을 확인하세요."
            )
        }
    }

    static func receivingAudioTranscribing(sampleCount: Int, level: Int, source: AudioInputSource) -> String {
        switch source {
        case .systemAudio:
            localized(
                english: "Receiving Mac audio (\(sampleCount) samples, \(level) dB), transcribing live...",
                korean: "Mac 오디오 수신 중(\(sampleCount) 샘플, \(level) dB), 실시간 기록 중..."
            )
        case .microphone:
            localized(
                english: "Receiving microphone audio (\(sampleCount) samples, \(level) dB), transcribing live...",
                korean: "마이크 오디오 수신 중(\(sampleCount) 샘플, \(level) dB), 실시간 기록 중..."
            )
        }
    }

    static func unsupportedTranslation(source: String, target: String) -> String {
        localized(
            english: "Apple Translation does not support \(source) to \(target).",
            korean: "Apple Translation은 \(source) → \(target) 번역을 지원하지 않습니다."
        )
    }

    static let speechPermissionDenied = localized(
        english: "Speech recognition permission was not granted.",
        korean: "음성 인식 권한이 허용되지 않았습니다."
    )
    static let recognizerUnavailable = localized(
        english: "The selected speech recognizer is unavailable.",
        korean: "선택한 음성 인식기를 사용할 수 없습니다."
    )
    static let screenRecordingNotGranted = localized(
        english: "macOS does not recognize Screen Recording access for this AirTranslate build. If it is already enabled, keep only the current app, toggle access once, then quit and relaunch AirTranslate.",
        korean: "macOS가 현재 AirTranslate 빌드의 화면 기록 권한을 인식하지 못합니다. 이미 허용했다면 현재 앱만 남기고 권한을 한 번 껐다 켠 뒤 AirTranslate를 종료하고 다시 실행하세요."
    )
    static let microphoneNotGranted = localized(
        english: "macOS does not recognize Microphone access for this AirTranslate build. If it is already enabled, keep only the current app, toggle access once, then quit and relaunch AirTranslate.",
        korean: "macOS가 현재 AirTranslate 빌드의 마이크 권한을 인식하지 못합니다. 이미 허용했다면 현재 앱만 남기고 권한을 한 번 껐다 켠 뒤 AirTranslate를 종료하고 다시 실행하세요."
    )
    static let microphoneUnavailable = localized(
        english: "The microphone input could not be started.",
        korean: "마이크 입력을 시작할 수 없습니다."
    )
    static let noActiveDisplay = localized(
        english: "No active display was available for system audio capture.",
        korean: "시스템 오디오 캡처에 사용할 수 있는 활성 디스플레이가 없습니다."
    )

    static func languageTitle(for id: String, fallback: String) -> String {
        switch id {
        case "en-US":
            localized(english: "English", korean: "영어", japanese: "英語", chineseSimplified: "英语")
        case "ko-KR":
            localized(english: "Korean", korean: "한국어", japanese: "韓国語", chineseSimplified: "韩语")
        case "ja-JP":
            localized(english: "Japanese", korean: "일본어", japanese: "日本語", chineseSimplified: "日语")
        case "zh-CN":
            localized(english: "Chinese Simplified", korean: "중국어 간체", japanese: "簡体字中国語", chineseSimplified: "简体中文")
        case "es-ES":
            localized(english: "Spanish", korean: "스페인어", japanese: "スペイン語", chineseSimplified: "西班牙语")
        case "fr-FR":
            localized(english: "French", korean: "프랑스어", japanese: "フランス語", chineseSimplified: "法语")
        case "de-DE":
            localized(english: "German", korean: "독일어", japanese: "ドイツ語", chineseSimplified: "德语")
        default:
            fallback
        }
    }
}
