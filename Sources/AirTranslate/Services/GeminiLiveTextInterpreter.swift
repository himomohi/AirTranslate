import Foundation
import os

private let screenTextLog = Logger(subsystem: "dev.appcaster.AirTranslate", category: "ScreenText")

/// Speaks text lines in another language through one Gemini Live session.
///
/// Each line goes out as text and comes back as streamed speech in the target language,
/// so translation and synthesis are one round trip and playback starts while audio is
/// still arriving. The session keeps earlier lines as context, so names stay consistent.
///
/// A new turn would cut off a reply still being generated, so one turn is in flight at a
/// time; lines arriving meanwhile are joined and sent together as the next turn, so fast
/// subtitles are not skipped. Playback speeds up while lines wait.
@MainActor
final class GeminiLiveTextInterpreter {
    struct Configuration: Equatable {
        var model = "gemini-3.8-live"
        var voice = "Kore"
        var sourceLanguage: String
        var targetLanguage: String
    }

    private static let endpoint = URL(string:
        "wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent")!
    private static let outputSampleRate = 24_000.0
    private static let maxGeneration: Duration = .seconds(10)
    /// Playback speed normally, and while a newer line is already waiting.
    static let normalRate: Float = 1.1
    static let catchUpRate: Float = 1.35

    let configuration: Configuration
    /// (source line, translation so far), as Gemini's transcript of its speech arrives.
    var onTranscript: ((String, String) -> Void)?
    /// Reports a failure, or nil once a reply arrives again.
    var onError: ((String?) -> Void)?

    private let audio: OpenAIRealtimeAudioOutput
    /// Replaces the socket in tests: receives each line that would be sent.
    private let sendOverride: ((String) async throws -> Void)?
    private var urlSession: URLSession?
    private var socket: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var connecting: Task<Void, Error>?
    private var setupWaiter: CheckedContinuation<Void, Error>?
    private var isSetupComplete = false

    private var waiting: String?
    private var lastQueued = ""
    private var generatingLine: String?
    private var transcript = ""
    private var watchdog: Task<Void, Never>?
    private var turnSentAt: ContinuousClock.Instant?
    private var receivedAudioThisTurn = false

    init(
        configuration: Configuration,
        audio: OpenAIRealtimeAudioOutput,
        sendOverride: ((String) async throws -> Void)? = nil
    ) {
        self.configuration = configuration
        self.audio = audio
        self.sendOverride = sendOverride
    }

    /// Opens the session before the first line so that line doesn't wait for setup.
    func prepare() {
        guard sendOverride == nil else { return }
        Task { [weak self] in
            do { try await self?.ensureConnected() } catch {
                self?.onError?(self?.describe(error) ?? error.localizedDescription)
                self?.disconnect()
            }
        }
    }

    func enqueue(_ text: String) {
        let line = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty, line != lastQueued else { return }
        lastQueued = line
        waiting = Self.joined(waiting, line)
        sendNextIfPossible()
        updateRate()
    }

    /// Appends `line` to the waiting text, keeping only the most recent ~400 characters
    /// so a long backlog cannot grow without bound.
    nonisolated static func joined(_ waiting: String?, _ line: String) -> String {
        guard let waiting, !waiting.isEmpty else { return line }
        let text = waiting + " " + line
        guard text.count > 400 else { return text }
        return String(text.suffix(400)).drop { !$0.isWhitespace }.trimmingCharacters(in: .whitespaces)
    }

    /// Faster while a newer line waits behind the one being spoken, so speech catches up.
    private func updateRate() {
        audio.setRate(waiting != nil ? Self.catchUpRate : Self.normalRate)
    }

    func stop() {
        watchdog?.cancel()
        waiting = nil
        generatingLine = nil
        audio.stop()
        audio.setRate(1)  // The output is shared with OpenAI realtime speech.
        disconnect()
    }

    var isGenerating: Bool { generatingLine != nil }

    // MARK: - Turns

    private func sendNextIfPossible() {
        guard generatingLine == nil, let line = waiting else { return }
        waiting = nil
        generatingLine = line
        transcript = ""
        turnSentAt = .now
        receivedAudioThisTurn = false
        screenTextLog.notice("turn sent (\(line.count, privacy: .public) chars)")
        updateRate()
        armWatchdog(for: line)
        Task { [weak self] in
            guard let self else { return }
            do {
                if let sendOverride {
                    try await sendOverride(line)
                } else {
                    try await ensureConnected()
                    try await send([
                        "clientContent": [
                            "turns": [["role": "user", "parts": [["text": line]]]],
                            "turnComplete": true,
                        ],
                    ])
                }
            } catch {
                onError?(describe(error))
                disconnect()
                finishTurn()  // Skip this line; the next one reconnects.
            }
        }
    }

    private func finishTurn() {
        guard generatingLine != nil else { return }
        if let turnSentAt {
            screenTextLog.notice("turn complete after \(String(describing: ContinuousClock.now - turnSentAt), privacy: .public)")
        }
        watchdog?.cancel()
        generatingLine = nil
        sendNextIfPossible()
    }

    private func armWatchdog(for line: String) {
        watchdog?.cancel()
        watchdog = Task { [weak self] in
            try? await Task.sleep(for: Self.maxGeneration)
            guard !Task.isCancelled, let self, generatingLine == line else { return }
            onError?(AppText.geminiLiveScreenTextTimedOut)
            disconnect()
            finishTurn()
        }
    }

    // MARK: - Server messages

    /// Handles one decoded server message. Internal so tests can feed recorded messages.
    func handleServerMessage(_ json: [String: Any]) {
        if json["setupComplete"] != nil {
            isSetupComplete = true
            setupWaiter?.resume()
            setupWaiter = nil
            return
        }
        if json["goAway"] != nil {
            // This connection closes soon: let the reply finish on it and open the next now.
            socket = nil
            prepare()
            return
        }
        guard let content = json["serverContent"] as? [String: Any] else { return }

        if generatingLine != nil,
           let parts = (content["modelTurn"] as? [String: Any])?["parts"] as? [[String: Any]] {
            for part in parts {
                guard let inline = part["inlineData"] as? [String: Any],
                      let base64 = inline["data"] as? String else { continue }
                onError?(nil)
                if !receivedAudioThisTurn, let turnSentAt {
                    receivedAudioThisTurn = true
                    screenTextLog.notice("first audio after \(String(describing: ContinuousClock.now - turnSentAt), privacy: .public)")
                }
                audio.playPCM16Base64(base64, sampleRate: Self.outputSampleRate)
            }
        }
        if let line = generatingLine,
           let text = (content["outputTranscription"] as? [String: Any])?["text"] as? String {
            transcript += text
            let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { onTranscript?(line, trimmed) }
        }
        if content["turnComplete"] as? Bool == true || content["interrupted"] as? Bool == true {
            finishTurn()
        }
    }

    // MARK: - Connection

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

        try await send(setupMessage())
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

    func setupMessage() -> [String: Any] {
        let instruction = """
            You are a live dubbing interpreter. Every user message is one line of on-screen text \
            (usually a video subtitle) in \(configuration.sourceLanguage). Respond only by speaking \
            its translation in \(configuration.targetLanguage), concisely and at a brisk pace so it \
            keeps up with the video, in the speaker's tone. Never add greetings, explanations, questions or anything that is not \
            in the line. Keep names consistent with earlier lines.
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
                // Keeps long videos within the context window instead of ending the session.
                "contextWindowCompression": ["slidingWindow": [String: Any]()],
            ],
        ]
    }

    private func send(_ message: [String: Any]) async throws {
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
                    self?.handleServerMessage(json)
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
        // An idle session closing is normal; the next line reconnects. Only a cut-off reply is an error.
        guard generatingLine != nil else { return }
        onError?(reason)
        finishTurn()
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
