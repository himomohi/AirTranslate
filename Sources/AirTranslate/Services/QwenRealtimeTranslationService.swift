import AVFoundation
import Foundation

protocol QwenWebSocketConnection: Sendable {
    func resume()
    func send(_ text: String) async throws
    func receive() async throws -> Data
    func close()
}

private final class QwenURLSessionConnection: QwenWebSocketConnection, @unchecked Sendable {
    private let session: URLSession
    private let socket: URLSessionWebSocketTask

    init(request: URLRequest) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.httpShouldSetCookies = false
        session = URLSession(configuration: configuration, delegate: QwenRejectRedirects(), delegateQueue: nil)
        socket = session.webSocketTask(with: request)
        socket.maximumMessageSize = QwenRealtimeTranslationService.maximumMessageBytes
    }

    func resume() { socket.resume() }
    func send(_ text: String) async throws { try await socket.send(.string(text)) }
    func receive() async throws -> Data {
        switch try await socket.receive() {
        case .string(let text): Data(text.utf8)
        case .data(let data): data
        @unknown default: throw QwenTranslationError.invalidResponse
        }
    }
    func close() {
        socket.cancel(with: .normalClosure, reason: nil)
        session.invalidateAndCancel()
    }
}

private final class QwenRejectRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        // 워크스페이스 호스트 밖으로 인증 헤더를 전달하지 않는다.
        completionHandler(nil)
    }
}

final class QwenRealtimeTranslationService: @unchecked Sendable {
    static let sampleRate = 16_000
    static let outputSampleRate = 24_000
    static let chunkBytes = 3_200
    static let maximumMessageBytes = 1_024 * 1_024
    static let maximumPendingAudioChunks = 48

    // partial은 새 delta만, final은 해당 발화 전체 문자열이다.
    typealias TextHandler = @Sendable (String, Bool) async -> Void
    typealias AudioHandler = @Sendable (Data) async -> Void
    typealias ErrorHandler = @Sendable (Error) async -> Void
    typealias ConnectionFactory = @Sendable (URLRequest) -> any QwenWebSocketConnection

    private enum Phase { case stopped, connecting, configuring, streaming, draining, failed }
    private let lock = NSLock()
    private let keyProvider: @Sendable () throws -> String?
    private let connectionFactory: ConnectionFactory
    private let setupTimeout: Duration
    private let finishTimeout: Duration
    private var phase = Phase.stopped
    private var generation = UUID()
    private var connection: (any QwenWebSocketConnection)?
    private var sendTask: Task<Void, Never>?
    private var receiveTask: Task<Void, Never>?
    private var outbound: [QwenClientMessage] = []
    private var pcmBuffer = Data()
    private var configurationMessage = ""
    private var targetLanguageCode = ""
    private var audioOutputEnabled = false
    private var paused = false
    private var finishAcknowledged = false
    private var deliveriesInFlight = 0
    private var terminalError: QwenTranslationError?
    private var sourceLedger = QwenTextLedger()
    private var translationLedger = QwenTextLedger()
    private var sourceHandler: TextHandler?
    private var translationHandler: TextHandler?
    private var audioHandler: AudioHandler?
    private var errorHandler: ErrorHandler?

    var onSourceTranscript: TextHandler? {
        get { lock.withLock { sourceHandler } }
        set { lock.withLock { sourceHandler = newValue } }
    }
    var onTranslation: TextHandler? {
        get { lock.withLock { translationHandler } }
        set { lock.withLock { translationHandler = newValue } }
    }
    var onAudio: AudioHandler? {
        get { lock.withLock { audioHandler } }
        set { lock.withLock { audioHandler = newValue } }
    }
    var onError: ErrorHandler? {
        get { lock.withLock { errorHandler } }
        set { lock.withLock { errorHandler = newValue } }
    }

    init(keyProvider: @escaping @Sendable () throws -> String? = { try QwenAPIKeyStore.readAPIKey() },
         connectionFactory: @escaping ConnectionFactory = { QwenURLSessionConnection(request: $0) },
         setupTimeout: Duration = .seconds(8), finishTimeout: Duration = .seconds(15)) {
        self.keyProvider = keyProvider
        self.connectionFactory = connectionFactory
        self.setupTimeout = setupTimeout
        self.finishTimeout = finishTimeout
    }

    func start(workspaceID: String, targetLanguage: LanguageOption, audioOutputEnabled: Bool) async throws {
        stop()
        let key: String
        do { key = try keyProvider()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" }
        catch { throw QwenTranslationError.missingKey }
        let request = try Self.request(key: key, workspaceID: workspaceID)
        let language = try Self.languageCode(targetLanguage)
        let configuration = try Self.configuration(language: language, audioOutputEnabled: audioOutputEnabled)
        let socket = connectionFactory(request)
        let token = lock.withLock {
            let token = generation
            connection = socket
            configurationMessage = configuration
            targetLanguageCode = language
            self.audioOutputEnabled = audioOutputEnabled
            phase = .connecting
            paused = false
            socket.resume()
            receiveTask = Task { [weak self] in await self?.receiveLoop(socket, generation: token) }
            return token
        }
        try await wait(generation: token, finishing: false)
    }

    func append(_ sampleBuffer: CMSampleBuffer) {
        let failure: (QwenTranslationError, UUID)? = lock.withLock {
            guard phase == .streaming, !paused else { return nil }
            guard let pcm = AzureMAITranscriber.pcm16(sampleBuffer), pcm.count.isMultiple(of: 2) else {
                paused = true
                return (.audioFormat, generation)
            }
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
        if let failure { fail(failure.0, generation: failure.1) }
    }

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
        try await wait(generation: token, finishing: true)
    }

    private func wait(generation token: UUID, finishing: Bool) async throws {
        try await withTaskCancellationHandler {
            do {
                let deadline = ContinuousClock.now.advanced(by: finishing ? finishTimeout : setupTimeout)
                while true {
                    try Task.checkCancellation()
                    let ready = try lock.withLock {
                        guard generation == token else { throw CancellationError() }
                        if let terminalError { throw terminalError }
                        return finishing ? finishAcknowledged && deliveriesInFlight == 0 : phase == .streaming
                    }
                    if ready {
                        if finishing { stop(generation: token) }
                        return
                    }
                    guard ContinuousClock.now < deadline else {
                        throw finishing ? QwenTranslationError.finishTimeout : QwenTranslationError.setupTimeout
                    }
                    try await Task.sleep(for: .milliseconds(10))
                }
            } catch {
                if error is CancellationError { stop(generation: token) }
                else { fail(error as? QwenTranslationError ?? .connection, generation: token) }
                throw error
            }
        } onCancel: { self.stop(generation: token) }
    }

    func stop() { stop(generation: nil) }

    private func stop(generation token: UUID?) {
        let socket: (any QwenWebSocketConnection)? = lock.withLock {
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
            configurationMessage = ""
            sourceLedger = QwenTextLedger()
            translationLedger = QwenTextLedger()
            finishAcknowledged = false
            deliveriesInFlight = 0
            terminalError = nil
            let socket = connection
            connection = nil
            return socket
        }
        socket?.close()
    }

    private func enqueueLocked(_ message: QwenClientMessage, generation token: UUID) {
        outbound.append(message)
        guard sendTask == nil, let socket = connection else { return }
        sendTask = Task { [weak self] in
            guard let self else { return }
            var nextAudioSend = ContinuousClock.now
            while !Task.isCancelled {
                let next: QwenClientMessage? = self.lock.withLock {
                    guard self.generation == token, self.phase != .stopped, self.phase != .failed else { return nil }
                    guard !self.outbound.isEmpty else { self.sendTask = nil; return nil }
                    return self.outbound.removeFirst()
                }
                guard let next else { return }
                do {
                    if case .audio = next { try await Task.sleep(until: nextAudioSend, clock: .continuous) }
                    try Task.checkCancellation()
                    guard self.lock.withLock({ self.generation == token && self.phase != .stopped && self.phase != .failed }) else { return }
                    try await socket.send(next.text)
                    if case .audio(let data) = next {
                        nextAudioSend = ContinuousClock.now.advanced(by: .seconds(Double(data.count) / 32_000))
                    }
                } catch { self.fail(.connection, generation: token); return }
            }
        }
    }

    private enum Delivery {
        case text(TextHandler?, String, Bool)
        case audio(AudioHandler?, Data)
    }

    private func receiveLoop(_ socket: any QwenWebSocketConnection, generation token: UUID) async {
        do {
            while !Task.isCancelled {
                let event = try QwenServerEvent.parse(try await socket.receive())
                let delivery: Delivery? = try lock.withLock {
                    guard generation == token, phase != .stopped, phase != .failed else { return nil }
                    switch event {
                    case .created:
                        guard phase == .connecting else { throw QwenTranslationError.invalidResponse }
                        phase = .configuring
                        enqueueLocked(.configuration(configurationMessage), generation: token)
                        configurationMessage = ""
                        return nil
                    case .updated(let language, let modalities):
                        let expected: Set<String> = audioOutputEnabled ? ["text", "audio"] : ["text"]
                        guard phase == .configuring, language == targetLanguageCode, Set(modalities) == expected else {
                            throw QwenTranslationError.invalidResponse
                        }
                        phase = .streaming
                        return nil
                    case .failure: throw QwenTranslationError.serviceUnavailable
                    case .ignored: return nil
                    default: break
                    }
                    guard phase == .streaming || phase == .draining else { throw QwenTranslationError.invalidResponse }
                    let result: Delivery?
                    switch event {
                    case let .source(id, text, final):
                        result = try sourceLedger.apply(id: id, text: text, final: final).map { .text(sourceHandler, $0, final) }
                    case let .translation(id, text, final):
                        result = try translationLedger.apply(id: id, text: text, final: final).map { .text(translationHandler, $0, final) }
                    case .audio(let data):
                        guard audioOutputEnabled else { throw QwenTranslationError.invalidResponse }
                        result = .audio(audioHandler, data)
                    case .finished:
                        guard phase == .draining, sourceLedger.isDrained, translationLedger.isDrained else {
                            throw QwenTranslationError.invalidResponse
                        }
                        finishAcknowledged = true
                        result = nil
                    default: result = nil
                    }
                    if result != nil { deliveriesInFlight += 1 }
                    return result
                }
                if let delivery {
                    guard lock.withLock({ generation == token && phase != .stopped && phase != .failed }) else { return }
                    switch delivery {
                    case let .text(handler, text, final): await handler?(text, final)
                    case let .audio(handler, data): await handler?(data)
                    }
                    lock.withLock { if generation == token { deliveriesInFlight -= 1 } }
                }
                if case .finished = event { return }
            }
        } catch { fail(error as? QwenTranslationError ?? .connection, generation: token) }
    }

    private func fail(_ error: QwenTranslationError, generation token: UUID) {
        let failure: ((any QwenWebSocketConnection)?, ErrorHandler?)? = lock.withLock {
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

    static func request(key: String, workspaceID: String) throws -> URLRequest {
        guard !key.isEmpty, key.utf8.allSatisfy({ $0 >= 0x21 && $0 <= 0x7E }) else { throw QwenTranslationError.missingKey }
        let workspace = workspaceID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !workspace.isEmpty, workspace.utf8.count <= 63,
              workspace.utf8.allSatisfy({ (97...122).contains($0) || (48...57).contains($0) || $0 == 45 }),
              workspace.first != "-", workspace.last != "-" else { throw QwenTranslationError.configuration }
        var components = URLComponents()
        components.scheme = "wss"
        components.host = "\(workspace).ap-southeast-1.maas.aliyuncs.com"
        components.path = "/api-ws/v1/realtime"
        components.queryItems = [.init(name: "model", value: QwenTranslationModel.liveTranslateFlashRealtime.rawValue)]
        guard let url = components.url else { throw QwenTranslationError.configuration }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        return request
    }

    static func languageCode(_ language: LanguageOption) throws -> String {
        guard let code = language.id.lowercased().split(separator: "-").first.map(String.init),
              ["en", "ko", "ja", "zh", "es", "fr", "de"].contains(code) else { throw QwenTranslationError.configuration }
        return code
    }

    static func configuration(language: String, audioOutputEnabled: Bool) throws -> String {
        let json: [String: Any] = ["type": "session.update", "session": [
            "output_modalities": audioOutputEnabled ? ["text", "audio"] : ["text"],
            "translation": ["language": language]
        ]]
        return String(decoding: try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys]), as: UTF8.self)
    }
}

enum QwenClientMessage: Sendable {
    case configuration(String), audio(Data), finish
    var text: String {
        switch self {
        case .configuration(let text): text
        case .audio(let data): "{\"type\":\"input_audio_buffer.append\",\"audio\":\"\(data.base64EncodedString())\"}"
        case .finish: "{\"type\":\"session.finish\"}"
        }
    }
}

struct QwenTextLedger {
    private var activeID: String?
    private var partialBytes = 0
    private var finalizedIDs: [String] = []
    var isDrained: Bool { activeID == nil }

    mutating func apply(id: String, text: String, final: Bool) throws -> String? {
        if finalizedIDs.contains(id) { return nil }
        guard activeID == nil || activeID == id else { throw QwenTranslationError.invalidResponse }
        guard text.utf8.count <= 256 * 1_024 else { throw QwenTranslationError.backlog }
        if final {
            activeID = nil
            partialBytes = 0
            finalizedIDs.append(id)
            if finalizedIDs.count > 128 { finalizedIDs.removeFirst() }
        } else {
            guard partialBytes + text.utf8.count <= 256 * 1_024 else { throw QwenTranslationError.backlog }
            activeID = id
            partialBytes += text.utf8.count
        }
        return text
    }
}

enum QwenServerEvent: Sendable {
    case created, updated(String, [String]), finished
    case source(String, String, Bool), translation(String, String, Bool), audio(Data)
    case failure, ignored

    static func parse(_ data: Data) throws -> Self {
        guard data.count <= QwenRealtimeTranslationService.maximumMessageBytes,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else { throw QwenTranslationError.invalidResponse }
        func string(_ key: String) throws -> String {
            guard let value = json[key] as? String else { throw QwenTranslationError.invalidResponse }
            return value
        }
        func itemID() throws -> String {
            let id = try string("item_id")
            guard !id.isEmpty, id.utf8.count <= 512 else { throw QwenTranslationError.invalidResponse }
            return id
        }
        switch type {
        case "session.created", "session.updated":
            guard let session = json["session"] as? [String: Any],
                  session["model"] as? String == QwenTranslationModel.liveTranslateFlashRealtime.rawValue,
                  let audio = session["audio"] as? [String: Any],
                  let input = audio["input"] as? [String: Any], let inputFormat = input["format"] as? [String: Any],
                  inputFormat["type"] as? String == "pcm", inputFormat["sample_rate"] as? Int == 16_000,
                  let output = audio["output"] as? [String: Any], let outputFormat = output["format"] as? [String: Any],
                  outputFormat["type"] as? String == "pcm", outputFormat["sample_rate"] as? Int == 24_000 else {
                throw QwenTranslationError.invalidResponse
            }
            if type == "session.created" { return .created }
            guard let modalities = session["output_modalities"] as? [String],
                  let translation = session["translation"] as? [String: Any], let language = translation["language"] as? String else {
                throw QwenTranslationError.invalidResponse
            }
            return .updated(language, modalities)
        case "conversation.item.input_audio_transcription.delta": return try .source(itemID(), string("delta"), false)
        case "conversation.item.input_audio_transcription.completed": return try .source(itemID(), string("transcript"), true)
        case "response.text.delta", "response.audio_transcript.delta": return try .translation(itemID(), string("delta"), false)
        case "response.text.done": return try .translation(itemID(), string("text"), true)
        case "response.audio_transcript.done": return try .translation(itemID(), string("transcript"), true)
        case "response.audio.delta":
            guard let audio = Data(base64Encoded: try string("delta")), !audio.isEmpty, audio.count.isMultiple(of: 2) else {
                throw QwenTranslationError.invalidResponse
            }
            return .audio(audio)
        case "session.finished": return .finished
        case "response.done":
            guard let response = json["response"] as? [String: Any], let status = response["status"] as? String else {
                throw QwenTranslationError.invalidResponse
            }
            return status == "completed" ? .ignored : .failure
        case "error", "conversation.item.input_audio_transcription.failed":
            // 서버의 message에는 토큰·사용자 원문이 포함될 수 있으므로 전달하지 않는다.
            return .failure
        default: return .ignored
        }
    }
}

enum QwenTranslationError: LocalizedError, Equatable, Sendable {
    case configuration, missingKey, audioFormat, backlog, connection, invalidResponse
    case setupTimeout, finishTimeout, serviceUnavailable

    var errorDescription: String? {
        switch self {
        case .configuration: AppText.localized(english: "Check the Qwen Singapore workspace ID and target language.", korean: "Qwen 싱가포르 워크스페이스 ID와 대상 언어를 확인하세요.", japanese: "QwenのシンガポールワークスペースIDと翻訳先言語を確認してください。", chineseSimplified: "请检查 Qwen 新加坡工作空间 ID 和目标语言。")
        case .missingKey: AppText.localized(english: "Save your Qwen API key before starting.", korean: "시작하기 전에 Qwen API 키를 저장하세요.", japanese: "開始前にQwen APIキーを保存してください。", chineseSimplified: "请先保存 Qwen API 密钥。")
        case .audioFormat: AppText.localized(english: "Qwen requires 16 kHz mono PCM audio.", korean: "Qwen 입력은 16 kHz 모노 PCM 오디오여야 합니다.", japanese: "Qwenには16 kHzモノラルPCM音声が必要です。", chineseSimplified: "Qwen 需要 16 kHz 单声道 PCM 音频。")
        case .backlog: AppText.localized(english: "Qwen reached the streaming queue limit. Restart capture when ready.", korean: "Qwen 스트리밍 대기열 한도에 도달했습니다. 준비되면 캡처를 다시 시작하세요.", japanese: "Qwenのキューが上限に達しました。準備ができたら再開してください。", chineseSimplified: "Qwen 流式队列已达上限。请重新开始采集。")
        case .connection: AppText.localized(english: "The Qwen connection was interrupted. Captions already received are preserved.", korean: "Qwen 연결이 끊겼습니다. 이미 받은 자막은 보존됩니다.", japanese: "Qwen接続が中断されました。受信済み字幕は保持されます。", chineseSimplified: "Qwen 连接中断。已收到的字幕会保留。")
        case .invalidResponse: AppText.localized(english: "Qwen returned an inconsistent response. Captions already received are preserved.", korean: "Qwen 응답이 일관되지 않습니다. 이미 받은 자막은 보존됩니다.", japanese: "Qwenの応答に不整合があります。受信済み字幕は保持されます。", chineseSimplified: "Qwen 响应不一致。已收到的字幕会保留。")
        case .setupTimeout: AppText.localized(english: "Qwen setup timed out. Check your network, API key and workspace.", korean: "Qwen 연결 준비 시간이 초과되었습니다. 네트워크·API 키·워크스페이스를 확인하세요.", japanese: "Qwen接続準備がタイムアウトしました。ネットワーク・APIキー・ワークスペースを確認してください。", chineseSimplified: "Qwen 连接准备超时。请检查网络、API 密钥和工作空间。")
        case .finishTimeout: AppText.localized(english: "Qwen did not finish in time. The last caption may be incomplete.", korean: "Qwen이 제한 시간 안에 완료되지 않았습니다. 마지막 자막이 불완전할 수 있습니다.", japanese: "Qwenが制限時間内に完了しませんでした。最後の字幕が不完全な可能性があります。", chineseSimplified: "Qwen 未在时限内完成。最后的字幕可能不完整。")
        case .serviceUnavailable: AppText.localized(english: "Qwen could not process the session. Check API access, quota and service status.", korean: "Qwen이 세션을 처리하지 못했습니다. API 접근 권한·할당량·서비스 상태를 확인하세요.", japanese: "Qwenがセッションを処理できませんでした。API権限・利用枠・サービス状態を確認してください。", chineseSimplified: "Qwen 无法处理此会话。请检查 API 权限、配额和服务状态。")
        }
    }
}
