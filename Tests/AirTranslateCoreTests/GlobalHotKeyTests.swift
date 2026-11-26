import Carbon.HIToolbox
import Foundation
import Testing
@testable import AirTranslate

struct GlobalHotKeyTests {
    @Test func defaultIsOptionCommandO() {
        let shortcut = KeyboardShortcutSetting.readScreenDefault
        #expect(shortcut.modifiers == UInt32(cmdKey | optionKey))
        #expect(shortcut.displayString.hasPrefix("⌥⌘"))
        #expect(shortcut.isValid)
    }

    @Test func displayStringOrdersModifiersAndNamesSpecialKeys() {
        let all = UInt32(cmdKey | optionKey | controlKey | shiftKey)
        #expect(KeyboardShortcutSetting(keyCode: UInt32(kVK_Space), modifiers: all).displayString == "⌃⌥⇧⌘Space")
        #expect(KeyboardShortcutSetting(keyCode: UInt32(kVK_F5), modifiers: UInt32(controlKey)).displayString == "⌃F5")
        #expect(KeyboardShortcutSetting(keyCode: UInt32(kVK_LeftArrow), modifiers: UInt32(cmdKey)).displayString == "⌘←")
    }

    @Test func codableRoundTrip() throws {
        let shortcut = KeyboardShortcutSetting(keyCode: 12, modifiers: UInt32(controlKey | shiftKey))
        let decoded = try JSONDecoder().decode(KeyboardShortcutSetting.self, from: JSONEncoder().encode(shortcut))
        #expect(decoded == shortcut)
    }

    @Test func modifierValidationRequiresCommandOptionOrControl() {
        #expect(!KeyboardShortcutSetting.isValid(modifiers: 0))
        #expect(!KeyboardShortcutSetting.isValid(modifiers: UInt32(shiftKey)))
        #expect(KeyboardShortcutSetting.isValid(modifiers: UInt32(cmdKey)))
        #expect(KeyboardShortcutSetting.isValid(modifiers: UInt32(optionKey | shiftKey)))
        #expect(KeyboardShortcutSetting.isValid(modifiers: UInt32(controlKey)))
    }

    @Test func carbonModifiersFromEventFlags() {
        #expect(KeyboardShortcutSetting.carbonModifiers(from: [.command, .option]) == UInt32(cmdKey | optionKey))
        #expect(KeyboardShortcutSetting.carbonModifiers(from: [.shift, .capsLock]) == UInt32(shiftKey))
    }
}
