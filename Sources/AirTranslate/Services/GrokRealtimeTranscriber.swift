import AVFoundation
import Foundation

struct GrokTranscriptUpdate: Equatable, Sendable {
    let itemID: String
    let text: String
    let isFinal: Bool
    let languageCode: String?
    let revision: Int?
}

// 실제 WebSocket과 테스트 연결이 동일한 송수신·종료 경로를 사용한다.
protocol GrokWebSocketConnection: Sendable {
    func resume()
    func send(_ message: GrokClientMessage) async throws
    func receive() async throws -> Data
    func close()
}

private final class GrokURLSessionConnection: GrokWebSocketConnection, @unchecked Sendable {
    private let session: URLSession
    private let socket: URLSessionWebSocketTask

    init(request: URLRequest) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        session = URLSession(configuration: configuration, delegate: GrokRejectRedirects(), delegateQueue: nil)
        socket = session.webSocketTask(with: request)
        socket.maximumMessageSize = GrokRealtimeTranscriber.maximumMessageBytes
    }

    func resume() { socket.resume() }
    func send(_ message: GrokClientMessage) async throws { switch message {
        case .audio(let data): try await socket.send(.data(data))
        case .finish: try await socket.send(.string("{\"type\":\"audio.done\"}"))
        } }
    func receive() async throws -> Data {
        switch try await socket.receive() {
        case .string(let text): Data(text.utf8)
        case .data(let data): data
        @unknown default: throw GrokTranscriptionError.invalidResponse
        }
    }
    func close() {
        socket.cancel(with: .normalClosure, reason: nil)
        session.invalidateAndCancel()
    }
}

private final class GrokRejectRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        // 다른 호스트로 Authorization 헤더가 전달되지 않도록 리다이렉트를 거부한다.
        completionHandler(nil)
    }
}

final class GrokRealtimeTranscriber: @unchecked Sendable {
    static let sampleRate = 16_000
    static let chunkBytes = 3_200 // 100 ms, PCM16 little-endian mono, WAV 헤더 없음.
    static let maximumMessageBytes = 1_024 * 1_024
    static let maximumPendingAudioChunks = 48

    typealias TranscriptHandler = @Sendable (GrokTranscriptUpdate) async -> Void
    typealias ErrorHandler = @Sendable (Error) async -> Void
    typealias ConnectionFactory = @Sendable (URLRequest) -> any GrokWebSocketConnection

    private enum Phase { case stopped, configuring, streaming, draining, failed }
    private let lock = NSLock()
    private let keyProvider: @Sendable () throws -> String?
    private let connectionFactory: ConnectionFactory
    private let setupTimeout: Duration
    private let finishTimeout: Duration
    private var phase = Phase.stopped
    private var generation = UUID()
    private var connection: (any GrokWebSocketConnection)?
    private var sendTask: Task<Void, Never>?
    private var receiveTask: Task<Void, Never>?
    private var outbound: [GrokClientMessage] = []
    private var pcmBuffer = Data()
    private var paused = false
    private var finishAcknowledged = false
    private var deliveriesInFlight = 0
    private var terminalError: GrokTranscriptionError?
    private var ledger = GrokTranscriptLedger()
    private var transcriptHandler: TranscriptHandler?
    private var errorHandler: ErrorHandler?

    var onTranscript: TranscriptHandler? {
        get { lock.withLock { transcriptHandler } }
        set { lock.withLock { transcriptHandler = newValue } }
    }
    var onError: ErrorHandler? {
        get { lock.withLock { errorHandler } }
        set { lock.withLock { errorHandler = newValue } }
    }

    init(keyProvider: @escaping @Sendable () throws -> String? = { try GrokAPIKeyStore.readAPIKey() },
         connectionFactory: @escaping ConnectionFactory = { GrokURLSessionConnection(request: $0) },
         setupTimeout: Duration = .seconds(8), finishTimeout: Duration = .seconds(15)) {
        self.keyProvider = keyProvider
        self.connectionFactory = connectionFactory
        self.setupTimeout = setupTimeout
        self.finishTimeout = finishTimeout
    }

    func start(model: GrokTranscriptionModel, sourceLanguage: LanguageOption,
               autoDetectLanguage: Bool) async throws {
        stop()
        guard model.isEnabled else { throw GrokTranscriptionError.configuration }
        let key: String
        do { key = try keyProvider()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" }
        catch { throw GrokTranscriptionError.missingKey }
        let language = autoDetectLanguage ? nil : GrokTranscriptionModel.languageCode(for: sourceLanguage)
        if !autoDetectLanguage, language == nil { throw GrokTranscriptionError.configuration }
        let request = try Self.request(key: key, model: model, language: language)
        let socket = connectionFactory(request)
        let token = lock.withLock {
            let token = generation
            connection = socket
            phase = .configuring
            paused = false
            terminalError = nil
            socket.resume()
            receiveTask = Task { [weak self] in await self?.receiveLoop(socket, generation: token) }
            return token
        }
        try await withTaskCancellationHandler {
            do {
                let deadline = ContinuousClock.now.advanced(by: setupTimeout)
                while true {
                    try Task.checkCancellation()
                    let ready = try lock.withLock {
                        guard generation == token else { throw CancellationError() }
                        if let terminalError { throw terminalError }
                        return phase == .streaming
                    }
                    if ready { return }
                    guard ContinuousClock.now < deadline else { throw GrokTranscriptionError.setupTimeout }
                    try await Task.sleep(for: .milliseconds(10))
                }
            } catch {
                if error is CancellationError { stop(generation: token) }
                else { fail(error as? GrokTranscriptionError ?? .connection, generation: token) }
                throw error
            }
        } onCancel: { self.stop(generation: token) }
    }

    func append(_ sampleBuffer: CMSampleBuffer) {
        var failure: (GrokTranscriptionError, UUID)?
        lock.withLock {
            guard phase == .streaming, !paused else { return }
            // 두 캡처 입력은 이미 16 kHz 모노로 정규화되어 있다.
            guard let pcm = AzureMAITranscriber.pcm16(sampleBuffer), pcm.count.isMultiple(of: 2) else {
                failure = (.audioFormat, generation)
                paused = true
                return
            }
            failure = appendPCMLocked(pcm)
        }
        if let failure { fail(failure.0, generation: failure.1) }
    }

    // 캡처 라우팅을 유지한 채 pause 전 마지막 음성을 finish로 확정할 수 있다.
    // resume는 이전 finish가 끝난 뒤 start로 새 세션을 열어야 한다.
    func setPaused(_ value: Bool) { lock.withLock { paused = value } }

    func finish() async throws {
        let token: UUID? = lock.withLock {
            guard phase == .streaming || phase == .draining || phase == .failed else { return nil }
            if phase == .streaming {
                phase = .draining
                paused = true
                if !pcmBuffer.isEmpty {
                    enqueueLocked(.audio(pcmBuffer), generation: generation)
                    pcmBuffer.removeAll(keepingCapacity: false)
                }
                enqueueLocked(.finish, generation: generation)
            }
            return generation
        }
        guard let token else { return }
        try await withTaskCancellationHandler {
            do {
                let deadline = ContinuousClock.now.advanced(by: finishTimeout)
                while true {
                    try Task.checkCancellation()
                    let done = try lock.withLock {
                        guard generation == token else { throw CancellationError() }
                        if let terminalError { throw terminalError }
                        return finishAcknowledged && deliveriesInFlight == 0
                    }
                    if done {
                        stop(generation: token)
                        return
                    }
                    guard ContinuousClock.now < deadline else { throw GrokTranscriptionError.finishTimeout }
                    try await Task.sleep(for: .milliseconds(10))
                }
            } catch {
                if error is CancellationError { stop(generation: token) }
                else { fail(error as? GrokTranscriptionError ?? .connection, generation: token) }
                throw error
            }
        } onCancel: { self.stop(generation: token) }
    }

    func stop() { stop(generation: nil) }

    private func stop(generation token: UUID?) {
        let socket: (any GrokWebSocketConnection)? = lock.withLock {
            if let token, token != generation { return nil }
            generation = UUID()
            phase = .stopped
            paused = true
            sendTask?.cancel()
            receiveTask?.cancel()
            sendTask = nil
            receiveTask = nil
            outbound.removeAll()
            pcmBuffer.removeAll()
            ledger = GrokTranscriptLedger()
            finishAcknowledged = false
            deliveriesInFlight = 0
            terminalError = nil
            let socket = connection
            connection = nil
            return socket
        }
        socket?.close()
    }

    private func appendPCMLocked(_ pcm: Data) -> (GrokTranscriptionError, UUID)? {
        // 한 입력 버퍼가 비정상적으로 커도 큐 한도를 넘는 할당을 하지 않는다.
        guard pcm.count <= Self.chunkBytes * Self.maximumPendingAudioChunks,
              outbound.count + (pcmBuffer.count + pcm.count) / Self.chunkBytes <= Self.maximumPendingAudioChunks else {
            paused = true
            return (.backlog, generation)
        }
        pcmBuffer.append(pcm)
        while pcmBuffer.count >= Self.chunkBytes {
            let chunk = Data(pcmBuffer.prefix(Self.chunkBytes))
            pcmBuffer.removeFirst(Self.chunkBytes)
            enqueueLocked(.audio(chunk), generation: generation)
        }
        return nil
    }

    private func enqueueLocked(_ message: GrokClientMessage, generation token: UUID) {
        outbound.append(message)
        guard sendTask == nil, let socket = connection else { return }
        sendTask = Task { [weak self] in
            guard let self else { return }
            var nextAudioSend = ContinuousClock.now
            while !Task.isCancelled {
                let next: GrokClientMessage? = self.lock.withLock {
                    guard self.generation == token, self.phase != .stopped, self.phase != .failed else { return nil }
                    guard !self.outbound.isEmpty else {
                        self.sendTask = nil
                        return nil
                    }
                    return self.outbound.removeFirst()
                }
                guard let next else { return }
                do {
                    if case .audio(let data) = next {
                        try await Task.sleep(until: nextAudioSend, clock: .continuous)
                        try Task.checkCancellation()
                        guard self.lock.withLock({ self.generation == token && self.phase != .failed && self.phase != .stopped }) else { return }
                        try await socket.send(next)
                        nextAudioSend = ContinuousClock.now.advanced(by: .seconds(Double(data.count) / 32_000))
                    } else { try await socket.send(next) }
                }
                catch {
                    self.fail(.connection, generation: token)
                    return
                }
            }
        }
    }

    private func receiveLoop(_ socket: any GrokWebSocketConnection, generation token: UUID) async {
        do {
            while !Task.isCancelled {
                let data = try await socket.receive()
                let event = try GrokServerEvent.parse(data)
                let delivery: (TranscriptHandler?, [GrokTranscriptUpdate]) = try lock.withLock {
                    guard generation == token, phase != .stopped, phase != .failed else { return (nil, []) }
                    if case .created = event {
                        guard phase == .configuring else { throw GrokTranscriptionError.invalidResponse }
                        phase = .streaming
                        return (nil, [])
                    }
                    if case .failure(let error) = event { throw error }
                    guard phase == .streaming || phase == .draining else { throw GrokTranscriptionError.invalidResponse }
                    let updates = try ledger.apply(event)
                    if case .done = event {
                        guard phase == .draining else { throw GrokTranscriptionError.invalidResponse }
                        finishAcknowledged = true
                    }
                    deliveriesInFlight += updates.count
                    return (transcriptHandler, updates)
                }
                for update in delivery.1 {
                    guard lock.withLock({ generation == token && phase != .stopped && phase != .failed }) else { return }
                    let namespaced = GrokTranscriptUpdate(itemID: "\(token.uuidString):\(update.itemID)",
                        text: update.text, isFinal: update.isFinal, languageCode: update.languageCode, revision: update.revision)
                    await delivery.0?(namespaced)
                    lock.withLock {
                        if generation == token { deliveriesInFlight -= 1 }
                    }
                }
                if case .done = event { return }
            }
        } catch {
            fail(error as? GrokTranscriptionError ?? .connection, generation: token)
        }
    }

    private func fail(_ error: GrokTranscriptionError, generation token: UUID) {
        let failure: ((any GrokWebSocketConnection)?, ErrorHandler?)? = lock.withLock {
            guard generation == token, phase != .stopped, phase != .failed else { return nil }
            phase = .failed
            paused = true
            terminalError = error
            outbound.removeAll()
            pcmBuffer.removeAll()
            sendTask?.cancel()
            receiveTask?.cancel()
            let socket = connection
            connection = nil
            return (socket, errorHandler)
        }
        guard let failure else { return }
        failure.0?.close()
        Task { [weak self] in
            guard let self, self.lock.withLock({ self.generation == token && self.phase == .failed }) else { return }
            await failure.1?(error)
        }
    }

    static func request(key: String, model: GrokTranscriptionModel = .voiceTranscribe2, language: String? = nil) throws -> URLRequest {
        guard !key.isEmpty, key.utf8.allSatisfy({ $0 >= 0x21 && $0 <= 0x7E }) else {
            throw GrokTranscriptionError.missingKey
        }
        guard model.isEnabled, language == nil || GrokTranscriptionModel.supportedLanguageCodes.contains(language!) else {
            throw GrokTranscriptionError.configuration
        }
        var components = URLComponents(string: "wss://api.x.ai/v1/stt")!
        components.queryItems = [
            .init(name: "model", value: model.rawValue),
            .init(name: "sample_rate", value: "16000"),
            .init(name: "encoding", value: "pcm"),
            .init(name: "interim_results", value: "true"),
            .init(name: "endpointing", value: "400"),
        ]
        if let language { components.queryItems?.append(.init(name: "language", value: language)) }
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 15
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        return request
    }
}

enum GrokClientMessage: Equatable, Sendable {
    case audio(Data)
    case finish
}

struct GrokTranscriptLedger {
    private var turn = 0
    private var revision = 0
    private var chunks: [Double: String] = [:]
    private var lastPartial = ""
    private var finalizedUtterances: [String] = []
    private var finalizedBytes = 0
    private var finalizedThrough: Double = -1

    mutating func apply(_ event: GrokServerEvent) throws -> [GrokTranscriptUpdate] {
        switch event {
        case let .partial(text, isFinal, speechFinal, start, duration, language):
            guard start + duration > finalizedThrough else { return [] }
            revision += 1
            if speechFinal {
                // speech_final은 이미 이어 붙인 발화 전체다. 확정 청크를 다시 붙이지 않는다.
                return [try complete(text, through: start + duration, language: language)]
            }
            if isFinal {
                guard chunks[start] == nil else { return [] }
                guard chunks.count < 256 else { throw GrokTranscriptionError.backlog }
                chunks[start] = text
                lastPartial = ""
            } else {
                // 같은 시작 구간의 확정 청크보다 늦게 도착한 가설은 무시한다.
                guard chunks[start] == nil else { return [] }
                lastPartial = text
            }
            let assembled = Self.normalized((chunks.sorted { $0.key < $1.key }.map(\.value) + [lastPartial]).joined(separator: " "))
            guard assembled.utf8.count <= GrokRealtimeTranscriber.maximumMessageBytes else { throw GrokTranscriptionError.backlog }
            return [.init(itemID: String(turn), text: assembled, isFinal: false, languageCode: language, revision: revision)]
        case let .done(text, duration, language):
            // done은 세션 전체다. 이미 전달된 발화의 접두부를 제거해 마지막 발화만 확정한다.
            var remaining = Self.normalized(text)
            for utterance in finalizedUtterances {
                guard remaining.hasPrefix(utterance) else { throw GrokTranscriptionError.invalidResponse }
                remaining = String(remaining.dropFirst(utterance.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if remaining.isEmpty, chunks.isEmpty, lastPartial.isEmpty { return [] }
            return [try complete(remaining, through: duration, language: language)]
        default: return []
        }
    }

    private mutating func complete(_ text: String, through: Double, language: String?) throws -> GrokTranscriptUpdate {
        let normalized = Self.normalized(text)
        guard finalizedBytes + normalized.utf8.count <= GrokRealtimeTranscriber.maximumMessageBytes else { throw GrokTranscriptionError.backlog }
        let update = GrokTranscriptUpdate(itemID: String(turn), text: normalized, isFinal: true, languageCode: language, revision: nil)
        if !normalized.isEmpty { finalizedUtterances.append(normalized) }
        finalizedBytes += normalized.utf8.count
        finalizedThrough = max(finalizedThrough, through)
        chunks.removeAll(keepingCapacity: true)
        lastPartial = ""
        turn += 1
        revision = 0
        return update
    }

    private static func normalized(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}

enum GrokServerEvent: Sendable {
    case created
    case partial(String, Bool, Bool, Double, Double, String?)
    case done(String, Double, String?)
    case failure(GrokTranscriptionError)
    case ignored

    static func parse(_ data: Data) throws -> Self {
        guard data.count <= GrokRealtimeTranscriber.maximumMessageBytes,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else { throw GrokTranscriptionError.invalidResponse }
        func number(_ name: String) throws -> Double {
            guard let value = json[name] as? NSNumber,
                  CFGetTypeID(value) != CFBooleanGetTypeID(), value.doubleValue.isFinite,
                  value.doubleValue >= 0 else { throw GrokTranscriptionError.invalidResponse }
            return value.doubleValue
        }
        func boolean(_ name: String) throws -> Bool {
            guard let value = json[name] as? NSNumber, CFGetTypeID(value) == CFBooleanGetTypeID() else {
                throw GrokTranscriptionError.invalidResponse
            }
            return value.boolValue
        }
        let language = (json["language"] as? String)?.lowercased().replacingOccurrences(of: "_", with: "-").split(separator: "-").first.map(String.init)
        switch type {
        case "transcript.created": return .created
        case "transcript.partial":
            guard let text = json["text"] as? String else { throw GrokTranscriptionError.invalidResponse }
            let isFinal = try boolean("is_final"), speechFinal = try boolean("speech_final")
            guard !speechFinal || isFinal else { throw GrokTranscriptionError.invalidResponse }
            return try .partial(text, isFinal, speechFinal, number("start"), number("duration"), language)
        case "transcript.done":
            guard let text = json["text"] as? String else { throw GrokTranscriptionError.invalidResponse }
            return try .done(text, number("duration"), language)
        case "error":
            // message에는 원문·토큰 등이 포함될 수 있으므로 저장하거나 사용자에게 노출하지 않는다.
            return .failure(.serviceUnavailable)
        default: return .ignored
        }
    }
}

enum GrokTranscriptionError: LocalizedError, Equatable, Sendable {
    case configuration, missingKey, audioFormat, backlog, connection, invalidResponse
    case setupTimeout, finishTimeout, serviceUnavailable

    var errorDescription: String? {
        switch self {
        case .configuration: GrokCopy.languageUnsupported
        case .missingKey: GrokCopy.configurationRequired
        case .audioFormat: AppText.localized(english: "Grok requires 16 kHz mono PCM audio.", korean: "Grok 입력은 16 kHz 모노 PCM 오디오여야 합니다.", japanese: "Grokには16 kHzモノラルPCM音声が必要です。", chineseSimplified: "Grok 需要 16 kHz 单声道 PCM 音频。")
        case .backlog: AppText.localized(english: "Grok reached the transcription queue limit. Restart capture when ready.", korean: "Grok 전사 대기열 한도에 도달했습니다. 준비되면 캡처를 다시 시작하세요.", japanese: "Grokの文字起こしキューが上限に達しました。準備ができたら再開してください。", chineseSimplified: "Grok 转写队列已达上限。请在准备好后重新开始。")
        case .connection: GrokCopy.interrupted
        case .invalidResponse: AppText.localized(english: "Grok returned an inconsistent transcription response. Captions already received are preserved.", korean: "Grok 전사 응답이 일관되지 않습니다. 이미 받은 자막은 보존됩니다.", japanese: "Grokの文字起こし応答に不整合があります。受信済み字幕は保持されます。", chineseSimplified: "Grok 转写响应不一致。已收到的字幕会保留。")
        case .setupTimeout: AppText.localized(english: "Grok setup timed out. Check your network and API key.", korean: "Grok 연결 준비 시간이 초과되었습니다. 네트워크와 API 키를 확인하세요.", japanese: "Grokの接続準備がタイムアウトしました。ネットワークとAPIキーを確認してください。", chineseSimplified: "Grok 连接准备超时。请检查网络和 API 密钥。")
        case .finishTimeout: AppText.localized(english: "Grok did not finish in time. The last caption may be incomplete.", korean: "Grok이 제한 시간 안에 완료되지 않았습니다. 마지막 자막이 불완전할 수 있습니다.", japanese: "Grokが制限時間内に完了しませんでした。最後の字幕が不完全な可能性があります。", chineseSimplified: "Grok 未在时限内完成。最后的字幕可能不完整。")
        case .serviceUnavailable: AppText.localized(english: "Grok could not process the session. Check API access, quota and service status before restarting.", korean: "Grok이 세션을 처리하지 못했습니다. API 접근 권한·할당량·서비스 상태를 확인한 뒤 다시 시작하세요.", japanese: "Grokがセッションを処理できませんでした。API権限・利用枠・サービス状態を確認して再開してください。", chineseSimplified: "Grok 无法处理此会话。请检查 API 权限、配额和服务状态后重试。")
        }
    }
}
