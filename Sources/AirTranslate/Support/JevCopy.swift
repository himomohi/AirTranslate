import Foundation

enum JevCopy {
    static var keySettings: String { AppText.localized(english: "Set up TypeSafe API key", korean: "TypeSafe API 키 설정", japanese: "TypeSafe API キーを設定", chineseSimplified: "设置 TypeSafe API 密钥") }
    static var title: String { AppText.localized(english: "Jev candidate selection (experimental)", korean: "Jev 단어 후보 선택 (실험)", japanese: "Jev 候補選択（実験）", chineseSimplified: "Jev 候选选择（实验）") }
    static var detail: String { AppText.localized(english: "Apple transcription → Jev → translation. For final speech results, Jev chooses a context-appropriate recognition candidate. Sends text candidates and recent transcript context to TypeSafe; adds API usage and up to 1.2 s waiting for a Jev response. Uncertain, missing or late choices keep the original. Accuracy improvement is not guaranteed.", korean: "Apple 전사 → Jev → 번역. 확정 전사 후보 중 문맥에 맞는 단어·표현을 고릅니다. 후보와 앞선 전사 문맥을 TypeSafe로 보내며 API 사용량과 Jev 응답 대기 최대 1.2초가 추가됩니다. 후보 없음·불확실·시간 초과 시 원문을 유지합니다. 정확도 향상은 보장되지 않습니다.", japanese: "Apple 文字起こし → Jev → 翻訳。確定した認識候補から文脈に合う表現を選びます。候補と直前の文字起こしを TypeSafe に送信し、API 使用量とJev 応答待機（最大1.2秒）が加わります。候補なし・不確実・時間切れでは原文を保持します。精度向上は保証されません。", chineseSimplified: "Apple 转写 → Jev → 翻译。从最终识别候选中选择符合上下文的词语。将候选和之前的转写上下文发送给 TypeSafe，增加 API 用量及最多1.2秒的 Jev 响应等待。无候选、不确定或超时则保留原文。不保证准确率提升。") }
    static var appleOnly: String { AppText.localized(english: "Available with Apple speech recognition and translation. Stop capture before changing this option.", korean: "Apple 전사와 번역을 함께 사용할 때 지원합니다. 변경하려면 녹음을 중지하세요.", japanese: "Apple 文字起こしと翻訳で利用できます。変更前に録音を停止してください。", chineseSimplified: "支持 Apple 转写加翻译。更改前请停止录音。") }
    static var keyRequired: String { AppText.localized(english: "Add a TypeSafe API key in API settings. Without a key, the original transcript is translated.", korean: "API 설정에서 TypeSafe API 키를 등록하세요. 키가 없으면 원래 전사문으로 번역합니다.", japanese: "API 設定で TypeSafe API キーを登録してください。キーがなければ原文を翻訳します。", chineseSimplified: "请在 API 设置中添加 TypeSafe API 密钥。没有密钥时翻译原始转写。") }
    static var ready: String { AppText.localized(english: "Waiting for final recognition candidates", korean: "확정 전사 후보를 기다리는 중", japanese: "確定した認識候補を待機中", chineseSimplified: "等待最终识别候选") }
    static func status(_ outcome: JevTranscriptSelection.Outcome) -> String {
        switch outcome {
        case .selected: AppText.localized(english: "Jev selected a candidate for translation", korean: "Jev가 고른 후보로 번역", japanese: "Jev が選んだ候補を翻訳", chineseSimplified: "翻译 Jev 选择的候选")
        case .original: AppText.localized(english: "Jev kept the original transcript", korean: "Jev 판단: 원래 전사문 유지", japanese: "Jev が原文を保持", chineseSimplified: "Jev 保留原始转写")
        case .noCandidates: AppText.localized(english: "No alternative candidate — translating the original", korean: "대체 후보 없음 · 원문으로 번역", japanese: "代替候補なし・原文を翻訳", chineseSimplified: "无其他候选 · 翻译原文")
        case .lowConfidence: AppText.localized(english: "Uncertain choice — translating the original", korean: "선택 불확실 · 원문으로 번역", japanese: "選択が不確実・原文を翻訳", chineseSimplified: "选择不确定 · 翻译原文")
        case .timedOut: AppText.localized(english: "Jev timed out — translating the original", korean: "Jev 시간 초과 · 원문으로 번역", japanese: "Jev 時間切れ・原文を翻訳", chineseSimplified: "Jev 超时 · 翻译原文")
        case .unavailable, .invalidResponse: AppText.localized(english: "Jev unavailable — translating the original; check the API key", korean: "Jev 사용 불가 · 원문으로 번역 (API 키 확인)", japanese: "Jev 利用不可・原文を翻訳（API キーを確認）", chineseSimplified: "Jev 不可用 · 翻译原文（请检查 API 密钥）")
        }
    }
}
