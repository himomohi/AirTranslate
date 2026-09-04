import Foundation

struct TranslationGlossaryEntry: Equatable, Sendable {
    let source: String
    let target: String
}

struct TranslationQualityContext: Equatable, Sendable {
    static let maximumPresentationContextCharacters = 1_000
    static let maximumGlossaryEntries = 50
    static let maximumGlossaryTermCharacters = 120
    private static let separators = ["=>", "->", "→", "="]

    let presentationContext: String
    let glossaryEntries: [TranslationGlossaryEntry]
    private let replacementEntries: [TranslationGlossaryEntry]

    init(presentationContext: String, glossaryText: String) {
        self.presentationContext = String(
            presentationContext
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .prefix(Self.maximumPresentationContextCharacters)
        )
        let parsedEntries = Self.parseGlossary(glossaryText)
        glossaryEntries = parsedEntries
        replacementEntries = parsedEntries.sorted { left, right in
            left.source.count > right.source.count
        }
    }

    var sourceTerms: [String] {
        glossaryEntries.map(\.source)
    }

    func applyingTerminology(to text: String) -> String {
        let matches = replacementEntries
            .flatMap { entry in
                matchingRanges(for: entry, in: text).map { range in
                    (range: range, entry: entry)
                }
            }
            .sorted { left, right in
                if left.range.lowerBound == right.range.lowerBound {
                    return left.entry.source.count > right.entry.source.count
                }
                return left.range.lowerBound < right.range.lowerBound
            }

        guard !matches.isEmpty else { return text }

        var result = ""
        var cursor = text.startIndex
        for match in matches where match.range.lowerBound >= cursor {
            result.append(contentsOf: text[cursor..<match.range.lowerBound])
            result.append(match.entry.target)
            cursor = match.range.upperBound
        }
        result.append(contentsOf: text[cursor...])
        return result
    }

    func enhancing(instructions baseInstructions: String, target: LanguageOption) -> String {
        var guidance = [
            baseInstructions,
            "This is live simultaneous interpretation for an audience. Translate the speaker's meaning naturally and concisely instead of following source-language word order.",
            "Preserve names, numbers, acronyms, and business terminology. Omit empty fillers such as uh, um, and huh when they add no meaning.",
        ]

        if target.id.lowercased().hasPrefix("ja") {
            guidance.append("Use polite, natural Japanese suitable for projected captions, with concise です/ます style where appropriate.")
        }

        if !presentationContext.isEmpty {
            guidance.append("Presentation context: \(presentationContext)")
        }

        if !glossaryEntries.isEmpty {
            let terms = glossaryEntries
                .map { "- \($0.source) => \($0.target)" }
                .joined(separator: "\n")
            guidance.append("Use these exact target terms whenever the matching source term appears:\n\(terms)")
        }

        guidance.append("Return only the interpretation. Do not add explanations, labels, or facts that the speaker did not say.")
        return guidance.joined(separator: "\n\n")
    }

    private static func parseGlossary(_ text: String) -> [TranslationGlossaryEntry] {
        var entries: [TranslationGlossaryEntry] = []
        var indexBySource: [String: Int] = [:]

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            guard let separatorRange = separators
                .compactMap({ separator in
                    line.range(of: separator).map { (range: $0, length: separator.count) }
                })
                .min(by: { left, right in
                    if left.range.lowerBound == right.range.lowerBound {
                        return left.length > right.length
                    }
                    return left.range.lowerBound < right.range.lowerBound
                })?
                .range
            else { continue }

            let source = line[..<separatorRange.lowerBound]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let target = line[separatorRange.upperBound...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !source.isEmpty, !target.isEmpty else { continue }
            guard source.count <= maximumGlossaryTermCharacters,
                  target.count <= maximumGlossaryTermCharacters
            else { continue }

            let entry = TranslationGlossaryEntry(source: source, target: target)
            let normalizedSource = source.folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: .current
            )
            if let existingIndex = indexBySource[normalizedSource] {
                entries[existingIndex] = entry
            } else {
                indexBySource[normalizedSource] = entries.count
                entries.append(entry)
            }

            if entries.count >= maximumGlossaryEntries {
                break
            }
        }

        return entries
    }

    private func matchingRanges(
        for entry: TranslationGlossaryEntry,
        in text: String
    ) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        var searchStart = text.startIndex

        while searchStart < text.endIndex,
              let range = text.range(
                  of: entry.source,
                  options: [.caseInsensitive],
                  range: searchStart..<text.endIndex
              ) {
            if Self.hasTermBoundaries(range, in: text) {
                ranges.append(range)
            }
            searchStart = range.upperBound
        }

        return ranges
    }

    private static func hasTermBoundaries(
        _ range: Range<String.Index>,
        in text: String
    ) -> Bool {
        if range.lowerBound > text.startIndex {
            let previous = text[text.index(before: range.lowerBound)]
            if previous.isLetter || previous.isNumber {
                return false
            }
        }

        if range.upperBound < text.endIndex {
            let next = text[range.upperBound]
            if next.isLetter || next.isNumber {
                return false
            }
        }

        return true
    }
}

enum TranslationQualityPolicy {
    /// Returns nil when the normal low-latency policy should remain in charge.
    static func debounceDelay(
        isEnabled: Bool,
        isFinal: Bool,
        sourceText: String
    ) -> Int? {
        guard isEnabled else { return nil }
        guard !isFinal else { return 0 }

        let trimmedText = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let finalCharacter = trimmedText.last else { return 420 }
        if ".!?。！？".contains(finalCharacter) {
            return 120
        }
        if ",;:、，；：—–".contains(finalCharacter) {
            return 240
        }
        return 420
    }
}
