import CoreMedia
import Foundation
import Testing
@testable import AirTranslate

@MainActor
private final class FloatingActivityTranslator {
    private(set) var invocationCount = 0

    func translate(_ invocation: TranslationInvocationForTesting) -> String {
        invocationCount += 1
        return "번역: " + invocation.text
    }
}

@MainActor
private final class DelayedFloatingActivityTranslator {
    private(set) var invocationCount = 0
    private var continuation: CheckedContinuation<String, Never>?

    func translate(_ invocation: TranslationInvocationForTesting) async -> String {
        invocationCount += 1
        return await withCheckedContinuation { continuation = $0 }
    }

    func complete(_ translatedText: String) {
        let pending = continuation
        continuation = nil
        pending?.resume(returning: translatedText)
    }
}

@Suite
@MainActor
struct FloatingCaptionActivityTests {
    @Test
    func inactivePresentationDoesNoFloatingWorkWhileSourceAndTranslationContinue() async throws {
        let fixture = makeFixture()
        defer { fixture.cleanup() }
        let session = fixture.session
        #expect(!session.isFloatingCaptionPresentationActive)
        let initialWork = session.floatingPresentationWorkCountForTesting

        deliver("A completed phrase.", segment: 1, revision: 1, final: true, to: session)
        #expect(await waitUntil { session.lines.last?.translatedText == "번역: A completed phrase." })
        #expect(session.lines.last?.sourceText == "A completed phrase.")
        #expect(fixture.translator.invocationCount == 1)
        #expect(session.floatingPresentationWorkCountForTesting == initialWork)
        #expect(!session.floatingPresentationHasPendingTasksForTesting)
        #expect(session.floatingSourceText.isEmpty && session.floatingTranslationText.isEmpty)
    }

    @Test
    func openingRestoresLatestCanonicalTextImmediatelyAndTogglesDoNotRetranslate() async throws {
        let fixture = makeFixture()
        defer { fixture.cleanup() }
        let session = fixture.session
        deliver("The first phrase.", segment: 1, revision: 1, final: true, to: session)
        #expect(await waitUntil { fixture.translator.invocationCount == 1 && session.lines.last?.translatedSourceText == "The first phrase." })
        session.setFloatingCaptionPresentationActive(true)
        #expect(session.floatingSourceText == "The first phrase.")
        #expect(session.floatingTranslationText == "번역: The first phrase.")

        session.setFloatingCaptionPresentationActive(false)
        let workWhenClosed = session.floatingPresentationWorkCountForTesting
        deliver("The latest phrase.", segment: 2, revision: 1, final: true, to: session)
        #expect(await waitUntil { session.lines.last?.translatedSourceText == "The latest phrase." })
        #expect(session.floatingPresentationWorkCountForTesting == workWhenClosed)
        session.setFloatingCaptionPresentationActive(true)
        #expect(session.floatingSourceText == "The latest phrase.")
        #expect(session.floatingTranslationText == "번역: The latest phrase.")

        for _ in 0..<12 {
            session.setFloatingCaptionPresentationActive(false)
            session.setFloatingCaptionPresentationActive(true)
            #expect(session.floatingSourceText == "The latest phrase.")
            #expect(!session.floatingPresentationHasPendingTasksForTesting)
        }
        await settleMainActor()
        #expect(fixture.translator.invocationCount == 2)
        #expect(session.lines.count == 2)
    }

    @Test
    func reopeningAfterSourceCorrectionDoesNotKeepPreviousTranslationBeyondHoldTimeout() async throws {
        let fixture = makeFixture()
        let delayedTranslator = DelayedFloatingActivityTranslator()
        defer {
            delayedTranslator.complete("")
            fixture.cleanup()
        }
        let session = fixture.session
        let originalSource = "Book a flight to Seoul."
        let correctedSource = "Book a flight to Busan."
        let originalTranslation = "번역: " + originalSource
        session.floatingCaptionStability = .responsive
        session.setFloatingCaptionPresentationActive(true)
        deliver(originalSource, segment: 1, revision: 1, final: false, to: session)
        try #require(await waitUntil { session.lines.last?.translatedSourceText == originalSource })
        let lineID = try #require(session.lines.last?.id)
        #expect(session.floatingTranslationText == originalTranslation)

        session.translationForTesting = { await delayedTranslator.translate($0) }
        deliver(correctedSource, segment: 1, revision: 2, final: false, to: session)
        try #require(await waitUntil { delayedTranslator.invocationCount == 1 })
        try #require(session.lines.last?.id == lineID)
        try #require(session.lines.last?.sourceText == correctedSource)
        try #require(session.lines.last?.translatedSourceText == originalSource)
        try #require(session.lines.last?.translatedText == originalTranslation)

        session.setFloatingCaptionPresentationActive(false)
        session.setFloatingCaptionPresentationActive(true)
        #expect(session.floatingSourceText == correctedSource)
        // 이전 원문에 속한 번역은 즉시 비우거나 기존 hold 만료로 제거해야 한다.
        #expect(session.floatingTranslationText.isEmpty || session.floatingPresentationHasPendingTasksForTesting)
        let holdTimeout = FloatingCaptionStability.responsive.profile.translationHoldTimeout
        #expect(await waitUntil(timeout: holdTimeout + 0.8) { session.floatingTranslationText.isEmpty })
        #expect(session.lines.last?.translatedText == originalTranslation)
        #expect(session.lines.last?.translatedSourceText == originalSource)
        #expect(!session.floatingPresentationHasPendingTasksForTesting)

        // 읽기 유예가 끝난 이전 원문의 번역은 재오픈으로 다시 살아나면 안 된다.
        session.setFloatingCaptionPresentationActive(false)
        session.setFloatingCaptionPresentationActive(true)
        #expect(session.floatingTranslationText.isEmpty)
        #expect(session.floatingCaptionHistory.previousTranslation == nil)

        delayedTranslator.complete("부산행 항공편을 예약하세요.")
        try #require(await waitUntil { session.lines.last?.translatedSourceText == correctedSource })
        #expect(session.floatingTranslationText == "부산행 항공편을 예약하세요.")
        #expect(fixture.translator.invocationCount == 1)
        #expect(delayedTranslator.invocationCount == 1)
    }

    @Test
    func closingCancelsDwellAndHoldTasksAndDirectUpdatesCannotRestartThem() async {
        let fixture = makeFixture()
        defer { fixture.cleanup() }
        let session = fixture.session
        session.setFloatingCaptionPresentationActive(true)
        session.presentFloatingSourceText("current sentence")
        session.updateFloatingTranslationPresentation("첫 번역", sourceText: "current sentence")
        session.updateFloatingTranslationPresentation("바뀐 번역", sourceText: "current sentence")
        #expect(session.floatingPresentationHasPendingTasksForTesting)
        session.presentFloatingSourceText("a different sentence")
        #expect(session.floatingPresentationHasPendingTasksForTesting)

        session.setFloatingCaptionPresentationActive(false)
        let workWhenClosed = session.floatingPresentationWorkCountForTesting
        for _ in 0..<20 {
            session.presentFloatingSourceText("ignored presentation")
            session.updateFloatingTranslationPresentation("표시 전용 갱신", sourceText: "ignored presentation")
        }
        await settleMainActor()
        #expect(!session.floatingPresentationHasPendingTasksForTesting)
        #expect(session.floatingPresentationWorkCountForTesting == workWhenClosed)
        #expect(session.floatingSourceText.isEmpty && session.floatingTranslationText.isEmpty)
        #expect(fixture.translator.invocationCount == 0)
    }

    @Test
    func reopeningDuringPartialDoesNotDuplicateCommittedTextOnNextRecognition() async throws {
        let fixture = makeFixture()
        defer { fixture.cleanup() }
        let session = fixture.session
        deliver("Alpha beta", segment: 1, revision: 1, final: false, to: session)
        #expect(await waitUntil { fixture.translator.invocationCount == 1 })
        session.setFloatingCaptionPresentationActive(true)
        #expect(session.floatingSourceText == "Alpha beta")
        deliver("Alpha beta gamma.", segment: 1, revision: 2, final: true, to: session)
        #expect(session.floatingSourceText == "Alpha beta gamma.")

        session.setFloatingCaptionPresentationActive(false)
        session.setFloatingCaptionPresentationActive(true)
        deliver("Next phrase.", segment: 2, revision: 1, final: true, to: session)
        #expect(session.floatingSourceText == "Next phrase.")
        #expect(session.lines.count == 2)
    }

    @Test
    func inactiveQwenDirectPresentationKeepsCanonicalTextAndReopensWithoutNetworkWork() {
        let fixture = makeFixture()
        defer { fixture.cleanup() }
        let session = fixture.session
        session.stop()
        session.useQwenTranslationMode()
        let pipeline = session.activateLiveCallbackPipelineForTesting()
        let workWhenClosed = session.floatingPresentationWorkCountForTesting
        session.deliverQwenTextForTesting("Provider source.", isFinal: true, isTranslation: false, generation: pipeline.generation)
        session.deliverQwenTextForTesting("제공자 번역.", isFinal: true, isTranslation: true, generation: pipeline.generation)
        #expect(session.lines.last?.sourceText == "Provider source.")
        #expect(session.lines.last?.translatedText == "제공자 번역.")
        #expect(session.floatingPresentationWorkCountForTesting == workWhenClosed)
        #expect(!session.floatingPresentationHasPendingTasksForTesting)
        session.setFloatingCaptionPresentationActive(true)
        #expect(session.floatingSourceText == "Provider source.")
        #expect(session.floatingTranslationText == "제공자 번역.")
        #expect(fixture.translator.invocationCount == 0)
        session.finishQwenPipelineForTesting()
    }

    private struct Fixture {
        let session: TranslationSessionStore
        let translator: FloatingActivityTranslator
        let defaults: UserDefaults
        let suiteName: String

        @MainActor
        func cleanup() {
            session.setFloatingCaptionPresentationActive(false)
            session.stop()
            defaults.removePersistentDomain(forName: suiteName)
        }
    }

    private func makeFixture() -> Fixture {
        let suiteName = "FloatingCaptionActivityTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let session = TranslationSessionStore(modelAvailabilityProvider: { _, _ in [:] }, settingsDefaults: defaults)
        let translator = FloatingActivityTranslator()
        session.sourceLanguage = .english
        session.targetLanguage = .korean
        session.useAppleDefaultMode()
        session.isAppleSourceAutoDetectionEnabled = false
        session.isTranscriptPersistenceEnabled = false
        session.isDubbingEnabled = false
        session.translationForTesting = { translator.translate($0) }
        _ = session.activateLiveCallbackPipelineForTesting()
        return Fixture(session: session, translator: translator, defaults: defaults, suiteName: suiteName)
    }

    private func deliver(_ text: String, segment: Int, revision: Int, final: Bool, to session: TranslationSessionStore) {
        session.receiveCaptionForTesting(text, metadata: AppleSpeechRecognitionMetadata(
            segmentID: "apple:en:\(segment)", revision: revision, isFinal: final,
            audioRange: CMTimeRange(start: CMTime(seconds: Double(segment) * 2, preferredTimescale: 1_000),
                                    duration: CMTime(seconds: 1, preferredTimescale: 1_000)),
            sourceText: text, emittedAt: Date()
        ))
    }

    private func waitUntil(timeout: TimeInterval = 2, _ condition: @MainActor () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: .seconds(timeout))
        while !condition(), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(1))
        }
        return condition()
    }

    private func settleMainActor() async {
        for _ in 0..<12 { await Task.yield() }
    }
}
