import Foundation
import Testing
@testable import AirTranslate

@Suite @MainActor
struct FloatingCaptionHistoryLayoutTests {
    @Test func defaultMinimumWindowKeepsCurrentAndPreviousCaptionInEveryMode() {
        for mode in FloatingCaptionDisplayMode.allCases {
            withSession { session in
                session.floatingCaptionDisplayMode = mode
                let minimum = session.floatingCaptionMinimumWindowHeight
                let expected: CGFloat = mode == .originalAndTranslation ? 185.6 : 116.4
                #expect(abs(minimum - expected) < 0.001)
                #expect(session.floatingCaptionMinimumWindowSize.height == minimum)

                session.floatingCaptionMeasuredContentHeight = minimum - 32
                let layout = session.floatingCaptionHistoryLayout
                #expect(layout.currentLines >= 1)
                #expect(layout.historyLines >= 1)
                #expect(layout.contentHeight <= minimum - 32 + 0.001)
            }
        }
    }

    @Test func largestFontMinimumReservesBothPanesAndHistoryMotion() {
        for mode in FloatingCaptionDisplayMode.allCases {
            withSession { session in
                configureLargestFont(session, mode: mode)
                let minimum = session.floatingCaptionMinimumWindowHeight
                let expected: CGFloat = mode == .originalAndTranslation ? 391.2 : 240.72
                #expect(abs(minimum - expected) < 0.001)

                session.floatingCaptionMeasuredContentHeight = minimum - 32
                let layout = session.floatingCaptionHistoryLayout
                #expect(layout.currentLines == 1)
                #expect(layout.historyLines == 1)
                #expect(layout.contentHeight <= minimum - 32 + 0.001)
            }
        }
    }

    @Test func largestFontAt720PointsReducesLinesBeforeClippingEitherPane() {
        for mode in FloatingCaptionDisplayMode.allCases {
            withSession { session in
                configureLargestFont(session, mode: mode)
                session.floatingCaptionMeasuredContentHeight = 688
                let layout = session.floatingCaptionHistoryLayout
                let usesTwoPanes = mode == .originalAndTranslation

                #expect(session.floatingCaptionPrimaryPointSize == 72)
                #expect(session.floatingCaptionSecondaryPointSize == 48)
                #expect(abs(session.floatingCaptionPrimaryLineHeight - 99.36) < 0.001)
                #expect(abs(session.floatingCaptionSecondaryLineHeight - 66.24) < 0.001)
                #expect(layout.currentLines == (usesTwoPanes ? 2 : 5))
                #expect(layout.historyLines == 1)
                #expect(abs(layout.contentHeight - (usesTwoPanes ? 544.8 : 646.16)) < 0.001)
                #expect(layout.contentHeight <= 688)
                #expect(session.floatingCaptionEffectiveLineCount == layout.currentLines)
                #expect(session.floatingCaptionPreferredWindowHeight <= 720)
                #expect(session.floatingCaptionPreferredWindowHeight >= session.floatingCaptionMinimumWindowHeight)
            }
        }
    }

    @Test func preferredHeightAndLineAllocationConvergeAfterGeometryFeedback() {
        for mode in FloatingCaptionDisplayMode.allCases {
            for usesLargestFont in [false, true] {
                withSession { session in
                    session.floatingCaptionDisplayMode = mode
                    if usesLargestFont { configureLargestFont(session, mode: mode) }
                    session.floatingCaptionMeasuredContentHeight = session.floatingCaptionMinimumWindowHeight - 32
                    let preferred = session.floatingCaptionPreferredWindowHeight

                    session.floatingCaptionMeasuredContentHeight = preferred - 32
                    let settledLayout = session.floatingCaptionHistoryLayout
                    #expect(settledLayout.currentLines >= 1)
                    #expect((1...2).contains(settledLayout.historyLines))
                    #expect(settledLayout.contentHeight <= preferred - 32 + 0.001)

                    // 창 높이를 다시 보고해도 희망 높이와 줄 배분이 누적 증가하지 않아야 한다.
                    for _ in 0..<3 {
                        session.floatingCaptionMeasuredContentHeight = session.floatingCaptionPreferredWindowHeight - 32
                        #expect(abs(session.floatingCaptionPreferredWindowHeight - preferred) < 0.001)
                        #expect(session.floatingCaptionHistoryLayout == settledLayout)
                    }

                    // 수동 확장도 다음 자동 크기 요청의 기준을 끌어올리지 않아야 한다.
                    session.floatingCaptionMeasuredContentHeight = 1_000
                    #expect(abs(session.floatingCaptionPreferredWindowHeight - preferred) < 0.001)
                }
            }
        }
    }

    @Test func showingAndClearingHistoryDoesNotChangeReservedWindowHeight() {
        withSession { session in
            session.floatingCaptionDisplayMode = .originalAndTranslation
            session.setFloatingCaptionPresentationActive(true)
            session.floatingCaptionMeasuredContentHeight = session.floatingCaptionPreferredWindowHeight - 32
            let emptyLayout = session.floatingCaptionHistoryLayout
            let minimum = session.floatingCaptionMinimumWindowHeight
            let preferred = session.floatingCaptionPreferredWindowHeight
            #expect(session.floatingCaptionHistory.previousSource == nil)
            #expect(session.floatingCaptionHistory.previousTranslation == nil)

            let first = FloatingCaptionIdentity.line(UUID())
            let second = FloatingCaptionIdentity.line(UUID())
            session.presentFloatingSourceText("First caption.", identity: first)
            session.updateFloatingTranslationPresentation("첫 번째 자막.", sourceText: "First caption.", identity: first)
            session.presentFloatingSourceText("Second caption.", identity: second)
            session.updateFloatingTranslationPresentation("두 번째 자막.", sourceText: "Second caption.", identity: second)
            #expect(session.floatingCaptionHistory.previousSource != nil)
            #expect(session.floatingCaptionHistory.previousTranslation != nil)
            #expect(session.floatingCaptionHistoryLayout == emptyLayout)
            #expect(session.floatingCaptionMinimumWindowHeight == minimum)
            #expect(session.floatingCaptionPreferredWindowHeight == preferred)

            session.setFloatingCaptionPresentationActive(false)
            #expect(session.floatingCaptionHistory.previousSource == nil)
            #expect(session.floatingCaptionHistory.previousTranslation == nil)
            #expect(session.floatingCaptionHistoryLayout == emptyLayout)
            #expect(session.floatingCaptionMinimumWindowHeight == minimum)
            #expect(session.floatingCaptionPreferredWindowHeight == preferred)
        }
    }

    @Test func undersizedViewportDropsHistoryButPreservesOneCurrentLinePerPane() {
        for usesTwoPanes in [false, true] {
            let layout = FloatingCaptionHistoryLayout(
                configuredLines: 6,
                primaryLineHeight: 99.36,
                secondaryLineHeight: 66.24,
                lineSpacing: 10,
                usesTwoPanes: usesTwoPanes,
                availableHeight: 1
            )
            #expect(layout.currentLines == 1)
            #expect(layout.historyLines == 0)
            #expect(abs(layout.contentHeight - (usesTwoPanes ? 173.6 : 99.36)) < 0.001)
        }
    }

    private func configureLargestFont(_ session: TranslationSessionStore, mode: FloatingCaptionDisplayMode) {
        session.floatingCaptionDisplayMode = mode
        session.floatingCaptionCustomPointSize = 72
        session.floatingCaptionLineCount = .six
        session.floatingCaptionStyle.fontFamily = .serif
        session.floatingCaptionStyle.lineSpacing = .relaxed
    }

    private func withSession(_ body: (TranslationSessionStore) -> Void) {
        let name = "FloatingCaptionHistoryLayoutTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        let session = TranslationSessionStore(modelAvailabilityProvider: { _, _ in [:] }, settingsDefaults: defaults)
        session.isTranscriptPersistenceEnabled = false
        session.isDubbingEnabled = false
        session.resetFloatingCaptionAppearance()
        defer {
            session.setFloatingCaptionPresentationActive(false)
            defaults.removePersistentDomain(forName: name)
        }
        body(session)
    }
}
