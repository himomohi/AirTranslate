import Foundation
import Testing
@testable import AirTranslate

@Suite
struct FloatingCaptionStabilityTests {
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
    func presentationQualityPresetUsesAudienceReadableCaptionsAndPersists() {
        let suiteName = "FloatingCaptionStabilityTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let first = TranslationSessionStore(
            modelAvailabilityProvider: { _, _ in [:] },
            settingsDefaults: defaults
        )
        first.presentationContext = "AI workshop for ecommerce sellers"
        first.presentationGlossary = "Gary Hong = ゲイリー・ウォン"
        first.isPresentationQualityModeEnabled = true

        #expect(first.floatingCaptionDisplayMode == .translation)
        #expect(first.floatingCaptionTextSize == .large)
        #expect(first.floatingCaptionLineCount == .two)
        #expect(first.floatingCaptionStability == .steady)
        #expect(first.floatingCaptionTextAlignment == .leading)

        let second = TranslationSessionStore(
            modelAvailabilityProvider: { _, _ in [:] },
            settingsDefaults: defaults
        )
        #expect(second.isPresentationQualityModeEnabled)
        #expect(second.presentationContext == "AI workshop for ecommerce sellers")
        #expect(second.presentationGlossary == "Gary Hong = ゲイリー・ウォン")
        #expect(second.floatingCaptionDisplayMode == .translation)
        #expect(second.floatingCaptionTextSize == .large)
        #expect(second.floatingCaptionLineCount == .two)
        #expect(second.floatingCaptionStability == .steady)
        #expect(second.floatingCaptionTextAlignment == .leading)
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
        let session = TranslationSessionStore(modelAvailabilityProvider: { _, _ in [:] })
        session.floatingCaptionTextSize = .medium
        session.floatingCaptionDisplayMode = .originalAndTranslation

        // Unknown width falls back to the per-size estimate; the smaller
        // secondary font gets a proportionally wider budget.
        #expect(session.floatingCaptionLineWidthUnits(usesPrimaryFont: true) == 32)
        #expect(session.floatingCaptionLineWidthUnits(usesPrimaryFont: false) == 32 * 30 / 20)

        session.floatingCaptionMeasuredTextWidth = 372
        #expect(session.floatingCaptionLineWidthUnits(usesPrimaryFont: true) == 372.0 / 30.0)
        #expect(session.floatingCaptionLineWidthUnits(usesPrimaryFont: false) == 372.0 / 20.0)

        session.isRunning = true
        session.presentFloatingSourceText("AirTranslate keeps captions visible while you watch a lecture on your Mac.")
        let lines = session.floatingSourceText.split(separator: "\n")
        #expect(lines.count >= 2)
        #expect(lines.allSatisfy { $0.count <= 40 })
    }

    @Test
    func captionBlockHeightReservesEveryConfiguredLine() {
        let oneLine = FloatingCaptionWindowView.blockHeight(lineHeight: 30, lineCount: 1)
        let threeLines = FloatingCaptionWindowView.blockHeight(lineHeight: 30, lineCount: 3)

        #expect(oneLine == CGFloat(30))
        #expect(threeLines == CGFloat(30 * 3 + 5 * 2))
    }
}
