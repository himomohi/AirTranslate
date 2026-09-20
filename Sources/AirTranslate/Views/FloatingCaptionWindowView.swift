import AppKit
import SwiftUI

struct FloatingCaptionWindowView: View {
    @Bindable var session: TranslationSessionStore

    private static let blockSpacing: CGFloat = 8
    private static let horizontalPadding: CGFloat = AirTranslateDesign.Spacing.lg * 2
    private static let verticalPadding: CGFloat = AirTranslateDesign.Spacing.md * 2
    private static let replacementCrossfadeDuration = 0.16

    var body: some View {
        ZStack {
            AirTranslateDesign.Palette.transparent

            VStack(spacing: Self.blockSpacing) {
                content
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
                hasCaptionText: hasVisibleCaptionText
            )
        )
    }

    // 블록 경계를 고정해 자막이 갱신되어도 읽는 위치를 유지한다.
    @ViewBuilder
    private var content: some View {
        switch session.floatingCaptionDisplayMode {
        case .original:
            primaryBlock(sourceText, anchor: .bottom)
        case .originalAndTranslation:
            if session.floatingCaptionStyle.translationFirst {
                primaryBlock(translationText, anchor: .bottom)
                secondaryBlock(sourceText, anchor: .top)
            } else {
                secondaryBlock(sourceText, anchor: .bottom)
                primaryBlock(translationText, anchor: .top)
            }
        case .translation:
            primaryBlock(translationText, anchor: .bottom)
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

    private var hasVisibleCaptionText: Bool {
        switch session.floatingCaptionDisplayMode {
        case .original: !sourceText.isEmpty
        case .translation: !translationText.isEmpty
        case .originalAndTranslation: !sourceText.isEmpty || !translationText.isEmpty
        }
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
        let textHeight: CGFloat

        switch session.floatingCaptionDisplayMode {
        case .original, .translation:
            textHeight = primaryBlockHeight
        case .originalAndTranslation:
            textHeight = primaryBlockHeight + secondaryBlockHeight + Self.blockSpacing
        }

        return min(max(90, textHeight + Self.verticalPadding), 720)
    }

    private func primaryBlock(_ text: String, anchor: VerticalAlignment) -> some View {
        captionBlock(
            text,
            font: session.floatingCaptionPrimaryFont,
            color: session.floatingCaptionTextColor,
            height: primaryBlockHeight,
            anchor: anchor
        )
    }

    private func secondaryBlock(_ text: String, anchor: VerticalAlignment) -> some View {
        captionBlock(
            text,
            font: session.floatingCaptionSecondaryFont,
            color: session.floatingCaptionTextColor.opacity(0.82),
            height: secondaryBlockHeight,
            anchor: anchor
        )
    }

    private func captionBlock(
        _ text: String,
        font: Font,
        color: Color,
        height: CGFloat,
        anchor: VerticalAlignment
    ) -> some View {
        StreamingTranscriptText(
            text: text,
            font: font,
            foregroundColor: color,
            isTextSelectionEnabled: false,
            lineLimit: lineLimit,
            textAlignment: alignment.textAlignment,
            frameAlignment: alignment.frameAlignment(vertical: anchor),
            truncationMode: .tail,
            streamsAppendedTextInChunks: false,
            replacementCrossfadeDuration: Self.replacementCrossfadeDuration
        )
        .multilineTextAlignment(alignment.textAlignment)
        .lineSpacing(session.floatingCaptionStyle.lineSpacing.points)
        .frame(maxWidth: .infinity, minHeight: height, maxHeight: height, alignment: alignment.frameAlignment(vertical: anchor))
        .clipped()
        .modifier(CaptionTextEffectModifier(effect: session.floatingCaptionStyle.textEffect))
    }
}
