import CoreMedia
import Foundation
import Testing
@testable import AirTranslate

@Suite
struct FloatingCaptionHistoryTests {
    private let start = Date(timeIntervalSince1970: 100)
    private let first = FloatingCaptionIdentity.appleSegment("first")
    private let second = FloatingCaptionIdentity.appleSegment("second")

    @Test func partialExtensionsAndFinalCorrectionsDoNotCreateHistory() {
        var history = FloatingCaptionHistory()
        for (index, text) in ["A", "A partial", "A corrected sentence."].enumerated() {
            history.presentSource(text, identity: first, keepsHistory: true, now: start.addingTimeInterval(Double(index)))
            history.presentTranslation("번역 \(index)", identity: first, keepsHistory: true, now: start.addingTimeInterval(Double(index)))
        }
        #expect(history.source?.text == "A corrected sentence.")
        #expect(history.previousSource == nil && history.previousTranslation == nil)
        #expect(history.nextExpiry == nil)
    }

    @Test func sourceAndTranslationRetireIndependentlyWhenTheirOwnReplacementArrives() {
        var history = FloatingCaptionHistory()
        history.presentSource("First source", identity: first, keepsHistory: true, now: start)
        history.presentTranslation("첫 번역", identity: first, keepsHistory: true, now: start)
        history.presentSource("Second source", identity: second, keepsHistory: true, now: start.addingTimeInterval(1))
        #expect(history.previousSource?.caption.identity == first)
        #expect(history.translation?.text == "첫 번역")
        #expect(history.previousTranslation == nil)
        history.presentTranslation("다음 번역", identity: second, keepsHistory: true, now: start.addingTimeInterval(3))
        #expect(history.previousTranslation?.caption.identity == first)
        #expect(history.previousTranslation?.retiredAt == start.addingTimeInterval(3))
        #expect(history.previousSource?.retiredAt == start.addingTimeInterval(1))
    }

    @Test func identicalWordsInDifferentSegmentsStillCreateOnePreviousBlock() {
        var history = FloatingCaptionHistory()
        history.presentSource("Yes.", identity: first, keepsHistory: true, now: start)
        history.presentSource("Yes.", identity: second, keepsHistory: true, now: start.addingTimeInterval(1))
        #expect(history.previousSource?.caption.identity == first)
        #expect(history.source?.identity == second)
    }

    @Test func previousBlocksStayBoundedAndPartialUpdatesDoNotExtendExpiry() {
        var history = FloatingCaptionHistory()
        history.presentSource(String(repeating: "가", count: 20_000), identity: first, keepsHistory: true, now: start)
        history.presentSource("Next", identity: second, keepsHistory: true, now: start.addingTimeInterval(1))
        #expect(history.previousSource?.caption.text.count == FloatingCaptionHistory.maximumCharacters)
        for index in 0..<100 {
            history.presentSource("Next \(index)", identity: second, keepsHistory: true, now: start.addingTimeInterval(2))
        }
        #expect(history.nextExpiry == start.addingTimeInterval(9))
        history.expire(at: start.addingTimeInterval(8.99))
        #expect(history.previousSource != nil)
        history.expire(at: start.addingTimeInterval(9))
        #expect(history.previousSource == nil)
        #expect(history.source?.text == "Next 99")

        history.presentSource("Third", identity: .appleSegment("third"), keepsHistory: true, now: start.addingTimeInterval(10))
        #expect(history.previousSource?.caption.identity == second)
        history.presentSource("Fourth", identity: .appleSegment("fourth"), keepsHistory: true, now: start.addingTimeInterval(11))
        #expect(history.previousSource?.caption.identity == .appleSegment("third"))
    }

    @Test func expiredOrWithdrawnTranslationDoesNotReappearWhenNextTranslationArrives() {
        var history = FloatingCaptionHistory()
        history.presentTranslation("만료될 번역", identity: first, keepsHistory: true, now: start)
        history.presentTranslation("", identity: nil, keepsHistory: true, now: start.addingTimeInterval(1))
        history.presentTranslation("새 번역", identity: second, keepsHistory: true, now: start.addingTimeInterval(2))
        #expect(history.previousTranslation == nil)
        #expect(history.nextExpiry == nil)
    }

    @Test func cumulativeStreamsWithoutNewIdentityDoNotInventSentenceBoundaries() {
        var history = FloatingCaptionHistory()
        for text in ["First.", "First. Second.", "First. Second. Third."] {
            history.presentSource(text, identity: first, keepsHistory: true, now: start)
            history.presentTranslation(text, identity: nil, keepsHistory: true, now: start)
        }
        #expect(history.previousSource == nil && history.previousTranslation == nil)
        #expect(history.nextExpiry == nil)
    }

    @Test func independentExpiryKeepsTheLaterPaneReadableForItsFullLifetime() {
        var history = FloatingCaptionHistory()
        history.presentSource("A", identity: first, keepsHistory: true, now: start)
        history.presentTranslation("가", identity: first, keepsHistory: true, now: start)
        history.presentSource("B", identity: second, keepsHistory: true, now: start.addingTimeInterval(1))
        history.presentTranslation("나", identity: second, keepsHistory: true, now: start.addingTimeInterval(3))
        history.expire(at: start.addingTimeInterval(9))
        #expect(history.previousSource == nil)
        #expect(history.previousTranslation?.caption.text == "가")
        #expect(history.nextExpiry == start.addingTimeInterval(11))
        history.expire(at: start.addingTimeInterval(11))
        #expect(history.nextExpiry == nil)
    }
}

@Suite @MainActor
struct FloatingCaptionHistorySessionTests {
    @Test func partialUpdatesAndAppearanceChangesDoNotRescheduleHistoryExpiry() {
        withSession { session in
            let a = FloatingCaptionIdentity.line(UUID()), b = FloatingCaptionIdentity.line(UUID())
            session.setFloatingCaptionPresentationActive(true)
            session.presentFloatingSourceText("A", identity: a)
            session.presentFloatingSourceText("B", identity: b)
            let previous = session.floatingCaptionHistory.previousSource
            let schedules = session.floatingHistoryExpirySchedulesForTesting
            #expect(schedules == 1)
            for index in 0..<100 {
                session.presentFloatingSourceText("B partial \(index)", identity: b)
            }
            session.floatingCaptionCustomPointSize = 48
            session.floatingCaptionMeasuredTextWidth = 900
            _ = session.floatingSourceText
            #expect(session.floatingCaptionHistory.previousSource == previous)
            #expect(session.floatingHistoryExpirySchedulesForTesting == schedules)
        }
    }

    @Test func sameWordsFromOldSegmentCannotReplaceCurrentTranslation() {
        withSession { session in
            let a = FloatingCaptionIdentity.line(UUID()), b = FloatingCaptionIdentity.line(UUID())
            session.setFloatingCaptionPresentationActive(true)
            session.presentFloatingSourceText("Yes.", identity: a)
            session.updateFloatingTranslationPresentation("첫 번째 네.", sourceText: "Yes.", identity: a)
            session.presentFloatingSourceText("Yes.", identity: b)
            // 번역이 실제 교체되기 전에는 기존 번역의 읽기 hold를 유지한다.
            #expect(session.floatingTranslationText == "첫 번째 네.")
            #expect(session.floatingCaptionHistory.previousTranslation == nil)
            session.updateFloatingTranslationPresentation("늦게 온 이전 번역", sourceText: "Yes.", identity: a)
            #expect(session.floatingTranslationText == "첫 번째 네.")
            session.updateFloatingTranslationPresentation("두 번째 네.", sourceText: "Yes.", identity: b)
            #expect(session.floatingTranslationText == "두 번째 네.")
            #expect(session.floatingCaptionHistory.previousTranslation?.caption.identity == a)
            #expect(session.floatingCaptionHistory.translation?.identity == b)
        }
    }

    @Test func staleExpiryCompletionCannotClearAReplacementSchedule() {
        withSession { session in
            session.setFloatingCaptionPresentationActive(true)
            session.presentFloatingSourceText("A", identity: .line(UUID()))
            session.presentFloatingSourceText("B", identity: .line(UUID()))
            let oldDeadline = session.floatingCaptionHistory.nextExpiry!
            session.isPreviewingFloatingCaptions = true
            session.isPreviewingFloatingCaptions = false
            session.presentFloatingSourceText("C", identity: .line(UUID()))
            session.presentFloatingSourceText("D", identity: .line(UUID()))
            let replacement = session.floatingCaptionHistory
            let schedules = session.floatingHistoryExpirySchedulesForTesting
            #expect(replacement.nextExpiry != oldDeadline)

            session.completeFloatingHistoryExpiryForTesting(scheduledFor: oldDeadline, now: oldDeadline.addingTimeInterval(20))
            #expect(session.floatingCaptionHistory == replacement)
            #expect(session.floatingHistoryHasPendingExpiryForTesting)
            #expect(session.floatingHistoryExpirySchedulesForTesting == schedules)
        }
    }

    @Test func cancelledCompletionCannotMutateHistoryEvenWhenDeadlineStillMatches() async {
        let suiteName = "FloatingCaptionHistoryCancelledExpiry.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let session = TranslationSessionStore(modelAvailabilityProvider: { _, _ in [:] }, settingsDefaults: defaults)
        defer {
            session.setFloatingCaptionPresentationActive(false)
            defaults.removePersistentDomain(forName: suiteName)
        }
        session.setFloatingCaptionPresentationActive(true)
        session.presentFloatingSourceText("A", identity: .line(UUID()))
        session.presentFloatingSourceText("B", identity: .line(UUID()))
        let retained = session.floatingCaptionHistory
        let deadline = retained.nextExpiry!
        let schedules = session.floatingHistoryExpirySchedulesForTesting
        await Task { @MainActor in
            // 만료 대기가 끝났어도 실제 상태 반영 직전 취소된 실행을 재현한다.
            withUnsafeCurrentTask { $0?.cancel() }
            session.completeFloatingHistoryExpiryForTesting(scheduledFor: deadline, now: deadline)
        }.value
        #expect(session.floatingCaptionHistory == retained)
        #expect(session.floatingHistoryHasPendingExpiryForTesting)
        #expect(session.floatingHistoryExpirySchedulesForTesting == schedules)
    }

    @Test func closePreviewDisplayModeAndSessionResetClearHistoryAndPendingExpiry() {
        withSession { session in
            @MainActor func fillHistory() {
                session.presentFloatingSourceText("A", identity: .line(UUID()))
                session.presentFloatingSourceText("B", identity: .line(UUID()))
                #expect(session.floatingHistoryHasPendingExpiryForTesting)
            }
            session.setFloatingCaptionPresentationActive(true)
            fillHistory()
            session.isPreviewingFloatingCaptions = true
            #expect(session.floatingCaptionHistory == FloatingCaptionHistory())
            #expect(!session.floatingHistoryHasPendingExpiryForTesting)
            session.isPreviewingFloatingCaptions = false
            fillHistory()
            session.floatingCaptionDisplayMode = .translation
            #expect(session.floatingCaptionHistory.previousSource == nil)
            #expect(!session.floatingHistoryHasPendingExpiryForTesting)
            session.floatingCaptionDisplayMode = .originalAndTranslation
            fillHistory()
            session.setFloatingCaptionPresentationActive(false)
            let schedules = session.floatingHistoryExpirySchedulesForTesting
            session.presentFloatingSourceText("Closed", identity: .line(UUID()))
            #expect(session.floatingCaptionHistory == FloatingCaptionHistory())
            #expect(!session.floatingHistoryHasPendingExpiryForTesting)
            #expect(session.floatingHistoryExpirySchedulesForTesting == schedules)
            session.setFloatingCaptionPresentationActive(true)
            #expect(session.floatingCaptionHistory.previousSource == nil)
            session.useAppleDefaultMode()
            _ = session.activateLiveCallbackPipelineForTesting()
            fillHistory()
            session.stop()
            #expect(session.floatingCaptionHistory.previousSource == nil)
            #expect(!session.floatingHistoryHasPendingExpiryForTesting)
        }
    }

    @Test func appleSegmentIdentitySurvivesPartialFinalAndReopenWithoutHistoryReplay() async throws {
        let suiteName = "FloatingCaptionHistoryApple.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let session = TranslationSessionStore(modelAvailabilityProvider: { _, _ in [:] }, settingsDefaults: defaults)
        defer {
            session.setFloatingCaptionPresentationActive(false)
            session.stop()
            defaults.removePersistentDomain(forName: suiteName)
        }
        session.sourceLanguage = .english
        session.targetLanguage = .korean
        session.useAppleDefaultMode()
        session.isAppleSourceAutoDetectionEnabled = false
        session.isTranscriptPersistenceEnabled = false
        session.isDubbingEnabled = false
        session.translationForTesting = { "번역: " + $0.text }
        _ = session.activateLiveCallbackPipelineForTesting()
        session.setFloatingCaptionPresentationActive(true)
        @MainActor func deliver(_ text: String, segment: String, revision: Int, final: Bool, start: TimeInterval = 0) {
            session.receiveCaptionForTesting(text, metadata: AppleSpeechRecognitionMetadata(
                segmentID: segment, revision: revision, isFinal: final,
                audioRange: CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 1_000),
                                       duration: CMTime(seconds: 1, preferredTimescale: 1_000)),
                sourceText: text, emittedAt: Date()
            ))
        }
        deliver("Hello", segment: "apple:first", revision: 1, final: false)
        deliver("Hello there.", segment: "apple:first", revision: 2, final: true)
        #expect(session.floatingCaptionHistory.previousSource == nil)
        deliver("Hello there.", segment: "apple:second", revision: 1, final: true, start: 2)
        #expect(session.floatingCaptionHistory.previousSource?.caption.identity == .appleSegment("apple:first"))
        #expect(session.floatingCaptionHistory.source?.identity == .appleSegment("apple:second"))
        session.setFloatingCaptionPresentationActive(false)
        session.setFloatingCaptionPresentationActive(true)
        #expect(session.floatingCaptionHistory.previousSource == nil)
        #expect(session.floatingCaptionHistory.source?.identity == .appleSegment("apple:second"))
        #expect(!session.floatingHistoryHasPendingExpiryForTesting)
    }

    private func withSession(_ body: @MainActor (TranslationSessionStore) -> Void) {
        let suiteName = "FloatingCaptionHistorySessionTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let session = TranslationSessionStore(modelAvailabilityProvider: { _, _ in [:] }, settingsDefaults: defaults)
        session.isTranscriptPersistenceEnabled = false
        session.isDubbingEnabled = false
        defer {
            session.setFloatingCaptionPresentationActive(false)
            defaults.removePersistentDomain(forName: suiteName)
        }
        body(session)
    }
}
