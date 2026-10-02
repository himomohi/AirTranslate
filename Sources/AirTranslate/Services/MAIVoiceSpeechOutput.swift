@preconcurrency import AVFAudio
import Foundation

actor MAIVoiceCatalog {
    static let shared = MAIVoiceCatalog()
    private var cachedVoices: [String: [String]] = [:]
    private var refreshedAt: Date?
    private let session: URLSession

    init(configuration: URLSessionConfiguration = .ephemeral) {
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 15
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        session = URLSession(configuration: configuration, delegate: MAIVoiceRejectRedirects(), delegateQueue: nil)
    }

    func voices(for model: SpeechSynthesisModel) async throws -> [String] {
        guard model.isMAIVoice else { throw MAIVoiceError.invalidModel }
        if let refreshedAt, Date().timeIntervalSince(refreshedAt) < 1_800,
           let voices = cachedVoices[model.rawValue] { return voices }
        let url = URL(string: "https://openrouter.ai/api/v1/models?output_modalities=speech")!
        let (bytes, response) = try await session.bytes(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw MAIVoiceError.catalog }
        let data = try await MAIVoiceSpeechOutput.collect(bytes, maximumBytes: 1_048_576)
        cachedVoices = try Self.decode(data)
        refreshedAt = Date()
        guard let voices = cachedVoices[model.rawValue], !voices.isEmpty else { throw MAIVoiceError.catalog }
        return voices
    }

    static func decode(_ data: Data) throws -> [String: [String]] {
        struct Catalog: Decodable {
            struct Model: Decodable {
                let id: String
                let supported_voices: [String]?
            }
            let data: [Model]
        }
        guard let catalog = try? JSONDecoder().decode(Catalog.self, from: data) else { throw MAIVoiceError.catalog }
        var voices: [String: [String]] = [:]
        for model in catalog.data {
            guard let selection = SpeechSynthesisModel(rawValue: model.id), selection.isMAIVoice else { continue }
            voices[model.id] = Array(Set((model.supported_voices ?? []).filter { $0.hasSuffix(":" + selection.title) })).sorted()
        }
        return voices
    }

    static func matchingVoices(_ voices: [String], languageID: String) -> [String] {
        let normalized = languageID.replacingOccurrences(of: "_", with: "-").lowercased()
        let exact = voices.filter { $0.lowercased().hasPrefix(normalized + "-") }
        if !exact.isEmpty { return exact }
        let code = normalized.split(separator: "-").first.map(String.init) ?? normalized
        return voices.filter { $0.lowercased().hasPrefix(code + "-") }
    }

    static func selectVoice(_ voices: [String], languageID: String, preferredName: String) throws -> String {
        let matching = matchingVoices(voices, languageID: languageID)
        if !preferredName.isEmpty {
            guard let selected = matching.first(where: { $0.split(separator: ":").first.map(String.init) == preferredName }) else {
                throw MAIVoiceError.languageUnsupported
            }
            return selected
        }
        guard let selected = matching.first(where: { $0.contains("-Harper:") }) ?? matching.first else {
            throw MAIVoiceError.languageUnsupported
        }
        return selected
    }
}

@MainActor
final class MAIVoiceSpeechOutput: NSObject, AVAudioPlayerDelegate {
    private struct Segment {
        let text: String
        let model: SpeechSynthesisModel
        let languageID: String
        let voiceName: String
    }
    private let session: URLSession
    private let catalog: MAIVoiceCatalog
    private let keyProvider: () throws -> String?
    private var pending: Segment?
    private var activeText: String?
    private var worker: Task<Void, Never>?
    private var generation: UInt64 = 0
    private var player: AVAudioPlayer?
    private var playback: CheckedContinuation<Void, Error>?
    private var volume: Float = 1
    var onFailure: ((MAIVoiceError) -> Void)?

    init(configuration: URLSessionConfiguration = .ephemeral,
         catalog: MAIVoiceCatalog = .shared,
         keyProvider: @escaping () throws -> String? = { try OpenRouterAPIKeyStore.readAPIKey() }) {
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 30
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.httpShouldSetCookies = false
        session = URLSession(configuration: configuration, delegate: MAIVoiceRejectRedirects(), delegateQueue: nil)
        self.catalog = catalog
        self.keyProvider = keyProvider
        super.init()
    }

    func setVolume(_ value: Double) {
        volume = Float(min(max(value, 0), 1))
        player?.volume = volume
    }

    func speak(_ text: String, model: SpeechSynthesisModel, language: LanguageOption, voiceName: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard model.isMAIVoice, !text.isEmpty, text != pending?.text, text != activeText else { return }
        guard text.count <= 10_000 else { onFailure?(.textTooLong); return }
        // 생성 중인 문장과 최신 대기 문장 하나만 유지한다.
        pending = Segment(text: text, model: model, languageID: language.id, voiceName: voiceName)
        guard worker == nil else { return }
        let current = generation
        worker = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled, self.generation == current, let segment = self.pending {
                self.pending = nil
                self.activeText = segment.text
                do {
                    guard let key = try self.keyProvider() else { throw MAIVoiceError.missingKey }
                    let voices = try await self.catalog.voices(for: segment.model)
                    try Task.checkCancellation()
                    let voice = try MAIVoiceCatalog.selectVoice(voices, languageID: segment.languageID, preferredName: segment.voiceName)
                    let request = try Self.makeRequest(text: segment.text, model: segment.model, voice: voice, apiKey: key)
                    let (bytes, response) = try await self.session.bytes(for: request)
                    try Self.validateResponse(response)
                    let audio = try await Self.collect(bytes, maximumBytes: 8_388_608)
                    try Task.checkCancellation()
                    guard self.generation == current else { return }
                    guard !audio.isEmpty else { throw MAIVoiceError.invalidAudio }
                    try await self.play(audio)
                } catch {
                    guard !Task.isCancelled, self.generation == current else { return }
                    self.onFailure?(error as? MAIVoiceError ?? .connection)
                }
                guard self.generation == current else { return }
                self.activeText = nil
            }
            guard self.generation == current else { return }
            self.worker = nil
        }
    }

    func stop() {
        generation &+= 1
        worker?.cancel()
        worker = nil
        pending = nil
        activeText = nil
        player?.delegate = nil
        player?.stop()
        finishPlayback()
    }

    private func play(_ audio: Data) async throws {
        let next = try AVAudioPlayer(data: audio)
        next.volume = volume
        next.delegate = self
        guard next.prepareToPlay() else { throw MAIVoiceError.invalidAudio }
        player = next
        try await withCheckedThrowingContinuation { continuation in
            playback = continuation
            if !next.play() { finishPlayback(failed: true) }
        }
    }

    private func finishPlayback(failed: Bool = false) {
        let continuation = playback
        playback = nil
        player?.delegate = nil
        player = nil
        if failed { continuation?.resume(throwing: MAIVoiceError.invalidAudio) }
        else { continuation?.resume() }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            guard self?.player === player else { return }
            self?.finishPlayback(failed: !flag)
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor [weak self] in
            guard self?.player === player else { return }
            self?.finishPlayback(failed: true)
        }
    }

    nonisolated static func collect<S: AsyncSequence>(_ bytes: S, maximumBytes: Int) async throws -> Data where S.Element == UInt8 {
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < maximumBytes else { throw MAIVoiceError.invalidAudio }
            data.append(byte)
        }
        return data
    }

    nonisolated static func validateResponse(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw MAIVoiceError.invalidAudio }
        guard (200..<300).contains(http.statusCode) else { throw MAIVoiceError.http(http.statusCode) }
        guard http.mimeType == "audio/mpeg" || http.mimeType == "audio/mp3" else { throw MAIVoiceError.invalidAudio }
    }

    nonisolated static func makeRequest(text: String, model: SpeechSynthesisModel, voice: String, apiKey: String) throws -> URLRequest {
        guard model.isMAIVoice else { throw MAIVoiceError.invalidModel }
        guard !apiKey.isEmpty, apiKey.utf8.allSatisfy({ $0 >= 0x21 && $0 <= 0x7e }) else { throw MAIVoiceError.missingKey }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.count <= 10_000 else { throw MAIVoiceError.textTooLong }
        guard voice.hasSuffix(":" + model.title), !voice.contains("\n") else { throw MAIVoiceError.languageUnsupported }
        var request = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/audio/speech")!)
        request.httpMethod = "POST"
        request.setValue("Bearer " + apiKey, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("audio/mpeg", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model.rawValue, "input": text, "voice": voice, "response_format": "mp3"
        ])
        return request
    }
}

final class MAIVoiceRejectRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        // 인증 키를 리디렉션 대상에 전달하지 않는다.
        completionHandler(nil)
    }
}

enum MAIVoiceError: LocalizedError {
    case missingKey, invalidModel, languageUnsupported, catalog, connection, invalidAudio, textTooLong
    case http(Int)

    var errorDescription: String? {
        switch self {
        case .missingKey: MAIVoiceCopy.keyRequired
        case .languageUnsupported: MAIVoiceCopy.languageUnsupported
        case .catalog: MAIVoiceCopy.catalogFailed
        case .http(let status): AppText.localized(english: "MAI Voice request failed (HTTP \(status)). Check the OpenRouter key, credits and model availability.", korean: "MAI Voice 요청 실패(HTTP \(status)). OpenRouter 키·잔액·모델 가용성을 확인하세요.")
        case .textTooLong: AppText.localized(english: "MAI Voice text exceeds the request limit.", korean: "MAI Voice 요청의 텍스트 길이 제한을 초과했습니다.")
        default: AppText.localized(english: "MAI Voice audio generation or playback failed. Captions remain available.", korean: "MAI Voice 음성 생성 또는 재생에 실패했습니다. 자막은 계속 사용할 수 있습니다.")
        }
    }
}
