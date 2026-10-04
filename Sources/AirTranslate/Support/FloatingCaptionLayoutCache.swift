import AppKit
import Foundation

/// 현재 원문·번역의 조판만 보관하며 입력이 달라지면 기존 조판기를 즉시 사용한다.
@MainActor
final class FloatingCaptionLayoutCache {
    static let maximumEntryCount = 2
    static let maximumCachedInputUTF8Bytes = 64 * 1_024

    private(set) var didReuseLastResult = false
    var entryCount: Int { entries.count }

    private struct Entry {
        let text: String
        let maxLines: Int
        let widthBits: UInt64
        let font: NSFont
        let fontAttributes: NSDictionary
        let fallbackWidthBits: UInt64
        let result: String

        func matches(
            text: String, maxLines: Int, widthBits: UInt64,
            font: NSFont, fontAttributes: NSDictionary, fallbackWidthBits: UInt64
        ) -> Bool {
            self.maxLines == maxLines
                && self.widthBits == widthBits
                && self.fallbackWidthBits == fallbackWidthBits
                && self.font.isEqual(font)
                && self.fontAttributes.isEqual(fontAttributes)
                // String의 정규 동등성 대신 실제 UTF-8을 비교해 원문의 코드 포인트를 보존한다.
                && self.text.utf8.elementsEqual(text.utf8)
        }
    }

    // 앞은 가장 오래 사용한 항목, 뒤는 가장 최근 사용한 항목이다.
    private var entries: [Entry] = []

    func text(
        _ text: String,
        maxLines: Int,
        availableWidth: CGFloat,
        font: NSFont,
        fallbackWidthUnits: Double
    ) -> String {
        didReuseLastResult = false
        guard text.utf8.count <= Self.maximumCachedInputUTF8Bytes else {
            return formatted(text, maxLines: maxLines, availableWidth: availableWidth,
                             font: font, fallbackWidthUnits: fallbackWidthUnits)
        }

        let widthBits = Double(availableWidth).bitPattern
        let fallbackWidthBits = fallbackWidthUnits.bitPattern
        // 이름·크기만으로 축약하지 않아 가변 폰트 축, 특성, 행렬 등의 속성도 비교한다.
        let fontAttributes = font.fontDescriptor.fontAttributes as NSDictionary
        if let index = entries.firstIndex(where: {
            $0.matches(text: text, maxLines: maxLines, widthBits: widthBits,
                       font: font, fontAttributes: fontAttributes, fallbackWidthBits: fallbackWidthBits)
        }) {
            let entry = entries.remove(at: index)
            entries.append(entry)
            didReuseLastResult = true
            return entry.result
        }

        let result = formatted(text, maxLines: maxLines, availableWidth: availableWidth,
                               font: font, fallbackWidthUnits: fallbackWidthUnits)
        guard result.utf8.count <= Self.maximumCachedInputUTF8Bytes else { return result }
        if entries.count == Self.maximumEntryCount { entries.removeFirst() }
        entries.append(Entry(text: text, maxLines: maxLines, widthBits: widthBits,
                             font: font, fontAttributes: fontAttributes,
                             fallbackWidthBits: fallbackWidthBits, result: result))
        return result
    }

    func removeAll() {
        entries.removeAll()
        didReuseLastResult = false
    }

    private func formatted(
        _ text: String, maxLines: Int, availableWidth: CGFloat,
        font: NSFont, fallbackWidthUnits: Double
    ) -> String {
        if availableWidth > 0 {
            return text.floatingCaptionTail(maxLines: maxLines, availableWidth: availableWidth, font: font)
        }
        return text.floatingCaptionTail(maxLines: maxLines, lineWidthUnits: fallbackWidthUnits)
    }
}
