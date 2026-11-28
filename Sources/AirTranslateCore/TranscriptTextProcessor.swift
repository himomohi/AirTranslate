import Foundation

package struct TranscriptUnit: Equatable {
    package var separatorBefore: String
    package var text: String

    package init(separatorBefore: String, text: String) {
        self.separatorBefore = separatorBefore
        self.text = text
    }
}

package struct RecentCommittedReplay: Equatable {
    package let committedText: String
    package let tailText: String
}

package enum TranscriptTextProcessor {
    private static let committedRevisionSearchLimit = 2
    private static let committedReplayPrefixSearchLimit = 4
    private static let minimumCommittedReplayPrefixUnits = 2
    private static let sentenceBoundaryRegex = try! NSRegularExpression(pattern: #"([.!?。！？]+)\s+"#)
    private static let koreanSentenceBoundaryRegex = try! NSRegularExpression(
        pattern: #"(습니다|니다|어요|아요|세요|군요|네요|죠|지요|다)\s+"#
    )
    private static let paragraphSeparatorRegex = try! NSRegularExpression(pattern: #"[ \t]*\n{2,}[ \t]*"#)
    private static let lettersAndDigits = CharacterSet.letters.union(.decimalDigits)
    private static let tokenAllowedCharacters = CharacterSet.letters
        .union(.decimalDigits)
        .union(.whitespacesAndNewlines)

    package static func organizeTranscript(_ text: String, languageID: String) -> String {
        paragraphParts(from: text)
            .map { organizeParagraph($0, languageID: languageID) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }

    package static func organizeParagraph(_ text: String, languageID: String) -> String {
        var organized = normalizedForComparison(text)
        guard !organized.isEmpty else { return "" }

        organized = Self.sentenceBoundaryRegex.stringByReplacingMatches(
            in: organized,
            range: NSRange(organized.startIndex..., in: organized),
            withTemplate: "$1\n"
        )

        if languageID == "ko-KR" {
            organized = Self.koreanSentenceBoundaryRegex.stringByReplacingMatches(
                in: organized,
                range: NSRange(organized.startIndex..., in: organized),
                withTemplate: "$1\n"
            )
        }

        return organized
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    package static func paragraphParts(from text: String) -> [String] {
        let marker = "\u{1E}"
        let lineNormalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let normalized = Self.paragraphSeparatorRegex.stringByReplacingMatches(
            in: lineNormalized,
            range: NSRange(lineNormalized.startIndex..., in: lineNormalized),
            withTemplate: marker
        )

        return normalized
            .components(separatedBy: marker)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    package static func displayTail(
        from text: String,
        maxCharacters: Int,
        overflowMarker: String = "..."
    ) -> String {
        guard maxCharacters > 0, text.count > maxCharacters else { return text }

        let tailStart = text.index(text.endIndex, offsetBy: -maxCharacters)
        let overflowLimit = maxCharacters + max(12, maxCharacters / 4)
        if let previousBoundary = text[..<tailStart].lastIndex(of: "\n") {
            let displayStart = text.index(after: previousBoundary)
            if text[displayStart...].count <= overflowLimit {
                return overflowMarker + "\n" + text[displayStart...]
            }
        }

        let minimumTailStart = text.index(text.endIndex, offsetBy: -(maxCharacters * 3 / 4))
        let tailRange = tailStart..<text.endIndex
        let boundary = text[tailRange].firstIndex(of: "\n")
        let displayStart = boundary.map { text.index(after: $0) }

        if let displayStart, displayStart <= minimumTailStart {
            return overflowMarker + "\n" + text[displayStart...]
        }

        return overflowMarker + "\n" + text[tailStart...]
    }

    package static func incomingTailAfterRecentCommittedReplay(
        _ incoming: String,
        committedText: String,
        languageID: String
    ) -> RecentCommittedReplay? {
        let replayedText = organizeTranscript(incoming, languageID: languageID)
        let incomingUnits = transcriptUnits(from: replayedText)
        guard incomingUnits.count >= Self.minimumCommittedReplayPrefixUnits else { return nil }

        var committedUnits = transcriptUnits(from: committedText)
        guard committedUnits.count >= Self.minimumCommittedReplayPrefixUnits else { return nil }

        let maxReplayCount = min(
            Self.committedReplayPrefixSearchLimit,
            incomingUnits.count,
            committedUnits.count
        )
        guard maxReplayCount >= Self.minimumCommittedReplayPrefixUnits else { return nil }

        for replayCount in stride(
            from: maxReplayCount,
            through: Self.minimumCommittedReplayPrefixUnits,
            by: -1
        ) {
            let committedStartIndex = committedUnits.count - replayCount
            let committedReplayUnits = Array(committedUnits[committedStartIndex...])
            let incomingReplayUnits = Array(incomingUnits.prefix(replayCount))

            guard !hasParagraphBoundaryInsideReplay(committedReplayUnits),
                  !hasParagraphBoundaryInsideReplay(incomingReplayUnits)
            else {
                continue
            }

            let replayPairs = Array(zip(incomingReplayUnits, committedReplayUnits))
            guard replayPairs.allSatisfy({
                normalizedForComparison($0.text) == normalizedForComparison($1.text)
                    || isLikelyRecentTranscriptRevision($0.text, of: $1.text, allowsExactRepeat: false)
            }) else {
                continue
            }

            for (offset, pair) in replayPairs.enumerated() {
                committedUnits[committedStartIndex + offset].text = preferredCommittedRevision(
                    existing: pair.1.text,
                    incoming: pair.0.text
                )
            }

            let tailUnits = Array(incomingUnits.dropFirst(replayCount))
            return RecentCommittedReplay(
                committedText: transcriptText(from: committedUnits),
                tailText: transcriptText(from: tailUnits).trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }

        return nil
    }

    package static func committedTextByReplacingRevision(
        with text: String,
        committedText: String,
        languageID: String,
        allowsBackfill: Bool
    ) -> String? {
        let revisedText = organizeTranscript(text, languageID: languageID)
        let incomingUnits = transcriptUnits(from: revisedText)
        guard !incomingUnits.isEmpty else { return nil }

        var committedUnits = transcriptUnits(from: committedText)
        guard !committedUnits.isEmpty else { return nil }

        if incomingUnits.count > 1 {
            guard incomingUnits.count <= committedUnits.count else { return nil }

            let suffixStartIndex = committedUnits.count - incomingUnits.count
            let suffixPairs = zip(incomingUnits, committedUnits[suffixStartIndex...])
            guard suffixPairs.allSatisfy({
                isLikelyRecentTranscriptRevision($0.text, of: $1.text, allowsExactRepeat: false)
                    || normalizedForComparison($0.text) == normalizedForComparison($1.text)
            }) else {
                return nil
            }
            guard suffixPairs.contains(where: {
                normalizedForComparison($0.text) != normalizedForComparison($1.text)
            }) else {
                return nil
            }

            for (offset, incomingUnit) in incomingUnits.enumerated() {
                let index = suffixStartIndex + offset
                committedUnits[index].text = preferredCommittedRevision(
                    existing: committedUnits[index].text,
                    incoming: incomingUnit.text
                )
            }
            return transcriptText(from: committedUnits)
        }

        guard let incomingUnit = incomingUnits.first else { return nil }

        let tailIndex = committedUnits.count - 1
        let firstSearchIndex = allowsBackfill
            ? max(0, committedUnits.count - Self.committedRevisionSearchLimit)
            : tailIndex

        for index in stride(from: tailIndex, through: firstSearchIndex, by: -1) {
            if index < tailIndex, committedUnits[tailIndex].separatorBefore == "\n\n" {
                break
            }

            let existingText = committedUnits[index].text
            let isTail = index == tailIndex
            guard isLikelyRecentTranscriptRevision(
                incomingUnit.text,
                of: existingText,
                allowsExactRepeat: isTail
            ) else {
                continue
            }

            committedUnits[index].text = preferredCommittedRevision(
                existing: existingText,
                incoming: incomingUnit.text
            )
            return transcriptText(from: committedUnits)
        }

        return nil
    }

    package static func incomingTailAfterCommittedText(
        _ incoming: String,
        committedText: String,
        allowsCommittedReplay: Bool
    ) -> String? {
        let normalizedCommitted = normalizedForComparison(committedText)
        let normalizedIncoming = normalizedForComparison(incoming)
        guard isWholeTextPrefix(normalizedCommitted, of: normalizedIncoming) else {
            return nil
        }

        guard normalizedIncoming != normalizedCommitted else {
            if allowsCommittedReplay,
               transcriptUnits(from: incoming).count > 1 || shouldSuppressExactRecentRepeat(normalizedIncoming) {
                return ""
            }

            return nil
        }

        guard let tailStart = originalIndex(
            in: incoming,
            afterNormalizedPrefix: normalizedCommitted
        ) else {
            return nil
        }

        return String(incoming[tailStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    package static func isRevisionOfCurrentPartial(current: String, incoming: String) -> Bool {
        let normalizedCurrent = normalizedForComparison(current)
        let normalizedIncoming = normalizedForComparison(incoming)
        guard !normalizedCurrent.isEmpty, !normalizedIncoming.isEmpty else {
            return false
        }

        if normalizedIncoming == normalizedCurrent
            || isWholeTextPrefix(normalizedCurrent, of: normalizedIncoming)
            || isWholeTextPrefix(normalizedIncoming, of: normalizedCurrent)
            || isPrefixEndingInsideToken(normalizedCurrent, of: normalizedIncoming)
            || isPrefixEndingInsideToken(normalizedIncoming, of: normalizedCurrent) {
            return true
        }

        let sharedPrefixLength = commonPrefixLength(normalizedCurrent, normalizedIncoming)
        let shorterLength = min(normalizedCurrent.count, normalizedIncoming.count)
        if isLikelyEastAsianRevision(normalizedIncoming, of: normalizedCurrent) {
            return true
        }
        return shorterLength >= 12 && sharedPrefixLength * 2 >= shorterLength
    }

    package static func preferredPartialText(current: String, incoming: String) -> String {
        let normalizedCurrent = normalizedForComparison(current)
        let normalizedIncoming = normalizedForComparison(incoming)

        if normalizedCurrent.count > normalizedIncoming.count + 2 {
            return current
        }

        return incoming
    }

    package static func isVolatileFragmentSuperseded(current: String, incoming: String) -> Bool {
        let normalizedCurrent = normalizedForComparison(current)
        let normalizedIncoming = normalizedForComparison(incoming)
        guard containsJapaneseKana(normalizedCurrent),
              containsEastAsianScript(normalizedIncoming)
        else {
            return false
        }
        guard transcriptUnits(from: normalizedCurrent).count == 1,
              transcriptUnits(from: normalizedIncoming).count == 1
        else {
            return false
        }
        guard normalizedCurrent.count <= 8,
              normalizedIncoming.count >= max(5, normalizedCurrent.count + 2),
              !hasTerminalPunctuation(normalizedCurrent)
        else {
            return false
        }

        return true
    }

    package static func shouldAppendCommittedPartial(
        _ partial: String,
        to committedText: String,
        pendingParagraphBreak: Bool
    ) -> Bool {
        let normalizedPartial = normalizedForComparison(partial)
        guard !normalizedPartial.isEmpty else { return false }

        guard !committedTranscriptAlreadyMatches(partial, in: committedText) else { return false }

        let partialUnits = transcriptUnits(from: partial)
        let committedUnits = transcriptUnits(from: committedText)
        guard partialUnits.count == 1,
              let partialUnit = partialUnits.first,
              let lastCommittedUnit = committedUnits.last
        else {
            return true
        }

        let normalizedPartialUnit = normalizedForComparison(partialUnit.text)
        let normalizedLastUnit = normalizedForComparison(lastCommittedUnit.text)
        return normalizedPartialUnit != normalizedLastUnit
            || pendingParagraphBreak
            || !shouldSuppressExactRecentRepeat(normalizedPartialUnit)
    }

    package static func transcriptUnits(from text: String) -> [TranscriptUnit] {
        var units: [TranscriptUnit] = []
        var buffer = ""
        var newlineCount = 0
        var separatorForNext = ""
        let normalizedText = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        func appendBufferedUnit() {
            let trimmedText = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedText.isEmpty else {
                buffer = ""
                return
            }

            let separator = units.isEmpty ? "" : (separatorForNext.isEmpty ? "\n" : separatorForNext)
            units.append(TranscriptUnit(separatorBefore: separator, text: trimmedText))
            buffer = ""
            separatorForNext = ""
        }

        for character in normalizedText {
            if character == "\n" {
                appendBufferedUnit()
                newlineCount += 1
                continue
            }

            if newlineCount > 0 {
                separatorForNext = newlineCount >= 2 ? "\n\n" : "\n"
                newlineCount = 0
            }
            buffer.append(character)
        }

        appendBufferedUnit()
        return units
    }

    package static func transcriptText(from units: [TranscriptUnit]) -> String {
        units.enumerated().map { index, unit in
            if index == 0 {
                return unit.text
            }

            let separator = unit.separatorBefore.isEmpty ? "\n" : unit.separatorBefore
            return separator + unit.text
        }
        .joined()
    }

    package static func normalizedForComparison(_ text: String) -> String {
        var scalars = String.UnicodeScalarView()
        scalars.reserveCapacity(text.unicodeScalars.count)
        var pendingSpace = false
        var sawNonWhitespace = false
        for scalar in text.unicodeScalars {
            if scalar.properties.isWhitespace {
                if sawNonWhitespace {
                    pendingSpace = true
                }
            } else {
                if pendingSpace {
                    scalars.append(" ")
                    pendingSpace = false
                }
                scalars.append(scalar)
                sawNonWhitespace = true
            }
        }
        return String(scalars)
    }

    package static func isCompatibleLiveSource(current: String, requested: String) -> Bool {
        let currentText = current.trimmingCharacters(in: .whitespacesAndNewlines)
        let requestedText = requested.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !requestedText.isEmpty else { return currentText.isEmpty }
        if currentText == requestedText || currentText.hasPrefix(requestedText) {
            return true
        }

        let normalizedCurrentText = normalizedForComparison(currentText)
        let normalizedRequestedText = normalizedForComparison(requestedText)
        return normalizedCurrentText == normalizedRequestedText
            || normalizedCurrentText.hasPrefix(normalizedRequestedText)
    }

    package static func isLikelyRecentTranscriptRevision(
        _ incoming: String,
        of existing: String,
        allowsExactRepeat: Bool
    ) -> Bool {
        let normalizedIncoming = normalizedForComparison(incoming)
        let normalizedExisting = normalizedForComparison(existing)
        guard normalizedIncoming != normalizedExisting else {
            return allowsExactRepeat && shouldSuppressExactRecentRepeat(normalizedIncoming)
        }
        guard !normalizedIncoming.isEmpty, !normalizedExisting.isEmpty else { return false }

        if isWholeTextPrefix(normalizedIncoming, of: normalizedExisting)
            || isWholeTextPrefix(normalizedExisting, of: normalizedIncoming)
            || isPrefixEndingInsideToken(normalizedIncoming, of: normalizedExisting)
            || isPrefixEndingInsideToken(normalizedExisting, of: normalizedIncoming) {
            return true
        }
        if isLikelyEastAsianRevision(normalizedIncoming, of: normalizedExisting) {
            return true
        }
        guard normalizedIncoming.count >= 12, normalizedExisting.count >= 12 else { return false }

        let incomingTokens = transcriptTokens(from: normalizedIncoming)
        let existingTokens = transcriptTokens(from: normalizedExisting)
        let smallerCount = min(incomingTokens.count, existingTokens.count)
        guard smallerCount >= 5 else { return false }

        if incomingTokens == existingTokens {
            return true
        }

        let sharedPrefixLength = commonPrefixLength(normalizedIncoming, normalizedExisting)
        let overlapCount = orderedTokenOverlapCount(incomingTokens, existingTokens)
        let overlapRatio = Double(overlapCount) / Double(smallerCount)
        let shorterLength = min(normalizedIncoming.count, normalizedExisting.count)
        let longerLength = max(normalizedIncoming.count, normalizedExisting.count)
        let lengthRatio = Double(longerLength) / Double(shorterLength)

        if sharedPrefixLength >= 8,
           overlapCount >= 4,
           overlapRatio >= 0.58,
           lengthRatio <= 2.25 {
            return true
        }

        if overlapCount >= 8,
           overlapRatio >= 0.74,
           lengthRatio <= 1.35 {
            return true
        }

        return overlapCount >= 5
            && overlapRatio >= 0.78
            && lengthRatio <= 1.6
    }

    private static func isLikelyEastAsianRevision(_ incoming: String, of existing: String) -> Bool {
        guard containsEastAsianScript(incoming), containsEastAsianScript(existing) else { return false }
        let incomingLength = incoming.count
        let existingLength = existing.count
        let shorterLength = min(incomingLength, existingLength)
        let longerLength = max(incomingLength, existingLength)
        guard shorterLength >= 10 else { return false }
        guard Double(longerLength) / Double(shorterLength) <= 1.45 else { return false }

        let incomingGrams = characterNGrams(incoming, size: 2)
        let existingGrams = characterNGrams(existing, size: 2)
        let smallerCount = min(incomingGrams.count, existingGrams.count)
        guard smallerCount >= 8 else { return false }

        let overlapCount = multisetOverlapCount(incomingGrams, existingGrams)
        return Double(overlapCount) / Double(smallerCount) >= 0.72
    }

    private static func characterNGrams(_ text: String, size: Int) -> [String] {
        let characters = Array(text)
        guard characters.count >= size else { return [] }

        return (0...(characters.count - size)).map { index in
            String(characters[index..<(index + size)])
        }
    }

    private static func multisetOverlapCount(_ lhs: [String], _ rhs: [String]) -> Int {
        var counts: [String: Int] = [:]
        for item in lhs {
            counts[item, default: 0] += 1
        }

        var overlapCount = 0
        for item in rhs {
            guard let count = counts[item], count > 0 else { continue }
            overlapCount += 1
            counts[item] = count - 1
        }
        return overlapCount
    }

    package static func isWholeTextPrefix(_ prefix: String, of text: String) -> Bool {
        guard !prefix.isEmpty, text.hasPrefix(prefix) else { return false }
        guard text != prefix else { return true }
        guard let nextCharacter = text.dropFirst(prefix.count).first,
              let previousCharacter = prefix.last
        else {
            return true
        }

        return !isLetterOrNumber(previousCharacter) || !isLetterOrNumber(nextCharacter)
    }

    package static func isPrefixEndingInsideToken(_ prefix: String, of text: String) -> Bool {
        guard !prefix.isEmpty, text.hasPrefix(prefix), text != prefix else { return false }
        guard let nextCharacter = text.dropFirst(prefix.count).first,
              let previousCharacter = prefix.last
        else {
            return false
        }

        return isLetterOrNumber(previousCharacter) && isLetterOrNumber(nextCharacter)
    }

    private static func containsEastAsianScript(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x3040...0x30FF, 0x3400...0x9FFF, 0xAC00...0xD7AF:
                return true
            default:
                return false
            }
        }
    }

    private static func containsJapaneseKana(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x3040...0x30FF:
                return true
            default:
                return false
            }
        }
    }

    private static func hasTerminalPunctuation(_ text: String) -> Bool {
        guard let lastCharacter = text.trimmingCharacters(in: .whitespacesAndNewlines).last else {
            return false
        }

        return ".!?。！？".contains(lastCharacter)
    }

    private static func hasParagraphBoundaryInsideReplay(_ units: [TranscriptUnit]) -> Bool {
        units.dropFirst().contains { $0.separatorBefore == "\n\n" }
    }

    private static func originalIndex(
        in text: String,
        afterNormalizedPrefix normalizedPrefix: String
    ) -> String.Index? {
        guard !normalizedPrefix.isEmpty else { return text.startIndex }

        var normalizedText = ""
        var previousWasWhitespace = true

        for index in text.indices {
            let character = text[index]
            let nextIndex = text.index(after: index)

            if character.isWhitespace {
                guard !previousWasWhitespace else { continue }
                previousWasWhitespace = true
                normalizedText.append(" ")
            } else {
                previousWasWhitespace = false
                normalizedText.append(character)
            }

            guard normalizedPrefix.hasPrefix(normalizedText) else {
                return nil
            }

            if normalizedText == normalizedPrefix {
                return nextIndex
            }
        }

        return nil
    }

    private static func preferredCommittedRevision(existing: String, incoming: String) -> String {
        let normalizedExisting = normalizedForComparison(existing)
        let normalizedIncoming = normalizedForComparison(incoming)

        if normalizedIncoming.count * 5 >= normalizedExisting.count * 3 {
            return incoming
        }

        return existing
    }

    private static func orderedTokenOverlapCount(_ lhs: [String], _ rhs: [String]) -> Int {
        guard !lhs.isEmpty, !rhs.isEmpty else { return 0 }

        var previousRow = Array(repeating: 0, count: rhs.count + 1)
        for lhsToken in lhs {
            var currentRow = Array(repeating: 0, count: rhs.count + 1)
            for (rhsIndex, rhsToken) in rhs.enumerated() {
                if lhsToken == rhsToken {
                    currentRow[rhsIndex + 1] = previousRow[rhsIndex] + 1
                } else {
                    currentRow[rhsIndex + 1] = max(previousRow[rhsIndex + 1], currentRow[rhsIndex])
                }
            }
            previousRow = currentRow
        }

        return previousRow[rhs.count]
    }

    private static func transcriptTokens(from text: String) -> [String] {
        let filteredText = String(text.unicodeScalars.map { scalar in
            tokenAllowedCharacters.contains(scalar) ? Character(scalar) : " "
        })

        return filteredText
            .lowercased()
            .split(separator: " ")
            .map(String.init)
            .filter { $0.count > 1 }
    }

    package static func committedTranscriptAlreadyMatches(_ text: String, in committedText: String) -> Bool {
        let committed = committedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !committed.isEmpty else { return false }

        let normalizedCommitted = normalizedForComparison(committed)
        let normalizedText = normalizedForComparison(text)
        guard !normalizedText.isEmpty else { return false }

        return normalizedCommitted == normalizedText
            && (transcriptUnits(from: committed).count > 1 || shouldSuppressExactRecentRepeat(normalizedText))
    }

    private static func shouldSuppressExactRecentRepeat(_ normalizedText: String) -> Bool {
        normalizedText.count >= 15
            && transcriptTokens(from: normalizedText).count >= 4
    }

    private static func isLetterOrNumber(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy { lettersAndDigits.contains($0) }
    }

    private static func commonPrefixLength(_ lhs: String, _ rhs: String) -> Int {
        var length = 0
        for (leftCharacter, rightCharacter) in zip(lhs, rhs) {
            guard leftCharacter == rightCharacter else { break }
            length += 1
        }
        return length
    }
}
