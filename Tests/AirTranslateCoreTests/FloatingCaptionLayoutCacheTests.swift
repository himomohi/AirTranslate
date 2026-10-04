import AppKit
import Testing
@testable import AirTranslate

@Suite
@MainActor
struct FloatingCaptionLayoutCacheTests {
    private let sample = "A changing caption keeps exact spacing and Unicode. 한글 자막 日本語 中文 👨‍👩‍👧‍👦."

    @Test
    func identicalInputsReuseTheExactFormattedBytes() {
        let cache = FloatingCaptionLayoutCache()
        let font = NSFont.systemFont(ofSize: 28)
        let first = cache.text(sample, maxLines: 3, availableWidth: 360, font: font, fallbackWidthUnits: 32)
        #expect(!cache.didReuseLastResult)
        let second = cache.text(sample, maxLines: 3, availableWidth: 360, font: font, fallbackWidthUnits: 32)
        #expect(cache.didReuseLastResult)
        #expect(first.utf8.elementsEqual(second.utf8))
        #expect(first.utf8.elementsEqual(sample.floatingCaptionTail(maxLines: 3, availableWidth: 360, font: font).utf8))
        #expect(cache.entryCount == 1)
    }

    @Test
    func everyLayoutInputInvalidatesItsEntry() {
        let baseFont = NSFont.systemFont(ofSize: 28)
        let cases: [(String, Int, CGFloat, NSFont, Double)] = [
            (sample + " Changed.", 3, 360, baseFont, 32),
            (sample, 2, 360, baseFont, 32),
            (sample, 3, 180, baseFont, 32),
            (sample, 3, 360, NSFont.systemFont(ofSize: 40), 32),
            (sample, 3, 360, NSFont.monospacedSystemFont(ofSize: 28, weight: .regular), 32),
            (sample, 3, 360, NSFont.systemFont(ofSize: 28, weight: .bold), 32),
            (sample, 3, 360, baseFont, 18)
        ]
        for (text, lines, width, font, fallback) in cases {
            let cache = FloatingCaptionLayoutCache()
            _ = cache.text(sample, maxLines: 3, availableWidth: 360, font: baseFont, fallbackWidthUnits: 32)
            let actual = cache.text(text, maxLines: lines, availableWidth: width, font: font, fallbackWidthUnits: fallback)
            #expect(!cache.didReuseLastResult)
            #expect(actual.utf8.elementsEqual(reference(text, lines: lines, width: width, font: font, fallback: fallback).utf8))
        }
    }

    @Test
    func descriptorMatrixIsNotReducedToFontNameAndSize() throws {
        let base = try #require(NSFont(name: "Helvetica", size: 28))
        // 크기를 포함한 실제 폰트 행렬을 사용해 이름·28pt 크기는 같고 가로 폭만 다르게 한다.
        var matrix: [CGFloat] = [35, 0, 0, 28, 0, 0]
        let transformedFont = NSFont(name: base.fontName, matrix: &matrix)
        let transformed = try #require(transformedFont)
        #expect(base.fontName == transformed.fontName)
        #expect(base.pointSize == transformed.pointSize)
        #expect(!(base.fontDescriptor.fontAttributes as NSDictionary).isEqual(transformed.fontDescriptor.fontAttributes as NSDictionary))
        let cache = FloatingCaptionLayoutCache()
        _ = cache.text(sample, maxLines: 3, availableWidth: 360, font: base, fallbackWidthUnits: 32)
        let result = cache.text(sample, maxLines: 3, availableWidth: 360, font: transformed, fallbackWidthUnits: 32)
        #expect(!cache.didReuseLastResult)
        #expect(result.utf8.elementsEqual(reference(sample, lines: 3, width: 360, font: transformed, fallback: 32).utf8))
    }

    @Test
    func canonicallyEquivalentInputsDoNotReuseDifferentCodePoints() {
        let cache = FloatingCaptionLayoutCache()
        let font = NSFont.systemFont(ofSize: 24)
        let composed = "Caf\u{00E9} 한글"
        let decomposed = "Cafe\u{0301} 한글"
        #expect(composed == decomposed)
        #expect(!composed.utf8.elementsEqual(decomposed.utf8))
        for text in [composed, decomposed] {
            let actual = cache.text(text, maxLines: 3, availableWidth: 640, font: font, fallbackWidthUnits: 32)
            #expect(!cache.didReuseLastResult)
            #expect(actual.utf8.elementsEqual(reference(text, lines: 3, width: 640, font: font, fallback: 32).utf8))
        }
        #expect(cache.entryCount == 2)
    }

    @Test
    func unicodeLongAndFallbackOutputsMatchTheUncachedFormatter() {
        let texts = [
            "", "  whitespace\n\nkept at boundaries.  ",
            "숫자는 3.14입니다. 다음 문장입니다! 中文日本語 한글 자막입니다.",
            "👨‍👩‍👧‍👦 👩🏽‍💻 🇰🇷 e\u{0301} \u{1100}\u{1161} Zero\u{200D}width.",
            String(repeating: "Long lecture content. 긴 문장과 이모지 🧑🏽‍🚀를 표시합니다. ", count: 300)
        ]
        let font = NSFont.systemFont(ofSize: 30)
        let widths: [CGFloat] = [0, -1, 140, 672, .infinity, .nan]
        for text in texts {
            for width in widths {
                for lines in [1, 3, 5] {
                    let cache = FloatingCaptionLayoutCache()
                    let expected = reference(text, lines: lines, width: width, font: font, fallback: 19)
                    let first = cache.text(text, maxLines: lines, availableWidth: width, font: font, fallbackWidthUnits: 19)
                    let repeated = cache.text(text, maxLines: lines, availableWidth: width, font: font, fallbackWidthUnits: 19)
                    #expect(first.utf8.elementsEqual(expected.utf8))
                    #expect(repeated.utf8.elementsEqual(expected.utf8))
                    #expect(cache.didReuseLastResult)
                }
            }
        }
    }

    @Test
    func fallbackWidthChangesRecomputeWrapping() {
        let cache = FloatingCaptionLayoutCache()
        let font = NSFont.systemFont(ofSize: 28)
        let wide = cache.text(sample, maxLines: 3, availableWidth: 0, font: font, fallbackWidthUnits: 40)
        let narrow = cache.text(sample, maxLines: 3, availableWidth: 0, font: font, fallbackWidthUnits: 12)
        #expect(!cache.didReuseLastResult)
        #expect(wide.utf8.elementsEqual(sample.floatingCaptionTail(maxLines: 3, lineWidthUnits: 40).utf8))
        #expect(narrow.utf8.elementsEqual(sample.floatingCaptionTail(maxLines: 3, lineWidthUnits: 12).utf8))
        #expect(wide != narrow)
    }

    @Test
    func leastRecentlyUsedEntryIsEvictedAndClearRemovesEverything() {
        let cache = FloatingCaptionLayoutCache()
        let font = NSFont.systemFont(ofSize: 24)
        func read(_ text: String) {
            _ = cache.text(text, maxLines: 2, availableWidth: 320, font: font, fallbackWidthUnits: 32)
        }
        read("source")
        read("translation")
        read("source")
        #expect(cache.didReuseLastResult)
        read("next source")
        #expect(!cache.didReuseLastResult)
        #expect(cache.entryCount == FloatingCaptionLayoutCache.maximumEntryCount)
        read("source")
        #expect(cache.didReuseLastResult)
        read("translation")
        #expect(!cache.didReuseLastResult)
        #expect(cache.entryCount == FloatingCaptionLayoutCache.maximumEntryCount)
        cache.removeAll()
        #expect(cache.entryCount == 0)
        #expect(!cache.didReuseLastResult)
        read("source")
        #expect(!cache.didReuseLastResult)
    }

    @Test
    func oversizedUTF8InputIsNeverRetainedOrReused() {
        let cache = FloatingCaptionLayoutCache()
        let font = NSFont.systemFont(ofSize: 24)
        let text = String(repeating: "가", count: FloatingCaptionLayoutCache.maximumCachedInputUTF8Bytes / 3 + 1)
        #expect(text.count < FloatingCaptionLayoutCache.maximumCachedInputUTF8Bytes)
        #expect(text.utf8.count > FloatingCaptionLayoutCache.maximumCachedInputUTF8Bytes)
        let expected = reference(text, lines: 3, width: 360, font: font, fallback: 32)
        for _ in 0..<2 {
            let actual = cache.text(text, maxLines: 3, availableWidth: 360, font: font, fallbackWidthUnits: 32)
            #expect(!cache.didReuseLastResult)
            #expect(cache.entryCount == 0)
            #expect(actual.utf8.elementsEqual(expected.utf8))
        }
    }

    private func reference(_ text: String, lines: Int, width: CGFloat, font: NSFont, fallback: Double) -> String {
        if width > 0 {
            return text.floatingCaptionTail(maxLines: lines, availableWidth: width, font: font)
        }
        return text.floatingCaptionTail(maxLines: lines, lineWidthUnits: fallback)
    }
}
