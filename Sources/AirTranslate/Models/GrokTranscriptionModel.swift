import Foundation

enum GrokTranscriptionModel: String, CaseIterable, Identifiable, Sendable {
    case off
    case voiceTranscribe2 = "grok-voice-transcribe-2.0"

    static let selectableCases: [Self] = [.voiceTranscribe2]
    // language는 인식 언어 강제가 아닌 숫자·통화·단위 표기용 설정이다.
    static let supportedLanguageCodes: Set<String> = [
        "ar", "cs", "da", "nl", "en", "fil", "fr", "de", "hi", "id", "it", "ja", "ko",
        "mk", "ms", "fa", "pl", "pt", "ro", "ru", "es", "sv", "th", "tr", "vi",
    ]
    var id: String { rawValue }
    var isEnabled: Bool { self != .off }
    var title: String { isEnabled ? "Grok Voice Transcribe 2.0" : AppText.localized(english: "Off", korean: "끔", japanese: "オフ", chineseSimplified: "关闭") }
    static func languageCode(for language: LanguageOption) -> String? {
        let primary = language.id.lowercased().replacingOccurrences(of: "_", with: "-").split(separator: "-").first.map(String.init) ?? ""
        let code = primary == "tl" ? "fil" : primary
        return supportedLanguageCodes.contains(code) ? code : nil
    }
}
