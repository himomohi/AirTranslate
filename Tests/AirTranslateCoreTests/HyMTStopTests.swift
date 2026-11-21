import CoreMedia
import Foundation
import Testing
@testable import AirTranslate

@Suite(.serialized)
@MainActor
struct HyMTStopTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["AIRTRANSLATE_HYMT_QUALITY"] == "1"))
    func installedNativeModelFinishesAndSavesQueuedTranslationOnStop() async throws {
        _ = try #require(try await HyMTModelStore.shared.installedModel())
        let fixture = try HyMTStopFixture()
        defer { fixture.cleanup() }
        let session = fixture.session
        session.translationForTesting = nil
        session.hyMTTerminologyText = "Apps SDK\nMCP"
        _ = session.activateLiveCallbackPipelineForTesting()
        let source = "Apps SDK is built on MCP, an open standard for connecting tools and applications."
        fixture.receive(source, isFinal: true)
        session.stop()
        #expect(session.isFinishingHyMT)
        let deadline = ContinuousClock.now.advanced(by: .seconds(20))
        while session.isRunning, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(!session.isRunning && !session.isFinishingHyMT)
        let result = try #require(session.lines.last?.translatedText)
        #expect(!result.isEmpty && result != AppText.translationCancelled && result != "또")
        #expect(result.contains("MCP"))
        #expect(try fixture.savedOriginal() == source)
        #expect(try fixture.savedTranslation() == result)
        print("HyMT native stop completed and saved: \(result)")
    }

    @Test(arguments: [false, true])
    func stopWaitsForFullTranslationAndCommitsLastVisibleCaption(isFinal: Bool) async throws {
        let fixture = try HyMTStopFixture()
        defer { fixture.cleanup() }
        let session = fixture.session
        _ = session.activateLiveCallbackPipelineForTesting()
        fixture.receive("We can build useful apps.", isFinal: isFinal)
        #expect(await waitUntil { fixture.translator.count == 1 })
        #expect(session.lines.last?.translatedText == "또")
        #expect(session.checkpointHyMTTranscriptForTesting())
        #expect(try fixture.savedTranslation() == nil)

        session.stop()
        session.stop()
        #expect(session.isRunning && session.isFinishingHyMT)
        #expect(session.captureControlState.phase == .finishing)
        #expect(!session.captureControlState.canToggleCapture)
        #expect(!session.captureControlState.canTogglePause)
        fixture.receive("Input after stop must be ignored.", isFinal: true, segment: "late")
        session.start()
        session.pause()
        #expect(!session.isStarting && !session.isPaused)
        #expect(session.lines.count == 1)
        #expect(fixture.translator.count == 1)

        fixture.translator.complete(0, text: "유용한 앱을 만들 수 있습니다.")
        #expect(await waitUntil { !session.isRunning })
        #expect(!session.isFinishingHyMT)
        #expect(session.lines.last?.isFinal == true)
        #expect(session.lines.last?.translatedText == "유용한 앱을 만들 수 있습니다.")
        #expect(try fixture.savedOriginal() == "We can build useful apps.")
        #expect(try fixture.savedTranslation() == "유용한 앱을 만들 수 있습니다.")
    }

    @Test func systemMenuStopAndDuplicateStopUseTheSameDrain() async throws {
        let fixture = try HyMTStopFixture()
        defer { fixture.cleanup() }
        let session = fixture.session
        let generation = session.activateLiveCallbackPipelineForTesting().generation
        fixture.receive("The final sentence is still translating.", isFinal: true)
        #expect(await waitUntil { fixture.translator.count == 1 })
        session.stopHyMTFromSystemMenuForTesting(generation: generation)
        session.stopHyMTFromSystemMenuForTesting(generation: generation)
        session.stop()
        #expect(session.isRunning && session.isFinishingHyMT)
        fixture.translator.complete(0, text: "마지막 문장을 번역 중입니다.")
        #expect(await waitUntil { !session.isRunning })
        #expect(try fixture.savedTranslation() == "마지막 문장을 번역 중입니다.")
        session.stopHyMTFromSystemMenuForTesting(generation: generation)
        #expect(!session.isRunning && !session.isFinishingHyMT)
    }

    @Test func smallPartialHeldByRecognitionPolicyIsTranslatedOnStop() async throws {
        let fixture = try HyMTStopFixture()
        defer { fixture.cleanup() }
        let session = fixture.session
        _ = session.activateLiveCallbackPipelineForTesting()
        fixture.receive("Hello", isFinal: false)
        #expect(fixture.translator.count == 0)
        session.stop()
        #expect(session.isFinishingHyMT)
        #expect(await waitUntil { fixture.translator.count == 1 })
        fixture.translator.complete(0, text: "안녕하세요")
        #expect(await waitUntil { !session.isRunning })
        #expect(session.lines.last?.isFinal == true)
        #expect(try fixture.savedTranslation() == "안녕하세요")
    }

    @Test func finalQueueDrainsEverySentenceInOrder() async throws {
        let fixture = try HyMTStopFixture()
        defer { fixture.cleanup() }
        let session = fixture.session
        _ = session.activateLiveCallbackPipelineForTesting()
        fixture.receive("First sentence.", isFinal: true, segment: "first")
        #expect(await waitUntil { fixture.translator.count == 1 })
        fixture.receive("Second sentence.", isFinal: true, segment: "second", start: 2)
        session.stop()
        fixture.translator.complete(0, text: "첫 문장.")
        #expect(await waitUntil { fixture.translator.count == 2 })
        #expect(session.isFinishingHyMT)
        fixture.translator.complete(1, text: "두 번째 문장.")
        #expect(await waitUntil { !session.isRunning })
        #expect(try fixture.savedOriginal() == "First sentence.\n\nSecond sentence.")
        #expect(try fixture.savedTranslation() == "첫 문장.\n\n두 번째 문장.")
    }

    @Test func timeoutDiscardsProgressAndOldResultCannotOverwriteNewSession() async throws {
        let fixture = try HyMTStopFixture()
        defer { fixture.cleanup() }
        let session = fixture.session
        session.hyMTStopTimeoutForTesting = .milliseconds(40)
        let old = session.activateLiveCallbackPipelineForTesting()
        fixture.receive("A slow old translation.", isFinal: true)
        #expect(await waitUntil { fixture.translator.count == 1 })
        session.stop()
        #expect(await waitUntil { !session.isRunning })
        #expect(!session.isFinishingHyMT)
        #expect(session.lines.last?.translatedText == AppText.translationCancelled)
        #expect(try fixture.savedTranslation() == nil)
        #expect(try fixture.savedOriginal() == "A slow old translation.")

        let current = session.activateLiveCallbackPipelineForTesting()
        #expect(current.generation != old.generation)
        session.stopHyMTFromSystemMenuForTesting(generation: old.generation)
        session.liveSpeechTranscriber(old.transcriber, didRecognize: "Stale callback.", language: .english, confidence: 1)
        fixture.receive("A new session sentence.", isFinal: true, segment: "new", start: 3)
        fixture.translator.complete(0, text: "오래된 번역이 덮어쓰면 안 됩니다.")
        #expect(await waitUntil { fixture.translator.count == 2 })
        #expect(session.isRunning && !session.isFinishingHyMT)
        #expect(!session.lines.contains { $0.sourceText == "Stale callback." })
        #expect(!session.lines.contains { $0.translatedText == "오래된 번역이 덮어쓰면 안 됩니다." })
        fixture.translator.complete(1, text: "새 세션 문장.")
        #expect(await waitUntil { session.lines.last?.translatedText == "새 세션 문장." })
        session.stop()
        #expect(!session.isRunning)
    }

    @Test func translationDeadlineDoesNotWaitForSlowCaptureCleanup() async throws {
        let fixture = try HyMTStopFixture()
        defer { fixture.cleanup() }
        let session = fixture.session
        let capture = HyMTSlowCaptureStop()
        defer { capture.release() }
        session.hyMTCaptureStopForTesting = { await capture.stop() }
        session.hyMTStopTimeoutForTesting = .milliseconds(40)
        _ = session.activateLiveCallbackPipelineForTesting()
        fixture.receive("Capture cleanup may be slow.", isFinal: true)
        #expect(await waitUntil { fixture.translator.count == 1 })
        session.stop()
        #expect(await waitUntil { capture.didStart })
        #expect(await waitUntil { !session.isRunning })
        #expect(!capture.didFinish)
        #expect(!session.isFinishingHyMT)
        #expect(try fixture.savedTranslation() == nil)
        var captureTaskFinished = false
        let waiter = Task { @MainActor in
            await session.waitForHyMTCaptureStopForTesting()
            captureTaskFinished = true
        }
        defer { waiter.cancel() }
        try await Task.sleep(for: .milliseconds(20))
        #expect(!captureTaskFinished)
        capture.release()
        #expect(await waitUntil { captureTaskFinished })
        fixture.translator.complete(0, text: "늦은 번역.")
        #expect(session.lines.last?.translatedText == AppText.translationCancelled)
    }

    @Test func inferenceFailureDoesNotSavePartialOutput() async throws {
        let fixture = try HyMTStopFixture()
        defer { fixture.cleanup() }
        let session = fixture.session
        _ = session.activateLiveCallbackPipelineForTesting()
        fixture.receive("An inference may fail.", isFinal: true)
        #expect(await waitUntil { fixture.translator.count == 1 })
        session.stop()
        fixture.translator.fail(0)
        #expect(await waitUntil { !session.isRunning })
        #expect(session.statusMessage == HyMTStopTestError.failed.localizedDescription)
        #expect(session.lines.last?.translatedText == AppText.translationCancelled)
        #expect(try fixture.savedTranslation() == nil)
    }

    @Test func terminationCancelsDrainAndLateResultCannotChangeSavedText() async throws {
        let fixture = try HyMTStopFixture()
        defer { fixture.cleanup() }
        let session = fixture.session
        _ = session.activateLiveCallbackPipelineForTesting()
        fixture.receive("Terminate while translation is pending.", isFinal: true)
        #expect(await waitUntil { fixture.translator.count == 1 })
        session.stop()
        session.prepareForTermination()
        #expect(!session.isRunning && !session.isFinishingHyMT)
        fixture.translator.complete(0, text: "종료 뒤 결과.")
        try await Task.sleep(for: .milliseconds(40))
        #expect(session.lines.last?.translatedText == AppText.translationCancelled)
        #expect(try fixture.savedTranslation() == nil)
        #expect(try fixture.savedOriginal() == "Terminate while translation is pending.")
    }

    @Test func pauseResumePreserveEngineAndStopFromPausedStillDrains() async throws {
        let fixture = try HyMTStopFixture()
        defer { fixture.cleanup() }
        let session = fixture.session
        _ = session.activateLiveCallbackPipelineForTesting()
        fixture.receive("Pause does not cancel this translation.", isFinal: true)
        #expect(await waitUntil { fixture.translator.count == 1 })
        session.pause()
        #expect(session.isPaused && session.isUsingHyMT)
        session.resume()
        #expect(!session.isPaused && session.isUsingHyMT)
        session.pause()
        session.stop()
        session.resume()
        #expect(session.isPaused && session.isFinishingHyMT)
        fixture.translator.complete(0, text: "일시정지해도 번역을 보존합니다.")
        #expect(await waitUntil { !session.isRunning })
        #expect(!session.isPaused)
        #expect(try fixture.savedTranslation() == "일시정지해도 번역을 보존합니다.")
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !condition(), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(5))
        }
        return condition()
    }
}

@MainActor
private final class HyMTStopFixture {
    let suite = "HyMTStopTests.\(UUID().uuidString)"
    let defaults: UserDefaults
    let directory: URL
    let session: TranslationSessionStore
    let translator = HyMTStopTranslator()

    init() throws {
        defaults = try #require(UserDefaults(suiteName: suite))
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        session = TranslationSessionStore(modelAvailabilityProvider: { _, _ in [:] }, settingsDefaults: defaults,
                                          transcriptsDirectoryURL: directory)
        session.sourceLanguage = .english
        session.targetLanguage = .korean
        session.isAppleSourceAutoDetectionEnabled = false
        session.useHyMTMode()
        session.isTranscriptPersistenceEnabled = true
        session.savedTranscriptContentMode = .originalAndTranslation
        session.isDubbingEnabled = false
        session.translationForTesting = { [translator] invocation in try await translator.translate(invocation) }
    }

    func receive(_ text: String, isFinal: Bool, segment: String = "test", start: Double = 0) {
        session.receiveCaptionForTesting(text, metadata: .init(segmentID: segment, revision: 1, isFinal: isFinal,
            audioRange: CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 1_000),
                                   duration: CMTime(seconds: 1, preferredTimescale: 1_000)),
            sourceText: text, emittedAt: Date()))
    }

    func savedOriginal() throws -> String? { try savedText(containing: "original") }
    func savedTranslation() throws -> String? { try savedText(containing: "translation") }
    private func savedText(containing part: String) throws -> String? {
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        guard let file = files.first(where: {
            $0.lastPathComponent.hasSuffix("_\(part).txt") || $0.lastPathComponent.hasSuffix("-\(part).txt")
        }) else { return nil }
        return try String(contentsOf: file, encoding: .utf8)
    }

    func cleanup() {
        session.prepareForTermination()
        translator.cancelAll()
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: directory)
    }
}

@MainActor
private final class HyMTStopTranslator {
    private(set) var count = 0
    private var pending: [Int: CheckedContinuation<String, Error>] = [:]
    func translate(_ invocation: TranslationInvocationForTesting) async throws -> String {
        let index = count
        count += 1
        invocation.progress("또")
        // 취소를 늦게 반영하는 native 의존성도 세대 경계에서 차단되는지 검증한다.
        return try await withCheckedThrowingContinuation { pending[index] = $0 }
    }
    func complete(_ index: Int, text: String) { pending.removeValue(forKey: index)?.resume(returning: text) }
    func fail(_ index: Int) { pending.removeValue(forKey: index)?.resume(throwing: HyMTStopTestError.failed) }
    func cancelAll() {
        let continuations = Array(pending.values)
        pending.removeAll()
        for continuation in continuations { continuation.resume(throwing: CancellationError()) }
    }
}

private enum HyMTStopTestError: LocalizedError {
    case failed
    var errorDescription: String? { "HyMT fixture failure" }
}

@MainActor
private final class HyMTSlowCaptureStop {
    private(set) var didStart = false
    private(set) var didFinish = false
    private var continuation: CheckedContinuation<Void, Never>?
    func stop() async {
        didStart = true
        await withCheckedContinuation { continuation = $0 }
        didFinish = true
    }
    func release() {
        continuation?.resume()
        continuation = nil
    }
}
