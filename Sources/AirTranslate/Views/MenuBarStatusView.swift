import SwiftUI

struct MenuBarStatusView: View {
    @Bindable var session: TranslationSessionStore
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @State private var isFloatingCaptionVisible = FloatingCaptionWindowController.isOpen

    var body: some View {
        VStack(alignment: .leading, spacing: AirTranslateDesign.Spacing.sm) {
            header

            actionGrid

            displayModeGrid

            captionFormatControls

            appControls
        }
        .padding(AirTranslateDesign.Spacing.md)
        .frame(width: 350)
        .tint(AirTranslateDesign.Palette.accent)
        .background(.regularMaterial)
        .onAppear {
            syncFloatingCaptionVisibility()
        }
        .onReceive(NotificationCenter.default.publisher(for: FloatingCaptionWindowController.visibilityDidChangeNotification)) { _ in
            syncFloatingCaptionVisibility()
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: AirTranslateDesign.Spacing.sm) {
            Image(systemName: statusSymbolName)
                .font(.system(size: AirTranslateDesign.iconLarge, weight: .semibold))
                .foregroundStyle(statusColor)
                .frame(width: 40, height: 40)
                .background(
                    statusBackgroundColor,
                    in: RoundedRectangle(cornerRadius: AirTranslateDesign.Radius.control, style: .continuous)
                )

            VStack(alignment: .leading, spacing: AirTranslateDesign.Spacing.xxs) {
                Text(AppText.floatingCaptions)
                    .font(AirTranslateDesign.Typography.stageTitle)
                    .foregroundStyle(AirTranslateDesign.Palette.textPrimary)

                HStack(spacing: AirTranslateDesign.Spacing.xs) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 7, height: 7)
                        .accessibilityHidden(true)

                    Text(session.statusMessage)
                        .font(AirTranslateDesign.Typography.meta)
                        .foregroundStyle(AirTranslateDesign.Palette.textSecondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 0)
        }
    }

    private var actionGrid: some View {
        VStack(spacing: AirTranslateDesign.Spacing.xxs) {
            Button {
                toggleCapture()
            } label: {
                IconPanelButtonLabel(
                    systemImage: capturePhase.actionSystemImage,
                    title: capturePhase.actionTitle,
                    subtitle: capturePhase.actionSubtitle(statusMessage: session.statusMessage),
                    tint: captureActionColor,
                    isSelected: capturePhase == .idle
                )
            }
            .buttonStyle(AirTranslatePressButtonStyle())
            .help(capturePhase.actionTitle)
            .accessibilityLabel(capturePhase.actionTitle)
            .accessibilityValue(capturePhase.actionSubtitle(statusMessage: session.statusMessage))

            Button {
                toggleFloatingCaptions()
            } label: {
                IconPanelButtonLabel(
                    systemImage: isFloatingCaptionVisible ? "captions.bubble.fill" : "captions.bubble",
                    title: isFloatingCaptionVisible
                        ? AppText.hideFloatingCaptions
                        : AppText.showFloatingCaptions,
                    subtitle: isFloatingCaptionVisible ? AppText.floatingCaptionPowerOn : AppText.floatingCaptionPowerOff,
                    tint: isFloatingCaptionVisible ? AirTranslateDesign.Palette.live : AirTranslateDesign.Palette.textSecondary,
                    isSelected: isFloatingCaptionVisible
                )
            }
            .buttonStyle(AirTranslatePressButtonStyle())
            .help(isFloatingCaptionVisible ? AppText.hideFloatingCaptions : AppText.showFloatingCaptions)
            .accessibilityLabel(isFloatingCaptionVisible ? AppText.hideFloatingCaptions : AppText.showFloatingCaptions)
            .accessibilityValue(isFloatingCaptionVisible ? AppText.floatingCaptionPowerOn : AppText.floatingCaptionPowerOff)

            Button {
                openWindow(id: AirTranslateWindowID.main)
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                IconPanelButtonLabel(
                    systemImage: "macwindow",
                    title: AppText.openAirTranslate,
                    subtitle: AppText.mainWindow,
                    tint: AirTranslateDesign.Palette.textSecondary
                )
            }
            .buttonStyle(AirTranslatePressButtonStyle())
            .help(AppText.openMainWindow)

            if session.isRunning {
                Button {
                    session.isPaused ? session.resume() : session.pause()
                } label: {
                    IconPanelButtonLabel(
                        systemImage: session.isPaused ? "play.fill" : "pause.fill",
                        title: session.isPaused ? AppText.resume : AppText.pause,
                        subtitle: session.isPaused ? AppText.paused : AppText.menuBarRunningTitle,
                        tint: session.isPaused ? AirTranslateDesign.Palette.accent : AirTranslateDesign.Palette.paused,
                        isSelected: session.isPaused
                    )
                }
                .buttonStyle(AirTranslatePressButtonStyle())
            }
        }
        .padding(AirTranslateDesign.Spacing.xs)
        .airRaisedSurface()
    }

    private var displayModeGrid: some View {
        VStack(alignment: .leading, spacing: AirTranslateDesign.Spacing.xs) {
            ControlSectionHeader(
                systemImage: "rectangle.split.2x1",
                title: AppText.floatingDisplay
            )

            HStack(spacing: 8) {
                ForEach(session.availableFloatingCaptionDisplayModes) { mode in
                    Button {
                        session.floatingCaptionDisplayMode = mode
                    } label: {
                        IconChoiceLabel(
                            systemImage: mode.systemImage,
                            title: compactDisplayTitle(for: mode),
                            isSelected: session.floatingCaptionDisplayMode == mode
                        )
                    }
                    .buttonStyle(AirTranslatePressButtonStyle())
                    .help(mode.title)
                    .accessibilityLabel(mode.title)
                    .accessibilityValue(session.floatingCaptionDisplayMode == mode ? AppText.selected : "")
                }
            }
        }
        .padding(AirTranslateDesign.Spacing.sm)
        .airRaisedSurface()
    }

    private var captionFormatControls: some View {
        VStack(alignment: .leading, spacing: AirTranslateDesign.Spacing.xs) {
            ControlSectionHeader(
                systemImage: "slider.horizontal.3",
                title: AppText.captionStyle
            )

            HStack(spacing: 8) {
                Menu {
                    ForEach(FloatingCaptionTextSize.allCases) { size in
                        Button(size.title) {
                            session.selectFloatingCaptionTextSizePreset(size)
                        }
                    }
                } label: {
                    IconMenuLabel(
                        systemImage: "textformat.size",
                        title: AppText.size,
                        value: "\(Int(session.floatingCaptionPrimaryPointSize)) pt"
                    )
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .help(AppText.floatingTextSize)

                Menu {
                    ForEach(FloatingCaptionLineCount.allCases) { lineCount in
                        Button(lineCount.title) {
                            session.floatingCaptionLineCount = lineCount
                        }
                    }
                } label: {
                    IconMenuLabel(
                        systemImage: "line.3.horizontal",
                        title: AppText.lines,
                        value: session.floatingCaptionLineCount.title
                    )
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .help(AppText.floatingLineCount)

                Menu {
                    ForEach(FloatingCaptionStability.allCases) { stability in
                        Button(stability.title) {
                            session.floatingCaptionStability = stability
                        }
                    }
                } label: {
                    IconMenuLabel(
                        systemImage: "waveform.path.ecg",
                        title: AppText.stability,
                        value: session.floatingCaptionStability.title
                    )
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .help(AppText.captionStabilityDescription)
            }
        }
        .padding(AirTranslateDesign.Spacing.sm)
        .airRaisedSurface()
    }

    private var appControls: some View {
        HStack(spacing: 12) {
            Button {
                NSApp.activate(ignoringOtherApps: true)
                openSettings()
            } label: {
                AirChip(
                    text: AppText.settings,
                    systemImage: "gearshape",
                    tint: AirTranslateDesign.Palette.textSecondary
                )
            }
            .buttonStyle(.plain)
            .help(AppText.openSettings)

            Spacer(minLength: 0)

            Button {
                NSApp.terminate(nil)
            } label: {
                AirChip(
                    text: AppText.quit,
                    systemImage: "power",
                    tint: AirTranslateDesign.Palette.danger
                )
            }
            .buttonStyle(.plain)
            .help(AppText.quitAirTranslate)
        }
    }

    private var statusSymbolName: String {
        switch capturePhase {
        case .idle:
            "captions.bubble.fill"
        case .starting:
            "hourglass.circle.fill"
        case .running:
            "waveform.circle.fill"
        case .paused:
            "pause.circle.fill"
        }
    }

    private var statusColor: Color {
        switch capturePhase {
        case .idle:
            AirTranslateDesign.Palette.textSecondary
        case .starting, .paused:
            AirTranslateDesign.Palette.paused
        case .running:
            AirTranslateDesign.Palette.live
        }
    }

    private var statusBackgroundColor: Color {
        switch capturePhase {
        case .idle:
            AirTranslateDesign.Palette.raisedHover
        case .starting, .paused:
            AirTranslateDesign.Palette.pausedSoft
        case .running:
            AirTranslateDesign.Palette.liveSoft
        }
    }

    private var capturePhase: MenuBarCapturePhase {
        MenuBarCapturePhase(
            isRunning: session.isRunning,
            isStarting: session.isStarting,
            isPaused: session.isPaused
        )
    }

    private var captureActionColor: Color {
        switch capturePhase {
        case .idle:
            AirTranslateDesign.Palette.accent
        case .starting, .running, .paused:
            AirTranslateDesign.Palette.danger
        }
    }

    private func toggleFloatingCaptions() {
        FloatingCaptionWindowController.toggle(session: session)
        syncFloatingCaptionVisibility()
    }

    private func toggleCapture() {
        if capturePhase != .idle {
            session.stop()
        } else {
            session.start()
        }
    }

    private func syncFloatingCaptionVisibility() {
        isFloatingCaptionVisible = FloatingCaptionWindowController.isOpen
    }

    private func compactDisplayTitle(for mode: FloatingCaptionDisplayMode) -> String {
        switch mode {
        case .original:
            AppText.originalOnly
        case .originalAndTranslation:
            AppText.both
        case .translation:
            AppText.translationOnly
        }
    }
}

enum MenuBarCapturePhase: Equatable {
    case idle
    case starting
    case running
    case paused

    init(isRunning: Bool, isStarting: Bool, isPaused: Bool) {
        if isStarting {
            self = .starting
        } else if isRunning {
            self = isPaused ? .paused : .running
        } else {
            self = .idle
        }
    }

    var actionSystemImage: String {
        switch self {
        case .idle:
            "play.fill"
        case .starting:
            "xmark"
        case .running, .paused:
            "stop.fill"
        }
    }

    var actionTitle: String {
        switch self {
        case .idle:
            AppText.start
        case .starting:
            AppText.cancel
        case .running, .paused:
            AppText.stop
        }
    }

    func actionSubtitle(statusMessage: String) -> String {
        switch self {
        case .idle:
            AppText.ready
        case .starting:
            statusMessage
        case .running:
            AppText.menuBarRunningTitle
        case .paused:
            AppText.paused
        }
    }
}

private struct ControlSectionHeader: View {
    let systemImage: String
    let title: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(AirTranslateDesign.Typography.sectionLabel)
            .tracking(0.6)
            .textCase(.uppercase)
            .foregroundStyle(AirTranslateDesign.Palette.textSecondary)
    }
}

private struct IconPanelButtonLabel: View {
    let systemImage: String
    let title: String
    let subtitle: String
    let tint: Color
    var isSelected = false

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: systemImage)
                .font(.system(size: AirTranslateDesign.iconRegular, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(AirTranslateDesign.Typography.label.weight(.semibold))
                    .foregroundStyle(AirTranslateDesign.Palette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                Text(subtitle)
                    .font(AirTranslateDesign.Typography.meta.weight(.medium))
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.caption2.weight(.bold))
                .foregroundStyle(AirTranslateDesign.Palette.textTertiary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, minHeight: 38)
        .airTranslateInteractiveSurface(isSelected: isSelected, tint: tint)
        .contentShape(RoundedRectangle(cornerRadius: AirTranslateDesign.controlRadius, style: .continuous))
    }
}

private struct IconChoiceLabel: View {
    let systemImage: String
    let title: String
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: AirTranslateDesign.iconSmall, weight: .semibold))

            Text(title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .foregroundStyle(isSelected ? AirTranslateDesign.Palette.accent : AirTranslateDesign.Palette.textPrimary)
        .padding(.horizontal, 7)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, minHeight: 34)
        .airTranslateInteractiveSurface(isSelected: isSelected)
        .contentShape(RoundedRectangle(cornerRadius: AirTranslateDesign.controlRadius, style: .continuous))
    }
}

private struct IconMenuLabel: View {
    let systemImage: String
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: AirTranslateDesign.iconRegular, weight: .semibold))
                .foregroundStyle(AirTranslateDesign.Palette.accent)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(AirTranslateDesign.Typography.meta.weight(.semibold))
                    .foregroundStyle(AirTranslateDesign.Palette.textSecondary)

                Text(value)
                    .font(AirTranslateDesign.Typography.label.weight(.semibold))
                    .foregroundStyle(AirTranslateDesign.Palette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.up.chevron.down")
                .font(.caption.weight(.bold))
                .foregroundStyle(AirTranslateDesign.Palette.textSecondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, minHeight: 40)
        .airTranslateInteractiveSurface()
        .contentShape(RoundedRectangle(cornerRadius: AirTranslateDesign.controlRadius, style: .continuous))
    }
}
