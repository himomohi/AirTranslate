// Adapted from john-rocky/eg2-transcribe (Apache-2.0), commit
// e9c1c2653ff2ebe81447394b3cf22e407433dbed, Pipeline/{Stage,Tensor,Transcriber}.swift
// and Audio/AudioDecoder.swift. https://github.com/john-rocky/eg2-transcribe
// AirTranslate 변경: 파일 전체 대신 30초 창 스트리밍, 고정 모델 계약, 입력 제한, 취소 및 직렬 실행을 추가했다.

import AVFoundation
import Foundation
#if canImport(CoreAI)
import CoreAI
#endif

struct EmbeddingGemmaTranscriptionResult: Sendable, Equatable {
    let text: String
    let duration: Double
    let processingSeconds: Double
}

enum EmbeddingGemmaTranscriptionError: LocalizedError {
    case unsupported
    case busy
    case localFileRequired
    case fileTooLarge
    case durationTooLong
    case unsupportedFormat
    case audio(String)
    case model(String)

    var errorDescription: String? {
        switch self {
        case .unsupported: EmbeddingGemmaCopy.unsupported
        case .busy: AppText.localized(
            english: "The previous transcription is finishing. Try again shortly.",
            korean: "이전 전사가 종료되는 중입니다. 잠시 후 다시 시도해 주세요.",
            japanese: "前の文字起こしを終了しています。しばらくしてから再試行してください。",
            chineseSimplified: "上一次转写正在结束。请稍后重试。")
        case .localFileRequired: AppText.localized(
            english: "Choose a local audio file.", korean: "로컬 오디오 파일을 선택해 주세요.",
            japanese: "ローカルの音声ファイルを選択してください。", chineseSimplified: "请选择本地音频文件。")
        case .fileTooLarge: AppText.localized(
            english: "Choose an audio file no larger than 2 GB.", korean: "2GB 이하의 오디오 파일을 선택해 주세요.",
            japanese: "2 GB以下の音声ファイルを選択してください。", chineseSimplified: "请选择不超过 2 GB 的音频文件。")
        case .durationTooLong: AppText.localized(
            english: "Experimental transcription supports audio up to 60 minutes.",
            korean: "실험 전사는 60분 이하의 파일을 지원합니다.",
            japanese: "実験的な文字起こしは60分以下の音声に対応しています。",
            chineseSimplified: "实验转写支持最长 60 分钟的音频。")
        case .unsupportedFormat: AppText.localized(
            english: "This audio format could not be decoded. Use an 8–192 kHz file with 1–8 channels.",
            korean: "오디오 형식을 읽지 못했습니다. 8~192kHz, 1~8채널 파일을 사용해 주세요.",
            japanese: "音声形式を読み取れません。8～192 kHz、1～8チャンネルのファイルを使用してください。",
            chineseSimplified: "无法解码此音频格式。请使用 8–192 kHz、1–8 声道的文件。")
        case .audio: AppText.localized(
            english: "The audio file could not be read or converted. Try another supported audio file.",
            korean: "오디오 파일을 읽거나 변환하지 못했습니다. 지원하는 다른 음원 파일을 사용해 주세요.",
            japanese: "音声ファイルを読み取り・変換できません。対応する別の音声ファイルをお試しください。",
            chineseSimplified: "无法读取或转换音频文件。请尝试其他支持的音频文件。")
        case .model: AppText.localized(
            english: "The local model could not load or process this audio. Try downloading the models again.",
            korean: "로컬 모델을 불러오거나 음원을 처리하지 못했습니다. 모델을 다시 다운로드해 주세요.",
            japanese: "ローカルモデルの読み込みまたは音声処理に失敗しました。モデルを再ダウンロードしてください。",
            chineseSimplified: "本地模型无法加载或处理此音频。请尝试重新下载模型。")
        }
    }
}

#if canImport(CoreAI)
@available(macOS 27.0, *)
actor EmbeddingGemmaTranscriber {
    static let shared = EmbeddingGemmaTranscriber()
    static let maximumDuration: Double = 3600
    static let maximumFileBytes = 2_000_000_000
    private var busy = false

    func transcribe(fileURL: URL, modelDirectory: URL,
                    progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws -> EmbeddingGemmaTranscriptionResult {
        #if !arch(arm64)
        throw EmbeddingGemmaTranscriptionError.unsupported
        #else
        guard !busy else { throw EmbeddingGemmaTranscriptionError.busy }
        busy = true
        defer { busy = false }
        try Task.checkCancellation()
        do {
        let start = ContinuousClock.now
        let audio = try EmbeddingGemmaAudioStream(fileURL: fileURL)
        let reader = try EmbeddingGemmaReaderContract(root: modelDirectory)
        let vocabulary = try reader.loadVocabulary(root: modelDirectory)
        let extractor = try EmbeddingGemmaAudioFeatures(filtersURL: modelDirectory.appendingPathComponent("mel_filters.bin"))
        progress(0)
        let encoder = try await EmbeddingGemmaStage.load(
            url: modelDirectory.appendingPathComponent("macos/eg2_audio_fp16_T3000.aimodel"), neuralEngine: false)
        try Task.checkCancellation()
        let decoder = try await EmbeddingGemmaStage.load(
            url: modelDirectory.appendingPathComponent("macos/eg2_reader_v2_fp16_T750.aimodel"), neuralEngine: true)
        try Task.checkCancellation()
        try Self.validate(encoder: encoder, decoder: decoder)
        var collapse = EmbeddingGemmaCTC(blankID: vocabulary.count)
        var frame0 = 0
        while true {
            try Task.checkCancellation()
            let sample0 = frame0 * 160
            // 다음 유효 프레임까지 먼저 읽어 정확히 30초인 파일의 마지막 창도 구분한다.
            try audio.fill(through: (frame0 + EmbeddingGemmaWindowing.frames) * 160 + 161)
            let totalFrames = EmbeddingGemmaAudioFeatures.frameCount(samples: audio.totalSamples)
            let frames = min(EmbeddingGemmaWindowing.frames, totalFrames - frame0)
            if frames <= 0 { break }
            let final = audio.ended && frame0 + frames >= totalFrames
            let first = frame0 == 0
            let from = max(0, sample0 - 160)
            let through = sample0 + (frames - 1) * 160 + 161
            let samples = try audio.samples(in: from..<through)
            let features = try extractor.features(samples, firstFrameSample: sample0 - from, frames: frames)
            var padded = [Float](repeating: 0, count: 3000 * 128)
            padded.replaceSubrange(0..<features.count, with: features)
            var halfMask = [Float](repeating: 0, count: 1500)
            for index in 0..<((frames + 1) / 2) { halfMask[index] = 1 }
            var tokenMask = [Float](repeating: 0, count: 750)
            for index in 0..<EmbeddingGemmaWindowing.tokenCount(frames: frames) { tokenMask[index] = 1 }
            let encoderInput = try encoder.feed([
                "features": .host(padded, shape: [1, 3000, 128]),
                "half_mask": .host(halfMask, shape: [1, 1500]),
            ])
            let encoded = try await encoder.run(encoderInput)
            try Task.checkCancellation()
            guard let soft = encoded["soft_tokens"] else {
                throw EmbeddingGemmaTranscriptionError.model("오디오 인코더 출력이 없습니다.")
            }
            let decoderInput = try decoder.feed([
                "soft_tokens": .tensor(soft),
                "token_mask": .host(tokenMask, shape: [1, 750]),
            ])
            let decoded = try await decoder.run(decoderInput)
            try Task.checkCancellation()
            guard let topIndex = decoded["top1_index"], let topLogit = decoded["top1_logit"],
                  let blankLogit = decoded["blank_logit"] else {
                throw EmbeddingGemmaTranscriptionError.model("단어 전사 출력이 없습니다.")
            }
            let indices = try EmbeddingGemmaTensor.int32s(topIndex)
            let tops = try EmbeddingGemmaTensor.floats(topLogit)
            let blanks = try EmbeddingGemmaTensor.floats(blankLogit)
            guard indices.count == 750, tops.count == 750, blanks.count == 750 else {
                throw EmbeddingGemmaTranscriptionError.model("단어 전사 출력의 길이가 올바르지 않습니다.")
            }
            let keep = try EmbeddingGemmaWindowing.keptTokens(frames: frames, first: first, final: final)
            let labels = try keep.map {
                try EmbeddingGemmaCTC.label(index: indices[$0], top: tops[$0], blank: blanks[$0], blankID: vocabulary.count)
            }
            try collapse.append(labels)
            progress(final ? 1 : min(0.99, Double(sample0 + frames * 160) / max(1, audio.estimatedSampleCount)))
            if final { break }
            frame0 += EmbeddingGemmaWindowing.stepFrames
            audio.discard(before: max(0, frame0 * 160 - 160))
        }
        try Task.checkCancellation()
        progress(1)
        let elapsed = start.duration(to: .now).components
        return EmbeddingGemmaTranscriptionResult(
            text: collapse.words.map { vocabulary[$0] }.joined(separator: " "),
            duration: Double(audio.totalSamples) / 16_000,
            processingSeconds: Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as EmbeddingGemmaTranscriptionError {
            throw error
        } catch {
            throw EmbeddingGemmaTranscriptionError.model("로컬 추론 처리에 실패했습니다.")
        }
        #endif
    }

    private static func validate(encoder: EmbeddingGemmaStage, decoder: EmbeddingGemmaStage) throws {
        guard encoder.inputs.keys.sorted() == ["features", "half_mask"],
              encoder.inputs["features"]?.shape == [1, 3000, 128],
              encoder.inputs["half_mask"]?.shape == [1, 1500],
              encoder.outputs["soft_tokens"]?.shape == [1, 750, 512],
              decoder.inputs.keys.sorted() == ["soft_tokens", "token_mask"],
              decoder.inputs["soft_tokens"]?.shape == [1, 750, 512],
              decoder.inputs["token_mask"]?.shape == [1, 750] else {
            throw EmbeddingGemmaTranscriptionError.model("설치된 모델의 오디오 입력 계약이 올바르지 않습니다.")
        }
        for name in ["top1_index", "top1_logit", "blank_logit"] {
            guard decoder.outputs[name]?.shape == [1, 750] else {
                throw EmbeddingGemmaTranscriptionError.model("설치된 모델의 단어 출력 계약이 올바르지 않습니다.")
            }
        }
    }
}

@available(macOS 27.0, *)
private struct EmbeddingGemmaReaderContract {
    private struct Config: Decodable {
        struct Window: Decodable {
            let seconds: Double
            let left_overlap_tokens: Int
            let right_extra_tokens: Int
        }
        let version: String
        let vocab: String
        let n_vocab: Int
        let window: Window
    }

    init(root: URL) throws {
        let config = try JSONDecoder().decode(Config.self, from: Data(contentsOf: root.appendingPathComponent("reader_config.json")))
        guard config.version == "v2", config.vocab == "vocab.txt", config.n_vocab == 200_000,
              config.window.seconds == 30, config.window.left_overlap_tokens == 96,
              config.window.right_extra_tokens == 1 else {
            throw EmbeddingGemmaTranscriptionError.model("이 실험 전사에서 지원하는 v2 모델이 아닙니다.")
        }
    }

    func loadVocabulary(root: URL) throws -> [String] {
        let contents = try String(contentsOf: root.appendingPathComponent("vocab.txt"), encoding: .utf8)
        var words = contents.components(separatedBy: "\n")
        if words.last == "" { words.removeLast() }
        guard words.count == 200_000, words.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            throw EmbeddingGemmaTranscriptionError.model("모델의 20만 단어 사전이 올바르지 않습니다.")
        }
        return words
    }
}

/// 출력 PCM은 현재 창+왼쪽 문맥+작은 변환 버퍼만 보관한다.
@available(macOS 27.0, *)
private final class EmbeddingGemmaAudioStream: @unchecked Sendable {
    let estimatedSampleCount: Double
    private let file: AVAudioFile
    private let input: AVAudioPCMBuffer
    private let output: AVAudioPCMBuffer?
    private let converter: AVAudioConverter?
    private let chunk: AVAudioFrameCount = 16_384
    private var converterEnded = false
    private var readError: Error?
    private var buffered: [Float] = []
    private var bufferStart = 0
    private(set) var ended = false
    private(set) var totalSamples = 0

    init(fileURL: URL) throws {
        guard fileURL.isFileURL else { throw EmbeddingGemmaTranscriptionError.localFileRequired }
        let values: URLResourceValues
        do { values = try fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]) }
        catch { throw EmbeddingGemmaTranscriptionError.audio("음원 파일 정보를 읽지 못했습니다.") }
        guard values.isRegularFile == true, let bytes = values.fileSize else {
            throw EmbeddingGemmaTranscriptionError.audio("음원이 읽을 수 있는 일반 파일이 아닙니다.")
        }
        guard bytes <= EmbeddingGemmaTranscriber.maximumFileBytes else {
            throw EmbeddingGemmaTranscriptionError.fileTooLarge
        }
        do { file = try AVAudioFile(forReading: fileURL) }
        catch { throw EmbeddingGemmaTranscriptionError.unsupportedFormat }
        let source = file.processingFormat
        guard source.sampleRate.isFinite, (8_000...192_000).contains(source.sampleRate),
              (1...8).contains(source.channelCount), file.length >= 0 else {
            throw EmbeddingGemmaTranscriptionError.unsupportedFormat
        }
        let duration = Double(file.length) / source.sampleRate
        guard duration <= EmbeddingGemmaTranscriber.maximumDuration else {
            throw EmbeddingGemmaTranscriptionError.durationTooLong
        }
        estimatedSampleCount = duration * 16_000
        guard let input = AVAudioPCMBuffer(pcmFormat: source, frameCapacity: chunk) else {
            throw EmbeddingGemmaTranscriptionError.audio("오디오 읽기 버퍼를 만들지 못했습니다.")
        }
        self.input = input
        if source.sampleRate == 16_000, source.channelCount == 1, source.commonFormat == .pcmFormatFloat32 {
            converter = nil
            output = nil
        } else {
            guard let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false),
                  let converter = AVAudioConverter(from: source, to: target),
                  let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: 16_384) else {
                throw EmbeddingGemmaTranscriptionError.audio("16kHz 모노 오디오로 변환하지 못했습니다.")
            }
            converter.downmix = true
            converter.sampleRateConverterQuality = AVAudioQuality.max.rawValue
            self.converter = converter
            self.output = output
        }
    }

    func fill(through end: Int) throws {
        while totalSamples < end, !ended {
            try Task.checkCancellation()
            if let converter, let output {
                output.frameLength = 0
                var error: NSError?
                let status = converter.convert(to: output, error: &error) { [self] requested, state in
                    nextInput(requested: requested, status: state)
                }
                if readError != nil { throw EmbeddingGemmaTranscriptionError.audio("오디오 파일을 읽지 못했습니다.") }
                if status == .error { throw EmbeddingGemmaTranscriptionError.audio("오디오 변환에 실패했습니다.") }
                try append(output)
                if status == .endOfStream { ended = true }
                if status == .inputRanDry, converterEnded, output.frameLength == 0 { ended = true }
                if output.frameLength == 0, status != .endOfStream, !converterEnded {
                    throw EmbeddingGemmaTranscriptionError.audio("오디오 디코더가 데이터를 반환하지 않았습니다.")
                }
            } else {
                do { try file.read(into: input, frameCount: chunk) }
                catch { throw EmbeddingGemmaTranscriptionError.audio("오디오 파일을 읽지 못했습니다.") }
                try append(input)
                if input.frameLength == 0 || file.framePosition >= file.length { ended = true }
            }
        }
    }

    func samples(in range: Range<Int>) throws -> [Float] {
        guard range.lowerBound >= bufferStart, range.upperBound <= totalSamples else {
            throw EmbeddingGemmaTranscriptionError.audio("오디오 스트리밍 범위를 읽지 못했습니다.")
        }
        return Array(buffered[(range.lowerBound - bufferStart)..<(range.upperBound - bufferStart)])
    }

    func discard(before sample: Int) {
        let count = min(buffered.count, max(0, sample - bufferStart))
        buffered.removeFirst(count)
        bufferStart += count
    }

    private func append(_ buffer: AVAudioPCMBuffer) throws {
        let count = Int(buffer.frameLength)
        guard count > 0 else { return }
        guard let data = buffer.floatChannelData?[0] else {
            throw EmbeddingGemmaTranscriptionError.audio("오디오 표본을 읽지 못했습니다.")
        }
        guard totalSamples + count <= Int(EmbeddingGemmaTranscriber.maximumDuration * 16_000) else {
            throw EmbeddingGemmaTranscriptionError.durationTooLong
        }
        buffered.append(contentsOf: UnsafeBufferPointer(start: data, count: count))
        totalSamples += count
    }

    private func nextInput(requested: AVAudioPacketCount, status: UnsafeMutablePointer<AVAudioConverterInputStatus>) -> AVAudioBuffer? {
        guard !converterEnded, file.framePosition < file.length else {
            converterEnded = true
            status.pointee = .endOfStream
            return nil
        }
        do { try file.read(into: input, frameCount: min(chunk, max(1, requested))) }
        catch {
            readError = error
            converterEnded = true
            status.pointee = .endOfStream
            return nil
        }
        if input.frameLength == 0 {
            converterEnded = true
            status.pointee = .endOfStream
            return nil
        }
        status.pointee = .haveData
        return input
    }
}

// 같은 InferenceFunction의 동시 실행은 출력 버퍼를 손상시키므로 재진입도 거부한다.
@available(macOS 27.0, *)
private actor EmbeddingGemmaStage {
    struct Spec: Sendable {
        let shape: [Int]
        let scalarType: NDArray.ScalarType
    }
    enum Value: Sendable {
        case host([Float], shape: [Int])
        case tensor(NDArray)
    }
    nonisolated let inputs: [String: Spec]
    nonisolated let outputs: [String: Spec]
    private let model: AIModel
    private let function: InferenceFunction
    private var busy = false

    private init(model: AIModel, function: InferenceFunction, inputs: [String: Spec], outputs: [String: Spec]) {
        self.model = model
        self.function = function
        self.inputs = inputs
        self.outputs = outputs
    }

    static func load(url: URL, neuralEngine: Bool) async throws -> EmbeddingGemmaStage {
        let options = SpecializationOptions(preferredComputeUnitKind: neuralEngine ? .neuralEngine : .gpu)
        let model = try await AIModel(contentsOf: url, options: options)
        try Task.checkCancellation()
        guard let function = try model.loadFunction(named: "main"), function.descriptor.stateNames.isEmpty else {
            throw EmbeddingGemmaTranscriptionError.model("상태 없는 main 전사 함수를 읽지 못했습니다.")
        }
        let descriptor = function.descriptor
        var inputs: [String: Spec] = [:]
        var outputs: [String: Spec] = [:]
        for name in descriptor.inputNames {
            guard case .ndArray(let array) = descriptor.inputDescriptor(of: name), !array.hasDynamicShape else {
                throw EmbeddingGemmaTranscriptionError.model("전사 모델 입력은 고정 크기 배열이어야 합니다.")
            }
            inputs[name] = Spec(shape: array.shape, scalarType: array.scalarType)
        }
        for name in descriptor.outputNames {
            guard case .ndArray(let array) = descriptor.outputDescriptor(of: name), !array.hasDynamicShape else {
                throw EmbeddingGemmaTranscriptionError.model("전사 모델 출력은 고정 크기 배열이어야 합니다.")
            }
            outputs[name] = Spec(shape: array.shape, scalarType: array.scalarType)
        }
        return EmbeddingGemmaStage(model: model, function: function, inputs: inputs, outputs: outputs)
    }

    nonisolated func feed(_ values: [String: Value]) throws -> [String: NDArray] {
        var arrays: [String: NDArray] = [:]
        for (name, spec) in inputs {
            guard let value = values[name] else {
                throw EmbeddingGemmaTranscriptionError.model("전사 모델 입력 \(name)이 없습니다.")
            }
            switch value {
            case .host(let floats, let shape):
                guard shape == spec.shape else { throw EmbeddingGemmaTranscriptionError.model("전사 입력 크기가 올바르지 않습니다.") }
                arrays[name] = try EmbeddingGemmaTensor.make(floats, shape: shape, as: spec.scalarType)
            case .tensor(let array):
                guard array.shape == spec.shape else { throw EmbeddingGemmaTranscriptionError.model("전사 단계 사이 배열 크기가 다릅니다.") }
                arrays[name] = try EmbeddingGemmaTensor.copy(array, as: spec.scalarType)
            }
        }
        return arrays
    }

    func run(_ feed: [String: NDArray]) async throws -> [String: NDArray] {
        guard !busy else { throw EmbeddingGemmaTranscriptionError.busy }
        busy = true
        defer { busy = false }
        try Task.checkCancellation()
        var result = try await function.run(inputs: feed)
        try Task.checkCancellation()
        var arrays: [String: NDArray] = [:]
        for name in outputs.keys {
            guard let array = result.remove(name)?.ndArray else {
                throw EmbeddingGemmaTranscriptionError.model("전사 모델 출력 \(name)이 없습니다.")
            }
            arrays[name] = array
        }
        return arrays
    }
}

// CoreAI 배열 stride를 보존하며 float16/float32를 변환한다.
@available(macOS 27.0, *)
private enum EmbeddingGemmaTensor {
    static func make(_ values: UnsafeBufferPointer<Float>, shape: [Int], as type: NDArray.ScalarType) throws -> NDArray {
        guard values.count == shape.reduce(1, *), let source = values.baseAddress else {
            throw EmbeddingGemmaTranscriptionError.model("전사 배열의 값 개수와 크기가 다릅니다.")
        }
        let dense = denseStrides(shape)
        var array = NDArray(shape: shape, scalarType: type)
        switch type {
        case .float16:
            array.mutableView(as: Float16.self).withUnsafeMutablePointer { p, _, strides in
                transfer(source, dense, p, ints(strides), shape) { Float16($0) }
            }
        case .float32:
            array.mutableView(as: Float.self).withUnsafeMutablePointer { p, _, strides in
                transfer(source, dense, p, ints(strides), shape) { $0 }
            }
        default:
            throw EmbeddingGemmaTranscriptionError.model("전사 배열 입력 형식을 지원하지 않습니다.")
        }
        return array
    }

    static func make(_ values: [Float], shape: [Int], as type: NDArray.ScalarType) throws -> NDArray {
        try values.withUnsafeBufferPointer { try make($0, shape: shape, as: type) }
    }

    static func floats(_ array: NDArray) throws -> [Float] {
        guard array.interleaveLayout == nil else { throw EmbeddingGemmaTranscriptionError.model("교차 배열 출력을 지원하지 않습니다.") }
        let shape = array.shape
        let dense = denseStrides(shape)
        var out = [Float](repeating: 0, count: shape.reduce(1, *))
        try out.withUnsafeMutableBufferPointer { dst in
            guard let d = dst.baseAddress else { return }
            switch array.scalarType {
            case .float16:
                array.view(as: Float16.self).withUnsafePointer { p, _, strides in
                    transfer(p, ints(strides), d, dense, shape) { Float($0) }
                }
            case .float32:
                array.view(as: Float.self).withUnsafePointer { p, _, strides in
                    transfer(p, ints(strides), d, dense, shape) { $0 }
                }
            default:
                throw EmbeddingGemmaTranscriptionError.model("전사 배열은 float16 또는 float32여야 합니다.")
            }
        }
        return out
    }

    static func int32s(_ array: NDArray) throws -> [Int32] {
        guard array.interleaveLayout == nil else { throw EmbeddingGemmaTranscriptionError.model("교차 배열 출력을 지원하지 않습니다.") }
        guard array.scalarType == .int32 else { throw EmbeddingGemmaTranscriptionError.model("단어 번호 배열은 int32여야 합니다.") }
        let shape = array.shape
        let dense = denseStrides(shape)
        var out = [Int32](repeating: 0, count: shape.reduce(1, *))
        out.withUnsafeMutableBufferPointer { dst in
            guard let d = dst.baseAddress else { return }
            array.view(as: Int32.self).withUnsafePointer { p, _, strides in
                transfer(p, ints(strides), d, dense, shape) { $0 }
            }
        }
        return out
    }

    static func copy(_ array: NDArray, as type: NDArray.ScalarType) throws -> NDArray {
        guard array.interleaveLayout == nil else { throw EmbeddingGemmaTranscriptionError.model("교차 배열 출력을 지원하지 않습니다.") }
        let shape = array.shape
        var out = NDArray(shape: shape, scalarType: type)
        switch (array.scalarType, type) {
        case (.float16, .float16):
            array.view(as: Float16.self).withUnsafePointer { p, _, s in
                out.mutableView(as: Float16.self).withUnsafeMutablePointer { q, _, t in transfer(p, ints(s), q, ints(t), shape) { $0 } }
            }
        case (.float32, .float16):
            array.view(as: Float.self).withUnsafePointer { p, _, s in
                out.mutableView(as: Float16.self).withUnsafeMutablePointer { q, _, t in transfer(p, ints(s), q, ints(t), shape) { Float16($0) } }
            }
        case (.float32, .float32):
            array.view(as: Float.self).withUnsafePointer { p, _, s in
                out.mutableView(as: Float.self).withUnsafeMutablePointer { q, _, t in transfer(p, ints(s), q, ints(t), shape) { $0 } }
            }
        case (.float16, .float32):
            array.view(as: Float16.self).withUnsafePointer { p, _, s in
                out.mutableView(as: Float.self).withUnsafeMutablePointer { q, _, t in transfer(p, ints(s), q, ints(t), shape) { Float($0) } }
            }
        default:
            throw EmbeddingGemmaTranscriptionError.model("전사 단계 사이 배열 형식을 변환하지 못했습니다.")
        }
        return out
    }

    static func denseStrides(_ shape: [Int]) -> [Int] {
        var strides = [Int](repeating: 1, count: shape.count)
        var step = 1
        for d in stride(from: shape.count - 1, through: 0, by: -1) {
            strides[d] = step
            step *= shape[d]
        }
        return strides
    }

    @inline(__always)
    private static func transfer<S, D>(_ src: UnsafePointer<S>, _ srcStrides: [Int], _ dst: UnsafeMutablePointer<D>,
                                       _ dstStrides: [Int], _ shape: [Int], _ convert: (S) -> D) {
        let total = shape.reduce(1, *)
        guard total > 0 else { return }
        let dense = denseStrides(shape)
        if srcStrides == dense && dstStrides == dense {
            for i in 0..<total { dst[i] = convert(src[i]) }
            return
        }
        let rank = shape.count
        let inner = shape[rank - 1]
        let si = srcStrides[rank - 1], di = dstStrides[rank - 1]
        var index = [Int](repeating: 0, count: rank)
        for _ in 0..<(total / inner) {
            var so = 0, dOffset = 0
            for d in 0..<(rank - 1) {
                so += index[d] * srcStrides[d]
                dOffset += index[d] * dstStrides[d]
            }
            for j in 0..<inner { dst[dOffset + j * di] = convert(src[so + j * si]) }
            var d = rank - 2
            while d >= 0 {
                index[d] += 1
                if index[d] < shape[d] { break }
                index[d] = 0
                d -= 1
            }
        }
    }

    private static func ints(_ span: Span<Int>) -> [Int] {
        var out: [Int] = []
        out.reserveCapacity(span.count)
        for i in 0..<span.count { out.append(span[i]) }
        return out
    }
}
#endif
