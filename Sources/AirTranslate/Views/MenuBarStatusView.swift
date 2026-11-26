import SwiftUI

struct MenuBarStatusView: View {
    @Bindable var session: TranslationSessionStore
    let openWindow: OpenWindowAction
    @Environment(\.openSettings) private var openSettings

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
    }

    private var header: some View {
        HStack(alignment: .center, spacing: AirTranslateDesign.Spacing.sm) {
            Image(systemName: statusSymbolName)
                .font(.system(size: AirTranslateDesign.iconLarge, weight: .semibold))
                .foregroundStyle(statusColor)
                .frame(width: 38, height: 38)
                .background(
                    statusBackgroundColor,
                    in: RoundedRectangle(cornerRadius: AirTranslateDesign.Radius.control, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 7, height: 7)
                        .accessibilityHidden(true)

                    Text(session.languageSummary)
                        .font(AirTranslateDesign.Typography.label.weight(.semibold))
                        .foregroundStyle(AirTranslateDesign.Palette.textPrimary)
                        .lineLimit(1)
                }

                Text(session.statusMessage)
                    .font(AirTranslateDesign.Typography.meta)
                    .foregroundStyle(AirTranslateDesign.Palette.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            AirChip(
                text: session.processingEngineTitle,
                tint: AirTranslateDesign.Palette.accent
            )
        }
    }

    private var actionGrid: some View {
        VStack(spacing: AirTranslateDesign.Spacing.xs) {
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: AirTranslateDesign.Spacing.xs),
                    GridItem(.flexible(), spacing: AirTranslateDesign.Spacing.xs)
                ],
                spacing: AirTranslateDesign.Spacing.xs
            ) {
                Button {
                    toggleCapture()
                } label: {
                    ControlTileLabel(
                        systemImage: capturePhase.actionSystemImage,
                        title: capturePhase.actionTitle,
                        subtitle: capturePhase.actionSubtitle(statusMessage: session.statusMessage),
                        tint: captureActionColor,
                        isSelected: capturePhase == .idle || capturePhase == .running
                    )
                }
                .buttonStyle(AirTranslatePressButtonStyle())
                .disabled(!session.captureControlState.canToggleCapture)
                .help(capturePhase.actionTitle)
                .accessibilityLabel(capturePhase.actionTitle)
                .accessibilityValue(capturePhase.actionSubtitle(statusMessage: session.statusMessage))

                Button {
                    CaptionControlActions.toggleVisibility(session: session, using: openWindow)
                } label: {
                    ControlTileLabel(
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
                    CaptionControlActions.showCaptionsOnly(session: session, using: openWindow)
                } label: {
                    ControlTileLabel(
                        systemImage: "pip",
                        title: AppText.showCaptionsOnly,
                        subtitle: AppText.showCaptionsOnlyDetail,
                        tint: AirTranslateDesign.Palette.accent
                    )
                }
                .buttonStyle(AirTranslatePressButtonStyle())
                .accessibilityLabel(AppText.showCaptionsOnly)
                .accessibilityHint(AppText.showCaptionsOnlyDetail)
                .disabled(session.captureControlState.phase == .finishing)

                Button {
                    guard canSwitchAudioInput else { return }
                    session.audioInputSource = session.audioInputSource == .systemAudio ? .microphone : .systemAudio
                } label: {
                    ControlTileLabel(
                        systemImage: session.audioInputSource == .microphone ? "mic.fill" : "speaker.wave.2.fill",
                        title: AppText.audioInputSource,
                        subtitle: session.audioInputSource.title,
                        tint: canSwitchAudioInput ? AirTranslateDesign.Palette.accent : AirTranslateDesign.Palette.textTertiary
                    )
                }
                .buttonStyle(AirTranslatePressButtonStyle())
                .disabled(!canSwitchAudioInput)
                .help(canSwitchAudioInput ? AppText.audioInputSource : AppText.lockedDuringSession)
                .accessibilityLabel(AppText.audioInputSource)
                .accessibilityValue(session.audioInputSource.title)
            }

            readScreenButton

            if session.isRunning {
                Button {
                    session.isPaused ? session.resume() : session.pause()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: session.isPaused ? "play.fill" : "pause.fill")
                            .font(.system(size: 13, weight: .semibold))
                        Text(session.isPaused ? AppText.resume : AppText.pause)
                            .font(AirTranslateDesign.Typography.label.weight(.semibold))
                    }
                    .foregroundStyle(session.isPaused ? AirTranslateDesign.Palette.accent : AirTranslateDesign.Palette.paused)
                    .frame(maxWidth: .infinity, minHeight: 34)
                    .airTranslateInteractiveSurface(
                        isSelected: session.isPaused,
                        tint: session.isPaused ? AirTranslateDesign.Palette.accent : AirTranslateDesign.Palette.paused
                    )
                }
                .buttonStyle(AirTranslatePressButtonStyle())
                .disabled(!session.captureControlState.canTogglePause)
            }
        }
    }

    private var readScreenButton: some View {
        let isActive = session.isReadingScreenText || session.isPickingScreenTextRegion
        let title = isActive ? AppText.stopReadingScreenText : AppText.readScreenText
        return Button {
            session.toggleScreenTextReading()
        } label: {
            ControlTileLabel(
                systemImage: isActive ? "stop.fill" : "text.viewfinder",
                title: title,
                subtitle: isActive ? AppText.readingScreenText : AppText.readScreenTextHelp,
                tint: isActive ? AirTranslateDesign.Palette.danger : AirTranslateDesign.Palette.accent,
                isSelected: isActive
            )
        }
        .buttonStyle(AirTranslatePressButtonStyle())
        .disabled(!isActive && (session.isRunning || session.isStarting))
        .help(isActive ? title : AppText.readScreenTextHelp)
        .accessibilityLabel(title)
        .overlay(alignment: .bottomTrailing) {
            Button {
                session.changeScreenTextRegion()
            } label: {
                Image(systemName: "rectangle.dashed")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .padding(6)
            .disabled(!session.canChangeScreenTextRegion)
            .help(AppText.changeScreenTextRegion)
            .accessibilityLabel(AppText.changeScreenTextRegion)
        }
        .contextMenu {
            Button(AppText.changeScreenTextRegion) { session.changeScreenTextRegion() }
                .disabled(!session.canChangeScreenTextRegion)
        }
    }

    private var canSwitchAudioInput: Bool {
        !session.isRunning && !session.isStarting
    }

    private var displayModeGrid: some View {
        VStack(alignment: .leading, spacing: AirTranslateDesign.Spacing.xs) {
            ControlSectionHeader(
                systemImage: "rectangle.split.2x1",
                title: AppText.captionDisplayMode
            )

            CaptionDisplayModePicker(session: session)
                .pickerStyle(.segmented)
                .labelsHidden()
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
                CaptionTextSizeButtons(session: session)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

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
        HStack(spacing: 8) {
            Button {
                CaptionControlActions.showMainWindow(using: openWindow)
            } label: {
                AirChip(
                    text: AppText.mainWindow,
                    systemImage: "macwindow",
                    tint: AirTranslateDesign.Palette.textPrimary
                )
            }
            .buttonStyle(.plain)
            .help(AppText.openMainWindow)

            Button {
                CaptionControlActions.showSettings(using: openSettings)
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
        case .starting, .finishing:
            "hourglass.circle.fill"
        case .reconnecting:
            "arrow.triangle.2.circlepath"
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
        case .starting, .paused, .finishing, .reconnecting:
            AirTranslateDesign.Palette.paused
        case .running:
            AirTranslateDesign.Palette.live
        }
    }

    private var statusBackgroundColor: Color {
        switch capturePhase {
        case .idle:
            AirTranslateDesign.Palette.raisedHover
        case .starting, .paused, .finishing, .reconnecting:
            AirTranslateDesign.Palette.pausedSoft
        case .running:
            AirTranslateDesign.Palette.liveSoft
        }
    }

    private var capturePhase: MenuBarCapturePhase {
        session.captureControlState.phase
    }

    private var captureActionColor: Color {
        switch capturePhase {
        case .idle:
            AirTranslateDesign.Palette.accent
        case .starting, .running, .paused, .finishing, .reconnecting:
            AirTranslateDesign.Palette.danger
        }
    }

    private var isFloatingCaptionVisible: Bool {
        session.isFloatingCaptionPresentationActive
    }

    private func toggleCapture() {
        if capturePhase != .idle {
            session.stop()
        } else {
            session.start()
        }
    }
}

enum MenuBarCapturePhase: Equatable {
    case idle
    case starting
    case running
    case paused
    case finishing
    case reconnecting

    init(
        isRunning: Bool,
        isStarting: Bool,
        isPaused: Bool,
        isFinishing: Bool = false,
        isReconnecting: Bool = false
    ) {
        if isStarting {
            self = .starting
        } else if isRunning {
            if isFinishing {
                self = .finishing
            } else if isReconnecting {
                self = .reconnecting
            } else {
                self = isPaused ? .paused : .running
            }
        } else {
            self = .idle
        }
    }

    var actionSystemImage: String {
        switch self {
        case .idle:
            "play.fill"
        case .starting, .reconnecting:
            "xmark"
        case .running, .paused:
            "stop.fill"
        case .finishing:
            "hourglass"
        }
    }

    var actionTitle: String {
        switch self {
        case .idle:
            AppText.start
        case .starting, .reconnecting:
            AppText.cancel
        case .running, .paused:
            AppText.stop
        case .finishing:
            AppText.finishingCapture
        }
    }

    func actionSubtitle(statusMessage: String) -> String {
        switch self {
        case .idle:
            AppText.ready
        case .starting, .finishing, .reconnecting:
            statusMessage
        case .running:
            AppText.menuBarRunningTitle
        case .paused:
            AppText.paused
        }
    }

    var showsProgress: Bool {
        self == .starting || self == .finishing || self == .reconnecting
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

private struct ControlTileLabel: View {
    let systemImage: String
    let title: String
    let subtitle: String
    let tint: Color
    var isSelected = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: systemImage)
                    .font(.system(size: AirTranslateDesign.iconRegular, weight: .semibold))
                    .foregroundStyle(tint)
                Spacer(minLength: 0)
                Circle()
                    .fill(isSelected ? tint : AirTranslateDesign.Palette.hairlineStrong)
                    .frame(width: 6, height: 6)
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(AirTranslateDesign.Typography.label.weight(.semibold))
                    .foregroundStyle(AirTranslateDesign.Palette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text(subtitle)
                    .font(AirTranslateDesign.Typography.meta)
                    .foregroundStyle(isSelected ? tint : AirTranslateDesign.Palette.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, minHeight: 68, alignment: .topLeading)
        .background(
            isSelected ? tint.opacity(0.14) : AirTranslateDesign.Palette.raised,
            in: RoundedRectangle(cornerRadius: AirTranslateDesign.Radius.surface, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: AirTranslateDesign.Radius.surface, style: .continuous)
                .strokeBorder(isSelected ? tint.opacity(0.6) : AirTranslateDesign.Palette.hairline)
        }
        .contentShape(RoundedRectangle(cornerRadius: AirTranslateDesign.Radius.surface, style: .continuous))
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
