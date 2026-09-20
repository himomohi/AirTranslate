import Foundation

// 공식 요금 확인 근거와 과금 조건은 docs/processing-mode-pricing.md에 기록한다.
struct ProcessingModeInfo {
    static let pricingCheckedOn = "2026-09-19–20"

    let modelID: String
    let summary: String
    let price: String

    var tooltip: String { "\(summary)\n\(price)" }

    static var pricingNote: String {
        AppText.localized(
            english: "USD · audio duration / tokens · checked \(pricingCheckedOn)",
            korean: "USD · 오디오 길이·토큰 기준 · \(pricingCheckedOn)",
            japanese: "USD · 音声時間・トークン基準 · \(pricingCheckedOn)",
            chineseSimplified: "USD · 按音频时长或令牌计费 · \(pricingCheckedOn)"
        )
    }

    static func information(
        for engine: ProcessingEngine,
        openAIOutputMode: LiveOutputMode = .translation,
        geminiModel: GeminiTranslationModel = .gemini35LiveTranslate,
        nariModel: NariTranscriptionModel = .qwen3ASRFast
    ) -> Self {
        switch engine {
        case .qwen:
            Self(modelID: QwenTranslationModel.liveTranslateFlashRealtime.rawValue, summary: QwenCopy.detail, price: QwenCopy.price)
        case .apple:
            Self(modelID: "apple-system",
                 summary: copy("On-device transcription & translation", "기기 내 음성 전사·번역", "デバイス内で文字起こし・翻訳", "设备端语音转写与翻译"),
                 price: copy("Free · no API usage fee", "무료 · API 사용료 없음", "無料 · API利用料なし", "免费 · 无 API 使用费"))
        case .openAI:
            if openAIOutputMode == .transcription {
                Self(modelID: "gpt-live-transcribe",
                     summary: copy("Source captions · gpt-live-transcribe", "원문 전사 · gpt-live-transcribe", "原文字幕 · gpt-live-transcribe", "原文转写 · gpt-live-transcribe"),
                     price: perMinute("0.017"))
            } else {
                Self(modelID: "gpt-realtime-translate",
                     summary: copy("Speech translation · gpt-realtime-translate", "음성 번역 · gpt-realtime-translate", "音声翻訳 · gpt-realtime-translate", "语音翻译 · gpt-realtime-translate"),
                     price: perMinute("0.034"))
            }
        case .gemini:
            if geminiModel.isTranscription {
                Self(modelID: GeminiTranslationModel.gemini35TranscribeLive.rawValue,
                     summary: copy("Gemini 3.5 · live transcription", "Gemini 3.5 · 실시간 원문 전사", "Gemini 3.5 · リアルタイム文字起こし", "Gemini 3.5 · 实时转写"),
                     price: estimatedPerMinute("0.009"))
            } else {
                Self(modelID: GeminiTranslationModel.gemini35LiveTranslate.rawValue,
                     summary: copy("Gemini 3.5 · speech translation", "Gemini 3.5 · 실시간 음성 번역", "Gemini 3.5 · リアルタイム音声翻訳", "Gemini 3.5 · 实时语音翻译"),
                     price: estimatedPerMinute("0.0368"))
            }
        case .meta:
            Self(modelID: "muse-voice-transcribe-1.0",
                 summary: copy("Live transcription with speaker labels", "화자를 구분하는 실시간 전사", "話者を区別するリアルタイム文字起こし", "区分说话人的实时转写"),
                 price: perHour("0.18"))
        case .azure:
            Self(modelID: "MAI-Transcribe-2",
                 summary: copy("MAI-Transcribe-2 · 5-second audio chunks", "MAI-Transcribe-2 · 5초 구간 전사", "MAI-Transcribe-2 · 5秒単位の文字起こし", "MAI-Transcribe-2 · 每5秒分段转写"),
                 price: perHour("0.10") + copy(" · promo to 2026-12-31", " · 할인 ~2026-12-31", " · 割引は2026-12-31まで", " · 优惠至2026-12-31"))
        case .nari:
            if nariModel.isLegacyFreeEndpoint {
                Self(modelID: nariModel.rawValue,
                     summary: copy("Qwen3-ASR · retired free beta", "Qwen3-ASR · 종료된 무료 베타", "Qwen3-ASR · 無料ベータ終了", "Qwen3-ASR · 免费测试已结束"),
                     price: copy("Unavailable · choose a GA model", "사용 불가 · GA 모델 선택 필요", "利用不可 · GAモデルを選択", "不可用 · 请选择 GA 模型"))
            } else if nariModel == .qwen3ASR {
                Self(modelID: NariTranscriptionModel.qwen3ASR.rawValue,
                     summary: copy("Qwen3-ASR · low-cost live transcription", "Qwen3-ASR · 경제적인 실시간 전사", "Qwen3-ASR · 低コストのリアルタイム文字起こし", "Qwen3-ASR · 低成本实时转写"),
                     price: perHour("0.06"))
            } else {
                Self(modelID: NariTranscriptionModel.qwen3ASRFast.rawValue,
                     summary: copy("Qwen3-ASR Fast · low-latency transcription", "Qwen3-ASR Fast · 빠른 실시간 전사", "Qwen3-ASR Fast · 低遅延文字起こし", "Qwen3-ASR Fast · 低延迟转写"),
                     price: perHour("0.12"))
            }
        case .grok:
            Self(modelID: "grok-voice-transcribe-2.0",
                 summary: copy("Grok Voice 2.0 · streaming transcription", "Grok Voice 2.0 · 실시간 음성 전사", "Grok Voice 2.0 · リアルタイム文字起こし", "Grok Voice 2.0 · 实时语音转写"),
                 price: perHour("0.20"))
        }
    }

    private static func perMinute(_ amount: String) -> String {
        copy("US$\(amount)/min", "US$\(amount)/분", "US$\(amount)/分", "US$\(amount)/分钟")
    }

    private static func perHour(_ amount: String) -> String {
        copy("US$\(amount)/hr", "US$\(amount)/시간", "US$\(amount)/時間", "US$\(amount)/小时")
    }

    private static func estimatedPerMinute(_ amount: String) -> String {
        copy("Paid ≈ US$\(amount)/min · token-based", "유료 약 US$\(amount)/분 · 토큰 기준", "有料 約US$\(amount)/分 · トークン基準", "付费约 US$\(amount)/分钟 · 按令牌计费")
    }

    private static func copy(_ english: String, _ korean: String, _ japanese: String, _ chinese: String) -> String {
        AppText.localized(english: english, korean: korean, japanese: japanese, chineseSimplified: chinese)
    }
}

extension ProcessingEngine {
    @MainActor
    func information(in session: TranslationSessionStore) -> ProcessingModeInfo {
        ProcessingModeInfo.information(
            for: self,
            openAIOutputMode: session.openAIOutputMode,
            geminiModel: session.geminiTranslationModel.isEnabled ? session.geminiTranslationModel : session.preferredGeminiModel,
            nariModel: session.nariTranscriptionModel.isEnabled ? session.nariTranscriptionModel : .qwen3ASRFast
        )
    }
}
