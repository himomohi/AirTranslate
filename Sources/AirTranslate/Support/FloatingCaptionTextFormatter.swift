import AppKit
import CoreText
import Foundation

private enum FloatingCaptionTextLayout {
    static let defaultLineWidthUnits = 32.0
    static let scanLineMultiplier = 4

    static func displayWidth(of character: Character) -> Double {
        if character.isWhitespace {
            return 0.45
        }

        guard let scalar = character.unicodeScalars.first else {
            return 1
        }

        return scalar.isASCII ? 0.62 : 1
    }
}

extension String {
    /// 실제 렌더링 글꼴로 줄을 나눠 넓은 영문·CJK·이모지가 끝에서 잘리지 않게 한다.
    func floatingCaptionTail(maxLines: Int, availableWidth: CGFloat, font: NSFont) -> String {
        guard availableWidth.isFinite, availableWidth > 0 else {
            return floatingCaptionTail(maxLines: maxLines)
        }
        let count = max(1, maxLines)
        let text = trimmingCharacters(in: .whitespacesAndNewlines).floatingCaptionSentenceBreaks()
        let bounded = String(text.boundedSuffix(maxCharacters: count * 72 * FloatingCaptionTextLayout.scanLineMultiplier))
        var lines: [String] = []
        for paragraph in bounded.components(separatedBy: .newlines) where !paragraph.isEmpty {
            let string = paragraph as NSString
            let attributed = NSAttributedString(string: paragraph, attributes: [.font: font])
            let typesetter = CTTypesetterCreateWithAttributedString(attributed)
            var offset = 0
            while offset < string.length {
                let proposed = CTTypesetterSuggestLineBreak(typesetter, offset, max(1, availableWidth - 4))
                let length = proposed > 0 ? proposed : string.rangeOfComposedCharacterSequence(at: offset).length
                let line = string.substring(with: NSRange(location: offset, length: length))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !line.isEmpty { lines.append(line) }
                offset += length
            }
        }
        return lines.suffix(count).joined(separator: "\n")
    }

    func floatingCaptionTail(
        maxLines: Int,
        lineWidthUnits: Double = FloatingCaptionTextLayout.defaultLineWidthUnits
    ) -> String {
        let maxLines = max(1, maxLines)
        let lineWidthUnits = max(1, lineWidthUnits)
        let trimmedText = trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return "" }
        let scanCharacters = maxLines * 72 * FloatingCaptionTextLayout.scanLineMultiplier
        let captionText = trimmedText.floatingCaptionSentenceBreaks()
        let scanText = String(captionText.boundedSuffix(maxCharacters: scanCharacters))

        let logicalLines = scanText.floatingCaptionWrappedLines(
            maxLineWidth: lineWidthUnits
        )

        return logicalLines
            .suffix(maxLines)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func boundedSuffix(maxCharacters: Int) -> Substring {
        guard maxCharacters > 0,
              let start = index(endIndex, offsetBy: -maxCharacters, limitedBy: startIndex)
        else {
            return self[startIndex..<endIndex]
        }

        return self[start..<endIndex]
    }

    private func floatingCaptionSentenceBreaks() -> String {
        replacingOccurrences(
            of: #"(?<!\d)([.!?。！？])\s+(?=\S)"#,
            with: "$1\n",
            options: .regularExpression
        )
    }

    private func floatingCaptionWrappedLines(maxLineWidth: Double) -> [String] {
        components(separatedBy: .newlines)
            .flatMap { paragraph in
                paragraph.floatingCaptionWrappedParagraph(maxLineWidth: maxLineWidth)
            }
            .filter { !$0.isEmpty }
    }

    private func floatingCaptionWrappedParagraph(maxLineWidth: Double) -> [String] {
        let paragraph = trimmingCharacters(in: .whitespacesAndNewlines)
        guard !paragraph.isEmpty else { return [] }

        var lines: [String] = []
        var currentLine = ""
        var currentWidth = 0.0

        for word in paragraph.split(whereSeparator: \.isWhitespace) {
            let word = String(word)
            let wordWidth = word.floatingCaptionDisplayWidth

            if wordWidth > maxLineWidth {
                if !currentLine.isEmpty {
                    lines.append(currentLine)
                    currentLine = ""
                    currentWidth = 0
                }
                lines.append(contentsOf: word.floatingCaptionSplitLongToken(maxLineWidth: maxLineWidth))
                continue
            }

            let separatorWidth = currentLine.isEmpty ? 0 : FloatingCaptionTextLayout.displayWidth(of: " ")
            let nextWidth = currentWidth + separatorWidth + wordWidth
            if !currentLine.isEmpty, nextWidth > maxLineWidth {
                lines.append(currentLine)
                currentLine = word
                currentWidth = wordWidth
            } else {
                if !currentLine.isEmpty {
                    currentLine += " "
                    currentWidth += separatorWidth
                }
                currentLine += word
                currentWidth += wordWidth
            }
        }

        if !currentLine.isEmpty {
            lines.append(currentLine)
        }

        return lines
    }

    private var floatingCaptionDisplayWidth: Double {
        reduce(0) { width, character in
            width + FloatingCaptionTextLayout.displayWidth(of: character)
        }
    }

    private func floatingCaptionSplitLongToken(maxLineWidth: Double) -> [String] {
        var lines: [String] = []
        var currentLine = ""
        var currentWidth = 0.0

        for character in self {
            let characterWidth = FloatingCaptionTextLayout.displayWidth(of: character)
            if !currentLine.isEmpty, currentWidth + characterWidth > maxLineWidth {
                lines.append(currentLine)
                currentLine = ""
                currentWidth = 0
            }

            currentLine.append(character)
            currentWidth += characterWidth
        }

        if !currentLine.isEmpty {
            lines.append(currentLine)
        }

        return lines
    }
}
