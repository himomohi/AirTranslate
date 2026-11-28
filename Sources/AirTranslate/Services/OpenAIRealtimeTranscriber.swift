import AVFoundation
import CoreMedia
import Foundation

enum RealtimeAudioTransportProvider: String, Sendable {
    case openAI
    case gemini
    case meta
}

enum RealtimeAudioDropPhase: String, Sendable {
    case sendWindow
    case preSetupBuffer
}

enum RealtimeAudioDropPolicy: String, Sendable {
    case dropNewest = "drop-newest"
    case dropOldest = "drop-oldest"
}

struct RealtimeAudioTransportDegradation: Equatable, Sendable {
    let provider: RealtimeAudioTransportProvider
    let policy: RealtimeAudioDropPolicy
    let phase: RealtimeAudioDropPhase
    let droppedChunkCount: Int
    let droppedAudioDuration: TimeInterval
    let pendingSendCount: Int
    let pendingSendLimit: Int
}

final class OpenAIRealtimeTranscriber: @unchecked Sendable {
    private static let realtimeAudioSampleRate = 24_000
    private static let maxAudioChunkMilliseconds = 80
    private static let bytesPerPCM16Sample = 2
    private static let maxPCM16AudioChunkByteCount = realtimeAudioSampleRate
        * bytesPerPCM16Sample
        * maxAudioChunkMilliseconds
        / 1_000
    private static let maxPendingAudioSendCount = 48
    private static let realtimeTranscriptPublishInterval: TimeInterval = 0.05
    static let maximumTrackedRealtimeTimelineItemCount = 256
    private static let missingLifecycleMetadataGraceRegistrations = 8
    private static let missingLifecycleMetadataGraceSeconds: TimeInterval = 0.1
    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    enum OutputMode {
        case transcription
        case translationOnly
    }

    var delegate: LiveSpeechTranscriberDelegate? {
        get {
            stateLock.lock()
            defer { stateLock.unlock() }
            return delegateStorage
        }
        set {
            stateLock.lock()
            delegateStorage = newValue
            stateLock.unlock()
        }
    }
    /// Store integration can observe loss metrics without making the existing speech delegate ABI mandatory.
    /// The callback runs after the state lock is released and never contains audio, URLs, or provider diagnostics.
    var onAudioTransportDegraded: (@Sendable (RealtimeAudioTransportDegradation) -> Void)? {
        get {
            stateLock.lock()
            defer { stateLock.unlock() }
            return audioTransportDegradationHandler
        }
        set {
            stateLock.lock()
            audioTransportDegradationHandler = newValue
            stateLock.unlock()
        }
    }

    private let stateLock = NSLock()
    private let conversionLock = NSLock()
    private weak var delegateStorage: LiveSpeechTranscriberDelegate?
    private var urlSession: URLSession?
    private var webSocketTask: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var connectionGeneration: UInt64 = 0
    private var language = LanguageOption.supported[0]
    private var outputMode = OutputMode.transcription
    private var isPaused = false
    private var pendingAudioSendCount = 0
    private var droppedAudioChunkCount = 0
    private var droppedAudioByteCount = 0
    private var audioTransportDegradationHandler:
        (@Sendable (RealtimeAudioTransportDegradation) -> Void)?
    private var terminalTranscriptHandler: ((
        _ text: String,
        _ language: LanguageOption,
        _ confidence: Double
    ) -> Void)?
    private let proxyTranscriber = LiveSpeechTranscriber()
    private let realtimeTranscriptBufferLock = NSLock()
    private var realtimeTranscriptionPublishThrottles: [String: RealtimeTranscriptPublishThrottle] = [:]
    private var realtimeTimelineItems: [String: RealtimeTimelineItem] = [:]
    private var realtimeTimelineRegistrationCounter = 0
    private var realtimeTimelineOrderCache: [String] = []
    private var isRealtimeTimelineOrderCacheDirty = true
    private var realtimeTimelineRetiredItemIDs = Set<String>()
    private var realtimeTimelineRetiredItemOrder: [String] = []
    private var pendingRealtimeTimelineFlushTask: Task<Void, Never>?
    private var realtimeTranscriptsPendingDelivery: [String] = []
    private let realtimeTranscriptDeliveryCondition = NSCondition()
    private var realtimeTranscriptDeliveryCounts: [UInt64: Int] = [:]
    #if DEBUG
    private var realtimeTranscriptsQueuedForDeliveryHook: (() -> Void)?
    private var realtimeEventValidatedBeforeMutationHook: (() -> Void)?
    private var realtimeTimelineMutationValidatedHook: (() -> Void)?
    #endif
    private let realtimeTranslationInputPublishThrottle = RealtimeTranscriptPublishThrottle(
        publishInterval: OpenAIRealtimeTranscriber.realtimeTranscriptPublishInterval
    )
    private let realtimeTranslationOutputPublishThrottle = RealtimeTranscriptPublishThrottle(
        publishInterval: OpenAIRealtimeTranscriber.realtimeTranscriptPublishInterval
    )

    #if DEBUG
    var onRealtimeTranscriptsQueuedForDeliveryForTesting: (() -> Void)? {
        get {
            stateLock.lock()
            defer { stateLock.unlock() }
            return realtimeTranscriptsQueuedForDeliveryHook
        }
        set {
            stateLock.lock()
            realtimeTranscriptsQueuedForDeliveryHook = newValue
            stateLock.unlock()
        }
    }

    var onRealtimeEventValidatedBeforeMutationForTesting: (() -> Void)? {
        get {
            stateLock.lock()
            defer { stateLock.unlock() }
            return realtimeEventValidatedBeforeMutationHook
        }
        set {
            stateLock.lock()
            realtimeEventValidatedBeforeMutationHook = newValue
            stateLock.unlock()
        }
    }

    var onRealtimeTimelineMutationValidatedForTesting: (() -> Void)? {
        get {
            stateLock.lock()
            defer { stateLock.unlock() }
            return realtimeTimelineMutationValidatedHook
        }
        set {
            stateLock.lock()
            realtimeTimelineMutationValidatedHook = newValue
            stateLock.unlock()
        }
    }
    #endif

    var onTerminalTranscriptReady: ((
        _ text: String,
        _ language: LanguageOption,
        _ confidence: Double
    ) -> Void)? {
        get {
            stateLock.lock()
            defer { stateLock.unlock() }
            return terminalTranscriptHandler
        }
        set {
            stateLock.lock()
            terminalTranscriptHandler = newValue
            stateLock.unlock()
        }
    }

    func start(language: LanguageOption, model: OpenAIRealtimeTranscriptionModel) async throws {
        try await start(
            language: language,
            modelID: model.rawValue,
            outputMode: .transcription,
            isEnabled: model.isEnabled
        )
    }

    func startRealtimeTranslationOnly(language: LanguageOption, model: OpenAIRealtimeTranslationModel) async throws {
        try await start(
            language: language,
            modelID: model.apiModelID,
            outputMode: .translationOnly,
            isEnabled: model.usesRealtimeAudioTranslation
        )
    }

    private func start(
        language: LanguageOption,
        modelID: String,
        outputMode: OutputMode,
        isEnabled: Bool
    ) async throws {
        let startIntentGeneration = stop()

        guard isEnabled else { return }
        guard let apiKey = try OpenAIAPIKeyStore.readAPIKey(), !apiKey.isEmpty else {
            throw OpenAITranslationError.missingAPIKey
        }

        let url: URL
        switch outputMode {
        case .transcription:
            url = URL(string: "wss://api.openai.com/v1/realtime?intent=transcription")!
        case .translationOnly:
            url = URL(string: "wss://api.openai.com/v1/realtime/translations?model=\(modelID)")!
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        let urlSession = URLSession(
            configuration: configuration,
            delegate: OpenAIRealtimeRejectRedirects(),
            delegateQueue: nil
        )
        let webSocketTask = urlSession.webSocketTask(with: request)
        let generation = stateLock.withLock { () -> UInt64? in
            guard connectionGeneration == startIntentGeneration else { return nil }
            connectionGeneration &+= 1
            self.language = language
            self.outputMode = outputMode
            self.urlSession = urlSession
            self.webSocketTask = webSocketTask
            isPaused = false
            return connectionGeneration
        }
        guard let generation else {
            webSocketTask.cancel(with: .goingAway, reason: nil)
            urlSession.invalidateAndCancel()
            throw CancellationError()
        }
        webSocketTask.resume()

        do {
            try await sendSessionUpdate(
                language: language,
                modelID: modelID,
                outputMode: outputMode,
                webSocketTask: webSocketTask,
                generation: generation
            )
        } catch {
            cancelConnectionIfCurrent(
                webSocketTask: webSocketTask,
                generation: generation
            )
            throw Self.publicConnectionError(from: error)
        }

        let receiveTask = Task<Void, Never> { [weak self, webSocketTask] in
            guard let self else { return }
            await self.receiveLoop(
                webSocketTask: webSocketTask,
                generation: generation
            )
        }
        let didInstallReceiveTask = stateLock.withLock {
            guard connectionGeneration == generation, self.webSocketTask === webSocketTask else {
                return false
            }
            self.receiveTask = receiveTask
            return true
        }
        if !didInstallReceiveTask {
            receiveTask.cancel()
            webSocketTask.cancel(with: .goingAway, reason: nil)
            throw CancellationError()
        }
    }

    func append(_ sampleBuffer: CMSampleBuffer) {
        stateLock.lock()
        let isPaused = isPaused
        let webSocketTask = webSocketTask
        let audioAppendEventType = outputMode.audioAppendEventType
        let generation = connectionGeneration
        stateLock.unlock()

        guard !isPaused, let webSocketTask else { return }

        conversionLock.lock()
        let audioChunks = pcm16Base64AudioChunks(from: sampleBuffer)
        conversionLock.unlock()

        for chunk in audioChunks {
            let text = "{\"type\":\"\(audioAppendEventType)\",\"audio\":\"\(chunk.base64)\"}"
            guard reserveAudioSendSlot(
                audioByteCount: chunk.byteCount,
                generation: generation
            ) else {
                continue
            }

            webSocketTask.send(.string(text)) { [weak self] error in
                self?.releaseAudioSendSlot(generation: generation)
                guard let error, let self else { return }
                self.publishFailureIfCurrent(
                    Self.publicConnectionError(from: error),
                    generation: generation
                )
            }
        }
    }

    func setPaused(_ isPaused: Bool) {
        stateLock.lock()
        self.isPaused = isPaused
        stateLock.unlock()
    }

    @discardableResult
    func stop(
        flushingTerminalTranscriptsWith handler: ((
            _ text: String,
            _ language: LanguageOption,
            _ confidence: Double
        ) -> Void)? = nil
    ) -> UInt64 {
        stateLock.lock()
        let stoppingGeneration = connectionGeneration
        let terminalTranscripts = resetRealtimeTranscriptBuffers(
            flushingTerminalTranscripts: true
        )
        let terminalTranscriptDelegate = delegateStorage
        let storedTerminalTranscriptHandler = terminalTranscriptHandler
        let terminalTranscriptLanguage = language
        connectionGeneration &+= 1
        let stoppedGeneration = connectionGeneration
        let receiveTask = receiveTask
        let webSocketTask = webSocketTask
        let urlSession = urlSession
        self.receiveTask = nil
        self.webSocketTask = nil
        self.urlSession = nil
        isPaused = false
        pendingAudioSendCount = 0
        droppedAudioChunkCount = 0
        droppedAudioByteCount = 0
        stateLock.unlock()
        waitForRealtimeTranscriptDeliveries(generation: stoppingGeneration)
        terminalTranscripts.forEach { text in
            if let handler {
                handler(text, terminalTranscriptLanguage, 0.5)
            } else if let storedTerminalTranscriptHandler {
                storedTerminalTranscriptHandler(text, terminalTranscriptLanguage, 0.5)
            } else {
                terminalTranscriptDelegate?.liveSpeechTranscriber(
                    proxyTranscriber,
                    didRecognize: text,
                    language: terminalTranscriptLanguage,
                    confidence: 0.5
                )
            }
        }
        receiveTask?.cancel()
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        urlSession?.invalidateAndCancel()
        return stoppedGeneration
    }

    @discardableResult
    func reserveAudioSendSlot(audioByteCount: Int) -> Bool {
        stateLock.lock()
        let generation = connectionGeneration
        stateLock.unlock()
        return reserveAudioSendSlot(
            audioByteCount: audioByteCount,
            generation: generation
        )
    }

    @discardableResult
    private func reserveAudioSendSlot(
        audioByteCount: Int,
        generation: UInt64
    ) -> Bool {
        stateLock.lock()
        guard connectionGeneration == generation,
              pendingAudioSendCount < Self.maxPendingAudioSendCount
        else {
            guard connectionGeneration == generation else {
                stateLock.unlock()
                return false
            }
            droppedAudioChunkCount += 1
            droppedAudioByteCount += max(0, audioByteCount)
            let degradation = audioTransportDegradationLocked(phase: .sendWindow)
            let callback = audioTransportDegradationHandler
            stateLock.unlock()
            callback?(degradation)
            return false
        }

        pendingAudioSendCount += 1
        stateLock.unlock()
        return true
    }

    func releaseAudioSendSlot() {
        stateLock.lock()
        let generation = connectionGeneration
        stateLock.unlock()
        releaseAudioSendSlot(generation: generation)
    }

    private func releaseAudioSendSlot(generation: UInt64) {
        stateLock.lock()
        guard connectionGeneration == generation else {
            stateLock.unlock()
            return
        }
        pendingAudioSendCount = max(0, pendingAudioSendCount - 1)
        stateLock.unlock()
    }

    var audioTransportDegradation: RealtimeAudioTransportDegradation? {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard droppedAudioChunkCount > 0 else { return nil }
        return audioTransportDegradationLocked(phase: .sendWindow)
    }

    private func audioTransportDegradationLocked(
        phase: RealtimeAudioDropPhase
    ) -> RealtimeAudioTransportDegradation {
        RealtimeAudioTransportDegradation(
            provider: .openAI,
            policy: .dropNewest,
            phase: phase,
            droppedChunkCount: droppedAudioChunkCount,
            droppedAudioDuration: TimeInterval(droppedAudioByteCount)
                / TimeInterval(Self.realtimeAudioSampleRate * Self.bytesPerPCM16Sample),
            pendingSendCount: pendingAudioSendCount,
            pendingSendLimit: Self.maxPendingAudioSendCount
        )
    }

    private static func decodedAudioByteCount(_ base64: String) -> Int {
        Data(base64Encoded: base64)?.count ?? (base64.utf8.count / 4 * 3)
    }

    private func sendSessionUpdate(
        language: LanguageOption,
        modelID: String,
        outputMode: OutputMode,
        webSocketTask: URLSessionWebSocketTask,
        generation: UInt64
    ) async throws {
        let data: Data
        switch outputMode {
        case .transcription:
            data = try Self.transcriptionSessionUpdateData(language: language, modelID: modelID)
        case .translationOnly:
            let event = OpenAIRealtimeTranslationSessionUpdateEvent(
                session: OpenAIRealtimeTranslationSession(
                    audio: OpenAIRealtimeTranslationAudio(
                        input: OpenAIRealtimeTranslationAudioInput(
                            format: OpenAIRealtimeAudioFormat(type: "audio/pcm", rate: Self.realtimeAudioSampleRate),
                            transcription: OpenAIRealtimeTranslationInputTranscription(
                                model: OpenAIRealtimeTranscriptionModel.gptRealtimeWhisper.rawValue
                            ),
                            turnDetection: .lowLatencyServerVAD,
                            noiseReduction: OpenAIRealtimeNoiseReduction(type: "near_field")
                        ),
                        output: OpenAIRealtimeTranslationAudioOutput(
                            language: language.openAILanguageCode
                        )
                    )
                )
            )
            data = try Self.encoder.encode(event)
        }
        guard let text = String(data: data, encoding: .utf8) else { return }
        try await send(
            text,
            webSocketTask: webSocketTask,
            generation: generation
        )
    }

    static func transcriptionSessionUpdateData(language: LanguageOption, modelID: String) throws -> Data {
        let event = OpenAIRealtimeTranscriptionSessionUpdateEvent(
            session: OpenAIRealtimeTranscriptionSession(
                type: "transcription",
                audio: OpenAIRealtimeTranscriptionAudio(
                    input: OpenAIRealtimeTranscriptionAudioInput(
                        format: OpenAIRealtimeAudioFormat(type: "audio/pcm", rate: Self.realtimeAudioSampleRate),
                        transcription: OpenAIRealtimeTranscriptionConfig(
                            model: modelID,
                            languages: [language.openAILanguageCode],
                            delay: "low"
                        ),
                        turnDetection: .lowLatencyServerVAD,
                        noiseReduction: OpenAIRealtimeNoiseReduction(type: "near_field")
                    )
                )
            )
        )
        return try Self.encoder.encode(event)
    }

    private func send(
        _ text: String,
        webSocketTask: URLSessionWebSocketTask,
        generation: UInt64
    ) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            webSocketTask.send(.string(text)) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
        guard isCurrentConnection(
            webSocketTask: webSocketTask,
            generation: generation
        ) else {
            throw CancellationError()
        }
    }

    private func receiveLoop(
        webSocketTask: URLSessionWebSocketTask,
        generation: UInt64
    ) async {
        while !Task.isCancelled {
            guard isCurrentConnection(
                webSocketTask: webSocketTask,
                generation: generation
            ) else {
                return
            }
            do {
                let message = try await webSocketTask.receive()
                guard case let .string(text) = message else { continue }
                handleEventText(text, generation: generation)
            } catch {
                guard !Task.isCancelled else { return }
                publishFailureIfCurrent(
                    Self.publicConnectionError(from: error),
                    generation: generation
                )
                return
            }
        }
    }

    func handleEventText(_ text: String) {
        stateLock.lock()
        let generation = connectionGeneration
        stateLock.unlock()
        handleEventText(text, generation: generation)
    }

    func handleEventText(_ text: String, generation: UInt64) {
        guard isCurrentGeneration(generation) else { return }
        guard let data = text.data(using: .utf8),
              let event = try? Self.decoder.decode(OpenAIRealtimeTranscriptionEvent.self, from: data)
        else { return }

        stateLock.lock()
        guard connectionGeneration == generation else {
            stateLock.unlock()
            return
        }
        let outputMode = outputMode
        stateLock.unlock()

        #if DEBUG
        if Self.isRealtimeTimelineMutationEvent(event.type) {
            let hook = stateLock.withLock {
                realtimeEventValidatedBeforeMutationHook
            }
            hook?()
        }
        #endif

        switch event.type {
        case "input_audio_buffer.committed",
            "session.input_audio_buffer.committed":
            guard let itemID = event.itemID, !itemID.isEmpty else { return }
            registerRealtimeTimelineItem(
                id: itemID,
                previousItemID: event.previousItemID,
                carriesInputTranscript: true,
                generation: generation
            )
        case "conversation.item.created":
            guard let item = event.item, !item.id.isEmpty else { return }
            registerRealtimeTimelineItem(
                id: item.id,
                previousItemID: event.previousItemID,
                carriesInputTranscript: item.carriesInputAudio,
                generation: generation
            )
        case "conversation.item.input_audio_transcription.delta",
            "session.input_audio_transcription.delta",
            "session.input_transcription.delta",
            "session.input_transcript.delta":
            guard let delta = event.delta, !delta.isEmpty else { return }
            switch outputMode {
            case .transcription:
                appendRealtimeTranscriptionDelta(
                    delta,
                    itemID: event.itemID,
                    generation: generation
                )
            case .translationOnly:
                appendRealtimeTranslationInputDelta(
                    delta,
                    generation: generation
                )
            }
        case "conversation.item.input_audio_transcription.completed",
            "session.input_audio_transcription.completed",
            "session.input_transcription.completed",
            "session.input_transcript.completed",
            "session.input_transcript.done":
            let transcript = event.transcript ?? ""
            switch outputMode {
            case .transcription:
                finishRealtimeTranscription(
                    itemID: event.itemID,
                    finalText: transcript,
                    generation: generation
                )
            case .translationOnly:
                realtimeTranslationInputPublishThrottle.finish(finalText: transcript) { [weak self] text in
                    self?.publishRealtimeTranslationInputTranscript(
                        text,
                        generation: generation
                    )
                }
            }
        case "conversation.item.input_audio_transcription.failed":
            guard outputMode == .transcription else { return }
            failRealtimeTranscription(
                itemID: event.itemID,
                generation: generation
            )
        case "session.output_transcript.delta":
            guard outputMode == .translationOnly,
                  let delta = event.delta,
                  !delta.isEmpty else { return }
            appendRealtimeTranslationOutputDelta(
                delta,
                generation: generation
            )
        case "session.output_transcript.completed",
            "session.output_transcript.done":
            guard outputMode == .translationOnly else { return }
            realtimeTranslationOutputPublishThrottle.finish(finalText: event.transcript) { [weak self] text in
                self?.publishTranslatedTranscript(
                    text,
                    generation: generation
                )
            }
        case "session.output_audio.delta":
            guard outputMode == .translationOnly,
                  let delta = event.delta,
                  !delta.isEmpty else { return }
            publishOutputAudioIfCurrent(delta, generation: generation)
        case "error":
            publishFailureIfCurrent(
                OpenAIRealtimeTranscriberError.connectionFailed,
                generation: generation
            )
        default:
            return
        }
    }

    nonisolated static func publicConnectionError(from error: Error) -> Error {
        if error is CancellationError {
            return error
        }
        if error is OpenAIRealtimeTranscriberError {
            return error
        }
        return OpenAIRealtimeTranscriberError.connectionFailed
    }

    private func appendRealtimeTranscriptionDelta(
        _ delta: String,
        itemID: String?,
        generation: UInt64
    ) {
        stateLock.lock()
        guard connectionGeneration == generation else {
            stateLock.unlock()
            return
        }
        realtimeTranscriptBufferLock.lock()
        if let itemID, !itemID.isEmpty,
           realtimeTimelineItems[itemID]?.isTerminal == true {
            realtimeTranscriptBufferLock.unlock()
            stateLock.unlock()
            return
        }
        let shouldPublish: Bool
        if let itemID, !itemID.isEmpty {
            shouldPublish = orderedInputTranscriptItemIDsLocked().first == itemID
        } else {
            shouldPublish = true
        }
        let throttleID = transcriptBufferID(for: itemID)
        let throttle: RealtimeTranscriptPublishThrottle
        if let existingThrottle = realtimeTranscriptionPublishThrottles[throttleID] {
            throttle = existingThrottle
        } else {
            throttle = RealtimeTranscriptPublishThrottle(
                publishInterval: Self.realtimeTranscriptPublishInterval
            )
            realtimeTranscriptionPublishThrottles[throttleID] = throttle
        }
        realtimeTranscriptBufferLock.unlock()
        stateLock.unlock()

        throttle.append(delta) { [weak self] text in
            guard shouldPublish else { return }
            self?.publishRecognizedTranscript(
                text,
                generation: generation
            )
        }
    }

    private func finishRealtimeTranscription(
        itemID: String?,
        finalText: String?,
        generation: UInt64
    ) {
        let completion = completeRealtimeTimelineItem(
            id: itemID,
            finalText: finalText,
            generation: generation,
            isFailure: false
        )
        deliverPendingRealtimeTranscripts(generation: generation)
        schedulePendingRealtimeTimelineFlushIfNeeded(generation: generation)
        if completion.didOverflow {
            publishFailureIfCurrent(
                OpenAIRealtimeTranscriberError.timelineCapacityExceeded,
                generation: generation
            )
        }
    }

    private func failRealtimeTranscription(
        itemID: String?,
        generation: UInt64
    ) {
        guard let itemID, !itemID.isEmpty else { return }
        let completion = completeRealtimeTimelineItem(
            id: itemID,
            finalText: nil,
            generation: generation,
            isFailure: true
        )
        deliverPendingRealtimeTranscripts(generation: generation)
        schedulePendingRealtimeTimelineFlushIfNeeded(generation: generation)
        if completion.didOverflow {
            publishFailureIfCurrent(
                OpenAIRealtimeTranscriberError.timelineCapacityExceeded,
                generation: generation
            )
        }
    }

    private func transcriptBufferID(for itemID: String?) -> String {
        guard let itemID, !itemID.isEmpty else {
            return "legacy-transcription-item"
        }
        return itemID
    }

    private func registerRealtimeTimelineItem(
        id: String,
        previousItemID: String?,
        carriesInputTranscript: Bool,
        generation: UInt64
    ) {
        stateLock.lock()
        guard connectionGeneration == generation else {
            stateLock.unlock()
            return
        }
        #if DEBUG
        realtimeTimelineMutationValidatedHook?()
        #endif
        realtimeTranscriptBufferLock.lock()
        if var item = realtimeTimelineItems[id] {
            item.previousItemID = previousItemID ?? item.previousItemID
            item.carriesInputTranscript = item.carriesInputTranscript || carriesInputTranscript
            item.hasLifecycleMetadata = true
            realtimeTimelineItems[id] = item
        } else {
            realtimeTimelineRegistrationCounter += 1
            realtimeTimelineItems[id] = RealtimeTimelineItem(
                previousItemID: previousItemID,
                carriesInputTranscript: carriesInputTranscript,
                registrationOrder: realtimeTimelineRegistrationCounter,
                hasLifecycleMetadata: true
            )
        }
        isRealtimeTimelineOrderCacheDirty = true
        var readyTranscripts = drainCompletedRealtimeTranscriptsLocked()
        let retention = enforceRealtimeTimelineRetentionLimitLocked()
        readyTranscripts.append(contentsOf: retention.transcripts)
        realtimeTranscriptsPendingDelivery.append(contentsOf: readyTranscripts)
        realtimeTranscriptBufferLock.unlock()
        stateLock.unlock()
        deliverPendingRealtimeTranscripts(generation: generation)
        if retention.didOverflow {
            publishFailureIfCurrent(
                OpenAIRealtimeTranscriberError.timelineCapacityExceeded,
                generation: generation
            )
        }
    }

    private func completeRealtimeTimelineItem(
        id: String?,
        finalText: String?,
        generation: UInt64,
        isFailure: Bool
    ) -> RealtimeTimelineCompletion {
        stateLock.lock()
        guard connectionGeneration == generation else {
            stateLock.unlock()
            return .empty
        }
        #if DEBUG
        realtimeTimelineMutationValidatedHook?()
        #endif
        realtimeTranscriptBufferLock.lock()
        defer {
            realtimeTranscriptBufferLock.unlock()
            stateLock.unlock()
        }

        let throttle = realtimeTranscriptionPublishThrottles.removeValue(
            forKey: transcriptBufferID(for: id)
        ) ?? RealtimeTranscriptPublishThrottle(
            publishInterval: Self.realtimeTranscriptPublishInterval
        )
        let completedText: String?
        if isFailure {
            throttle.reset()
            completedText = nil
        } else {
            completedText = throttle.takeCompletedText(finalText: finalText)
        }

        guard let id, !id.isEmpty else {
            if let completedText, !completedText.isEmpty {
                realtimeTranscriptsPendingDelivery.append(completedText)
            }
            return .empty
        }

        if var item = realtimeTimelineItems[id] {
            guard !item.isTerminal else { return .empty }
            item.carriesInputTranscript = true
            item.isTerminal = true
            item.completedText = completedText
            item.terminalAt = Date()
            realtimeTimelineItems[id] = item
        } else {
            realtimeTimelineRegistrationCounter += 1
            realtimeTimelineItems[id] = RealtimeTimelineItem(
                previousItemID: nil,
                carriesInputTranscript: true,
                registrationOrder: realtimeTimelineRegistrationCounter,
                hasLifecycleMetadata: false,
                isTerminal: true,
                completedText: completedText,
                terminalAt: Date()
            )
        }
        isRealtimeTimelineOrderCacheDirty = true
        var readyTranscripts = drainCompletedRealtimeTranscriptsLocked()
        let retention = enforceRealtimeTimelineRetentionLimitLocked()
        readyTranscripts.append(contentsOf: retention.transcripts)
        realtimeTranscriptsPendingDelivery.append(contentsOf: readyTranscripts)
        return RealtimeTimelineCompletion(
            didOverflow: retention.didOverflow
        )
    }

    private func drainCompletedRealtimeTranscriptsLocked() -> [String] {
        var transcripts: [String] = []
        for id in orderedInputTranscriptItemIDsLocked() {
            guard let item = realtimeTimelineItems[id] else { continue }
            if !item.hasLifecycleMetadata || hasUnresolvedPredecessorLocked(for: id) {
                let registrationAge = realtimeTimelineRegistrationCounter - item.registrationOrder
                let terminalAge = item.terminalAt.map { Date().timeIntervalSince($0) } ?? 0
                guard item.isTerminal,
                      registrationAge >= Self.missingLifecycleMetadataGraceRegistrations
                        || terminalAge >= Self.missingLifecycleMetadataGraceSeconds
                else {
                    break
                }
            }
            guard item.isTerminal else { break }
            realtimeTimelineItems.removeValue(forKey: id)
            retireRealtimeTimelineItemLocked(id)
            realtimeTranscriptionPublishThrottles.removeValue(
                forKey: transcriptBufferID(for: id)
            )?.reset()
            isRealtimeTimelineOrderCacheDirty = true
            if let text = item.completedText, !text.isEmpty {
                transcripts.append(text)
            }
        }
        pruneUnreferencedRealtimeTimelineMetadataLocked()
        return transcripts
    }

    private func orderedInputTranscriptItemIDsLocked() -> [String] {
        if !isRealtimeTimelineOrderCacheDirty {
            return realtimeTimelineOrderCache
        }

        var successors: [String: [String]] = [:]
        var unresolvedPredecessorCount: [String: Int] = [:]
        for (id, item) in realtimeTimelineItems {
            if let predecessor = item.previousItemID,
               predecessor != id,
               realtimeTimelineItems[predecessor] != nil {
                successors[predecessor, default: []].append(id)
                unresolvedPredecessorCount[id] = 1
            } else {
                unresolvedPredecessorCount[id] = 0
            }
        }

        let registrationOrder: (String) -> Int = {
            self.realtimeTimelineItems[$0]?.registrationOrder ?? .max
        }
        let sortsLater: (String, String) -> Bool = { lhs, rhs in
            let lhsOrder = registrationOrder(lhs)
            let rhsOrder = registrationOrder(rhs)
            return lhsOrder == rhsOrder ? lhs > rhs : lhsOrder > rhsOrder
        }
        var ready = unresolvedPredecessorCount
            .compactMap { $0.value == 0 ? $0.key : nil }
            .sorted(by: sortsLater)
        var ranks: [String: Int] = [:]

        while let id = ready.popLast() {
            guard ranks[id] == nil else { continue }
            ranks[id] = ranks.count
            for successor in successors[id] ?? [] {
                let remaining = max(0, (unresolvedPredecessorCount[successor] ?? 0) - 1)
                unresolvedPredecessorCount[successor] = remaining
                guard remaining == 0 else { continue }
                let insertionIndex = ready.firstIndex {
                    sortsLater(successor, $0)
                } ?? ready.endIndex
                ready.insert(successor, at: insertionIndex)
            }
        }

        // A provider cycle has no valid causal order. Keep the cache total and
        // deterministic so the bounded-retention path can handle malformed data.
        let unranked = realtimeTimelineItems.keys
            .filter { ranks[$0] == nil }
            .sorted {
                let lhsOrder = registrationOrder($0)
                let rhsOrder = registrationOrder($1)
                return lhsOrder == rhsOrder ? $0 < $1 : lhsOrder < rhsOrder
            }
        for id in unranked {
            ranks[id] = ranks.count
        }

        realtimeTimelineOrderCache = realtimeTimelineItems
            .filter { $0.value.carriesInputTranscript }
            .map(\.key)
            .sorted {
                (ranks[$0] ?? .max) < (ranks[$1] ?? .max)
            }
        isRealtimeTimelineOrderCacheDirty = false
        return realtimeTimelineOrderCache
    }

    private func schedulePendingRealtimeTimelineFlushIfNeeded(generation: UInt64) {
        stateLock.lock()
        guard connectionGeneration == generation else {
            stateLock.unlock()
            return
        }
        realtimeTranscriptBufferLock.lock()
        let hasPendingTerminalItem = realtimeTimelineItems.contains { id, item in
            item.isTerminal
                && (!item.hasLifecycleMetadata || hasUnresolvedPredecessorLocked(for: id))
        }
        guard hasPendingTerminalItem, pendingRealtimeTimelineFlushTask == nil else {
            realtimeTranscriptBufferLock.unlock()
            stateLock.unlock()
            return
        }
        pendingRealtimeTimelineFlushTask = Task { [weak self] in
            do {
                try await Task.sleep(
                    for: .seconds(Self.missingLifecycleMetadataGraceSeconds)
                )
            } catch {
                return
            }
            self?.flushExpiredRealtimeTimelineItems(generation: generation)
        }
        realtimeTranscriptBufferLock.unlock()
        stateLock.unlock()
    }

    #if DEBUG
    private static func isRealtimeTimelineMutationEvent(_ type: String) -> Bool {
        switch type {
        case "input_audio_buffer.committed",
            "session.input_audio_buffer.committed",
            "conversation.item.created",
            "conversation.item.input_audio_transcription.completed",
            "session.input_audio_transcription.completed",
            "session.input_transcription.completed",
            "session.input_transcript.completed",
            "session.input_transcript.done",
            "conversation.item.input_audio_transcription.failed":
            true
        default:
            false
        }
    }
    #endif

    private func flushExpiredRealtimeTimelineItems(generation: UInt64) {
        stateLock.lock()
        guard connectionGeneration == generation else {
            stateLock.unlock()
            return
        }
        realtimeTranscriptBufferLock.lock()
        pendingRealtimeTimelineFlushTask = nil
        let transcripts = drainCompletedRealtimeTranscriptsLocked()
        realtimeTranscriptsPendingDelivery.append(contentsOf: transcripts)
        realtimeTranscriptBufferLock.unlock()
        stateLock.unlock()
        deliverPendingRealtimeTranscripts(generation: generation)
        schedulePendingRealtimeTimelineFlushIfNeeded(generation: generation)
    }

    private func deliverPendingRealtimeTranscripts(generation: UInt64) {
        #if DEBUG
        realtimeTranscriptBufferLock.lock()
        let hasPendingTranscripts = !realtimeTranscriptsPendingDelivery.isEmpty
        realtimeTranscriptBufferLock.unlock()
        if hasPendingTranscripts {
            let hook = stateLock.withLock {
                realtimeTranscriptsQueuedForDeliveryHook
            }
            hook?()
        }
        #endif

        stateLock.lock()
        guard connectionGeneration == generation else {
            stateLock.unlock()
            return
        }
        let delegate = delegateStorage
        let storedTerminalTranscriptHandler = terminalTranscriptHandler
        guard delegate != nil || storedTerminalTranscriptHandler != nil else {
            stateLock.unlock()
            return
        }
        realtimeTranscriptBufferLock.lock()
        let transcripts = realtimeTranscriptsPendingDelivery
        realtimeTranscriptsPendingDelivery.removeAll()
        realtimeTranscriptBufferLock.unlock()
        guard !transcripts.isEmpty else {
            stateLock.unlock()
            return
        }
        let callbackLanguage = language
        beginRealtimeTranscriptDelivery(generation: generation)
        stateLock.unlock()

        let deliveryThreadKey = realtimeTranscriptDeliveryThreadKey(generation: generation)
        let deliveryDepth = (Thread.current.threadDictionary[deliveryThreadKey] as? Int) ?? 0
        Thread.current.threadDictionary[deliveryThreadKey] = deliveryDepth + 1
        defer {
            if deliveryDepth == 0 {
                Thread.current.threadDictionary.removeObject(forKey: deliveryThreadKey)
            } else {
                Thread.current.threadDictionary[deliveryThreadKey] = deliveryDepth
            }
            endRealtimeTranscriptDelivery(generation: generation)
        }
        transcripts.forEach { text in
            if let storedTerminalTranscriptHandler {
                storedTerminalTranscriptHandler(text, callbackLanguage, 0.5)
            } else {
                delegate?.liveSpeechTranscriber(
                    proxyTranscriber,
                    didRecognize: text,
                    language: callbackLanguage,
                    confidence: 0.5
                )
            }
        }
    }

    private func beginRealtimeTranscriptDelivery(generation: UInt64) {
        realtimeTranscriptDeliveryCondition.lock()
        realtimeTranscriptDeliveryCounts[generation, default: 0] += 1
        realtimeTranscriptDeliveryCondition.unlock()
    }

    private func endRealtimeTranscriptDelivery(generation: UInt64) {
        realtimeTranscriptDeliveryCondition.lock()
        let remaining = max(0, (realtimeTranscriptDeliveryCounts[generation] ?? 0) - 1)
        if remaining == 0 {
            realtimeTranscriptDeliveryCounts.removeValue(forKey: generation)
            realtimeTranscriptDeliveryCondition.broadcast()
        } else {
            realtimeTranscriptDeliveryCounts[generation] = remaining
        }
        realtimeTranscriptDeliveryCondition.unlock()
    }

    private func waitForRealtimeTranscriptDeliveries(generation: UInt64) {
        let deliveryThreadKey = realtimeTranscriptDeliveryThreadKey(generation: generation)
        guard Thread.current.threadDictionary[deliveryThreadKey] == nil else { return }
        let deadline = Date(timeIntervalSinceNow: 2.0)
        realtimeTranscriptDeliveryCondition.lock()
        while (realtimeTranscriptDeliveryCounts[generation] ?? 0) > 0, Date() < deadline {
            realtimeTranscriptDeliveryCondition.wait(until: deadline)
        }
        realtimeTranscriptDeliveryCondition.unlock()
    }

    private func realtimeTranscriptDeliveryThreadKey(generation: UInt64) -> String {
        "OpenAIRealtimeTranscriber.\(ObjectIdentifier(self).hashValue).delivery.\(generation)"
    }

    private func enforceRealtimeTimelineRetentionLimitLocked() -> RealtimeTimelineRetentionResult {
        guard realtimeTimelineItems.count > Self.maximumTrackedRealtimeTimelineItemCount else {
            return .empty
        }

        // Do not manufacture an empty terminal item to make room: that silently
        // loses a provider transcript. Clear this bounded, invalid timeline and
        // let the caller turn the loss into a sanitized, controlled failure.
        let throttles = realtimeTranscriptionPublishThrottles.values
        realtimeTranscriptionPublishThrottles.removeAll()
        realtimeTimelineItems.removeAll()
        realtimeTimelineRegistrationCounter = 0
        realtimeTimelineOrderCache.removeAll()
        isRealtimeTimelineOrderCacheDirty = true
        realtimeTimelineRetiredItemIDs.removeAll()
        realtimeTimelineRetiredItemOrder.removeAll()
        throttles.forEach { $0.reset() }
        return RealtimeTimelineRetentionResult(
            transcripts: [],
            didOverflow: true
        )
    }

    private func pruneUnreferencedRealtimeTimelineMetadataLocked() {
        let referencedIDs = Set(realtimeTimelineItems.values.compactMap(\.previousItemID))
        let removableIDs = realtimeTimelineItems.compactMap { id, item in
            !item.carriesInputTranscript && !referencedIDs.contains(id) ? id : nil
        }
        guard !removableIDs.isEmpty else { return }
        removableIDs.forEach {
            realtimeTimelineItems.removeValue(forKey: $0)
            retireRealtimeTimelineItemLocked($0)
        }
        isRealtimeTimelineOrderCacheDirty = true
    }

    private func hasUnresolvedPredecessorLocked(for id: String) -> Bool {
        var cursor = realtimeTimelineItems[id]?.previousItemID
        var visited = Set<String>()
        while let current = cursor, visited.insert(current).inserted {
            if realtimeTimelineRetiredItemIDs.contains(current) {
                return false
            }
            guard let item = realtimeTimelineItems[current] else {
                return true
            }
            cursor = item.previousItemID
        }
        return false
    }

    private func retireRealtimeTimelineItemLocked(_ id: String) {
        guard realtimeTimelineRetiredItemIDs.insert(id).inserted else { return }
        realtimeTimelineRetiredItemOrder.append(id)
        while realtimeTimelineRetiredItemOrder.count > Self.maximumTrackedRealtimeTimelineItemCount {
            let expiredID = realtimeTimelineRetiredItemOrder.removeFirst()
            realtimeTimelineRetiredItemIDs.remove(expiredID)
        }
    }

    private func appendRealtimeTranslationInputDelta(
        _ delta: String,
        generation: UInt64
    ) {
        realtimeTranslationInputPublishThrottle.append(delta) { [weak self] text in
            self?.publishRealtimeTranslationInputTranscript(
                text,
                generation: generation
            )
        }
    }

    private func appendRealtimeTranslationOutputDelta(
        _ delta: String,
        generation: UInt64
    ) {
        realtimeTranslationOutputPublishThrottle.append(delta) { [weak self] text in
            self?.publishTranslatedTranscript(
                text,
                generation: generation
            )
        }
    }

    private func publishRecognizedTranscript(
        _ text: String,
        generation: UInt64
    ) {
        guard let callback = delegateSnapshotIfCurrent(generation: generation) else { return }
        callback.delegate.liveSpeechTranscriber(
            callback.proxyTranscriber,
            didRecognize: text,
            language: callback.language,
            confidence: 0.5
        )
    }

    private func publishRealtimeTranslationInputTranscript(
        _ text: String,
        generation: UInt64
    ) {
        guard let callback = delegateSnapshotIfCurrent(generation: generation) else { return }
        callback.delegate.liveSpeechTranscriber(
            callback.proxyTranscriber,
            didRecognizeSourceTranscript: text,
            confidence: 0.5
        )
    }

    private func publishTranslatedTranscript(
        _ text: String,
        generation: UInt64
    ) {
        guard let callback = delegateSnapshotIfCurrent(generation: generation) else { return }
        callback.delegate.liveSpeechTranscriber(
            callback.proxyTranscriber,
            didTranslate: text,
            language: callback.language,
            confidence: 0.5
        )
    }

    private func publishOutputAudioIfCurrent(
        _ audio: String,
        generation: UInt64
    ) {
        guard let callback = delegateSnapshotIfCurrent(generation: generation) else { return }
        callback.delegate.liveSpeechTranscriber(
            callback.proxyTranscriber,
            didOutputAudioPCM16Base64: audio,
            sampleRate: Double(Self.realtimeAudioSampleRate)
        )
    }

    private func publishFailureIfCurrent(
        _ error: Error,
        generation: UInt64
    ) {
        guard let callback = delegateSnapshotIfCurrent(generation: generation) else { return }
        callback.delegate.liveSpeechTranscriber(
            callback.proxyTranscriber,
            didFail: error
        )
    }

    private func delegateSnapshotIfCurrent(
        generation: UInt64
    ) -> (
        delegate: LiveSpeechTranscriberDelegate,
        proxyTranscriber: LiveSpeechTranscriber,
        language: LanguageOption
    )? {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard connectionGeneration == generation,
              let delegate = delegateStorage
        else {
            return nil
        }
        return (delegate, proxyTranscriber, language)
    }

    private func isCurrentGeneration(_ generation: UInt64) -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return connectionGeneration == generation
    }

    private func isCurrentConnection(
        webSocketTask: URLSessionWebSocketTask,
        generation: UInt64
    ) -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return connectionGeneration == generation && self.webSocketTask === webSocketTask
    }

    private func cancelConnectionIfCurrent(
        webSocketTask: URLSessionWebSocketTask,
        generation: UInt64
    ) {
        stateLock.lock()
        guard connectionGeneration == generation, self.webSocketTask === webSocketTask else {
            stateLock.unlock()
            webSocketTask.cancel(with: .goingAway, reason: nil)
            return
        }
        connectionGeneration &+= 1
        let receiveTask = receiveTask
        let urlSession = urlSession
        self.receiveTask = nil
        self.webSocketTask = nil
        self.urlSession = nil
        pendingAudioSendCount = 0
        resetRealtimeTranscriptBuffers()
        stateLock.unlock()
        receiveTask?.cancel()
        webSocketTask.cancel(with: .goingAway, reason: nil)
        urlSession?.invalidateAndCancel()
    }

    func ownsDelegateProxy(_ transcriber: LiveSpeechTranscriber) -> Bool {
        transcriber === proxyTranscriber
    }

    var trackedRealtimeTimelineItemCount: Int {
        realtimeTranscriptBufferLock.lock()
        defer { realtimeTranscriptBufferLock.unlock() }
        return realtimeTimelineItems.count
    }

    var realtimeTranscriptionThrottleCount: Int {
        realtimeTranscriptBufferLock.lock()
        defer { realtimeTranscriptBufferLock.unlock() }
        return realtimeTranscriptionPublishThrottles.count
    }

    var currentConnectionGeneration: UInt64 {
        stateLock.lock()
        defer { stateLock.unlock() }
        return connectionGeneration
    }

    @discardableResult
    private func resetRealtimeTranscriptBuffers(
        flushingTerminalTranscripts: Bool = false
    ) -> [String] {
        realtimeTranscriptBufferLock.lock()
        let terminalTranscripts: [String]
        if flushingTerminalTranscripts {
            let terminalTimelineTranscripts: [String] = orderedInputTranscriptItemIDsLocked().compactMap { id in
                guard let item = realtimeTimelineItems[id],
                      item.isTerminal,
                      let text = item.completedText,
                      !text.isEmpty
                else {
                    return nil
                }
                return text
            }
            terminalTranscripts = realtimeTranscriptsPendingDelivery + terminalTimelineTranscripts
        } else {
            terminalTranscripts = []
        }
        let transcriptionThrottles = realtimeTranscriptionPublishThrottles.values
        let pendingTimelineFlushTask = pendingRealtimeTimelineFlushTask
        pendingRealtimeTimelineFlushTask = nil
        realtimeTranscriptsPendingDelivery.removeAll()
        realtimeTranscriptionPublishThrottles.removeAll()
        realtimeTimelineItems.removeAll()
        realtimeTimelineRegistrationCounter = 0
        realtimeTimelineOrderCache.removeAll()
        isRealtimeTimelineOrderCacheDirty = true
        realtimeTimelineRetiredItemIDs.removeAll()
        realtimeTimelineRetiredItemOrder.removeAll()
        realtimeTranscriptBufferLock.unlock()
        pendingTimelineFlushTask?.cancel()
        transcriptionThrottles.forEach { $0.reset() }
        realtimeTranslationInputPublishThrottle.reset()
        realtimeTranslationOutputPublishThrottle.reset()
        return terminalTranscripts
    }

    private func pcm16Base64AudioChunks(from sampleBuffer: CMSampleBuffer) -> [(base64: String, byteCount: Int)] {
        guard let audioData = AzureMAITranscriber.pcm16AudioData(from: sampleBuffer) else { return [] }
        return base64PCM16Chunks(from: audioData)
    }

    private func base64PCM16Chunks(from audioData: Data) -> [(base64: String, byteCount: Int)] {
        guard audioData.count > Self.maxPCM16AudioChunkByteCount else {
            return [(audioData.base64EncodedString(), audioData.count)]
        }

        var chunks: [(base64: String, byteCount: Int)] = []
        chunks.reserveCapacity((audioData.count + Self.maxPCM16AudioChunkByteCount - 1) / Self.maxPCM16AudioChunkByteCount)
        var offset = 0
        while offset < audioData.count {
            let end = min(offset + Self.maxPCM16AudioChunkByteCount, audioData.count)
            chunks.append((audioData[offset..<end].base64EncodedString(), end - offset))
            offset = end
        }
        return chunks
    }
}

private final class OpenAIRealtimeRejectRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

final class RealtimeTranscriptPublishThrottle: @unchecked Sendable {
    private let lock = NSLock()
    private let publishInterval: TimeInterval
    private var text = ""
    private var lastPublishAt = Date.distantPast
    private var pendingFlushTask: Task<Void, Never>?

    init(publishInterval: TimeInterval) {
        self.publishInterval = publishInterval
    }

    func append(_ delta: String, publish: @escaping @Sendable (String) -> Void) {
        lock.lock()
        text += delta
        let now = Date()
        let elapsed = now.timeIntervalSince(lastPublishAt)
        guard elapsed >= publishInterval else {
            scheduleTrailingFlushLocked(after: publishInterval - elapsed, publish: publish)
            lock.unlock()
            return
        }
        cancelPendingFlushLocked()
        lastPublishAt = now
        let textToPublish = text
        lock.unlock()
        publish(textToPublish)
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }

        cancelPendingFlushLocked()
        text = ""
        lastPublishAt = .distantPast
    }

    func finish(
        finalText: String?,
        publish: @escaping @Sendable (String) -> Void
    ) {
        guard let completedText = takeCompletedText(finalText: finalText) else { return }
        publish(completedText)
    }

    func takeCompletedText(finalText: String?) -> String? {
        lock.lock()
        cancelPendingFlushLocked()
        let bufferedText = text
        let completedText: String
        if let finalText, !finalText.isEmpty {
            completedText = finalText
        } else {
            completedText = bufferedText
        }
        text = ""
        lastPublishAt = .distantPast
        lock.unlock()

        return completedText.isEmpty ? nil : completedText
    }

    private func scheduleTrailingFlushLocked(
        after delay: TimeInterval,
        publish: @escaping @Sendable (String) -> Void
    ) {
        guard pendingFlushTask == nil else { return }
        pendingFlushTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            self?.flushPendingText(publish: publish)
        }
    }

    private func flushPendingText(publish: @Sendable (String) -> Void) {
        lock.lock()
        guard !Task.isCancelled else {
            lock.unlock()
            return
        }
        pendingFlushTask = nil
        guard !text.isEmpty else {
            lock.unlock()
            return
        }
        lastPublishAt = Date()
        let textToPublish = text
        lock.unlock()
        publish(textToPublish)
    }

    private func cancelPendingFlushLocked() {
        pendingFlushTask?.cancel()
        pendingFlushTask = nil
    }
}

private struct OpenAIRealtimeTranscriptionSessionUpdateEvent: Encodable {
    let type = "session.update"
    let session: OpenAIRealtimeTranscriptionSession
}

private struct OpenAIRealtimeTranslationSessionUpdateEvent: Encodable {
    let type = "session.update"
    let session: OpenAIRealtimeTranslationSession
}

private struct OpenAIRealtimeTranscriptionSession: Encodable {
    let type: String
    let audio: OpenAIRealtimeTranscriptionAudio
}

private struct OpenAIRealtimeTranscriptionAudio: Encodable {
    let input: OpenAIRealtimeTranscriptionAudioInput
}

private struct OpenAIRealtimeTranscriptionAudioInput: Encodable {
    let format: OpenAIRealtimeAudioFormat
    let transcription: OpenAIRealtimeTranscriptionConfig
    let turnDetection: OpenAIRealtimeTurnDetection
    let noiseReduction: OpenAIRealtimeNoiseReduction

    private enum CodingKeys: String, CodingKey {
        case format
        case transcription
        case turnDetection = "turn_detection"
        case noiseReduction = "noise_reduction"
    }
}

private struct OpenAIRealtimeAudioFormat: Encodable {
    let type: String
    let rate: Int
}

private struct OpenAIRealtimeTranslationSession: Encodable {
    let audio: OpenAIRealtimeTranslationAudio
}

private struct OpenAIRealtimeTranslationAudio: Encodable {
    let input: OpenAIRealtimeTranslationAudioInput
    let output: OpenAIRealtimeTranslationAudioOutput
}

private struct OpenAIRealtimeTranslationAudioInput: Encodable {
    let format: OpenAIRealtimeAudioFormat
    let transcription: OpenAIRealtimeTranslationInputTranscription
    let turnDetection: OpenAIRealtimeTurnDetection
    let noiseReduction: OpenAIRealtimeNoiseReduction

    private enum CodingKeys: String, CodingKey {
        case format
        case transcription
        case turnDetection = "turn_detection"
        case noiseReduction = "noise_reduction"
    }
}

private struct OpenAIRealtimeTranslationInputTranscription: Encodable {
    let model: String
}

private struct OpenAIRealtimeTranslationAudioOutput: Encodable {
    let language: String
}

private struct OpenAIRealtimeTranscriptionConfig: Encodable {
    let model: String
    let languages: [String]
    let delay: String
}

private struct OpenAIRealtimeTurnDetection: Encodable {
    let type: String
    let threshold: Double?
    let prefixPaddingMilliseconds: Int?
    let silenceDurationMilliseconds: Int?

    static let lowLatencyServerVAD = OpenAIRealtimeTurnDetection(
        type: "server_vad",
        threshold: 0.42,
        prefixPaddingMilliseconds: 120,
        silenceDurationMilliseconds: 220
    )

    init(
        type: String,
        threshold: Double? = nil,
        prefixPaddingMilliseconds: Int? = nil,
        silenceDurationMilliseconds: Int? = nil
    ) {
        self.type = type
        self.threshold = threshold
        self.prefixPaddingMilliseconds = prefixPaddingMilliseconds
        self.silenceDurationMilliseconds = silenceDurationMilliseconds
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case threshold
        case prefixPaddingMilliseconds = "prefix_padding_ms"
        case silenceDurationMilliseconds = "silence_duration_ms"
    }
}

private struct OpenAIRealtimeNoiseReduction: Encodable {
    let type: String
}

private struct OpenAIRealtimeAudioAppendEvent: Encodable {
    let type: String
    let audio: String
}

private struct OpenAIRealtimeTranscriptionEvent: Decodable {
    let type: String
    let itemID: String?
    let previousItemID: String?
    let item: OpenAIRealtimeConversationItem?
    let delta: String?
    let transcript: String?
    let error: OpenAIRealtimeErrorBody?

    private enum CodingKeys: String, CodingKey {
        case type
        case itemID = "item_id"
        case previousItemID = "previous_item_id"
        case item
        case delta
        case transcript
        case error
    }
}

private struct OpenAIRealtimeConversationItem: Decodable {
    let id: String
    let role: String?
    let content: [OpenAIRealtimeConversationContent]?

    var carriesInputAudio: Bool {
        role == "user" && (content?.contains(where: { $0.type == "input_audio" }) ?? false)
    }
}

private struct OpenAIRealtimeConversationContent: Decodable {
    let type: String
}

private struct OpenAIRealtimeErrorBody: Decodable {
    let message: String?
}

private enum OpenAIRealtimeTranscriberError: LocalizedError {
    case connectionFailed
    case timelineCapacityExceeded

    var errorDescription: String? {
        switch self {
        case .connectionFailed:
            AppText.openAIRealtimeConnectionFailed
        case .timelineCapacityExceeded:
            AppText.openAIInvalidResponse
        }
    }
}

private struct RealtimeTimelineRetentionResult {
    let transcripts: [String]
    let didOverflow: Bool

    static let empty = RealtimeTimelineRetentionResult(
        transcripts: [],
        didOverflow: false
    )
}

private struct RealtimeTimelineCompletion {
    let didOverflow: Bool

    static let empty = RealtimeTimelineCompletion(
        didOverflow: false
    )
}

private struct RealtimeTimelineItem {
    var previousItemID: String?
    var carriesInputTranscript: Bool
    let registrationOrder: Int
    var hasLifecycleMetadata: Bool
    var isTerminal = false
    var completedText: String?
    var terminalAt: Date?
}

private extension OpenAIRealtimeTranscriber.OutputMode {
    var audioAppendEventType: String {
        switch self {
        case .transcription:
            "input_audio_buffer.append"
        case .translationOnly:
            "session.input_audio_buffer.append"
        }
    }
}

private extension LanguageOption {
    var openAILanguageCode: String {
        String(id.prefix(2))
    }
}
