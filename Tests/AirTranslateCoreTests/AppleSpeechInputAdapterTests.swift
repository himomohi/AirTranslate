import AVFoundation
import CoreMedia
import Foundation
import Speech
import Testing
@testable import AirTranslate

@Suite
struct AppleSpeechInputAdapterTests {
    @Test func configuredMonoInputKeepsTheExistingPoolPathWithoutNativeConversion() throws {
        guard #available(macOS 27.0, *) else { return }
        for commonFormat in [AVAudioCommonFormat.pcmFormatInt16, .pcmFormatFloat32] {
            let sample = try makeSample(format: format(commonFormat, rate: 16_000), frames: 320)
            let adapter = AppleSpeechInputAdapter(analyzerFormat: format(.pcmFormatInt16, rate: 16_000))
            let pooledBuffer = try #require(AVAudioPCMBuffer(pcmFormat: format(.pcmFormatInt16, rate: 16_000), frameCapacity: 320))
            pooledBuffer.frameLength = 320
            var poolCalls = 0
            var output: [AnalyzerInput] = []
            for _ in 0..<3 {
                output += try adapter.convert(sample) { _ in poolCalls += 1; return pooledBuffer }
            }
            #expect(poolCalls == 3)
            #expect(adapter.nativeConverterCreationCountForTesting == 0)
            #expect(output.count == 3)
            #expect(output.map { $0.bufferStartTime?.seconds } == [0, 0.02, 0.04])
            #expect(output.allSatisfy { abs($0.bufferDuration.seconds - 0.02) < 0.000_000_001 })
            #expect(try adapter.finish().isEmpty)
        }
    }

    @Test func mismatchedRateResamplesAndFlushesEveryInputFrameExactlyOnce() throws {
        guard #available(macOS 27.0, *) else { return }
        let adapter = AppleSpeechInputAdapter(analyzerFormat: format(.pcmFormatInt16, rate: 16_000))
        let sample = try makeSample(format: format(.pcmFormatFloat32, rate: 48_000), frames: 960)
        var output: [AnalyzerInput] = []
        for _ in 0..<3 {
            output += try adapter.convert(sample) { _ in Issue.record("비표준 입력이 기존 풀 경로로 전달됨"); return nil }
        }
        output += try adapter.finish()
        #expect(adapter.nativeConverterCreationCountForTesting == 1)
        #expect(abs(output.reduce(0) { $0 + $1.bufferDuration.seconds } - 0.06) < 0.000_000_001)
        #expect(output.allSatisfy { $0.bufferFormat.sampleRate == 16_000 && $0.bufferFormat.channelCount == 1 })
        assertContinuous(output)
        #expect(try adapter.finish().isEmpty)
        #expect(try adapter.convert(sample) { _ in Issue.record("종료 후 입력 처리됨"); return nil }.isEmpty)
    }

    @Test func transitionsBetweenPoolAndNativeConversionKeepRelativeTimeContinuous() throws {
        guard #available(macOS 27.0, *) else { return }
        let adapter = AppleSpeechInputAdapter(analyzerFormat: format(.pcmFormatInt16, rate: 16_000))
        let normal = try makeSample(format: format(.pcmFormatInt16, rate: 16_000), frames: 320, timestamp: 9_000)
        let other = try makeSample(format: format(.pcmFormatFloat32, rate: 48_000), frames: 960, timestamp: 90_000)
        var poolCalls = 0
        let pool: (CMSampleBuffer) -> AVAudioPCMBuffer? = { sample in
            poolCalls += 1
            return try? AppleSpeechInputAdapter.copyPCMBuffer(from: sample)
        }
        var output = try adapter.convert(normal, fastPath: pool)
        output += try adapter.convert(other, fastPath: pool)
        output += try adapter.convert(normal, fastPath: pool)
        output += try adapter.finish()
        #expect(poolCalls == 2)
        #expect(output.first?.bufferStartTime == .zero)
        #expect(abs(output.reduce(0) { $0 + $1.bufferDuration.seconds } - 0.06) < 0.000_000_001)
        assertContinuous(output)
    }

    @Test func consecutiveNonstandardFormatsFlushBeforeReplacingConverter() throws {
        guard #available(macOS 27.0, *) else { return }
        let adapter = AppleSpeechInputAdapter(analyzerFormat: format(.pcmFormatInt16, rate: 16_000))
        var output: [AnalyzerInput] = []
        for rate in [48_000.0, 44_100.0, 48_000.0] {
            let sample = try makeSample(format: format(.pcmFormatFloat32, rate: rate), frames: Int(rate / 50))
            output += try adapter.convert(sample) { _ in nil }
        }
        output += try adapter.finish()
        #expect(adapter.nativeConverterCreationCountForTesting == 3)
        #expect(abs(output.reduce(0) { $0 + $1.bufferDuration.seconds } - 0.06) < 1.0 / 16_000)
        assertContinuous(output)
    }

    @Test func stereoCopyPreservesBothChannelsAndOwnsItsSamples() throws {
        guard #available(macOS 27.0, *) else { return }
        let sample = try makeSample(format: format(.pcmFormatFloat32, rate: 48_000, channels: 2), frames: 32)
        let copied = try AppleSpeechInputAdapter.copyPCMBuffer(from: sample)
        let data = try #require(copied.floatChannelData)
        #expect(copied.format.channelCount == 2)
        #expect(copied.frameLength == 32)
        #expect(data[0][0] == 0.25)
        #expect(data[1][0] == 0.5)
        let original = try #require(CMSampleBufferGetDataBuffer(sample))
        #expect(CMBlockBufferFillDataBytes(with: 0, blockBuffer: original, offsetIntoDestination: 0,
                                         dataLength: CMBlockBufferGetDataLength(original)) == noErr)
        #expect(data[0][0] == 0.25)
        #expect(data[1][0] == 0.5)
    }

    @Test func unsupportedLegacyWidthsAndChannelsCannotEnterPoolPath() throws {
        guard #available(macOS 27.0, *) else { return }
        let formats = [format(.pcmFormatFloat64, rate: 16_000), format(.pcmFormatInt32, rate: 16_000),
                       format(.pcmFormatFloat32, rate: 16_000, channels: 2), format(.pcmFormatInt16, rate: 48_000)]
        for value in formats {
            #expect(!AppleSpeechInputAdapter.supportsExistingFastPath(value.streamDescription.pointee))
            let adapter = AppleSpeechInputAdapter(analyzerFormat: format(.pcmFormatInt16, rate: 16_000))
            let sample = try makeSample(format: value, frames: Int(value.sampleRate / 50))
            let output = try adapter.convert(sample) { _ in Issue.record("잘못된 샘플 해석 경로 진입"); return nil }
                + adapter.finish()
            #expect(adapter.nativeConverterCreationCountForTesting == 1)
            #expect(abs(output.reduce(0) { $0 + $1.bufferDuration.seconds } - 0.02) < 1.0 / 16_000)
        }
    }

    @Test func invalidNativeInputFailsOnceAndCannotResumeAfterFailure() throws {
        guard #available(macOS 27.0, *) else { return }
        let adapter = AppleSpeechInputAdapter(analyzerFormat: format(.pcmFormatInt16, rate: 16_000))
        let missingData = try makeSample(format: format(.pcmFormatFloat32, rate: 48_000), frames: 960, includesData: false)
        #expect(throws: (any Error).self) { try adapter.convert(missingData) { _ in nil } }
        let valid = try makeSample(format: format(.pcmFormatFloat32, rate: 48_000), frames: 960)
        #expect(try adapter.convert(valid) { _ in nil }.isEmpty)
        #expect(try adapter.finish().isEmpty)
    }

    @Test func concurrentFinishWaitsForCurrentConversionAndRejectsLateInput() async throws {
        guard #available(macOS 27.0, *) else { return }
        let adapter = AppleSpeechInputAdapter(analyzerFormat: format(.pcmFormatInt16, rate: 16_000))
        let fixture = SpeechInputSampleHolder(try makeSample(format: format(.pcmFormatInt16, rate: 16_000), frames: 320))
        let gate = SpeechInputTestGate()
        let conversion = Task.detached {
            try adapter.convert(fixture.sample) { sample in
                gate.entered.signal()
                _ = gate.release.wait(timeout: .now() + 5)
                return try? AppleSpeechInputAdapter.copyPCMBuffer(from: sample)
            }
        }
        let entered = await gate.waitUntilEntered()
        #expect(entered)
        let finish = Task.detached { try adapter.finish() }
        gate.release.signal()
        #expect(try await conversion.value.count == 1)
        #expect(try await finish.value.isEmpty)
        #expect(try adapter.convert(fixture.sample) { _ in Issue.record("종료 후 풀 접근"); return nil }.isEmpty)
    }

    @Test func stoppedGenerationCannotEnqueueLateConvertedInputOrReportLateFailure() async throws {
        for fails in [false, true] {
            let transcriber = LiveSpeechTranscriber(authorizationRequester: { false })
            let recorder = SpeechInputFailureRecorder()
            transcriber.delegate = recorder
            let queue: SpeechAnalyzerInputQueue<AnalyzerInput> = transcriber.makeInputQueueForTesting()
            let gate = SpeechInputTestGate()
            let adapter = LateSpeechInputAdapter(gate: gate, fails: fails)
            transcriber.installInputAdapterForTesting(adapter, queue: queue)
            let fixture = SpeechInputSampleHolder(try makeSample(format: format(.pcmFormatInt16, rate: 16_000), frames: 320))
            let append = Task.detached { transcriber.append(fixture.sample) }
            let entered = await gate.waitUntilEntered()
            #expect(entered)
            await transcriber.stopAndWaitForCleanup()
            #expect(!transcriber.hasActiveResourcesForTesting)
            gate.release.signal()
            await append.value
            var count = 0
            for await _ in queue.stream { count += 1 }
            #expect(count == 0)
            #expect(recorder.count == 0)
            #expect(adapter.finishCount == 1)
        }
    }

    @Test func transcriberFlushesAdapterBeforeClosingItsInputQueue() async throws {
        let transcriber = LiveSpeechTranscriber(authorizationRequester: { false })
        let queue: SpeechAnalyzerInputQueue<AnalyzerInput> = transcriber.makeInputQueueForTesting()
        let adapter = TailSpeechInputAdapter()
        transcriber.installInputAdapterForTesting(adapter, queue: queue)
        await transcriber.stopAndWaitForCleanup()
        var count = 0
        for await _ in queue.stream { count += 1 }
        #expect(count == 1)
        #expect(adapter.finishCount == 1)
        await transcriber.stopAndWaitForCleanup()
        #expect(adapter.finishCount == 1)
    }

    private func format(_ common: AVAudioCommonFormat, rate: Double, channels: AVAudioChannelCount = 1) -> AVAudioFormat {
        AVAudioFormat(commonFormat: common, sampleRate: rate, channels: channels, interleaved: false)!
    }

    private func makeSample(format: AVAudioFormat, frames: Int, timestamp: Double = 0, includesData: Bool = true) throws -> CMSampleBuffer {
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: Int32(format.sampleRate)),
                                        presentationTimeStamp: CMTime(seconds: timestamp, preferredTimescale: 1_000_000), decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        #expect(CMSampleBufferCreate(allocator: kCFAllocatorDefault, dataBuffer: nil, dataReady: false,
            makeDataReadyCallback: nil, refcon: nil, formatDescription: format.formatDescription,
            sampleCount: frames, sampleTimingEntryCount: 1, sampleTimingArray: &timing,
            sampleSizeEntryCount: 0, sampleSizeArray: nil, sampleBufferOut: &sample) == noErr)
        let value = try #require(sample)
        if includesData {
            let pcm = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)))
            pcm.frameLength = AVAudioFrameCount(frames)
            for channel in 0..<Int(format.channelCount) {
                pcm.int16ChannelData?[channel].initialize(repeating: Int16(100 * (channel + 1)), count: frames)
                pcm.int32ChannelData?[channel].initialize(repeating: Int32(100_000 * (channel + 1)), count: frames)
                pcm.floatChannelData?[channel].initialize(repeating: Float(channel + 1) * 0.25, count: frames)
            }
            if format.commonFormat == .pcmFormatFloat64 {
                for buffer in UnsafeMutableAudioBufferListPointer(pcm.mutableAudioBufferList) {
                    buffer.mData?.bindMemory(to: Double.self, capacity: frames).initialize(repeating: 0.25, count: frames)
                }
            }
            #expect(CMSampleBufferSetDataBufferFromAudioBufferList(value, blockBufferAllocator: kCFAllocatorDefault,
                blockBufferMemoryAllocator: kCFAllocatorDefault, flags: 0, bufferList: pcm.audioBufferList) == noErr)
            #expect(CMSampleBufferSetDataReady(value) == noErr)
        }
        return value
    }

    @available(macOS 27.0, *)
    private func assertContinuous(_ output: [AnalyzerInput]) {
        var end = 0.0
        for input in output {
            #expect(abs((input.bufferStartTime?.seconds ?? -1) - end) < 1.0 / 16_000)
            end = (input.bufferStartTime?.seconds ?? -1) + input.bufferDuration.seconds
        }
    }
}

private final class SpeechInputSampleHolder: @unchecked Sendable {
    let sample: CMSampleBuffer
    init(_ sample: CMSampleBuffer) { self.sample = sample }
}

private final class SpeechInputTestGate: @unchecked Sendable {
    let entered = DispatchSemaphore(value: 0)
    let release = DispatchSemaphore(value: 0)

    func waitUntilEntered() async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async { [self] in
                continuation.resume(returning: entered.wait(timeout: .now() + 5) == .success)
            }
        }
    }
}

private final class SpeechInputFailureRecorder: LiveSpeechTranscriberDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var errors = 0
    var count: Int { lock.withLock { errors } }
    func liveSpeechTranscriber(_ transcriber: LiveSpeechTranscriber, didRecognize text: String, language: LanguageOption, confidence: Double) {}
    func liveSpeechTranscriber(_ transcriber: LiveSpeechTranscriber, didFail error: Error) { lock.withLock { errors += 1 } }
}

private final class LateSpeechInputAdapter: SpeechAnalyzerInputAdapting, @unchecked Sendable {
    private let lock = NSLock()
    private let gate: SpeechInputTestGate
    private let fails: Bool
    private var finishes = 0
    var finishCount: Int { lock.withLock { finishes } }
    init(gate: SpeechInputTestGate, fails: Bool) { self.gate = gate; self.fails = fails }
    func convert(_ sampleBuffer: CMSampleBuffer, fastPath: (CMSampleBuffer) -> AVAudioPCMBuffer?) throws -> [AnalyzerInput] {
        gate.entered.signal()
        _ = gate.release.wait(timeout: .now() + 5)
        if fails { throw CocoaError(.fileReadUnknown) }
        let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: false)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1)!
        buffer.frameLength = 1
        return [AnalyzerInput(buffer: buffer)]
    }
    func finish() throws -> [AnalyzerInput] { lock.withLock { finishes += 1 }; return [] }
}

private final class TailSpeechInputAdapter: SpeechAnalyzerInputAdapting, @unchecked Sendable {
    private let lock = NSLock()
    private var finishes = 0
    var finishCount: Int { lock.withLock { finishes } }
    func convert(_ sampleBuffer: CMSampleBuffer, fastPath: (CMSampleBuffer) -> AVAudioPCMBuffer?) throws -> [AnalyzerInput] { [] }
    func finish() throws -> [AnalyzerInput] {
        lock.withLock { finishes += 1 }
        let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: false)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1)!
        buffer.frameLength = 1
        return [AnalyzerInput(buffer: buffer)]
    }
}
