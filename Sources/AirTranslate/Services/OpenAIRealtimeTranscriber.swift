import AVFoundation
import CoreMedia
import Foundation

struct OpenAIRealtimeProviderConfig: Sendable {
    enum Kind: Sendable {
        case openAI
        case azure
    }

    let kind: Kind
    let host: String
    let apiKey: String

    static let openAIHost = "api.openai.com"

    static func openAI(apiKey: String) -> OpenAIRealtimeProviderConfig {
        OpenAIRealtimeProviderConfig(
            kind: .openAI,
            host: openAIHost,
            apiKey: apiKey
        )
    }

    static func azure(
        host: String,
        apiKey: String
    ) -> OpenAIRealtimeProviderConfig {
        OpenAIRealtimeProviderConfig(
            kind: .azure,
            host: host,
            apiKey: apiKey
        )
    }

    func transcriptionURL() -> URL? {
        switch kind {
        case .openAI:
            return URL(string: "wss://\(host)/v1/realtime?intent=transcription")
        case .azure:
            return URL(string: "wss://\(host)/openai/v1/realtime?intent=transcription")
        }
    }

    func translationURL(modelID: String) -> URL? {
        let encodedModel = modelID
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? modelID
        switch kind {
        case .openAI:
            return URL(string: "wss://\(host)/v1/realtime/translations?model=\(encodedModel)")
        case .azure:
            return URL(string: "wss://\(host)/openai/v1/realtime/translations?model=\(encodedModel)")
        }
    }

    func apply(to request: inout URLRequest) {
        switch kind {
        case .openAI:
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        case .azure:
            request.setValue(apiKey, forHTTPHeaderField: "api-key")
        }
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}

final class OpenAIRealtimeTranscriber: @unchecked Sendable {
    static let realtimeAudioSampleRate = 24_000
    private static let maxAudioChunkMilliseconds = 80
    private static let bytesPerPCM16Sample = 2
    private static let maxPCM16AudioChunkByteCount = realtimeAudioSampleRate
        * bytesPerPCM16Sample
        * maxAudioChunkMilliseconds
        / 1_000

    enum OutputMode {
        case transcription
        case translationOnly
    }

    weak var delegate: LiveSpeechTranscriberDelegate?

    private let stateLock = NSLock()
    private let conversionLock = NSLock()
    private var webSocketTask: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var language = LanguageOption.supported[0]
    private var outputMode = OutputMode.transcription
    private var isPaused = false
    private var realtimeTranscriptText = ""

    func start(
        language: LanguageOption,
        model: OpenAIRealtimeTranscriptionModel,
        modelIDOverride: String? = nil,
        providerConfig: OpenAIRealtimeProviderConfig
    ) async throws {
        let trimmedOverride = modelIDOverride?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nonEmpty
        let resolvedID = trimmedOverride ?? model.rawValue
        try await start(
            language: language,
            modelID: resolvedID,
            outputMode: .transcription,
            isEnabled: model.isEnabled,
            providerConfig: providerConfig
        )
    }

    func startRealtimeTranslationOnly(
        language: LanguageOption,
        model: OpenAIRealtimeTranslationModel,
        modelIDOverride: String? = nil,
        providerConfig: OpenAIRealtimeProviderConfig
    ) async throws {
        let trimmedOverride = modelIDOverride?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nonEmpty
        let resolvedID = trimmedOverride ?? model.apiModelID
        try await start(
            language: language,
            modelID: resolvedID,
            outputMode: .translationOnly,
            isEnabled: model.usesRealtimeAudioTranslation,
            providerConfig: providerConfig
        )
    }

    private func start(
        language: LanguageOption,
        modelID: String,
        outputMode: OutputMode,
        isEnabled: Bool,
        providerConfig: OpenAIRealtimeProviderConfig
    ) async throws {
        stop()

        guard isEnabled else {
            return
        }
        guard !providerConfig.apiKey.isEmpty else {
            throw OpenAITranslationError.missingAPIKey
        }

        self.language = language
        self.outputMode = outputMode
        realtimeTranscriptText = ""
        let url: URL
        switch outputMode {
        case .transcription:
            guard let transcriptionURL = providerConfig.transcriptionURL() else {
                throw OpenAITranslationError.transcriptionEndpointUnsupported
            }
            url = transcriptionURL
        case .translationOnly:
            guard let translationURL = providerConfig.translationURL(modelID: modelID) else {
                throw OpenAITranslationError.invalidResponse
            }
            url = translationURL
        }

        var request = URLRequest(url: url)
        providerConfig.apply(to: &request)

        let webSocketTask = URLSession.shared.webSocketTask(with: request)
        self.webSocketTask = webSocketTask
        webSocketTask.resume()

        try await sendSessionUpdate(
            language: language,
            modelID: modelID,
            providerKind: providerConfig.kind
        )
        receiveTask = Task { [weak self] in
            await self?.receiveLoop()
        }
    }

    func append(_ sampleBuffer: CMSampleBuffer) {
        stateLock.lock()
        let isPaused = isPaused
        let webSocketTask = webSocketTask
        let audioAppendEventType = outputMode.audioAppendEventType
        stateLock.unlock()

        guard !isPaused, let webSocketTask else { return }

        conversionLock.lock()
        let audioChunks = pcm16Base64AudioChunks(from: sampleBuffer)
        conversionLock.unlock()

        for audio in audioChunks {
            let event = OpenAIRealtimeAudioAppendEvent(
                type: audioAppendEventType,
                audio: audio
            )
            guard let data = try? JSONEncoder().encode(event),
                  let text = String(data: data, encoding: .utf8) else { continue }

            webSocketTask.send(.string(text)) { [weak self] error in
                guard let error, let self else { return }
                self.delegate?.liveSpeechTranscriber(self.proxyTranscriber, didFail: error)
            }
        }
    }

    func setPaused(_ isPaused: Bool) {
        stateLock.lock()
        self.isPaused = isPaused
        stateLock.unlock()
    }

    func stop() {
        setPaused(false)
        receiveTask?.cancel()
        receiveTask = nil
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        realtimeTranscriptText = ""
    }

    private func sendSessionUpdate(
        language: LanguageOption,
        modelID: String,
        providerKind: OpenAIRealtimeProviderConfig.Kind
    ) async throws {
        let text = try Self.sessionUpdatePayload(
            language: language,
            modelID: modelID,
            outputMode: outputMode,
            providerKind: providerKind
        )
        try await send(text)
    }

    static func sessionUpdatePayload(
        language: LanguageOption,
        modelID: String,
        outputMode: OutputMode,
        providerKind: OpenAIRealtimeProviderConfig.Kind = .openAI
    ) throws -> String {
        let data: Data
        switch outputMode {
        case .transcription:
            let event = OpenAIRealtimeTranscriptionSessionUpdateEvent(
                session: OpenAIRealtimeTranscriptionSession(
                    type: "transcription",
                    audio: OpenAIRealtimeTranscriptionAudio(
                        input: OpenAIRealtimeTranscriptionAudioInput(
                            format: OpenAIRealtimeAudioFormat(type: "audio/pcm", rate: Self.realtimeAudioSampleRate),
                            transcription: OpenAIRealtimeTranscriptionConfig(
                                model: modelID,
                                language: language.openAILanguageCode
                            ),
                            turnDetection: .lowLatencyServerVAD,
                            noiseReduction: OpenAIRealtimeNoiseReduction(type: "near_field")
                        )
                    )
                )
            )
            data = try JSONEncoder().encode(event)
        case .translationOnly:
            let input: OpenAIRealtimeTranslationAudioInput?
            switch providerKind {
            case .openAI:
                input = nil
            case .azure:
                input = OpenAIRealtimeTranslationAudioInput(
                    transcription: OpenAIRealtimeTranscriptionConfig(
                        model: modelID
                    ),
                    noiseReduction: OpenAIRealtimeNoiseReduction(type: "near_field")
                )
            }

            let event = OpenAIRealtimeTranslationSessionUpdateEvent(
                session: OpenAIRealtimeTranslationSession(
                    audio: OpenAIRealtimeTranslationAudio(
                        input: input,
                        output: OpenAIRealtimeTranslationAudioOutput(
                            language: language.openAILanguageCode
                        )
                    )
                )
            )
            data = try JSONEncoder().encode(event)
        }

        guard let text = String(data: data, encoding: .utf8) else {
            throw OpenAITranslationError.invalidResponse
        }
        return text
    }

    private func send(_ text: String) async throws {
        guard let webSocketTask else { return }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            webSocketTask.send(.string(text)) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private func receiveLoop() async {
        while !Task.isCancelled {
            guard let webSocketTask else { return }
            do {
                let message = try await webSocketTask.receive()
                guard case let .string(text) = message else { continue }
                handleEventText(text)
            } catch {
                guard !Task.isCancelled else { return }
                delegate?.liveSpeechTranscriber(proxyTranscriber, didFail: error)
                return
            }
        }
    }

    private func handleEventText(_ text: String) {
        guard let data = text.data(using: .utf8),
              let event = try? JSONDecoder().decode(OpenAIRealtimeTranscriptionEvent.self, from: data)
        else {
            return
        }

        switch event.type {
        case "conversation.item.input_audio_transcription.delta":
            guard let delta = event.delta, !delta.isEmpty else { return }
            appendRealtimeTranscriptDelta(delta)
        case "conversation.item.input_audio_transcription.completed":
            guard let transcript = event.transcript, !transcript.isEmpty else { return }
            publish(text: transcript)
            realtimeTranscriptText = ""
        case "session.output_transcript.delta":
            guard outputMode == .translationOnly,
                  let delta = event.delta,
                  !delta.isEmpty else { return }
            appendRealtimeTranscriptDelta(delta)
        case "session.output_transcript.done":
            guard outputMode == .translationOnly,
                  let transcript = event.transcript,
                  !transcript.isEmpty else { return }
            publish(text: transcript)
            realtimeTranscriptText = ""
        case "session.output_audio.delta":
            guard outputMode == .translationOnly,
                  let delta = event.delta,
                  !delta.isEmpty else { return }
            delegate?.liveSpeechTranscriber(
                proxyTranscriber,
                didOutputAudioPCM16Base64: delta,
                sampleRate: Double(Self.realtimeAudioSampleRate)
            )
        case "error":
            delegate?.liveSpeechTranscriber(proxyTranscriber, didFail: OpenAIRealtimeTranscriberError.server(event.error?.message))
        default:
            return
        }
    }

    private func appendRealtimeTranscriptDelta(_ delta: String) {
        // OpenAI Realtime occasionally emits U+FFFD when a model-token boundary
        // splits a multi-byte character. The full transcript arrives correctly
        // on `*.done`, so strip FFFD from partials to avoid showing � in the UI.
        let sanitized = delta.replacingOccurrences(of: "\u{FFFD}", with: "")
        guard !sanitized.isEmpty else { return }
        realtimeTranscriptText += sanitized
        publish(text: realtimeTranscriptText)
    }

    private func publish(text: String) {
        switch outputMode {
        case .transcription:
            delegate?.liveSpeechTranscriber(
                proxyTranscriber,
                didRecognize: text,
                language: language,
                confidence: 0.5
            )
        case .translationOnly:
            delegate?.liveSpeechTranscriber(
                proxyTranscriber,
                didTranslate: text,
                language: language,
                confidence: 0.5
            )
        }
    }

    private var proxyTranscriber: LiveSpeechTranscriber {
        LiveSpeechTranscriber()
    }

    private func pcm16Base64AudioChunks(from sampleBuffer: CMSampleBuffer) -> [String] {
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
              let streamDescription = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription)
        else {
            return []
        }

        var listSize = 0
        CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: &listSize,
            bufferListOut: nil,
            bufferListSize: 0,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: 0,
            blockBufferOut: nil
        )
        guard listSize > 0 else { return [] }

        return withUnsafeTemporaryAllocation(
            byteCount: listSize,
            alignment: MemoryLayout<AudioBufferList>.alignment
        ) { rawList -> [String] in
            guard let baseAddress = rawList.baseAddress else { return [] }

            let audioBufferList = baseAddress.bindMemory(to: AudioBufferList.self, capacity: 1)
            var blockBuffer: CMBlockBuffer?
            let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
                sampleBuffer,
                bufferListSizeNeededOut: nil,
                bufferListOut: audioBufferList,
                bufferListSize: listSize,
                blockBufferAllocator: kCFAllocatorDefault,
                blockBufferMemoryAllocator: kCFAllocatorDefault,
                flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
                blockBufferOut: &blockBuffer
            )
            guard status == noErr else { return [] }

            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            var audioData = Data()
            let sourceIsFloat = streamDescription.pointee.mFormatFlags & kAudioFormatFlagIsFloat != 0
            for buffer in buffers {
                guard let data = buffer.mData else { continue }

                if sourceIsFloat {
                    let sampleCount = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
                    let samples = data.bindMemory(to: Float.self, capacity: sampleCount)
                    for index in 0..<sampleCount {
                        let clamped = max(-1, min(1, samples[index]))
                        var sample = Int16(clamped * Float(Int16.max)).littleEndian
                        withUnsafeBytes(of: &sample) { audioData.append(contentsOf: $0) }
                    }
                } else {
                    audioData.append(data.assumingMemoryBound(to: UInt8.self), count: Int(buffer.mDataByteSize))
                }
            }

            guard !audioData.isEmpty else { return [] }
            return base64PCM16Chunks(from: audioData)
        }
    }

    private func base64PCM16Chunks(from audioData: Data) -> [String] {
        guard audioData.count > Self.maxPCM16AudioChunkByteCount else {
            return [audioData.base64EncodedString()]
        }

        var chunks: [String] = []
        var offset = 0
        while offset < audioData.count {
            let end = min(offset + Self.maxPCM16AudioChunkByteCount, audioData.count)
            chunks.append(Data(audioData[offset..<end]).base64EncodedString())
            offset = end
        }
        return chunks
    }
}

private struct OpenAIRealtimeTranscriptionSessionUpdateEvent: Encodable {
    let type = "session.update"
    let session: OpenAIRealtimeTranscriptionSession
}

private struct OpenAIRealtimeTranslationSessionUpdateEvent: Encodable {
    let type = "session.update"
    let session: OpenAIRealtimeTranslationSession
}

private struct OpenAIRealtimeTranscriptionSession: Encodable {
    let type: String
    let audio: OpenAIRealtimeTranscriptionAudio
}

private struct OpenAIRealtimeTranscriptionAudio: Encodable {
    let input: OpenAIRealtimeTranscriptionAudioInput
}

private struct OpenAIRealtimeTranscriptionAudioInput: Encodable {
    let format: OpenAIRealtimeAudioFormat
    let transcription: OpenAIRealtimeTranscriptionConfig
    let turnDetection: OpenAIRealtimeTurnDetection
    let noiseReduction: OpenAIRealtimeNoiseReduction

    private enum CodingKeys: String, CodingKey {
        case format
        case transcription
        case turnDetection = "turn_detection"
        case noiseReduction = "noise_reduction"
    }
}

private struct OpenAIRealtimeAudioFormat: Encodable {
    let type: String
    let rate: Int
}

private struct OpenAIRealtimeTranslationSession: Encodable {
    let audio: OpenAIRealtimeTranslationAudio
}

private struct OpenAIRealtimeTranslationAudio: Encodable {
    let input: OpenAIRealtimeTranslationAudioInput?
    let output: OpenAIRealtimeTranslationAudioOutput
}

private struct OpenAIRealtimeTranslationAudioInput: Encodable {
    let transcription: OpenAIRealtimeTranscriptionConfig
    let noiseReduction: OpenAIRealtimeNoiseReduction

    private enum CodingKeys: String, CodingKey {
        case transcription
        case noiseReduction = "noise_reduction"
    }
}

private struct OpenAIRealtimeTranslationAudioOutput: Encodable {
    let language: String
}

private struct OpenAIRealtimeTranscriptionConfig: Encodable {
    let model: String
    let language: String?

    init(model: String, language: String? = nil) {
        self.model = model
        self.language = language
    }
}

private struct OpenAIRealtimeTurnDetection: Encodable {
    let type: String
    let threshold: Double?
    let prefixPaddingMilliseconds: Int?
    let silenceDurationMilliseconds: Int?

    static let lowLatencyServerVAD = OpenAIRealtimeTurnDetection(
        type: "server_vad",
        threshold: 0.42,
        prefixPaddingMilliseconds: 120,
        silenceDurationMilliseconds: 220
    )

    init(
        type: String,
        threshold: Double? = nil,
        prefixPaddingMilliseconds: Int? = nil,
        silenceDurationMilliseconds: Int? = nil
    ) {
        self.type = type
        self.threshold = threshold
        self.prefixPaddingMilliseconds = prefixPaddingMilliseconds
        self.silenceDurationMilliseconds = silenceDurationMilliseconds
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case threshold
        case prefixPaddingMilliseconds = "prefix_padding_ms"
        case silenceDurationMilliseconds = "silence_duration_ms"
    }
}

private struct OpenAIRealtimeNoiseReduction: Encodable {
    let type: String
}

private struct OpenAIRealtimeAudioAppendEvent: Encodable {
    let type: String
    let audio: String
}

private struct OpenAIRealtimeTranscriptionEvent: Decodable {
    let type: String
    let delta: String?
    let transcript: String?
    let error: OpenAIRealtimeErrorBody?
}

private struct OpenAIRealtimeErrorBody: Decodable {
    let message: String?
}

private enum OpenAIRealtimeTranscriberError: LocalizedError {
    case server(String?)

    var errorDescription: String? {
        switch self {
        case let .server(message):
            message ?? AppText.openAIInvalidResponse
        }
    }
}

private extension OpenAIRealtimeTranscriber.OutputMode {
    var audioAppendEventType: String {
        switch self {
        case .transcription:
            "input_audio_buffer.append"
        case .translationOnly:
            "session.input_audio_buffer.append"
        }
    }
}

private extension LanguageOption {
    var openAILanguageCode: String {
        String(id.prefix(2))
    }
}
