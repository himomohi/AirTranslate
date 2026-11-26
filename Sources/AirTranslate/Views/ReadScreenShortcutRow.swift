import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Settings → General row for the global Read Screen Text shortcut.
struct ReadScreenShortcutRow: View {
    @State private var shortcut = ReadScreenShortcut.shared
    @State private var invalidAttempt = false

    var body: some View {
        SettingsControlRow(
            title: SettingsCopy.readScreenShortcut,
            detail: SettingsCopy.readScreenShortcutDetail,
            systemImage: "keyboard"
        ) {
            HStack(spacing: AirTranslateDesign.Spacing.xs) {
                ShortcutRecorderButton(
                    shortcut: shortcut.setting,
                    onRecord: { shortcut.update($0) },
                    onRejected: { invalidAttempt = true }
                )
                Button {
                    shortcut.update(nil)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.borderless)
                .disabled(shortcut.setting == nil)
                .help(SettingsCopy.clearShortcut)
                .accessibilityLabel(SettingsCopy.clearShortcut)

                Button {
                    shortcut.reset()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .buttonStyle(.borderless)
                .disabled(shortcut.setting == .readScreenDefault)
                .help(SettingsCopy.resetShortcut)
                .accessibilityLabel(SettingsCopy.resetShortcut)
            }
        }
        if shortcut.registrationFailed {
            SettingsNoticeRow(text: SettingsCopy.shortcutUnavailable, systemImage: "exclamationmark.triangle")
        } else if invalidAttempt {
            SettingsNoticeRow(text: SettingsCopy.shortcutNeedsModifier, systemImage: "exclamationmark.triangle")
        }
    }
}

/// Click to record; the next key combo (with ⌘, ⌥ or ⌃) is captured, Esc cancels.
/// The local key monitor only exists while recording.
private struct ShortcutRecorderButton: View {
    let shortcut: KeyboardShortcutSetting?
    let onRecord: (KeyboardShortcutSetting) -> Void
    let onRejected: () -> Void

    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        Button(action: { isRecording ? stopRecording() : startRecording() }) {
            Text(isRecording ? SettingsCopy.typeShortcut : shortcut?.displayString ?? SettingsCopy.shortcutOff)
                .monospaced()
                .frame(minWidth: 96)
        }
        .buttonStyle(.bordered)
        .tint(isRecording ? AirTranslateDesign.Palette.accent : nil)
        .accessibilityLabel(SettingsCopy.readScreenShortcut)
        .onDisappear(perform: stopRecording)
    }

    private func startRecording() {
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let keyCode = UInt32(event.keyCode)
            let flags = event.modifierFlags
            MainActor.assumeIsolated { handle(keyCode: keyCode, flags: flags) }
            return nil // swallow every key while recording
        }
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        isRecording = false
    }

    private func handle(keyCode: UInt32, flags: NSEvent.ModifierFlags) {
        if Int(keyCode) == kVK_Escape {
            stopRecording()
            return
        }
        let modifiers = KeyboardShortcutSetting.carbonModifiers(from: flags)
        guard KeyboardShortcutSetting.isValid(modifiers: modifiers) else {
            onRejected()
            return
        }
        stopRecording()
        onRecord(KeyboardShortcutSetting(keyCode: keyCode, modifiers: modifiers))
    }
}
