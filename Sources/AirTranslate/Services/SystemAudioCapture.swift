import Accelerate
import AVFoundation
import CoreGraphics
import ScreenCaptureKit

protocol SystemAudioCaptureDelegate: AnyObject {
    func systemAudioCapture(
        _ capture: SystemAudioCapture,
        didOutput sampleBuffer: CMSampleBuffer,
        generation: UInt64
    )
    func systemAudioCapture(
        _ capture: SystemAudioCapture,
        didReceiveAudioSampleCount count: Int,
        level: Float?,
        generation: UInt64
    )
    func systemAudioCapture(
        _ capture: SystemAudioCapture,
        didFail error: Error,
        generation: UInt64
    )
    func systemAudioCaptureDidStopByUser(
        _ capture: SystemAudioCapture,
        generation: UInt64
    )
}

struct ScreenRecordingRequestAttemptStore: @unchecked Sendable {
    private static let userDefaultsKey = "AirTranslate.screenRecordingAccessRequestAttempted"

    let hasRequestedAccess: () -> Bool
    let markRequestedAccess: () -> Void

    static func userDefaults(_ defaults: UserDefaults = .standard) -> Self {
        Self(
            hasRequestedAccess: { defaults.bool(forKey: userDefaultsKey) },
            markRequestedAccess: { defaults.set(true, forKey: userDefaultsKey) }
        )
    }
}

/// Persists the system screen-recording request attempt across app launches.
/// The TCC preflight still wins so an approval made in System Settings is
/// usable without another request from the app.
final class ScreenRecordingAccessPolicy: @unchecked Sendable {
    typealias AccessCheck = () -> Bool

    enum Outcome: Equatable {
        case allowed, requested, settingsRequired
    }

    private let preflightAccess: AccessCheck
    private let requestAccess: AccessCheck
    private let requestAttemptStore: ScreenRecordingRequestAttemptStore
    private let stateLock = NSLock()

    init(
        preflightAccess: @escaping AccessCheck = CGPreflightScreenCaptureAccess,
        requestAccess: @escaping AccessCheck = CGRequestScreenCaptureAccess,
        requestAttemptStore: ScreenRecordingRequestAttemptStore = .userDefaults()
    ) {
        self.preflightAccess = preflightAccess
        self.requestAccess = requestAccess
        self.requestAttemptStore = requestAttemptStore
    }

    func accessOrRequestOnce() -> Outcome {
        if preflightAccess() {
            return withStateLock {
                if !requestAttemptStore.hasRequestedAccess() {
                    requestAttemptStore.markRequestedAccess()
                }
                return .allowed
            }
        }

        return withStateLock {
            guard !requestAttemptStore.hasRequestedAccess() else { return .settingsRequired }
            requestAttemptStore.markRequestedAccess()
            return requestAccess() ? .allowed : .requested
        }
    }

    private func withStateLock<Result>(_ body: () -> Result) -> Result {
        stateLock.lock()
        defer { stateLock.unlock() }
        return body()
    }
}

actor CaptureOperationGate {
    private var isLocked = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func enter() async {
        if !isLocked {
            isLocked = true
            return
        }

        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func leave() {
        guard !waiters.isEmpty else {
            isLocked = false
            return
        }

        waiters.removeFirst().resume()
    }
}

final class SystemAudioCapture: NSObject, @unchecked Sendable {
    private static let audioLevelReportInterval = 8
    private static let sharedScreenRecordingAccessPolicy = ScreenRecordingAccessPolicy()

    static func isUserStoppedError(_ error: Error) -> Bool {
        if error is SystemAudioCaptureLifecycleOutcome {
            return true
        }
        let nsError = error as NSError
        return nsError.domain == SCStreamErrorDomain
            && nsError.code == SCStreamError.Code.userStopped.rawValue
    }

    static func isFatalStopError(_ error: Error) -> Bool {
        !isUserStoppedError(error)
    }

    private struct ActiveStream {
        let stream: SCStream
        let generation: UInt64
        var audioSampleCount: Int
    }

    private let stateLock = NSLock()
    private let operationGate = CaptureOperationGate()
    private let sampleQueue = DispatchQueue(label: "AirTranslate.SystemAudioCapture.sampleQueue")
    private let screenSampleQueue = DispatchQueue(
        label: "AirTranslate.SystemAudioCapture.screenSampleQueue",
        qos: .utility
    )
    private weak var delegateStorage: SystemAudioCaptureDelegate?
    private let screenRecordingAccessPolicy: ScreenRecordingAccessPolicy
    private var operationGeneration: UInt64 = 0
    private var userStoppedGeneration: UInt64?
    private var activeStream: ActiveStream?

    init(screenRecordingAccessPolicy: ScreenRecordingAccessPolicy? = nil) {
        self.screenRecordingAccessPolicy = screenRecordingAccessPolicy
            ?? Self.sharedScreenRecordingAccessPolicy
        super.init()
    }

    var delegate: SystemAudioCaptureDelegate? {
        get { withStateLock { delegateStorage } }
        set { withStateLock { delegateStorage = newValue } }
    }

    @MainActor
    func requestScreenRecordingAccess() throws {
        guard screenRecordingAccessOutcome() == .allowed else {
            throw CaptureError.screenRecordingNotGranted
        }
    }

    @MainActor
    func screenRecordingAccessOutcome() -> ScreenRecordingAccessPolicy.Outcome {
        screenRecordingAccessPolicy.accessOrRequestOnce()
    }

    @MainActor
    func start(sampleRate: Int = 16_000, generation: UInt64 = 0) async throws {
        let operation = beginOperation()
        await operationGate.enter()

        do {
            try await performStart(
                sampleRate: sampleRate,
                generation: generation,
                operation: operation
            )
            await operationGate.leave()
        } catch {
            await operationGate.leave()
            throw error
        }
    }

    func stop() async {
        invalidateOperations()
        await operationGate.enter()
        await performStop()
        await operationGate.leave()
    }

    private func performStart(
        sampleRate: Int,
        generation: UInt64,
        operation: UInt64
    ) async throws {
        await performStop()
        try ensureOperationIsCurrent(operation)

        let content = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: true
        )
        try ensureOperationIsCurrent(operation)

        guard let display = content.displays.first else {
            throw CaptureError.noDisplay
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.width = 2
        configuration.height = 2
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        configuration.capturesAudio = true
        configuration.excludesCurrentProcessAudio = true
        configuration.sampleRate = sampleRate
        configuration.channelCount = 1

        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: screenSampleQueue)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: sampleQueue)

        let installed = withStateLock {
            guard operationGeneration == operation else { return false }
            activeStream = ActiveStream(
                stream: stream,
                generation: generation,
                audioSampleCount: 0
            )
            return true
        }
        guard installed else {
            removeOutputs(from: stream)
            throw CancellationError()
        }

        do {
            try await stream.startCapture()
            let completion = withStateLock {
                let stoppedByUser = userStoppedGeneration == generation
                if stoppedByUser {
                    userStoppedGeneration = nil
                }
                return (
                    remainsCurrent: operationGeneration == operation && activeStream?.stream === stream,
                    stoppedByUser: stoppedByUser
                )
            }
            if completion.stoppedByUser {
                throw SystemAudioCaptureLifecycleOutcome.userStopped
            }
            guard completion.remainsCurrent else {
                await clearAndStop(stream)
                throw CancellationError()
            }
        } catch {
            let stoppedByUser = withStateLock {
                guard userStoppedGeneration == generation else { return false }
                userStoppedGeneration = nil
                return true
            }
            await clearAndStop(stream)
            if stoppedByUser || Self.isUserStoppedError(error) {
                throw SystemAudioCaptureLifecycleOutcome.userStopped
            }
            throw error
        }
    }

    private func performStop() async {
        let stream = withStateLock {
            let stream = activeStream?.stream
            activeStream = nil
            return stream
        }
        guard let stream else { return }

        removeOutputs(from: stream)
        try? await stream.stopCapture()
    }

    private func clearAndStop(_ stream: SCStream) async {
        withStateLock {
            if activeStream?.stream === stream {
                activeStream = nil
            }
        }
        removeOutputs(from: stream)
        try? await stream.stopCapture()
    }

    private func removeOutputs(from stream: SCStream) {
        try? stream.removeStreamOutput(self, type: .screen)
        try? stream.removeStreamOutput(self, type: .audio)
    }

    private func beginOperation() -> UInt64 {
        withStateLock {
            operationGeneration &+= 1
            userStoppedGeneration = nil
            return operationGeneration
        }
    }

    private func invalidateOperations() {
        withStateLock {
            operationGeneration &+= 1
        }
    }

    private func ensureOperationIsCurrent(_ operation: UInt64) throws {
        guard withStateLock({ operationGeneration == operation }) else {
            throw CancellationError()
        }
    }

    private func withStateLock<Result>(_ body: () -> Result) -> Result {
        stateLock.lock()
        defer { stateLock.unlock() }
        return body()
    }
}

extension SystemAudioCapture: SCStreamOutput {
    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        guard type == .audio, sampleBuffer.isValid else { return }

        let delivery = withStateLock {
            guard var activeStream, activeStream.stream === stream else {
                return (
                    delegate: Optional<SystemAudioCaptureDelegate>.none,
                    generation: UInt64.zero,
                    count: 0
                )
            }

            activeStream.audioSampleCount += 1
            self.activeStream = activeStream
            return (
                delegate: delegateStorage,
                generation: activeStream.generation,
                count: activeStream.audioSampleCount
            )
        }
        guard let delegate = delivery.delegate else { return }

        delegate.systemAudioCapture(
            self,
            didOutput: sampleBuffer,
            generation: delivery.generation
        )
        if delivery.count == 1 || delivery.count % Self.audioLevelReportInterval == 0 {
            delegate.systemAudioCapture(
                self,
                didReceiveAudioSampleCount: delivery.count,
                level: audioLevel(from: sampleBuffer),
                generation: delivery.generation
            )
        }
    }

    private func audioLevel(from sampleBuffer: CMSampleBuffer) -> Float? {
        AudioLevelCalculator.decibels(from: sampleBuffer)
    }
}

enum AudioLevelCalculator {
    private static let int16ConversionChunkSize = 4_096

    static func decibels(from sampleBuffer: CMSampleBuffer) -> Float? {
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
              let streamDescription = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription)
        else {
            return nil
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

        guard listSize > 0 else { return nil }

        return withUnsafeTemporaryAllocation(
            byteCount: listSize,
            alignment: MemoryLayout<AudioBufferList>.alignment
        ) { rawList -> Float? in
            guard let baseAddress = rawList.baseAddress else { return nil }

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

            guard status == noErr else { return nil }

            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            let isFloat = streamDescription.pointee.mFormatFlags & kAudioFormatFlagIsFloat != 0

            if buffers.count == 1, let buffer = buffers.first, let data = buffer.mData {
                if isFloat {
                    let count = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
                    guard count > 0 else { return nil }
                    let samples = data.bindMemory(to: Float.self, capacity: count)
                    var rms: Float = 0
                    vDSP_rmsqv(samples, 1, &rms, vDSP_Length(count))
                    return Float(20 * log10(max(Double(rms), 0.000_001)))
                }
            }

            var squareSum: Double = 0
            var sampleCount = 0

            for buffer in buffers {
                guard let data = buffer.mData else { continue }

                if isFloat {
                    let count = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
                    guard count > 0 else { continue }
                    let samples = data.bindMemory(to: Float.self, capacity: count)
                    var bufferSquareSum: Float = 0
                    vDSP_svesq(samples, 1, &bufferSquareSum, vDSP_Length(count))
                    squareSum += Double(bufferSquareSum)
                    sampleCount += count
                } else {
                    let count = Int(buffer.mDataByteSize) / MemoryLayout<Int16>.size
                    guard count > 0 else { continue }
                    let samples = data.bindMemory(to: Int16.self, capacity: count)
                    let chunkCapacity = min(count, int16ConversionChunkSize)
                    let invScale = 1.0 / Double(Int16.max)
                    let invScaleSquared = invScale * invScale
                    withUnsafeTemporaryAllocation(of: Float.self, capacity: chunkCapacity) { scratch in
                        guard let floatPtr = scratch.baseAddress else { return }
                        var offset = 0
                        while offset < count {
                            let chunk = min(chunkCapacity, count - offset)
                            vDSP_vflt16(samples.advanced(by: offset), 1, floatPtr, 1, vDSP_Length(chunk))
                            var chunkSquareSum: Float = 0
                            vDSP_svesq(floatPtr, 1, &chunkSquareSum, vDSP_Length(chunk))
                            squareSum += Double(chunkSquareSum) * invScaleSquared
                            offset += chunk
                        }
                    }
                    sampleCount += count
                }
            }

            guard sampleCount > 0 else { return nil }
            let rms = sqrt(squareSum / Double(sampleCount))
            let decibels = 20 * log10(max(rms, 0.000_001))
            return Float(decibels)
        }
    }
}

extension SystemAudioCapture: SCStreamDelegate {
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        let didStopByUser = Self.isUserStoppedError(error)
        let delivery = withStateLock {
            guard let activeStream, activeStream.stream === stream else {
                return (
                    delegate: Optional<SystemAudioCaptureDelegate>.none,
                    generation: UInt64.zero
                )
            }

            operationGeneration &+= 1
            if didStopByUser {
                userStoppedGeneration = activeStream.generation
            }
            self.activeStream = nil
            return (delegate: delegateStorage, generation: activeStream.generation)
        }

        removeOutputs(from: stream)
        if didStopByUser {
            delivery.delegate?.systemAudioCaptureDidStopByUser(
                self,
                generation: delivery.generation
            )
        } else {
            delivery.delegate?.systemAudioCapture(
                self,
                didFail: error,
                generation: delivery.generation
            )
        }
    }
}

enum SystemAudioCaptureLifecycleOutcome: Error {
    case userStopped
}

enum CaptureError: LocalizedError {
    case screenRecordingNotGranted
    case microphoneNotGranted
    case microphoneUnavailable
    case microphoneInterrupted
    case microphoneRuntimeFailure
    case noDisplay

    var errorDescription: String? {
        switch self {
        case .screenRecordingNotGranted:
            AppText.screenRecordingNotGranted
        case .microphoneNotGranted:
            AppText.microphoneNotGranted
        case .microphoneUnavailable:
            AppText.microphoneUnavailable
        case .microphoneInterrupted:
            AppText.localized(
                english: "Microphone capture was interrupted.",
                korean: "마이크 캡처가 중단되었습니다.",
                japanese: "マイクのキャプチャが中断されました。",
                chineseSimplified: "麦克风捕获已中断。"
            )
        case .microphoneRuntimeFailure:
            AppText.localized(
                english: "Microphone capture stopped unexpectedly.",
                korean: "마이크 캡처가 예기치 않게 중지되었습니다.",
                japanese: "マイクのキャプチャが予期せず停止しました。",
                chineseSimplified: "麦克风捕获意外停止。"
            )
        case .noDisplay:
            AppText.noActiveDisplay
        }
    }
}
