import CoreGraphics
import CoreText
import Foundation
import Testing
@testable import AirTranslate

@Suite
struct ScreenTextReaderTests {
    @Test func newTextIsReportedAfterTwoMatchingReads() {
        var stabilizer = ScreenTextStabilizer()
        #expect(stabilizer.ingest("Hello there") == nil)
        #expect(stabilizer.isConfirming)
        #expect(stabilizer.ingest("Hello  there") == "Hello there")
        #expect(stabilizer.ingest("Hello there") == nil)
    }

    @Test func ocrNoiseDoesNotReportTheSameLineAgain() {
        var stabilizer = ScreenTextStabilizer()
        _ = stabilizer.ingest("We have to leave tonight")
        _ = stabilizer.ingest("We have to leave tonight")
        #expect(stabilizer.ingest("We have to 1eave tonight") == nil)
        #expect(stabilizer.ingest("We have to 1eave tonight") == nil)
    }

    @Test func textClearsAfterSeveralEmptyReads() {
        var stabilizer = ScreenTextStabilizer()
        _ = stabilizer.ingest("Line")
        _ = stabilizer.ingest("Line")
        #expect(stabilizer.ingest("") == nil)
        #expect(stabilizer.ingest("") == nil)
        #expect(stabilizer.ingest("") == "")
    }

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

    @Test func recognizesRenderedText() throws {
        let image = try #require(Self.renderText("Hello world"))
        let text = ScreenTextReader.recognizeText(in: image, languages: ["en-US"])
        #expect(text.lowercased().contains("hello world"))
    }

    private static func renderText(_ string: String) -> CGImage? {
        let size = CGSize(width: 480, height: 80)
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
        context.textPosition = CGPoint(x: 20, y: 24)
        CTLineDraw(line, context)
        return context.makeImage()
    }
}
