import AppKit
import SwiftUI

struct CaptionBoardView: View {
    @Bindable var session: TranslationSessionStore
    @Binding var viewportState: CaptionFeedViewportState

    var body: some View {
        CaptionTranscriptFeed(session: session, viewportState: $viewportState)
            .frame(maxWidth: 928, maxHeight: .infinity)
            .padding(.horizontal, AirTranslateDesign.Spacing.lg)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct CaptionTranscriptFeed: View {
    private static let stageVisibleLineLimit = 12

    @Bindable var session: TranslationSessionStore
    @Binding var viewportState: CaptionFeedViewportState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var longSessionAutoScrollTask: Task<Void, Never>?
    @State private var scrollPosition = ScrollPosition(idType: UUID.self)
    @State private var lineFrames: [UUID: CGRect] = [:]
    @State private var scrollMetrics: CaptionFeedScrollMetrics?
    @State private var restorationAnchor: CaptionFeedReadingAnchor?
    @State private var initialScrollAnchor: UnitPoint

    init(session: TranslationSessionStore, viewportState: Binding<CaptionFeedViewportState>) {
        self.session = session
        _viewportState = viewportState
        _restorationAnchor = State(initialValue: viewportState.wrappedValue.restorationAnchor)
        _initialScrollAnchor = State(initialValue: viewportState.wrappedValue.followState.isFollowingLatest ? .bottom : .top)
    }

    private struct LatestLineKey: Equatable {
        let id: UUID
        let revision: Int
    }

    private var latestLineKey: LatestLineKey? {
        session.lines.last.map { LatestLineKey(id: $0.id, revision: $0.revision) }
    }

    var body: some View {
        if !session.hasTranscriptContent && !session.isRunning {
            StageEmptyStateView(session: session, description: emptyStateDescription)
        } else {
            transcriptScrollView
        }
    }

    private var emptyStateDescription: String {
        if session.isUsingGeminiTranscriptionMode {
            return AppText.localized(
                english: "Start capture to see automatically detected source captions.",
                korean: "캡처를 시작하면 자동 감지된 원문 자막이 표시됩니다.",
                japanese: "キャプチャを開始すると、自動検出された原文字幕が表示されます。",
                chineseSimplified: "开始采集后，将显示自动检测的原文字幕。"
            )
        }
        if session.isUsingProviderTranscriptionMode || session.isUsingNariSTT || session.isUsingGrokSTT {
            return AppText.gptTranscriptionNoCaptionsDescription(for: session.audioInputSource)
        }
        return AppText.noCaptionsDescription
    }

    private var transcriptScrollView: some View {
        GeometryReader { viewport in
            Group {
                ScrollView {
                    VStack(alignment: .leading, spacing: AirTranslateDesign.Spacing.xs) {
                        if session.shouldShowTranscript && session.lines.isEmpty {
                            Text(AppText.waitingForTranscript)
                                .font(AirTranslateDesign.Typography.label)
                                .foregroundStyle(AirTranslateDesign.Palette.textSecondary)
                                .frame(maxWidth: .infinity, minHeight: 96)
                        }

                        ForEach(session.lines.suffix(Self.stageVisibleLineLimit)) { line in
                            CaptionLineView(
                                line: line,
                                showsTranslationPane: session.shouldShowTranslationPane,
                                isLive: session.isRunning
                                    && line.id == session.lines.last?.id
                                    && !line.isFinal
                            )
                            .equatable()
                            .id(line.id)
                            .background {
                                GeometryReader { lineGeometry in
                                    Color.clear.preference(
                                        key: CaptionFeedLineFramesKey.self,
                                        value: [line.id: lineGeometry.frame(in: .named("captionFeedContent"))]
                                    )
                                }
                            }
                            .transition(.opacity)
                        }
                    }
                    .padding(.vertical, AirTranslateDesign.Spacing.lg)
                    .frame(minHeight: viewport.size.height, alignment: .bottom)
                    .coordinateSpace(name: "captionFeedContent")
                }
                .defaultScrollAnchor(initialScrollAnchor)
                .scrollPosition($scrollPosition)
                .onPreferenceChange(CaptionFeedLineFramesKey.self) { frames in
                    guard !frames.isEmpty else { return }
                    lineFrames = frames
                    restoreOrRecordReadingPosition()
                }
                .onScrollGeometryChange(for: CaptionFeedScrollMetrics.self) { geometry in
                    CaptionFeedScrollMetrics(
                        offsetY: geometry.contentOffset.y,
                        minimumY: -geometry.contentInsets.top,
                        maximumY: max(-geometry.contentInsets.top,
                                      geometry.contentSize.height - geometry.containerSize.height + geometry.contentInsets.bottom)
                    )
                } action: { _, metrics in
                    scrollMetrics = metrics
                    restoreOrRecordReadingPosition()
                }
                .onScrollPhaseChange { _, phase in
                    switch phase {
                    case .tracking, .interacting, .decelerating:
                        restorationAnchor = nil
                        viewportState.followState.setUserScrolling(true)
                        restoreOrRecordReadingPosition()
                        longSessionAutoScrollTask?.cancel()
                        longSessionAutoScrollTask = nil
                    case .idle:
                        viewportState.followState.setUserScrolling(false)
                    case .animating:
                        break
                    }
                }
                .onChange(of: latestLineKey) { oldValue, newValue in
                    guard let newValue, viewportState.followState.shouldFollowUpdates else { return }

                    if newValue.id != oldValue?.id {
                        longSessionAutoScrollTask?.cancel()
                        longSessionAutoScrollTask = nil
                        withAnimation(reduceMotion ? nil : AirTranslateDesign.Motion.enter) {
                            scrollPosition.scrollTo(edge: .bottom)
                        }
                    } else {
                        scrollToLatestRevision()
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if !viewportState.followState.isFollowingLatest, !session.lines.isEmpty {
                        Button {
                            longSessionAutoScrollTask?.cancel()
                            longSessionAutoScrollTask = nil
                            restorationAnchor = nil
                            viewportState.returnToLatest()
                            scrollPosition.scrollTo(edge: .bottom)
                        } label: {
                            Label(AppText.jumpToLatestCaptions, systemImage: "arrow.down.to.line")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .airFocusRing(cornerRadius: AirTranslateDesign.Radius.control)
                        .accessibilityHint(AppText.followLatestCaptionsHint)
                        .padding(AirTranslateDesign.Spacing.md)
                    }
                }
            }
        }
        .mask { TranscriptScrollFadeMask(showsBottomFade: false) }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onDisappear {
            longSessionAutoScrollTask?.cancel()
            longSessionAutoScrollTask = nil
            viewportState.followState.suspendInteraction()
        }
    }

    private func restoreOrRecordReadingPosition() {
        guard let scrollMetrics else { return }
        if scrollPosition.isPositionedByUser {
            restorationAnchor = nil
        }
        if let restorationAnchor {
            // 초기 레이아웃과 본문 첫 표시로 높이가 달라져도 저장한 읽기 위치를 기준으로 삼는다.
            if let offset = restorationAnchor.resolvedOffset(in: lineFrames, metrics: scrollMetrics),
               abs(offset - scrollMetrics.offsetY) > 0.5 {
                scrollPosition.scrollTo(y: offset)
            }
            return
        }
        viewportState.followState.updateLatestVisibility(scrollMetrics.isLatestVisible)
        viewportState.recordReadingPosition(offsetY: scrollMetrics.offsetY, lineFrames: lineFrames)
    }

    private func scrollToLatestRevision() {
        guard session.shouldCoalesceTranscriptAutoScroll else {
            scrollPosition.scrollTo(edge: .bottom)
            return
        }

        longSessionAutoScrollTask?.cancel()
        longSessionAutoScrollTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, viewportState.followState.shouldFollowUpdates else { return }
            scrollPosition.scrollTo(edge: .bottom)
            longSessionAutoScrollTask = nil
        }
    }
}

struct CaptionFeedFollowState: Equatable {
    private(set) var isFollowingLatest = true
    private var isLatestVisible = true
    private var isUserScrolling = false

    var shouldFollowUpdates: Bool { isFollowingLatest && !isUserScrolling }

    mutating func updateLatestVisibility(_ isVisible: Bool) {
        isLatestVisible = isVisible
        // 새 자막으로 내용 높이가 늘어난 것만으로 사용자가 과거를 읽는다고 판단하지 않는다.
        if isUserScrolling || !isFollowingLatest {
            isFollowingLatest = isVisible
        }
    }

    mutating func setUserScrolling(_ isScrolling: Bool) {
        if isUserScrolling && !isScrolling {
            isFollowingLatest = isLatestVisible
        }
        isUserScrolling = isScrolling
    }

    mutating func returnToLatest() {
        isFollowingLatest = true
        isUserScrolling = false
    }

    mutating func suspendInteraction() {
        isUserScrolling = false
    }
}

struct CaptionFeedViewportState: Equatable {
    var followState = CaptionFeedFollowState()
    private(set) var readingAnchor: CaptionFeedReadingAnchor?

    var restorationAnchor: CaptionFeedReadingAnchor? {
        followState.isFollowingLatest ? nil : readingAnchor
    }

    mutating func recordReadingPosition(offsetY: CGFloat, lineFrames: [UUID: CGRect]) {
        guard !followState.isFollowingLatest, offsetY.isFinite else { return }
        let orderedFrames = lineFrames.sorted { $0.value.minY < $1.value.minY }
        guard let visibleLine = orderedFrames.first(where: { $0.value.maxY > offsetY }) ?? orderedFrames.last else { return }
        let anchor = CaptionFeedReadingAnchor(
            lineID: visibleLine.key,
            offsetWithinLine: offsetY - visibleLine.value.minY
        )
        if readingAnchor != anchor { readingAnchor = anchor }
    }

    mutating func returnToLatest() {
        readingAnchor = nil
        followState.returnToLatest()
    }
}

struct CaptionFeedReadingAnchor: Equatable {
    let lineID: UUID
    let offsetWithinLine: CGFloat

    func resolvedOffset(in lineFrames: [UUID: CGRect], metrics: CaptionFeedScrollMetrics) -> CGFloat? {
        let offset: CGFloat
        if let frame = lineFrames[lineID] {
            offset = frame.minY + offsetWithinLine
        } else if let first = lineFrames.values.min(by: { $0.minY < $1.minY }) {
            // 표시 개수 제한으로 읽던 자막이 빠지면 남은 가장 오래된 자막으로 복원한다.
            offset = first.minY
        } else {
            return nil
        }
        return min(metrics.maximumY, max(metrics.minimumY, offset))
    }
}

struct CaptionFeedScrollMetrics: Equatable {
    let offsetY: CGFloat
    let minimumY: CGFloat
    let maximumY: CGFloat

    var isLatestVisible: Bool { maximumY - offsetY <= 48 }
}

private struct CaptionFeedLineFramesKey: PreferenceKey {
    static let defaultValue: [UUID: CGRect] = [:]

    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
}

private struct StageEmptyStateView: View {
    @Bindable var session: TranslationSessionStore
    let description: String

    var body: some View {
        VStack(spacing: AirTranslateDesign.Spacing.lg) {
            Group {
                if session.isStarting {
                    ProgressView()
                        .controlSize(.large)
                        .frame(width: 132, height: 54)
                        .accessibilityHidden(true)
                } else {
                    AudioLevelWaveform(
                        level: nil,
                        date: Date(timeIntervalSinceReferenceDate: 0),
                        barCount: 13,
                        width: 132,
                        height: 54,
                        barWidth: 5,
                        barSpacing: 5
                    )
                }
            }
            .padding(.bottom, AirTranslateDesign.Spacing.xs)

            VStack(spacing: AirTranslateDesign.Spacing.xs) {
                Text(session.isStarting ? AppText.preparingToListen : AppText.readyToStartListening)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(AirTranslateDesign.Palette.textPrimary)
                    .multilineTextAlignment(.center)

                Text("\(session.languageSummary) · \(session.processingEngineTitle)")
                    .font(AirTranslateDesign.Typography.label)
                    .foregroundStyle(AirTranslateDesign.Palette.textSecondary)
                    .lineLimit(1)
            }

            if !session.isStarting, PermissionActionButton(session: session).needsPermissionAction {
                HStack(spacing: AirTranslateDesign.Spacing.sm) {
                    Image(systemName: "lock.shield.fill")
                        .foregroundStyle(AirTranslateDesign.Palette.warning)
                    VStack(alignment: .leading, spacing: AirTranslateDesign.Spacing.xxs) {
                        Text(AppText.permissionRequired)
                            .font(AirTranslateDesign.Typography.label.weight(.semibold))
                            .foregroundStyle(AirTranslateDesign.Palette.textPrimary)
                        Text(session.statusMessage)
                            .font(AirTranslateDesign.Typography.meta)
                            .foregroundStyle(AirTranslateDesign.Palette.textSecondary)
                    }
                    Spacer(minLength: AirTranslateDesign.Spacing.sm)
                    PermissionActionButton(session: session)
                }
                .padding(AirTranslateDesign.Spacing.md)
                .frame(maxWidth: 560)
                .airRaisedSurface()
            }

            Button {
                if session.isStarting {
                    session.stop()
                } else {
                    session.start()
                }
            } label: {
                Label(
                    session.isStarting ? AppText.cancel : AppText.startListening,
                    systemImage: session.isStarting ? "xmark" : "play.fill"
                )
                    .frame(minHeight: 48)
            }
            .buttonStyle(AirPillButtonStyle(kind: session.isStarting ? .stop : .start))
            .accessibilityHint(session.isStarting ? session.statusMessage : description)

            Text(session.isStarting ? session.statusMessage : description)
                .font(AirTranslateDesign.Typography.meta)
                .foregroundStyle(AirTranslateDesign.Palette.textSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(maxWidth: 560)
        }
        .padding(AirTranslateDesign.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct CaptionLineView: View, Equatable {
    let line: CaptionLine
    let showsTranslationPane: Bool
    let isLive: Bool

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.line.id == rhs.line.id
            && lhs.line.revision == rhs.line.revision
            && lhs.showsTranslationPane == rhs.showsTranslationPane
            && lhs.isLive == rhs.isLive
    }

    var body: some View {
        HStack(alignment: .top, spacing: AirTranslateDesign.Spacing.md) {
            if let speakerLabel = line.speakerLabel {
                AirChip(
                    text: AppText.speakerLabel(speakerLabel),
                    systemImage: "person.fill",
                    tint: AirTranslateDesign.Palette.accent
                )
                .frame(width: 72, alignment: .leading)
                .accessibilityLabel(AppText.speakerLabel(speakerLabel))
            }

            VStack(alignment: .leading, spacing: AirTranslateDesign.Spacing.xs) {
                if showsTranslationPane {
                    TurnTranscriptText(
                        lineID: line.id,
                        title: AppText.original,
                        text: line.sourceText,
                        displayText: line.sourceDisplayText,
                        holdsLiveRewrites: isLive,
                        font: AirTranslateDesign.Typography.captionOriginal,
                        lineSpacing: 4,
                        color: AirTranslateDesign.Palette.textSecondary
                    )

                    TurnTranscriptText(
                        lineID: line.id,
                        title: AppText.translation,
                        text: line.translatedText,
                        displayText: line.translatedDisplayText,
                        holdsLiveRewrites: isLive,
                        font: AirTranslateDesign.Typography.captionTranslation,
                        lineSpacing: 6,
                        color: AirTranslateDesign.Palette.textPrimary
                    )
                } else {
                    TurnTranscriptText(
                        lineID: line.id,
                        title: AppText.original,
                        text: line.sourceText,
                        displayText: line.sourceDisplayText,
                        holdsLiveRewrites: isLive,
                        font: AirTranslateDesign.Typography.captionTranslation,
                        lineSpacing: 6,
                        color: AirTranslateDesign.Palette.textPrimary
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .airStageBlock(isLive: isLive)
    }
}

private struct TurnTranscriptText: View {
    let lineID: UUID
    let title: String
    let text: String
    let displayText: String
    let holdsLiveRewrites: Bool
    let font: Font
    let lineSpacing: CGFloat
    let color: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var displayState = CaptionDisplayUpdatePolicy.State()
    @State private var didInitializeDisplayState = false
    @State private var displayHoldTask: Task<Void, Never>?
    @State private var isTextOverflowing = false
    @State private var isReadingBack = false
    @State private var isCopyFeedbackVisible = false
    @State private var copyFeedbackToken = 0
    @State private var isHovering = false
    @FocusState private var isCopyFocused: Bool
    @AccessibilityFocusState private var isCopyAccessibilityFocused: Bool

    private let displayPolicy = CaptionDisplayUpdatePolicy()

    var body: some View {
        VStack(alignment: .leading, spacing: AirTranslateDesign.Spacing.xxs) {
            HStack(spacing: AirTranslateDesign.Spacing.xs) {
                Text(title.uppercased())
                    .font(.system(size: 12, weight: .medium))
                    .tracking(0.6)
                    .foregroundStyle(AirTranslateDesign.Palette.textSecondary)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                Button {
                    if copyText() {
                        showCopyFeedback()
                    }
                } label: {
                    Image(systemName: isCopyFeedbackVisible ? "checkmark" : "doc.on.doc")
                        .font(AirTranslateDesign.Typography.meta.weight(.medium))
                        .foregroundStyle(
                            isCopyFeedbackVisible
                                ? AirTranslateDesign.Palette.accent
                                : AirTranslateDesign.Palette.textTertiary
                        )
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(AirTranslatePressButtonStyle())
                .controlSize(.small)
                .focused($isCopyFocused)
                .accessibilityFocused($isCopyAccessibilityFocused)
                .opacity(isCopyControlVisible ? 1 : 0)
                .disabled(!canCopy)
                .help(isCopyFeedbackVisible ? AppText.copied : AppText.copyTranscriptPane(title))
                .accessibilityLabel(AppText.copyTranscriptPane(title))
                .accessibilityValue(isCopyFeedbackVisible ? AppText.copied : AppText.copy)
                .accessibilityRespondsToUserInteraction(true)
                .accessibilityHidden(!canCopy)
            }

            if text.utf8.count > 4_000 && text.count > 4_000 {
                ScrollableTranscriptText(
                    text: visibleDisplayText,
                    weight: .medium,
                    pointSize: 22,
                    accessibilityLabel: title,
                    isOverflowing: $isTextOverflowing,
                    isReadingBack: $isReadingBack
                )
                .frame(maxWidth: .infinity, minHeight: 90, maxHeight: 180)
                .mask {
                    if isTextOverflowing && isReadingBack {
                        TranscriptScrollFadeMask()
                    } else {
                        Rectangle()
                    }
                }
            } else {
                StreamingTranscriptText(
                    text: visibleDisplayText,
                    font: font,
                    foregroundColor: color,
                    streamsAppendedTextInChunks: false,
                    replacementCrossfadeDuration: reduceMotion ? 0 : 0.1
                )
                .lineSpacing(lineSpacing)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .onHover { isHovering = $0 }
        .animation(reduceMotion ? nil : AirTranslateDesign.Motion.quick, value: isHovering)
        .onAppear {
            applyDisplayUpdate(displayText, canHoldRewrite: holdsLiveRewrites)
        }
        .onChange(of: displayText) { _, newDisplayText in
            applyDisplayUpdate(newDisplayText, canHoldRewrite: holdsLiveRewrites)
        }
        .onChange(of: holdsLiveRewrites) { _, canHoldRewrite in
            applyDisplayUpdate(displayText, canHoldRewrite: canHoldRewrite)
        }
        .onDisappear {
            displayHoldTask?.cancel()
            displayHoldTask = nil
        }
        .task(id: copyFeedbackToken) {
            guard isCopyFeedbackVisible else { return }

            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled else { return }

            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
                isCopyFeedbackVisible = false
            }
        }
    }

    private var visibleDisplayText: String {
        didInitializeDisplayState ? displayState.visibleText : displayText
    }

    private var isCopyControlVisible: Bool {
        isHovering || isCopyFeedbackVisible || isCopyFocused || isCopyAccessibilityFocused
    }

    private var canCopy: Bool {
        text.rangeOfCharacter(from: .whitespacesAndNewlines.inverted) != nil
            && text != AppText.translating
    }

    private func copyText() -> Bool {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty, trimmedText != AppText.translating else { return false }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(trimmedText, forType: .string)
        return true
    }

    private func showCopyFeedback() {
        copyFeedbackToken += 1

        withAnimation(reduceMotion ? nil : AirTranslateDesign.Motion.quick) {
            isCopyFeedbackVisible = true
        }
    }

    private func applyDisplayUpdate(_ candidateText: String, canHoldRewrite: Bool) {
        let previousText = didInitializeDisplayState ? displayState.visibleText : ""
        if !didInitializeDisplayState {
            displayState.visibleText = visibleDisplayText
            didInitializeDisplayState = true
        }

        displayHoldTask?.cancel()

        let decision = displayPolicy.receive(
            candidateText,
            at: Date(),
            // 대기 문구는 읽기 시간을 보호할 번역 결과가 아니다.
            canHoldRewrite: canHoldRewrite && displayState.visibleText != AppText.translating,
            state: &displayState
        )
        handleDisplayDecision(decision)
        recordDisplayChange(from: previousText)
    }

    private func handleDisplayDecision(_ decision: CaptionDisplayUpdatePolicy.Decision) {
        switch decision {
        case .unchanged, .published:
            displayHoldTask = nil
        case .held(let holdUntil):
            scheduleDisplayFlush(at: holdUntil)
        }
    }

    private func scheduleDisplayFlush(at holdUntil: Date) {
        let delay = max(0, holdUntil.timeIntervalSinceNow)
        let nanoseconds = UInt64((delay * 1_000_000_000).rounded(.up))

        displayHoldTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled else { return }

            let previousText = displayState.visibleText
            let decision = displayPolicy.flushDueRewrite(at: Date(), state: &displayState)
            handleDisplayDecision(decision)
            recordDisplayChange(from: previousText)
        }
    }

    private func recordDisplayChange(from previousText: String) {
        guard PipelineDiagnostics.isEnabled,
              previousText != displayState.visibleText,
              displayState.visibleText != AppText.translating else { return }
        let replacesReadableText = !previousText.isEmpty && previousText != AppText.translating
            && !displayState.visibleText.hasPrefix(previousText)
        PipelineDiagnostics.record(
            title == AppText.translation ? "board.translation" : "board.source",
            id: lineID.uuidString,
            values: [
                "characters": Double(displayState.visibleText.count),
                "rewrite": replacesReadableText ? 1 : 0
            ]
        )
    }
}

private struct TranscriptScrollFadeMask: View {
    var showsBottomFade = true

    var body: some View {
        VStack(spacing: 0) {
            LinearGradient(
                stops: [
                    .init(color: AirTranslateDesign.Palette.transparent, location: 0),
                    .init(color: AirTranslateDesign.Palette.maskOpaque, location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 18)

            Rectangle()
                .fill(AirTranslateDesign.Palette.maskOpaque)

            if showsBottomFade {
                LinearGradient(
                    stops: [
                        .init(color: AirTranslateDesign.Palette.maskOpaque, location: 0),
                        .init(color: AirTranslateDesign.Palette.transparent, location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 18)
            }
        }
    }
}

private struct ScrollableTranscriptText: NSViewRepresentable {
    let text: String
    let weight: NSFont.Weight
    let pointSize: CGFloat
    let accessibilityLabel: String
    @Binding var isOverflowing: Bool
    @Binding var isReadingBack: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(isOverflowing: $isOverflowing, isReadingBack: $isReadingBack)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = false
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.contentView.postsBoundsChangedNotifications = true
        scrollView.setAccessibilityLabel(accessibilityLabel)

        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.drawsBackground = false
        textView.textColor = .labelColor
        textView.font = NSFont.systemFont(ofSize: pointSize, weight: weight)
        textView.textContainerInset = NSSize(width: 0, height: 0)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.frame = NSRect(origin: .zero, size: scrollView.contentSize)
        textView.autoresizingMask = [.width]
        textView.setAccessibilityLabel(accessibilityLabel)

        scrollView.documentView = textView
        context.coordinator.attach(to: scrollView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }

        let contentWidth = scrollView.contentSize.width
        let textChanged = textView.string != text
        let widthChanged = abs(context.coordinator.lastContentWidth - contentWidth) > 0.5
        let weightChanged = context.coordinator.lastWeight != weight
        guard textChanged || widthChanged || weightChanged else { return }

        let shouldStayPinnedToBottom = isPinnedToBottom(scrollView)
        if textChanged {
            textView.string = text
        }

        textView.font = NSFont.systemFont(ofSize: pointSize, weight: weight)
        textView.textColor = .labelColor
        scrollView.setAccessibilityLabel(accessibilityLabel)
        textView.setAccessibilityLabel(accessibilityLabel)
        textView.textContainer?.containerSize = NSSize(
            width: contentWidth,
            height: CGFloat.greatestFiniteMagnitude
        )
        let documentHeight = updateDocumentSize(textView, in: scrollView)
        context.coordinator.recordLayoutInput(
            contentWidth: contentWidth,
            weight: weight
        )
        let isOverflowing = documentHeight > scrollView.contentSize.height + 1
        context.coordinator.updateState(
            isOverflowing: isOverflowing,
            isReadingBack: isOverflowing && !shouldStayPinnedToBottom
        )

        if shouldStayPinnedToBottom {
            textView.scrollToEndOfDocument(nil)
            context.coordinator.updateState(isOverflowing: isOverflowing, isReadingBack: false)
        }
    }

    private func updateDocumentSize(_ textView: NSTextView, in scrollView: NSScrollView) -> CGFloat {
        guard let textContainer = textView.textContainer,
              let layoutManager = textView.layoutManager
        else {
            textView.frame.size = scrollView.contentSize
            return scrollView.contentSize.height
        }

        layoutManager.ensureLayout(for: textContainer)
        let usedHeight = layoutManager.usedRect(for: textContainer).height + textView.textContainerInset.height * 2
        textView.frame.size = NSSize(
            width: scrollView.contentSize.width,
            height: max(scrollView.contentSize.height, usedHeight)
        )
        return usedHeight
    }

    private func isPinnedToBottom(_ scrollView: NSScrollView) -> Bool {
        guard let documentView = scrollView.documentView else { return true }

        let visibleMaxY = scrollView.contentView.bounds.maxY
        let documentHeight = documentView.bounds.height
        return documentHeight <= scrollView.contentSize.height || documentHeight - visibleMaxY < 24
    }

    @MainActor
    final class Coordinator: NSObject {
        private var isOverflowing: Binding<Bool>
        private var isReadingBack: Binding<Bool>
        private weak var scrollView: NSScrollView?
        var lastContentWidth: CGFloat = -1
        var lastWeight: NSFont.Weight?

        init(isOverflowing: Binding<Bool>, isReadingBack: Binding<Bool>) {
            self.isOverflowing = isOverflowing
            self.isReadingBack = isReadingBack
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        func attach(to scrollView: NSScrollView) {
            self.scrollView = scrollView
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(contentBoundsDidChange),
                name: NSView.boundsDidChangeNotification,
                object: scrollView.contentView
            )
        }

        func updateState(isOverflowing: Bool, isReadingBack: Bool) {
            guard self.isOverflowing.wrappedValue != isOverflowing
                || self.isReadingBack.wrappedValue != isReadingBack
            else {
                return
            }

            self.isOverflowing.wrappedValue = isOverflowing
            self.isReadingBack.wrappedValue = isReadingBack
        }

        func recordLayoutInput(contentWidth: CGFloat, weight: NSFont.Weight) {
            lastContentWidth = contentWidth
            lastWeight = weight
        }

        @objc private func contentBoundsDidChange() {
            guard let scrollView else { return }
            let isOverflowing = hasOverflow(scrollView)
            updateState(
                isOverflowing: isOverflowing,
                isReadingBack: isOverflowing && !isPinnedToBottom(scrollView)
            )
        }

        private func hasOverflow(_ scrollView: NSScrollView) -> Bool {
            guard let documentView = scrollView.documentView else { return false }
            return documentView.bounds.height > scrollView.contentSize.height + 1
        }

        private func isPinnedToBottom(_ scrollView: NSScrollView) -> Bool {
            guard let documentView = scrollView.documentView else { return true }

            let visibleMaxY = scrollView.contentView.bounds.maxY
            let documentHeight = documentView.bounds.height
            return documentHeight <= scrollView.contentSize.height || documentHeight - visibleMaxY < 24
        }
    }
}

private struct SessionOverviewCard: View {
    let session: TranslationSessionStore
    let title: String
    let subtitle: String
    let isRunning: Bool
    let isStarting: Bool
    let isPaused: Bool
    let statusMessage: String
    let isFloatingCaptionVisible: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "captions.bubble.fill")
                .font(.system(size: AirTranslateDesign.iconRegular, weight: .semibold))
                .foregroundStyle(AirTranslateDesign.Palette.accent)
                .frame(width: 24, height: 24)
                .overlay(alignment: .topTrailing) {
                    if isFloatingCaptionVisible {
                        Circle()
                            .fill(AirTranslateDesign.Palette.live)
                            .frame(width: 7, height: 7)
                            .padding(4)
                            .accessibilityHidden(true)
                    }
                }
                .help(headerIconHelp)
                .accessibilityLabel(title)
                .accessibilityValue(headerIconValue)
                .animation(
                    reduceMotion ? nil : .spring(response: 0.22, dampingFraction: 0.78),
                    value: isFloatingCaptionVisible
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(AirTranslateDesign.Palette.textPrimary)
                    .lineLimit(1)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(AirTranslateDesign.Palette.textSecondary)
                    .lineLimit(1)
            }
            .layoutPriority(1)

            Spacer(minLength: 12)

            Group {
                if isRunning {
                    HeaderAudioLevelStrip(
                        session: session,
                        isPaused: isPaused
                    )
                } else {
                    HeaderStatusMessage(
                        statusMessage: statusMessage,
                        isStarting: isStarting,
                        isBlocked: isBlocked
                    )
                }
            }
            .frame(maxWidth: 300, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .frame(minHeight: 50)
        .airTranslateSurface()
    }

    private var headerIconHelp: String {
        "\(title) · \(subtitle) · \(AppText.floatingCaptions): \(floatingCaptionStateTitle)"
    }

    private var headerIconValue: String {
        "\(subtitle), \(AppText.floatingCaptions) \(floatingCaptionStateTitle)"
    }

    private var floatingCaptionStateTitle: String {
        isFloatingCaptionVisible ? AppText.floatingCaptionPowerOn : AppText.floatingCaptionPowerOff
    }

    private var isBlocked: Bool {
        !isRunning
            && !isStarting
            && statusMessage != AppText.ready
            && statusMessage != AppText.stopped
            && statusMessage != AppText.transcriptSavedToast
    }
}

private struct HeaderStatusMessage: View {
    let statusMessage: String
    let isStarting: Bool
    let isBlocked: Bool

    private var symbolName: String {
        if isStarting {
            return "clock"
        }
        if isBlocked {
            return "exclamationmark.triangle.fill"
        }
        return "checkmark.circle.fill"
    }

    private var foregroundStyle: Color {
        if isStarting {
            return AirTranslateDesign.Palette.accent
        }
        if isBlocked {
            return AirTranslateDesign.Palette.warning
        }
        return AirTranslateDesign.Palette.textSecondary
    }

    var body: some View {
        HStack(spacing: 8) {
            if isStarting {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 16, height: 16)
            } else {
                Image(systemName: symbolName)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(foregroundStyle)
                    .frame(width: 16, height: 16)
            }

            Text(statusMessage)
                .font(.caption.weight(isBlocked ? .semibold : .medium))
                .foregroundStyle(foregroundStyle)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .minimumScaleFactor(0.78)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(foregroundStyle.opacity(isBlocked ? 0.11 : 0.06), in: RoundedRectangle(cornerRadius: AirTranslateDesign.controlRadius, style: .continuous))
        .help(statusMessage)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(statusMessage)
    }
}

private struct HeaderAudioLevelStrip: View {
    let session: TranslationSessionStore
    let isPaused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var title: String {
        isPaused ? AppText.paused : AppText.listening
    }

    private var foregroundStyle: Color {
        isPaused ? AirTranslateDesign.Palette.paused : AirTranslateDesign.Palette.live
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: AirTranslateDesign.controlRadius, style: .continuous)
                .fill(foregroundStyle.opacity(isPaused ? 0.14 : 0.11))

            RoundedRectangle(cornerRadius: AirTranslateDesign.controlRadius, style: .continuous)
                .strokeBorder(foregroundStyle.opacity(isPaused ? 0.34 : 0.42), lineWidth: 1)

            HStack(spacing: 8) {
                if isPaused {
                    Image(systemName: "pause.fill")
                        .font(.system(size: 11, weight: .black))
                        .foregroundStyle(foregroundStyle)
                }

                Text(title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(foregroundStyle)
                    .lineLimit(1)

                if !isPaused {
                    AudioLevelWaveform(
                        level: session.latestAudioLevel,
                        date: Date(),
                        barCount: 8,
                        width: 62,
                        height: 20,
                        barWidth: 3.2,
                        barSpacing: 2.4
                    )
                }
            }
            .padding(.horizontal, 10)
        }
        .frame(width: 154, height: 32)
        .help(title)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .animation(
            reduceMotion ? nil : .spring(response: 0.26, dampingFraction: 0.82),
            value: isPaused
        )
    }

}

struct AudioLevelWaveform: View {
    let level: Float?
    let date: Date
    var barCount = 5
    var width = 25.0
    var height = 24.0
    var barWidth = 3.8
    var barSpacing = 3.0
    var tint = AirTranslateDesign.Palette.live

    var body: some View {
        HStack(alignment: .center, spacing: barSpacing) {
            ForEach(0..<barCount, id: \.self) { index in
                Capsule(style: .continuous)
                    .fill(barFill(for: index))
                    .frame(width: barWidth, height: barHeight(for: index))
            }
        }
        .frame(width: width, height: height)
        .accessibilityHidden(true)
    }

    private var normalizedLevel: Double {
        guard let level else { return 0.18 }

        let clampedLevel = min(max(Double(level), -60), -12)
        return (clampedLevel + 60) / 48
    }

    private func barHeight(for index: Int) -> Double {
        let centerDistance = abs(Double(index) - Double(barCount - 1) / 2)
        let centerBoost = max(0.54, 1 - (centerDistance * 0.055))
        let phase = date.timeIntervalSinceReferenceDate * 7.5 + Double(index) * 0.82
        let movement = (sin(phase) + 1) / 2
        let dynamicLevel = 0.18 + normalizedLevel * 0.82
        let computedHeight = 5 + (dynamicLevel * centerBoost * (0.66 + movement * 0.42) * (height - 5))

        return min(max(computedHeight, 5), height)
    }

    private func barFill(for index: Int) -> Color {
        let quietOpacity = 0.44 + Double(index) * 0.035
        return tint.opacity(min(0.92, 0.46 + normalizedLevel * quietOpacity))
    }
}
