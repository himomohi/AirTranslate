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

    let formattedText: String
    let expiresAt: Date
    let font: Font
    let color: Color
    let lineCount: Int
    let alignment: FloatingCaptionTextAlignment
    let lineSpacing: CGFloat
    let effect: FloatingCaptionTextEffect

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.formattedText == rhs.formattedText && lhs.expiresAt == rhs.expiresAt && lhs.font == rhs.font
            && lhs.color == rhs.color && lhs.lineCount == rhs.lineCount && lhs.alignment == rhs.alignment
            && lhs.lineSpacing == rhs.lineSpacing && lhs.effect == rhs.effect
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

private struct FloatingCaptionAlignedCurrentBlock: View, Equatable {
    let text: String
    let font: Font
    let color: Color
    let lineLimit: Int
    let height: CGFloat
    let alignment: FloatingCaptionTextAlignment
    let verticalAlignment: VerticalAlignment
    let lineSpacing: CGFloat
    let effect: FloatingCaptionTextEffect
    let hasBackdrop: Bool

    var body: some View {
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
            .lineSpacing(lineSpacing)
            .frame(maxWidth: .infinity, minHeight: height, maxHeight: height, alignment: alignment.frameAlignment(vertical: verticalAlignment))
            .clipped()
            .modifier(
                CaptionTextEffectModifier(
                    effect: effect,
                    hasBackdrop: hasBackdrop
                )
            )
    }
}

struct FloatingCaptionWindowView: View {
    @Bindable var session: TranslationSessionStore

    private static let horizontalPadding: CGFloat = AirTranslateDesign.Spacing.lg * 2
    private static let verticalPadding: CGFloat = AirTranslateDesign.Spacing.md * 2

    var body: some View {
        FloatingCaptionInteractiveShell(session: session) {
            FloatingCaptionStageView(session: session)
        }
        .frame(
            minWidth: FloatingCaptionWindowController.minimumWindowSize.width,
            idealWidth: FloatingCaptionWindowController.defaultWindowSize.width,
            maxWidth: .infinity,
            minHeight: session.floatingCaptionMinimumWindowHeight,
            idealHeight: session.floatingCaptionPreferredWindowHeight,
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
        .background(FloatingWindowConfiguratorBridge(session: session))
    }

    static func blockHeight(lineHeight: CGFloat, lineCount: Int) -> CGFloat {
        FloatingCaptionAppearance.blockHeight(lineHeight: lineHeight, lineCount: lineCount)
    }
}

private struct FloatingCaptionInteractiveShell<Content: View>: View {
    let session: TranslationSessionStore
    let content: Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false
    @State private var isCopyFeedbackVisible = false
    @State private var copyFeedbackToken = 0

    init(session: TranslationSessionStore, @ViewBuilder content: () -> Content) {
        self.session = session
        self.content = content()
    }

    var body: some View {
        content
            .contentShape(Rectangle())
            .allowsWindowActivationEvents(true)
            .onHover { isHovering = $0 }
            .overlay(alignment: .topTrailing) {
                if isHovering && hasVisibleCaption(in: session) {
                    FloatingCaptionHoverHUD(
                        session: session,
                        isCopyFeedbackVisible: isCopyFeedbackVisible,
                        copyLatestCaption: {
                            if copyLatestText() {
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
    }

    private func copyLatestText() -> Bool {
        let snapshot = currentSnapshot(for: session)
        let primary = !snapshot.translation.isEmpty ? snapshot.translation : snapshot.source
        let trimmed = primary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != AppText.translating else { return false }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(trimmed, forType: .string)
        return true
    }
}

private struct FloatingCaptionStageView: View {
    private static let blockSpacing: CGFloat = 8

    let session: TranslationSessionStore
    @State private var historyLayoutCache = FloatingCaptionLayoutCache()

    var body: some View {
        let textSnapshot = currentSnapshot(for: session)
        let hasVisibleCaption = textSnapshot.hasVisibleText || hasVisibleHistory(in: session)

        ZStack {
            AirTranslateDesign.Palette.transparent

            ZStack {
                FloatingCaptionBackdropView(session: session, isVisible: hasVisibleCaption)

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

    private var lineLimit: Int {
        session.floatingCaptionEffectiveLineCount
    }

    private var primaryBlockHeight: CGFloat {
        FloatingCaptionAppearance.blockHeight(
            lineHeight: session.floatingCaptionPrimaryLineHeight,
            lineCount: lineLimit,
            lineSpacing: session.floatingCaptionStyle.lineSpacing.points
        )
    }

    private var secondaryBlockHeight: CGFloat {
        FloatingCaptionAppearance.blockHeight(
            lineHeight: session.floatingCaptionSecondaryLineHeight,
            lineCount: lineLimit,
            lineSpacing: session.floatingCaptionStyle.lineSpacing.points
        )
    }

    private func primaryBlock(_ text: String, previous: FloatingCaptionHistory.Previous?, anchor: VerticalAlignment) -> some View {
        captionPane(
            text,
            previous: previous,
            font: session.floatingCaptionPrimaryFont,
            color: session.floatingCaptionTextColor,
            height: primaryBlockHeight,
            lineHeight: session.floatingCaptionPrimaryLineHeight,
            usesPrimaryFont: true,
            anchor: anchor
        )
    }

    private func secondaryBlock(_ text: String, previous: FloatingCaptionHistory.Previous?, anchor: VerticalAlignment) -> some View {
        captionPane(
            text,
            previous: previous,
            font: session.floatingCaptionSecondaryFont,
            color: session.floatingCaptionTextColor.opacity(0.82),
            height: secondaryBlockHeight,
            lineHeight: session.floatingCaptionSecondaryLineHeight,
            usesPrimaryFont: false,
            anchor: anchor
        )
    }

    private func captionPane(
        _ text: String,
        previous: FloatingCaptionHistory.Previous?,
        font: Font,
        color: Color,
        height: CGFloat,
        lineHeight: CGFloat,
        usesPrimaryFont: Bool,
        anchor: VerticalAlignment
    ) -> some View {
        let style = session.floatingCaptionStyle
        let alignment = session.floatingCaptionTextAlignment
        let lineSpacing = style.lineSpacing.points
        let historyLines = session.floatingCaptionHistoryLayout.historyLines
        let historyHeight = FloatingCaptionAppearance.blockHeight(
            lineHeight: lineHeight,
            lineCount: historyLines,
            lineSpacing: lineSpacing
        )
        // 조판된 현재 줄 수만 차지하게 해 짧은 자막 위의 이전 자막이 멀리 떨어지지 않게 한다.
        // 바깥 높이는 예약된 줄 수 그대로 유지하므로 현재 자막의 기준 위치와 창 크기는 고정된다.
        let visibleLineCount = min(lineLimit, max(1, text.split(separator: "\n").count))
        let visibleHeight = FloatingCaptionAppearance.blockHeight(
            lineHeight: lineHeight,
            lineCount: visibleLineCount,
            lineSpacing: lineSpacing
        )
        let paneHeight = height + (historyLines > 0
            ? historyHeight + FloatingCaptionHistoryLayout.historyMotionHeight + FloatingCaptionHistoryLayout.historySpacing : 0)

        return VStack(spacing: historyLines > 0 ? FloatingCaptionHistoryLayout.historySpacing : 0) {
            if historyLines > 0 {
                ZStack(alignment: alignment.frameAlignment(vertical: .bottom)) {
                    Color.clear
                    if !session.isPreviewingFloatingCaptions, let previous {
                        let availableWidth = session.floatingCaptionMeasuredTextWidth
                        let nativeFont = style.nativeFont(
                            size: usesPrimaryFont ? session.floatingCaptionPrimaryPointSize : session.floatingCaptionSecondaryPointSize,
                            primary: usesPrimaryFont
                        )
                        let fallbackWidthUnits = session.floatingCaptionLineWidthUnits(usesPrimaryFont: usesPrimaryFont)
                        let formattedHistory = historyLayoutCache.text(
                            previous.caption.text,
                            maxLines: historyLines,
                            availableWidth: availableWidth,
                            font: nativeFont,
                            fallbackWidthUnits: fallbackWidthUnits
                        )
                        FloatingCaptionPreviousBlock(
                            formattedText: formattedHistory,
                            expiresAt: previous.expiresAt,
                            font: font,
                            color: color,
                            lineCount: historyLines,
                            alignment: alignment,
                            lineSpacing: lineSpacing,
                            effect: style.textEffect
                        )
                        .equatable()
                        .id(previous)
                    }
                }
                .frame(height: historyHeight + FloatingCaptionHistoryLayout.historyMotionHeight)
                .clipped()
                .accessibilityHidden(true)
            }

            FloatingCaptionAlignedCurrentBlock(
                text: text,
                font: font,
                color: color,
                lineLimit: lineLimit,
                height: visibleHeight,
                alignment: alignment,
                verticalAlignment: anchor,
                lineSpacing: lineSpacing,
                effect: style.textEffect,
                hasBackdrop: style.backdrop != .none
            )
            .equatable()
            .transaction { $0.animation = nil }
        }
        .frame(height: paneHeight, alignment: alignment.frameAlignment(vertical: anchor))
    }
}

private struct FloatingCaptionBackdropView: View {
    let session: TranslationSessionStore
    let isVisible: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        let backdrop = session.floatingCaptionStyle.backdrop
        if isVisible && backdrop != .none {
            let backdropShape = RoundedRectangle(
                cornerRadius: session.floatingCaptionStyle.backgroundShape.radius,
                style: .continuous
            )
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
    }
}

private struct FloatingWindowConfiguratorBridge: View {
    let session: TranslationSessionStore

    var body: some View {
        EquatableFloatingWindowConfigurator(
            preferredContentHeight: session.floatingCaptionPreferredWindowHeight,
            minimumWindowSize: session.floatingCaptionMinimumWindowSize,
            keepsAboveOtherWindows: session.keepsFloatingCaptionAboveOtherWindows,
            hasCaptionText: hasVisibleCaption(in: session)
        )
        .equatable()
    }
}

private struct EquatableFloatingWindowConfigurator: View, Equatable {
    let preferredContentHeight: CGFloat
    let minimumWindowSize: NSSize
    let keepsAboveOtherWindows: Bool
    let hasCaptionText: Bool

    var body: some View {
        FloatingWindowConfigurator(
            preferredContentHeight: preferredContentHeight,
            minimumWindowSize: minimumWindowSize,
            keepsAboveOtherWindows: keepsAboveOtherWindows,
            hasCaptionText: hasCaptionText
        )
    }
}

@MainActor
private func currentSnapshot(for session: TranslationSessionStore) -> FloatingCaptionTextSnapshot {
    FloatingCaptionTextSnapshot(
        mode: session.floatingCaptionDisplayMode,
        source: {
            session.isPreviewingFloatingCaptions
                ? session.floatingCaptionText(from: CaptionStyleCopy.sampleOriginal, usesPrimaryFont: session.floatingCaptionDisplayMode == .original)
                : session.floatingSourceText
        },
        translation: {
            session.isPreviewingFloatingCaptions
                ? session.floatingCaptionText(from: CaptionStyleCopy.sampleTranslation)
                : session.floatingTranslationText
        }
    )
}

@MainActor
private func hasVisibleHistory(in session: TranslationSessionStore) -> Bool {
    guard !session.isPreviewingFloatingCaptions, session.floatingCaptionHistoryLayout.historyLines > 0 else { return false }
    return (session.floatingCaptionDisplayMode != .translation && session.floatingCaptionHistory.previousSource != nil)
        || (session.floatingCaptionDisplayMode != .original && session.floatingCaptionHistory.previousTranslation != nil)
}

@MainActor
private func hasVisibleCaption(in session: TranslationSessionStore) -> Bool {
    currentSnapshot(for: session).hasVisibleText || hasVisibleHistory(in: session)
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
