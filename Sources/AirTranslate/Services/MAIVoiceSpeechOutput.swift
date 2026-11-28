@preconcurrency import AVFAudio
import Foundation

actor MAIVoiceCatalog {
    static let shared = MAIVoiceCatalog()
    private static let decoder = JSONDecoder()
    private var cachedVoices: [String: [String]] = [:]
    private var refreshedAt: Date?
    private let session: URLSession

    init(configuration: URLSessionConfiguration = .ephemeral) {
        let config = configuration.copy() as! URLSessionConfiguration
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 15
        config.urlCache = nil
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.urlCredentialStorage = nil
        session = URLSession(configuration: config, delegate: MAIVoiceRejectRedirects(), delegateQueue: nil)
    }

    func voices(for model: SpeechSynthesisModel) async throws -> [String] {
        guard model.isMAIVoice else { throw MAIVoiceError.invalidModel }
        if let refreshedAt, Date().timeIntervalSince(refreshedAt) < 1_800,
           let voices = cachedVoices[model.rawValue] { return voices }
        let url = URL(string: "https://openrouter.ai/api/v1/models?output_modalities=speech")!
        let data = try await MAIVoiceSpeechOutput.fetchBoundedData(
            session: session,
            request: URLRequest(url: url),
            maximumBytes: 1_048_576,
            overflowError: .catalog
        ) { response in
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw MAIVoiceError.catalog }
        }
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
        guard let catalog = try? decoder.decode(Catalog.self, from: data) else { throw MAIVoiceError.catalog }
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
    private struct Segment: Equatable {
        let text: String
        let model: SpeechSynthesisModel
        let languageID: String
        let voiceName: String
    }
    private struct PrefetchedAudio {
        let segment: Segment
        let task: Task<Data, Error>
    }
    private let session: URLSession
    private let catalog: MAIVoiceCatalog
    private let keyProvider: () throws -> String?
    private var pending: Segment?
    private var prefetched: PrefetchedAudio?
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
        let config = configuration.copy() as! URLSessionConfiguration
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 30
        config.urlCache = nil
        config.httpCookieStorage = nil
        config.urlCredentialStorage = nil
        config.httpShouldSetCookies = false
        session = URLSession(configuration: config, delegate: MAIVoiceRejectRedirects(), delegateQueue: nil)
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
        let segment = Segment(text: text, model: model, languageID: language.id, voiceName: voiceName)
        pending = segment
        if player != nil {
            startPrefetchIfNeeded(for: segment)
        }
        guard worker == nil else { return }
        let current = generation
        worker = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled, self.generation == current, let segment = self.pending {
                self.pending = nil
                self.activeText = segment.text
                do {
                    let audio: Data
                    if let prefetched = self.prefetched, prefetched.segment == segment {
                        self.prefetched = nil
                        audio = try await prefetched.task.value
                    } else {
                        self.prefetched?.task.cancel()
                        self.prefetched = nil
                        guard let key = try self.keyProvider() else { throw MAIVoiceError.missingKey }
                        audio = try await Self.fetchAudio(
                            segment: segment,
                            catalog: self.catalog,
                            session: self.session,
                            apiKey: key
                        )
                    }
                    try Task.checkCancellation()
                    guard self.generation == current else { return }
                    guard !audio.isEmpty else { throw MAIVoiceError.invalidAudio }
                    if let next = self.pending {
                        self.startPrefetchIfNeeded(for: next)
                    }
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
        prefetched?.task.cancel()
        prefetched = nil
        worker?.cancel()
        worker = nil
        pending = nil
        activeText = nil
        player?.delegate = nil
        player?.stop()
        finishPlayback()
    }

    private func startPrefetchIfNeeded(for segment: Segment) {
        if let existing = prefetched {
            if existing.segment == segment { return }
            existing.task.cancel()
            prefetched = nil
        }
        guard let key = try? keyProvider() else { return }
        let catalog = self.catalog
        let session = self.session
        let task = Task {
            try await Self.fetchAudio(
                segment: segment,
                catalog: catalog,
                session: session,
                apiKey: key
            )
        }
        prefetched = PrefetchedAudio(segment: segment, task: task)
    }

    private nonisolated static func fetchAudio(
        segment: Segment,
        catalog: MAIVoiceCatalog,
        session: URLSession,
        apiKey: String
    ) async throws -> Data {
        let voices = try await catalog.voices(for: segment.model)
        try Task.checkCancellation()
        let voice = try MAIVoiceCatalog.selectVoice(voices, languageID: segment.languageID, preferredName: segment.voiceName)
        let request = try makeRequest(text: segment.text, model: segment.model, voice: voice, apiKey: apiKey)
        return try await fetchBoundedData(
            session: session,
            request: request,
            maximumBytes: 8_388_608,
            overflowError: .invalidAudio
        ) { response in
            try validateResponse(response)
        }
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

    nonisolated static func fetchBoundedData(
        session: URLSession,
        request: URLRequest,
        maximumBytes: Int,
        overflowError: MAIVoiceError,
        validateResponse: @escaping @Sendable (URLResponse) throws -> Void
    ) async throws -> Data {
        try Task.checkCancellation()
        let task = session.dataTask(with: request)
        let delegate = BoundedDataTaskDelegate(
            maximumBytes: maximumBytes,
            overflowError: overflowError,
            validateResponse: validateResponse
        )
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                delegate.start(task: task, continuation: continuation)
            }
        } onCancel: {
            task.cancel()
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

private final class BoundedDataTaskDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private let maximumBytes: Int
    private let overflowError: MAIVoiceError
    private let validateResponse: @Sendable (URLResponse) throws -> Void
    private var continuation: CheckedContinuation<Data, Error>?
    private var buffer = Data()
    private var selfRetain: BoundedDataTaskDelegate?

    init(
        maximumBytes: Int,
        overflowError: MAIVoiceError,
        validateResponse: @escaping @Sendable (URLResponse) throws -> Void
    ) {
        self.maximumBytes = maximumBytes
        self.overflowError = overflowError
        self.validateResponse = validateResponse
    }

    func start(task: URLSessionDataTask, continuation: CheckedContinuation<Data, Error>) {
        lock.withLock {
            self.continuation = continuation
            self.selfRetain = self
        }
        task.delegate = self
        task.resume()
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

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void
    ) {
        do {
            try validateResponse(response)
            if response.expectedContentLength > Int64(maximumBytes) {
                throw overflowError
            }
            if response.expectedContentLength > 0 {
                let capacity = min(Int(response.expectedContentLength), maximumBytes)
                lock.withLock { buffer.reserveCapacity(capacity) }
            }
            completionHandler(.allow)
        } catch {
            completionHandler(.cancel)
            finish(with: .failure(error))
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        let overflowed = lock.withLock { () -> Bool in
            guard continuation != nil else { return false }
            if buffer.count + data.count > maximumBytes {
                return true
            }
            buffer.append(data)
            return false
        }
        if overflowed {
            dataTask.cancel()
            finish(with: .failure(overflowError))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            if (error as? URLError)?.code == .cancelled {
                finish(with: .failure(CancellationError()))
            } else {
                finish(with: .failure(error))
            }
        } else {
            let data = lock.withLock { buffer }
            finish(with: .success(data))
        }
    }

    private func finish(with result: Result<Data, Error>) {
        let pending = lock.withLock { () -> CheckedContinuation<Data, Error>? in
            let cont = continuation
            continuation = nil
            selfRetain = nil
            return cont
        }
        pending?.resume(with: result)
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
