import Foundation

struct HyMTTranslationOptions: Equatable, Sendable {
    var terminology: [String] = []
    var context: String = ""

    var normalizedTerminology: [String] { Self.parseTerminology(terminology.joined(separator: "\n")) }
    var boundedContext: String { String(context.suffix(800)).trimmingCharacters(in: .whitespacesAndNewlines) }

    // 사전과 문맥이 다른 요청은 같은 문장의 캐시도 공유하지 않는다.
    var cacheID: String {
        (normalizedTerminology + [boundedContext]).map { "\($0.utf8.count):\($0)" }.joined()
    }

    static func parseTerminology(_ text: String) -> [String] {
        var seen = Set<String>()
        return text.split(whereSeparator: \.isNewline).compactMap { raw in
            let term = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !term.isEmpty, term.count <= 80,
                  !term.contains("<｜"), !term.contains("|>"),
                  seen.insert(term.lowercased()).inserted else { return nil }
            return term
        }.prefix(32).map { $0 }
    }

    /// 사용자가 지정한 약어 포함 용어만 대상으로 한다. 화면의 인식 원문은 변경하지 않는다.
    func preparedSource(_ source: String) -> String {
        let terms = normalizedTerminology.filter { $0.range(of: "[A-Z]{2,}", options: .regularExpression) != nil }
        let grouped = Dictionary(grouping: terms, by: Self.soundKey)
        let unambiguous = grouped.compactMapValues { values in values.count == 1 ? values.first : nil }
        guard !unambiguous.isEmpty,
              let regex = try? NSRegularExpression(pattern: "[A-Za-z][A-Za-z0-9]*") else { return source }
        let text = source as NSString
        let words = regex.matches(in: source, range: NSRange(location: 0, length: text.length))
        var replacements: [(NSRange, String)] = []
        var index = 0
        while index < words.count {
            var found: (NSRange, String, Int)?
            // 한 단어로 일치하면 뒤의 I 같은 독립 단어를 더 소비하지 않는다.
            for count in 1...min(5, words.count - index) {
                let range = NSRange(location: words[index].range.location,
                    length: NSMaxRange(words[index + count - 1].range) - words[index].range.location)
                let candidate = text.substring(with: range)
                // 문장 부호를 넘어 서로 다른 문장이나 단어를 합치지 않는다.
                let separators = candidate.filter { !$0.isLetter && !$0.isNumber }
                guard separators.allSatisfy({ $0.isWhitespace || $0 == "-" }),
                      let canonical = unambiguous[Self.soundKey(candidate)],
                      candidate.filter(\.isNumber) == canonical.filter(\.isNumber),
                      count <= canonical.split(whereSeparator: \.isWhitespace).count,
                      Self.soundKey(canonical).count >= 5 else { continue }
                found = (range, canonical, count)
                break
            }
            if let (range, canonical, count) = found {
                if text.substring(with: range) != canonical { replacements.append((range, canonical)) }
                index += count
            } else { index += 1 }
        }
        let result = NSMutableString(string: source)
        for (range, canonical) in replacements.reversed() { result.replaceCharacters(in: range, with: canonical) }
        return result as String
    }

    private static func soundKey(_ text: String) -> String {
        let letters = Array(text.uppercased().unicodeScalars.filter { (65...90).contains($0.value) }.map(Character.init))
        var result = ""
        var previous: Character?
        var index = 0
        while index < letters.count {
            let letter = letters[index]
            let next = index + 1 < letters.count ? letters[index + 1] : " "
            let code: Character?
            switch letter {
            case "A", "E", "I", "O", "U", "Y": code = index == 0 ? letter : nil
            case "B", "P": code = "P"
            case "D", "T": code = "T"
            case "V", "F": code = "F"
            case "Z", "S": code = "S"
            case "C":
                if next == "H" { code = "X"; index += 1 }
                else { code = ["E", "I", "Y"].contains(next) ? "S" : "K" }
            case "G", "Q", "K": code = "K"
            case "H", "W": code = nil
            default: code = letter
            }
            if let code, code != previous { result.append(code); previous = code }
            index += 1
        }
        return result
    }
}

enum HyMTDecodingPolicy: Sendable, CaseIterable, Equatable {
    case stable
    case recommended
}
