import AppKit
import SwiftUI

/// 상태바 패널과 앱 메뉴가 같은 창 동작과 글자 크기 경계를 사용한다.
@MainActor
enum CaptionControlActions {
    static func toggleVisibility(session: TranslationSessionStore, using openWindow: OpenWindowAction) {
        if FloatingCaptionWindowController.isOpen {
            FloatingCaptionWindowController.close()
        } else {
            openWindow(id: AirTranslateWindowID.floatingCaptionModeChoice)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    static func showCaptionsOnly(session: TranslationSessionStore, using openWindow: OpenWindowAction) {
        FloatingCaptionWindowController.openExclusive(session: session) {
            showMainWindow(using: openWindow)
        }
    }

    static func showMainWindow(using openWindow: OpenWindowAction) {
        FloatingCaptionWindowController.cancelPendingExclusiveStart()
        if !MainCaptionWindowObserver.showMainWindows() {
            openWindow(id: AirTranslateWindowID.main)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    static func showSettings(using openSettings: OpenSettingsAction) {
        NSApp.activate(ignoringOtherApps: true)
        openSettings()
    }

    static func adjustTextSize(session: TranslationSessionStore, by change: CGFloat) {
        session.floatingCaptionCustomPointSize = FloatingCaptionAppearance.clampedCustomPointSize(
            session.floatingCaptionPrimaryPointSize + change
        )
    }
}

struct CaptionDisplayModePicker: View {
    @Bindable var session: TranslationSessionStore

    var body: some View {
        Picker(AppText.captionDisplayMode, selection: $session.floatingCaptionDisplayMode) {
            ForEach(session.availableFloatingCaptionDisplayModes) { mode in
                Text(mode == .originalAndTranslation ? AppText.both : mode.title)
                    .tag(mode)
                    .accessibilityLabel(mode.title)
            }
        }
        .accessibilityLabel(AppText.captionDisplayMode)
    }
}

struct CaptionTextSizeButtons: View {
    let session: TranslationSessionStore
    var includesKeyboardShortcuts = false

    var body: some View {
        Button(AppText.makeCaptionTextSmaller, systemImage: "textformat.size.smaller") {
            CaptionControlActions.adjustTextSize(session: session, by: -2)
        }
        .disabled(session.floatingCaptionPrimaryPointSize <= FloatingCaptionAppearance.customPointSizeRange.lowerBound)
        .accessibilityValue("\(Int(session.floatingCaptionPrimaryPointSize)) pt")
        .keyboardShortcut(includesKeyboardShortcuts ? KeyboardShortcut("-", modifiers: [.command, .option]) : nil)

        Button(AppText.makeCaptionTextLarger, systemImage: "textformat.size.larger") {
            CaptionControlActions.adjustTextSize(session: session, by: 2)
        }
        .disabled(session.floatingCaptionPrimaryPointSize >= FloatingCaptionAppearance.customPointSizeRange.upperBound)
        .accessibilityValue("\(Int(session.floatingCaptionPrimaryPointSize)) pt")
        .keyboardShortcut(includesKeyboardShortcuts ? KeyboardShortcut("+", modifiers: [.command, .option]) : nil)
    }
}

@MainActor
struct CaptionCommands: Commands {
    @Bindable var session: TranslationSessionStore
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some Commands {
        CommandMenu(AppText.menuBarTitle) {
            Button(session.isFloatingCaptionPresentationActive ? AppText.hideFloatingCaptions : AppText.showFloatingCaptions) {
                CaptionControlActions.toggleVisibility(session: session, using: openWindow)
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])

            Button(AppText.showCaptionsOnly) {
                CaptionControlActions.showCaptionsOnly(session: session, using: openWindow)
            }
            .disabled(session.captureControlState.phase == .finishing)
            .help(AppText.showCaptionsOnlyDetail)
            Button(AppText.openMainWindow) {
                CaptionControlActions.showMainWindow(using: openWindow)
            }

            Divider()
            CaptionDisplayModePicker(session: session)
                .pickerStyle(.inline)

            Divider()
            Text("\(AppText.size): \(Int(session.floatingCaptionPrimaryPointSize)) pt")
            CaptionTextSizeButtons(session: session, includesKeyboardShortcuts: true)
            Picker(AppText.lines, selection: $session.floatingCaptionLineCount) {
                ForEach(FloatingCaptionLineCount.allCases) { count in
                    Text(count.title).tag(count)
                }
            }
            .pickerStyle(.menu)

            Divider()
            Button(AppText.openSettings) {
                CaptionControlActions.showSettings(using: openSettings)
            }
        }
    }
}
