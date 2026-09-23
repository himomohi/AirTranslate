@preconcurrency import AVFAudio
import Foundation

@MainActor
final class GeminiSpeechOutput: NSObject, AVAudioPlayerDelegate {
    private struct QueuedSpeech {
        let text: String
        let model: SpeechSynthesisModel
        let key: String
    }

    private static let maximumQueuedSegments = 1
    private static let endpoint = URL(string: "https://generativelanguage.googleapis.com/v1beta/interactions")!

    private let session: URLSession
    private var speechVolume: Float = 1
    private var queuedSpeech: [QueuedSpeech] = []
    private var queuedSpeechKeys: Set<String> = []
    private var generation: UInt64 = 0
    private var workerTask: Task<Void, Never>?
    private var player: AVAudioPlayer?
    private var playbackContinuation: CheckedContinuation<Void, Error>?

    var onFailure: (() -> Void)?

    override init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 30
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.httpShouldSetCookies = false
        session = URLSession(
            configuration: configuration,
            delegate: GeminiSpeechOutputRejectRedirects(),
            delegateQueue: nil
        )
        super.init()
    }

    func setVolume(_ volume: Double) {
        speechVolume = Float(min(max(volume, 0), 1))
        player?.volume = speechVolume
    }

    func speak(_ text: String, model: SpeechSynthesisModel) {
        guard model.isGeminiTTS else { return }
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }

        let key = Self.speechKey(trimmedText)
        guard !queuedSpeechKeys.contains(key) else { return }

        if queuedSpeech.count >= Self.maximumQueuedSegments {
            let staleSpeech = queuedSpeech.removeFirst()
            queuedSpeechKeys.remove(staleSpeech.key)
        }

        queuedSpeech.append(QueuedSpeech(text: trimmedText, model: model, key: key))
        queuedSpeechKeys.insert(key)
        startWorkerIfNeeded()
    }

    func stop() {
        generation &+= 1
        queuedSpeech.removeAll()
        queuedSpeechKeys.removeAll()
        workerTask?.cancel()
        workerTask = nil
        player?.delegate = nil
        player?.stop()
        player = nil
        finishPlayback()
    }

    private func startWorkerIfNeeded() {
        guard workerTask == nil else { return }
        let workerGeneration = generation
        workerTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.processQueuedSpeech(generation: workerGeneration)
            self.finishWorker(generation: workerGeneration)
        }
    }

    private func finishWorker(generation workerGeneration: UInt64) {
        guard generation == workerGeneration else { return }
        workerTask = nil
        if !queuedSpeech.isEmpty {
            startWorkerIfNeeded()
        }
    }

    private func processQueuedSpeech(generation workerGeneration: UInt64) async {
        while !Task.isCancelled,
              generation == workerGeneration,
              !queuedSpeech.isEmpty {
            let request = queuedSpeech.removeFirst()
            do {
                let audioData = try await generateWave(text: request.text, model: request.model)
                guard !Task.isCancelled, generation == workerGeneration else {
                    queuedSpeechKeys.remove(request.key)
                    return
                }
                try await play(audioData)
            } catch is CancellationError {
                queuedSpeechKeys.remove(request.key)
                return
            } catch {
                onFailure?()
            }
            queuedSpeechKeys.remove(request.key)
        }
    }

    private func play(_ audioData: Data) async throws {
        try Task.checkCancellation()
        let nextPlayer = try AVAudioPlayer(data: audioData)
        nextPlayer.volume = speechVolume
        nextPlayer.delegate = self
        guard nextPlayer.prepareToPlay() else {
            throw GeminiSpeechOutputError.audioPlaybackFailed
        }
        player = nextPlayer

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            playbackContinuation = continuation
            guard nextPlayer.play() else {
                playbackContinuation = nil
                continuation.resume(throwing: GeminiSpeechOutputError.audioPlaybackFailed)
                return
            }
        }
    }

    private func finishPlayback(reportFailure: Bool = false) {
        let continuation = playbackContinuation
        playbackContinuation = nil
        player?.delegate = nil
        player = nil
        if reportFailure {
            continuation?.resume(throwing: GeminiSpeechOutputError.audioPlaybackFailed)
        } else {
            continuation?.resume()
        }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            self?.finishPlayback(reportFailure: !flag)
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor [weak self] in
            self?.finishPlayback(reportFailure: true)
        }
    }

    private func generateWave(text: String, model: SpeechSynthesisModel) async throws -> Data {
        guard let apiKey = try GeminiAPIKeyStore.readAPIKey(), !apiKey.isEmpty else {
            throw GeminiSpeechOutputError.missingAPIKey
        }
        let request = try Self.makeRequest(text: text, model: model, apiKey: apiKey)

        let (responseData, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw GeminiSpeechOutputError.requestFailed
        }

        let interaction = try JSONDecoder().decode(GeminiSpeechInteractionResponse.self, from: responseData)
        guard let encodedAudio = interaction.outputAudio?.data,
              let audioData = Data(base64Encoded: encodedAudio),
              audioData.starts(with: Data("RIFF".utf8)),
              audioData.count > 44 else {
            throw GeminiSpeechOutputError.invalidAudio
        }
        return audioData
    }

    static func makeRequest(text: String, model: SpeechSynthesisModel, apiKey: String) throws -> URLRequest {
        guard let modelID = model.apiModelID else {
            throw GeminiSpeechOutputError.invalidModel
        }
        guard !apiKey.isEmpty, apiKey.utf8.allSatisfy({ $0 >= 0x21 && $0 <= 0x7E }) else {
            throw GeminiSpeechOutputError.missingAPIKey
        }
        let payload: [String: Any] = [
            "model": modelID,
            "input": [[
                "type": "user_input",
                "content": [[
                    "type": "text",
                    "text": text
                ]]
            ]],
            "response_format": ["type": "audio"],
            "generation_config": [
                "speech_config": [["voice": "Kore"]]
            ]
        ]

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        return request
    }

    private static func speechKey(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

final class GeminiSpeechOutputRejectRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        // Do not forward the Gemini API key to a redirected host.
        completionHandler(nil)
    }
}

private struct GeminiSpeechInteractionResponse: Decodable {
    let outputAudio: OutputAudio?

    enum CodingKeys: String, CodingKey {
        case outputAudio = "output_audio"
    }

    struct OutputAudio: Decodable {
        let data: String?
    }
}

private enum GeminiSpeechOutputError: Error {
    case missingAPIKey
    case requestFailed
    case invalidModel
    case invalidAudio
    case audioPlaybackFailed
}
