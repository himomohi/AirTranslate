import AppKit
import Foundation
import Testing
@testable import AirTranslate

@Suite @MainActor
struct FloatingCaptionStyleTests {
    private func withSession(_ body: (TranslationSessionStore, UserDefaults) throws -> Void) rethrows {
        let name = "FloatingCaptionStyleTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        try body(TranslationSessionStore(modelAvailabilityProvider: { _, _ in [:] }, settingsDefaults: defaults), defaults)
    }

    @Test func legacyCustomAppearanceSurvivesStyleMigration() {
        withSession { _, defaults in
            defaults.removeObject(forKey: "floatingCaptionStyle")
            defaults.set(39.0, forKey: "floatingCaptionCustomPointSize")
            defaults.set("#FFCC00", forKey: "floatingCaptionTextColorHex")
            defaults.set(0.0, forKey: "floatingCaptionBackgroundOpacity")
            let restored = TranslationSessionStore(modelAvailabilityProvider: { _, _ in [:] }, settingsDefaults: defaults)
            #expect(restored.floatingCaptionStyle == .standard)
            #expect(restored.floatingCaptionPrimaryPointSize == 39)
            #expect(restored.floatingCaptionTextColorHex == "#FFCC00")
            #expect(restored.floatingCaptionBackgroundOpacity == 0)
            #expect(restored.selectedFloatingCaptionPreset == nil)
        }
    }

    @Test func unknownStyleFieldsFallBackIndividually() throws {
        let data = Data(#"{"fontFamily":"future-font","fontWeight":"bold","lineSpacing":"relaxed","textEffect":"future-effect","translationFirst":true}"#.utf8)
        let style = try JSONDecoder().decode(FloatingCaptionStyle.self, from: data)
        #expect(style.fontFamily == .system)
        #expect(style.fontWeight == .bold)
        #expect(style.lineSpacing == .relaxed)
        #expect(style.textEffect == .shadow)
        #expect(style.backgroundShape == .soft)
        #expect(style.translationFirst)
    }

    @Test func presetDoesNotChangeSessionOrReadingPolicy() {
        withSession { session, _ in
            session.floatingCaptionDisplayMode = .translation
            session.floatingCaptionStability = .steady
            session.keepsFloatingCaptionAboveOtherWindows = false
            session.floatingCaptionBackgroundColorHex = "#112233"
            session.floatingCaptionBackgroundOpacity = 0.42
            session.floatingCaptionStyle.backgroundShape = .rounded
            let model = session.selectedModel
            let source = session.sourceLanguage
            let target = session.targetLanguage
            for preset in FloatingCaptionPreset.allCases {
                session.applyFloatingCaptionPreset(preset)
                #expect(session.selectedFloatingCaptionPreset == preset)
                #expect(session.floatingCaptionDisplayMode == .translation)
                #expect(session.floatingCaptionStability == .steady)
                #expect(!session.keepsFloatingCaptionAboveOtherWindows)
                #expect(session.floatingCaptionBackgroundColorHex == "#112233")
                #expect(session.floatingCaptionBackgroundOpacity == 0.42)
                #expect(session.floatingCaptionStyle.backgroundShape == .rounded)
                #expect(session.selectedModel == model)
                #expect(session.sourceLanguage == source)
                #expect(session.targetLanguage == target)
                #expect(!session.isRunning)
            }
        }
    }

    @Test func editedPresetRestoresAsCustomWithoutPersistingPreview() {
        withSession { session, defaults in
            session.applyFloatingCaptionPreset(.cinema)
            session.floatingCaptionCustomPointSize = 43
            session.floatingCaptionStyle.fontFamily = .serif
            session.floatingCaptionStyle.translationFirst = true
            session.isPreviewingFloatingCaptions = true
            let restored = TranslationSessionStore(modelAvailabilityProvider: { _, _ in [:] }, settingsDefaults: defaults)
            #expect(restored.floatingCaptionPrimaryPointSize == 43)
            #expect(restored.floatingCaptionStyle.fontFamily == .serif)
            #expect(restored.floatingCaptionStyle.translationFirst)
            #expect(restored.floatingCaptionStyle.textEffect == .outline)
            #expect(restored.selectedFloatingCaptionPreset == nil)
            #expect(!restored.isPreviewingFloatingCaptions)
        }
    }

    @Test func presetRespectsOriginalOnlyModeAndRestoresPreviousDisplayChoice() {
        withSession { session, _ in
            session.floatingCaptionDisplayMode = .translation
            session.useTranscribeOnlyMode()
            session.applyFloatingCaptionPreset(.lecture)
            #expect(session.floatingCaptionDisplayMode == .original)
            #expect(session.isTranscribeOnlyMode)
            session.useTranslationMode()
            #expect(session.floatingCaptionDisplayMode == .translation)
        }
    }

    @Test func expandedSpacingUsesSameHeightBudgetAsVisibleBlocks() {
        withSession { session, _ in
            session.floatingCaptionDisplayMode = .originalAndTranslation
            session.floatingCaptionCustomPointSize = 72
            session.floatingCaptionLineCount = .six
            session.floatingCaptionStyle.fontFamily = .serif
            session.floatingCaptionStyle.lineSpacing = .relaxed
            session.floatingCaptionMeasuredContentHeight = 350
            let lines = session.floatingCaptionEffectiveLineCount
            let required = FloatingCaptionAppearance.blockHeight(lineHeight: session.floatingCaptionPrimaryLineHeight, lineCount: lines, lineSpacing: 10)
                + FloatingCaptionAppearance.blockHeight(lineHeight: session.floatingCaptionSecondaryLineHeight, lineCount: lines, lineSpacing: 10)
                + FloatingCaptionAppearance.captionBlockSpacing
            #expect(lines >= 1)
            #expect(lines < 6)
            #expect(required <= 350)
            let availableAtMinimum = session.floatingCaptionMinimumWindowHeight - FloatingCaptionAppearance.windowVerticalPadding
            #expect(availableAtMinimum >= session.floatingCaptionPrimaryLineHeight + session.floatingCaptionSecondaryLineHeight + FloatingCaptionAppearance.captionBlockSpacing)
        }
    }

    @Test func resetRestoresAddedOptionsWithoutChangingWindowPreference() {
        withSession { session, defaults in
            session.applyFloatingCaptionPreset(.paper)
            session.floatingCaptionStyle.translationFirst = true
            session.floatingCaptionDisplayMode = .translation
            session.keepsFloatingCaptionAboveOtherWindows = false
            session.resetFloatingCaptionAppearance()
            let restored = TranslationSessionStore(modelAvailabilityProvider: { _, _ in [:] }, settingsDefaults: defaults)
            #expect(restored.floatingCaptionStyle == .standard)
            #expect(restored.selectedFloatingCaptionPreset == .standard)
            #expect(restored.floatingCaptionDisplayMode == .translation)
            #expect(!restored.keepsFloatingCaptionAboveOtherWindows)
        }
    }

    @Test func glyphMeasuredWrappingFitsEveryFontAndRetainsNewestWords() {
        let examples = [
            "WWWWWWWWWWWWWWWW iiiiiiiiii https://example.com/averylongwordwithoutspaces newest",
            "중요한말을놓치지않도록긴문장과자막의줄바꿈을확인합니다마지막",
            "大切な言葉を読みやすく表示して字幕の最後まで確認します最後",
            "让重要的话语清晰显示在屏幕上并且始终保留最新的内容最后",
            "👩🏽‍💻 👨‍👩‍👧‍👦 🏳️‍🌈 👩🏽‍💻 👨‍👩‍👧‍👦 final"
        ]
        for family in FloatingCaptionFontFamily.allCases {
            let style = FloatingCaptionStyle(fontFamily: family, fontWeight: .bold)
            for size: CGFloat in [18, 30, 72] {
                let font = style.nativeFont(size: size, primary: true)
                for example in examples {
                    let wrapped = example.floatingCaptionTail(maxLines: 3, availableWidth: 372, font: font)
                    #expect(wrapped.split(separator: "\n").count <= 3)
                    #expect(wrapped.last == example.last)
                    for line in wrapped.split(separator: "\n") {
                        let width = (String(line) as NSString).size(withAttributes: [.font: font]).width
                        #expect(width <= 372, "\(family) \(size) pt: \(width)")
                    }
                }
            }
        }
    }
}
