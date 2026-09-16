import Foundation
import Testing
@testable import AirTranslate

@Suite
struct LongSessionCaptionPresentationTests {
    @Test
    @MainActor
    func standardSessionCoalescesLargeTranscriptUpdatesAndKeepsLatestText() async throws {
        let (session, _, cleanup) = try makeTranscriptionSession()
        defer { cleanup() }
        session.usesManualCaptionDeliveryForTesting = true
        let baseText = String(repeating: "long session transcript ", count: 180)
        session.receiveCaptionForTesting(baseText)
        session.flushCaptionDeliveryForTesting()
        let initialRevision = session.lines.last?.revision

        // 동일한 버스트를 한 실행 구간에 넣고 두 단계의 최신값 보존을 검증한다.
        for index in 1...100 {
            session.receiveCaptionForTesting(baseText + "latest \(index)")
        }
        #expect(session.lines.last?.revision == initialRevision)
        session.flushCaptionDeliveryForTesting()
        #expect(session.lines.last?.sourceText.hasSuffix("latest 100") == true)
        #expect(session.lines.last?.revision == initialRevision.map { $0 + 1 })
    }

    @Test
    @MainActor
    func standardSessionStillPresentsShortTranscriptImmediately() async throws {
        let (session, _, cleanup) = try makeTranscriptionSession()
        defer { cleanup() }
        let transcriber = LiveSpeechTranscriber()

        session.liveSpeechTranscriber(
            transcriber,
            didRecognize: "short transcript",
            language: .english,
            confidence: 0.9
        )
        #expect(await waitUntil { session.lines.last?.sourceText == "short transcript" })

        session.liveSpeechTranscriber(
            transcriber,
            didRecognize: "short transcript updated",
            language: .english,
            confidence: 0.9
        )

        #expect(await waitUntil(timeout: 0.1) {
            session.lines.last?.sourceText == "short transcript updated"
        })
    }

    @Test
    @MainActor
    func stopFlushesLatestCoalescedLongTranscript() async throws {
        let (session, directory, cleanup) = try makeTranscriptionSession()
        defer { cleanup() }
        let transcriber = LiveSpeechTranscriber()
        let baseText = String(repeating: "long stop transcript ", count: 200)

        session.liveSpeechTranscriber(
            transcriber,
            didRecognize: baseText,
            language: .english,
            confidence: 0.9
        )
        #expect(await waitUntil { session.lines.last != nil })

        session.liveSpeechTranscriber(
            transcriber,
            didRecognize: baseText + "final buffered words",
            language: .english,
            confidence: 0.9
        )
        await Task.yield()
        session.stop()

        #expect(session.lines.last?.sourceText.hasSuffix("final buffered words") == true)
        #expect(session.statusMessage == AppText.transcriptSavedToast)
        #expect(savedTranscriptText(in: directory).contains("final buffered words"))
    }

    @Test
    @MainActor
    func pauseFlushesLatestCoalescedLongTranscript() async throws {
        let (session, directory, cleanup) = try makeTranscriptionSession()
        defer { cleanup() }
        let transcriber = LiveSpeechTranscriber()
        let baseText = String(repeating: "long pause transcript ", count: 200)

        session.liveSpeechTranscriber(
            transcriber,
            didRecognize: baseText,
            language: .english,
            confidence: 0.9
        )
        #expect(await waitUntil { session.lines.last != nil })

        session.liveSpeechTranscriber(
            transcriber,
            didRecognize: baseText + "pause buffered words",
            language: .english,
            confidence: 0.9
        )
        await Task.yield()
        session.pause()

        #expect(session.lines.last?.sourceText.hasSuffix("pause buffered words") == true)
        #expect(session.isPaused)
        #expect(savedTranscriptText(in: directory).contains("pause buffered words"))
    }

    @Test
    @MainActor
    func terminationFlushesAndSavesLatestCoalescedLongTranscript() async throws {
        let (session, directory, cleanup) = try makeTranscriptionSession()
        defer { cleanup() }
        let transcriber = LiveSpeechTranscriber()
        let baseText = String(repeating: "long termination transcript ", count: 180)

        session.liveSpeechTranscriber(
            transcriber,
            didRecognize: baseText,
            language: .english,
            confidence: 0.9
        )
        #expect(await waitUntil { session.lines.last != nil })

        session.liveSpeechTranscriber(
            transcriber,
            didRecognize: baseText + "termination buffered words",
            language: .english,
            confidence: 0.9
        )
        await Task.yield()
        session.prepareForTermination()

        #expect(session.lines.last?.sourceText.hasSuffix("termination buffered words") == true)
        let savedFiles = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        #expect(!savedFiles.isEmpty)
        #expect(savedTranscriptText(in: directory).contains("termination buffered words"))
    }

    @Test
    @MainActor
    func runningSessionCheckpointsTranscriptWithoutStopping() async throws {
        let (session, directory, cleanup) = try makeTranscriptionSession(checkpointInterval: 0.04)
        defer { cleanup() }
        let transcriber = LiveSpeechTranscriber()

        session.liveSpeechTranscriber(
            transcriber,
            didRecognize: "checkpointed while capture remains active",
            language: .english,
            confidence: 0.9
        )

        #expect(await waitUntil(timeout: 1.5) {
            savedTranscriptText(in: directory).contains("checkpointed while capture remains active")
        })
        #expect(session.isRunning)
        #expect(!session.isPaused)
        session.stop()
    }

    @Test
    @MainActor
    func fiftyThousandCharacterBurstDoesNotStarveMainActorHeartbeat() async throws {
        let (session, _, cleanup) = try makeTranscriptionSession()
        defer { cleanup() }
        let transcriber = LiveSpeechTranscriber()
        let baseText = String(repeating: "responsive long transcript ", count: 2_000)

        session.liveSpeechTranscriber(
            transcriber,
            didRecognize: baseText,
            language: .english,
            confidence: 0.9
        )
        #expect(await waitUntil(timeout: 0.6) { session.lines.last != nil })

        for index in 1...200 {
            session.liveSpeechTranscriber(
                transcriber,
                didRecognize: baseText + "latest \(index)",
                language: .english,
                confidence: 0.9
            )
        }

        let heartbeatScheduledAt = Date()
        let heartbeat = Task { @MainActor in Date() }
        let heartbeatDate = await heartbeat.value
        let heartbeatDelay = heartbeatDate.timeIntervalSince(heartbeatScheduledAt)

        #expect(heartbeatDelay < 0.5)
        session.stop()
        #expect(session.lines.last?.sourceText.hasSuffix("latest 200") == true)
    }

    @MainActor
    private func makeTranscriptionSession(
        checkpointInterval: TimeInterval = 30
    ) throws -> (TranslationSessionStore, URL, () -> Void) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AirTranslateLongSessionTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let suiteName = "AirTranslateLongSessionSettings-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let session = TranslationSessionStore(
            modelAvailabilityProvider: { _, _ in [:] },
            settingsDefaults: defaults,
            transcriptsDirectoryURL: directory,
            transcriptCheckpointInterval: checkpointInterval
        )
        session.useTranscribeOnlyMode()
        session.sourceLanguage = .english
        session.targetLanguage = .korean
        session.sessionDurationMode = .standard
        session.isTranscriptPersistenceEnabled = true
        session.isAppleSourceAutoDetectionEnabled = false
        session.paragraphBreakSilenceInterval = 30
        session.isRunning = true
        return (session, directory, {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: directory)
        })
    }

    private func savedTranscriptText(in directory: URL) -> String {
        guard let fileURLs = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else {
            return ""
        }

        return fileURLs
            .compactMap { try? String(contentsOf: $0, encoding: .utf8) }
            .joined(separator: "\n")
    }

    @MainActor
    private func waitUntil(
        timeout: TimeInterval = 0.3,
        _ condition: @escaping @MainActor () -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() {
                return true
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }
}
