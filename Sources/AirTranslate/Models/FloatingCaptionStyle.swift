import AppKit
import SwiftUI

enum FloatingCaptionFontFamily: String, Codable, CaseIterable, Identifiable {
    case system, rounded, serif, monospaced
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: CaptionStyleCopy.text("System", "기본", "システム", "系统")
        case .rounded: CaptionStyleCopy.text("Rounded", "둥글게", "丸ゴシック", "圆体")
        case .serif: CaptionStyleCopy.text("Serif", "명조", "明朝", "衬线")
        case .monospaced: CaptionStyleCopy.text("Monospaced", "고정폭", "等幅", "等宽")
        }
    }
    var design: Font.Design {
        switch self {
        case .system: .default
        case .rounded: .rounded
        case .serif: .serif
        case .monospaced: .monospaced
        }
    }
    var lineHeightScale: CGFloat { self == .system ? 1.24 : 1.38 }
    var widthScale: CGFloat { self == .monospaced ? 1.18 : 1 }
}

enum FloatingCaptionFontWeight: String, Codable, CaseIterable, Identifiable {
    case regular, medium, semibold, bold
    var id: String { rawValue }
    var title: String {
        switch self {
        case .regular: CaptionStyleCopy.text("Regular", "보통", "標準", "常规")
        case .medium: CaptionStyleCopy.text("Medium", "중간", "中太", "中等")
        case .semibold: CaptionStyleCopy.text("Semibold", "약간 굵게", "セミボールド", "半粗")
        case .bold: CaptionStyleCopy.text("Bold", "굵게", "太字", "粗体")
        }
    }
    var primary: Font.Weight {
        switch self {
        case .regular: .regular
        case .medium: .medium
        case .semibold: .semibold
        case .bold: .bold
        }
    }
    var secondary: Font.Weight {
        switch self {
        case .regular, .medium: .regular
        case .semibold: .medium
        case .bold: .semibold
        }
    }
}

enum FloatingCaptionLineSpacing: String, Codable, CaseIterable, Identifiable {
    case compact, standard, relaxed
    var id: String { rawValue }
    var points: CGFloat {
        switch self { case .compact: 2; case .standard: 5; case .relaxed: 10 }
    }
    var title: String {
        switch self {
        case .compact: CaptionStyleCopy.text("Compact", "좁게", "狭く", "紧凑")
        case .standard: CaptionStyleCopy.text("Standard", "보통", "標準", "标准")
        case .relaxed: CaptionStyleCopy.text("Relaxed", "넓게", "広く", "宽松")
        }
    }
}

enum FloatingCaptionTextEffect: String, Codable, CaseIterable, Identifiable {
    case none, shadow, outline
    var id: String { rawValue }
    var title: String {
        switch self {
        case .none: CaptionStyleCopy.text("None", "없음", "なし", "无")
        case .shadow: CaptionStyleCopy.text("Shadow", "그림자", "影", "阴影")
        case .outline: CaptionStyleCopy.text("Outline", "윤곽선", "縁取り", "描边")
        }
    }
}

enum FloatingCaptionBackgroundShape: String, Codable, CaseIterable, Identifiable {
    case square, soft, rounded
    var id: String { rawValue }
    var radius: CGFloat {
        switch self { case .square: 0; case .soft: 16; case .rounded: 28 }
    }
    var title: String {
        switch self {
        case .square: CaptionStyleCopy.text("Square", "각지게", "四角", "直角")
        case .soft: CaptionStyleCopy.text("Soft", "부드럽게", "少し丸く", "柔和")
        case .rounded: CaptionStyleCopy.text("Round", "둥글게", "丸く", "圆角")
        }
    }
}

/// 기존 저장값을 건드리지 않고 추가 표시 옵션만 별도 키에 보관한다.
struct FloatingCaptionStyle: Codable, Equatable {
    var fontFamily: FloatingCaptionFontFamily = .system
    var fontWeight: FloatingCaptionFontWeight = .semibold
    var lineSpacing: FloatingCaptionLineSpacing = .standard
    var textEffect: FloatingCaptionTextEffect = .shadow
    var backgroundShape: FloatingCaptionBackgroundShape = .soft
    var translationFirst = false

    static let standard = FloatingCaptionStyle()

    func captionTextMatches(_ other: Self) -> Bool {
        fontFamily == other.fontFamily && fontWeight == other.fontWeight
            && lineSpacing == other.lineSpacing && textEffect == other.textEffect
            && translationFirst == other.translationFirst
    }

    func nativeFont(size: CGFloat, primary: Bool) -> NSFont {
        let weight: NSFont.Weight
        switch fontWeight {
        case .regular: weight = .regular
        case .medium: weight = primary ? .medium : .regular
        case .semibold: weight = primary ? .semibold : .medium
        case .bold: weight = primary ? .bold : .semibold
        }
        let base = NSFont.systemFont(ofSize: size, weight: weight)
        let design: NSFontDescriptor.SystemDesign
        switch fontFamily {
        case .system: return base
        case .rounded: design = .rounded
        case .serif: design = .serif
        case .monospaced: design = .monospaced
        }
        guard let descriptor = base.fontDescriptor.withDesign(design) else { return base }
        return NSFont(descriptor: descriptor, size: size) ?? base
    }

    init(
        fontFamily: FloatingCaptionFontFamily = .system,
        fontWeight: FloatingCaptionFontWeight = .semibold,
        lineSpacing: FloatingCaptionLineSpacing = .standard,
        textEffect: FloatingCaptionTextEffect = .shadow,
        backgroundShape: FloatingCaptionBackgroundShape = .soft,
        translationFirst: Bool = false
    ) {
        self.fontFamily = fontFamily
        self.fontWeight = fontWeight
        self.lineSpacing = lineSpacing
        self.textEffect = textEffect
        self.backgroundShape = backgroundShape
        self.translationFirst = translationFirst
    }

    private enum CodingKeys: String, CodingKey {
        case fontFamily, fontWeight, lineSpacing, textEffect, backgroundShape, translationFirst
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        fontFamily = (try? values.decode(FloatingCaptionFontFamily.self, forKey: .fontFamily)) ?? .system
        fontWeight = (try? values.decode(FloatingCaptionFontWeight.self, forKey: .fontWeight)) ?? .semibold
        lineSpacing = (try? values.decode(FloatingCaptionLineSpacing.self, forKey: .lineSpacing)) ?? .standard
        textEffect = (try? values.decode(FloatingCaptionTextEffect.self, forKey: .textEffect)) ?? .shadow
        backgroundShape = (try? values.decode(FloatingCaptionBackgroundShape.self, forKey: .backgroundShape)) ?? .soft
        translationFirst = (try? values.decode(Bool.self, forKey: .translationFirst)) ?? false
    }
}

enum FloatingCaptionPreset: String, CaseIterable, Identifiable {
    case standard, cinema, lecture, highContrast, paper
    var id: String { rawValue }
    var title: String {
        switch self {
        case .standard: CaptionStyleCopy.text("Everyday", "기본", "標準", "日常")
        case .cinema: CaptionStyleCopy.text("Cinema", "영화", "映画", "影院")
        case .lecture: CaptionStyleCopy.text("Lecture", "강의", "講義", "讲座")
        case .highContrast: CaptionStyleCopy.text("High contrast", "고대비", "高コントラスト", "高对比度")
        case .paper: CaptionStyleCopy.text("Light scene", "밝은 화면용", "明るい画面用", "明亮画面")
        }
    }
    var detail: String {
        switch self {
        case .standard: CaptionStyleCopy.text("Balanced for daily use", "일상에 편안한 기본값", "毎日使いやすい設定", "适合日常使用")
        case .cinema: CaptionStyleCopy.text("Larger text with an outline", "큰 글씨와 윤곽선", "大きな文字と縁取り", "大字与描边")
        case .lecture: CaptionStyleCopy.text("More lines, left aligned", "여러 줄을 왼쪽 정렬로", "複数行を左揃えで", "更多行，左对齐")
        case .highContrast: CaptionStyleCopy.text("Bold yellow with a dark outline", "선명한 노란 글씨와 진한 윤곽선", "黄色の太字と濃い縁取り", "醒目黄字与深色描边")
        case .paper: CaptionStyleCopy.text("Dark text for bright content", "밝은 화면에 어울리는 진한 글씨", "明るい画面に濃い文字", "适合明亮内容的深色文字")
        }
    }
    var style: FloatingCaptionStyle {
        switch self {
        case .standard: .standard
        case .cinema: FloatingCaptionStyle(textEffect: .outline)
        case .lecture: FloatingCaptionStyle(fontWeight: .medium, lineSpacing: .relaxed)
        case .highContrast: FloatingCaptionStyle(fontWeight: .bold, textEffect: .outline)
        case .paper: FloatingCaptionStyle(fontFamily: .rounded, fontWeight: .medium, textEffect: .none)
        }
    }
    var textSize: FloatingCaptionTextSize { [.cinema, .highContrast].contains(self) ? .large : .medium }
    var lineCount: FloatingCaptionLineCount {
        switch self { case .cinema: .two; case .lecture: .four; default: .three }
    }
    var alignment: FloatingCaptionTextAlignment { [.lecture, .paper].contains(self) ? .leading : .center }
    var textColorHex: String {
        switch self { case .highContrast: "#FFE066"; case .paper: "#18222B"; default: "#FFFFFF" }
    }
    var previewSceneHex: String {
        switch self { case .paper: "#F6F2E9"; case .highContrast, .cinema: "#000000"; default: "#05080A" }
    }
}
