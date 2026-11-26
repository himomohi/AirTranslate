import AppKit
import Carbon.HIToolbox
import Observation

/// A key combination stored as a virtual key code plus Carbon modifier flags
/// (`cmdKey`, `optionKey`, `controlKey`, `shiftKey`).
struct KeyboardShortcutSetting: Codable, Equatable, Sendable {
    static let readScreenDefault = KeyboardShortcutSetting(
        keyCode: UInt32(kVK_ANSI_O),
        modifiers: UInt32(cmdKey | optionKey)
    )

    var keyCode: UInt32
    var modifiers: UInt32

    /// Global shortcuts must include ⌘, ⌥ or ⌃ so they never swallow plain typing.
    static func isValid(modifiers: UInt32) -> Bool {
        modifiers & UInt32(cmdKey | optionKey | controlKey) != 0
    }

    var isValid: Bool { Self.isValid(modifiers: modifiers) }

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var result: UInt32 = 0
        if flags.contains(.control) { result |= UInt32(controlKey) }
        if flags.contains(.option) { result |= UInt32(optionKey) }
        if flags.contains(.shift) { result |= UInt32(shiftKey) }
        if flags.contains(.command) { result |= UInt32(cmdKey) }
        return result
    }

    /// For example "⌥⌘O", in the standard ⌃⌥⇧⌘ order.
    var displayString: String {
        var text = ""
        if modifiers & UInt32(controlKey) != 0 { text += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { text += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { text += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { text += "⌘" }
        return text + Self.keyName(for: keyCode)
    }

    private static let specialKeyNames: [Int: String] = [
        kVK_Return: "↩", kVK_Tab: "⇥", kVK_Space: "Space", kVK_Delete: "⌫",
        kVK_ForwardDelete: "⌦", kVK_Escape: "⎋", kVK_Home: "↖", kVK_End: "↘",
        kVK_PageUp: "⇞", kVK_PageDown: "⇟", kVK_LeftArrow: "←", kVK_RightArrow: "→",
        kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5",
        kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10",
        kVK_F11: "F11", kVK_F12: "F12", kVK_F13: "F13", kVK_F14: "F14",
        kVK_F15: "F15", kVK_F16: "F16", kVK_F17: "F17", kVK_F18: "F18",
        kVK_F19: "F19", kVK_F20: "F20"
    ]

    /// Key name for the current ASCII-capable keyboard layout (so ⌥⌘O stays "O" on Dvorak too).
    static func keyName(for keyCode: UInt32) -> String {
        if let name = specialKeyNames[Int(keyCode)] { return name }
        guard
            let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
            let property = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return "Key \(keyCode)" }
        let layout = unsafeBitCast(property, to: CFData.self)
        let keyboardType = UInt32(LMGetKbdType())
        var deadKeys: UInt32 = 0
        var length = 0
        var chars = [UniChar](repeating: 0, count: 4)
        let status = unsafe CFDataGetBytePtr(layout).withMemoryRebound(to: UCKeyboardLayout.self, capacity: 1) {
            UCKeyTranslate(
                $0, UInt16(keyCode), UInt16(kUCKeyActionDisplay), 0, keyboardType,
                OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeys, chars.count, &length, &chars
            )
        }
        guard status == noErr, length > 0 else { return "Key \(keyCode)" }
        return String(utf16CodeUnits: chars, count: length).uppercased()
    }
}

/// Registers one system-wide hot key with Carbon `RegisterEventHotKey`, which needs no
/// Accessibility or Input Monitoring permission. The handler runs on the main actor.
@MainActor
final class GlobalHotKey {
    private static let signature: OSType = 0x4152_5453 // "ARTS"

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let handler: @MainActor () -> Void

    init(handler: @escaping @MainActor () -> Void) {
        self.handler = handler
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else { return OSStatus(eventNotHandledErr) }
                let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
                // Application-target events are delivered on the main thread.
                MainActor.assumeIsolated { hotKey.handler() }
                return noErr
            },
            1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handlerRef
        )
    }

    /// Replaces any current registration. Pass nil to disable. Returns false when the OS refuses
    /// the combo (for example another app already owns it); nothing is registered then.
    @discardableResult
    func register(_ shortcut: KeyboardShortcutSetting?) -> Bool {
        unregister()
        guard let shortcut else { return true }
        let id = EventHotKeyID(signature: Self.signature, id: 1)
        let status = RegisterEventHotKey(
            shortcut.keyCode, shortcut.modifiers, id,
            GetApplicationEventTarget(), 0, &hotKeyRef
        )
        if status != noErr { hotKeyRef = nil }
        return status == noErr
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
    }
}

/// The user-configurable Read Screen Text shortcut: persists it and keeps the hot key registered.
@MainActor
@Observable
final class ReadScreenShortcut {
    static let shared = ReadScreenShortcut()
    private static let defaultsKey = "AirTranslate.readScreenShortcut"

    private(set) var setting: KeyboardShortcutSetting?
    private(set) var registrationFailed = false

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var hotKey: GlobalHotKey?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Missing key means the default; empty data means the user cleared (disabled) it.
        if let data = defaults.data(forKey: Self.defaultsKey) {
            setting = try? JSONDecoder().decode(KeyboardShortcutSetting.self, from: data)
        } else {
            setting = .readScreenDefault
        }
    }

    func start(handler: @escaping @MainActor () -> Void) {
        hotKey = GlobalHotKey(handler: handler)
        registrationFailed = hotKey?.register(setting) == false
    }

    /// Applies a new shortcut (nil disables it). On a refused combo the previous one stays active.
    func update(_ newSetting: KeyboardShortcutSetting?) {
        if let newSetting, !newSetting.isValid { return }
        guard let hotKey else { return }
        if hotKey.register(newSetting) {
            registrationFailed = false
            setting = newSetting
            defaults.set(newSetting.flatMap { try? JSONEncoder().encode($0) } ?? Data(), forKey: Self.defaultsKey)
        } else {
            registrationFailed = true
            hotKey.register(setting)
        }
    }

    func reset() { update(.readScreenDefault) }
}
