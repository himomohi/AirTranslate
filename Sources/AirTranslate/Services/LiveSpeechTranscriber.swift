import AVFoundation
import CoreMedia
import Speech

enum LiveSpeechTranscriberError: LocalizedError, Equatable, Sendable {
    case audioInputBackpressure(bufferLimit: Int)
    case audioInputConversionFailed

    var errorDescription: String? {
        switch self {
        case .audioInputBackpressure:
            "Apple Speech stopped because audio arrived faster than it could be transcribed. Restart transcription to continue."
        case .audioInputConversionFailed:
            AppText.localized(
                english: "Apple Speech stopped because the audio format could not be converted. Restart transcription to continue.",
                korean: "오디오 형식을 변환할 수 없어 Apple 전사를 중지했습니다. 전사를 다시 시작해 주세요."
            )
        }
    }
}

enum SpeechAnalyzerInputYieldDisposition: Equatable, Sendable {
    case enqueued
    case dropped
    case terminated
}

final class SpeechAnalyzerInputQueue<Element: Sendable>: @unchecked Sendable {
    let stream: AsyncStream<Element>

    private let continuation: AsyncStream<Element>.Continuation
    private let bufferLimit: Int
    private let onBackpressure: @Sendable (Int) -> Void
    private let lock = NSLock()
    private var isFinished = false
    private var didReportBackpressure = false

    init(
        bufferLimit: Int,
        onBackpressure: @escaping @Sendable (Int) -> Void
    ) {
        precondition(bufferLimit > 0)

        var capturedContinuation: AsyncStream<Element>.Continuation?
        stream = AsyncStream(
            bufferingPolicy: .bufferingNewest(bufferLimit)
        ) { continuation in
            capturedContinuation = continuation
        }
        continuation = capturedContinuation!
        self.bufferLimit = bufferLimit
        self.onBackpressure = onBackpressure
    }

    @discardableResult
    func yield(_ element: Element) -> SpeechAnalyzerInputYieldDisposition {
        lock.lock()
        let canYield = !isFinished
        lock.unlock()
        guard canYield else { return .terminated }

        switch continuation.yield(element) {
        case .enqueued:
            return .enqueued
        case .dropped:
            lock.lock()
            let shouldReport = !isFinished && !didReportBackpressure
            if shouldReport {
                isFinished = true
                didReportBackpressure = true
            }
            lock.unlock()

            if shouldReport {
                // Once any chunk is evicted, transcript completeness can no
                // longer be guaranteed. End the input before reporting the
                // fatal degradation so the owner can stop the pipeline.
                continuation.finish()
                onBackpressure(bufferLimit)
            }
            return .dropped
        case .terminated:
            lock.lock()
            isFinished = true
            lock.unlock()
            return .terminated
        @unknown default:
            lock.lock()
            isFinished = true
            lock.unlock()
            continuation.finish()
            return .terminated
        }
    }

    func finish() {
        lock.lock()
        let shouldFinish = !isFinished
        isFinished = true
        lock.unlock()

        if shouldFinish {
            continuation.finish()
        }
    }
}

protocol LiveSpeechTranscriberDelegate: AnyObject {
    func liveSpeechTranscriber(
        _ transcriber: LiveSpeechTranscriber,
        didRecognize text: String,
        language: LanguageOption,
        confidence: Double
    )
    func liveSpeechTranscriber(
        _ transcriber: LiveSpeechTranscriber,
        didRecognize text: String,
        language: LanguageOption,
        confidence: Double,
        metadata: AppleSpeechRecognitionMetadata
    )
    func liveSpeechTranscriber(
        _ transcriber: LiveSpeechTranscriber,
        didTranslate text: String,
        language: LanguageOption,
        confidence: Double
    )
    func liveSpeechTranscriber(
        _ transcriber: LiveSpeechTranscriber,
        didRecognizeSourceTranscript text: String,
        confidence: Double
    )
    func liveSpeechTranscriber(
        _ transcriber: LiveSpeechTranscriber,
        didOutputAudioPCM16Base64 audio: String,
        sampleRate: Double
    )
    func liveSpeechTranscriber(_ transcriber: LiveSpeechTranscriber, didFail error: Error)
}

extension LiveSpeechTranscriberDelegate {
    func liveSpeechTranscriber(
        _ transcriber: LiveSpeechTranscriber,
        didRecognize text: String,
        language: LanguageOption,
        confidence: Double,
        metadata _: AppleSpeechRecognitionMetadata
    ) {
        liveSpeechTranscriber(
            transcriber,
            didRecognize: text,
            language: language,
            confidence: confidence
        )
    }

    func liveSpeechTranscriber(
        _ transcriber: LiveSpeechTranscriber,
        didTranslate text: String,
        language: LanguageOption,
        confidence: Double
    ) {}

    func liveSpeechTranscriber(
        _ transcriber: LiveSpeechTranscriber,
        didRecognizeSourceTranscript text: String,
        confidence: Double
    ) {}

    func liveSpeechTranscriber(
        _ transcriber: LiveSpeechTranscriber,
        didOutputAudioPCM16Base64 audio: String,
        sampleRate: Double
    ) {}
}

struct SpeechAssetReservation: Sendable {
    fileprivate let id: UInt64
    let locale: Locale
}

private final class SpeechAssetAsyncMutex: @unchecked Sendable {
    // This intentionally stays non-reentrant across the caller's awaits.
    // An actor method would permit another reserve/release operation to enter
    // while AssetInventory is suspended.
    private let stateLock = NSLock()
    private var isAcquired = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    // Cancellation does not remove a queued waiter: it still acquires the
    // mutex, so callers must check cancellation after acquisition and release.
    func acquire() async {
        await withCheckedContinuation { continuation in
            let shouldResumeImmediately = stateLock.withLock {
                guard !isAcquired else {
                    waiters.append(continuation)
                    return false
                }
                isAcquired = true
                return true
            }
            if shouldResumeImmediately {
                continuation.resume()
            }
        }
    }

    func release() {
        let nextWaiter: CheckedContinuation<Void, Never>? = stateLock.withLock {
            guard !waiters.isEmpty else {
                isAcquired = false
                return nil
            }
            return waiters.removeFirst()
        }
        nextWaiter?.resume()
    }
}

private final class LifecycleOneShotGate: @unchecked Sendable {
    private let lock = NSLock()
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var isOpen = false

    func wait() async {
        await withCheckedContinuation { continuation in
            let shouldResumeImmediately = lock.withLock {
                guard !isOpen else { return true }
                waiters.append(continuation)
                return false
            }
            if shouldResumeImmediately {
                continuation.resume()
            }
        }
    }

    func open() {
        let waiters: [CheckedContinuation<Void, Never>] = lock.withLock {
            guard !isOpen else { return [] }
            isOpen = true
            defer { self.waiters = [] }
            return self.waiters
        }
        waiters.forEach { $0.resume() }
    }
}

final class SpeechAssetReservationCoordinator: @unchecked Sendable {
    typealias ReserveLocale = @Sendable (Locale) async throws -> Bool
    typealias ReleaseLocale = @Sendable (Locale) async -> Bool

    static let shared = SpeechAssetReservationCoordinator()

    private struct LocaleOwners {
        let locale: Locale
        var reservationIDs: Set<UInt64>
    }

    private let mutex = SpeechAssetAsyncMutex()
    private let reserveLocale: ReserveLocale
    private let releaseLocale: ReleaseLocale
    private var nextReservationID: UInt64 = 0
    private var ownersByLocaleIdentifier: [String: LocaleOwners] = [:]

    init(
        reserveLocale: @escaping ReserveLocale = {
            try await AssetInventory.reserve(locale: $0)
        },
        releaseLocale: @escaping ReleaseLocale = {
            await AssetInventory.release(reservedLocale: $0)
        }
    ) {
        self.reserveLocale = reserveLocale
        self.releaseLocale = releaseLocale
    }

    func reserve(
        locale: Locale,
        claim: @escaping @Sendable (SpeechAssetReservation) -> Bool
    ) async throws -> SpeechAssetReservation {
        await mutex.acquire()
        defer { mutex.release() }

        try Task.checkCancellation()
        let localeIdentifier = locale.identifier
        let needsSystemReservation = ownersByLocaleIdentifier[localeIdentifier] == nil
        if needsSystemReservation {
            // A false result means the app already owns this global locale
            // reservation. The coordinator still adopts it and releases it
            // when its final logical owner exits.
            _ = try await reserveLocale(locale)
            do {
                try Task.checkCancellation()
            } catch {
                _ = await releaseLocale(locale)
                throw error
            }
        }

        nextReservationID &+= 1
        let reservation = SpeechAssetReservation(
            id: nextReservationID,
            locale: locale
        )
        // `claim` runs while the mutex is held, after the serialized asset
        // reservation await. It must not recursively reserve/release or await
        // work that requires this coordinator.
        guard claim(reservation) else {
            if needsSystemReservation {
                _ = await releaseLocale(locale)
            }
            throw CancellationError()
        }

        if var owners = ownersByLocaleIdentifier[localeIdentifier] {
            owners.reservationIDs.insert(reservation.id)
            ownersByLocaleIdentifier[localeIdentifier] = owners
        } else {
            ownersByLocaleIdentifier[localeIdentifier] = LocaleOwners(
                locale: locale,
                reservationIDs: [reservation.id]
            )
        }
        return reservation
    }

    func release(_ reservation: SpeechAssetReservation) async {
        await mutex.acquire()
        defer { mutex.release() }

        let localeIdentifier = reservation.locale.identifier
        guard var owners = ownersByLocaleIdentifier[localeIdentifier],
              owners.reservationIDs.remove(reservation.id) != nil
        else {
            return
        }
        guard owners.reservationIDs.isEmpty else {
            ownersByLocaleIdentifier[localeIdentifier] = owners
            return
        }

        ownersByLocaleIdentifier[localeIdentifier] = nil
        _ = await releaseLocale(owners.locale)
    }
}

final class LiveSpeechTranscriber: @unchecked Sendable {
    private struct LifecycleResources {
        let inputQueue: SpeechAnalyzerInputQueue<AnalyzerInput>?
        let inputAdapter: (any SpeechAnalyzerInputAdapting)?
        let analyzer: SpeechAnalyzer?
        let analyzeTask: Task<Void, Never>?
        let resultTasks: [Task<Void, Never>]
        let assetReservations: [SpeechAssetReservation]
    }

    private struct LifecycleTransition {
        let generation: UInt64
        let cleanupTask: Task<Void, Never>
    }

    private struct LifecycleTransitionPlan {
        let transition: LifecycleTransition
        let resources: LifecycleResources
        let producerTeardownGate: LifecycleOneShotGate
    }

    weak var delegate: LiveSpeechTranscriberDelegate?

    private static let reusablePCMBufferCount = 48
    private static let analyzerInputBufferLimit = 32

    private let audioFormat = AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: 16_000,
        channels: 1,
        interleaved: false
    )!
    private var analyzer: SpeechAnalyzer?
    private var inputQueue: SpeechAnalyzerInputQueue<AnalyzerInput>?
    private var inputAdapter: (any SpeechAnalyzerInputAdapting)?
    private var analyzeTask: Task<Void, Never>?
    private var resultTasks: [Task<Void, Never>] = []
    private var assetReservations: [SpeechAssetReservation] = []
    private let stateLock = NSLock()
    private let conversionLock = NSLock()
    private let authorizationRequester: @Sendable () async -> Bool
    private let assetReservationCoordinator: SpeechAssetReservationCoordinator
#if DEBUG
    private var cleanupCompletionHookForTesting: (@Sendable () async -> Void)?
    private var postRunningTaskPublicationHookForTesting: (@Sendable () -> Void)?
#endif
    private var lifecycleGeneration: UInt64 = 0
    private var cleanupTask: Task<Void, Never>?
    private var isPaused = false
    private var reusablePCMBuffers = [AVAudioPCMBuffer?](
        repeating: nil,
        count: reusablePCMBufferCount
    )
    private var reusablePCMBufferCursor = 0

    init(
        authorizationRequester: @escaping @Sendable () async -> Bool = {
            await LiveSpeechTranscriber.requestAuthorization()
        },
        assetReservationCoordinator: SpeechAssetReservationCoordinator = .shared
    ) {
        self.authorizationRequester = authorizationRequester
        self.assetReservationCoordinator = assetReservationCoordinator
    }

    static func installedSupportedLanguages(from languages: [LanguageOption]) async -> [LanguageOption] {
        guard SpeechTranscriber.isAvailable else { return [] }

        let maximumLanguageCount = max(1, AssetInventory.maximumReservedLocales)
        var installedLanguages: [LanguageOption] = []
        for language in languages {
            guard installedLanguages.count < maximumLanguageCount else { break }
            guard let supportedLocale = await SpeechTranscriber.supportedLocale(equivalentTo: language.locale) else {
                continue
            }

            let transcriber = SpeechTranscriber(locale: supportedLocale, preset: .progressiveTranscription)
            switch await AssetInventory.status(forModules: [transcriber]) {
            case .installed:
                installedLanguages.append(language)
            case .downloading, .supported, .unsupported:
                continue
            @unknown default:
                continue
            }
        }

        return installedLanguages
    }

    func start(languages: [LanguageOption], includesAlternatives: Bool = false) async throws {
        let lifecycleTransition = takeLifecycleTransition()
        let lifecycleGeneration = lifecycleTransition.generation
        await lifecycleTransition.cleanupTask.value

        do {
            try await withTaskCancellationHandler {
                try Task.checkCancellation()
                let authorized = await authorizationRequester()
            // SFSpeechRecognizer's completion handler can resume after its
            // surrounding task was cancelled. Check before reserving locales
            // or constructing an analyzer so that stale starts stay local.
            try Task.checkCancellation()
            guard authorized else { throw SpeechError.notAuthorized }
            try ensureLifecycleIsCurrent(lifecycleGeneration)

            var seenLanguageIDs = Set<String>()
            let uniqueLanguages = languages.filter { language in
                seenLanguageIDs.insert(language.id).inserted
            }
            var transcribers: [(language: LanguageOption, transcriber: SpeechTranscriber)] = []
            for language in uniqueLanguages {
                try Task.checkCancellation()
                guard let supportedLocale = await SpeechTranscriber.supportedLocale(equivalentTo: language.locale) else {
                    throw SpeechError.recognizerUnavailable
                }
                try Task.checkCancellation()

                _ = try await assetReservationCoordinator.reserve(
                    locale: supportedLocale
                ) { [weak self] reservation in
                    guard let self else { return false }
                    return claimAssetReservation(
                        reservation,
                        lifecycleGeneration: lifecycleGeneration
                    )
                }
                try Task.checkCancellation()
                transcribers.append((
                    language: language,
                    transcriber: SpeechTranscriber(
                        locale: supportedLocale,
                        transcriptionOptions: [],
                        // 문맥 창을 줄이는 fastResults 대신 기본 정확도를 유지하고 중간 결과만 받는다.
                        reportingOptions: includesAlternatives
                            ? [.volatileResults, .alternativeTranscriptions] : [.volatileResults],
                        attributeOptions: [.transcriptionConfidence]
                    )
                ))
            }
            let modules: [any SpeechModule] = transcribers.map(\.transcriber)
            let inputQueue: SpeechAnalyzerInputQueue<AnalyzerInput> = makeInputQueue(
                bufferLimit: Self.analyzerInputBufferLimit,
                lifecycleGeneration: lifecycleGeneration
            )
            let inputAdapter: (any SpeechAnalyzerInputAdapting)?
            if #available(macOS 27.0, *) {
                inputAdapter = AppleSpeechInputAdapter(analyzerFormat: audioFormat)
            } else {
                inputAdapter = nil
            }
            let analyzer = SpeechAnalyzer(
                modules: modules,
                options: SpeechAnalyzer.Options(
                    priority: .userInitiated,
                    modelRetention: .processLifetime
                )
            )
            let didPublishPreparationResources = stateLock.withLock {
                guard self.lifecycleGeneration == lifecycleGeneration else {
                    return false
                }
                self.inputQueue = inputQueue
                self.inputAdapter = inputAdapter
                self.analyzer = analyzer
                return true
            }
            guard didPublishPreparationResources else {
                // This analyzer never entered lifecycle ownership, so this
                // start remains responsible for its local teardown. Any asset
                // reservations were claimed separately and are owned by the
                // lifecycle transition that invalidated this generation.
                inputQueue.finish()
                await analyzer.cancelAndFinishNow()
                throw CancellationError()
            }

            try Task.checkCancellation()
            try await analyzer.prepareToAnalyze(in: audioFormat)
            try ensureLifecycleIsCurrent(lifecycleGeneration)
            try Task.checkCancellation()

            let didPublishRunningTasks = publishRunningTasks(
                lifecycleGeneration: lifecycleGeneration
            ) { producerStartGate in
                let analyzeTask = Task { [weak self] in
                    await producerStartGate.wait()
                    guard !Task.isCancelled else { return }
                    do {
                        try await analyzer.start(inputSequence: inputQueue.stream)
                    } catch {
                        guard let self else { return }
                        self.delegate?.liveSpeechTranscriber(self, didFail: error)
                    }
                }

                let resultTasks = transcribers.map { entry in
                    Task { [weak self] in
                        var metadataBuilder = AppleSpeechRecognitionMetadataBuilder()
                        var previousConfidence = 0.0
                        await producerStartGate.wait()
                        guard !Task.isCancelled else { return }
                        do {
                            for try await result in entry.transcriber.results {
                                let text = String(result.text.characters)
                                    .trimmingCharacters(in: .whitespacesAndNewlines)
                                guard !text.isEmpty else { continue }
                                if PipelineDiagnostics.isEnabled {
                                    PipelineDiagnostics.record("speech.result", values: [
                                        "characters": Double(text.count),
                                        "final": result.isFinal ? 1 : 0,
                                        "audio_start": result.range.start.seconds,
                                        "audio_end": result.range.end.seconds
                                    ])
                                }
                                guard let self else { return }
                                let emittedAt = Date()
                                let emittedAtUptime = ProcessInfo.processInfo.systemUptime
                                if let previous = metadataBuilder.finalizedPreviousResult(
                                    before: result.range,
                                    finalizedThrough: result.resultsFinalizationTime,
                                    language: entry.language,
                                    emittedAt: emittedAt,
                                    emittedAtUptime: emittedAtUptime
                                ) {
                                    self.delegate?.liveSpeechTranscriber(
                                        self,
                                        didRecognize: previous.text,
                                        language: entry.language,
                                        confidence: previousConfidence,
                                        metadata: previous.metadata
                                    )
                                }
                                let metadata = metadataBuilder.metadata(
                                    sourceText: text,
                                    alternatives: includesAlternatives
                                        ? result.alternatives.prefix(3).map { String($0.characters).trimmingCharacters(in: .whitespacesAndNewlines) } : [],
                                    language: entry.language,
                                    isFinal: result.isFinal,
                                    audioRange: result.range,
                                    emittedAt: emittedAt,
                                    emittedAtUptime: emittedAtUptime
                                )
                                previousConfidence = Self.averageConfidence(in: result.text)
                                self.delegate?.liveSpeechTranscriber(
                                    self,
                                    didRecognize: text,
                                    language: entry.language,
                                    confidence: previousConfidence,
                                    metadata: metadata
                                )
                            }
                        } catch {
                            guard let self else { return }
                            self.delegate?.liveSpeechTranscriber(self, didFail: error)
                        }
                    }
                }
                return (analyzeTask, resultTasks)
            }
            guard didPublishRunningTasks else {
                // A newer lifecycle transition already owns inputQueue,
                // analyzer, and asset reservations. The producer factory was
                // not invoked, so there are no local tasks to cancel and no
                // analyzer cleanup to duplicate.
                throw CancellationError()
            }
            try Task.checkCancellation()
            try ensureLifecycleIsCurrent(lifecycleGeneration)
            } onCancel: {
                // A local candidate may never be published to
                // TranslationSessionStore. Invalidate its generation as soon
                // as its owning task is cancelled so an in-flight global
                // reservation transaction cannot claim stale ownership.
                _ = self.stop(lifecycleGeneration: lifecycleGeneration)
            }
        } catch {
            // This instance may be a stale candidate which was never promoted
            // to TranslationSessionStore. Its cleanup must not rely on the
            // store's currently active generation.
            if let cleanupTask = stop(lifecycleGeneration: lifecycleGeneration) {
                await cleanupTask.value
            }
            throw error
        }
    }

    private func claimAssetReservation(
        _ reservation: SpeechAssetReservation,
        lifecycleGeneration: UInt64
    ) -> Bool {
        stateLock.withLock {
            guard self.lifecycleGeneration == lifecycleGeneration else {
                return false
            }
            assetReservations.append(reservation)
            return true
        }
    }

    private func publishRunningTasks(
        lifecycleGeneration: UInt64,
        makeTasks: (LifecycleOneShotGate) -> (
            analyzeTask: Task<Void, Never>,
            resultTasks: [Task<Void, Never>]
        )
    ) -> Bool {
        let producerStartGate = LifecycleOneShotGate()
#if DEBUG
        var postPublicationHook: (@Sendable () -> Void)?
#endif
        let didPublish = stateLock.withLock {
            guard self.lifecycleGeneration == lifecycleGeneration else {
                return false
            }

            // Task construction and lifecycle ownership are one critical
            // section. A competing stop either prevents construction or
            // snapshots every newly created producer.
            let tasks = makeTasks(producerStartGate)
            analyzeTask = tasks.analyzeTask
            resultTasks = tasks.resultTasks
#if DEBUG
            postPublicationHook = postRunningTaskPublicationHookForTesting
#endif
            return true
        }
#if DEBUG
        postPublicationHook?()
#endif
        producerStartGate.open()
        return didPublish
    }

    func append(_ sampleBuffer: CMSampleBuffer) {
        stateLock.lock()
        let isPaused = isPaused
        let inputQueue = inputQueue
        let inputAdapter = inputAdapter
        let generation = lifecycleGeneration
        stateLock.unlock()

        guard !isPaused, let inputQueue else { return }

        if let inputAdapter {
            do {
                let inputs = try inputAdapter.convert(sampleBuffer) { [self] sampleBuffer in
                    conversionLock.withLock { pcmBuffer(from: sampleBuffer) }
                }
                guard acceptsAudioInput(inputQueue, generation: generation) else { return }
                for input in inputs {
                    if #available(macOS 27.0, *), PipelineDiagnostics.isEnabled {
                        PipelineDiagnostics.record("speech.audio", values: [
                            "duration": input.bufferDuration.seconds,
                            "capture_time": CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
                        ])
                    }
                    guard inputQueue.yield(input) == .enqueued else { break }
                }
            } catch {
                guard acceptsAudioInput(inputQueue, generation: generation) else { return }
                delegate?.liveSpeechTranscriber(self, didFail: LiveSpeechTranscriberError.audioInputConversionFailed)
            }
            return
        }

        conversionLock.lock()
        let pcmBuffer = pcmBuffer(from: sampleBuffer)
        conversionLock.unlock()

        guard let pcmBuffer, acceptsAudioInput(inputQueue, generation: generation) else {
            return
        }

        if PipelineDiagnostics.isEnabled {
            PipelineDiagnostics.record("speech.audio", values: [
                "duration": Double(pcmBuffer.frameLength) / pcmBuffer.format.sampleRate,
                "capture_time": CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
            ])
        }
        inputQueue.yield(AnalyzerInput(buffer: pcmBuffer))
    }

    private func acceptsAudioInput(_ queue: SpeechAnalyzerInputQueue<AnalyzerInput>, generation: UInt64) -> Bool {
        stateLock.withLock {
            lifecycleGeneration == generation && inputQueue === queue && !isPaused
        }
    }

    func setPaused(_ isPaused: Bool) {
        stateLock.lock()
        self.isPaused = isPaused
        stateLock.unlock()
    }

    func stop() {
        _ = takeLifecycleTransition()
    }

    func stopAndWaitForCleanup() async {
        let lifecycleTransition = takeLifecycleTransition()
        await lifecycleTransition.cleanupTask.value
    }

    private func stop(lifecycleGeneration: UInt64) -> Task<Void, Never>? {
        guard let lifecycleTransition = takeLifecycleTransition(
            expectedGeneration: lifecycleGeneration
        ) else {
            return nil
        }
        return lifecycleTransition.cleanupTask
    }

    private func takeLifecycleTransition() -> LifecycleTransition {
        transitionLifecycle(expectedGeneration: nil)!
    }

    private func takeLifecycleTransition(
        expectedGeneration: UInt64
    ) -> LifecycleTransition? {
        transitionLifecycle(expectedGeneration: expectedGeneration)
    }

    private func transitionLifecycle(
        expectedGeneration: UInt64?
    ) -> LifecycleTransition? {
        let plan: LifecycleTransitionPlan? = stateLock.withLock {
            if let expectedGeneration,
               lifecycleGeneration != expectedGeneration {
                return nil
            }

            lifecycleGeneration &+= 1
            isPaused = false
            let resources = LifecycleResources(
                inputQueue: inputQueue,
                inputAdapter: inputAdapter,
                analyzer: analyzer,
                analyzeTask: analyzeTask,
                resultTasks: resultTasks,
                assetReservations: assetReservations
            )
            inputQueue = nil
            inputAdapter = nil
            analyzer = nil
            analyzeTask = nil
            resultTasks = []
            assetReservations = []

            let previousCleanupTask = cleanupTask
            let analyzer = resources.analyzer
            let assetReservations = resources.assetReservations
            let producerTeardownGate = LifecycleOneShotGate()
#if DEBUG
            let cleanupCompletionHookForTesting = cleanupCompletionHookForTesting
#endif
            let assetReservationCoordinator = assetReservationCoordinator
            let cleanupTask = Task {
                await producerTeardownGate.wait()
                await previousCleanupTask?.value
                if let analyzer {
                    await analyzer.cancelAndFinishNow()
                }
                for reservation in assetReservations {
                    await assetReservationCoordinator.release(reservation)
                }
#if DEBUG
                await cleanupCompletionHookForTesting?()
#endif
            }
            self.cleanupTask = cleanupTask
            return LifecycleTransitionPlan(
                transition: LifecycleTransition(
                    generation: lifecycleGeneration,
                    cleanupTask: cleanupTask
                ),
                resources: resources,
                producerTeardownGate: producerTeardownGate
            )
        }
        guard let plan else { return nil }

        // The cleanup tail is already published, so a competing start must
        // wait for it. Stop synchronous producers only after releasing
        // stateLock because finish/cancel may invoke callbacks inline.
        if let tail = try? plan.resources.inputAdapter?.finish() {
            for input in tail {
                guard plan.resources.inputQueue?.yield(input) == .enqueued else { break }
            }
        }
        plan.resources.inputQueue?.finish()
        plan.resources.analyzeTask?.cancel()
        plan.resources.resultTasks.forEach { $0.cancel() }
        plan.producerTeardownGate.open()

        resetReusablePCMBuffers()
        return plan.transition
    }

    private func ensureLifecycleIsCurrent(_ expectedGeneration: UInt64) throws {
        guard stateLock.withLock({
            lifecycleGeneration == expectedGeneration
        }) else {
            throw CancellationError()
        }
    }

    private static func requestAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    private func makeInputQueue<Element: Sendable>(
        bufferLimit: Int,
        lifecycleGeneration: UInt64? = nil
    ) -> SpeechAnalyzerInputQueue<Element> {
        SpeechAnalyzerInputQueue(bufferLimit: bufferLimit) { [weak self] bufferLimit in
            guard let self else { return }
            if let lifecycleGeneration,
               !stateLock.withLock({ self.lifecycleGeneration == lifecycleGeneration }) { return }
            delegate?.liveSpeechTranscriber(
                self,
                didFail: LiveSpeechTranscriberError.audioInputBackpressure(
                    bufferLimit: bufferLimit
                )
            )
        }
    }

#if DEBUG
    var hasActiveResourcesForTesting: Bool {
        stateLock.withLock {
            analyzer != nil
                || inputQueue != nil
                || inputAdapter != nil
                || analyzeTask != nil
                || !resultTasks.isEmpty
                || !assetReservations.isEmpty
        }
    }

    func setCleanupCompletionHookForTesting(
        _ hook: (@Sendable () async -> Void)?
    ) {
        stateLock.withLock {
            cleanupCompletionHookForTesting = hook
        }
    }

    func installAnalyzeTaskCancellationLockProbeForTesting(
        _ probe: @escaping @Sendable (Bool) -> Void
    ) {
        let task = Task { [weak self] in
            await withTaskCancellationHandler {
                _ = try? await Task.sleep(for: .seconds(60))
            } onCancel: { [weak self] in
                guard let self else { return }
                let acquiredStateLock = stateLock.try()
                if acquiredStateLock {
                    stateLock.unlock()
                }
                probe(acquiredStateLock)
            }
        }
        stateLock.withLock {
            precondition(analyzeTask == nil)
            analyzeTask = task
        }
    }

    var lifecycleGenerationForTesting: UInt64 {
        stateLock.withLock { lifecycleGeneration }
    }

    func claimAssetReservationForTesting(
        _ reservation: SpeechAssetReservation,
        lifecycleGeneration: UInt64
    ) -> Bool {
        claimAssetReservation(
            reservation,
            lifecycleGeneration: lifecycleGeneration
        )
    }

    func setPostRunningTaskPublicationHookForTesting(
        _ hook: (@Sendable () -> Void)?
    ) {
        stateLock.withLock {
            postRunningTaskPublicationHookForTesting = hook
        }
    }

    func publishCancellationProbeTasksForTesting(
        lifecycleGeneration: UInt64,
        onStarted: @escaping @Sendable (String) -> Void,
        onCancelled: @escaping @Sendable (String) -> Void
    ) -> Bool {
        publishRunningTasks(lifecycleGeneration: lifecycleGeneration) { producerStartGate in
            let makeTask: @Sendable (String) -> Task<Void, Never> = { name in
                Task {
                    await producerStartGate.wait()
                    guard !Task.isCancelled else {
                        onCancelled(name)
                        return
                    }
                    onStarted(name)
                }
            }
            return (makeTask("analyze"), [makeTask("result")])
        }
    }

    func makeInputQueueForTesting<Element: Sendable>(
        bufferLimit: Int = LiveSpeechTranscriber.analyzerInputBufferLimit
    ) -> SpeechAnalyzerInputQueue<Element> {
        makeInputQueue(bufferLimit: bufferLimit)
    }

    func installInputAdapterForTesting(
        _ adapter: any SpeechAnalyzerInputAdapting,
        queue: SpeechAnalyzerInputQueue<AnalyzerInput>
    ) {
        stateLock.withLock {
            precondition(inputQueue == nil && inputAdapter == nil)
            inputAdapter = adapter
            inputQueue = queue
        }
    }
#endif

    private static func averageConfidence(in text: AttributedString) -> Double {
        var total = 0.0
        var count = 0

        for run in text.runs {
            if let confidence = run[AttributeScopes.SpeechAttributes.ConfidenceAttribute.self] {
                total += confidence
                count += 1
            }
        }

        return count == 0 ? 0.5 : total / Double(count)
    }

    private func pcmBuffer(from sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
        let frameCount = CMSampleBufferGetNumSamples(sampleBuffer)
        guard frameCount > 0,
              let pcmBuffer = reusablePCMBuffer(frameCount: frameCount),
              let destination = pcmBuffer.int16ChannelData?.pointee,
              let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
              let streamDescription = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription)
        else {
            return nil
        }

        var listSize = 0
        CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: &listSize,
            bufferListOut: nil,
            bufferListSize: 0,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: 0,
            blockBufferOut: nil
        )
        guard listSize > 0 else { return nil }

        return withUnsafeTemporaryAllocation(
            byteCount: listSize,
            alignment: MemoryLayout<AudioBufferList>.alignment
        ) { rawList -> AVAudioPCMBuffer? in
            guard let baseAddress = rawList.baseAddress else { return nil }

            let audioBufferList = baseAddress.bindMemory(to: AudioBufferList.self, capacity: 1)
            var blockBuffer: CMBlockBuffer?
            let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
                sampleBuffer,
                bufferListSizeNeededOut: nil,
                bufferListOut: audioBufferList,
                bufferListSize: listSize,
                blockBufferAllocator: kCFAllocatorDefault,
                blockBufferMemoryAllocator: kCFAllocatorDefault,
                flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
                blockBufferOut: &blockBuffer
            )
            guard status == noErr else { return nil }

            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            let sourceIsFloat = streamDescription.pointee.mFormatFlags & kAudioFormatFlagIsFloat != 0
            var copiedSamples = 0

            for buffer in buffers {
                guard let data = buffer.mData else { continue }

                if sourceIsFloat {
                    let sampleCount = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
                    let samples = data.bindMemory(to: Float.self, capacity: sampleCount)
                    for index in 0..<sampleCount where copiedSamples < frameCount {
                        let sample = max(-1, min(1, samples[index]))
                        destination[copiedSamples] = Int16(sample * Float(Int16.max))
                        copiedSamples += 1
                    }
                } else {
                    let sampleCount = Int(buffer.mDataByteSize) / MemoryLayout<Int16>.size
                    let samples = data.bindMemory(to: Int16.self, capacity: sampleCount)
                    let remainingSamples = frameCount - copiedSamples
                    let samplesToCopy = min(sampleCount, remainingSamples)
                    guard samplesToCopy > 0 else { break }

                    destination
                        .advanced(by: copiedSamples)
                        .update(from: samples, count: samplesToCopy)
                    copiedSamples += samplesToCopy
                }
            }

            guard copiedSamples > 0 else { return nil }
            pcmBuffer.frameLength = AVAudioFrameCount(copiedSamples)
            return pcmBuffer
        }
    }

    private func reusablePCMBuffer(frameCount: Int) -> AVAudioPCMBuffer? {
        let frameCapacity = AVAudioFrameCount(frameCount)
        let index = reusablePCMBufferCursor
        reusablePCMBufferCursor = (reusablePCMBufferCursor + 1) % Self.reusablePCMBufferCount

        if let buffer = reusablePCMBuffers[index],
           buffer.frameCapacity >= frameCapacity {
            buffer.frameLength = 0
            return buffer
        }

        let buffer = AVAudioPCMBuffer(
            pcmFormat: audioFormat,
            frameCapacity: frameCapacity
        )
        reusablePCMBuffers[index] = buffer
        return buffer
    }

    private func resetReusablePCMBuffers() {
        conversionLock.lock()
        reusablePCMBuffers = [AVAudioPCMBuffer?](
            repeating: nil,
            count: Self.reusablePCMBufferCount
        )
        reusablePCMBufferCursor = 0
        conversionLock.unlock()
    }
}
