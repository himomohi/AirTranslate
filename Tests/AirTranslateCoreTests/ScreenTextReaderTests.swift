import CoreGraphics
import CoreText
import Foundation
import Testing
@testable import AirTranslate

@Suite
struct ScreenTextReaderTests {
    @Test func visionLanguagePrefersExactThenSameLanguage() {
        let supported = ["en-US", "zh-Hans", "zh-Hant", "ko-KR", "vi-VT"]
        #expect(ScreenTextReader.visionLanguages(for: .english, supported: supported) == ["en-US"])
        let chinese = LanguageOption(id: "zh-CN", title: "Chinese", locale: Locale(identifier: "zh-CN"))
        #expect(ScreenTextReader.visionLanguages(for: chinese, supported: supported) == ["zh-Hans"])
        let vietnamese = LanguageOption(id: "vi-VN", title: "Vietnamese", locale: Locale(identifier: "vi-VN"))
        #expect(ScreenTextReader.visionLanguages(for: vietnamese, supported: supported) == ["vi-VT"])
        let german = LanguageOption(id: "de-DE", title: "German", locale: Locale(identifier: "de-DE"))
        #expect(ScreenTextReader.visionLanguages(for: german, supported: supported).isEmpty)
    }

    @Test func sourceRectFlipsToDisplayCoordinates() {
        let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let rect = ScreenTextReader.sourceRect(CGRect(x: 100, y: 50, width: 300, height: 60), on: screen)
        #expect(rect == CGRect(x: 100, y: 690, width: 300, height: 60))
    }

    @Test func onlyAUserDeclinedCaptureCountsAsAPermissionDenial() {
        let declined = NSError(domain: "com.apple.ScreenCaptureKit.SCStreamErrorDomain", code: -3801)
        #expect(ScreenTextReader.isPermissionDenial(declined))
        #expect(!ScreenTextReader.isPermissionDenial(ScreenTextReaderError.captureFailed))
    }

    @Test func clippedEdgeLinesAreDroppedAndRowsJoined() {
        typealias Box = ScreenTextReader.TextBox
        let boxes = [
            Box(text: "because they are", box: CGRect(x: 0.1, y: 0.88, width: 0.6, height: 0.12)),  // cut at top
            Box(text: "architectures. Um,", box: CGRect(x: 0.1, y: 0.45, width: 0.4, height: 0.25)),
            Box(text: "it's just going", box: CGRect(x: 0.52, y: 0.46, width: 0.4, height: 0.25)),
            Box(text: "a game", box: CGRect(x: 0.1, y: 0.0, width: 0.2, height: 0.1)),  // cut at bottom
        ]
        #expect(ScreenTextReader.captionLines(from: boxes) == ["architectures. Um, it's just going"])
    }

    @Test func fullLinesTouchingAnEdgeAreKept() {
        typealias Box = ScreenTextReader.TextBox
        let boxes = [
            Box(text: "first line", box: CGRect(x: 0.1, y: 0.55, width: 0.6, height: 0.44)),
            Box(text: "second line", box: CGRect(x: 0.1, y: 0.01, width: 0.6, height: 0.44)),
        ]
        #expect(ScreenTextReader.captionLines(from: boxes) == ["first line", "second line"])
    }

    @Test func recognizesRenderedText() throws {
        let image = try #require(Self.renderText("Hello world"))
        let lines = ScreenTextReader.recognizeLines(in: image, languages: ["en-US"])
        #expect(lines.joined(separator: " ").lowercased().contains("hello world"))
    }

    private static func renderText(_ string: String) -> CGImage? {
        let size = CGSize(width: 480, height: 120)
        guard let context = CGContext(data: nil, width: Int(size.width), height: Int(size.height),
                                      bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(CGRect(origin: .zero, size: size))
        let attributes: [NSAttributedString.Key: Any] = [
            .font: CTFontCreateWithName("Helvetica" as CFString, 40, nil),
            .foregroundColor: CGColor(gray: 1, alpha: 1),
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: attributes))
        context.textPosition = CGPoint(x: 20, y: 44)
        CTLineDraw(line, context)
        return context.makeImage()
    }
}

@Suite
struct ScreenTextTrackerTests {
    private let start = ContinuousClock.now
    private func at(_ ms: Int) -> ContinuousClock.Instant { start + .milliseconds(ms) }

    /// Text of all non-empty pieces, and whether any piece ended a unit.
    private func words(_ out: [(String, Bool)]) -> String {
        out.map(\.0).filter { !$0.isEmpty }.joined(separator: " ")
    }

    @Test func growingLineCommitsAllButTheLastWordUntilItSettles() {
        var tracker = ScreenTextTracker()
        #expect(words(tracker.ingest(["we were going"], now: at(0))) == "we were")
        #expect(words(tracker.ingest(["we were going to the"], now: at(100))) == "going to")
        let settled = tracker.ingest(["we were going to the"], now: at(700))
        #expect(words(settled) == "the")
        #expect(settled.last?.1 == true)  // A pause ends the unit.
    }

    @Test func rollUpYieldsOnlyNewWordsAndEndsTheScrolledLine() {
        var tracker = ScreenTextTracker()
        _ = tracker.ingest(["because they are using very similar"], now: at(0))
        // The line scrolls up and a new bottom line starts.
        let out = tracker.ingest(["because they are using very similar", "architectures. Um, it's"], now: at(100))
        #expect(out.first?.0 == "similar")
        #expect(out.first?.1 == true)
        #expect(words(out) == "similar architectures. Um,")
        // The top line scrolls away; nothing is repeated.
        let next = tracker.ingest(["architectures. Um, it's just going to be"], now: at(200))
        #expect(words(next) == "it's just going to")
    }

    @Test func oneMisreadWordInTheOverlapDoesNotRepeatText() {
        var tracker = ScreenTextTracker()
        _ = tracker.ingest(["they are using very similar architectures"], now: at(0))
        _ = tracker.ingest(["they are using very similar architectures"], now: at(600))
        let out = tracker.ingest(["they are usinq very similar architectures", "and then"], now: at(700))
        #expect(words(out) == "and")
    }

    @Test func briefMissOfTheBottomLineDoesNotRepeatTheTopLine() {
        var tracker = ScreenTextTracker()
        _ = tracker.ingest(["first line here", "second line here"], now: at(0))
        _ = tracker.ingest(["first line here", "second line here"], now: at(600))
        #expect(words(tracker.ingest(["first line here"], now: at(700))).isEmpty)
    }

    @Test func clearedCaptionCompletesThePendingWord() {
        var tracker = ScreenTextTracker()
        _ = tracker.ingest(["see you"], now: at(0))
        let out = tracker.ingest([], now: at(100))
        #expect(out.first?.0 == "you")
        #expect(out.first?.1 == true)
    }
}

@Suite
struct ScreenTextCaptionFilterTests {
    typealias Box = ScreenTextReader.TextBox

    @Test func videoGraphicsAndLabelsAreIgnored() {
        let boxes = [
            Box(text: "the mountains between Vietnam and Laos", box: CGRect(x: 0.05, y: 0.55, width: 0.5, height: 0.2)),
            // A card in the video on the same row, apart from the caption and smaller.
            Box(text: "I ranked 10 MORE of the world", box: CGRect(x: 0.75, y: 0.6, width: 0.2, height: 0.1)),
            Box(text: "that I covered in my mountains video.", box: CGRect(x: 0.05, y: 0.3, width: 0.5, height: 0.2)),
            Box(text: "MOUNTAIN RANGES RANKED", box: CGRect(x: 0.6, y: 0.3, width: 0.3, height: 0.2)),
            Box(text: "CHINA", box: CGRect(x: 0.8, y: 0.1, width: 0.1, height: 0.1)),
        ]
        #expect(ScreenTextReader.captionLines(from: boxes)
            == ["the mountains between Vietnam and Laos", "that I covered in my mountains video."])
    }

    @Test func boxesOfOneLineAreJoined() {
        let boxes = [
            Box(text: "architectures. Um,", box: CGRect(x: 0.1, y: 0.45, width: 0.3, height: 0.25)),
            Box(text: "it's just going", box: CGRect(x: 0.42, y: 0.46, width: 0.3, height: 0.25)),
        ]
        #expect(ScreenTextReader.captionLines(from: boxes) == ["architectures. Um, it's just going"])
    }
}

@Suite
struct ScreenTextAllCapsSubtitleTests {
    @Test func allCapsSubtitlesAreKeptWhenThereIsNoOtherDialogue() {
        let boxes = [ScreenTextReader.TextBox(text: "I DON'T KNOW", box: CGRect(x: 0.2, y: 0.4, width: 0.5, height: 0.2))]
        #expect(ScreenTextReader.captionLines(from: boxes) == ["I DON'T KNOW"])
    }
}

@Suite
struct ScreenTextPopOnCaptionTests {
    @Test func twoLinePopOnCaptionIsOneUnitAndSettlesQuickly() {
        var tracker = ScreenTextTracker()
        let start = ContinuousClock.now
        let caption = ["That pattern runs through", "almost everything in Indochina,"]
        let first = tracker.ingest(caption, now: start)
        #expect(!first.contains { $0.1 })  // No unit ends between the two lines.
        let settled = tracker.ingest(caption, now: start + .milliseconds(200))
        let all = (first + settled).map(\.0).filter { !$0.isEmpty }.joined(separator: " ")
        #expect(all == "That pattern runs through almost everything in Indochina,")
        #expect(settled.last?.1 == true)
    }
}
