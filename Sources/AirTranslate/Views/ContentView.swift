import SwiftUI

struct ContentView: View {
    @Bindable var session: TranslationSessionStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openSettings) private var openSettings
    @State private var isLibraryPresented = false
    @State private var isFloatingCaptionVisible = FloatingCaptionWindowController.isOpen

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                AirTranslateDesign.Palette.canvas
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    StageHeaderView(session: session)
                    CaptionBoardView(session: session)
                }

                VStack(spacing: AirTranslateDesign.Spacing.xs) {
                    if let failureMessage = session.captureStartFailureMessage {
                        CaptureStartFailureView(
                            message: failureMessage,
                            recoveryAction: session.captureStartRecoveryAction,
                            recover: recoverFromCaptureStartFailure,
                            dismiss: session.dismissCaptureStartFailure
                        )
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    if let toastMessage = session.toastMessage {
                        ToastMessageView(message: toastMessage)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .padding(.top, AirTranslateDesign.Spacing.sm)
                .padding(.horizontal, AirTranslateDesign.Spacing.lg)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                ConsoleBarView(session: session, isCompact: geometry.size.width < 1040)
                    .padding(.horizontal, AirTranslateDesign.Spacing.lg)
                    .padding(.top, AirTranslateDesign.Spacing.sm)
                    .padding(.bottom, AirTranslateDesign.Spacing.md)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    isLibraryPresented = true
                } label: {
                    Image(systemName: "tray.full")
                }
                .help(AppText.manageSavedTranscripts)
                .accessibilityLabel(AppText.library)

                Button {
                    toggleFloatingCaptions()
                } label: {
                    Image(systemName: isFloatingCaptionVisible ? "captions.bubble.fill" : "captions.bubble")
                }
                .help(AppText.floatingCaptions)
                .accessibilityLabel(AppText.floatingCaptions)
                .accessibilityValue(
                    isFloatingCaptionVisible
                        ? AppText.floatingCaptionPowerOn
                        : AppText.floatingCaptionPowerOff
                )
                .accessibilityAddTraits(isFloatingCaptionVisible ? .isSelected : [])

                SettingsLink {
                    Image(systemName: "gearshape")
                }
                .help(AppText.configureTranslationSettings)
                .accessibilityLabel(AppText.translationSettings)
            }
        }
        .controlSize(.regular)
        .sheet(isPresented: $isLibraryPresented) {
            TranscriptLibraryView(session: session)
        }
        .onAppear {
            syncFloatingCaptionVisibility()
        }
        .onReceive(NotificationCenter.default.publisher(for: FloatingCaptionWindowController.visibilityDidChangeNotification)) { _ in
            syncFloatingCaptionVisibility()
        }
        .animation(reduceMotion ? nil : AirTranslateDesign.Motion.state, value: session.toastSequence)
        .animation(reduceMotion ? nil : AirTranslateDesign.Motion.enter, value: session.toastMessage)
        .confirmationDialog(
            AppText.autoDetectionLanguageChangeTitle,
            isPresented: autoDetectionLanguageChangeBinding,
            titleVisibility: .visible
        ) {
            Button(AppText.startNewAutoDetectionSession) {
                session.confirmAutoDetectionLanguageChange()
            }

            Button(AppText.keepCurrentAutoDetectionLanguage, role: .cancel) {
                session.keepCurrentAutoDetectionLanguage()
            }
        } message: {
            if let languageChange = session.pendingAutoDetectionLanguageChange {
                Text(
                    AppText.autoDetectionLanguageChangeMessage(
                        current: languageChange.currentLanguage.localizedTitle,
                        detected: languageChange.detectedLanguage.localizedTitle,
                        target: languageChange.targetLanguage.localizedTitle
                    )
                )
            }
        }
    }

    private func recoverFromCaptureStartFailure(_ action: CaptureStartRecoveryAction) {
        switch action {
        case .apiKeys:
            session.requestAPIKeySettings()
            openSettings()
        case .generalSettings:
            session.requestGeneralSettings()
            openSettings()
        case .privacy(let pane):
            session.openPrivacySettings(pane)
        case .retry:
            session.start()
        }
    }

    private func toggleFloatingCaptions() {
        FloatingCaptionWindowController.toggle(session: session)
        syncFloatingCaptionVisibility()
    }

    private func syncFloatingCaptionVisibility() {
        isFloatingCaptionVisible = FloatingCaptionWindowController.isOpen
    }

    private var autoDetectionLanguageChangeBinding: Binding<Bool> {
        Binding(
            get: { session.pendingAutoDetectionLanguageChange != nil },
            set: { isPresented in
                if !isPresented {
                    session.keepCurrentAutoDetectionLanguage()
                }
            }
        )
    }
}

private struct CaptureStartFailureView: View {
    let message: String
    let recoveryAction: CaptureStartRecoveryAction?
    let recover: (CaptureStartRecoveryAction) -> Void
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: AirTranslateDesign.Spacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(AirTranslateDesign.Palette.warning)
                .accessibilityHidden(true)

            Text(message)
                .font(AirTranslateDesign.Typography.label.weight(.semibold))
                .foregroundStyle(AirTranslateDesign.Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(1)

            if let recoveryAction {
                Button(actionTitle(for: recoveryAction)) {
                    recover(recoveryAction)
                }
                .buttonStyle(.borderedProminent)
                .tint(AirTranslateDesign.Palette.accent)
                .controlSize(.small)
            }

            Button(action: dismiss) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .accessibilityLabel(AppText.dismissStartFailure)
        }
        .padding(.horizontal, AirTranslateDesign.Spacing.md)
        .padding(.vertical, AirTranslateDesign.Spacing.sm)
        .frame(maxWidth: 680)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: AirTranslateDesign.Radius.surface, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AirTranslateDesign.Radius.surface, style: .continuous)
                .strokeBorder(AirTranslateDesign.Palette.warning)
        }
        .shadow(
            color: AirTranslateDesign.Palette.shadow.opacity(AirTranslateDesign.Elevation.floatingOpacity),
            radius: AirTranslateDesign.Elevation.floatingRadius,
            y: AirTranslateDesign.Elevation.floatingY
        )
        .accessibilityElement(children: .contain)
        .onAppear {
            AccessibilityNotification.Announcement(message).post()
        }
        .onChange(of: message) { _, newValue in
            AccessibilityNotification.Announcement(newValue).post()
        }
    }

    private func actionTitle(for action: CaptureStartRecoveryAction) -> String {
        switch action {
        case .apiKeys: AppText.openAPIKeySettings
        case .generalSettings: NariCopy.chooseGAModel
        case .privacy: AppText.openPrivacySettings
        case .retry: AppText.retry
        }
    }
}

private struct ToastMessageView: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "checkmark.circle.fill")
            .font(AirTranslateDesign.Typography.label.weight(.semibold))
            .foregroundStyle(AirTranslateDesign.Palette.textPrimary)
            .padding(.horizontal, AirTranslateDesign.Spacing.sm)
            .padding(.vertical, AirTranslateDesign.Spacing.xs)
            .airConsoleSurface()
            .accessibilityAddTraits(.updatesFrequently)
    }
}
