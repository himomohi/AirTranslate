import AppKit
import Testing
@testable import AirTranslate

@Suite
struct FloatingCaptionWorkTests {
    @Test
    func displayedPanesAreFormattedOnceAndHiddenPanesAreNotFormatted() {
        for mode in FloatingCaptionDisplayMode.allCases {
            var sourceCalls = 0
            var translationCalls = 0
            let snapshot = FloatingCaptionTextSnapshot(
                mode: mode,
                source: { sourceCalls += 1; return "Source" },
                translation: { translationCalls += 1; return "번역" }
            )
            #expect(snapshot.hasVisibleText)
            #expect(snapshot.hasVisibleText)
            #expect(sourceCalls == (mode == .translation ? 0 : 1))
            #expect(translationCalls == (mode == .original ? 0 : 1))
        }
    }

    @Test
    func hiddenPaneCannotMakeAnEmptyCaptionWindowInterceptClicks() {
        let sourceOnly = FloatingCaptionTextSnapshot(mode: .original, source: { "" }, translation: { "숨긴 번역" })
        let translationOnly = FloatingCaptionTextSnapshot(mode: .translation, source: { "Hidden source" }, translation: { "" })
        #expect(!sourceOnly.hasVisibleText)
        #expect(!translationOnly.hasVisibleText)
    }

    @Test
    func longHistoryDoesNotChangeTheRecentCaptionInEitherLayoutPath() {
        let ending = "First recent sentence. A value is 3.14 today. 마지막 자막은 그대로 보여야 합니다. 👨‍👩‍👧‍👦"
        let prefix = String(repeating: "Earlier sentences. 이미 읽은 내용입니다. ", count: 12_000)
        for maxLines in [1, 2, 3] {
            #expect((prefix + ending).floatingCaptionTail(maxLines: maxLines) == ending.floatingCaptionTail(maxLines: maxLines))
            let font = NSFont.systemFont(ofSize: 32)
            #expect(
                (prefix + ending).floatingCaptionTail(maxLines: maxLines, availableWidth: 672, font: font)
                    == ending.floatingCaptionTail(maxLines: maxLines, availableWidth: 672, font: font)
            )
        }
    }
}
