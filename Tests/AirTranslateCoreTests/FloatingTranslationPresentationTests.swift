import Foundation
import Testing
@testable import AirTranslate

@Suite
struct FloatingTranslationPresentationTests {
    @Test
    @MainActor
    func retranslationOfGrowingSourceIsHeldUntilTranslationDwellElapses() async throws {
        let session = makeSession()
        let source = "we are going to focus on realtime translation"

        session.presentFloatingSourceText(source)
        session.updateFloatingTranslationPresentation("우리는 실시간 번역에", sourceText: source)
        #expect(session.floatingTranslationText == "우리는 실시간 번역에")

        // Source keeps extending in place; the translation dwell clock must not
        // be reset by that, but neither must a rewrite pass before it elapses.
        session.presentFloatingSourceText(source + " today", resetsDwell: false)
        try await Task.sleep(for: .milliseconds(200))
        session.updateFloatingTranslationPresentation("오늘 우리는 실시간 번역에 집중합니다", sourceText: source + " today")

        #expect(session.floatingTranslationText == "우리는 실시간 번역에")

        // Once the translation dwell (minimum 1.2s for the balanced profile) has
        // elapsed the newest queued rewrite is promoted.
        #expect(await floatingTranslation(of: session, equals: "오늘 우리는 실시간 번역에 집중합니다", timeout: 3.0))
    }

    @Test
    @MainActor
    func translationExtensionRendersImmediatelyDuringDwell() async throws {
        let session = makeSession()
        let source = "alpha bravo charlie"

        session.presentFloatingSourceText(source)
        session.updateFloatingTranslationPresentation("알파 브라보", sourceText: source)
        session.updateFloatingTranslationPresentation("알파 브라보 찰리", sourceText: source)

        #expect(session.floatingTranslationText == "알파 브라보 찰리")
    }

    @Test
    @MainActor
    func newestQueuedRetranslationWinsWhenDwellElapses() async throws {
        let session = makeSession()
        let source = "alpha bravo charlie"

        session.presentFloatingSourceText(source)
        session.updateFloatingTranslationPresentation("첫 번째 번역", sourceText: source)
        session.updateFloatingTranslationPresentation("두 번째 번역", sourceText: source)
        session.updateFloatingTranslationPresentation("세 번째 번역", sourceText: source)

        #expect(session.floatingTranslationText == "첫 번째 번역")
        #expect(await floatingTranslation(of: session, equals: "세 번째 번역", timeout: 3.0))
    }

    @Test
    @MainActor
    func previousTranslationStaysVisibleUntilReplacementForNewSourceArrives() async throws {
        let session = makeSession()

        session.presentFloatingSourceText("first sentence")
        session.updateFloatingTranslationPresentation("첫 문장", sourceText: "first sentence")
        #expect(session.floatingTranslationText == "첫 문장")

        // A brand-new sentence replaces the source; the old translation must not
        // blink out while the new one is still pending.
        session.presentFloatingSourceText("second sentence")
        #expect(session.floatingTranslationText == "첫 문장")

        // The translation for the new source replaces the stale one at once even
        // though the translation dwell has not elapsed.
        session.updateFloatingTranslationPresentation("둘째 문장", sourceText: "second sentence")
        #expect(session.floatingTranslationText == "둘째 문장")
    }

    @Test
    @MainActor
    func staleTranslationExpiresAfterHoldTimeout() async throws {
        let session = makeSession()
        session.floatingCaptionStability = .responsive

        session.presentFloatingSourceText("first sentence")
        session.updateFloatingTranslationPresentation("첫 문장", sourceText: "first sentence")
        session.presentFloatingSourceText("second sentence")
        #expect(session.floatingTranslationText == "첫 문장")

        let timeout = FloatingCaptionStability.responsive.profile.translationHoldTimeout
        #expect(await floatingTranslation(of: session, equals: "", timeout: timeout + 0.8))
    }

    @Test
    @MainActor
    func translationForUnrelatedSourceIsIgnored() async throws {
        let session = makeSession()

        session.presentFloatingSourceText("current sentence")
        session.updateFloatingTranslationPresentation("현재 문장", sourceText: "current sentence")
        session.updateFloatingTranslationPresentation("엉뚱한 문장", sourceText: "unrelated sentence")

        #expect(session.floatingTranslationText == "현재 문장")
    }

    @MainActor
    private func makeSession() -> TranslationSessionStore {
        let session = TranslationSessionStore(modelAvailabilityProvider: { _, _ in [:] })
        session.useAppleDefaultMode()
        session.sourceLanguage = .english
        session.targetLanguage = .korean
        session.isAppleSourceAutoDetectionEnabled = false
        session.isRunning = true
        session.setFloatingCaptionPresentationActive(true)
        return session
    }

    @MainActor
    private func floatingTranslation(
        of session: TranslationSessionStore,
        equals expected: String,
        timeout: TimeInterval
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if session.floatingTranslationText == expected {
                return true
            }
            // Poll gently: other suites measure MainActor latency in parallel.
            try? await Task.sleep(for: .milliseconds(40))
        }
        return session.floatingTranslationText == expected
    }
}
