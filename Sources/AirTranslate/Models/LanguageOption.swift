import Foundation

struct LanguageOption: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let locale: Locale

    var localizedTitle: String {
        AppText.languageTitle(for: id, fallback: title)
    }

    static let english = LanguageOption(id: "en-US", title: "English", locale: Locale(identifier: "en-US"))
    static let korean = LanguageOption(id: "ko-KR", title: "Korean", locale: Locale(identifier: "ko-KR"))

    static let supported: [LanguageOption] = [
        english,
        korean,
        .init(id: "ja-JP", title: "Japanese", locale: Locale(identifier: "ja-JP")),
        .init(id: "zh-CN", title: "Chinese Simplified", locale: Locale(identifier: "zh-CN")),
        .init(id: "es-ES", title: "Spanish", locale: Locale(identifier: "es-ES")),
        .init(id: "fr-FR", title: "French", locale: Locale(identifier: "fr-FR")),
        .init(id: "de-DE", title: "German", locale: Locale(identifier: "de-DE")),
        .init(id: "vi-VN", title: "Vietnamese", locale: Locale(identifier: "vi-VN"))
    ]

    static func prioritizedAutoDetectionCandidates(
        sourceLanguage _: LanguageOption,
        targetLanguage: LanguageOption
    ) -> [LanguageOption] {
        LanguageOption.supported.filter { language in
            language != targetLanguage
        }
    }

    static func preferredSystemLanguage(fallback: LanguageOption) -> LanguageOption {
        for identifier in Locale.preferredLanguages {
            let normalizedIdentifier = identifier.lowercased().replacingOccurrences(of: "_", with: "-")
            if let exactMatch = supported.first(where: { $0.id.lowercased() == normalizedIdentifier }) {
                return exactMatch
            }

            let languageCode = normalizedIdentifier.split(separator: "-").first.map(String.init) ?? normalizedIdentifier
            if let languageMatch = supported.first(where: { $0.id.lowercased().hasPrefix("\(languageCode)-") }) {
                return languageMatch
            }
        }

        return fallback
    }

    var metaLanguageBiasName: String? {
        switch id.lowercased().split(separator: "-").first.map(String.init) {
        case "en": "English"
        case "ko": "Korean"
        case "ja": "Japanese"
        case "zh": "Mandarin Chinese"
        case "es": "Spanish"
        case "fr": "French"
        case "de": "German"
        case "pt": "Portuguese"
        case "it": "Italian"
        case "nl": "Dutch"
        case "pl": "Polish"
        case "tr": "Turkish"
        case "ar": "Arabic"
        case "he": "Hebrew"
        case "hi": "Hindi"
        case "bn": "Bengali"
        case "mr": "Marathi"
        case "ta": "Tamil"
        case "te": "Telugu"
        case "kn": "Kannada"
        case "id": "Indonesian"
        case "ms": "Malay"
        case "tl", "fil": "Tagalog"
        case "th": "Thai"
        case "vi": "Vietnamese"
        default: nil
        }
    }
}
