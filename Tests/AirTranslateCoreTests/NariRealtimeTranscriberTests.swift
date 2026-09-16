import AVFoundation
import Foundation
import Testing
@testable import AirTranslate

private final class NariSocketStub: NariWebSocketConnection, @unchecked Sendable {
    private let lock = NSLock()
    private var incoming: [Data] = []
    private var waiter: CheckedContinuation<Data, Error>?
    private var blockedSend: CheckedContinuation<Void, Error>?
    private var closed = false
    private var sentMessages: [String] = []
    let configureAutomatically: Bool
    let commitAutomatically: Bool
    let blockAudio: Bool
    let allowLateReceiveAfterClose: Bool

    init(configureAutomatically: Bool = true, commitAutomatically: Bool = true, blockAudio: Bool = false,
         allowLateReceiveAfterClose: Bool = false) {
        self.configureAutomatically = configureAutomatically
        self.commitAutomatically = commitAutomatically
        self.blockAudio = blockAudio
        self.allowLateReceiveAfterClose = allowLateReceiveAfterClose
    }
    func resume() {}
    var messages: [String] { lock.withLock { sentMessages } }
    var isClosed: Bool { lock.withLock { closed } }
    func send(_ text: String) async throws {
        try lock.withLock {
            guard !closed else { throw CancellationError() }
            sentMessages.append(text)
        }
        let json = try JSONSerialization.jsonObject(with: Data(text.utf8)) as! [String: Any]
        switch json["type"] as? String {
        case "session.configure" where configureAutomatically:
            let model = (json["session"] as! [String: Any])["model"] as! String
            emit(["type": "session.configured", "session": ["model": model]])
        case "input_audio_buffer.commit" where commitAutomatically:
            emit(["type": "input_audio_buffer.commit_empty", "item_id": NSNull(), "client_event_id": json["event_id"]!])
        case "input_audio_buffer.append" where blockAudio:
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                lock.withLock {
                    if closed { continuation.resume(throwing: CancellationError()) }
                    else { blockedSend = continuation }
                }
            }
        default: break
        }
    }
    func receive() async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            lock.withLock {
                if closed { continuation.resume(throwing: CancellationError()) }
                else if !incoming.isEmpty { continuation.resume(returning: incoming.removeFirst()) }
                else { waiter = continuation }
            }
        }
    }
    func emit(_ json: [String: Any]) {
        emitData(try! JSONSerialization.data(withJSONObject: json, options: [.sortedKeys]))
    }
    func emitData(_ data: Data) {
        lock.withLock {
            guard !closed || allowLateReceiveAfterClose else { return }
            if let waiter {
                self.waiter = nil
                waiter.resume(returning: data)
            } else { incoming.append(data) }
        }
    }
    func close() {
        lock.withLock {
            closed = true
            if !allowLateReceiveAfterClose {
                waiter?.resume(throwing: CancellationError())
                waiter = nil
            }
            blockedSend?.resume(throwing: CancellationError())
            blockedSend = nil
            incoming.removeAll()
        }
    }
    func commitID() throws -> String? {
        for message in messages.reversed() {
            let json = try JSONSerialization.jsonObject(with: Data(message.utf8)) as! [String: Any]
            if json["type"] as? String == "input_audio_buffer.commit" { return json["event_id"] as? String }
        }
        return nil
    }
}

private actor NariTestResults {
    var updates: [NariTranscriptUpdate] = []
    var failures: [NariTranscriptionError] = []
    func add(_ update: NariTranscriptUpdate) { updates.append(update) }
    func fail(_ error: Error) { if let error = error as? NariTranscriptionError { failures.append(error) } }
}

@Suite(.serialized)
struct NariRealtimeTranscriberTests {
    @Test func authenticatedEndpointAndConfigurationContract() throws {
        let request = try NariRealtimeTranscriber.request(key: "test-only")
        #expect(request.url?.absoluteString == "wss://api.narilabs.com/v1/realtime?intent=transcription")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-only")
        #expect(request.httpBody == nil)
        #expect(!request.url!.absoluteString.contains("test-only"))
        #expect(throws: NariTranscriptionError.missingKey) { try NariRealtimeTranscriber.request(key: "bad\r\nheader") }
        let config = try NariRealtimeTranscriber.configurationMessage(model: "qwen3-asr-fast", language: "ko")
        let json = try #require(JSONSerialization.jsonObject(with: Data(config.utf8)) as? [String: Any])
        let session = try #require(json["session"] as? [String: Any])
        #expect(json["type"] as? String == "session.configure")
        #expect(session["model"] as? String == "qwen3-asr-fast")
        #expect(session["language"] as? String == "ko")
        let vad = try #require(session["turn_detection"] as? [String: Any])
        #expect(vad["type"] as? String == "server_vad")
        #expect(vad["silence_duration_ms"] as? Int == 500)
        #expect(!config.contains("input_audio_format"))
        let auto = try NariRealtimeTranscriber.configurationMessage(model: "qwen3-asr", language: nil)
        #expect(!auto.contains("language"))
        #expect(throws: NariTranscriptionError.configuration) {
            try NariRealtimeTranscriber.configurationMessage(model: "qwen3-asr:free", language: nil)
        }
        #expect(throws: NariTranscriptionError.configuration) {
            try NariRealtimeTranscriber.configurationMessage(model: "qwen3-tts:free", language: nil)
        }
    }

    @Test func partialRevisionsReplaceAndCompletedIsAuthoritativeEvenWhenEmpty() throws {
        var ledger = NariTranscriptLedger()
        #expect(try ledger.apply(.partial("a", "안녕", 1)).first?.text == "안녕")
        #expect(try ledger.apply(.partial("a", "안녕하세요", 3)).first?.text == "안녕하세요")
        #expect(try ledger.apply(.partial("a", "stale", 2)).isEmpty)
        #expect(try ledger.apply(.committed("a", nil, nil)).isEmpty)
        let final = try ledger.apply(.completed("a", "", nil))
        #expect(final.count == 1)
        #expect(final.first?.isFinal == true)
        #expect(final.first?.text == "")
        #expect(try ledger.apply(.partial("a", "late", 4)).isEmpty)
        #expect(try ledger.apply(.completed("a", "duplicate", "ko")).isEmpty)
        #expect(ledger.isDrained)
    }

    @Test func completedWithoutPartialAndOutOfOrderFinalsFollowCommitChain() throws {
        var ledger = NariTranscriptLedger()
        #expect(try ledger.apply(.completed("b", "second", "en")).isEmpty)
        #expect(try ledger.apply(.committed("b", "a", nil)).isEmpty)
        #expect(try ledger.apply(.committed("a", nil, nil)).isEmpty)
        let updates = try ledger.apply(.completed("a", "first", "en"))
        #expect(updates.map(\.text) == ["first", "second"])
        #expect(ledger.isDrained)
    }

    @Test func laterPartialsWaitForEarlierUtteranceAndPublishOnlyLatestRevision() throws {
        var ledger = NariTranscriptLedger()
        _ = try ledger.apply(.speechStarted("a"))
        _ = try ledger.apply(.committed("a", nil, nil))
        _ = try ledger.apply(.speechStarted("b"))
        #expect(try ledger.apply(.partial("b", "early", 1)).isEmpty)
        #expect(try ledger.apply(.partial("b", "latest", 2)).isEmpty)
        let updates = try ledger.apply(.completed("a", "first", "en"))
        #expect(updates.map(\.text) == ["first", "latest"])
        #expect(updates.map(\.isFinal) == [true, false])
    }

    @Test func pendingTranscriptsHaveABoundedQueue() throws {
        var ledger = NariTranscriptLedger()
        for index in 0..<NariTranscriptLedger.maximumPendingItems {
            _ = try ledger.apply(.partial("item-\(index)", "text", 1))
        }
        #expect(throws: NariTranscriptionError.backlog) { try ledger.apply(.speechStarted("overflow")) }
    }

    @Test func configurationAcknowledgementGatesAudioAndPauseExcludesInput() async throws {
        let socket = NariSocketStub(configureAutomatically: false)
        let service = makeService(socket)
        defer { service.stop() }
        let starting = Task { try await service.start(model: .qwen3ASRFast, sourceLanguage: .korean, autoDetectLanguage: true) }
        try await waitUntil { socket.messages.count == 1 }
        let sample = try makeSample(frames: 1_600)
        service.append(sample)
        #expect(socket.messages.count == 1)
        socket.emit(["type": "session.configured", "session": ["model": "qwen3-asr-fast"]])
        try await starting.value
        service.append(sample)
        service.setPaused(true)
        service.append(sample)
        try await service.finish()
        #expect(socket.messages.count == 3) // configure, append, commit
        #expect(socket.isClosed)
        let append = try #require(JSONSerialization.jsonObject(with: Data(socket.messages[1].utf8)) as? [String: Any])
        let base64 = try #require(append["audio"] as? String)
        let pcm = try #require(Data(base64Encoded: base64))
        #expect(pcm.count == 3_200)
        #expect(Array(pcm.prefix(4)) == [0, 0, 0, 0])
        #expect(socket.messages[1].utf8.count < NariRealtimeTranscriber.maximumMessageBytes)
    }

    @Test func finishWaitsForCommitAckAllFinalsAndCallbackApplication() async throws {
        let socket = NariSocketStub(commitAutomatically: false)
        let service = makeService(socket)
        defer { service.stop() }
        let results = NariTestResults()
        service.onTranscript = { update in
            try? await Task.sleep(for: .milliseconds(30))
            await results.add(update)
        }
        try await service.start(model: .qwen3ASRFast, sourceLanguage: .english, autoDetectLanguage: false)
        service.append(try makeSample(frames: 400)) // 25 ms 잔여 버퍼도 commit 전에 보낸다.
        socket.emit(["type": "input_audio_buffer.committed", "item_id": "a", "previous_item_id": NSNull()])
        let finishing = Task { try await service.finish() }
        try await waitUntil { try socket.commitID() != nil }
        let maybeCommit = try socket.commitID()
        let commit = try #require(maybeCommit)
        socket.emit(["type": "input_audio_buffer.committed", "item_id": "b", "previous_item_id": "a", "client_event_id": commit])
        socket.emit(["type": "transcript.completed", "item_id": "b", "transcript": "second", "language": "en"])
        try await Task.sleep(for: .milliseconds(30))
        #expect(!socket.isClosed)
        socket.emit(["type": "transcript.completed", "item_id": "a", "transcript": "first", "language": "en"])
        try await finishing.value
        #expect(await results.updates.map(\.text) == ["first", "second"])
        #expect(socket.messages.count == 3)
        #expect(socket.messages[1].contains("input_audio_buffer.append"))
        #expect(socket.messages[2].contains("input_audio_buffer.commit"))
        #expect(socket.isClosed)
    }

    @Test func emptyCommitAckStillWaitsForPreviousVadFinal() async throws {
        let socket = NariSocketStub(commitAutomatically: false)
        let service = makeService(socket)
        defer { service.stop() }
        let results = NariTestResults()
        service.onTranscript = { await results.add($0) }
        try await service.start(model: .qwen3ASRFast, sourceLanguage: .english, autoDetectLanguage: false)
        socket.emit(["type": "input_audio_buffer.committed", "item_id": "a", "previous_item_id": NSNull()])
        let finishing = Task { try await service.finish() }
        try await waitUntil { try socket.commitID() != nil }
        let maybeCommit = try socket.commitID()
        let commit = try #require(maybeCommit)
        socket.emit(["type": "input_audio_buffer.commit_empty", "client_event_id": commit])
        try await Task.sleep(for: .milliseconds(30))
        #expect(!socket.isClosed)
        socket.emit(["type": "transcript.completed", "item_id": "a", "transcript": "", "language": NSNull()])
        try await finishing.value
        #expect(await results.updates.count == 1)
        #expect(await results.updates.first?.text == "")
    }

    @Test func saturationStopsWithoutUnboundedAudioOrReplay() async throws {
        let socket = NariSocketStub(blockAudio: true)
        let service = makeService(socket)
        defer { service.stop() }
        let results = NariTestResults()
        service.onError = { await results.fail($0) }
        try await service.start(model: .qwen3ASRFast, sourceLanguage: .english, autoDetectLanguage: false)
        let sample = try makeSample(frames: 1_600)
        service.append(sample)
        try await waitUntil { socket.messages.count == 2 }
        for _ in 0...NariRealtimeTranscriber.maximumPendingAudioChunks { service.append(sample) }
        try await waitUntil { socket.isClosed }
        try await waitUntil { await results.failures.count == 1 }
        #expect(await results.failures == [.backlog])
        #expect(socket.messages.count == 2)
        service.append(sample)
        #expect(socket.messages.count == 2)
    }

    @Test func providerErrorsAreSanitizedAndOnlyDeliveredOnce() async throws {
        let socket = NariSocketStub()
        let service = makeService(socket)
        defer { service.stop() }
        let results = NariTestResults()
        service.onError = { await results.fail($0) }
        try await service.start(model: .qwen3ASRFast, sourceLanguage: .english, autoDetectLanguage: false)
        socket.emit(["type": "error", "error": ["code": "INSUFFICIENT_CREDITS", "message": "secret-key and private-transcript", "requestId": "private-id"]])
        try await waitUntil { await results.failures.count == 1 }
        #expect(await results.failures == [.credits])
        #expect(!NariTranscriptionError.credits.localizedDescription.contains("secret"))
        #expect(socket.isClosed)
    }

    @Test func setupAndFinishTimeoutCloseTheirConnections() async throws {
        let noSetup = NariSocketStub(configureAutomatically: false)
        let service = makeService(noSetup, timeout: .milliseconds(50))
        await #expect(throws: NariTranscriptionError.setupTimeout) {
            try await service.start(model: .qwen3ASRFast, sourceLanguage: .english, autoDetectLanguage: false)
        }
        #expect(noSetup.isClosed)
        service.stop()
        let noFinal = NariSocketStub(commitAutomatically: false)
        let other = makeService(noFinal, timeout: .milliseconds(50))
        try await other.start(model: .qwen3ASRFast, sourceLanguage: .english, autoDetectLanguage: false)
        await #expect(throws: NariTranscriptionError.finishTimeout) { try await other.finish() }
        #expect(noFinal.isClosed)
        other.stop()
    }

    @Test func cancellationClosesPendingSetupImmediately() async throws {
        let socket = NariSocketStub(configureAutomatically: false)
        let service = makeService(socket)
        let task = Task { try await service.start(model: .qwen3ASRFast, sourceLanguage: .english, autoDetectLanguage: false) }
        try await waitUntil { socket.messages.count == 1 }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(socket.isClosed)
        #expect(socket.messages.count == 1)
    }

    @Test func resumedConnectionStartsFreshWithoutReplayingPausedAudio() async throws {
        let first = NariSocketStub()
        let second = NariSocketStub()
        let sockets = NariSocketPool([first, second])
        let service = NariRealtimeTranscriber(keyProvider: { "test-only" }, connectionFactory: { _ in sockets.next() })
        let results = NariTestResults()
        service.onTranscript = { await results.add($0) }
        defer { service.stop() }
        try await service.start(model: .qwen3ASRFast, sourceLanguage: .english, autoDetectLanguage: false)
        first.emit(["type": "input_audio_buffer.committed", "item_id": "a", "previous_item_id": NSNull()])
        first.emit(["type": "transcript.completed", "item_id": "a", "transcript": "first", "language": "en"])
        service.setPaused(true)
        service.append(try makeSample(frames: 1_600))
        try await service.finish()
        try await service.start(model: .qwen3ASRFast, sourceLanguage: .english, autoDetectLanguage: false)
        second.emit(["type": "input_audio_buffer.committed", "item_id": "a", "previous_item_id": NSNull()])
        second.emit(["type": "transcript.completed", "item_id": "a", "transcript": "second", "language": "en"])
        try await service.finish()
        let updates = await results.updates
        #expect(updates.map(\.text) == ["first", "second"])
        #expect(updates[0].itemID != updates[1].itemID)
        #expect(first.messages.count == 2)
        #expect(second.messages.count == 2)
    }

    @Test func oldGenerationCannotPublishEvenWhenReceiveReturnsAfterClose() async throws {
        let old = NariSocketStub(allowLateReceiveAfterClose: true)
        let current = NariSocketStub()
        let sockets = NariSocketPool([old, current])
        let service = NariRealtimeTranscriber(keyProvider: { "test-only" }, connectionFactory: { _ in sockets.next() })
        defer { service.stop() }
        let results = NariTestResults()
        service.onTranscript = { await results.add($0) }
        try await service.start(model: .qwen3ASRFast, sourceLanguage: .english, autoDetectLanguage: false)
        service.stop()
        try await service.start(model: .qwen3ASRFast, sourceLanguage: .english, autoDetectLanguage: false)
        old.emit(["type": "transcript.partial", "item_id": "stale", "transcript": "must not appear", "revision": 1])
        current.emit(["type": "input_audio_buffer.committed", "item_id": "fresh", "previous_item_id": NSNull()])
        current.emit(["type": "transcript.completed", "item_id": "fresh", "transcript": "current", "language": "en"])
        try await service.finish()
        #expect(await results.updates.map(\.text) == ["current"])
    }

    @Test func cancellingFinishClosesWithoutPretendingLastAudioWasFinalized() async throws {
        let socket = NariSocketStub(commitAutomatically: false)
        let service = makeService(socket)
        defer { service.stop() }
        let results = NariTestResults()
        service.onTranscript = { await results.add($0) }
        try await service.start(model: .qwen3ASRFast, sourceLanguage: .english, autoDetectLanguage: false)
        service.append(try makeSample(frames: 400))
        let finishing = Task { try await service.finish() }
        try await waitUntil { try socket.commitID() != nil }
        finishing.cancel()
        await #expect(throws: CancellationError.self) { try await finishing.value }
        #expect(socket.isClosed)
        #expect(await results.updates.isEmpty)
    }

    @Test func pcmFloatConversionClipsAndRejectsWrongRate() throws {
        let sample = try makeSample(frames: 4, floatValues: [-2, -0.5, .nan, 2])
        let data = try #require(AzureMAITranscriber.pcm16(sample))
        let values = data.withUnsafeBytes { raw in
            stride(from: 0, to: data.count, by: 2).map { raw.loadUnaligned(fromByteOffset: $0, as: Int16.self).littleEndian }
        }
        #expect(values == [-32_767, -16_383, 0, 32_767])
        #expect(AzureMAITranscriber.pcm16(try makeSample(frames: 1_600, sampleRate: 24_000)) == nil)
    }

    @Test func invalidWireEventsAreRejected() throws {
        #expect(throws: NariTranscriptionError.invalidResponse) { try NariServerEvent.parse(Data("not JSON".utf8)) }
        #expect(throws: NariTranscriptionError.invalidResponse) {
            try NariServerEvent.parse(Data(#"{"type":"transcript.partial","item_id":"a","transcript":"text","revision":0}"#.utf8))
        }
        #expect(throws: NariTranscriptionError.invalidResponse) {
            try NariServerEvent.parse(Data(repeating: 32, count: NariRealtimeTranscriber.maximumMessageBytes + 1))
        }
    }

    private func makeService(_ socket: NariSocketStub, timeout: Duration = .seconds(2)) -> NariRealtimeTranscriber {
        NariRealtimeTranscriber(keyProvider: { "test-only" }, connectionFactory: { _ in socket }, setupTimeout: timeout, finishTimeout: timeout)
    }

    private func waitUntil(_ predicate: () async throws -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while try await !predicate() {
            if ContinuousClock.now > deadline { throw NariTranscriptionError.finishTimeout }
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    private func makeSample(frames: Int, sampleRate: Double = 16_000, floatValues: [Float]? = nil) throws -> CMSampleBuffer {
        let bytesPerFrame: UInt32 = floatValues == nil ? 2 : 4
        var description = AudioStreamBasicDescription(mSampleRate: sampleRate, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: (floatValues == nil ? kAudioFormatFlagIsSignedInteger : kAudioFormatFlagIsFloat) | kAudioFormatFlagIsPacked,
            mBytesPerPacket: bytesPerFrame, mFramesPerPacket: 1, mBytesPerFrame: bytesPerFrame,
            mChannelsPerFrame: 1, mBitsPerChannel: bytesPerFrame * 8, mReserved: 0)
        var format: CMAudioFormatDescription?
        #expect(CMAudioFormatDescriptionCreate(allocator: kCFAllocatorDefault, asbd: &description, layoutSize: 0, layout: nil,
            magicCookieSize: 0, magicCookie: nil, extensions: nil, formatDescriptionOut: &format) == noErr)
        let byteCount = frames * Int(bytesPerFrame)
        var block: CMBlockBuffer?
        #expect(CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: byteCount,
            blockAllocator: kCFAllocatorDefault, customBlockSource: nil, offsetToData: 0, dataLength: byteCount,
            flags: kCMBlockBufferAssureMemoryNowFlag, blockBufferOut: &block) == noErr)
        let audioBlock = try #require(block)
        #expect(CMBlockBufferFillDataBytes(with: 0, blockBuffer: audioBlock, offsetIntoDestination: 0, dataLength: byteCount) == noErr)
        if let floatValues {
            floatValues.withUnsafeBytes { raw in
                #expect(CMBlockBufferReplaceDataBytes(with: raw.baseAddress!, blockBuffer: audioBlock,
                    offsetIntoDestination: 0, dataLength: byteCount) == noErr)
            }
        }
        var sample: CMSampleBuffer?
        #expect(CMAudioSampleBufferCreateReadyWithPacketDescriptions(allocator: kCFAllocatorDefault, dataBuffer: audioBlock,
            formatDescription: try #require(format), sampleCount: frames, presentationTimeStamp: .zero,
            packetDescriptions: nil, sampleBufferOut: &sample) == noErr)
        return try #require(sample)
    }
}

private final class NariSocketPool: @unchecked Sendable {
    let lock = NSLock()
    var sockets: [NariSocketStub]
    init(_ sockets: [NariSocketStub]) { self.sockets = sockets }
    func next() -> NariSocketStub { lock.withLock { sockets.removeFirst() } }
}
