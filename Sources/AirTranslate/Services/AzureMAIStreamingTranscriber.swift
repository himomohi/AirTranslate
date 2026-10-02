import AVFoundation
import Foundation

protocol AzureMAIWebSocketConnection: Sendable {
    func resume()
    func send(_ message: String) async throws
    func receive() async throws -> Data
    func close()
}

private final class AzureMAIURLSessionConnection: AzureMAIWebSocketConnection, @unchecked Sendable {
    private let session: URLSession
    private let socket: URLSessionWebSocketTask

    init(request: URLRequest, configuration: URLSessionConfiguration) {
        let config = configuration.copy() as! URLSessionConfiguration
        config.urlCache = nil
        config.httpCookieStorage = nil
        config.urlCredentialStorage = nil
        session = URLSession(configuration: config, delegate: AzureMAIRejectRedirects(), delegateQueue: nil)
        socket = session.webSocketTask(with: request)
        socket.maximumMessageSize = AzureMAIStreamingTranscriber.maximumMessageBytes
    }

    func resume() { socket.resume() }
    func send(_ message: String) async throws { try await socket.send(.string(message)) }
    func receive() async throws -> Data {
        switch try await socket.receive() {
        case .string(let text): Data(text.utf8)
        case .data(let data): data
        @unknown default: throw AzureMAIError.response
        }
    }
    func close() {
        socket.cancel(with: .normalClosure, reason: nil)
        session.invalidateAndCancel()
    }
}

private final class AzureMAIRejectRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        // 리소스 키를 다른 주소에 전달하지 않는다.
        completionHandler(nil)
    }
}

// Microsoft의 MAI Realtime 계약을 사용한다. 서버 VAD가 없어 오디오 3초마다 수동 확정한다.
// https://learn.microsoft.com/azure/ai-services/speech-service/mai-transcribe-2-streaming-realtime
final class AzureMAIStreamingTranscriber: @unchecked Sendable {
    static let sampleRate = 16_000
    static let chunkBytes = 3_200 // 100 ms PCM16 little-endian mono, WAV 헤더 없음.
    static let maximumMessageBytes = 128 * 1_024
    static let maximumPendingAudioChunks = 48
    static let maximumPendingCommits = 8
    static let supportedLanguages: Set<String> = [
        "af", "ar", "as", "az", "bg", "bn", "bs", "ca", "cs", "da", "de", "el", "en", "es", "et",
        "fa", "fi", "fil", "fr", "gl", "gu", "he", "hi", "hu", "hy", "id", "is", "it", "ja", "kk",
        "kn", "ko", "lt", "lv", "mk", "ml", "mr", "ms", "nb", "ne", "nl", "or", "pa", "pl", "pt",
        "ro", "ru", "sk", "sl", "sv", "sw", "ta", "te", "th", "tr", "uk", "ur", "vi", "yue", "zh"
    ]

    typealias ResultHandler = @Sendable (Result<String, AzureMAIError>) async -> Void
    typealias PartialHandler = @Sendable (String) async -> Void
    typealias ConnectionFactory = @Sendable (URLRequest) -> any AzureMAIWebSocketConnection
    private enum Phase { case stopped, connecting, configuring, streaming, draining, failed }
    private struct Outbound { let message: String; let isAudio: Bool }

    private let lock = NSLock()
    private let configuration: URLSessionConfiguration
    private let connectionFactory: ConnectionFactory?
    private let setupTimeout: Duration
    private let finishTimeout: Duration
    private let commitBytes: Int
    private var phase = Phase.stopped
    private var generation = UUID()
    private var connection: (any AzureMAIWebSocketConnection)?
    private var sendTask: Task<Void, Never>?
    private var receiveTask: Task<Void, Never>?
    private var outbound: [Outbound] = []
    private var pcmBuffer = Data()
    private var pendingAudioChunks = 0
    private var bytesSinceCommit = 0
    private var totalAudioBytes = 0
    private var paused = false
    private var expectedDeployment = ""
    private var configurationMessage = ""
    private var ledger = AzureMAITranscriptLedger()
    private var deliveriesInFlight = 0
    private var terminalError: AzureMAIError?
    private var failureDeliveryPending = false
    private var handler: ResultHandler?
    private var partialHandler: PartialHandler?

    init(configuration: URLSessionConfiguration = .ephemeral,
         connectionFactory: ConnectionFactory? = nil,
         setupTimeout: Duration = .seconds(10), finishTimeout: Duration = .seconds(15),
         commitAudioSeconds: Int = 3) {
        self.configuration = configuration
        self.connectionFactory = connectionFactory
        self.setupTimeout = setupTimeout
        self.finishTimeout = finishTimeout
        commitBytes = Self.sampleRate * 2 * max(1, min(5, commitAudioSeconds))
    }

    func start(endpoint: String, key: String, deployment: String, language: String?,
               handler: @escaping ResultHandler, partialHandler: @escaping PartialHandler) async throws {
        stop()
        let request = try Self.request(endpoint: endpoint, key: key)
        let deployment = deployment.trimmingCharacters(in: .whitespacesAndNewlines)
        let message = try Self.configurationMessage(deployment: deployment, language: language)
        let socket = connectionFactory?(request) ?? AzureMAIURLSessionConnection(request: request, configuration: configuration)
        let token = lock.withLock {
            let token = generation
            connection = socket
            self.handler = handler
            self.partialHandler = partialHandler
            expectedDeployment = deployment
            configurationMessage = message
            terminalError = nil
            phase = .connecting
            paused = false
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
                    guard ContinuousClock.now < deadline else { throw AzureMAIError.connection }
                    try await Task.sleep(for: .milliseconds(10))
                }
            } catch {
                if error is CancellationError { stop(generation: token) }
                else { fail(error as? AzureMAIError ?? .connection, generation: token) }
                throw error
            }
        } onCancel: { self.stop(generation: token) }
    }

    func append(_ sampleBuffer: CMSampleBuffer) {
        var failure: (AzureMAIError, UUID)?
        lock.withLock {
            guard phase == .streaming, !paused else { return }
            // 비정상적으로 큰 버퍼를 변환하기 전에 메모리 상한을 확인한다.
            guard CMSampleBufferGetNumSamples(sampleBuffer) <= Self.chunkBytes * Self.maximumPendingAudioChunks / 2 else {
                failure = (.backlog, generation)
                paused = true
                return
            }
            guard let pcm = AzureMAITranscriber.pcm16(sampleBuffer), pcm.count.isMultiple(of: 2) else {
                failure = (.audioFormat, generation)
                paused = true
                return
            }
            do { try appendPCMLocked(pcm) }
            catch { failure = (error as? AzureMAIError ?? .connection, generation); paused = true }
        }
        if let failure { fail(failure.0, generation: failure.1) }
    }

    func setPaused(_ value: Bool) {
        var failure: (AzureMAIError, UUID)?
        lock.withLock {
            paused = value
            guard value, phase == .streaming else { return }
            do { try flushAndCommitLocked() }
            catch { failure = (error as? AzureMAIError ?? .connection, generation) }
        }
        if let failure { fail(failure.0, generation: failure.1) }
    }

    func finish() async {
        var failure: (AzureMAIError, UUID)?
        let token: UUID? = lock.withLock {
            guard phase == .streaming || phase == .draining || phase == .failed else { return nil }
            if phase == .streaming {
                phase = .draining
                paused = true
                do { try flushAndCommitLocked() }
                catch { failure = (error as? AzureMAIError ?? .connection, generation) }
            }
            return generation
        }
        if let failure { fail(failure.0, generation: failure.1) }
        guard let token else { return }
        await withTaskCancellationHandler {
            let deadline = ContinuousClock.now.advanced(by: finishTimeout)
            while !Task.isCancelled {
                let result = lock.withLock { () -> Int in
                    guard generation == token else { return 1 }
                    if phase == .failed { return 1 }
                    return ledger.isDrained && outbound.isEmpty && pendingAudioChunks == 0 && deliveriesInFlight == 0 ? 2 : 0
                }
                if result != 0 {
                    if result == 2 { stop(generation: token) }
                    else { await waitForFailureDelivery(generation: token) }
                    return
                }
                guard ContinuousClock.now < deadline else {
                    fail(.connection, generation: token)
                    await waitForFailureDelivery(generation: token)
                    return
                }
                do { try await Task.sleep(for: .milliseconds(10)) }
                catch { break }
            }
            stop(generation: token)
        } onCancel: { self.stop(generation: token) }
    }

    func stop() { stop(generation: nil) }

    private func stop(generation token: UUID?) {
        let socket: (any AzureMAIWebSocketConnection)? = lock.withLock {
            if let token, token != generation { return nil }
            generation = UUID()
            phase = .stopped
            paused = true
            sendTask?.cancel(); receiveTask?.cancel()
            sendTask = nil; receiveTask = nil
            outbound.removeAll(); pcmBuffer.removeAll()
            pendingAudioChunks = 0; bytesSinceCommit = 0; totalAudioBytes = 0
            ledger = AzureMAITranscriptLedger()
            deliveriesInFlight = 0
            terminalError = nil
            failureDeliveryPending = false
            handler = nil; partialHandler = nil
            expectedDeployment = ""; configurationMessage = ""
            let socket = connection
            connection = nil
            return socket
        }
        socket?.close()
    }

    private func appendPCMLocked(_ pcm: Data) throws {
        guard !pcm.isEmpty else { return }
        let bufferedChunks = (pcmBuffer.count + pcm.count + Self.chunkBytes - 1) / Self.chunkBytes
        guard pcm.count <= Self.chunkBytes * Self.maximumPendingAudioChunks,
              pendingAudioChunks + bufferedChunks <= Self.maximumPendingAudioChunks,
              totalAudioBytes + pcm.count <= Self.sampleRate * 2 * 3_600 else { throw AzureMAIError.backlog }
        totalAudioBytes += pcm.count
        pcmBuffer.append(pcm)
        while pcmBuffer.count >= Self.chunkBytes {
            let chunk = Data(pcmBuffer.prefix(Self.chunkBytes))
            pcmBuffer.removeFirst(Self.chunkBytes)
            try enqueueAudioLocked(chunk)
            if bytesSinceCommit >= commitBytes { try commitLocked() }
        }
    }

    private func flushAndCommitLocked() throws {
        if !pcmBuffer.isEmpty {
            let chunk = pcmBuffer
            pcmBuffer.removeAll(keepingCapacity: false)
            try enqueueAudioLocked(chunk)
        }
        if bytesSinceCommit > 0 { try commitLocked() }
    }

    private func enqueueAudioLocked(_ pcm: Data) throws {
        guard pendingAudioChunks < Self.maximumPendingAudioChunks else { throw AzureMAIError.backlog }
        pendingAudioChunks += 1
        bytesSinceCommit += pcm.count
        enqueueLocked(Self.audioMessage(pcm), isAudio: true, generation: generation)
    }

    private func commitLocked() throws {
        try ledger.registerCommit()
        bytesSinceCommit = 0
        enqueueLocked("{\"type\":\"input_audio_buffer.commit\"}", generation: generation)
    }

    private func enqueueLocked(_ message: String, isAudio: Bool = false, generation token: UUID) {
        outbound.append(Outbound(message: message, isAudio: isAudio))
        guard sendTask == nil, let socket = connection else { return }
        sendTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                let next = self.lock.withLock { () -> Outbound? in
                    guard self.generation == token, self.phase != .stopped, self.phase != .failed else { return nil }
                    guard !self.outbound.isEmpty else { self.sendTask = nil; return nil }
                    return self.outbound.removeFirst()
                }
                guard let next else { return }
                do {
                    try await socket.send(next.message)
                    self.lock.withLock {
                        if self.generation == token, next.isAudio { self.pendingAudioChunks -= 1 }
                    }
                } catch { self.fail(.connection, generation: token); return }
            }
        }
    }

    private func receiveLoop(_ socket: any AzureMAIWebSocketConnection, generation token: UUID) async {
        do {
            while !Task.isCancelled {
                let event = try AzureMAIStreamingEvent.parse(try await socket.receive())
                let delivery = try lock.withLock { () -> (ResultHandler?, PartialHandler?, [String], String?) in
                    guard generation == token, phase != .stopped, phase != .failed else { return (nil, nil, [], nil) }
                    switch event {
                    case .created:
                        guard phase == .connecting else { throw AzureMAIError.response }
                        phase = .configuring
                        enqueueLocked(configurationMessage, generation: token)
                        return (nil, nil, [], nil)
                    case .updated(let model, let rate, let format, let vadDisabled):
                        guard phase == .configuring, model == expectedDeployment, rate == Self.sampleRate,
                              format == "audio/pcm", vadDisabled else { throw AzureMAIError.response }
                        phase = .streaming
                        configurationMessage = ""
                        return (nil, nil, [], nil)
                    case .failure: throw AzureMAIError.response
                    case .other: return (nil, nil, [], nil)
                    default: break
                    }
                    guard phase == .streaming || phase == .draining else { throw AzureMAIError.response }
                    let updates = try ledger.apply(event)
                    deliveriesInFlight += updates.finals.count + (updates.partial == nil ? 0 : 1)
                    return (handler, partialHandler, updates.finals, updates.partial)
                }
                for text in delivery.2 {
                    guard isCurrent(token) else { return }
                    // completed만 최종 처리한다. finalized delta를 다시 완료 결과로 보내지 않는다.
                    // 빈 완료도 알려야 마지막 provisional 자막을 호출자가 정리할 수 있다.
                    await delivery.0?(.success(text))
                    lock.withLock { if generation == token { deliveriesInFlight -= 1 } }
                }
                if let partial = delivery.3 {
                    guard isCurrent(token) else { return }
                    await delivery.1?(partial)
                    lock.withLock { if generation == token { deliveriesInFlight -= 1 } }
                }
            }
        } catch { fail(error as? AzureMAIError ?? .connection, generation: token) }
    }

    private func isCurrent(_ token: UUID) -> Bool {
        lock.withLock { generation == token && phase != .stopped && phase != .failed }
    }

    private func fail(_ error: AzureMAIError, generation token: UUID) {
        let failure = lock.withLock { () -> ((any AzureMAIWebSocketConnection)?, ResultHandler?)? in
            guard generation == token, phase != .stopped, phase != .failed else { return nil }
            phase = .failed; paused = true; terminalError = error
            outbound.removeAll(); pcmBuffer.removeAll()
            sendTask?.cancel(); receiveTask?.cancel()
            sendTask = nil; receiveTask = nil
            configurationMessage = ""; expectedDeployment = ""
            ledger = AzureMAITranscriptLedger()
            pendingAudioChunks = 0; bytesSinceCommit = 0
            let socket = connection
            connection = nil
            let callback = handler
            failureDeliveryPending = callback != nil
            handler = nil; partialHandler = nil
            return (socket, callback)
        }
        guard let failure else { return }
        failure.0?.close()
        Task { [weak self] in
            guard let self, self.lock.withLock({ self.generation == token && self.phase == .failed }) else { return }
            await failure.1?(.failure(error))
            self.lock.withLock { if self.generation == token { self.failureDeliveryPending = false } }
        }
    }

    private func waitForFailureDelivery(generation token: UUID) async {
        // finish 직후 호출자가 stop하더라도 마지막 오류 안내가 먼저 적용되게 한다.
        // 외부 callback 자체가 응답하지 않는 경우에도 종료 시간은 유한하다.
        let deadline = ContinuousClock.now.advanced(by: .seconds(1))
        while !Task.isCancelled, ContinuousClock.now < deadline,
              lock.withLock({ generation == token && failureDeliveryPending }) {
            do { try await Task.sleep(for: .milliseconds(5)) }
            catch { return }
        }
    }

    static func endpointURL(_ endpoint: String) throws -> URL {
        let suffix = ".services.ai.azure.com"
        guard var parts = URLComponents(string: endpoint.trimmingCharacters(in: .whitespacesAndNewlines)),
              parts.scheme == "https", let rawHost = parts.host else { throw AzureMAIError.configuration }
        let host = rawHost.lowercased()
        guard host.hasSuffix(suffix), parts.user == nil, parts.password == nil, parts.port == nil,
              parts.query == nil, parts.fragment == nil, parts.path.isEmpty || parts.path == "/" else {
            throw AzureMAIError.configuration
        }
        let resource = String(host.dropLast(suffix.count))
        guard !resource.isEmpty, resource.count <= 63,
              resource.first != "-", resource.last != "-",
              resource.utf8.allSatisfy({ (97...122).contains($0) || (48...57).contains($0) || $0 == 45 }) else {
            throw AzureMAIError.configuration
        }
        parts.scheme = "wss"; parts.host = host
        parts.path = "/mai/v1/realtime"
        parts.queryItems = [URLQueryItem(name: "intent", value: "transcription")]
        guard let url = parts.url else { throw AzureMAIError.configuration }
        return url
    }

    static func request(endpoint: String, key: String) throws -> URLRequest {
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, key.utf8.count <= 16_384,
              key.utf8.allSatisfy({ $0 >= 0x21 && $0 <= 0x7E }) else { throw AzureMAIError.configuration }
        var request = URLRequest(url: try endpointURL(endpoint))
        request.timeoutInterval = 15
        request.setValue(key, forHTTPHeaderField: "api-key")
        return request
    }

    static func configurationMessage(deployment: String, language: String?) throws -> String {
        guard !deployment.isEmpty, deployment.count <= 256,
              !deployment.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
              language == nil || supportedLanguages.contains(language!) else { throw AzureMAIError.configuration }
        let input: [String: Any] = [
            "format": ["type": "audio/pcm", "rate": sampleRate],
            "transcription": ["model": deployment, "language": language as Any? ?? NSNull()],
            "turn_detection": NSNull(), "noise_reduction": NSNull()
        ]
        let body: [String: Any] = ["type": "session.update", "session": ["type": "transcription", "audio": ["input": input]]]
        return String(decoding: try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys]), as: UTF8.self)
    }

    static func audioMessage(_ data: Data) -> String {
        "{\"type\":\"input_audio_buffer.append\",\"audio\":\"\(data.base64EncodedString())\"}"
    }
}

enum AzureMAIStreamingEvent {
    case created
    case updated(model: String, rate: Int, format: String, vadDisabled: Bool)
    case delta(String?, String), intermediate(String?, String), committed(String?), completed(String?, String)
    case failure, other

    static func parse(_ data: Data) throws -> Self {
        guard data.count <= AzureMAIStreamingTranscriber.maximumMessageBytes,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = object["type"] as? String else { throw AzureMAIError.response }
        let itemID = object["item_id"] as? String
        if let itemID, itemID.isEmpty || itemID.count > 256 { throw AzureMAIError.response }
        switch type {
        case "session.created": return .created
        case "session.updated":
            guard let session = object["session"] as? [String: Any], session["type"] as? String == "transcription",
                  let audio = session["audio"] as? [String: Any], let input = audio["input"] as? [String: Any],
                  let format = input["format"] as? [String: Any], let formatType = format["type"] as? String,
                  let rate = format["rate"] as? Int,
                  let transcription = input["transcription"] as? [String: Any], let model = transcription["model"] as? String else {
                throw AzureMAIError.response
            }
            return .updated(model: model, rate: rate, format: formatType,
                            vadDisabled: input["turn_detection"] == nil || input["turn_detection"] is NSNull)
        case "conversation.item.input_audio_transcription.delta":
            guard let text = object["delta"] as? String else { throw AzureMAIError.response }
            return .delta(itemID, text)
        case "conversation.item.input_audio_transcription.intermediate":
            guard let text = object["intermediate"] as? String else { throw AzureMAIError.response }
            return .intermediate(itemID, text)
        case "input_audio_buffer.committed": return .committed(itemID)
        case "conversation.item.input_audio_transcription.completed":
            guard let text = object["transcript"] as? String else { throw AzureMAIError.response }
            return .completed(itemID, text)
        case "error", "conversation.item.input_audio_transcription.failed": return .failure
        default: return .other
        }
    }
}

// commit 제출 순서를 보존하고 item_id가 있는 완료 이벤트의 중복을 제거한다.
struct AzureMAITranscriptLedger {
    private struct Commit { var acknowledged = false; var itemID: String?; var final: String? }
    private struct Draft { var stable = ""; var intermediate = "" }
    private var commits: [Commit] = []
    private var drafts: [String: Draft] = [:]
    private var draftOrder: [String] = []
    private var publishedDraft: String?
    private var publishedText: String?
    private var retired = Set<String>()
    private var retiredOrder: [String] = []
    private static let anonymous = ""
    var isDrained: Bool { commits.isEmpty }

    mutating func registerCommit() throws {
        guard commits.count < AzureMAIStreamingTranscriber.maximumPendingCommits else { throw AzureMAIError.backlog }
        commits.append(Commit())
    }

    mutating func apply(_ event: AzureMAIStreamingEvent) throws -> (finals: [String], partial: String?) {
        switch event {
        case .delta(let id, let text), .intermediate(let id, let text):
            if let id, retired.contains(id) { return ([], nil) }
            let key = id ?? Self.anonymous
            guard drafts[key] != nil || drafts.count < AzureMAIStreamingTranscriber.maximumPendingCommits + 1 else {
                throw AzureMAIError.backlog
            }
            if drafts[key] == nil { draftOrder.append(key) }
            var draft = drafts[key] ?? Draft()
            if case .delta = event { draft.stable += text; draft.intermediate = "" }
            else { draft.intermediate = text }
            guard draft.stable.utf8.count + draft.intermediate.utf8.count <= AzureMAIStreamingTranscriber.maximumMessageBytes else {
                throw AzureMAIError.backlog
            }
            drafts[key] = draft
        case .committed(let id):
            if let id, retired.contains(id) || commits.contains(where: { $0.acknowledged && $0.itemID == id }) { return ([], nil) }
            guard let index = commits.firstIndex(where: { !$0.acknowledged }) else { throw AzureMAIError.response }
            commits[index].acknowledged = true
            commits[index].itemID = id
        case .completed(let id, let text):
            if let id, retired.contains(id) { return ([], nil) }
            let index: Int?
            if let id { index = commits.firstIndex(where: { $0.acknowledged && $0.itemID == id }) }
            else {
                // 문서의 축약 예제처럼 item_id가 없는 완료는 확정 순서를 따른다.
                // 기다리는 commit이 없으면 늦게 반복된 완료를 다시 전달하지 않는다.
                index = commits.firstIndex(where: { $0.acknowledged && $0.final == nil })
                if index == nil { return ([], nil) }
            }
            guard let index else { throw AzureMAIError.response }
            if commits[index].final != nil { return ([], nil) }
            commits[index].final = text
        default: break
        }
        var finals: [String] = []
        while let first = commits.first, first.acknowledged, let text = first.final {
            commits.removeFirst()
            drafts.removeValue(forKey: first.itemID ?? Self.anonymous)
            drafts.removeValue(forKey: Self.anonymous)
            draftOrder.removeAll { $0 == first.itemID || $0 == Self.anonymous }
            if publishedDraft == first.itemID || publishedDraft == Self.anonymous {
                publishedDraft = nil; publishedText = nil
            }
            if let id = first.itemID {
                retired.insert(id); retiredOrder.append(id)
                if retiredOrder.count > 256 { retired.remove(retiredOrder.removeFirst()) }
            }
            finals.append(text)
        }
        // 하나의 provisional 행을 쓰는 호출자에게 다음 구간을 먼저 노출하지 않는다.
        // 앞 구간 완료 뒤 보류했던 다음 구간의 최신 가설을 전달한다.
        let candidate: String?
        if let first = commits.first, first.acknowledged, let id = first.itemID {
            candidate = drafts[id] == nil ? nil : id
        } else { candidate = draftOrder.first }
        var partial: String?
        if let candidate, let draft = drafts[candidate] {
            let text = draft.stable + draft.intermediate
            if publishedDraft != candidate || publishedText != text {
                publishedDraft = candidate; publishedText = text
                partial = text
            }
        }
        return (finals, partial)
    }
}
