import Foundation
import os

private let screenTextLog = Logger(subsystem: "dev.appcaster.AirTranslate", category: "ScreenText")

/// Where interpreted speech is played (OpenAIRealtimeAudioOutput in the app).
protocol ScreenTextAudioSink: AnyObject {
    func playPCM16Base64(_ audio: String, sampleRate: Double)
    func setRate(_ rate: Float)
    func setVolume(_ volume: Double)
    func stop()
    func backlogSeconds() -> Double
}

extension OpenAIRealtimeAudioOutput: ScreenTextAudioSink {}

/// Speaks screen text in another language through Gemini Live.
///
/// Caption units (a finished caption line or a pause) are sent as turns, each with the
/// preceding words as context, and come back as streamed speech in the target language.
/// Gemini streams a reply at about real-time speed, so turns are spread over two sessions:
/// the next unit is generated while the current one is speaking, and audio plays strictly
/// in turn order.
///
/// Lag control: the estimated delay (unplayed audio, held audio, text not yet spoken) sets
/// the playback rate, and past `condenseLag` the next turn asks Gemini to condense. Nothing
/// is dropped; when far behind, everything waiting becomes one condensed turn.
@MainActor
final class GeminiLiveTextInterpreter {
    struct Configuration: Equatable {
        var model = "gemini-3.8-live"
        var voice = "Kore"
        var sourceLanguage: String
        var targetLanguage: String
    }

    static let laneCount = 2
    /// Waiting text is sent anyway once it has this many words or waited this long.
    nonisolated static let maxUnitWords = 14
    static let maxUnitWait: Duration = .milliseconds(2500)
    /// Estimated speaking time per source character (measured: ~35 ms).
    nonisolated static let secondsPerCharacter = 0.035
    nonisolated static let condenseLag = 3.0
    nonisolated static let farBehindLag = 6.0
    private static let contextWords = 15
    private static let outputSampleRate = 24_000.0
    private static let bytesPerSecond = 48_000.0  // 24 kHz, 16-bit mono

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
    private var pendingReady = false
    private var pendingSince: ContinuousClock.Instant?
    private var flushTask: Task<Void, Never>?
    private var rateTask: Task<Void, Never>?
    /// Recent source words, sent as context with the next turn.
    private var context: [String] = []
    /// Estimated speech still to come for each sent turn, and whether its leading silence is trimmed.
    private var expectedSeconds: [Int: Double] = [:]
    private var receivedSeconds: [Int: Double] = [:]
    private var speechStarted: Set<Int> = []
    private(set) var lag: Double = 0

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

    /// Adds new caption words; `endsUnit` marks a finished caption line or a pause.
    func enqueue(_ text: String, endsUnit: Bool) {
        let words = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !words.isEmpty {
            pending = Self.joined(pending, words)
            if pendingSince == nil { pendingSince = .now }
        }
        if endsUnit, !pending.isEmpty { pendingReady = true }
        startRateControl()
        dispatch()
    }

    func stop() {
        flushTask?.cancel()
        rateTask?.cancel()
        rateTask = nil
        pending = ""
        pendingReady = false
        held.removeAll()
        for lane in lanes { lane.close() }
        audio.stop()
        audio.setRate(1)
    }

    // MARK: - Phrases and turns

    /// Sends the pending text on a free session once it is a complete unit.
    private func dispatch(force: Bool = false) {
        flushTask?.cancel()
        flushTask = nil
        guard !pending.isEmpty, let lane = lanes.first(where: { $0.turn == nil }) else { return }
        let waited = pendingSince.map { ContinuousClock.now - $0 } ?? .zero
        let wordCount = pending.split(whereSeparator: \.isWhitespace).count
        guard force || pendingReady || wordCount >= Self.maxUnitWords || waited >= Self.maxUnitWait else {
            flushTask = Task { [weak self] in
                try? await Task.sleep(for: Self.maxUnitWait - waited)
                guard !Task.isCancelled else { return }
                self?.dispatch(force: true)
            }
            return
        }
        let text = pending
        pending = ""
        pendingReady = false
        pendingSince = nil
        lastSentTurn += 1
        let turn = lastSentTurn
        updateLag()
        let message = Self.turnMessage(text, context: context.joined(separator: " "), lag: lag)
        context = Array((context + text.split(whereSeparator: \.isWhitespace).map(String.init)).suffix(Self.contextWords))
        expectedSeconds[turn] = Double(text.count) * Self.secondsPerCharacter
        onTurnStarted?(turn, text)
        screenTextLog.notice("turn \(turn, privacy: .public) sent on lane \(lane.index, privacy: .public) (\(text.count, privacy: .public) chars, lag \(self.lag, format: .fixed(precision: 1), privacy: .public) s)")
        if let sendOverride {
            lane.turn = turn
            Task { [weak self] in
                do { try await sendOverride(lane.index, message) } catch { self?.turnFinished(turn, lane: lane) }
            }
        } else {
            lane.send(message, turn: turn)
        }
    }

    /// The turn text: preceding words as context, the words to translate, and a word budget
    /// when speech is behind.
    nonisolated static func turnMessage(_ text: String, context: String, lag: Double) -> String {
        var message = ""
        if !context.isEmpty { message += "Context (do not translate): \(context)\n" }
        message += "Translate: \(text)"
        let words = text.split(whereSeparator: \.isWhitespace).count
        if lag > farBehindLag {
            message += "\n(Far behind the video: say it in at most \(max(4, words / 3)) words.)"
        } else if lag > condenseLag {
            message += "\n(Behind the video: condense to at most \(max(5, words / 2)) words.)"
        }
        return message
    }

    /// Playback speed for an estimated lag in seconds.
    /// 1.1x while close to the screen, rising to `maxRate` as the lag grows to 4 s.
    nonisolated static func rate(forLag lag: Double) -> Float {
        let (calm, behind) = (1.5, 4.0)
        if lag <= calm { return normalRate }
        if lag >= behind { return maxRate }
        return normalRate + Float((lag - calm) / (behind - calm)) * (maxRate - normalRate)
    }

    nonisolated static let normalRate: Float = 1.1
    nonisolated static let maxRate: Float = 2.2

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
        expectedSeconds[turn] = nil
        receivedSeconds[turn] = nil
        speechStarted.remove(turn)
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
    }

    // MARK: - Lag control

    private func startRateControl() {
        guard rateTask == nil else { return }
        rateTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.updateLag()
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }

    /// Estimated seconds between what is on screen and what is being heard.
    private func updateLag() {
        let held = held.values.reduce(0.0) { total, turn in
            total + turn.chunks.reduce(0.0) { $0 + Double($1.count) * 0.75 / Self.bytesPerSecond }
        }
        let coming = expectedSeconds.reduce(0.0) { total, entry in
            total + max(0, entry.value - (receivedSeconds[entry.key] ?? 0))
        }
        lag = audio.backlogSeconds() + held + coming + Double(pending.count) * Self.secondsPerCharacter
        audio.setRate(Self.rate(forLag: lag))
    }

    // MARK: - Leading silence

    /// Drops near-silent samples before a turn's speech starts (base64 PCM16 little-endian).
    nonisolated static func trimmingLeadingSilence(_ base64: String, threshold: Int16 = 500) -> String? {
        guard let data = Data(base64Encoded: base64) else { return base64 }
        let samples = data.count / 2
        var first: Int?
        data.withUnsafeBytes { raw in
            for index in 0..<samples {
                let sample = Int16(littleEndian: raw.loadUnaligned(fromByteOffset: index * 2, as: Int16.self))
                if sample > threshold || sample < -threshold { first = index; break }
            }
        }
        guard let first else { return nil }
        return first == 0 ? base64 : data.dropFirst(first * 2).base64EncodedString()
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
                      var base64 = inline["data"] as? String else { continue }
                onError?(nil)
                receivedSeconds[turn, default: 0] += Double(base64.count) * 0.75 / Self.bytesPerSecond
                if !speechStarted.contains(turn) {
                    guard let trimmed = Self.trimmingLeadingSilence(base64) else { continue }
                    speechStarted.insert(turn)
                    base64 = trimmed
                }
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
            You are a live dubbing interpreter for a video. Each user message gives the previous \
            caption words as context and, after "Translate:", new caption words in \
            \(configuration.sourceLanguage); they may continue a sentence. Respond only by \
            speaking the translation of the new words in \(configuration.targetLanguage), \
            concisely and at a brisk pace, in the speaker's tone. Never speak the context, and \
            never add greetings, explanations, questions or anything that is not in the new \
            words. If asked to condense, keep the meaning in fewer words.
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
