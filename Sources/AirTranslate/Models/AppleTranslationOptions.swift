import Foundation
@preconcurrency import Translation

enum AppleTranslationQuality: String, CaseIterable, Sendable {
    case realtime
    case highQuality

    @available(macOS 26.4, *)
    var strategy: TranslationSession.Strategy {
        switch self {
        case .realtime: .lowLatency
        case .highQuality: .highFidelity
        }
    }
}

struct AppleTranslationOptions: Equatable, Sendable {
    var quality: AppleTranslationQuality = .realtime
    var protectedTerms: [String] = []

    static let maximumProtectedTerms = 100
    static let maximumTermCharacters = 80
    private static let matchingLocale = Locale(identifier: "en_US_POSIX")

    static var supportsStrategySelection: Bool {
        if #available(macOS 26.4, *) { return true }
        return false
    }

    var effectiveQuality: AppleTranslationQuality {
        effectiveQuality(supportsStrategySelection: Self.supportsStrategySelection)
    }

    func effectiveQuality(supportsStrategySelection: Bool) -> AppleTranslationQuality {
        supportsStrategySelection ? quality : .realtime
    }

    var normalizedProtectedTerms: [String] {
        Self.normalize(protectedTerms)
    }

    static func parseProtectedTerms(_ text: String) -> [String] {
        normalize(text.components(separatedBy: .newlines))
    }

    private static func normalize(_ terms: [String]) -> [String] {
        var result: [String] = []
        var seen = Set<String>()
        for term in terms {
            let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, trimmed.count <= maximumTermCharacters,
                  !trimmed.unicodeScalars.contains(where: CharacterSet.newlines.contains) else { continue }
            let key = trimmed.folding(options: .caseInsensitive, locale: matchingLocale)
            guard seen.insert(key).inserted else { continue }
            result.append(trimmed)
            if result.count == maximumProtectedTerms { break }
        }
        return result
    }

    /// 긴 용어를 먼저 확보하고, 원문 인덱스를 사용해 겹침과 문자 중간 절단을 막는다.
    func protectedRanges(in text: String) -> [Range<String.Index>] {
        let terms = normalizedProtectedTerms.enumerated().sorted {
            if $0.element.count != $1.element.count { return $0.element.count > $1.element.count }
            return $0.offset < $1.offset
        }
        guard !text.isEmpty, !terms.isEmpty else { return [] }
        let boundaries = Array(text.indices) + [text.endIndex]
        let boundarySet = Set(boundaries)
        var selected: [Range<String.Index>] = []
        for (_, term) in terms {
            var searchStart = text.startIndex
            while searchStart < text.endIndex,
                  let range = text.range(
                    of: term, options: .caseInsensitive,
                    range: searchStart..<text.endIndex, locale: Self.matchingLocale
                  ) {
                guard boundarySet.contains(range.lowerBound), boundarySet.contains(range.upperBound) else {
                    searchStart = boundaries.first(where: { $0 > range.lowerBound }) ?? text.endIndex
                    continue
                }
                if Self.hasWordBoundaries(range, term: term, in: text),
                   !selected.contains(where: { $0.overlaps(range) }) {
                    selected.append(range)
                    searchStart = range.upperBound
                } else {
                    // 겹쳐 탈락한 후보 다음에도 유효한 일치가 있을 수 있다.
                    searchStart = text.index(after: range.lowerBound)
                }
            }
        }
        return selected.sorted { $0.lowerBound < $1.lowerBound }
    }

    @available(macOS 26.4, *)
    func attributedTextPreservingTerms(in text: String) -> AttributedString? {
        let ranges = protectedRanges(in: text)
        guard !ranges.isEmpty else { return nil }
        var attributed = AttributedString(text)
        for range in ranges {
            guard let lower = AttributedString.Index(range.lowerBound, within: attributed),
                  let upper = AttributedString.Index(range.upperBound, within: attributed) else { continue }
            attributed[lower..<upper].skipsTranslation = true
        }
        return attributed
    }

    /// OS가 보존 속성을 무시한 경우를 실제 반환 문자열에서 확인한다.
    func preservesRegisteredText(source: String, translated: String) -> Bool {
        let required = protectedRanges(in: source).map { String(source[$0]) }
            .sorted { $0.count > $1.count }
        var occupied: [Range<String.Index>] = []
        for term in required {
            var searchStart = translated.startIndex
            var found = false
            while searchStart < translated.endIndex,
                  let range = translated.range(of: term, options: .literal, range: searchStart..<translated.endIndex) {
                if Self.hasWordBoundaries(range, term: term, in: translated),
                   !occupied.contains(where: { $0.overlaps(range) }) {
                    occupied.append(range)
                    found = true
                    break
                }
                searchStart = translated.index(after: range.lowerBound)
            }
            if !found { return false }
        }
        return true
    }

    private static func hasWordBoundaries(_ range: Range<String.Index>, term: String, in text: String) -> Bool {
        if let first = term.first, isWordCharacter(first), range.lowerBound > text.startIndex,
           isWordCharacter(text[text.index(before: range.lowerBound)]) { return false }
        if let last = term.last, isWordCharacter(last), range.upperBound < text.endIndex,
           isWordCharacter(text[range.upperBound]) { return false }
        return true
    }

    private static func isWordCharacter(_ character: Character) -> Bool {
        character.unicodeScalars.contains { scalar in
            // 한중일 표기는 공백 없는 문장 안에서도 정확한 용어 부분 일치를 허용한다.
            switch scalar.value {
            case 0x1100...0x11ff, 0x3040...0x30ff, 0x3100...0x318f,
                 0x31a0...0x31bf, 0x31f0...0x31ff, 0x3400...0x4dbf,
                 0x4e00...0x9fff, 0xa960...0xa97f, 0xac00...0xd7ff,
                 0xf900...0xfaff, 0xff66...0xff9d, 0x20000...0x323af:
                return false
            default:
                switch scalar.properties.generalCategory {
                case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter,
                     .decimalNumber, .letterNumber, .otherNumber, .nonspacingMark, .spacingMark,
                     .enclosingMark, .connectorPunctuation:
                    return true
                default:
                    return false
                }
            }
        }
    }
}
