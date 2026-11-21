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
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false
    @State private var isCopyFeedbackVisible = false
    @State private var copyFeedbackToken = 0

    private static let blockSpacing: CGFloat = 8
    private static let horizontalPadding: CGFloat = AirTranslateDesign.Spacing.lg * 2
    private static let verticalPadding: CGFloat = AirTranslateDesign.Spacing.md * 2

    var body: some View {
        let textSnapshot = FloatingCaptionTextSnapshot(
            mode: session.floatingCaptionDisplayMode,
            source: { sourceText },
            translation: { translationText }
        )
        let hasVisibleCaption = textSnapshot.hasVisibleText || hasVisibleHistory
        let backdrop = session.floatingCaptionStyle.backdrop
        let backdropShape = RoundedRectangle(cornerRadius: session.floatingCaptionStyle.backgroundShape.radius, style: .continuous)

        ZStack {
            AirTranslateDesign.Palette.transparent

            ZStack {
                if hasVisibleCaption && backdrop != .none {
                    backdropShape
                        .fill(
                            Color(red: 0.06, green: 0.075, blue: 0.095)
                                .opacity(reduceTransparency ? 0.96 : backdrop.fillOpacity)
                        )
                        .overlay {
                            backdropShape
                                .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
                        }
                        .allowsHitTesting(false)
                }

                VStack(spacing: Self.blockSpacing) {
                    captionContent(sourceText: textSnapshot.source, translationText: textSnapshot.translation)
                }
                .padding(.horizontal, AirTranslateDesign.Spacing.lg)
                .padding(.vertical, AirTranslateDesign.Spacing.md)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background {
                    if hasVisibleCaption {
                        FloatingCaptionDragSurface()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
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
            let textWidth = max(0, size.width - Self.horizontalPadding - 24)
            let contentHeight = max(0, size.height - Self.verticalPadding - 12)
            if session.floatingCaptionMeasuredTextWidth != textWidth {
                session.floatingCaptionMeasuredTextWidth = textWidth
            }
            if session.floatingCaptionMeasuredContentHeight != contentHeight {
                session.floatingCaptionMeasuredContentHeight = contentHeight
            }
        }
        .contentShape(Rectangle())
        .allowsWindowActivationEvents(true)
        .onHover { isHovering = $0 }
        .overlay(alignment: .topTrailing) {
            if isHovering && hasVisibleCaption {
                FloatingCaptionHoverHUD(
                    session: session,
                    isCopyFeedbackVisible: isCopyFeedbackVisible,
                    copyLatestCaption: {
                        if copyLatestText(snapshot: textSnapshot) {
                            copyFeedbackToken += 1
                            withAnimation(reduceMotion ? nil : AirTranslateDesign.Motion.quick) {
                                isCopyFeedbackVisible = true
                            }
                        }
                    }
                )
                .padding(.top, 12)
                .padding(.trailing, 20)
                .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : AirTranslateDesign.Motion.quick, value: isHovering)
        .task(id: copyFeedbackToken) {
            guard isCopyFeedbackVisible else { return }
            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled else { return }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
                isCopyFeedbackVisible = false
            }
        }
        .background(
            FloatingWindowConfigurator(
                preferredContentHeight: preferredHeight,
                minimumWindowSize: session.floatingCaptionMinimumWindowSize,
                keepsAboveOtherWindows: session.keepsFloatingCaptionAboveOtherWindows,
                hasCaptionText: hasVisibleCaption
            )
        )
    }

    private func copyLatestText(snapshot: FloatingCaptionTextSnapshot) -> Bool {
        let primary = !snapshot.translation.isEmpty ? snapshot.translation : snapshot.source
        let trimmed = primary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != AppText.translating else { return false }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(trimmed, forType: .string)
        return true
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
        .modifier(
            CaptionTextEffectModifier(
                effect: session.floatingCaptionStyle.textEffect,
                hasBackdrop: session.floatingCaptionStyle.backdrop != .none
            )
        )
    }
}

private struct FloatingCaptionHoverHUD: View {
    @Bindable var session: TranslationSessionStore
    let isCopyFeedbackVisible: Bool
    let copyLatestCaption: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusDotColor)
                .frame(width: 7, height: 7)
                .accessibilityHidden(true)

            if session.isRunning {
                Button {
                    session.isPaused ? session.resume() : session.pause()
                } label: {
                    Image(systemName: session.isPaused ? "play.fill" : "pause.fill")
                        .frame(width: 24, height: 22)
                }
                .disabled(!session.captureControlState.canTogglePause)
                .help(session.isPaused ? AppText.resume : AppText.pause)
                .accessibilityLabel(session.isPaused ? AppText.resume : AppText.pause)
            }

            Button(action: copyLatestCaption) {
                Image(systemName: isCopyFeedbackVisible ? "checkmark" : "doc.on.doc")
                    .foregroundStyle(isCopyFeedbackVisible ? AirTranslateDesign.Palette.accent : Color.white.opacity(0.9))
                    .frame(width: 24, height: 22)
            }
            .help(isCopyFeedbackVisible ? AppText.copied : AppText.copy)
            .accessibilityLabel(AppText.copy)

            if !session.isTranscribeOnlyMode {
                Button {
                    cycleDisplayMode()
                } label: {
                    Text(displayModeBadge)
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(AirTranslateDesign.Palette.accent.opacity(0.24), in: Capsule())
                        .foregroundStyle(AirTranslateDesign.Palette.accentBright)
                }
                .help(AppText.captionDisplayMode)
                .accessibilityLabel(AppText.captionDisplayMode)
                .accessibilityValue(session.floatingCaptionDisplayMode.title)
            }

            Button {
                CaptionControlActions.adjustTextSize(session: session, by: -2)
            } label: {
                Text("A-")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 22, height: 22)
            }
            .disabled(session.floatingCaptionPrimaryPointSize <= FloatingCaptionAppearance.customPointSizeRange.lowerBound)
            .help(AppText.makeCaptionTextSmaller)
            .accessibilityLabel(AppText.makeCaptionTextSmaller)

            Button {
                CaptionControlActions.adjustTextSize(session: session, by: 2)
            } label: {
                Text("A+")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 22, height: 22)
            }
            .disabled(session.floatingCaptionPrimaryPointSize >= FloatingCaptionAppearance.customPointSizeRange.upperBound)
            .help(AppText.makeCaptionTextLarger)
            .accessibilityLabel(AppText.makeCaptionTextLarger)

            Button {
                cycleBackdrop()
            } label: {
                Image(systemName: session.floatingCaptionStyle.backdrop == .none ? "rectangle.dashed" : "rectangle.fill")
                    .frame(width: 24, height: 22)
            }
            .help(CaptionStyleCopy.backdrop)
            .accessibilityLabel(CaptionStyleCopy.backdrop)
            .accessibilityValue(session.floatingCaptionStyle.backdrop.title)

            Button {
                FloatingCaptionWindowController.close()
            } label: {
                Image(systemName: "xmark")
                    .frame(width: 22, height: 22)
            }
            .help(CaptionStyleCopy.closeWindow)
            .accessibilityLabel(CaptionStyleCopy.closeWindow)
        }
        .buttonStyle(.plain)
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(Color.white.opacity(0.92))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color(red: 0.08, green: 0.10, blue: 0.13).opacity(0.92), in: Capsule())
        .overlay {
            Capsule().strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
        }
    }

    private var statusDotColor: Color {
        if session.isPaused { return AirTranslateDesign.Palette.paused }
        if session.isRunning { return AirTranslateDesign.Palette.live }
        return AirTranslateDesign.Palette.accent
    }

    private var displayModeBadge: String {
        switch session.floatingCaptionDisplayMode {
        case .originalAndTranslation: "2L"
        case .translation: "TR"
        case .original: "SRC"
        }
    }

    private func cycleDisplayMode() {
        let modes = session.availableFloatingCaptionDisplayModes
        guard let index = modes.firstIndex(of: session.floatingCaptionDisplayMode), !modes.isEmpty else { return }
        session.floatingCaptionDisplayMode = modes[(index + 1) % modes.count]
    }

    private func cycleBackdrop() {
        let cases = FloatingCaptionBackdrop.allCases
        guard let index = cases.firstIndex(of: session.floatingCaptionStyle.backdrop), !cases.isEmpty else { return }
        session.floatingCaptionStyle.backdrop = cases[(index + 1) % cases.count]
    }
}
