import AppKit
import SwiftUI

enum FloatingCaptionAppearance {
    static let defaultTextColorHex = "#FFFFFF"
    static let defaultBackgroundColorHex = "#05080A"
    static let defaultBackgroundOpacity = 0.86
    static let defaultCustomPointSize: CGFloat = 0
    static let customPointSizeRange: ClosedRange<CGFloat> = 18...72
    static let opacityRange: ClosedRange<Double> = 0...1
    static let captionLineSpacing: CGFloat = 5
    static let captionBlockSpacing: CGFloat = 8
    static let windowVerticalPadding: CGFloat = 32

    static func clampedCustomPointSize(_ value: CGFloat) -> CGFloat {
        guard value.isFinite, value > 0 else { return defaultCustomPointSize }
        return min(max(value, customPointSizeRange.lowerBound), customPointSizeRange.upperBound)
    }

    static func clampedOpacity(_ value: Double) -> Double {
        guard value.isFinite else { return defaultBackgroundOpacity }
        return min(max(value, opacityRange.lowerBound), opacityRange.upperBound)
    }

    static func blockHeight(lineHeight: CGFloat, lineCount: Int, lineSpacing: CGFloat = captionLineSpacing) -> CGFloat {
        lineHeight * CGFloat(lineCount) + CGFloat(max(0, lineCount - 1)) * lineSpacing
    }

    static func secondaryPointSize(for primaryPointSize: CGFloat) -> CGFloat {
        max(12, primaryPointSize * 2 / 3)
    }

    static func color(hex: String, fallback fallbackHex: String) -> Color {
        Color(nsColor: nsColor(hex: hex) ?? nsColor(hex: fallbackHex) ?? .white)
    }

    static func normalizedHex(_ hex: String, fallback fallbackHex: String) -> String {
        guard let color = nsColor(hex: hex) else { return fallbackHex }
        return hexString(from: color) ?? fallbackHex
    }

    static func hexString(from color: NSColor) -> String? {
        guard let srgb = color.usingColorSpace(.sRGB) else { return nil }
        let red = Int(round(min(max(srgb.redComponent, 0), 1) * 255))
        let green = Int(round(min(max(srgb.greenComponent, 0), 1) * 255))
        let blue = Int(round(min(max(srgb.blueComponent, 0), 1) * 255))
        return String(format: "#%02X%02X%02X", red, green, blue)
    }

    static func nsColor(hex: String) -> NSColor? {
        var raw = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.hasPrefix("#") {
            raw.removeFirst()
        }
        guard raw.count == 6, let value = UInt32(raw, radix: 16) else { return nil }
        return NSColor(
            srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }
}
