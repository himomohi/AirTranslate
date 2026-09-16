import AppKit
import Foundation
import Testing
@testable import AirTranslate

@Suite
struct FloatingCaptionStabilityTests {
    private func isolatedDefaults(_ label: String) -> (String, UserDefaults) {
        let suiteName = "\(label).\(UUID().uuidString)"
        return (suiteName, UserDefaults(suiteName: suiteName)!)
    }

    @Test
    func colorCodesRejectIncompleteInputAndClampExtendedRGB() {
        #expect(FloatingCaptionAppearance.nsColor(hex: "#12") == nil)
        #expect(FloatingCaptionAppearance.nsColor(hex: "#GG0000") == nil)
        #expect(FloatingCaptionAppearance.normalizedHex("  ffcc00  ", fallback: "#FFFFFF") == "#FFCC00")
        let extended = NSColor(colorSpace: .extendedSRGB, components: [1.5, -0.2, 0.5, 1], count: 4)
        #expect(FloatingCaptionAppearance.hexString(from: extended) == "#FF0080")
    }

    @Test
    func balancedProfileKeepsPreviousDefaults() {
        let profile = FloatingCaptionStability.balanced.profile

        #expect(profile.earlyRevisionWindow == 0.45)
        #expect(profile.minimumDwell == 1.2)
        #expect(profile.maximumDwell == 2.2)
    }

    @Test
    func steadierProfilesHoldTextLonger() {
        let responsive = FloatingCaptionStability.responsive.profile
        let balanced = FloatingCaptionStability.balanced.profile
        let steady = FloatingCaptionStability.steady.profile

        #expect(responsive.minimumDwell < balanced.minimumDwell)
        #expect(balanced.minimumDwell < steady.minimumDwell)
        #expect(responsive.maximumDwell < balanced.maximumDwell)
        #expect(balanced.maximumDwell < steady.maximumDwell)
        #expect(steady.earlyRevisionWindow <= balanced.earlyRevisionWindow)
        #expect(responsive.translationHoldTimeout < steady.translationHoldTimeout)
    }

    @Test
    func dwellScalesWithUnreadLengthInsideProfileBounds() {
        let profile = FloatingCaptionStability.balanced.profile

        #expect(profile.dwell(forUnreadLength: 0) == profile.minimumDwell)
        #expect(profile.dwell(forUnreadLength: 28) == max(profile.minimumDwell, 1.9))
        #expect(profile.dwell(forUnreadLength: 10_000) == profile.maximumDwell)
        #expect(profile.dwell(forUnreadLength: -5) == profile.minimumDwell)
    }

    @Test
    @MainActor
    func stabilityAndAlignmentPersistAcrossSessions() {
        let suiteName = "FloatingCaptionStabilityTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let first = TranslationSessionStore(
            modelAvailabilityProvider: { _, _ in [:] },
            settingsDefaults: defaults
        )
        #expect(first.floatingCaptionStability == .balanced)
        #expect(first.floatingCaptionTextAlignment == .center)

        first.floatingCaptionStability = .steady
        first.floatingCaptionTextAlignment = .leading

        let second = TranslationSessionStore(
            modelAvailabilityProvider: { _, _ in [:] },
            settingsDefaults: defaults
        )
        #expect(second.floatingCaptionStability == .steady)
        #expect(second.floatingCaptionTextAlignment == .leading)
    }

    @Test
    @MainActor
    func customAppearancePersistsAcrossSessionsWithoutReplacingPreset() {
        let suiteName = "FloatingCaptionAppearanceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let first = TranslationSessionStore(
            modelAvailabilityProvider: { _, _ in [:] },
            settingsDefaults: defaults
        )
        first.floatingCaptionTextSize = .large
        first.floatingCaptionCustomPointSize = 41
        first.floatingCaptionTextColorHex = "#112233"
        first.floatingCaptionBackgroundColorHex = "#445566"
        first.floatingCaptionBackgroundOpacity = 0

        let second = TranslationSessionStore(
            modelAvailabilityProvider: { _, _ in [:] },
            settingsDefaults: defaults
        )
        #expect(second.floatingCaptionTextSize == .large)
        #expect(second.floatingCaptionCustomPointSize == 41)
        #expect(second.floatingCaptionPrimaryPointSize == 41)
        #expect(second.floatingCaptionSecondaryPointSize == FloatingCaptionAppearance.secondaryPointSize(for: 41))
        #expect(second.floatingCaptionTextColorHex == "#112233")
        #expect(second.floatingCaptionBackgroundColorHex == "#445566")
        #expect(second.floatingCaptionBackgroundOpacity == 0)
    }


    @Test
    @MainActor
    func selectingPresetClearsCustomOverrideAfterRestore() {
        let suiteName = "FloatingCaptionPresetOverrideTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let first = TranslationSessionStore(
            modelAvailabilityProvider: { _, _ in [:] },
            settingsDefaults: defaults
        )
        first.floatingCaptionTextSize = .large
        first.floatingCaptionCustomPointSize = 31

        let restored = TranslationSessionStore(
            modelAvailabilityProvider: { _, _ in [:] },
            settingsDefaults: defaults
        )
        #expect(restored.floatingCaptionTextSize == .large)
        #expect(restored.floatingCaptionCustomPointSize == 31)
        #expect(restored.floatingCaptionPrimaryPointSize == 31)

        restored.selectFloatingCaptionTextSizePreset(.small)

        #expect(restored.floatingCaptionTextSize == .small)
        #expect(restored.floatingCaptionCustomPointSize == FloatingCaptionAppearance.defaultCustomPointSize)
        #expect(restored.floatingCaptionPrimaryPointSize == FloatingCaptionTextSize.small.primaryPointSize)
    }

    @Test
    @MainActor
    func corruptAppearanceDefaultsAreClampedOnRestore() {
        let suiteName = "FloatingCaptionCorruptAppearanceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(Double.infinity, forKey: "floatingCaptionCustomPointSize")
        defaults.set(Double.nan, forKey: "floatingCaptionBackgroundOpacity")
        defaults.set("not-a-color", forKey: "floatingCaptionTextColorHex")
        defaults.set("#XYZ123", forKey: "floatingCaptionBackgroundColorHex")

        let session = TranslationSessionStore(
            modelAvailabilityProvider: { _, _ in [:] },
            settingsDefaults: defaults
        )
        #expect(session.floatingCaptionCustomPointSize == FloatingCaptionAppearance.defaultCustomPointSize)
        #expect(session.floatingCaptionBackgroundOpacity == FloatingCaptionAppearance.defaultBackgroundOpacity)
        #expect(session.floatingCaptionTextColorHex == FloatingCaptionAppearance.defaultTextColorHex)
        #expect(session.floatingCaptionBackgroundColorHex == FloatingCaptionAppearance.defaultBackgroundColorHex)
    }

    @Test
    @MainActor
    func resetAppearanceRestoresBaselineWithoutChangingDisplayMode() {
        let (suiteName, defaults) = isolatedDefaults("FloatingCaptionResetAppearanceTests")
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let session = TranslationSessionStore(
            modelAvailabilityProvider: { _, _ in [:] },
            settingsDefaults: defaults
        )
        session.floatingCaptionDisplayMode = .translation
        session.floatingCaptionTextSize = .extraLarge
        session.floatingCaptionLineCount = .six
        session.floatingCaptionStability = .steady
        session.floatingCaptionTextAlignment = .leading
        session.floatingCaptionCustomPointSize = 64
        session.floatingCaptionTextColorHex = "#112233"
        session.floatingCaptionBackgroundColorHex = "#445566"
        session.floatingCaptionBackgroundOpacity = 0

        session.resetFloatingCaptionAppearance()

        #expect(session.floatingCaptionDisplayMode == .translation)
        #expect(session.floatingCaptionTextSize == .medium)
        #expect(session.floatingCaptionLineCount == .three)
        #expect(session.floatingCaptionStability == .balanced)
        #expect(session.floatingCaptionTextAlignment == .center)
        #expect(session.floatingCaptionCustomPointSize == FloatingCaptionAppearance.defaultCustomPointSize)
        #expect(session.floatingCaptionTextColorHex == FloatingCaptionAppearance.defaultTextColorHex)
        #expect(session.floatingCaptionBackgroundColorHex == FloatingCaptionAppearance.defaultBackgroundColorHex)
        #expect(session.floatingCaptionBackgroundOpacity == FloatingCaptionAppearance.defaultBackgroundOpacity)
    }

    @Test
    func unknownPersistedStabilityFallsBackToDefault() {
        #expect(FloatingCaptionStability(rawValue: "turbo") == nil)
        #expect(FloatingCaptionTextAlignment(rawValue: "justify") == nil)
    }

    @Test
    func measuredWidthConvertsToEmUnitsPerFont() {
        #expect(FloatingCaptionTextSize.lineWidthUnits(forAvailableWidth: 0, pointSize: 30) == 0)
        #expect(FloatingCaptionTextSize.lineWidthUnits(forAvailableWidth: 600, pointSize: 0) == 0)
        #expect(FloatingCaptionTextSize.lineWidthUnits(forAvailableWidth: 600, pointSize: 30) == 20)
        #expect(FloatingCaptionTextSize.lineWidthUnits(forAvailableWidth: 600, pointSize: 20) == 30)
    }

    @Test
    @MainActor
    func captionsWrapToMeasuredWindowWidthWhenAvailable() {
        let (suiteName, defaults) = isolatedDefaults("FloatingCaptionWrapTests")
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let session = TranslationSessionStore(
            modelAvailabilityProvider: { _, _ in [:] },
            settingsDefaults: defaults
        )
        session.floatingCaptionTextSize = .medium
        session.floatingCaptionCustomPointSize = FloatingCaptionAppearance.defaultCustomPointSize
        session.floatingCaptionDisplayMode = .originalAndTranslation

        // Unknown width falls back to the per-size estimate; the smaller
        // secondary font gets a proportionally wider budget.
        #expect(session.floatingCaptionLineWidthUnits(usesPrimaryFont: true) == 32)
        #expect(session.floatingCaptionLineWidthUnits(usesPrimaryFont: false) == 32 * 30 / 20)

        session.floatingCaptionMeasuredTextWidth = 372
        #expect(session.floatingCaptionLineWidthUnits(usesPrimaryFont: true) == 372.0 / 30.0)
        #expect(session.floatingCaptionLineWidthUnits(usesPrimaryFont: false) == 372.0 / 20.0)

        session.floatingCaptionCustomPointSize = 60
        #expect(session.floatingCaptionLineWidthUnits(usesPrimaryFont: true) == 372.0 / 60.0)
        #expect(session.floatingCaptionLineWidthUnits(usesPrimaryFont: false) == 372.0 / 40.0)

        session.isRunning = true
        session.presentFloatingSourceText("AirTranslate keeps captions visible while you watch a lecture on your Mac.")
        let lines = session.floatingSourceText.split(separator: "\n")
        #expect(lines.count >= 2)
        #expect(lines.allSatisfy { $0.count <= 40 })
    }

    @Test
    @MainActor
    func extremeDualCaptionSettingsReduceEffectiveLinesToAvailableHeight() {
        let (suiteName, defaults) = isolatedDefaults("FloatingCaptionExtremeLinesTests")
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let session = TranslationSessionStore(
            modelAvailabilityProvider: { _, _ in [:] },
            settingsDefaults: defaults
        )
        session.floatingCaptionDisplayMode = .originalAndTranslation
        session.floatingCaptionLineCount = .six
        session.floatingCaptionCustomPointSize = 72
        session.floatingCaptionMeasuredTextWidth = 520
        session.floatingCaptionMeasuredContentHeight = 360

        #expect(session.floatingCaptionEffectiveLineCount < FloatingCaptionLineCount.six.rawValue)
        session.isRunning = true
        session.presentFloatingSourceText("""
        One two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen sixteen seventeen eighteen nineteen twenty.
        """)
        let lines = session.floatingSourceText.split(separator: "\n")
        #expect(lines.count <= session.floatingCaptionEffectiveLineCount)
    }


    @Test
    @MainActor
    func extremeDualCaptionMinimumHeightFitsOneLineBlocks() {
        let (suiteName, defaults) = isolatedDefaults("FloatingCaptionMinimumHeightTests")
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let session = TranslationSessionStore(
            modelAvailabilityProvider: { _, _ in [:] },
            settingsDefaults: defaults
        )
        session.floatingCaptionDisplayMode = .originalAndTranslation
        session.floatingCaptionLineCount = .six
        session.floatingCaptionCustomPointSize = 72

        let minimumContentHeight = session.floatingCaptionMinimumWindowHeight - FloatingCaptionAppearance.windowVerticalPadding
        let requiredOneLineHeight = FloatingCaptionAppearance.blockHeight(
            lineHeight: session.floatingCaptionPrimaryLineHeight,
            lineCount: 1
        ) + FloatingCaptionAppearance.blockHeight(
            lineHeight: session.floatingCaptionSecondaryLineHeight,
            lineCount: 1
        ) + FloatingCaptionAppearance.captionBlockSpacing

        #expect(minimumContentHeight >= requiredOneLineHeight)
    }

    @Test
    func captionBlockHeightReservesEveryConfiguredLine() {
        let oneLine = FloatingCaptionAppearance.blockHeight(lineHeight: 30, lineCount: 1)
        let threeLines = FloatingCaptionAppearance.blockHeight(lineHeight: 30, lineCount: 3)

        #expect(oneLine == CGFloat(30))
        #expect(threeLines == CGFloat(30 * 3 + 5 * 2))
    }
}
