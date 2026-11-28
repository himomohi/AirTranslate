import Foundation
import ScreenCaptureKit
import Testing
@testable import AirTranslate

private enum DelayedTranslationPreparationError: LocalizedError {
    case firstGenerationFailed

    var errorDescription: String? {
        "First-generation translation preparation failed."
    }
}

private actor SuspendedTranslationPreparation {
    private var continuations: [CheckedContinuation<Void, Error>?] = []

    func prepare(
        source _: LanguageOption,
        target _: LanguageOption,
        model _: IntelligenceModel
    ) async throws {
        try await withCheckedThrowingContinuation { continuation in
            continuations.append(continuation)
        }
    }

    var pendingCount: Int {
        continuations.compactMap { $0 }.count
    }

    func fail(call index: Int, with error: Error) {
        guard continuations.indices.contains(index),
              let continuation = continuations[index]
        else {
            return
        }
        continuations[index] = nil
        continuation.resume(throwing: error)
    }

    func succeed(call index: Int) {
        guard continuations.indices.contains(index),
              let continuation = continuations[index]
        else {
            return
        }
        continuations[index] = nil
        continuation.resume()
    }
}

@Suite
struct AppleLifecycleP2Tests {
    @Test
    @MainActor
    func screenRecordingRequestIsPersistedAcrossCapturesAndPolicyRecreation() {
        var requestCount = 0
        var requestWasAttempted = false
        let requestAttemptStore = ScreenRecordingRequestAttemptStore(
            hasRequestedAccess: { requestWasAttempted },
            markRequestedAccess: { requestWasAttempted = true }
        )
        let policy = ScreenRecordingAccessPolicy(
            preflightAccess: { false },
            requestAccess: {
                requestCount += 1
                return false
            },
            requestAttemptStore: requestAttemptStore
        )
        let firstCapture = SystemAudioCapture(screenRecordingAccessPolicy: policy)
        let secondCapture = SystemAudioCapture(screenRecordingAccessPolicy: policy)

        #expect(throws: CaptureError.screenRecordingNotGranted) {
            try firstCapture.requestScreenRecordingAccess()
        }
        #expect(throws: CaptureError.screenRecordingNotGranted) {
            try secondCapture.requestScreenRecordingAccess()
        }

        let relaunchedPolicy = ScreenRecordingAccessPolicy(
            preflightAccess: { false },
            requestAccess: {
                requestCount += 1
                return false
            },
            requestAttemptStore: requestAttemptStore
        )
        let relaunchedCapture = SystemAudioCapture(screenRecordingAccessPolicy: relaunchedPolicy)
        #expect(throws: CaptureError.screenRecordingNotGranted) {
            try relaunchedCapture.requestScreenRecordingAccess()
        }

        #expect(requestWasAttempted)
        #expect(requestCount == 1)
    }

    @Test
    @MainActor
    func screenRecordingPreflightApprovalPersistsAttemptAndDoesNotRequestAfterRevocation() throws {
        var requestCount = 0
        var requestWasAttempted = false
        var preflightIsApproved = true
        let requestAttemptStore = ScreenRecordingRequestAttemptStore(
            hasRequestedAccess: { requestWasAttempted },
            markRequestedAccess: { requestWasAttempted = true }
        )
        let policy = ScreenRecordingAccessPolicy(
            preflightAccess: { preflightIsApproved },
            requestAccess: {
                requestCount += 1
                return false
            },
            requestAttemptStore: requestAttemptStore
        )
        let capture = SystemAudioCapture(screenRecordingAccessPolicy: policy)

        try capture.requestScreenRecordingAccess()

        #expect(requestWasAttempted)
        #expect(requestCount == 0)

        preflightIsApproved = false
        let relaunchedPolicy = ScreenRecordingAccessPolicy(
            preflightAccess: { preflightIsApproved },
            requestAccess: {
                requestCount += 1
                return false
            },
            requestAttemptStore: requestAttemptStore
        )
        let relaunchedCapture = SystemAudioCapture(screenRecordingAccessPolicy: relaunchedPolicy)

        #expect(throws: CaptureError.screenRecordingNotGranted) {
            try relaunchedCapture.requestScreenRecordingAccess()
        }
        #expect(requestCount == 0)
    }

    @Test
    func userStoppedIsNormalWhileRealStreamFailureRemainsFatalAcrossRestart() {
        let userStopped = NSError(
            domain: SCStreamErrorDomain,
            code: SCStreamError.Code.userStopped.rawValue
        )
        let systemFailure = NSError(
            domain: SCStreamErrorDomain,
            code: SCStreamError.Code.internalError.rawValue
        )

        #expect(
            SystemAudioCapture.isUserStoppedError(
                SystemAudioCaptureLifecycleOutcome.userStopped
            )
        )
        #expect(!SystemAudioCapture.isFatalStopError(userStopped))
        #expect(SystemAudioCapture.isFatalStopError(systemFailure))

        var lifecycle = PipelineLifecycleState()
        let configuration = makeConfiguration()
        let firstGeneration = lifecycle.beginStart(configuration: configuration)
        #expect(
            lifecycle.markRunning(
                generation: firstGeneration,
                currentConfiguration: configuration
            ) == .valid
        )

        // A user stop does not enter the fatal pipeline-error path. The UI can
        // perform its normal stop and start a fresh capture generation.
        #expect(lifecycle.acceptsSample(generation: firstGeneration))
        lifecycle.stop()
        let secondGeneration = lifecycle.beginStart(configuration: configuration)
        #expect(
            lifecycle.markRunning(
                generation: secondGeneration,
                currentConfiguration: configuration
            ) == .valid
        )
        #expect(lifecycle.acceptsSample(generation: secondGeneration))

        let didFailSecondGeneration = lifecycle.fail(generation: secondGeneration)
        #expect(didFailSecondGeneration)
        #expect(lifecycle.phase == .stopped)
    }

    @Test
    @MainActor
    func macAudioPromptDistinguishesSilentAndAudibleInput() async {
        let suiteName = "MacAudioPromptTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let session = TranslationSessionStore(
            modelAvailabilityProvider: { _, _ in [:] }, settingsDefaults: defaults
        )
        session.audioInputSource = .systemAudio
        #expect(session.waitingForTranscriptMessage == AppText.waitingForTranscript)

        let generation = session.activateLiveCallbackPipelineForTesting().generation
        let capture = session.systemAudioCaptureForTesting
        #expect(session.waitingForTranscriptMessage == AppText.waitingForMacAudio)

        session.systemAudioCapture(capture, didReceiveAudioSampleCount: 8, level: -120, generation: generation)
        #expect(await waitUntil { session.latestAudioLevel == -120 })
        #expect(session.waitingForTranscriptMessage == AppText.waitingForMacAudio)
        #expect(session.statusMessage == AppText.waitingForMacAudio)

        session.systemAudioCapture(capture, didReceiveAudioSampleCount: 16, level: -25, generation: generation)
        #expect(await waitUntil { session.latestAudioLevel == -25 })
        #expect(session.waitingForTranscriptMessage == AppText.receivingMacAudio)
        #expect(session.statusMessage == AppText.receivingMacAudio)

        session.pause()
        #expect(session.waitingForTranscriptMessage == AppText.waitingForTranscript)
        session.stop()
    }

    @Test
    @MainActor
    func audioLevelDeadbandSuppressesSubDecibelJitterWhileAudibleJumpUpdatesImmediately() async {
        let suiteName = "AudioLevelDeadbandTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let session = TranslationSessionStore(
            modelAvailabilityProvider: { _, _ in [:] }, settingsDefaults: defaults
        )
        session.audioInputSource = .systemAudio
        let generation = session.activateLiveCallbackPipelineForTesting().generation
        let capture = session.systemAudioCaptureForTesting

        session.systemAudioCapture(capture, didReceiveAudioSampleCount: 1, level: -60.0, generation: generation)
        #expect(await waitUntil { session.latestAudioLevel == -60.0 })

        session.systemAudioCapture(capture, didReceiveAudioSampleCount: 8, level: -59.5, generation: generation)
        await settleMainActorTasks()
        #expect(session.latestAudioLevel == -60.0)

        session.systemAudioCapture(capture, didReceiveAudioSampleCount: 16, level: -25.0, generation: generation)
        #expect(await waitUntil { session.latestAudioLevel == -25.0 })
        session.stop()
    }

    @Test
    @MainActor
    func externalUserStopSavesUnlocksRestartsAndIgnoresStaleGeneration() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AirTranslateUserStopTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let settingsSuiteName = "AirTranslateUserStopSettings-\(UUID().uuidString)"
        let settingsDefaults = UserDefaults(suiteName: settingsSuiteName)!
        defer { settingsDefaults.removePersistentDomain(forName: settingsSuiteName) }

        let session = TranslationSessionStore(
            modelAvailabilityProvider: { _, _ in [:] },
            settingsDefaults: settingsDefaults,
            transcriptsDirectoryURL: directory
        )
        session.isTranscriptPersistenceEnabled = true
        session.savedTranscriptContentMode = .original
        let capture = session.systemAudioCaptureForTesting
        let firstPipeline = session.activateLiveCallbackPipelineForTesting()
        let firstGeneration = firstPipeline.generation
        session.liveSpeechTranscriber(
            firstPipeline.transcriber,
            didRecognize: "External user stop must save this transcript.",
            language: .english,
            confidence: 0.9
        )
        #expect(await waitUntil {
            session.lines.last?.sourceText == "External user stop must save this transcript."
        })

        #expect(
            SidebarSessionConfigurationAccess.isLocked(
                isRunning: session.isRunning,
                isStarting: session.isStarting
            )
        )

        session.systemAudioCaptureDidStopByUser(
            capture,
            generation: firstGeneration
        )
        await waitForStoppedPipeline(on: session)

        #expect(session.statusMessage == AppText.transcriptSavedToast)
        #expect(await waitUntil {
            savedTranscriptText(in: directory)
                .contains("External user stop must save this transcript.")
        })
        #expect(
            !SidebarSessionConfigurationAccess.isLocked(
                isRunning: session.isRunning,
                isStarting: session.isStarting
            )
        )

        let secondGeneration = session.activateLiveCallbackPipelineForTesting().generation
        #expect(secondGeneration != firstGeneration)
        #expect(session.isRunning)
        #expect(
            SidebarSessionConfigurationAccess.isLocked(
                isRunning: session.isRunning,
                isStarting: session.isStarting
            )
        )

        session.systemAudioCaptureDidStopByUser(
            capture,
            generation: firstGeneration
        )
        await settleMainActorTasks()

        #expect(session.isRunning)
        #expect(
            SidebarSessionConfigurationAccess.isLocked(
                isRunning: session.isRunning,
                isStarting: session.isStarting
            )
        )

        session.systemAudioCaptureDidStopByUser(
            capture,
            generation: secondGeneration
        )
        await waitForStoppedPipeline(on: session)
    }

    @Test
    @MainActor
    func userStoppedThrownDuringInitialCaptureStartIsNormalNotStartFailure() async throws {
        let session = TranslationSessionStore(modelAvailabilityProvider: { _, _ in [:] })
        session.audioInputSource = .systemAudio
        let userStopped = NSError(
            domain: SCStreamErrorDomain,
            code: SCStreamError.Code.userStopped.rawValue
        )

        let generation = try #require(
            await session.simulateSystemAudioStartFailureForTesting(userStopped)
        )

        #expect(generation > 0)
        #expect(!session.isRunning)
        #expect(!session.isStarting)
        #expect(session.statusMessage == AppText.stopped)
        #expect(session.statusMessage != AppText.startFailed(userStopped.localizedDescription))

        let restartedGeneration = session.activateLiveCallbackPipelineForTesting().generation
        #expect(restartedGeneration != generation)
        #expect(session.isRunning)
        session.stop()

        let failedSession = TranslationSessionStore(modelAvailabilityProvider: { _, _ in [:] })
        failedSession.audioInputSource = .systemAudio
        let systemFailure = NSError(
            domain: SCStreamErrorDomain,
            code: SCStreamError.Code.internalError.rawValue
        )
        _ = try #require(
            await failedSession.simulateSystemAudioStartFailureForTesting(systemFailure)
        )
        #expect(!failedSession.isRunning)
        #expect(!failedSession.isStarting)
        #expect(failedSession.statusMessage == AppText.startFailed(systemFailure.localizedDescription))
    }

    @Test
    @MainActor
    func lateWarmupFailureFromStoppedGenerationCannotOverwriteRestartedSessionStatus() async throws {
        let preparation = SuspendedTranslationPreparation()
        let session = TranslationSessionStore(
            modelAvailabilityProvider: { _, _ in [:] },
            translationSessionPreparer: { source, target, model in
                try await preparation.prepare(
                    source: source,
                    target: target,
                    model: model
                )
            }
        )
        session.openAITranslationModel = .off
        session.geminiTranslationModel = .off
        session.selectedModel = .appleSystem

        let firstGeneration = session.activateLiveCallbackPipelineForTesting().generation
        session.warmTranslationSessionForTesting()
        await waitForPendingPreparations(1, on: preparation)

        session.stop()
        let secondGeneration = session.activateLiveCallbackPipelineForTesting().generation
        #expect(secondGeneration != firstGeneration)
        let secondGenerationStatus = "Generation 2 is listening."
        session.statusMessage = secondGenerationStatus
        session.warmTranslationSessionForTesting()
        await waitForPendingPreparations(2, on: preparation)

        await preparation.fail(
            call: 0,
            with: DelayedTranslationPreparationError.firstGenerationFailed
        )
        await settleMainActorTasks()

        #expect(session.isRunning)
        #expect(session.statusMessage == secondGenerationStatus)

        await preparation.succeed(call: 1)
        await settleMainActorTasks()
        #expect(session.statusMessage == secondGenerationStatus)
        session.stop()
    }

    @Test
    @MainActor
    func activeAppleSpeechBackpressureProducesVisibleControlledStop() async {
        let session = TranslationSessionStore(modelAvailabilityProvider: { _, _ in [:] })
        let activePipeline = session.activateLiveCallbackPipelineForTesting()
        let error = LiveSpeechTranscriberError.audioInputBackpressure(bufferLimit: 32)

        session.liveSpeechTranscriber(activePipeline.transcriber, didFail: error)
        await waitForStoppedPipeline(on: session)

        #expect(!session.isRunning)
        #expect(!session.isStarting)
        #expect(session.statusMessage == error.localizedDescription)
    }

    private func makeConfiguration() -> StartConfiguration {
        StartConfiguration(
            audioInputSource: .systemAudio,
            microphoneDeviceUniqueID: nil,
            sourceLanguage: .english,
            targetLanguage: .korean,
            selectedModel: .appleSystem,
            openAITranscriptionModel: .off,
            openAITranslationModel: .off,
            geminiTranslationModel: .off,
            usesAppleSourceAutoDetection: false
        )
    }

    private func waitForPendingPreparations(
        _ expectedCount: Int,
        on preparation: SuspendedTranslationPreparation
    ) async {
        for _ in 0..<200 {
            if await preparation.pendingCount == expectedCount {
                return
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
        let pendingCount = await preparation.pendingCount
        #expect(pendingCount == expectedCount)
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
        timeout: TimeInterval = 0.5,
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

    @MainActor
    private func settleMainActorTasks() async {
        for _ in 0..<5 {
            await Task.yield()
        }
    }

    @MainActor
    private func waitForStoppedPipeline(on session: TranslationSessionStore) async {
        #expect(await waitUntil {
            !session.isRunning && !session.isStarting
        })
    }
}
