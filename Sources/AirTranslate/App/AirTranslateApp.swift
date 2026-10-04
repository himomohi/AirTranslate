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
    }

    func applicationWillTerminate(_ notification: Notification) {
        session?.prepareForTermination()
    }
}
