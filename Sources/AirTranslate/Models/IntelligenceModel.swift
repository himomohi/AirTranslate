import Foundation

enum IntelligenceModel: String, CaseIterable, Identifiable {
    case appleSystem = "apple-system"
    case appleOnDevice = "apple-on-device"
    case appleSpeechOnly = "apple-speech-only"

    static var allCases: [IntelligenceModel] {
        [.appleSystem, .appleSpeechOnly]
    }

    var id: String { rawValue }

    var title: String {
        switch self {
        case .appleSystem:
            AppText.localized(
                english: "Live Transcription + Translation",
                korean: "실시간 전사 + 번역",
                japanese: "リアルタイム文字起こし + 翻訳",
                chineseSimplified: "实时转写 + 翻译"
            )
        case .appleOnDevice:
            AppText.localized(
                english: "Translation Language Pack",
                korean: "번역 언어팩",
                japanese: "翻訳言語パック",
                chineseSimplified: "翻译语言包"
            )
        case .appleSpeechOnly:
            AppText.localized(
                english: "Transcribe Only",
                korean: "전사만",
                japanese: "文字起こしのみ",
                chineseSimplified: "仅转写"
            )
        }
    }

    var detail: String {
        switch self {
        case .appleSystem:
            AppText.localized(
                english: "Live transcription with SpeechTranscriber, then TranslationSession for the selected language pair.",
                korean: "SpeechTranscriber로 실시간 전사한 뒤 선택한 언어쌍을 TranslationSession으로 번역합니다.",
                japanese: "SpeechTranscriberでリアルタイム文字起こしを行い、選択した言語ペアをTranslationSessionで翻訳します。",
                chineseSimplified: "使用 SpeechTranscriber 实时转写，然后用 TranslationSession 翻译所选语言对。"
            )
        case .appleOnDevice:
            AppText.localized(
                english: "Checks the installed Apple Translation language assets for the selected source and target languages.",
                korean: "선택한 원문/번역 언어쌍의 Apple 번역 언어 자산 설치 상태를 확인합니다.",
                japanese: "選択した原文/翻訳言語ペアのApple翻訳言語アセットのインストール状態を確認します。",
                chineseSimplified: "检查所选原文/译文语言对的 Apple 翻译语言资源安装状态。"
            )
        case .appleSpeechOnly:
            AppText.localized(
                english: "Uses SpeechTranscriber for source-language captions only, without TranslationSession.",
                korean: "TranslationSession 없이 SpeechTranscriber만 사용해 원문 자막을 기록합니다.",
                japanese: "TranslationSessionを使わず、SpeechTranscriberだけで原文字幕を記録します。",
                chineseSimplified: "不使用 TranslationSession，仅用 SpeechTranscriber 记录原文字幕。"
            )
        }
    }

    var checkingDetail: String {
        AppText.localized(
            english: "Checking local assets for \(title)...",
            korean: "\(title) 로컬 자산을 확인하는 중입니다...",
            japanese: "\(title) のローカルアセットを確認中...",
            chineseSimplified: "正在检查 \(title) 的本地资源..."
        )
    }
}

enum OpenAIRealtimeTranscriptionModel: String, CaseIterable, Identifiable {
    case off
    case gptRealtimeWhisper = "gpt-realtime-whisper"
    case gptLiveTranscribe = "gpt-live-transcribe"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off:
            AppText.localized(english: "Use Apple Speech", korean: "Apple Speech 사용", japanese: "Apple Speechを使用", chineseSimplified: "使用 Apple Speech")
        case .gptRealtimeWhisper:
            "gpt-realtime-whisper"
        case .gptLiveTranscribe:
            "gpt-live-transcribe"
        }
    }

    var isEnabled: Bool {
        self != .off
    }
}

enum OpenAIRealtimeTranslationModel: String, CaseIterable, Identifiable {
    case off
    case gptRealtimeTranslate = "gpt-realtime-translate"
    case gptRealtime21 = "gpt-realtime-2.1"
    case gptRealtime21Mini = "gpt-realtime-2.1-mini"

    static var liveTranslationCases: [OpenAIRealtimeTranslationModel] {
        [.gptRealtimeTranslate]
    }

    static var voiceAgentCases: [OpenAIRealtimeTranslationModel] {
        [.gptRealtime21, .gptRealtime21Mini]
    }

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off:
            AppText.localized(english: "Use Apple Translation", korean: "Apple Translation 사용", japanese: "Apple Translationを使用", chineseSimplified: "使用 Apple Translation")
        case .gptRealtimeTranslate:
            AppText.localized(
                english: "gpt-realtime-translate · translation-only",
                korean: "gpt-realtime-translate · 번역 전용",
                japanese: "gpt-realtime-translate · Live翻訳",
                chineseSimplified: "gpt-realtime-translate · 实时翻译"
            )
        case .gptRealtime21:
            AppText.localized(
                english: "gpt-realtime-2.1 · voice agent",
                korean: "gpt-realtime-2.1 · 보이스 에이전트",
                japanese: "gpt-realtime-2.1 · Voice agent",
                chineseSimplified: "gpt-realtime-2.1 · 语音代理"
            )
        case .gptRealtime21Mini:
            AppText.localized(
                english: "gpt-realtime-2.1-mini · voice agent",
                korean: "gpt-realtime-2.1-mini · 보이스 에이전트",
                japanese: "gpt-realtime-2.1-mini · Voice agent",
                chineseSimplified: "gpt-realtime-2.1-mini · 语音代理"
            )
        }
    }

    var isEnabled: Bool {
        self != .off
    }

    var usesRealtimeAudioTranslation: Bool {
        self == .gptRealtimeTranslate
    }

    var isSupportedLiveTranslationModel: Bool {
        self == .gptRealtimeTranslate
    }

    var apiModelID: String {
        switch self {
        case .off:
            ""
        case .gptRealtimeTranslate, .gptRealtime21, .gptRealtime21Mini:
            rawValue
        }
    }
}

enum GeminiTranslationModel: String, CaseIterable, Identifiable, Sendable {
    case off
    case gemini35LiveTranslate = "gemini-3.5-live-translate-preview"
    case gemini35TranscribeLive = "gemini-3.5-transcribe-live"

    static let selectableCases: [GeminiTranslationModel] = [
        .gemini35LiveTranslate,
        .gemini35TranscribeLive,
    ]

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off:
            AppText.localized(
                english: "Use Apple Translation",
                korean: "Apple Translation 사용",
                japanese: "Apple Translationを使用",
                chineseSimplified: "使用 Apple Translation"
            )
        case .gemini35LiveTranslate:
            "Gemini 3.5 Live Translate"
        case .gemini35TranscribeLive:
            "Gemini 3.5 Transcribe Live"
        }
    }

    var isEnabled: Bool {
        self != .off
    }

    var isTranslation: Bool {
        self == .gemini35LiveTranslate
    }

    var isTranscription: Bool {
        self == .gemini35TranscribeLive
    }

    var apiModelID: String {
        switch self {
        case .off:
            ""
        case .gemini35LiveTranslate, .gemini35TranscribeLive:
            rawValue
        }
    }
}

enum SpeechSynthesisModel: String, CaseIterable, Identifiable, Sendable {
    case appleSystem = "apple-system"
    case gemini38Flash = "gemini-3.8-flash-tts"
    case gemini38FlashLite = "gemini-3.8-flash-lite-tts"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .appleSystem:
            AppText.localized(
                english: "Apple System Voice",
                korean: "Apple 시스템 음성",
                japanese: "Appleシステム音声",
                chineseSimplified: "Apple 系统语音"
            )
        case .gemini38Flash:
            "Gemini 3.8 Flash TTS"
        case .gemini38FlashLite:
            "Gemini 3.8 Flash-Lite TTS"
        }
    }

    var isGeminiTTS: Bool {
        self != .appleSystem
    }

    var apiModelID: String? {
        isGeminiTTS ? rawValue : nil
    }
}

enum MetaTranscriptionModel: String, CaseIterable, Identifiable, Sendable {
    case off
    case museVoiceTranscribe = "muse-voice-transcribe-1.0"

    static let selectableCases: [MetaTranscriptionModel] = [.museVoiceTranscribe]

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off:
            AppText.localized(
                english: "Use Apple Speech",
                korean: "Apple Speech 사용",
                japanese: "Apple Speechを使用",
                chineseSimplified: "使用 Apple Speech"
            )
        case .museVoiceTranscribe:
            "Muse Voice Transcribe 1.0"
        }
    }

    var isEnabled: Bool {
        self != .off
    }

    var apiModelID: String {
        isEnabled ? rawValue : ""
    }
}
