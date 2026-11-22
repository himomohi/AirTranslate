import AVFoundation

protocol MicrophoneAudioCaptureDelegate: AnyObject {
    func microphoneAudioCapture(
        _ capture: MicrophoneAudioCapture,
        didOutput sampleBuffer: CMSampleBuffer,
        generation: UInt64
    )
    func microphoneAudioCapture(
        _ capture: MicrophoneAudioCapture,
        didReceiveAudioSampleCount count: Int,
        level: Float?,
        generation: UInt64
    )
    func microphoneAudioCapture(
        _ capture: MicrophoneAudioCapture,
        didFail error: Error,
        generation: UInt64
    )
}

final class MicrophoneAudioCapture: NSObject, @unchecked Sendable {
    private static let audioLevelReportInterval = 8

    private struct ActiveSession {
        let sessionID: ObjectIdentifier
        let outputID: ObjectIdentifier
        let generation: UInt64
        var audioSampleCount: Int
    }

    private let stateLock = NSLock()
    private let operationGate = CaptureOperationGate()
    private let sessionQueue = DispatchQueue(label: "AirTranslate.MicrophoneAudioCapture.sessionQueue")
    private let sampleQueue = DispatchQueue(label: "AirTranslate.MicrophoneAudioCapture.sampleQueue")
    private weak var delegateStorage: MicrophoneAudioCaptureDelegate?
    private var operationGeneration: UInt64 = 0
    private var activeSession: ActiveSession?

    // Accessed only on sessionQueue.
    private var session: AVCaptureSession?
    private var output: AVCaptureAudioDataOutput?

    var delegate: MicrophoneAudioCaptureDelegate? {
        get { withStateLock { delegateStorage } }
        set { withStateLock { delegateStorage = newValue } }
    }

    @MainActor
    func start(
        sampleRate: Int = 16_000,
        deviceUniqueID: String? = nil,
        generation: UInt64 = 0
    ) async throws {
        let operation = beginOperation()
        guard await Self.requestMicrophoneAccess() else {
            throw CaptureError.microphoneNotGranted
        }
        try ensureOperationIsCurrent(operation)

        await operationGate.enter()
        do {
            try await configureAndStartOnSessionQueue(
                sampleRate: sampleRate,
                deviceUniqueID: deviceUniqueID,
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
        await stopOnSessionQueue()
        await operationGate.leave()
    }

    @MainActor
    static func requestMicrophoneAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    private func configureAndStartOnSessionQueue(
        sampleRate: Int,
        deviceUniqueID: String?,
        generation: UInt64,
        operation: UInt64
    ) async throws {
        try await withCheckedThrowingContinuation { continuation in
            sessionQueue.async { [self] in
                do {
                    stopCurrentSessionOnSessionQueue()
                    try ensureOperationIsCurrent(operation)

                    guard let device = MicrophoneDeviceCatalog.captureDevice(for: deviceUniqueID) else {
                        throw CaptureError.microphoneUnavailable
                    }

                    let session = AVCaptureSession()
                    let input = try AVCaptureDeviceInput(device: device)
                    let output = AVCaptureAudioDataOutput()
                    output.audioSettings = [
                        AVFormatIDKey: kAudioFormatLinearPCM,
                        AVSampleRateKey: sampleRate,
                        AVNumberOfChannelsKey: 1,
                        AVLinearPCMBitDepthKey: 16,
                        AVLinearPCMIsFloatKey: false,
                        AVLinearPCMIsBigEndianKey: false
                    ]
                    output.setSampleBufferDelegate(self, queue: sampleQueue)

                    session.beginConfiguration()
                    guard session.canAddInput(input), session.canAddOutput(output) else {
                        session.commitConfiguration()
                        output.setSampleBufferDelegate(nil, queue: nil)
                        throw CaptureError.microphoneUnavailable
                    }
                    session.addInput(input)
                    session.addOutput(output)
                    session.commitConfiguration()

                    self.session = session
                    self.output = output
                    withStateLock {
                        activeSession = ActiveSession(
                            sessionID: ObjectIdentifier(session),
                            outputID: ObjectIdentifier(output),
                            generation: generation,
                            audioSampleCount: 0
                        )
                    }
                    observeRuntimeFailures(of: session)

                    session.startRunning()
                    try ensureOperationIsCurrent(operation)
                    guard session.isRunning,
                          withStateLock({
                              activeSession?.sessionID == ObjectIdentifier(session)
                          })
                    else {
                        throw CaptureError.microphoneRuntimeFailure
                    }

                    continuation.resume()
                } catch {
                    stopCurrentSessionOnSessionQueue()
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func stopOnSessionQueue() async {
        await withCheckedContinuation { continuation in
            sessionQueue.async { [self] in
                stopCurrentSessionOnSessionQueue()
                continuation.resume()
            }
        }
    }

    private func stopCurrentSessionOnSessionQueue() {
        let session = self.session
        output?.setSampleBufferDelegate(nil, queue: nil)
        if let session {
            NotificationCenter.default.removeObserver(
                self,
                name: AVCaptureSession.runtimeErrorNotification,
                object: session
            )
            NotificationCenter.default.removeObserver(
                self,
                name: AVCaptureSession.wasInterruptedNotification,
                object: session
            )
            if session.isRunning {
                session.stopRunning()
            }
        }
        output = nil
        self.session = nil
        withStateLock {
            if let session, activeSession?.sessionID == ObjectIdentifier(session) {
                activeSession = nil
            }
        }
    }

    private func observeRuntimeFailures(of session: AVCaptureSession) {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(captureSessionRuntimeError(_:)),
            name: AVCaptureSession.runtimeErrorNotification,
            object: session
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(captureSessionWasInterrupted(_:)),
            name: AVCaptureSession.wasInterruptedNotification,
            object: session
        )
    }

    @objc
    private func captureSessionRuntimeError(_ notification: Notification) {
        let error = notification.userInfo?[AVCaptureSessionErrorKey] as? Error
            ?? CaptureError.microphoneRuntimeFailure
        handleFatalNotification(notification, error: error)
    }

    @objc
    private func captureSessionWasInterrupted(_ notification: Notification) {
        handleFatalNotification(notification, error: CaptureError.microphoneInterrupted)
    }

    private func handleFatalNotification(_ notification: Notification, error: Error) {
        guard let session = notification.object as? AVCaptureSession else { return }

        let delivery = withStateLock {
            guard let activeSession,
                  activeSession.sessionID == ObjectIdentifier(session)
            else {
                return (
                    delegate: Optional<MicrophoneAudioCaptureDelegate>.none,
                    generation: UInt64.zero
                )
            }

            operationGeneration &+= 1
            self.activeSession = nil
            return (delegate: delegateStorage, generation: activeSession.generation)
        }
        guard let delegate = delivery.delegate else { return }

        delegate.microphoneAudioCapture(
            self,
            didFail: error,
            generation: delivery.generation
        )

        let sessionID = ObjectIdentifier(session)
        sessionQueue.async { [weak self] in
            guard let self,
                  let currentSession = self.session,
                  ObjectIdentifier(currentSession) == sessionID
            else {
                return
            }
            self.stopCurrentSessionOnSessionQueue()
        }
    }

    private func beginOperation() -> UInt64 {
        withStateLock {
            operationGeneration &+= 1
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

extension MicrophoneAudioCapture: AVCaptureAudioDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard sampleBuffer.isValid else { return }

        let delivery = withStateLock {
            guard var activeSession,
                  activeSession.outputID == ObjectIdentifier(output)
            else {
                return (
                    delegate: Optional<MicrophoneAudioCaptureDelegate>.none,
                    generation: UInt64.zero,
                    count: 0
                )
            }

            activeSession.audioSampleCount += 1
            self.activeSession = activeSession
            return (
                delegate: delegateStorage,
                generation: activeSession.generation,
                count: activeSession.audioSampleCount
            )
        }
        guard let delegate = delivery.delegate else { return }

        delegate.microphoneAudioCapture(
            self,
            didOutput: sampleBuffer,
            generation: delivery.generation
        )
        if delivery.count == 1 || delivery.count % Self.audioLevelReportInterval == 0 {
            delegate.microphoneAudioCapture(
                self,
                didReceiveAudioSampleCount: delivery.count,
                level: audioLevel(from: sampleBuffer),
                generation: delivery.generation
            )
        }
    }

    private func audioLevel(from sampleBuffer: CMSampleBuffer) -> Float? {
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

        let rawList = UnsafeMutableRawPointer.allocate(
            byteCount: listSize,
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { rawList.deallocate() }

        let audioBufferList = rawList.bindMemory(to: AudioBufferList.self, capacity: 1)
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
        var squareSum: Double = 0
        var sampleCount = 0

        for buffer in buffers {
            guard let data = buffer.mData else { continue }

            if isFloat {
                let samples = data.bindMemory(to: Float.self, capacity: Int(buffer.mDataByteSize) / MemoryLayout<Float>.size)
                let count = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
                for index in 0..<count {
                    let sample = Double(samples[index])
                    squareSum += sample * sample
                }
                sampleCount += count
            } else {
                let samples = data.bindMemory(to: Int16.self, capacity: Int(buffer.mDataByteSize) / MemoryLayout<Int16>.size)
                let count = Int(buffer.mDataByteSize) / MemoryLayout<Int16>.size
                for index in 0..<count {
                    let sample = Double(samples[index]) / Double(Int16.max)
                    squareSum += sample * sample
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
