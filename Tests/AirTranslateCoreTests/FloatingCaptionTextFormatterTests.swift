import Testing
@testable import AirTranslate

@Suite
struct FloatingCaptionTextFormatterTests {
    @Test
    func floatingCaptionTailWrapsLongEnglishCaptionWhileKeepingRecentLines() {
        let text = """
        This lecture introduces depreciation methods and deferred tax accounting before moving into practice questions for the next topic.
        """

        let caption = text.floatingCaptionTail(maxLines: 3)
        let lines = caption.split(separator: "\n", omittingEmptySubsequences: true)

        #expect(lines.count > 1)
        #expect(lines.count <= 3)
        #expect(caption.contains("deferred tax"))
    }

    @Test
    func floatingCaptionTailKeepsMediumEnglishCaptionOnOneLine() {
        let text = "Why you think we running up for truth hurts, homie."

        let caption = text.floatingCaptionTail(
            maxLines: 2,
            lineWidthUnits: FloatingCaptionTextSize.medium.floatingLineWidthUnits
        )

        #expect(caption == text)
    }

    @Test
    func floatingCaptionTailUsesFontSizeWidthBudget() {
        let text = "Why you think we running up for the truth hurts homie tough love. Tough love keeps the caption readable."

        for size in FloatingCaptionTextSize.allCases {
            let caption = text.floatingCaptionTail(
                maxLines: 4,
                lineWidthUnits: size.floatingLineWidthUnits
            )
            let lines = caption.split(separator: "\n", omittingEmptySubsequences: true)

            #expect(!lines.isEmpty)
            #expect(lines.allSatisfy { $0.floatingCaptionTestDisplayWidth <= size.floatingLineWidthUnits + 0.001 })
        }
    }

    @Test
    func floatingCaptionTailWrapsCJKTextWithoutWhitespace() {
        let text = "감가상각비와이연법인세회계처리를연속해서설명하는강의문장이길어져도자막창에서는읽기좋게나뉘어야합니다감가상각비와이연법인세회계처리를연속해서설명하는강의문장이길어져도자막창에서는읽기좋게나뉘어야합니다"

        let caption = text.floatingCaptionTail(maxLines: 3)
        let lines = caption.split(separator: "\n", omittingEmptySubsequences: true)

        #expect(lines.count > 1)
        #expect(lines.count <= 3)
        #expect(lines.allSatisfy { !$0.isEmpty })
    }

    @Test
    func floatingCaptionTailBreaksAfterCommonSentencePunctuation() {
        let text = "First idea appears. Second idea follows? Third idea lands!"

        let caption = text.floatingCaptionTail(maxLines: 3)

        #expect(caption == """
        First idea appears.
        Second idea follows?
        Third idea lands!
        """)
    }

    @Test
    func floatingCaptionTailPreservesDecimalNumbersAndNormalizesWhitespaceBetweenSentences() {
        let text = "Pi is 3.14 today.   Next sentence!\t\n中文句子。？  끝입니다."

        let caption = text.floatingCaptionTail(maxLines: 6, lineWidthUnits: 60)

        #expect(caption.contains("Pi is 3.14 today."))
        #expect(caption.contains("Next sentence!"))
        #expect(caption.contains("끝입니다."))
        #expect(!caption.contains("3.\n14"))
    }
}

private extension Substring {
    var floatingCaptionTestDisplayWidth: Double {
        reduce(0) { width, character in
            if character.isWhitespace {
                return width + 0.45
            }

            guard let scalar = character.unicodeScalars.first else {
                return width + 1
            }

            return width + (scalar.isASCII ? 0.62 : 1)
        }
    }
}
