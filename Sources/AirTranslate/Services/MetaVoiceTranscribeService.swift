import AVFoundation
import CoreMedia
import Foundation

protocol MetaVoiceTranscribeServiceDelegate: AnyObject {
    func metaVoiceTranscribeService(_ service: MetaVoiceTranscribeService, didStartTurn turnId: Int32)
    func metaVoiceTranscribeService(_ service: MetaVoiceTranscribeService, didReceivePartialTranscript text: String)
    func metaVoiceTranscribeService(_ service: MetaVoiceTranscribeService, didLabelSpeaker label: String)
    func metaVoiceTranscribeService(
        _ service: MetaVoiceTranscribeService,
        didCompleteTurn turnId: Int32,
        transcript: String
    )
    func metaVoiceTranscribeService(_ service: MetaVoiceTranscribeService, didFail error: Error)
}

enum MetaVoiceServerEvent: Equatable, Sendable {
    case acknowledgement(sessionId: String)
    case speechStart(turnId: Int32, audioProcessedMs: Int?)
    case transcript(text: String, final: Bool, audioProcessedMs: Int?)
    case speaker(label: String, audioProcessedMs: Int?)
    case speechEnd(turnId: Int32, audioProcessedMs: Int?)
    case speechComplete(turnId: Int32, transcript: String, audioProcessedMs: Int?)
    case audioProgress(audioProcessedMs: Int?)
    case error(message: String, sessionId: String?)
}

struct MetaTurn: Equatable, Sendable {
    let turnId: Int32
    var transcript: String
    var speakerLabel: String?
    var isComplete: Bool
}

enum MetaTurnUpdate: Equatable, Sendable {
    case started(turnId: Int32)
    case partial(turnId: Int32, transcript: String, speakerLabel: String?)
    case speaker(turnId: Int32, label: String)
    case completed(turn: MetaTurn)
}

struct MetaTurnAssembler: Sendable {
    private(set) var turns: [Int32: MetaTurn] = [:]
    private(set) var activeTurnId: Int32?

    mutating func apply(_ event: MetaVoiceServerEvent) -> MetaTurnUpdate? {
        switch event {
        case let .speechStart(turnId, _):
            turns[turnId] = MetaTurn(
                turnId: turnId,
                transcript: "",
                speakerLabel: nil,
                isComplete: false
            )
            activeTurnId = turnId
            return .started(turnId: turnId)
        case let .transcript(text, _, _):
            guard let turnId = activeTurnId else { return nil }
            var turn = turns[turnId] ?? MetaTurn(
                turnId: turnId,
                transcript: "",
                speakerLabel: nil,
                isComplete: false
            )
            turn.transcript = text
            turns[turnId] = turn
            return .partial(turnId: turnId, transcript: text, speakerLabel: turn.speakerLabel)
        case let .speaker(label, _):
            guard let turnId = activeTurnId else { return nil }
            var turn = turns[turnId] ?? MetaTurn(
                turnId: turnId,
                transcript: "",
                speakerLabel: nil,
                isComplete: false
            )
            turn.speakerLabel = label
            turns[turnId] = turn
            return .speaker(turnId: turnId, label: label)
        case let .speechComplete(turnId, transcript, _):
            var turn = turns[turnId] ?? MetaTurn(
                turnId: turnId,
                transcript: "",
                speakerLabel: nil,
                isComplete: false
            )
            turn.transcript = transcript
            turn.isComplete = true
            turns[turnId] = turn
            if activeTurnId == turnId {
                activeTurnId = nil
            }
            return .completed(turn: turn)
        case .acknowledgement, .speechEnd, .audioProgress, .error:
            return nil
        }
    }
}

final class MetaVoiceTranscribeService: @unchecked Sendable {
    private static let inputAudioSampleRate = 24_000
    private static let bytesPerPCM16Sample = 2
    private static let maxAudioChunkMilliseconds = 80
    private static let maxPCM16AudioChunkByteCount = inputAudioSampleRate
        * bytesPerPCM16Sample
        * maxAudioChunkMilliseconds
        / 1_000
    private static let maxPendingAudioSendCount = 48
    private static let connectionTimeoutMilliseconds = 10_000
    private static let maxPreHandshakeAudioSeconds = 3
    static let maxPreHandshakeAudioByteCount = inputAudioSampleRate
        * bytesPerPCM16Sample
        * maxPreHandshakeAudioSeconds
    private static let encoder = JSONEncoder()

    var delegate: MetaVoiceTranscribeServiceDelegate? {
        get { withStateLock { serviceDelegate } }
        set { withStateLock { serviceDelegate = newValue } }
    }

    var onAudioTransportDegraded: (@Sendable (RealtimeAudioTransportDegradation) -> Void)? {
        get { withStateLock { audioTransportDegradationHandler } }
        set { withStateLock { audioTransportDegradationHandler = newValue } }
    }

    var onSessionClosed: (@Sendable (Int, String?) -> Void)? {
        get { withStateLock { sessionClosedHandler } }
        set { withStateLock { sessionClosedHandler = newValue } }
    }

    private let stateLock = NSLock()
    private let conversionLock = NSLock()
    private let sendQueue = DispatchQueue(label: "AirTranslate.MetaVoiceTranscribeService.send", qos: .userInitiated)
    private let handshakeWaiters = LockConditionWaiters()
    private weak var serviceDelegate: MetaVoiceTranscribeServiceDelegate?
    private var urlSession: URLSession?
    private var webSocketTask: URLSessionWebSocketTask?
    private var connectionObserver: MetaVoiceWebSocketConnectionObserver?
    private var receiveTask: Task<Void, Never>?
    private var connectionGeneration: UInt64 = 0
    private var isPaused = false
    private var isHandshakeComplete = false
    private var setupError: Error?
    private var pendingAudioSendCount = 0
    private var droppedAudioChunkCount = 0
    private var droppedAudioByteCount = 0
    private var lastAudioDropPhase = RealtimeAudioDropPhase.sendWindow
    private var audioTransportDegradationHandler:
        (@Sendable (RealtimeAudioTransportDegradation) -> Void)?
    private var sessionClosedHandler: (@Sendable (Int, String?) -> Void)?
    private var preHandshakeAudioChunks: [Data] = []
    private var preHandshakeAudioByteCount = 0
    private var turnAssembler = MetaTurnAssembler()

    func start(
        model: MetaTranscriptionModel,
        sourceLanguage _: LanguageOption,
        usesSpeakerLabels: Bool,
        languageBias: [String]?,
        keywords: [String]
    ) async throws {
        stop()

        guard model.isEnabled else { return }
        guard let apiKey = try MetaAPIKeyStore.readAPIKey(), !apiKey.isEmpty else {
            throw MetaVoiceTranscribeError.missingAPIKey
        }
        guard var components = URLComponents(string: "wss://api.meta.ai/v1/asr/realtime") else {
            throw MetaVoiceTranscribeError.invalidResponse
        }
        components.queryItems = [URLQueryItem(name: "sessionId", value: UUID().uuidString)]
        guard let url = components.url else {
            throw MetaVoiceTranscribeError.invalidResponse
        }

        let observer = MetaVoiceWebSocketConnectionObserver()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        let session = URLSession(configuration: configuration, delegate: observer, delegateQueue: nil)
        let socket = session.webSocketTask(with: url)
        let installation = withStateLock {
            let displaced = (receiveTask, webSocketTask, urlSession)
            connectionGeneration &+= 1
            self.urlSession = session
            webSocketTask = socket
            connectionObserver = observer
            receiveTask = nil
            isPaused = false
            isHandshakeComplete = false
            setupError = nil
            pendingAudioSendCount = 0
            droppedAudioChunkCount = 0
            droppedAudioByteCount = 0
            lastAudioDropPhase = .sendWindow
            preHandshakeAudioChunks = []
            preHandshakeAudioByteCount = 0
            turnAssembler = MetaTurnAssembler()
            return (
                generation: connectionGeneration,
                displacedReceiveTask: displaced.0,
                displacedSocket: displaced.1,
                displacedSession: displaced.2
            )
        }
        installation.displacedReceiveTask?.cancel()
        installation.displacedSocket?.cancel(with: .goingAway, reason: nil)
        installation.displacedSession?.finishTasksAndInvalidate()

        let generation = installation.generation
        observer.onClose = { [weak self, weak socket] code, reason in
            guard let self, let socket else { return }
            self.handleSessionClosed(
                code: code,
                reason: reason,
                connectionGeneration: generation,
                webSocketTask: socket
            )
        }
        socket.resume()

        do {
            try await observer.waitForOpen(timeoutMilliseconds: Self.connectionTimeoutMilliseconds)
        } catch {
            guard isCurrentConnection(generation, webSocketTask: socket) else {
                throw CancellationError()
            }
            throw Self.publicConnectionError(from: error)
        }

        let task = Task<Void, Never> { [weak self] in
            guard let self else { return }
            await receiveLoop(webSocketTask: socket, connectionGeneration: generation)
        }
        let installed = withStateLock {
            guard isCurrentConnectionLocked(generation, webSocketTask: socket) else { return false }
            receiveTask = task
            return true
        }
        guard installed else {
            task.cancel()
            throw CancellationError()
        }

        let handshake = try Self.encodedHandshake(
            accessToken: apiKey,
            model: model,
            usesSpeakerLabels: usesSpeakerLabels,
            languageBias: languageBias,
            keywords: keywords
        )
        guard let handshakeText = String(data: handshake, encoding: .utf8) else {
            throw MetaVoiceTranscribeError.invalidResponse
        }
        try await send(handshakeText, connectionGeneration: generation)
        try await waitForHandshakeComplete(connectionGeneration: generation)
    }

    func append(_ sampleBuffer: CMSampleBuffer) {
        let state = withStateLock {
            (
                isPaused: isPaused,
                hasSocket: webSocketTask != nil,
                generation: connectionGeneration
            )
        }
        guard !state.isPaused, state.hasSocket else { return }

        conversionLock.lock()
        let chunks = pcm16AudioChunks(from: sampleBuffer)
        conversionLock.unlock()
        sendOrBufferAudioChunks(chunks, connectionGeneration: state.generation)
    }

    func sendOrBufferAudioChunks(_ chunks: [Data]) {
        sendOrBufferAudioChunks(chunks, connectionGeneration: nil)
    }

    private func sendOrBufferAudioChunks(
        _ chunks: [Data],
        connectionGeneration expectedGeneration: UInt64?
    ) {
        guard !chunks.isEmpty else { return }
        stateLock.lock()
        if let expectedGeneration, !isCurrentConnectionLocked(expectedGeneration) {
            stateLock.unlock()
            return
        }
        guard isHandshakeComplete else {
            let degradation = bufferPreHandshakeAudioChunksLocked(chunks)
            let callback = audioTransportDegradationHandler
            stateLock.unlock()
            if let degradation {
                callback?(degradation)
            }
            return
        }
        guard let socket = webSocketTask else {
            stateLock.unlock()
            return
        }
        let generation = connectionGeneration
        sendQueue.async { [weak self] in
            self?.sendAudioChunks(chunks, over: socket, connectionGeneration: generation)
        }
        stateLock.unlock()
    }

    private func sendAudioChunks(
        _ chunks: [Data],
        over socket: URLSessionWebSocketTask,
        connectionGeneration: UInt64
    ) {
        for chunk in chunks {
            guard reserveAudioSendSlot(
                audioByteCount: chunk.count,
                connectionGeneration: connectionGeneration
            ) else {
                continue
            }
            socket.send(.data(chunk)) { [weak self] error in
                guard let self else { return }
                self.releaseAudioSendSlot(connectionGeneration: connectionGeneration)
                guard let error else { return }
                self.notifyDelegate(connectionGeneration: connectionGeneration) {
                    $0.metaVoiceTranscribeService(
                        self,
                        didFail: Self.publicConnectionError(from: error)
                    )
                }
            }
        }
    }

    private func bufferPreHandshakeAudioChunksLocked(
        _ chunks: [Data]
    ) -> RealtimeAudioTransportDegradation? {
        var dropped = false
        for chunk in chunks {
            preHandshakeAudioChunks.append(chunk)
            preHandshakeAudioByteCount += chunk.count
        }
        while preHandshakeAudioByteCount > Self.maxPreHandshakeAudioByteCount,
              !preHandshakeAudioChunks.isEmpty {
            let removed = preHandshakeAudioChunks.removeFirst()
            preHandshakeAudioByteCount = max(0, preHandshakeAudioByteCount - removed.count)
            droppedAudioChunkCount += 1
            droppedAudioByteCount += removed.count
            lastAudioDropPhase = .preSetupBuffer
            dropped = true
        }
        return dropped ? audioTransportDegradationLocked(phase: .preSetupBuffer) : nil
    }

    var bufferedPreHandshakeAudioChunks: [Data] {
        withStateLock { preHandshakeAudioChunks }
    }

    func setPaused(_ isPaused: Bool) {
        withStateLock { self.isPaused = isPaused }
    }

    func stop() {
        let (displaced, waiters) = withStateLock {
            connectionGeneration &+= 1
            let displaced = (receiveTask, webSocketTask, urlSession)
            receiveTask = nil
            webSocketTask = nil
            connectionObserver = nil
            urlSession = nil
            isPaused = false
            isHandshakeComplete = false
            setupError = nil
            pendingAudioSendCount = 0
            droppedAudioChunkCount = 0
            droppedAudioByteCount = 0
            lastAudioDropPhase = .sendWindow
            preHandshakeAudioChunks = []
            preHandshakeAudioByteCount = 0
            turnAssembler = MetaTurnAssembler()
            return (displaced, handshakeWaiters.takeAllLocked())
        }
        LockConditionWaiters.resume(waiters)
        displaced.0?.cancel()
        guard let socket = displaced.1 else {
            displaced.2?.finishTasksAndInvalidate()
            return
        }
        socket.send(.string(#"{"type":"endStream"}"#)) { _ in
            Task {
                let timeoutTask = Task {
                    try? await Task.sleep(for: .seconds(5))
                    guard !Task.isCancelled else { return }
                    socket.cancel(with: .normalClosure, reason: nil)
                }
                while true {
                    do {
                        _ = try await socket.receive()
                    } catch {
                        break
                    }
                }
                timeoutTask.cancel()
                socket.cancel(with: .normalClosure, reason: nil)
                displaced.2?.finishTasksAndInvalidate()
            }
        }
    }

    nonisolated static func encodedHandshake(
        accessToken: String,
        model: MetaTranscriptionModel,
        usesSpeakerLabels: Bool,
        languageBias: [String]?,
        keywords: [String]
    ) throws -> Data {
        try encoder.encode(
            MetaVoiceHandshake(
                authorization: MetaVoiceAuthorization(accessToken: "Bearer \(accessToken)"),
                audioEncoding: "PCM_24KHZ",
                model: model.apiModelID,
                mode: usesSpeakerLabels ? "DIARIZATION" : "ENDPOINTING",
                partialMode: "CUMULATIVE",
                emitAudioProgress: false,
                keywords: keywords,
                languageBias: languageBias
            )
        )
    }

    static func decodeServerEvent(_ text: String) -> MetaVoiceServerEvent? {
        guard let data = text.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }
        if root["type"] == nil, let sessionId = root["sessionId"] as? String {
            return .acknowledgement(sessionId: sessionId)
        }
        guard let type = root["type"] as? String else { return nil }
        let audioProcessedMs = root["audioProcessedMs"] as? Int
        switch type {
        case "speechStart":
            guard let turnId = int32(root["turnId"]) else { return nil }
            return .speechStart(turnId: turnId, audioProcessedMs: audioProcessedMs)
        case "transcript":
            guard let transcript = root["transcript"] as? String else { return nil }
            return .transcript(
                text: transcript,
                final: root["final"] as? Bool ?? false,
                audioProcessedMs: audioProcessedMs
            )
        case "speaker":
            guard let label = root["label"] as? String else { return nil }
            return .speaker(label: label, audioProcessedMs: audioProcessedMs)
        case "speechEnd":
            guard let turnId = int32(root["turnId"]) else { return nil }
            return .speechEnd(turnId: turnId, audioProcessedMs: audioProcessedMs)
        case "speechComplete":
            guard let turnId = int32(root["turnId"]),
                  let transcript = root["transcript"] as? String else { return nil }
            return .speechComplete(
                turnId: turnId,
                transcript: transcript,
                audioProcessedMs: audioProcessedMs
            )
        case "audioProgress":
            return .audioProgress(audioProcessedMs: audioProcessedMs)
        case "error":
            guard let message = root["message"] as? String else { return nil }
            return .error(message: message, sessionId: root["sessionId"] as? String)
        default:
            return nil
        }
    }

    private static func int32(_ value: Any?) -> Int32? {
        if let value = value as? Int {
            return Int32(exactly: value)
        }
        if let value = value as? NSNumber {
            return Int32(exactly: value.int64Value)
        }
        return nil
    }

    func handleEventText(_ text: String) {
        handleEventText(text, connectionGeneration: nil)
    }

    func handleEventText(_ text: String, connectionGeneration: UInt64) {
        handleEventText(text, connectionGeneration: Optional(connectionGeneration))
    }

    private func handleEventText(_ text: String, connectionGeneration: UInt64?) {
        if let connectionGeneration,
           !withStateLock({ isCurrentGenerationLocked(connectionGeneration) }) {
            return
        }
        guard let event = Self.decodeServerEvent(text) else { return }
        if case .acknowledgement = event {
            markHandshakeComplete(connectionGeneration: connectionGeneration)
            return
        }
        if case .error = event {
            let error = MetaVoiceTranscribeError.server(AppText.metaInvalidResponse)
            recordSetupFailureIfNeeded(error, connectionGeneration: connectionGeneration)
            notifyDelegate(connectionGeneration: connectionGeneration) {
                $0.metaVoiceTranscribeService(self, didFail: error)
            }
            return
        }

        let update = withStateLock {
            turnAssembler.apply(event)
        }
        switch update {
        case let .started(turnId):
            notifyDelegate(connectionGeneration: connectionGeneration) {
                $0.metaVoiceTranscribeService(self, didStartTurn: turnId)
            }
        case let .partial(_, transcript, _):
            notifyDelegate(connectionGeneration: connectionGeneration) {
                $0.metaVoiceTranscribeService(self, didReceivePartialTranscript: transcript)
            }
        case let .speaker(_, label):
            notifyDelegate(connectionGeneration: connectionGeneration) {
                $0.metaVoiceTranscribeService(self, didLabelSpeaker: label)
            }
        case let .completed(turn):
            notifyDelegate(connectionGeneration: connectionGeneration) {
                $0.metaVoiceTranscribeService(
                    self,
                    didCompleteTurn: turn.turnId,
                    transcript: turn.transcript
                )
            }
        case nil:
            break
        }
    }

    private func receiveLoop(
        webSocketTask: URLSessionWebSocketTask,
        connectionGeneration: UInt64
    ) async {
        while !Task.isCancelled,
              isCurrentConnection(connectionGeneration, webSocketTask: webSocketTask) {
            do {
                let message = try await webSocketTask.receive()
                guard isCurrentConnection(
                    connectionGeneration,
                    webSocketTask: webSocketTask
                ) else {
                    return
                }
                switch message {
                case let .string(text):
                    handleEventText(text, connectionGeneration: connectionGeneration)
                case let .data(data):
                    if let text = String(data: data, encoding: .utf8) {
                        handleEventText(text, connectionGeneration: connectionGeneration)
                    }
                @unknown default:
                    continue
                }
            } catch {
                guard !Task.isCancelled,
                      isCurrentConnection(
                        connectionGeneration,
                        webSocketTask: webSocketTask
                      )
                else {
                    return
                }
                let observer = withStateLock { connectionObserver }
                let closed = await observer?.waitForCloseIfNeeded(timeoutMilliseconds: 50) ?? false
                guard !closed else { return }
                let publicError = Self.publicConnectionError(from: error)
                recordSetupFailureIfNeeded(
                    publicError,
                    connectionGeneration: connectionGeneration
                )
                notifyDelegate(connectionGeneration: connectionGeneration) {
                    $0.metaVoiceTranscribeService(self, didFail: publicError)
                }
                return
            }
        }
    }

    private func handleSessionClosed(
        code: Int,
        reason: String?,
        connectionGeneration: UInt64,
        webSocketTask: URLSessionWebSocketTask
    ) {
        let callback = withStateLock {
            guard isCurrentConnectionLocked(
                connectionGeneration,
                webSocketTask: webSocketTask
            ) else {
                return nil as (@Sendable (Int, String?) -> Void)?
            }
            return sessionClosedHandler
        }
        callback?(code, reason)
    }

    private func waitForHandshakeComplete(connectionGeneration: UInt64) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        try await handshakeWaiters.wait(
            lock: stateLock,
            deadline: deadline,
            timeoutError: MetaVoiceTranscribeError.setupTimedOut
        ) {
            guard isCurrentConnectionLocked(connectionGeneration) else { throw CancellationError() }
            if let setupError { throw setupError }
            return isHandshakeComplete
        }
    }

    private func markHandshakeComplete(connectionGeneration expectedGeneration: UInt64?) {
        stateLock.lock()
        if let expectedGeneration, !isCurrentGenerationLocked(expectedGeneration) {
            stateLock.unlock()
            return
        }
        let chunks = preHandshakeAudioChunks
        preHandshakeAudioChunks = []
        preHandshakeAudioByteCount = 0
        isHandshakeComplete = true
        setupError = nil
        let waiters = handshakeWaiters.takeAllLocked()
        if let socket = webSocketTask, !chunks.isEmpty {
            let generation = connectionGeneration
            sendQueue.async { [weak self] in
                self?.sendAudioChunks(chunks, over: socket, connectionGeneration: generation)
            }
        }
        stateLock.unlock()
        LockConditionWaiters.resume(waiters)
    }

    private func recordSetupFailureIfNeeded(
        _ error: Error,
        connectionGeneration expectedGeneration: UInt64?
    ) {
        let waiters = withStateLock { () -> [CheckedContinuation<Void, Error>] in
            if let expectedGeneration, !isCurrentGenerationLocked(expectedGeneration) {
                return []
            }
            if !isHandshakeComplete {
                setupError = error
                return handshakeWaiters.takeAllLocked()
            }
            return []
        }
        LockConditionWaiters.resume(waiters)
    }

    private func send(_ text: String, connectionGeneration: UInt64) async throws {
        var retryCount = 0
        while true {
            do {
                try await sendOnce(text, connectionGeneration: connectionGeneration)
                return
            } catch {
                guard retryCount < 40,
                      GeminiLiveTranslationService.isSocketNotConnectedError(error) else {
                    throw Self.publicConnectionError(from: error)
                }
                retryCount += 1
                try await Task.sleep(for: .milliseconds(min(100 + retryCount * 50, 500)))
            }
        }
    }

    private func sendOnce(_ text: String, connectionGeneration: UInt64) async throws {
        let socket = withStateLock {
            isCurrentConnectionLocked(connectionGeneration) ? webSocketTask : nil
        }
        guard let socket else { throw CancellationError() }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            socket.send(.string(text)) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    @discardableResult
    func reserveAudioSendSlot(audioByteCount: Int) -> Bool {
        reserveAudioSendSlot(audioByteCount: audioByteCount, connectionGeneration: nil)
    }

    func reserveAudioSendSlot(
        audioByteCount: Int,
        connectionGeneration expectedGeneration: UInt64?
    ) -> Bool {
        stateLock.lock()
        if let expectedGeneration, !isCurrentGenerationLocked(expectedGeneration) {
            stateLock.unlock()
            return false
        }
        guard pendingAudioSendCount < Self.maxPendingAudioSendCount else {
            droppedAudioChunkCount += 1
            droppedAudioByteCount += max(0, audioByteCount)
            lastAudioDropPhase = .sendWindow
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
        releaseAudioSendSlot(connectionGeneration: nil)
    }

    func releaseAudioSendSlot(connectionGeneration expectedGeneration: UInt64?) {
        withStateLock {
            if let expectedGeneration, !isCurrentGenerationLocked(expectedGeneration) {
                return
            }
            pendingAudioSendCount = max(0, pendingAudioSendCount - 1)
        }
    }

    var audioTransportDegradation: RealtimeAudioTransportDegradation? {
        withStateLock {
            guard droppedAudioChunkCount > 0 else { return nil }
            return audioTransportDegradationLocked(phase: lastAudioDropPhase)
        }
    }

    var isReadyForRealtimeInput: Bool {
        withStateLock { isHandshakeComplete }
    }

    var currentConnectionGeneration: UInt64 {
        withStateLock { connectionGeneration }
    }

    var pendingAudioSendSlotCount: Int {
        withStateLock { pendingAudioSendCount }
    }

    private func audioTransportDegradationLocked(
        phase: RealtimeAudioDropPhase
    ) -> RealtimeAudioTransportDegradation {
        RealtimeAudioTransportDegradation(
            provider: .meta,
            policy: phase == .preSetupBuffer ? .dropOldest : .dropNewest,
            phase: phase,
            droppedChunkCount: droppedAudioChunkCount,
            droppedAudioDuration: TimeInterval(droppedAudioByteCount)
                / TimeInterval(Self.inputAudioSampleRate * Self.bytesPerPCM16Sample),
            pendingSendCount: pendingAudioSendCount,
            pendingSendLimit: Self.maxPendingAudioSendCount
        )
    }

    private func pcm16AudioChunks(from sampleBuffer: CMSampleBuffer) -> [Data] {
        guard let audioData = AzureMAITranscriber.pcm16AudioData(from: sampleBuffer) else { return [] }
        guard audioData.count > Self.maxPCM16AudioChunkByteCount else {
            return [audioData]
        }
        return stride(
            from: 0,
            to: audioData.count,
            by: Self.maxPCM16AudioChunkByteCount
        ).map { offset in
            let end = min(offset + Self.maxPCM16AudioChunkByteCount, audioData.count)
            return Data(audioData[offset..<end])
        }
    }

    nonisolated static func publicConnectionError(from error: Error) -> Error {
        if error is CancellationError || error is MetaVoiceTranscribeError {
            return error
        }
        return MetaVoiceTranscribeError.connectionFailed
    }

    private func notifyDelegate(
        connectionGeneration expectedGeneration: UInt64?,
        _ notification: (MetaVoiceTranscribeServiceDelegate) -> Void
    ) {
        let delegate = withStateLock {
            if let expectedGeneration, !isCurrentGenerationLocked(expectedGeneration) {
                return nil as MetaVoiceTranscribeServiceDelegate?
            }
            return serviceDelegate
        }
        if let delegate {
            notification(delegate)
        }
    }

    private func isCurrentConnection(
        _ generation: UInt64,
        webSocketTask expectedSocket: URLSessionWebSocketTask? = nil
    ) -> Bool {
        withStateLock {
            isCurrentConnectionLocked(generation, webSocketTask: expectedSocket)
        }
    }

    private func isCurrentConnectionLocked(
        _ generation: UInt64,
        webSocketTask expectedSocket: URLSessionWebSocketTask? = nil
    ) -> Bool {
        guard isCurrentGenerationLocked(generation), let webSocketTask else { return false }
        guard let expectedSocket else { return true }
        return webSocketTask === expectedSocket
    }

    private func isCurrentGenerationLocked(_ generation: UInt64) -> Bool {
        connectionGeneration == generation
    }

    private func withStateLock<T>(_ body: () throws -> T) rethrows -> T {
        stateLock.lock()
        defer { stateLock.unlock() }
        return try body()
    }
}

final class MetaVoiceWebSocketConnectionObserver: NSObject, URLSessionWebSocketDelegate, URLSessionTaskDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Error>?
    private var completedResult: Result<Void, Error>?
    private var storedCloseInfo: (Int, String?)?
    private var closeWaiters: [CheckedContinuation<Void, Never>] = []
    var onClose: (@Sendable (Int, String?) -> Void)?

    var closeInfo: (Int, String?)? {
        lock.lock()
        defer { lock.unlock() }
        return storedCloseInfo
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }

    func waitForCloseIfNeeded(timeoutMilliseconds: Int) async -> Bool {
        if closeInfo != nil { return true }
        let timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(timeoutMilliseconds))
            guard !Task.isCancelled else { return }
            self?.wakeCloseWaiters()
        }
        defer { timeoutTask.cancel() }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            lock.lock()
            if storedCloseInfo != nil {
                lock.unlock()
                continuation.resume()
                return
            }
            closeWaiters.append(continuation)
            lock.unlock()
        }
        return closeInfo != nil
    }

    private func wakeCloseWaiters() {
        lock.lock()
        let waiters = closeWaiters
        closeWaiters.removeAll(keepingCapacity: true)
        lock.unlock()
        for waiter in waiters {
            waiter.resume()
        }
    }

    func waitForOpen(timeoutMilliseconds: Int) async throws {
        let timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(timeoutMilliseconds))
            guard !Task.isCancelled else { return }
            self?.resolve(.failure(MetaVoiceTranscribeError.setupTimedOut))
        }
        defer { timeoutTask.cancel() }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                register(continuation)
            }
        } onCancel: {
            resolve(.failure(CancellationError()))
        }
    }

    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol protocol: String?
    ) {
        resolve(.success(()))
    }

    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        let reasonText = reason.flatMap { String(data: $0, encoding: .utf8) }
        lock.lock()
        storedCloseInfo = (closeCode.rawValue, reasonText)
        let callback = onClose
        let waiters = closeWaiters
        closeWaiters.removeAll(keepingCapacity: true)
        lock.unlock()
        for waiter in waiters {
            waiter.resume()
        }
        callback?(closeCode.rawValue, reasonText)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        resolve(.failure(error))
    }

    func urlSession(_ session: URLSession, didBecomeInvalidWithError error: Error?) {
        resolve(.failure(error ?? MetaVoiceTranscribeError.setupTimedOut))
    }

    private func register(_ continuation: CheckedContinuation<Void, Error>) {
        lock.lock()
        if let completedResult {
            lock.unlock()
            continuation.resume(with: completedResult)
            return
        }
        self.continuation = continuation
        lock.unlock()
    }

    private func resolve(_ result: Result<Void, Error>) {
        lock.lock()
        guard completedResult == nil else {
            lock.unlock()
            return
        }
        completedResult = result
        let continuation = continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(with: result)
    }
}

private struct MetaVoiceHandshake: Encodable {
    let authorization: MetaVoiceAuthorization
    let audioEncoding: String
    let model: String
    let mode: String
    let partialMode: String
    let emitAudioProgress: Bool
    let keywords: [String]
    let languageBias: [String]?
}

private struct MetaVoiceAuthorization: Encodable {
    let accessToken: String
}

enum MetaVoiceTranscribeError: LocalizedError {
    case missingAPIKey
    case invalidResponse
    case setupTimedOut
    case connectionFailed
    case rateLimited
    case invalidRequest
    case server(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            AppText.metaAPIKeyMissing
        case .invalidResponse, .setupTimedOut:
            AppText.metaInvalidResponse
        case .connectionFailed:
            AppText.metaConnectionFailed
        case .rateLimited:
            AppText.metaRateLimited
        case .invalidRequest:
            AppText.metaInvalidRequest
        case let .server(message):
            message
        }
    }
}
