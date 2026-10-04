import Foundation
import Testing
@testable import AirTranslate

@Suite
struct FloatingPresentationPolicyTests {
    @Test
    @MainActor
    func prefixExtensionUpdatesFloatingCaptionInPlaceBeforeDwellElapses() async throws {
        let session = makeSession()
        let transcriber = LiveSpeechTranscriber()
        let base = "alpha bravo charlie delta echo foxtrot golf hotel"

        session.liveSpeechTranscriber(transcriber, didRecognize: base, language: .english, confidence: 0.9)
        #expect(await floatingSource(of: session, contains: "hotel"))

        // Leave the early revision window (0.45s) but stay inside the dwell.
        try await Task.sleep(for: .milliseconds(600))

        session.liveSpeechTranscriber(
            transcriber,
            didRecognize: base + " india juliet kilo",
            language: .english,
            confidence: 0.9
        )

        #expect(await floatingSource(of: session, contains: "kilo", timeout: 0.3))
    }

    @Test
    @MainActor
    func tailRewriteWaitsForCappedDwellThenAdvancesByUnreadLength() async throws {
        let session = makeSession()
        let transcriber = LiveSpeechTranscriber()
        let base = "alpha bravo charlie delta echo foxtrot golf hotel india"

        session.liveSpeechTranscriber(
            transcriber,
            didRecognize: base + " juliet",
            language: .english,
            confidence: 0.9
        )
        #expect(await floatingSource(of: session, contains: "juliet"))

        try await Task.sleep(for: .milliseconds(600))

        session.liveSpeechTranscriber(
            transcriber,
            didRecognize: base + " kilogram",
            language: .english,
            confidence: 0.9
        )
        try await Task.sleep(for: .milliseconds(80))

        // Past the early revision window and inside the dwell, a tail rewrite queues.
        #expect(!session.floatingSourceText.contains("kilogram"))
        #expect(session.floatingSourceText.contains("juliet"))

        // The capped dwell (2.2s) promotes the queued rewrite shortly after.
        #expect(await floatingSource(of: session, contains: "kilogram", timeout: 2.6))

        // The promotion introduced only a few unread characters, so the next
        // rewrite advances after the minimum dwell instead of a length-based one.
        try await Task.sleep(for: .milliseconds(1_500))
        session.liveSpeechTranscriber(
            transcriber,
            didRecognize: base + " lambda victor",
            language: .english,
            confidence: 0.9
        )

        #expect(await floatingSource(of: session, contains: "lambda", timeout: 0.3))
    }

    @MainActor
    private func makeSession() -> TranslationSessionStore {
        let session = TranslationSessionStore(modelAvailabilityProvider: { _, _ in [:] })
        session.useAppleDefaultMode()
        session.sourceLanguage = .english
        session.targetLanguage = .korean
        session.isAppleSourceAutoDetectionEnabled = false
        session.paragraphBreakSilenceInterval = 30
        session.isRunning = true
        session.setFloatingCaptionPresentationActive(true)
        return session
    }

    @MainActor
    private func floatingSource(
        of session: TranslationSessionStore,
        contains marker: String,
        timeout: TimeInterval = 1.0
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if session.floatingSourceText.contains(marker) {
                return true
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return session.floatingSourceText.contains(marker)
    }
}
