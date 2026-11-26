import Foundation
import os

private let screenTextLog = Logger(subsystem: "dev.appcaster.AirTranslate", category: "ScreenText")

/// Where interpreted speech is played (OpenAIRealtimeAudioOutput in the app).
protocol ScreenTextAudioSink: AnyObject {
    func playPCM16Base64(_ audio: String, sampleRate: Double)
    func setRate(_ rate: Float)
    func setVolume(_ volume: Double)
    func stop()
}

extension OpenAIRealtimeAudioOutput: ScreenTextAudioSink {}

/// Speaks screen text in another language through Gemini Live.
///
/// Text is grouped into phrases (a sentence end, a few words, or a short pause), and each
/// phrase is one turn: it goes out as text and comes back as streamed speech in the target
/// language. Gemini streams a reply at about real-time speed, so one session alone falls
/// behind fast subtitles; turns are spread over two sessions so the next phrase is generated
/// while the current one is still speaking. Audio is played strictly in turn order.
@MainActor
final class GeminiLiveTextInterpreter {
    struct Configuration: Equatable {
        var model = "gemini-3.8-live"
        var voice = "Kore"
        var sourceLanguage: String
        var targetLanguage: String
    }

    static let laneCount = 2
    static let normalRate: Float = 1.1
    static let catchUpRate: Float = 1.3
    /// A phrase is sent once it has this many words, ends a sentence, or waited `phraseDelay`.
    nonisolated static let phraseWords = 6
    static let phraseDelay: Duration = .milliseconds(800)
    private static let outputSampleRate = 24_000.0

    let configuration: Configuration
    /// A turn was sent: (turn, source text).
    var onTurnStarted: ((Int, String) -> Void)?
    /// (turn, translation so far), from Gemini's transcript of its own speech.
    var onTranscript: ((Int, String) -> Void)?
    /// Reports a failure, or nil once a reply arrives again.
    var onError: ((String?) -> Void)?

    private let audio: ScreenTextAudioSink
    private let sendOverride: ((Int, String) async throws -> Void)?
    private var lanes: [GeminiLiveLane] = []

    private var pending = ""
    private var pendingSince: ContinuousClock.Instant?
    private var flushTask: Task<Void, Never>?
    private var lastQueued = ""

    // Turn order: audio of turn `playHead` goes straight to the player; later turns are held.
    private struct HeldTurn {
        var chunks: [String] = []
        var complete = false
    }
    private var lastSentTurn = 0
    private var playHead = 1
    private var held: [Int: HeldTurn] = [:]

    init(
        configuration: Configuration,
        audio: ScreenTextAudioSink,
        sendOverride: ((Int, String) async throws -> Void)? = nil
    ) {
        self.configuration = configuration
        self.audio = audio
        self.sendOverride = sendOverride
        lanes = (0..<Self.laneCount).map { index in
            GeminiLiveLane(index: index, setup: Self.setupMessage(for: configuration))
        }
        for lane in lanes {
            lane.onMessage = { [weak self, weak lane] json in
                guard let self, let lane else { return }
                self.handleServerMessage(json, lane: lane.index)
            }
            lane.onFailure = { [weak self, weak lane] reason in
                guard let self, let lane else { return }
                self.onError?(reason)
                if let turn = lane.turn { self.turnFinished(turn, lane: lane) }
            }
        }
    }

    /// Opens the sessions before the first phrase so it doesn't wait for setup.
    func prepare() {
        guard sendOverride == nil else { return }
        for lane in lanes { lane.prepare() }
    }

    func enqueue(_ text: String) {
        let line = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty, line != lastQueued else { return }
        lastQueued = line
        pending = Self.joined(pending, line)
        if pendingSince == nil { pendingSince = .now }
        dispatch()
    }

    func stop() {
        flushTask?.cancel()
        pending = ""
        held.removeAll()
        for lane in lanes { lane.close() }
        audio.stop()
        audio.setRate(1)
    }

    // MARK: - Phrases and turns

    /// Sends the pending text on a free session once it reads as a phrase.
    private func dispatch(force: Bool = false) {
        flushTask?.cancel()
        flushTask = nil
        guard !pending.isEmpty, let lane = lanes.first(where: { $0.turn == nil }) else {
            updateRate()
            return
        }
        let waited = pendingSince.map { ContinuousClock.now - $0 } ?? .zero
        guard force || Self.isPhrase(pending) || waited >= Self.phraseDelay else {
            flushTask = Task { [weak self] in
                try? await Task.sleep(for: Self.phraseDelay - waited)
                guard !Task.isCancelled else { return }
                self?.dispatch(force: true)
            }
            return
        }
        let text = pending
        pending = ""
        pendingSince = nil
        lastSentTurn += 1
        let turn = lastSentTurn
        onTurnStarted?(turn, text)
        screenTextLog.notice("turn \(turn, privacy: .public) sent on lane \(lane.index, privacy: .public) (\(text.count, privacy: .public) chars)")
        updateRate()
        if let sendOverride {
            lane.turn = turn
            Task { [weak self] in
                do { try await sendOverride(lane.index, text) } catch { self?.turnFinished(turn, lane: lane) }
            }
        } else {
            lane.send(text, turn: turn)
        }
    }

    nonisolated static func isPhrase(_ text: String) -> Bool {
        if let last = text.last, ".!?…。！？".contains(last) { return true }
        return text.split(whereSeparator: \.isWhitespace).count >= phraseWords
    }

    /// Appends `line`, keeping only the most recent ~400 characters.
    nonisolated static func joined(_ waiting: String?, _ line: String) -> String {
        guard let waiting, !waiting.isEmpty else { return line }
        let text = waiting + " " + line
        guard text.count > 400 else { return text }
        return String(text.suffix(400)).drop { !$0.isWhitespace }.trimmingCharacters(in: .whitespaces)
    }

    private func turnFinished(_ turn: Int, lane: GeminiLiveLane) {
        guard lane.turn == turn else { return }
        lane.finishTurn()
        screenTextLog.notice("turn \(turn, privacy: .public) complete")
        if turn == playHead {
            advancePlayHead()
        } else {
            held[turn, default: HeldTurn()].complete = true
        }
        dispatch()
    }

    /// Moves playback to the next turn, releasing audio that arrived while it waited.
    private func advancePlayHead() {
        playHead += 1
        while playHead <= lastSentTurn {
            let turn = held.removeValue(forKey: playHead) ?? HeldTurn()
            for chunk in turn.chunks { audio.playPCM16Base64(chunk, sampleRate: Self.outputSampleRate) }
            guard turn.complete else { break }
            playHead += 1
        }
        updateRate()
    }

    /// Faster while more turns or text wait behind the one playing.
    private func updateRate() {
        let behind = lastSentTurn > playHead || !pending.isEmpty
        audio.setRate(behind ? Self.catchUpRate : Self.normalRate)
    }

    // MARK: - Server messages

    /// Handles one decoded server message from lane `index`. Internal so tests can feed messages.
    func handleServerMessage(_ json: [String: Any], lane index: Int) {
        let lane = lanes[index]
        if json["setupComplete"] != nil {
            lane.markSetupComplete()
            return
        }
        if json["goAway"] != nil {
            lane.reopenSoon()
            return
        }
        guard let turn = lane.turn, let content = json["serverContent"] as? [String: Any] else { return }

        if let parts = (content["modelTurn"] as? [String: Any])?["parts"] as? [[String: Any]] {
            for part in parts {
                guard let inline = part["inlineData"] as? [String: Any],
                      let base64 = inline["data"] as? String else { continue }
                onError?(nil)
                if turn == playHead {
                    audio.playPCM16Base64(base64, sampleRate: Self.outputSampleRate)
                } else {
                    held[turn, default: HeldTurn()].chunks.append(base64)
                }
            }
        }
        if let text = (content["outputTranscription"] as? [String: Any])?["text"] as? String {
            lane.transcript += text
            let trimmed = lane.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { onTranscript?(turn, trimmed) }
        }
        if content["turnComplete"] as? Bool == true || content["interrupted"] as? Bool == true {
            turnFinished(turn, lane: lane)
        }
    }

    nonisolated static func setupMessage(for configuration: Configuration) -> [String: Any] {
        let instruction = """
            You are a live dubbing interpreter. Every user message is a phrase of on-screen text \
            (usually video subtitles) in \(configuration.sourceLanguage); it may be part of a \
            longer sentence. Respond only by speaking its translation in \
            \(configuration.targetLanguage), concisely and at a brisk pace so it keeps up with the \
            video, in the speaker's tone. Never add greetings, explanations, questions or anything \
            that is not in the text.
            """
        return [
            "setup": [
                "model": "models/\(configuration.model)",
                "generationConfig": [
                    "responseModalities": ["AUDIO"],
                    "speechConfig": [
                        "voiceConfig": ["prebuiltVoiceConfig": ["voiceName": configuration.voice]],
                    ],
                ],
                "systemInstruction": ["parts": [["text": instruction]]],
                "outputAudioTranscription": [String: Any](),
                "contextWindowCompression": ["slidingWindow": [String: Any]()],
            ],
        ]
    }
}

// MARK: - One Gemini Live session

@MainActor
final class GeminiLiveLane {
    private static let endpoint = URL(string:
        "wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent")!
    /// A reply streams at about real time, so allow a long phrase to finish.
    private static let maxTurn: Duration = .seconds(25)

    let index: Int
    private let setup: [String: Any]
    var onMessage: (([String: Any]) -> Void)?
    var onFailure: ((String) -> Void)?

    /// The turn this session is generating, if any.
    var turn: Int?
    var transcript = ""

    private var urlSession: URLSession?
    private var socket: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var connecting: Task<Void, Error>?
    private var setupWaiter: CheckedContinuation<Void, Error>?
    private var isSetupComplete = false
    private var watchdog: Task<Void, Never>?

    init(index: Int, setup: [String: Any]) {
        self.index = index
        self.setup = setup
    }

    func prepare() {
        Task { [weak self] in
            do { try await self?.ensureConnected() } catch {
                guard let self else { return }
                onFailure?(describe(error))
                disconnect()
            }
        }
    }

    func send(_ text: String, turn: Int) {
        self.turn = turn
        transcript = ""
        watchdog?.cancel()
        watchdog = Task { [weak self] in
            try? await Task.sleep(for: Self.maxTurn)
            guard !Task.isCancelled, let self, self.turn == turn else { return }
            disconnect()
            onFailure?(AppText.geminiLiveScreenTextTimedOut)
        }
        Task { [weak self] in
            guard let self else { return }
            do {
                try await ensureConnected()
                try await sendJSON([
                    "clientContent": [
                        "turns": [["role": "user", "parts": [["text": text]]]],
                        "turnComplete": true,
                    ],
                ])
            } catch {
                guard self.turn == turn else { return }
                disconnect()
                onFailure?(describe(error))
            }
        }
    }

    func finishTurn() {
        watchdog?.cancel()
        turn = nil
    }

    func close() {
        finishTurn()
        disconnect()
    }

    func markSetupComplete() {
        isSetupComplete = true
        setupWaiter?.resume()
        setupWaiter = nil
    }

    /// The server will close this connection soon: let the reply finish on it, open a new one next.
    func reopenSoon() {
        socket = nil
        prepare()
    }

    private func ensureConnected() async throws {
        if socket != nil, connecting == nil { return }
        if let connecting { return try await connecting.value }
        let task = Task { try await connect() }
        connecting = task
        defer { connecting = nil }
        try await task.value
    }

    private func connect() async throws {
        guard let apiKey = try GeminiAPIKeyStore.readAPIKey(), !apiKey.isEmpty else {
            throw GeminiLiveTextInterpreterError.missingAPIKey
        }
        var request = URLRequest(url: Self.endpoint)
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")  // Never in the URL.
        let session = URLSession(configuration: .default)
        let socket = session.webSocketTask(with: request)
        urlSession = session
        self.socket = socket
        isSetupComplete = false
        socket.resume()
        startReceiving(on: socket)

        try await sendJSON(setup)
        guard !isSetupComplete else { return }
        let timeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled, let self, let waiter = setupWaiter else { return }
            setupWaiter = nil
            waiter.resume(throwing: GeminiLiveTextInterpreterError.setupTimedOut)
        }
        defer { timeout.cancel() }
        try await withCheckedThrowingContinuation { setupWaiter = $0 }
    }

    private func disconnect() {
        receiveTask?.cancel()
        receiveTask = nil
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
        urlSession?.finishTasksAndInvalidate()
        urlSession = nil
        setupWaiter?.resume(throwing: CancellationError())
        setupWaiter = nil
    }

    private func sendJSON(_ message: [String: Any]) async throws {
        guard let socket else { throw GeminiLiveTextInterpreterError.notConnected }
        let data = try JSONSerialization.data(withJSONObject: message)
        try await socket.send(.string(String(decoding: data, as: UTF8.self)))
    }

    private func startReceiving(on socket: URLSessionWebSocketTask) {
        receiveTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    let data: Data
                    switch try await socket.receive() {
                    case .data(let bytes): data = bytes
                    case .string(let text): data = Data(text.utf8)
                    @unknown default: continue
                    }
                    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                    self?.onMessage?(json)
                } catch {
                    guard !Task.isCancelled, let self else { return }
                    connectionLost(socket, error: error)
                    return
                }
            }
        }
    }

    private func connectionLost(_ lost: URLSessionWebSocketTask, error: Error) {
        let reason = describe(error, socket: lost)
        if let waiter = setupWaiter {
            setupWaiter = nil
            waiter.resume(throwing: GeminiLiveTextInterpreterError.connection(reason))
        }
        if socket === lost { disconnect() }
        // An idle session closing is normal; the next turn reconnects. Only a cut-off reply is an error.
        guard turn != nil else { return }
        onFailure?(reason)
    }

    private func describe(_ error: Error, socket: URLSessionWebSocketTask? = nil) -> String {
        if let data = (socket ?? self.socket)?.closeReason,
           let reason = String(data: data, encoding: .utf8), !reason.isEmpty {
            return "Gemini Live: \(reason)"
        }
        return error.localizedDescription
    }
}

enum GeminiLiveTextInterpreterError: LocalizedError {
    case missingAPIKey
    case notConnected
    case setupTimedOut
    case connection(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey: AppText.geminiAPIKeyNotConfigured
        case .notConnected, .setupTimedOut: AppText.geminiLiveScreenTextTimedOut
        case .connection(let reason): reason
        }
    }
}
