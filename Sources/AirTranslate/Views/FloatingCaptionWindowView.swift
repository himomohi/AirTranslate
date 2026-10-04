import AppKit
import SwiftUI

struct FloatingCaptionTextSnapshot {
    let source: String
    let translation: String

    // 표시할 블록만 한 번씩 조판하고 창 상태 확인에서도 같은 결과를 사용한다.
    init(mode: FloatingCaptionDisplayMode, source: () -> String, translation: () -> String) {
        self.source = mode == .translation ? "" : source()
        self.translation = mode == .original ? "" : translation()
    }

    var hasVisibleText: Bool { !source.isEmpty || !translation.isEmpty }
}

private struct FloatingCaptionPreviousBlock: View, Equatable {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var settled = false
    @State private var visible = true

    let text: String
    let expiresAt: Date
    let font: Font
    let color: Color
    let lineCount: Int
    let alignment: FloatingCaptionTextAlignment
    let lineSpacing: CGFloat
    let effect: FloatingCaptionTextEffect
    let availableWidth: CGFloat
    let nativeFont: NSFont
    let nativeFontName: String
    let nativeFontPointSize: CGFloat
    let fallbackWidthUnits: Double

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.text == rhs.text && lhs.expiresAt == rhs.expiresAt && lhs.font == rhs.font
            && lhs.color == rhs.color && lhs.lineCount == rhs.lineCount && lhs.alignment == rhs.alignment
            && lhs.lineSpacing == rhs.lineSpacing && lhs.effect == rhs.effect
            && lhs.availableWidth == rhs.availableWidth
            && lhs.nativeFontName == rhs.nativeFontName && lhs.nativeFontPointSize == rhs.nativeFontPointSize
            && lhs.fallbackWidthUnits == rhs.fallbackWidthUnits
    }

    private var formattedText: String {
        if availableWidth > 0 {
            return text.floatingCaptionTail(maxLines: lineCount, availableWidth: availableWidth, font: nativeFont)
        }
        return text.floatingCaptionTail(maxLines: lineCount, lineWidthUnits: fallbackWidthUnits)
    }

    var body: some View {
        Text(formattedText)
            .font(font)
            .foregroundStyle(color)
            .lineLimit(lineCount)
            .fixedSize(horizontal: false, vertical: true)
            .multilineTextAlignment(alignment.textAlignment)
            .lineSpacing(lineSpacing)
            .modifier(CaptionTextEffectModifier(effect: effect))
            .opacity(settled ? 0.68 : 0.86)
            .opacity(visible ? 1 : 0)
            .offset(y: reduceMotion || !settled ? 0 : -FloatingCaptionHistoryLayout.historyMotionHeight)
            .onAppear {
                // 현재 자막은 이 애니메이션에 포함하지 않는다. 만료는 세션의 작업 하나가 담당한다.
                withAnimation(.easeOut(duration: 0.45)) { settled = true }
                let remaining = max(0, expiresAt.timeIntervalSinceNow)
                let fadeDuration = min(0.6, remaining)
                withAnimation(.easeOut(duration: fadeDuration).delay(max(0, remaining - fadeDuration))) { visible = false }
            }
    }
}

struct FloatingCaptionWindowView: View {
    @Bindable var session: TranslationSessionStore

    private static let blockSpacing: CGFloat = 8
    private static let horizontalPadding: CGFloat = AirTranslateDesign.Spacing.lg * 2
    private static let verticalPadding: CGFloat = AirTranslateDesign.Spacing.md * 2

    var body: some View {
        let textSnapshot = FloatingCaptionTextSnapshot(
            mode: session.floatingCaptionDisplayMode,
            source: { sourceText },
            translation: { translationText }
        )
        ZStack {
            AirTranslateDesign.Palette.transparent

            VStack(spacing: Self.blockSpacing) {
                captionContent(sourceText: textSnapshot.source, translationText: textSnapshot.translation)
            }
            .padding(.horizontal, AirTranslateDesign.Spacing.lg)
            .padding(.vertical, AirTranslateDesign.Spacing.md)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(
            minWidth: FloatingCaptionWindowController.minimumWindowSize.width,
            idealWidth: FloatingCaptionWindowController.defaultWindowSize.width,
            maxWidth: .infinity,
            minHeight: session.floatingCaptionMinimumWindowHeight,
            idealHeight: preferredHeight,
            maxHeight: .infinity
        )
        .onGeometryChange(for: CGSize.self) { proxy in
            proxy.size
        } action: { size in
            let textWidth = max(0, size.width - Self.horizontalPadding)
            let contentHeight = max(0, size.height - Self.verticalPadding)
            if session.floatingCaptionMeasuredTextWidth != textWidth {
                session.floatingCaptionMeasuredTextWidth = textWidth
            }
            if session.floatingCaptionMeasuredContentHeight != contentHeight {
                session.floatingCaptionMeasuredContentHeight = contentHeight
            }
        }
        .contentShape(Rectangle())
        .allowsWindowActivationEvents(true)
        .overlay {
            FloatingCaptionDragSurface()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(
            FloatingWindowConfigurator(
                preferredContentHeight: preferredHeight,
                minimumWindowSize: session.floatingCaptionMinimumWindowSize,
                keepsAboveOtherWindows: session.keepsFloatingCaptionAboveOtherWindows,
                hasCaptionText: textSnapshot.hasVisibleText || hasVisibleHistory
            )
        )
    }

    private var hasVisibleHistory: Bool {
        guard !session.isPreviewingFloatingCaptions, session.floatingCaptionHistoryLayout.historyLines > 0 else { return false }
        return (session.floatingCaptionDisplayMode != .translation && session.floatingCaptionHistory.previousSource != nil)
            || (session.floatingCaptionDisplayMode != .original && session.floatingCaptionHistory.previousTranslation != nil)
    }

    // 블록 경계를 고정해 자막이 갱신되어도 읽는 위치를 유지한다.
    @ViewBuilder
    private func captionContent(sourceText: String, translationText: String) -> some View {
        switch session.floatingCaptionDisplayMode {
        case .original:
            primaryBlock(sourceText, previous: session.floatingCaptionHistory.previousSource, anchor: .bottom)
        case .originalAndTranslation:
            if session.floatingCaptionStyle.translationFirst {
                primaryBlock(translationText, previous: session.floatingCaptionHistory.previousTranslation, anchor: .bottom)
                secondaryBlock(sourceText, previous: session.floatingCaptionHistory.previousSource, anchor: .top)
            } else {
                secondaryBlock(sourceText, previous: session.floatingCaptionHistory.previousSource, anchor: .bottom)
                primaryBlock(translationText, previous: session.floatingCaptionHistory.previousTranslation, anchor: .top)
            }
        case .translation:
            primaryBlock(translationText, previous: session.floatingCaptionHistory.previousTranslation, anchor: .bottom)
        }
    }

    private var sourceText: String {
        session.isPreviewingFloatingCaptions
            ? session.floatingCaptionText(from: CaptionStyleCopy.sampleOriginal, usesPrimaryFont: session.floatingCaptionDisplayMode == .original)
            : session.floatingSourceText
    }

    private var translationText: String {
        session.isPreviewingFloatingCaptions
            ? session.floatingCaptionText(from: CaptionStyleCopy.sampleTranslation)
            : session.floatingTranslationText
    }

    private var lineLimit: Int {
        session.floatingCaptionEffectiveLineCount
    }

    private var alignment: FloatingCaptionTextAlignment {
        session.floatingCaptionTextAlignment
    }

    static func blockHeight(lineHeight: CGFloat, lineCount: Int) -> CGFloat {
        FloatingCaptionAppearance.blockHeight(lineHeight: lineHeight, lineCount: lineCount)
    }

    private var primaryBlockHeight: CGFloat {
        FloatingCaptionAppearance.blockHeight(lineHeight: session.floatingCaptionPrimaryLineHeight, lineCount: lineLimit, lineSpacing: session.floatingCaptionStyle.lineSpacing.points)
    }

    private var secondaryBlockHeight: CGFloat {
        FloatingCaptionAppearance.blockHeight(lineHeight: session.floatingCaptionSecondaryLineHeight, lineCount: lineLimit, lineSpacing: session.floatingCaptionStyle.lineSpacing.points)
    }

    private var preferredHeight: CGFloat {
        session.floatingCaptionPreferredWindowHeight
    }

    private func primaryBlock(_ text: String, previous: FloatingCaptionHistory.Previous?, anchor: VerticalAlignment) -> some View {
        captionPane(text, previous: previous, font: session.floatingCaptionPrimaryFont,
                    color: session.floatingCaptionTextColor, height: primaryBlockHeight,
                    lineHeight: session.floatingCaptionPrimaryLineHeight, usesPrimaryFont: true, anchor: anchor)
    }

    private func secondaryBlock(_ text: String, previous: FloatingCaptionHistory.Previous?, anchor: VerticalAlignment) -> some View {
        captionPane(text, previous: previous, font: session.floatingCaptionSecondaryFont,
                    color: session.floatingCaptionTextColor.opacity(0.82), height: secondaryBlockHeight,
                    lineHeight: session.floatingCaptionSecondaryLineHeight, usesPrimaryFont: false, anchor: anchor)
    }

    private func captionPane(
        _ text: String, previous: FloatingCaptionHistory.Previous?, font: Font, color: Color,
        height: CGFloat, lineHeight: CGFloat, usesPrimaryFont: Bool, anchor: VerticalAlignment
    ) -> some View {
        let historyLines = session.floatingCaptionHistoryLayout.historyLines
        let historyHeight = FloatingCaptionAppearance.blockHeight(
            lineHeight: lineHeight, lineCount: historyLines, lineSpacing: session.floatingCaptionStyle.lineSpacing.points
        )
        // 조판된 현재 줄 수만 차지하게 해 짧은 자막 위의 이전 자막이 멀리 떨어지지 않게 한다.
        // 바깥 높이는 예약된 줄 수 그대로 유지하므로 현재 자막의 기준 위치와 창 크기는 고정된다.
        let visibleLineCount = min(lineLimit, max(1, text.split(separator: "\n").count))
        let visibleHeight = FloatingCaptionAppearance.blockHeight(
            lineHeight: lineHeight, lineCount: visibleLineCount, lineSpacing: session.floatingCaptionStyle.lineSpacing.points
        )
        let paneHeight = height + (historyLines > 0
            ? historyHeight + FloatingCaptionHistoryLayout.historyMotionHeight + FloatingCaptionHistoryLayout.historySpacing : 0)
        return VStack(spacing: historyLines > 0 ? FloatingCaptionHistoryLayout.historySpacing : 0) {
            if historyLines > 0 {
                ZStack(alignment: alignment.frameAlignment(vertical: .bottom)) {
                    Color.clear
                    if !session.isPreviewingFloatingCaptions, let previous {
                        let nativeFont = session.floatingCaptionStyle.nativeFont(
                            size: usesPrimaryFont ? session.floatingCaptionPrimaryPointSize : session.floatingCaptionSecondaryPointSize,
                            primary: usesPrimaryFont
                        )
                        FloatingCaptionPreviousBlock(
                            text: previous.caption.text,
                            expiresAt: previous.expiresAt, font: font, color: color, lineCount: historyLines,
                            alignment: alignment, lineSpacing: session.floatingCaptionStyle.lineSpacing.points,
                            effect: session.floatingCaptionStyle.textEffect,
                            availableWidth: session.floatingCaptionMeasuredTextWidth,
                            nativeFont: nativeFont,
                            nativeFontName: nativeFont.fontName,
                            nativeFontPointSize: nativeFont.pointSize,
                            fallbackWidthUnits: session.floatingCaptionLineWidthUnits(usesPrimaryFont: usesPrimaryFont)
                        )
                        .equatable()
                        .id(previous)
                    }
                }
                .frame(height: historyHeight + FloatingCaptionHistoryLayout.historyMotionHeight)
                .clipped()
                .accessibilityHidden(true)
            }
            captionBlock(text, font: font, color: color, height: visibleHeight, anchor: anchor)
                .transaction { $0.animation = nil }
        }
        .frame(height: paneHeight, alignment: alignment.frameAlignment(vertical: anchor))
    }

    private func captionBlock(
        _ text: String,
        font: Font,
        color: Color,
        height: CGFloat,
        anchor: VerticalAlignment
    ) -> some View {
        // 자막 안정화는 세션의 표시 정책이 담당한다. 같은 텍스트를 뷰의 별도
        // 상태와 애니메이션 Task로 다시 처리하지 않고 완전한 대비로 즉시 표시한다.
        Text(text)
        .font(font)
        .foregroundStyle(color)
        .textSelection(.disabled)
        .lineLimit(lineLimit)
        .truncationMode(.tail)
        .fixedSize(horizontal: false, vertical: true)
        .multilineTextAlignment(alignment.textAlignment)
        .lineSpacing(session.floatingCaptionStyle.lineSpacing.points)
        .frame(maxWidth: .infinity, minHeight: height, maxHeight: height, alignment: alignment.frameAlignment(vertical: anchor))
        .clipped()
        .modifier(CaptionTextEffectModifier(effect: session.floatingCaptionStyle.textEffect))
    }
}
