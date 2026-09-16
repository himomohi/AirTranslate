import AVFoundation
import Foundation

struct NariTranscriptUpdate: Equatable, Sendable {
    let itemID: String
    let text: String
    let isFinal: Bool
    let languageCode: String?
    let revision: Int?
}

// 실제 WebSocket과 테스트 연결이 동일한 송수신·종료 경로를 사용한다.
protocol NariWebSocketConnection: Sendable {
    func resume()
    func send(_ text: String) async throws
    func receive() async throws -> Data
    func close()
}

private final class NariURLSessionConnection: NariWebSocketConnection, @unchecked Sendable {
    private let session: URLSession
    private let socket: URLSessionWebSocketTask

    init(request: URLRequest) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        session = URLSession(configuration: configuration, delegate: NariRejectRedirects(), delegateQueue: nil)
        socket = session.webSocketTask(with: request)
        socket.maximumMessageSize = NariRealtimeTranscriber.maximumMessageBytes
    }

    func resume() { socket.resume() }
    func send(_ text: String) async throws { try await socket.send(.string(text)) }
    func receive() async throws -> Data {
        switch try await socket.receive() {
        case .string(let text): Data(text.utf8)
        case .data(let data): data
        @unknown default: throw NariTranscriptionError.invalidResponse
        }
    }
    func close() {
        socket.cancel(with: .normalClosure, reason: nil)
        session.invalidateAndCancel()
    }
}

private final class NariRejectRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        // 다른 호스트로 Authorization 헤더가 전달되지 않도록 리다이렉트를 거부한다.
        completionHandler(nil)
    }
}

final class NariRealtimeTranscriber: @unchecked Sendable {
    static let sampleRate = 16_000
    static let chunkBytes = 3_200 // 100 ms, PCM16 little-endian mono, WAV 헤더 없음.
    static let maximumMessageBytes = 128 * 1_024
    static let maximumPendingAudioChunks = 48

    typealias TranscriptHandler = @Sendable (NariTranscriptUpdate) async -> Void
    typealias ErrorHandler = @Sendable (Error) async -> Void
    typealias ConnectionFactory = @Sendable (URLRequest) -> any NariWebSocketConnection

    private enum Phase { case stopped, configuring, streaming, draining, failed }
    private let lock = NSLock()
    private let keyProvider: @Sendable () throws -> String?
    private let connectionFactory: ConnectionFactory
    private let setupTimeout: Duration
    private let finishTimeout: Duration
    private var phase = Phase.stopped
    private var generation = UUID()
    private var connection: (any NariWebSocketConnection)?
    private var sendTask: Task<Void, Never>?
    private var receiveTask: Task<Void, Never>?
    private var outbound: [String] = []
    private var pcmBuffer = Data()
    private var paused = false
    private var expectedModel = ""
    private var finishEventID: String?
    private var finishAcknowledged = false
    private var deliveriesInFlight = 0
    private var terminalError: NariTranscriptionError?
    private var ledger = NariTranscriptLedger()
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

    init(keyProvider: @escaping @Sendable () throws -> String? = { try NariAPIKeyStore.readAPIKey() },
         connectionFactory: @escaping ConnectionFactory = { NariURLSessionConnection(request: $0) },
         setupTimeout: Duration = .seconds(8), finishTimeout: Duration = .seconds(15)) {
        self.keyProvider = keyProvider
        self.connectionFactory = connectionFactory
        self.setupTimeout = setupTimeout
        self.finishTimeout = finishTimeout
    }

    func start(model: NariTranscriptionModel, sourceLanguage: LanguageOption,
               autoDetectLanguage: Bool) async throws {
        stop()
        guard model.canStart else { throw NariTranscriptionError.configuration }
        let key: String
        do { key = try keyProvider()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" }
        catch { throw NariTranscriptionError.missingKey }
        let request = try Self.request(key: key)
        let configuration = try Self.configurationMessage(model: model.rawValue,
            language: autoDetectLanguage ? nil : sourceLanguage.id.split(separator: "-").first.map(String.init))
        let socket = connectionFactory(request)
        let token = lock.withLock {
            let token = generation
            connection = socket
            expectedModel = model.rawValue
            phase = .configuring
            paused = false
            terminalError = nil
            socket.resume()
            receiveTask = Task { [weak self] in await self?.receiveLoop(socket, generation: token) }
            enqueueLocked(configuration, generation: token)
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
                    guard ContinuousClock.now < deadline else { throw NariTranscriptionError.setupTimeout }
                    try await Task.sleep(for: .milliseconds(10))
                }
            } catch {
                if error is CancellationError { stop(generation: token) }
                else { fail(error as? NariTranscriptionError ?? .connection, generation: token) }
                throw error
            }
        } onCancel: { self.stop(generation: token) }
    }

    func append(_ sampleBuffer: CMSampleBuffer) {
        var failure: (NariTranscriptionError, UUID)?
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
                    enqueueLocked(Self.audioMessage(pcmBuffer), generation: generation)
                    pcmBuffer.removeAll(keepingCapacity: false)
                }
                let eventID = UUID().uuidString
                finishEventID = eventID
                enqueueLocked(Self.commitMessage(eventID: eventID), generation: generation)
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
                        return finishAcknowledged && ledger.isDrained && deliveriesInFlight == 0
                    }
                    if done {
                        stop(generation: token)
                        return
                    }
                    guard ContinuousClock.now < deadline else { throw NariTranscriptionError.finishTimeout }
                    try await Task.sleep(for: .milliseconds(10))
                }
            } catch {
                if error is CancellationError { stop(generation: token) }
                else { fail(error as? NariTranscriptionError ?? .connection, generation: token) }
                throw error
            }
        } onCancel: { self.stop(generation: token) }
    }

    func stop() { stop(generation: nil) }

    private func stop(generation token: UUID?) {
        let socket: (any NariWebSocketConnection)? = lock.withLock {
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
            ledger = NariTranscriptLedger()
            finishEventID = nil
            finishAcknowledged = false
            deliveriesInFlight = 0
            terminalError = nil
            let socket = connection
            connection = nil
            return socket
        }
        socket?.close()
    }

    private func appendPCMLocked(_ pcm: Data) -> (NariTranscriptionError, UUID)? {
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
            enqueueLocked(Self.audioMessage(chunk), generation: generation)
        }
        return nil
    }

    private func enqueueLocked(_ message: String, generation token: UUID) {
        outbound.append(message)
        guard sendTask == nil, let socket = connection else { return }
        sendTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                let next: String? = self.lock.withLock {
                    guard self.generation == token, self.phase != .stopped, self.phase != .failed else { return nil }
                    guard !self.outbound.isEmpty else {
                        self.sendTask = nil
                        return nil
                    }
                    return self.outbound.removeFirst()
                }
                guard let next else { return }
                do { try await socket.send(next) }
                catch {
                    self.fail(.connection, generation: token)
                    return
                }
            }
        }
    }

    private func receiveLoop(_ socket: any NariWebSocketConnection, generation token: UUID) async {
        do {
            while !Task.isCancelled {
                let data = try await socket.receive()
                let event = try NariServerEvent.parse(data)
                let delivery: (TranscriptHandler?, [NariTranscriptUpdate]) = try lock.withLock {
                    guard generation == token, phase != .stopped, phase != .failed else { return (nil, []) }
                    if case .configured(let model) = event {
                        guard phase == .configuring, model == expectedModel else { throw NariTranscriptionError.invalidResponse }
                        phase = .streaming
                        return (nil, [])
                    }
                    if case .failure(let error) = event { throw error }
                    guard phase == .streaming || phase == .draining else { throw NariTranscriptionError.invalidResponse }
                    let updates = try ledger.apply(event)
                    switch event {
                    case .committed(_, _, let clientID), .commitEmpty(let clientID):
                        if let finishEventID, clientID == finishEventID { finishAcknowledged = true }
                    default: break
                    }
                    deliveriesInFlight += updates.count
                    return (transcriptHandler, updates)
                }
                for update in delivery.1 {
                    guard lock.withLock({ generation == token && phase != .stopped && phase != .failed }) else { return }
                    let namespaced = NariTranscriptUpdate(itemID: "\(token.uuidString):\(update.itemID)",
                        text: update.text, isFinal: update.isFinal, languageCode: update.languageCode, revision: update.revision)
                    await delivery.0?(namespaced)
                    lock.withLock {
                        if generation == token { deliveriesInFlight -= 1 }
                    }
                }
            }
        } catch {
            fail(error as? NariTranscriptionError ?? .connection, generation: token)
        }
    }

    private func fail(_ error: NariTranscriptionError, generation token: UUID) {
        let failure: ((any NariWebSocketConnection)?, ErrorHandler?)? = lock.withLock {
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

    static func request(key: String) throws -> URLRequest {
        guard !key.isEmpty, key.utf8.allSatisfy({ $0 >= 0x21 && $0 <= 0x7E }) else {
            throw NariTranscriptionError.missingKey
        }
        var request = URLRequest(url: URL(string: "wss://api.narilabs.com/v1/realtime?intent=transcription")!)
        request.timeoutInterval = 15
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        return request
    }

    static func configurationMessage(model: String, language: String?) throws -> String {
        let models = ["qwen3-asr", "qwen3-asr-fast"]
        guard models.contains(model) else { throw NariTranscriptionError.configuration }
        var session: [String: Any] = ["model": model, "turn_detection": [
            "type": "server_vad", "threshold": 0.5, "prefix_padding_ms": 300, "silence_duration_ms": 500
        ]]
        if let language {
            guard NariServerEvent.languages.contains(language) else { throw NariTranscriptionError.configuration }
            session["language"] = language
        }
        let data = try JSONSerialization.data(withJSONObject: ["type": "session.configure", "session": session], options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }

    private static func audioMessage(_ data: Data) -> String {
        "{\"type\":\"input_audio_buffer.append\",\"audio\":\"\(data.base64EncodedString())\"}"
    }
    private static func commitMessage(eventID: String) -> String {
        "{\"type\":\"input_audio_buffer.commit\",\"event_id\":\"\(eventID)\"}"
    }
}

// 완료 순서는 committed의 연결 관계를 따른다. revision을 델타로 이어 붙이지 않는다.
struct NariTranscriptLedger {
    static let maximumPendingItems = 256
    private struct Item {
        var revision = 0
        var publishedRevision = 0
        var partial: NariTranscriptUpdate?
        let registration: Int
        var committed = false
        var previous: String?
        var completed: NariTranscriptUpdate?
    }
    private var items: [String: Item] = [:]
    private var retired = Set<String>()
    private var retiredOrder: [String] = []
    private var registration = 0
    var isDrained: Bool { items.isEmpty }

    mutating func apply(_ event: NariServerEvent) throws -> [NariTranscriptUpdate] {
        switch event {
        case .partial(let id, let text, let revision):
            guard !retired.contains(id) else { return [] }
            try register(id)
            if items[id]!.completed == nil, revision > items[id]!.revision {
                items[id]!.revision = revision
                items[id]!.partial = .init(itemID: id, text: text, isFinal: false, languageCode: nil, revision: revision)
            }
        case .completed(let id, let text, let language):
            guard !retired.contains(id) else { return [] }
            try register(id)
            if items[id]!.completed == nil {
                items[id]!.completed = .init(itemID: id, text: text, isFinal: true, languageCode: language, revision: nil)
            }
        case .committed(let id, let previous, _):
            guard !retired.contains(id) else { return [] }
            guard id != previous else { throw NariTranscriptionError.invalidResponse }
            try register(id)
            if items[id]!.committed, items[id]!.previous != previous { throw NariTranscriptionError.invalidResponse }
            items[id]!.committed = true
            items[id]!.previous = previous
        case .speechStarted(let id):
            if !retired.contains(id) { try register(id) }
        default: break
        }
        var updates: [NariTranscriptUpdate] = []
        while let entry = items.first(where: {
            $0.value.committed && $0.value.completed != nil && ($0.value.previous == nil || retired.contains($0.value.previous!))
        }) {
            updates.append(entry.value.completed!)
            items.removeValue(forKey: entry.key)
            retired.insert(entry.key)
            retiredOrder.append(entry.key)
            if retiredOrder.count > Self.maximumPendingItems {
                retired.remove(retiredOrder.removeFirst())
            }
        }
        // 앞선 발화가 남아 있으면 다음 발화의 가설을 먼저 표시하지 않는다.
        if let first = items.min(by: { $0.value.registration < $1.value.registration }),
           first.value.completed == nil, let partial = first.value.partial,
           first.value.revision > first.value.publishedRevision {
            updates.append(partial)
            items[first.key]!.publishedRevision = first.value.revision
        }
        return updates
    }

    private mutating func register(_ id: String) throws {
        guard items[id] == nil else { return }
        guard items.count < Self.maximumPendingItems else { throw NariTranscriptionError.backlog }
        registration += 1
        items[id] = Item(registration: registration)
    }
}

enum NariServerEvent: Sendable {
    case configured(String)
    case partial(String, String, Int)
    case completed(String, String, String?)
    case committed(String, String?, String?)
    case commitEmpty(String?)
    case speechStarted(String)
    case failure(NariTranscriptionError)
    case ignored

    static let languages: Set<String> = ["ar", "cs", "da", "de", "el", "en", "es", "fa", "fi", "fil", "fr", "hi", "hu", "id", "it", "ja", "ko", "mk", "ms", "nl", "pl", "pt", "ro", "ru", "sv", "th", "tr", "vi", "yue", "zh"]

    static func parse(_ data: Data) throws -> NariServerEvent {
        guard data.count <= NariRealtimeTranscriber.maximumMessageBytes,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else { throw NariTranscriptionError.invalidResponse }
        func itemID() throws -> String {
            guard let id = json["item_id"] as? String, !id.isEmpty, id.utf8.count <= 512 else {
                throw NariTranscriptionError.invalidResponse
            }
            return id
        }
        func transcript() throws -> String {
            guard let text = json["transcript"] as? String else { throw NariTranscriptionError.invalidResponse }
            return text
        }
        switch type {
        case "session.configured":
            guard let session = json["session"] as? [String: Any], let model = session["model"] as? String else {
                throw NariTranscriptionError.invalidResponse
            }
            return .configured(model)
        case "transcript.partial":
            guard let revision = json["revision"] as? Int, revision > 0 else { throw NariTranscriptionError.invalidResponse }
            return try .partial(itemID(), transcript(), revision)
        case "transcript.completed":
            let language = json["language"] as? String
            guard json["language"] is NSNull || language.map({ languages.contains($0) }) == true else {
                throw NariTranscriptionError.invalidResponse
            }
            return try .completed(itemID(), transcript(), language)
        case "input_audio_buffer.committed":
            guard json["previous_item_id"] is NSNull || json["previous_item_id"] is String else {
                throw NariTranscriptionError.invalidResponse
            }
            return try .committed(itemID(), json["previous_item_id"] as? String, json["client_event_id"] as? String)
        case "input_audio_buffer.commit_empty": return .commitEmpty(json["client_event_id"] as? String)
        case "input_audio_buffer.speech_started": return try .speechStarted(itemID())
        case "error":
            let code = (json["error"] as? [String: Any])?["code"] as? String
            return .failure(NariTranscriptionError.serverCode(code))
        default: return .ignored
        }
    }
}

enum NariTranscriptionError: LocalizedError, Equatable, Sendable {
    case configuration, missingKey, audioFormat, backlog, connection, invalidResponse
    case setupTimeout, finishTimeout, authentication, quota, credits, partnerAccess, sessionExpired, serviceUnavailable

    static func serverCode(_ code: String?) -> Self {
        switch code {
        case "INVALID_API_KEY": .authentication
        case "FREE_DAILY_LIMIT_EXCEEDED", "CONCURRENCY_LIMIT_EXCEEDED", "UPSTREAM_RATE_LIMITED": .quota
        case "INSUFFICIENT_CREDITS": .credits
        case "PARTNER_ACCESS_REQUIRED": .partnerAccess
        case "SESSION_IDLE_TIMEOUT": .sessionExpired
        case "SESSION_SETUP_TIMEOUT": .setupTimeout
        case "INVALID_REQUEST", "MODEL_NOT_FOUND", "SESSION_CONFIGURATION_LOCKED": .configuration
        default: .serviceUnavailable
        }
    }

    var errorDescription: String? {
        switch self {
        case .configuration: AppText.localized(english: "Check the Nari model and source language settings.", korean: "Nari 모델과 원문 언어 설정을 확인하세요.")
        case .missingKey: AppText.localized(english: "Save your Nari API key in API Keys settings.", korean: "API 키 설정에서 Nari API 키를 저장하세요.")
        case .audioFormat: AppText.localized(english: "Nari requires 16 kHz mono PCM audio.", korean: "Nari 입력은 16 kHz 모노 PCM 오디오여야 합니다.")
        case .backlog: AppText.localized(english: "Nari transcription could not keep up. Capture stopped at the queue limit. Restart when ready.", korean: "Nari 전사가 입력보다 느려 대기열 한도에서 중지했습니다. 준비되면 다시 시작하세요.")
        case .connection: AppText.localized(english: "Nari connection was interrupted. Check your network and API key, then restart.", korean: "Nari 연결이 끊겼습니다. 네트워크와 API 키를 확인하고 다시 시작하세요.")
        case .invalidResponse: AppText.localized(english: "Nari returned an invalid transcription response. Restart the session.", korean: "Nari 전사 응답 형식이 올바르지 않습니다. 세션을 다시 시작하세요.")
        case .setupTimeout: AppText.localized(english: "Nari session setup timed out. Check your connection and restart.", korean: "Nari 세션 준비 시간이 초과되었습니다. 연결을 확인하고 다시 시작하세요.")
        case .finishTimeout: AppText.localized(english: "Nari did not confirm the last utterance in time. The final text may be incomplete.", korean: "Nari가 마지막 발화를 제한 시간 안에 확정하지 못했습니다. 마지막 텍스트가 누락될 수 있습니다.")
        case .authentication: AppText.localized(english: "Nari rejected the API key. Check it in API Keys settings.", korean: "Nari API 키 인증에 실패했습니다. API 키 설정에서 확인하세요.")
        case .quota: AppText.localized(english: "Nari usage or concurrency limit reached. Check your allowance before restarting.", korean: "Nari 사용량 또는 동시 연결 한도에 도달했습니다. 할당량을 확인한 뒤 다시 시작하세요.")
        case .credits: AppText.localized(english: "Nari requires more credits for this GA model. Check your balance before restarting.", korean: "이 Nari GA 모델을 사용할 크레딧이 부족합니다. 잔액을 확인한 뒤 다시 시작하세요.")
        case .partnerAccess: AppText.localized(english: "This Nari GA model is not available to the current organization. Check Nari account access.", korean: "현재 Nari 조직에서 이 GA 모델을 사용할 수 없습니다. Nari 계정 접근 권한을 확인하세요.")
        case .sessionExpired: AppText.localized(english: "Nari closed the idle session. Restart when ready to send audio.", korean: "Nari가 오디오 입력이 없는 세션을 종료했습니다. 준비되면 다시 시작하세요.")
        case .serviceUnavailable: AppText.localized(english: "Nari is temporarily unavailable. Try starting again later.", korean: "Nari 서비스를 사용할 수 없습니다. 잠시 후 다시 시작하세요.")
        }
    }
}
