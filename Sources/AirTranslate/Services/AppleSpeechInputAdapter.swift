import AVFoundation
import CoreMedia
import Foundation
import Speech

protocol SpeechAnalyzerInputAdapting: AnyObject, Sendable {
    func convert(
        _ sampleBuffer: CMSampleBuffer,
        fastPath: (CMSampleBuffer) -> AVAudioPCMBuffer?
    ) throws -> [AnalyzerInput]
    func finish() throws -> [AnalyzerInput]
}

private enum AppleSpeechInputAdapterError: Error {
    case invalidFormat
    case invalidBuffer
    case copyFailed(OSStatus)
}

/// 정상 캡처의 기존 PCM 풀은 유지하고, 포맷이 달라진 입력만 시스템 변환기로 보정한다.
@available(macOS 27.0, *)
final class AppleSpeechInputAdapter: SpeechAnalyzerInputAdapting, @unchecked Sendable {
    private let lock = NSLock()
    private let analyzerFormat: AVAudioFormat
    private var converter: AnalyzerInputConverter?
    private var converterInputFormat: AVAudioFormat?
    private var elapsedInputTime = CMTime.zero
    private var isFinished = false
#if DEBUG
    private var nativeConverterCreationCount = 0
    var nativeConverterCreationCountForTesting: Int { lock.withLock { nativeConverterCreationCount } }
#endif

    init(analyzerFormat: AVAudioFormat) {
        self.analyzerFormat = analyzerFormat
    }

    func convert(
        _ sampleBuffer: CMSampleBuffer,
        fastPath: (CMSampleBuffer) -> AVAudioPCMBuffer?
    ) throws -> [AnalyzerInput] {
        try lock.withLock {
            guard !isFinished else { return [] }
            let frames = CMSampleBufferGetNumSamples(sampleBuffer)
            guard frames > 0 else { return [] }
            do {
                guard let description = CMSampleBufferGetFormatDescription(sampleBuffer),
                      let stream = CMAudioFormatDescriptionGetStreamBasicDescription(description),
                      stream.pointee.mFormatID == kAudioFormatLinearPCM,
                      stream.pointee.mSampleRate.isFinite, stream.pointee.mSampleRate > 0 else {
                    throw AppleSpeechInputAdapterError.invalidFormat
                }

                if Self.supportsExistingFastPath(stream.pointee) {
                    let tail = try flushNativeConverter()
                    guard let buffer = fastPath(sampleBuffer) else { return tail }
                    let input = AnalyzerInput(buffer: buffer, bufferStartTime: elapsedInputTime)
                    elapsedInputTime = CMTimeAdd(
                        elapsedInputTime, Self.duration(frames: Int(buffer.frameLength), sampleRate: buffer.format.sampleRate)
                    )
                    return tail + [input]
                }

                let buffer = try Self.copyPCMBuffer(from: sampleBuffer)
                var output: [AnalyzerInput] = []
                if converterInputFormat != buffer.format {
                    output = try flushNativeConverter()
                    converter = AnalyzerInputConverter(analyzerFormat: analyzerFormat)
                    converterInputFormat = buffer.format
#if DEBUG
                    nativeConverterCreationCount += 1
#endif
                }
                // 캡처의 절대 PTS 대신 기존 입력과 같은 세션 상대 시간을 사용한다. 일시정지 구간은 제외한다.
                let sampleTime = AVAudioFramePosition((elapsedInputTime.seconds * buffer.format.sampleRate).rounded())
                let audioTime = AVAudioTime(sampleTime: sampleTime, atRate: buffer.format.sampleRate)
                output += try converter!.convert(buffer, at: audioTime)
                elapsedInputTime = CMTimeAdd(
                    elapsedInputTime, Self.duration(frames: frames, sampleRate: buffer.format.sampleRate)
                )
                return output
            } catch {
                isFinished = true
                converter = nil
                converterInputFormat = nil
                throw error
            }
        }
    }

    func finish() throws -> [AnalyzerInput] {
        try lock.withLock {
            guard !isFinished else { return [] }
            isFinished = true
            return try flushNativeConverter()
        }
    }

    private func flushNativeConverter() throws -> [AnalyzerInput] {
        guard let converter else { return [] }
        defer {
            self.converter = nil
            converterInputFormat = nil
        }
        return try converter.flush()
    }

    static func supportsExistingFastPath(_ stream: AudioStreamBasicDescription) -> Bool {
        guard stream.mFormatID == kAudioFormatLinearPCM, stream.mSampleRate == 16_000,
              stream.mChannelsPerFrame == 1, stream.mFramesPerPacket == 1,
              stream.mFormatFlags & kAudioFormatFlagIsBigEndian == 0,
              stream.mFormatFlags & kAudioFormatFlagIsPacked != 0 else { return false }
        if stream.mFormatFlags & kAudioFormatFlagIsFloat != 0 {
            return stream.mBitsPerChannel == 32 && stream.mBytesPerFrame == 4 && stream.mBytesPerPacket == 4
        }
        return stream.mFormatFlags & kAudioFormatFlagIsSignedInteger != 0
            && stream.mBitsPerChannel == 16 && stream.mBytesPerFrame == 2 && stream.mBytesPerPacket == 2
    }

    /// 비표준 입력만 별도 버퍼에 복사해 채널·샘플 형식과 원본 수명을 함께 보존한다.
    static func copyPCMBuffer(from sampleBuffer: CMSampleBuffer) throws -> AVAudioPCMBuffer {
        let frames = CMSampleBufferGetNumSamples(sampleBuffer)
        guard frames > 0, frames <= Int(Int32.max),
              let description = CMSampleBufferGetFormatDescription(sampleBuffer),
              CMFormatDescriptionGetMediaSubType(description) == kAudioFormatLinearPCM,
              let format = AVAudioFormat(formatDescription: description),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)) else {
            throw AppleSpeechInputAdapterError.invalidBuffer
        }
        buffer.frameLength = AVAudioFrameCount(frames)
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer, at: 0, frameCount: Int32(frames), into: buffer.mutableAudioBufferList
        )
        guard status == noErr else { throw AppleSpeechInputAdapterError.copyFailed(status) }
        return buffer
    }

    private static func duration(frames: Int, sampleRate: Double) -> CMTime {
        if sampleRate.rounded() == sampleRate, sampleRate <= Double(Int32.max) {
            return CMTime(value: Int64(frames), timescale: Int32(sampleRate))
        }
        return CMTime(seconds: Double(frames) / sampleRate, preferredTimescale: 1_000_000_000)
    }
}
