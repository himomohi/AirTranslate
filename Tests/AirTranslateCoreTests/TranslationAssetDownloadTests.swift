import Foundation
import Testing
@testable import AirTranslate

@Suite(.serialized)
@MainActor
struct TranslationAssetDownloadTests {
    @Test func presenterReceivesExactPairAndReleasesOnSuccess() async throws {
        let probe = PresentationProbe()
        let downloader = TranslationAssetDownloader(present: probe.present)
        let task = Task { try await downloader.download(source: .english, target: .korean) }
        try await waitFor { probe.requests.count == 1 }
        #expect(probe.requests[0].source == .english)
        #expect(probe.requests[0].target == .korean)
        probe.complete(0, .success(()))
        try await task.value
        #expect(downloader.request == nil)
        #expect(probe.dismissed == [probe.requests[0].id])
    }

    @Test func failureAndSamePairRetryUseFreshRequest() async throws {
        let probe = PresentationProbe()
        let downloader = TranslationAssetDownloader(present: probe.present)
        let first = Task { try await downloader.download(source: .english, target: .korean) }
        try await waitFor { probe.requests.count == 1 }
        probe.complete(0, .failure(DownloadFailure.failed))
        await expectFailure(first)
        let second = Task { try await downloader.download(source: .english, target: .korean) }
        try await waitFor { probe.requests.count == 2 }
        #expect(probe.requests[0].id != probe.requests[1].id)
        probe.complete(0, .success(()))
        #expect(downloader.request?.id == probe.requests[1].id)
        probe.complete(1, .success(()))
        try await second.value
    }

    @Test func cancellationAndLateCompletionCannotFinishRetry() async throws {
        let probe = PresentationProbe()
        let downloader = TranslationAssetDownloader(present: probe.present)
        let first = Task { try await downloader.download(source: .english, target: .korean) }
        try await waitFor { probe.requests.count == 1 }
        first.cancel()
        await expectFailure(first)
        #expect(downloader.request == nil)
        let second = Task { try await downloader.download(source: .korean, target: .english) }
        try await waitFor { probe.requests.count == 2 }
        probe.complete(0, .failure(DownloadFailure.failed))
        #expect(downloader.request?.id == probe.requests[1].id)
        probe.complete(1, .success(()))
        try await second.value
        #expect(probe.dismissed.count == 2)
    }

    @Test func duplicateRequestDoesNotReplaceActivePresentation() async throws {
        let probe = PresentationProbe()
        let downloader = TranslationAssetDownloader(present: probe.present)
        let first = Task { try await downloader.download(source: .english, target: .korean) }
        try await waitFor { probe.requests.count == 1 }
        do {
            try await downloader.download(source: .english, target: .korean)
            Issue.record("Duplicate request should be rejected")
        } catch is CancellationError {} catch { Issue.record("Unexpected error: \(error)") }
        #expect(probe.requests.count == 1)
        downloader.cancel()
        await expectFailure(first)
    }

    @Test func synchronousCompletionStillDismissesPresentation() async throws {
        var dismissed = false
        let downloader = TranslationAssetDownloader { _, completion in
            completion(.success(()))
            return { dismissed = true }
        }
        try await downloader.download(source: .english, target: .korean)
        #expect(dismissed)
        #expect(downloader.request == nil)
    }

    @Test func earlyPreparationReturnWaitsForActualInstallation() async throws {
        var statusChecks = 0
        var waits = 0
        try await TranslationAssetDownloader.waitUntilInstalled(
            source: .english, target: .korean, isCancelled: { false },
            status: { source, target in
                #expect(source == .english && target == .korean)
                statusChecks += 1
                return statusChecks < 3 ? .supported : .installed
            },
            wait: { waits += 1 }
        )
        #expect(statusChecks == 3 && waits == 2)
        try await TranslationAssetDownloader.waitUntilInstalled(
            source: .english, target: .korean, isCancelled: { false },
            status: { _, _ in .installed },
            wait: { Issue.record("Installed assets must not wait") }
        )
    }

    @Test func installationWaitStopsOnWindowOrRequestCancellation() async throws {
        var cancelled = false
        var statusChecks = 0
        do {
            try await TranslationAssetDownloader.waitUntilInstalled(
                source: .english, target: .korean, isCancelled: { cancelled },
                status: { _, _ in statusChecks += 1; return .supported },
                wait: { cancelled = true }
            )
            Issue.record("Cancellation should end the installation wait")
        } catch is CancellationError {} catch { Issue.record("Unexpected error: \(error)") }
        #expect(statusChecks == 1)
    }

    @Test func unsupportedPairDoesNotWaitOrSucceed() async throws {
        do {
            try await TranslationAssetDownloader.waitUntilInstalled(
                source: .english, target: .korean, isCancelled: { false },
                status: { _, _ in .unsupported },
                wait: { Issue.record("Unsupported assets must not wait") }
            )
            Issue.record("Unsupported pair should fail")
        } catch is TranslationServiceError {} catch { Issue.record("Unexpected error: \(error)") }
    }

    @Test func manualDownloadPreservesBusyStateAcrossRefreshAndRejectsDuplicates() async throws {
        let fixture = try DownloadFixture()
        defer { fixture.cleanUp() }
        let session = fixture.session
        try await fixture.ready()
        session.downloadModelAssets(for: .appleOnDevice)
        session.downloadModelAssets(for: .appleOnDevice)
        session.downloadModelAssets(for: .appleSystem)
        session.refreshModelAvailability()
        try await waitFor { fixture.probe.calls.count == 1 }
        #expect(session.modelAvailability(for: .appleOnDevice).state == .downloading)
        #expect(session.modelAvailability(for: .appleSystem).state == .downloading)
        fixture.probe.state = .installed
        fixture.probe.complete(0, .success(()))
        try await waitFor { !session.isDownloadingModelAssets }
        #expect(session.modelAvailability(for: .appleOnDevice).state == .installed)
        #expect(session.modelAvailability(for: .appleSystem).state == .installed)
        #expect(!session.isRunning && !session.isStarting)
    }

    @Test func manualFailureAndUserCancellationAllowRetry() async throws {
        let fixture = try DownloadFixture()
        defer { fixture.cleanUp() }
        let session = fixture.session
        try await fixture.ready()
        session.downloadModelAssets(for: .appleOnDevice)
        try await waitFor { fixture.probe.calls.count == 1 }
        fixture.probe.complete(0, .failure(DownloadFailure.failed))
        try await waitFor { !session.isDownloadingModelAssets }
        #expect(session.modelAvailability(for: .appleOnDevice).state == .failed)
        session.downloadModelAssets(for: .appleOnDevice)
        try await waitFor { fixture.probe.calls.count == 2 }
        fixture.probe.complete(1, .failure(CancellationError()))
        try await waitFor { session.modelAvailability(for: .appleOnDevice).state.canDownload }
        #expect(!session.isDownloadingModelAssets)
        session.downloadModelAssets(for: .appleOnDevice)
        try await waitFor { fixture.probe.calls.count == 3 }
        fixture.probe.state = .installed
        fixture.probe.complete(2, .success(()))
        try await waitFor { !session.isDownloadingModelAssets }
        #expect(session.modelAvailability(for: .appleOnDevice).state == .installed)
    }

    @Test func languageChangeRejectsLateFailureWhileNewPairDownloads() async throws {
        let fixture = try DownloadFixture()
        defer { fixture.cleanUp() }
        let session = fixture.session
        try await fixture.ready()
        session.downloadModelAssets(for: .appleOnDevice)
        try await waitFor { fixture.probe.calls.count == 1 }
        session.targetLanguage = LanguageOption.supported[2]
        try await waitFor { session.modelAvailability(for: .appleOnDevice).state.canDownload }
        session.downloadModelAssets(for: .appleOnDevice)
        try await waitFor { fixture.probe.calls.count == 2 }
        fixture.probe.complete(0, .failure(DownloadFailure.failed))
        await drainTasks()
        #expect(session.isDownloadingModelAssets)
        #expect(session.modelAvailability(for: .appleOnDevice).state == .downloading)
        #expect(fixture.probe.calls[1].target == LanguageOption.supported[2])
        fixture.probe.state = .installed
        fixture.probe.complete(1, .success(()))
        try await waitFor { !session.isDownloadingModelAssets }
        #expect(session.modelAvailability(for: .appleOnDevice).state == .installed)
    }

    @Test func stoppedAutomaticDownloadCannotFailOrStartNewAttempt() async throws {
        let fixture = try DownloadFixture()
        defer { fixture.cleanUp() }
        let session = fixture.session
        try await fixture.ready()
        session.start()
        try await waitFor { fixture.probe.calls.count == 1 }
        #expect(session.isStarting)
        session.stop()
        try await waitFor { session.modelAvailability(for: .appleSystem).state.canDownload }
        session.start()
        try await waitFor { fixture.probe.calls.count == 2 }
        fixture.probe.complete(0, .failure(DownloadFailure.failed))
        await drainTasks()
        #expect(session.isStarting)
        #expect(session.captureStartFailureMessage == nil)
        #expect(session.isDownloadingModelAssets)
        session.stop()
        fixture.probe.complete(1, .success(()))
        await drainTasks()
        #expect(!session.isStarting && !session.isRunning)
    }

    @Test func readinessChangedAfterPreparationDoesNotStartCapture() async throws {
        let fixture = try DownloadFixture()
        defer { fixture.cleanUp() }
        try await fixture.ready()
        fixture.session.start()
        try await waitFor { fixture.probe.calls.count == 1 }
        fixture.probe.complete(0, .success(()))
        try await waitFor { !fixture.session.isDownloadingModelAssets }
        #expect(!fixture.session.isRunning && !fixture.session.isStarting)
        #expect(fixture.session.modelAvailability(for: .appleSystem).state == .downloadRequired)
        #expect(fixture.session.captureStartFailureMessage != nil)
    }

    @Test func configurationChangeAndTerminationCancelPendingDownload() async throws {
        let fixture = try DownloadFixture()
        defer { fixture.cleanUp() }
        try await fixture.ready()
        fixture.session.start()
        try await waitFor { fixture.probe.calls.count == 1 }
        fixture.session.audioInputSource = .microphone
        #expect(!fixture.session.isDownloadingModelAssets)
        #expect(!fixture.session.isStarting)
        fixture.probe.complete(0, .success(()))
        try await waitFor { fixture.session.modelAvailability(for: .appleOnDevice).state.canDownload }
        fixture.session.downloadModelAssets(for: .appleOnDevice)
        try await waitFor { fixture.probe.calls.count == 2 }
        fixture.session.prepareForTermination()
        fixture.probe.complete(1, .failure(DownloadFailure.failed))
        await drainTasks()
        #expect(!fixture.session.isDownloadingModelAssets)
        #expect(!fixture.session.isRunning && !fixture.session.isStarting)
        #expect(fixture.session.captureStartFailureMessage == nil)
    }

    @Test func speechOnlyRequestRetainsItsExistingDownloaderRoute() async throws {
        let fixture = try DownloadFixture()
        defer { fixture.cleanUp() }
        try await fixture.ready()
        fixture.session.downloadModelAssets(for: .appleSpeechOnly)
        try await waitFor { fixture.probe.calls.count == 1 }
        #expect(fixture.probe.calls[0].model == .appleSpeechOnly)
        #expect(fixture.session.modelAvailability(for: .appleOnDevice).state == .downloadRequired)
        fixture.probe.state = .installed
        fixture.probe.complete(0, .success(()))
        try await waitFor { !fixture.session.isDownloadingModelAssets }
    }

    private func expectFailure(_ task: Task<Void, Error>) async {
        do { try await task.value; Issue.record("Expected failure") } catch {}
    }
}

private enum DownloadFailure: Error { case failed }

@MainActor
private final class PresentationProbe {
    var requests: [TranslationAssetDownloader.Request] = []
    var completions: [TranslationAssetDownloader.Completion] = []
    var dismissed: [UUID] = []

    func present(_ request: TranslationAssetDownloader.Request, completion: @escaping TranslationAssetDownloader.Completion) -> TranslationAssetDownloader.Dismiss {
        requests.append(request)
        completions.append(completion)
        return { self.dismissed.append(request.id) }
    }

    func complete(_ index: Int, _ result: Result<Void, Error>) { completions[index](result) }
}

@MainActor
private final class AssetDownloadProbe {
    struct Call {
        let model: IntelligenceModel
        let source: LanguageOption
        let target: LanguageOption
    }
    var calls: [Call] = []
    var continuations: [Int: CheckedContinuation<Void, Error>] = [:]
    var state = ModelAvailabilityState.downloadRequired

    func download(_ model: IntelligenceModel, _ source: LanguageOption, _ target: LanguageOption) async throws {
        try await withCheckedThrowingContinuation { continuation in
            let index = calls.count
            calls.append(Call(model: model, source: source, target: target))
            continuations[index] = continuation
        }
    }

    func complete(_ index: Int, _ result: Result<Void, Error>) {
        continuations.removeValue(forKey: index)?.resume(with: result)
    }

    func availability() -> [String: ModelAvailability] {
        Dictionary(uniqueKeysWithValues: [IntelligenceModel.appleSystem, .appleOnDevice, .appleSpeechOnly].map {
            ($0.id, ModelAvailability(state: state, detail: "test"))
        })
    }
}

@MainActor
private final class DownloadFixture {
    let probe = AssetDownloadProbe()
    let session: TranslationSessionStore
    let defaults: UserDefaults
    let suite = "TranslationAssetDownloadTests.\(UUID().uuidString)"
    let directory: URL

    init() throws {
        defaults = try #require(UserDefaults(suiteName: suite))
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        session = TranslationSessionStore(
            modelAvailabilityProvider: { [probe] _, _ in probe.availability() },
            modelAssetDownloader: { [probe] model, source, target in try await probe.download(model, source, target) },
            settingsDefaults: defaults, transcriptsDirectoryURL: directory
        )
        session.sourceLanguage = .english
        session.targetLanguage = .korean
    }

    func ready() async throws {
        try await waitFor { session.modelAvailability(for: .appleSystem).state == .downloadRequired }
    }

    func cleanUp() {
        session.prepareForTermination()
        for index in Array(probe.continuations.keys) { probe.complete(index, .failure(CancellationError())) }
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: directory)
    }
}

@MainActor
private func waitFor(_ predicate: () -> Bool) async throws {
    let deadline = ContinuousClock.now + .seconds(3)
    while !predicate(), ContinuousClock.now < deadline { try? await Task.sleep(for: .milliseconds(2)) }
    try #require(predicate())
}

@MainActor
private func drainTasks() async {
    for _ in 0..<20 { await Task.yield() }
}
