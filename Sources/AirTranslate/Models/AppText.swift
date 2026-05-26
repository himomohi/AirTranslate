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
        english: "Enter your API key in the app. AirTranslate stores it in macOS Keychain and uses it only for OpenAI translation.",
        korean: "앱에서 API 키를 입력하세요. AirTranslate는 키를 macOS Keychain에 저장하고 OpenAI 번역에만 사용합니다."
    )
    static let openAIAPIKeyPlaceholder = localized(
        english: "Paste API key",
        korean: "API 키 붙여넣기",
        japanese: "APIキーを貼り付け",
        chineseSimplified: "粘贴 API key"
    )
    static let saveOpenAIAPIKey = localized(english: "Save API Key", korean: "API 키 저장", japanese: "APIキーを保存", chineseSimplified: "保存 API key")
    static let removeOpenAIAPIKey = localized(english: "Remove API Key", korean: "API 키 삭제", japanese: "APIキーを削除", chineseSimplified: "删除 API key")
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
    static let openAIAPIKeyRequiredForGPTMode = localized(
        english: "Enter an OpenAI API key to use GPT mode.",
        korean: "GPT 모드를 사용하려면 OpenAI API 키를 입력하세요.",
        japanese: "GPTモードを使うにはOpenAI APIキーを入力してください。",
        chineseSimplified: "要使用 GPT 模式，请输入 OpenAI API key。"
    )
    static let openAIAPIKeyEmpty = localized(
        english: "Enter an OpenAI API key before saving.",
        korean: "저장하기 전에 OpenAI API 키를 입력하세요."
    )
    static let openAIAPIKeyInvalidStoredValue = localized(
        english: "The stored OpenAI API key could not be read.",
        korean: "저장된 OpenAI API 키를 읽을 수 없습니다."
    )
    static let openAIProvider = localized(
        english: "Provider",
        korean: "공급자",
        japanese: "プロバイダー",
        chineseSimplified: "服务商"
    )
    static let openAIProviderOpenAITitle = "OpenAI"
    static let openAIProviderAzureTitle = "Azure OpenAI"
    static let azureOpenAIEndpoint = localized(
        english: "Azure Resource Endpoint",
        korean: "Azure 리소스 엔드포인트",
        japanese: "Azureリソースエンドポイント",
        chineseSimplified: "Azure 资源终结点"
    )
    static let azureOpenAIEndpointPlaceholder = localized(
        english: "https://<resource>.cognitiveservices.azure.com/",
        korean: "https://<리소스>.cognitiveservices.azure.com/",
        japanese: "https://<リソース>.cognitiveservices.azure.com/",
        chineseSimplified: "https://<资源名>.cognitiveservices.azure.com/"
    )
    static let azureOpenAIEndpointFormatHint = localized(
        english: "Use the Azure resource endpoint only. Do not include wss:// or /openai/v1/realtime.",
        korean: "Azure 리소스 엔드포인트만 입력하세요. wss:// 또는 /openai/v1/realtime은 포함하지 마세요.",
        japanese: "Azureリソースエンドポイントのみ入力してください。wss:// や /openai/v1/realtime は含めないでください。",
        chineseSimplified: "只填写 Azure 资源终结点。不要包含 wss:// 或 /openai/v1/realtime。"
    )
    static let azureOpenAIAPIKey = localized(
        english: "Azure API Key",
        korean: "Azure API 키",
        japanese: "Azure APIキー",
        chineseSimplified: "Azure API key"
    )
    static let azureOpenAIAPIKeyPlaceholder = localized(
        english: "Paste Azure resource key",
        korean: "Azure 리소스 키 붙여넣기",
        japanese: "Azureリソースキーを貼り付け",
        chineseSimplified: "粘贴 Azure 资源 key"
    )
    static let saveAzureOpenAIConfig = localized(
        english: "Save Azure Config",
        korean: "Azure 설정 저장",
        japanese: "Azure設定を保存",
        chineseSimplified: "保存 Azure 配置"
    )
    static let removeAzureOpenAIConfig = localized(
        english: "Remove Azure Config",
        korean: "Azure 설정 삭제",
        japanese: "Azure設定を削除",
        chineseSimplified: "删除 Azure 配置"
    )
    static let azureOpenAIConfigSaved = localized(
        english: "Azure OpenAI configuration saved.",
        korean: "Azure OpenAI 설정이 저장되었습니다.",
        japanese: "Azure OpenAI設定を保存しました。",
        chineseSimplified: "已保存 Azure OpenAI 配置。"
    )
    static let azureOpenAIConfigSavedTitle = localized(
        english: "Saved",
        korean: "저장됨",
        japanese: "保存しました",
        chineseSimplified: "已保存"
    )
    static let azureOpenAIConfigSaveFailedTitle = localized(
        english: "Save Failed",
        korean: "저장 실패",
        japanese: "保存に失敗しました",
        chineseSimplified: "保存失败"
    )
    static let azureOpenAIConfigRemoved = localized(
        english: "Azure OpenAI configuration removed.",
        korean: "Azure OpenAI 설정이 삭제되었습니다.",
        japanese: "Azure OpenAI設定を削除しました。",
        chineseSimplified: "已删除 Azure OpenAI 配置。"
    )
    static let azureOpenAIConfigConfigured = localized(
        english: "Azure config saved",
        korean: "Azure 설정 저장됨",
        japanese: "Azure設定保存済み",
        chineseSimplified: "Azure 配置已保存"
    )
    static let azureOpenAIConfigNotConfigured = localized(
        english: "Azure config required",
        korean: "Azure 설정 필요",
        japanese: "Azure設定が必要",
        chineseSimplified: "需要 Azure 配置"
    )
    static let azureOpenAIConfigRequiredForGPTMode = localized(
        english: "Enter the Azure endpoint and key to use GPT mode.",
        korean: "GPT 모드를 사용하려면 Azure 엔드포인트와 키를 입력하세요.",
        japanese: "GPTモードを使うにはAzureエンドポイントとキーを入力してください。",
        chineseSimplified: "要使用 GPT 模式，请输入 Azure 终结点和密钥。"
    )
    static let azureOpenAIEndpointInvalid = localized(
        english: "The Azure resource endpoint must be a URL such as https://<resource>.cognitiveservices.azure.com/.",
        korean: "Azure 리소스 엔드포인트는 https://<리소스>.cognitiveservices.azure.com/ 같은 URL이어야 합니다.",
        japanese: "Azureリソースエンドポイントは https://<リソース>.cognitiveservices.azure.com/ の形式のURLを入力してください。",
        chineseSimplified: "Azure 资源终结点必须是类似 https://<资源名>.cognitiveservices.azure.com/ 的 URL。"
    )
    static let azureOpenAIEndpointMissing = localized(
        english: "Add an Azure resource endpoint in Settings before using Azure OpenAI.",
        korean: "Azure OpenAI를 사용하기 전에 설정에서 Azure 리소스 엔드포인트를 입력하세요.",
        japanese: "Azure OpenAIを使う前に設定でAzureリソースエンドポイントを入力してください。",
        chineseSimplified: "使用 Azure OpenAI 前请先在设置中输入 Azure 资源终结点。"
    )
    static let azureOpenAIAPIKeyMissing = localized(
        english: "Add an Azure OpenAI API key in Settings before using Azure OpenAI.",
        korean: "Azure OpenAI를 사용하기 전에 설정에서 Azure OpenAI API 키를 입력하세요.",
        japanese: "Azure OpenAIを使う前に設定でAzure OpenAI APIキーを入力してください。",
        chineseSimplified: "使用 Azure OpenAI 前请先在设置中输入 Azure OpenAI API key。"
    )
    static let azureOpenAITranscriptionUnsupported = localized(
        english: "Azure OpenAI only supports realtime translation. Switch to a translation model or use the OpenAI provider for transcription.",
        korean: "Azure OpenAI는 실시간 번역만 지원합니다. 번역 모델로 전환하거나 전사를 위해 OpenAI 공급자를 사용하세요.",
        japanese: "Azure OpenAIはリアルタイム翻訳のみサポートします。翻訳モデルに切り替えるか、文字起こしにはOpenAIプロバイダーを使ってください。",
        chineseSimplified: "Azure OpenAI 仅支持实时翻译。请切换到翻译模型，或转写时改用 OpenAI 服务商。"
    )
    static let azureOpenAIPlatformPrompt = localized(
        english: "Need Azure OpenAI access?",
        korean: "Azure OpenAI 액세스가 필요하신가요?",
        japanese: "Azure OpenAIのアクセスが必要ですか？",
        chineseSimplified: "需要 Azure OpenAI 访问权限？"
    )
    static let azureOpenAIPlatformLink = localized(
        english: "Open Azure AI Foundry",
        korean: "Azure AI Foundry 열기",
        japanese: "Azure AI Foundryを開く",
        chineseSimplified: "打开 Azure AI Foundry"
    )
    static let appleProcessingMode = localized(english: "Apple Mode", korean: "Apple 기본 모드", japanese: "Apple標準モード", chineseSimplified: "Apple 默认模式")
    static let appleProcessingModeDescription = localized(
        english: "The default local workflow. Keep this as the base, then add OpenAI Realtime below only when needed.",
        korean: "기본 로컬 처리 흐름입니다. 이 설정을 기준으로 두고, 필요한 경우 아래 OpenAI Realtime만 추가하세요."
    )
    static let gptModels = localized(english: "OpenAI Realtime", korean: "OpenAI Realtime", japanese: "OpenAI Realtime", chineseSimplified: "OpenAI Realtime")
    static let gptTranscriptionModel = localized(
        english: "Transcription",
        korean: "전사",
        japanese: "文字起こし",
        chineseSimplified: "转写"
    )
    static let gptTranscriptionLockedByRealtimeTitle = localized(
        english: "Transcription handled by realtime translation",
        korean: "전사는 실시간 번역이 처리합니다",
        japanese: "文字起こしはリアルタイム翻訳が担当します",
        chineseSimplified: "转写由实时翻译模型负责"
    )
    static let gptTranscriptionLockedByRealtimeDetail = localized(
        english: "gpt-realtime-translate works directly on audio, so a separate transcription model is not used.",
        korean: "gpt-realtime-translate는 오디오를 직접 처리하므로 별도의 전사 모델은 사용되지 않습니다.",
        japanese: "gpt-realtime-translateは音声を直接処理するため、別途の文字起こしモデルは使用しません。",
        chineseSimplified: "gpt-realtime-translate 直接基于音频翻译,因此不再使用单独的转写模型。"
    )
    static let gptTranslationModel = localized(
        english: "Auto Translation",
        korean: "자동번역",
        japanese: "自動翻訳",
        chineseSimplified: "自动翻译"
    )
    static let gptModelsDescription = localized(
        english: "GPT mode uses OpenAI Realtime directly for the translated stream and bypasses local transcript cleanup.",
        korean: "GPT 모드는 OpenAI Realtime의 번역 스트림을 직접 사용하며 로컬 기록 다듬기를 건너뜁니다."
    )
    static let advancedSection = localized(
        english: "Advanced",
        korean: "고급",
        japanese: "詳細",
        chineseSimplified: "高级"
    )
    static let customTranscriptionModelName = localized(
        english: "Transcription model name",
        korean: "전사 모델 이름",
        japanese: "文字起こしモデル名",
        chineseSimplified: "转写模型名称"
    )
    static let customTranslationModelName = localized(
        english: "Translation model name",
        korean: "번역 모델 이름",
        japanese: "翻訳モデル名",
        chineseSimplified: "翻译模型名称"
    )
    static let customModelNameFootnote = localized(
        english: "Leave empty to use the default.",
        korean: "기본값을 사용하려면 비워두세요.",
        japanese: "デフォルトを使う場合は空のままにします。",
        chineseSimplified: "留空则使用默认值。"
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
    static let openAIRealtimeTranslationOnlySource = localized(
        english: "OpenAI realtime translation",
        korean: "OpenAI 실시간 번역"
    )
    static let output = localized(english: "Output", korean: "출력", japanese: "出力", chineseSimplified: "输出")
    static let translationSettings = localized(english: "Translation Settings", korean: "번역 설정", japanese: "翻訳設定", chineseSimplified: "翻译设置")
    static let configureTranslationSettings = localized(
        english: "Configure Translation Settings",
        korean: "번역 설정 구성"
    )
    static let transcript = localized(english: "Transcript", korean: "기록", japanese: "記録", chineseSimplified: "记录")
    static let liveOutput = localized(english: "Live Output", korean: "실시간 출력", japanese: "リアルタイム出力", chineseSimplified: "实时输出")
    static let library = localized(english: "Library", korean: "저장소", japanese: "ライブラリ", chineseSimplified: "资料库")
    static let dubbing = localized(english: "Dubbing", korean: "더빙", japanese: "音声出力", chineseSimplified: "配音")
    static let voiceOutput = localized(english: "System translated voice", korean: "시스템 번역 음성", japanese: "システム翻訳音声", chineseSimplified: "系统翻译语音")
    static let menuBarTitle = localized(english: "Captions", korean: "자막")
    static let menuBarRunningTitle = localized(english: "Live", korean: "기록 중")
    static let menuBarPausedTitle = localized(english: "Paused", korean: "일시정지")
    static let floatingCaptions = localized(english: "Floating Captions", korean: "플로팅 자막")
    static let showFloatingCaptions = localized(english: "Show Floating Captions", korean: "플로팅 자막 보기")
    static let floatingCaptionPowerOn = localized(english: "ON", korean: "켜짐")
    static let floatingCaptionPowerOff = localized(english: "OFF", korean: "꺼짐")
    static let captionsWindow = localized(english: "Caption Window", korean: "자막 창")
    static let hideFloatingCaptions = localized(english: "Hide Floating Captions", korean: "플로팅 자막 숨기기")
    static let openMainWindow = localized(english: "Open Main Window", korean: "메인 창 열기")
    static let floatingDisplay = localized(english: "Floating Display", korean: "플로팅 표시")
    static let floatingTextAlignment = localized(
        english: "Floating Text Alignment",
        korean: "플로팅 텍스트 정렬",
        japanese: "フローティングテキスト配置",
        chineseSimplified: "浮动字幕对齐"
    )
    static let textAlignmentLeading = localized(
        english: "Left",
        korean: "왼쪽",
        japanese: "左",
        chineseSimplified: "左对齐"
    )
    static let textAlignmentCenter = localized(
        english: "Center",
        korean: "가운데",
        japanese: "中央",
        chineseSimplified: "居中"
    )
    static let floatingTextSize = localized(english: "Floating Text Size", korean: "플로팅 글자 크기")
    static let floatingLineCount = localized(english: "Floating Lines", korean: "플로팅 표시 줄 수")
    static let floatingImmediateDisplay = localized(
        english: "Show Updates Immediately",
        korean: "업데이트 즉시 표시",
        japanese: "更新をすぐ表示",
        chineseSimplified: "立即显示更新"
    )
    static let floatingImmediateDisplayDescription = localized(
        english: "Shows new caption text as soon as it arrives. It feels more realtime, but recognition revisions can make the floating window flicker.",
        korean: "새 자막 텍스트가 도착하는 즉시 표시합니다. 더 실시간처럼 느껴지지만 인식 수정 때문에 플로팅 창이 깜박일 수 있습니다.",
        japanese: "新しい字幕テキストを到着次第表示します。よりリアルタイムになりますが、認識の修正でフローティングウィンドウがちらつくことがあります。",
        chineseSimplified: "新字幕到达后立即显示。实时性更好，但识别结果修订时浮动窗口可能会闪动。"
    )
    static let originalOnly = localized(english: "Original", korean: "원문", japanese: "原文", chineseSimplified: "原文")
    static let originalAndTranslation = localized(english: "Original + Translation", korean: "원문 + 번역", japanese: "原文 + 翻訳", chineseSimplified: "原文 + 译文")
    static let translationOnly = localized(english: "Translation", korean: "번역", japanese: "翻訳", chineseSimplified: "译文")
    static let textSizeSmall = localized(english: "Small", korean: "작게", japanese: "小", chineseSimplified: "小")
    static let textSizeMedium = localized(english: "Medium", korean: "보통", japanese: "中", chineseSimplified: "中")
    static let textSizeLarge = localized(english: "Large", korean: "크게", japanese: "大", chineseSimplified: "大")
    static let textSizeExtraLarge = localized(english: "Extra Large", korean: "아주 크게", japanese: "特大", chineseSimplified: "特大")
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
    static let savedTranscriptContent = localized(
        english: "Saved Content",
        korean: "저장 내용"
    )
    static let autoSave = localized(english: "Auto-save", korean: "자동 저장")
    static let autoSaveDescription = localized(
        english: "Transcript text is kept in memory while listening, then saved as a dated plain .txt file with a short content title when capture stops or the app quits.",
        korean: "기록 중에는 메모리에 유지하고, 캡처 중지 또는 앱 종료 직전에 날짜와 짧은 내용 제목이 들어간 일반 .txt 파일로 저장됩니다."
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
        english: "Auto-saved transcripts will appear here.",
        korean: "자동 저장된 기록이 여기에 표시됩니다."
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
    static let openPrivacySettings = localized(
        english: "Open Privacy Settings",
        korean: "개인정보 보호 설정 열기"
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

    static let openAIInvalidResponse = localized(
        english: "OpenAI returned an invalid response.",
        korean: "OpenAI가 올바르지 않은 응답을 반환했습니다."
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
        english: "Screen Recording permission is not active for this signed AirTranslate app. Grant it once, then quit and relaunch AirTranslate.",
        korean: "서명된 AirTranslate 앱에 화면 기록 권한이 활성화되어 있지 않습니다. 한 번 허용한 뒤 AirTranslate를 종료하고 다시 실행하세요."
    )
    static let microphoneNotGranted = localized(
        english: "Microphone permission is not active for this signed AirTranslate app. Grant it once, then quit and relaunch AirTranslate.",
        korean: "서명된 AirTranslate 앱에 마이크 권한이 활성화되어 있지 않습니다. 한 번 허용한 뒤 AirTranslate를 종료하고 다시 실행하세요."
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
