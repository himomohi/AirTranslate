import AppKit
import SwiftUI

@main
struct AirTranslateApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var session = TranslationSessionStore()
    @State private var menuBarPanelController = MenuBarPanelController()

    init() {
        appDelegate.session = session
    }

    var body: some Scene {
        WindowGroup("AirTranslate", id: AirTranslateWindowID.main) {
            ContentView(session: session)
                .frame(
                    minWidth: AirTranslateDesign.mainWindowMinimumWidth,
                    minHeight: AirTranslateDesign.mainWindowMinimumHeight
                )
                .tint(AirTranslateDesign.Palette.accent)
                .background(MenuBarPanelInstaller(session: session, controller: menuBarPanelController))
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
            CaptureCommands(session: session)
            CaptionCommands(session: session)
        }

        Window(AppText.floatingCaptionModeChoiceTitle, id: AirTranslateWindowID.floatingCaptionModeChoice) {
            FloatingCaptionModeChoiceView(session: session)
                .windowMinimizeBehavior(.disabled)
        }
        .windowResizability(.contentSize)
        .restorationBehavior(.disabled)
        .defaultLaunchBehavior(.suppressed)

        Settings {
            SettingsView(session: session)
                .tint(AirTranslateDesign.Palette.accent)
        }
    }
}

@MainActor
private struct CaptureCommands: Commands {
    @Bindable var session: TranslationSessionStore

    var body: some Commands {
        CommandMenu(AppText.capture) {
            Button(session.captureControlState.phase.actionTitle) {
                if session.isRunning || session.isStarting {
                    session.stop()
                } else {
                    session.start()
                }
            }
            .keyboardShortcut(.return, modifiers: [.command])
            .disabled(!session.captureControlState.canToggleCapture)

            Button(session.isPaused ? AppText.resume : AppText.pause) {
                session.isPaused ? session.resume() : session.pause()
            }
            .keyboardShortcut(.space, modifiers: [.command, .shift])
            .disabled(!session.captureControlState.canTogglePause)

            Divider()

            Button(session.isReadingScreenText || session.isPickingScreenTextRegion
                ? AppText.stopReadingScreenText : AppText.readScreenText) {
                session.toggleScreenTextReading()
            }
            .keyboardShortcut("o", modifiers: [.command, .shift])
            .disabled(!session.isReadingScreenText && (session.isRunning || session.isStarting))

            Button(AppText.changeScreenTextRegion) {
                session.changeScreenTextRegion()
            }
            .disabled(!session.canChangeScreenTextRegion)

            Toggle(AppText.screenTextUsesGeminiLive, isOn: $session.screenTextUsesGeminiLive)
                .disabled(session.isReadingScreenText || !session.hasGeminiAPIKey)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var session: TranslationSessionStore?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let appIcon = NSImage(named: "AppIcon") {
            NSApp.applicationIconImage = appIcon
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        ReadScreenShortcut.shared.start { [weak self] in
            self?.session?.toggleScreenTextReading()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        session?.prepareForTermination()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        session?.resumeCapturePermissionSetupIfApproved()
    }
}
