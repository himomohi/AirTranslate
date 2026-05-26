import SwiftUI

struct FloatingCaptionWindowView: View {
    @Bindable var session: TranslationSessionStore

    var body: some View {
        ZStack {
            Color.clear

            VStack(alignment: session.floatingCaptionTextAlignment.horizontalAlignment, spacing: 8) {
                content
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 420, idealWidth: 720, maxWidth: 960, minHeight: 90, idealHeight: preferredHeight, maxHeight: preferredHeight)
        .contentShape(Rectangle())
        .gesture(WindowDragGesture())
        .allowsWindowActivationEvents(true)
        .overlay {
            FloatingCaptionDragSurface()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(FloatingWindowConfigurator(preferredContentHeight: preferredHeight))
    }

    @ViewBuilder
    private var content: some View {
        switch session.floatingCaptionDisplayMode {
        case .original:
            subtitleText(sourceText, font: session.floatingCaptionTextSize.primaryFont)
        case .originalAndTranslation:
            if !sourceText.isEmpty {
                subtitleText(sourceText, font: session.floatingCaptionTextSize.secondaryFont)
                    .opacity(0.82)
                subtitleText(translationText.isEmpty ? " " : translationText, font: session.floatingCaptionTextSize.primaryFont)
                    .opacity(translationText.isEmpty ? 0 : 1)
            }
            if sourceText.isEmpty && translationText.isEmpty {
                subtitleText(AppText.noFloatingCaptionsYet, font: session.floatingCaptionTextSize.primaryFont)
            }
        case .translation:
            if !translationText.isEmpty {
                subtitleText(translationText, font: session.floatingCaptionTextSize.primaryFont)
            } else if sourceText.isEmpty {
                subtitleText(AppText.noFloatingCaptionsYet, font: session.floatingCaptionTextSize.primaryFont)
            }
        }
    }

    private var sourceText: String {
        session.floatingSourceText
    }

    private var translationText: String {
        session.floatingTranslationText
    }

    private var lineLimit: Int {
        session.floatingCaptionLineCount.rawValue
    }

    private var preferredHeight: CGFloat {
        let textSize = session.floatingCaptionTextSize
        let lineCount = CGFloat(lineLimit)
        let primaryHeight = textSize.primaryLineHeight * lineCount + CGFloat(lineLimit - 1) * 5
        let secondaryHeight = textSize.secondaryLineHeight * lineCount + CGFloat(lineLimit - 1) * 5
        let textHeight: CGFloat

        switch session.floatingCaptionDisplayMode {
        case .original, .translation:
            textHeight = primaryHeight
        case .originalAndTranslation:
            textHeight = primaryHeight + secondaryHeight + 8
        }

        return min(max(90, textHeight + 36), 720)
    }

    private func subtitleText(_ text: String, font: Font) -> some View {
        StreamingTranscriptText(
            text: text.isEmpty ? AppText.noFloatingCaptionsYet : text,
            font: font,
            foregroundColor: .white,
            isTextSelectionEnabled: false,
            lineLimit: lineLimit,
            textAlignment: session.floatingCaptionTextAlignment.textAlignment,
            frameAlignment: session.floatingCaptionTextAlignment.frameAlignment,
            truncationMode: .tail
        )
        .multilineTextAlignment(session.floatingCaptionTextAlignment.textAlignment)
        .frame(maxWidth: .infinity, alignment: session.floatingCaptionTextAlignment.frameAlignment)
        .lineSpacing(5)
        .shadow(color: .black.opacity(0.95), radius: 3, x: 0, y: 1)
        .shadow(color: .black.opacity(0.65), radius: 8, x: 0, y: 2)
    }
}
