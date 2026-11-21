import Foundation
import Testing
@testable import AirTranslate

@Suite("EmbeddingGemma 전처리와 CTC 계약")
struct EmbeddingGemmaTranscriberTests {
    @Test func missingAudioReportsAudioFailureBeforeModelLoading() async throws {
        #if canImport(CoreAI) && arch(arm64)
        if #available(macOS 27.0, *) {
            let root = FileManager.default.temporaryDirectory
                .appendingPathComponent("EmbeddingGemmaMissingAudio-\(UUID().uuidString)")
            do {
                _ = try await EmbeddingGemmaTranscriber().transcribe(
                    fileURL: root.appendingPathComponent("missing.wav"),
                    modelDirectory: root.appendingPathComponent("missing-model"))
                Issue.record("존재하지 않는 음원은 모델을 읽기 전에 거부해야 합니다.")
            } catch let error as EmbeddingGemmaTranscriptionError {
                guard case .audio = error else {
                    Issue.record("음원 읽기 실패를 모델 오류로 안내했습니다: \(error)")
                    return
                }
            }
        }
        #endif
    }

    @Test func directoryAudioReportsAudioFailureInsteadOfFileSizeLimit() async throws {
        #if canImport(CoreAI) && arch(arm64)
        if #available(macOS 27.0, *) {
            let root = FileManager.default.temporaryDirectory
                .appendingPathComponent("EmbeddingGemmaDirectoryAudio-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
            defer { try? FileManager.default.removeItem(at: root) }
            do {
                _ = try await EmbeddingGemmaTranscriber().transcribe(
                    fileURL: root, modelDirectory: root.appendingPathComponent("missing-model"))
                Issue.record("디렉터리를 음원으로 처리하면 안 됩니다.")
            } catch let error as EmbeddingGemmaTranscriptionError {
                guard case .audio = error else {
                    Issue.record("일반 파일이 아닌 음원을 크기 제한 오류로 안내했습니다: \(error)")
                    return
                }
            }
        }
        #endif
    }

    @Test func ctcPreservesBoundaryRepeatsAndBlankSeparation() throws {
        var ctc = EmbeddingGemmaCTC(blankID: 9)
        try ctc.append([2, 2, 9, 3])
        try ctc.append([3, 3, 9, 3, 4, 4, 9])
        #expect(ctc.words == [2, 3, 3, 4])
        #expect(ctc.previous == 9)
    }

    @Test func silenceAndEmptyTokensProduceEmptyTranscript() throws {
        var ctc = EmbeddingGemmaCTC(blankID: 9)
        try ctc.append([])
        try ctc.append([9, 9, 9])
        #expect(ctc.words.isEmpty)
        #expect(try EmbeddingGemmaCTC.label(index: 2, top: 1, blank: 1, blankID: 9) == 2)
        #expect(try EmbeddingGemmaCTC.label(index: 2, top: 1, blank: 2, blankID: 9) == 9)
    }

    @Test func invalidReaderOutputsAreRejected() {
        #expect(throws: (any Error).self) {
            try EmbeddingGemmaCTC.label(index: -1, top: 1, blank: 2, blankID: 9)
        }
        #expect(throws: (any Error).self) {
            try EmbeddingGemmaCTC.label(index: 9, top: 1, blank: 2, blankID: 9)
        }
        #expect(throws: (any Error).self) {
            try EmbeddingGemmaCTC.label(index: 2, top: .nan, blank: 2, blankID: 9)
        }
    }

    @Test func overlappingWindowsCoverEveryGlobalTokenOnce() throws {
        for frameCount in [1, 4, 2999, 3000, 3001, 5612, 6000, 9999, 360_000] {
            var covered: [Int] = []
            var frame0 = 0
            while frame0 < frameCount {
                let frames = min(3000, frameCount - frame0)
                let final = frame0 + frames >= frameCount
                let keep = try EmbeddingGemmaWindowing.keptTokens(frames: frames, first: frame0 == 0, final: final)
                covered.append(contentsOf: keep.map { frame0 / 4 + $0 })
                if final { break }
                frame0 += EmbeddingGemmaWindowing.stepFrames
            }
            #expect(covered == Array(0..<EmbeddingGemmaWindowing.tokenCount(frames: frameCount)))
        }
    }

    @Test func validFrameMaskIncludesUnfoldedExtraSample() {
        #expect(EmbeddingGemmaAudioFeatures.frameCount(samples: 160) == 0)
        #expect(EmbeddingGemmaAudioFeatures.frameCount(samples: 161) == 1)
        #expect(EmbeddingGemmaAudioFeatures.frameCount(samples: 320) == 1)
        #expect(EmbeddingGemmaAudioFeatures.frameCount(samples: 321) == 2)
        #expect(EmbeddingGemmaAudioFeatures.frameCount(samples: 480_000) == 2999)
        #expect(EmbeddingGemmaAudioFeatures.frameCount(samples: 480_001) == 3000)
    }

    @Test func zeroWaveformUsesNaturalLogFloor() throws {
        let extractor = try EmbeddingGemmaAudioFeatures(filters: [Double](repeating: 1, count: 257 * 128))
        let features = try extractor.features([Float](repeating: 0, count: 321))
        #expect(features.count == 2 * 128)
        #expect(features.allSatisfy { abs($0 - Float(log(0.001))) < 0.000001 })
        #expect(try extractor.features([Float](repeating: 0, count: 160)).isEmpty)
    }

    @Test func fftUsesMagnitudeAndFloat32PeriodicHann() throws {
        // 첫 프레임의 중심 임펄스는 Hann의 중앙값1을 곱한다. 모든 FFT 진폭은0.25다.
        // 전력(0.0625)을 사용하거나 vDSP의2배 스케일을 놓치면 이 고정값과 다르다.
        var filters = [Double](repeating: 0, count: 257 * 128)
        filters[17 * 128 + 3] = 2
        let extractor = try EmbeddingGemmaAudioFeatures(filters: filters)
        var samples = [Float](repeating: 0, count: 161)
        samples[0] = 0.25
        let actual = try extractor.features(samples)
        #expect(abs(actual[3] - Float(log(0.501))) < 0.000001)
        #expect(abs(actual[2] - Float(log(0.001))) < 0.000001)
    }

    @Test func windowFeaturesKeepRealLeftContext() throws {
        var filters = [Double](repeating: 0, count: 257 * 128)
        filters[5 * 128] = 1
        let extractor = try EmbeddingGemmaAudioFeatures(filters: filters)
        let samples = (0..<2001).map { Float(sin(Double($0) * 0.13) * 0.25) }
        let continuous = try extractor.features(samples)
        let frame0 = 6
        let start = frame0 * 160 - 160
        let frames = 4
        let window = Array(samples[start..<(frame0 * 160 + (frames - 1) * 160 + 161)])
        let actual = try extractor.features(window, firstFrameSample: 160, frames: frames)
        let expected = Array(continuous[(frame0 * 128)..<((frame0 + frames) * 128)])
        #expect(zip(actual, expected).allSatisfy { pair in abs(pair.0 - pair.1) < 0.000001 })
    }

    @Test func featureExtractionRejectsNonfiniteSamplesAndInvalidFilterSize() throws {
        #expect(throws: (any Error).self) { try EmbeddingGemmaAudioFeatures(filters: [1]) }
        let extractor = try EmbeddingGemmaAudioFeatures(filters: [Double](repeating: 0, count: 257 * 128))
        var samples = [Float](repeating: 0, count: 161)
        samples[0] = .nan
        #expect(throws: (any Error).self) { try extractor.features(samples) }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["AIRTRANSLATE_EG2_INTEGRATION_AUDIO"] != nil))
    func transcribesOptInLocalFixtureWithInstalledModel() async throws {
        #if canImport(CoreAI) && arch(arm64)
        if #available(macOS 27.0, *) {
            let environment = ProcessInfo.processInfo.environment
            let path = try #require(environment["AIRTRANSLATE_EG2_INTEGRATION_AUDIO"])
            let modelPath = environment["AIRTRANSLATE_EG2_MODEL_DIRECTORY"]
            let modelDirectory = modelPath.map { URL(fileURLWithPath: $0, isDirectory: true) }
                ?? EmbeddingGemmaModelStore.modelDirectory
            let result = try await EmbeddingGemmaTranscriber().transcribe(
                fileURL: URL(fileURLWithPath: path), modelDirectory: modelDirectory)
            print("EG2 fixture transcript: \(result.text)")
            print("EG2 fixture audio seconds: \(result.duration), processing seconds: \(result.processingSeconds)")
            #expect(result.duration >= 0)
            #expect(result.processingSeconds >= 0)
            if let expected = environment["AIRTRANSLATE_EG2_EXPECTED_TEXT"] {
                #expect(result.text == expected)
            }
            if let words = environment["AIRTRANSLATE_EG2_EXPECTED_WORDS"] {
                let resultWords = Set(result.text.lowercased().split(separator: " ").map(String.init))
                for word in words.lowercased().split(separator: " ") { #expect(resultWords.contains(String(word))) }
            }
        }
        #endif
    }
}
