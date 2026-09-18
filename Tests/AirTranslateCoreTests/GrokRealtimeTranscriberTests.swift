import AVFoundation
import Foundation
import Security
import Testing
@testable import AirTranslate

private final class GrokSocketStub: GrokWebSocketConnection, @unchecked Sendable {
    private let lock = NSLock()
    private var incoming: [Data] = []
    private var waiter: CheckedContinuation<Data, Error>?
    private var blockedSend: CheckedContinuation<Void, Error>?
    private var closed = false
    private var resumed = false
    private var sentMessages: [GrokClientMessage] = []
    let readyAutomatically: Bool
    let finishAutomatically: Bool
    let blockAudio: Bool
    let allowLateReceiveAfterClose: Bool

    init(readyAutomatically: Bool = true, finishAutomatically: Bool = true, blockAudio: Bool = false,
         allowLateReceiveAfterClose: Bool = false) {
        self.readyAutomatically = readyAutomatically
        self.finishAutomatically = finishAutomatically
        self.blockAudio = blockAudio
        self.allowLateReceiveAfterClose = allowLateReceiveAfterClose
    }
    func resume() {
        lock.withLock { resumed = true }
        if readyAutomatically { emit(["type": "transcript.created"]) }
    }
    var messages: [GrokClientMessage] { lock.withLock { sentMessages } }
    var isClosed: Bool { lock.withLock { closed } }
    var isResumed: Bool { lock.withLock { resumed } }
    func send(_ message: GrokClientMessage) async throws {
        try lock.withLock {
            guard !closed else { throw CancellationError() }
            sentMessages.append(message)
        }
        switch message {
        case .finish where finishAutomatically:
            emit(["type": "transcript.done", "text": "", "duration": 0])
        case .audio where blockAudio:
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
        let data = try! JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
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
}

private actor GrokTestResults {
    var updates: [GrokTranscriptUpdate] = []
    var failures: [GrokTranscriptionError] = []
    func add(_ update: GrokTranscriptUpdate) { updates.append(update) }
    func fail(_ error: Error) { if let error = error as? GrokTranscriptionError { failures.append(error) } }
}

@Suite(.serialized)
struct GrokRealtimeTranscriberTests {
    @Test func requestSelectsTranscribe2AndSendsCredentialsOnlyInHeader() throws {
        let request = try GrokRealtimeTranscriber.request(key: "test-only", language: "ko")
        let url = try #require(request.url)
        #expect(url.scheme == "wss" && url.host == "api.x.ai" && url.path == "/v1/stt")
        let query = Dictionary(uniqueKeysWithValues: URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!.map { ($0.name, $0.value!) })
        #expect(query == ["model": "grok-voice-transcribe-2.0", "sample_rate": "16000", "encoding": "pcm", "interim_results": "true", "endpointing": "400", "language": "ko"])
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-only")
        #expect(!url.absoluteString.contains("test-only"))
        #expect(request.httpBody == nil)
        #expect(!(try GrokRealtimeTranscriber.request(key: "test-only").url!.absoluteString.contains("language=")))
        #expect(throws: GrokTranscriptionError.configuration) { try GrokRealtimeTranscriber.request(key: "test-only", model: .off) }
        #expect(throws: GrokTranscriptionError.configuration) { try GrokRealtimeTranscriber.request(key: "test-only", language: "zh") }
        #expect(throws: GrokTranscriptionError.missingKey) { try GrokRealtimeTranscriber.request(key: "bad\r\nheader") }
        #expect(GrokTranscriptionModel.languageCode(for: .korean) == "ko")
        #expect(GrokTranscriptionModel(rawValue: "grok-voice-tts") == nil)
    }

    @Test func keyPresenceNeverReadsValueOrPromptsAndStoreIsDistinct() throws {
        let query = GrokAPIKeyStore.presenceQuery()
        #expect(query[kSecReturnData as String] == nil)
        #expect(query[kSecReturnAttributes as String] as? Bool == true)
        #expect(query[kSecUseAuthenticationUI as String] as? String == kSecUseAuthenticationUISkip as String)
        #expect(query[kSecAttrService as String] as? String == "AirTranslate.Grok")
        #expect(query[kSecAttrAccount as String] as? String == "XAI_API_KEY")
        #expect(try GrokAPIKeyStore.normalizedAPIKey("  test-only\n") == "test-only")
        #expect(throws: GrokAPIKeyStoreError.self) { try GrokAPIKeyStore.normalizedAPIKey("bad\nkey") }
    }

    @Test func chunksLockButStitchedUtteranceReplacesWithoutDuplication() throws {
        var ledger = GrokTranscriptLedger()
        #expect(try ledger.apply(.partial("I scream", false, false, 0, 1, nil)).first?.text == "I scream")
        #expect(try ledger.apply(.partial("Ice cream", true, false, 0, 3, nil)).first?.text == "Ice cream")
        #expect(try ledger.apply(.partial("stale", false, false, 0, 3, nil)).isEmpty)
        #expect(try ledger.apply(.partial("is good", false, false, 3, 1, nil)).first?.text == "Ice cream is good")
        #expect(try ledger.apply(.partial("is great", true, false, 3, 3, nil)).first?.isFinal == false)
        let final = try ledger.apply(.partial("Ice cream is great.", true, true, 0, 6, "en"))
        #expect(final.first?.text == "Ice cream is great.")
        #expect(final.first?.isFinal == true)
        #expect(try ledger.apply(.partial("Ice cream is great.", true, true, 0, 6, "en")).isEmpty)
        #expect(try ledger.apply(.done("Ice cream is great.", 6, "en")).isEmpty)
    }

    @Test func cumulativeDoneConsumesOptionalWhitespaceOnlyBetweenUtterances() throws {
        for separator in ["", " ", "\n\n"] {
            var ledger = GrokTranscriptLedger()
            _ = try ledger.apply(.partial("こんにちは。", true, true, 0, 1, nil))
            _ = try ledger.apply(.partial("さようなら。", true, true, 1, 1, nil))
            _ = try ledger.apply(.partial("また", false, false, 2, 1, nil))
            let result = try ledger.apply(.done("こんにちは。" + separator + "さようなら。" + separator + "また会いましょう。", 4, nil))
            #expect(result.count == 1)
            #expect(result.first?.text == "また会いましょう。")
            #expect(result.first?.itemID == "2")
        }
        var inconsistent = GrokTranscriptLedger()
        _ = try inconsistent.apply(.partial("ice cream", true, true, 0, 1, nil))
        #expect(throws: GrokTranscriptionError.invalidResponse) { try inconsistent.apply(.done("icecream", 1, nil)) }
    }

    @Test func finalOnlyDoneAndEmptyFinalClearPendingHypothesis() throws {
        var ledger = GrokTranscriptLedger()
        #expect(try ledger.apply(.done("Only final text.", 1, nil)).first?.text == "Only final text.")
        var empty = GrokTranscriptLedger()
        _ = try empty.apply(.partial("hallucination", false, false, 0, 1, nil))
        let update = try empty.apply(.done("", 1, nil)).first
        #expect(update?.text == "" && update?.isFinal == true)
    }

    @Test func messageAndTranscriptQueuesAreBoundedAndErrorsAreRedacted() throws {
        let event = try GrokServerEvent.parse(Data(#"{"type":"error","message":"server-private-marker Authorization Bearer should-not-escape"}"#.utf8))
        guard case .failure(let error) = event else { Issue.record("error event required"); return }
        #expect(!error.localizedDescription.contains("server-private-marker"))
        #expect(!error.localizedDescription.contains("should-not-escape"))
        #expect(throws: GrokTranscriptionError.invalidResponse) { try GrokServerEvent.parse(Data(repeating: 32, count: GrokRealtimeTranscriber.maximumMessageBytes + 1)) }
        #expect(throws: GrokTranscriptionError.invalidResponse) { try GrokServerEvent.parse(Data(#"{"type":"transcript.partial","text":"bad","is_final":1,"speech_final":false,"start":0,"duration":1}"#.utf8)) }
        var ledger = GrokTranscriptLedger()
        for index in 0..<256 { _ = try ledger.apply(.partial("chunk", true, false, Double(index), 1, nil)) }
        #expect(throws: GrokTranscriptionError.backlog) { try ledger.apply(.partial("overflow", true, false, 256, 1, nil)) }
        let noLanguage = try GrokServerEvent.parse(Data(#"{"type":"transcript.partial","text":"hello","is_final":true,"speech_final":true,"start":0,"duration":1}"#.utf8))
        var parserLedger = GrokTranscriptLedger()
        #expect(try parserLedger.apply(noLanguage).first?.languageCode == nil)
    }

    @Test func readyGatesBinaryAudioAndPauseExcludesInput() async throws {
        let socket = GrokSocketStub(readyAutomatically: false)
        let service = makeService(socket)
        defer { service.stop() }
        let starting = Task { try await service.start(model: .voiceTranscribe2, sourceLanguage: .korean, autoDetectLanguage: true) }
        try await waitUntil { socket.isResumed }
        let sample = try makeSample(frames: 1_600)
        service.append(sample)
        #expect(socket.messages.isEmpty)
        socket.emit(["type": "transcript.created"])
        try await starting.value
        service.append(sample)
        service.setPaused(true)
        service.append(sample)
        try await service.finish()
        #expect(socket.messages == [.audio(Data(repeating: 0, count: 3_200)), .finish])
        #expect(socket.isClosed)
    }

    @Test func finishFlushesTailAndWaitsForFinalDeliveryThenAcceptsNormalClose() async throws {
        let socket = GrokSocketStub(finishAutomatically: false)
        let service = makeService(socket)
        defer { service.stop() }
        let results = GrokTestResults()
        service.onTranscript = { update in
            try? await Task.sleep(for: .milliseconds(30))
            await results.add(update)
        }
        service.onError = { await results.fail($0) }
        try await service.start(model: .voiceTranscribe2, sourceLanguage: .english, autoDetectLanguage: false)
        service.append(try makeSample(frames: 400))
        socket.emit(["type": "transcript.partial", "text": "first", "is_final": true, "speech_final": true, "start": 0, "duration": 1])
        let finishing = Task { try await service.finish() }
        try await waitUntil { socket.messages.contains(.finish) }
        #expect(!socket.isClosed)
        socket.emit(["type": "transcript.done", "text": "first last", "duration": 2])
        try await finishing.value
        #expect(await results.updates.map(\.text) == ["first", "last"])
        #expect(await results.failures.isEmpty)
        #expect(socket.messages == [.audio(Data(repeating: 0, count: 800)), .finish])
        #expect(socket.isClosed)
    }

    @Test func missingKeySetupAndFinishTimeoutFailWithoutServiceAccess() async throws {
        let missing = GrokRealtimeTranscriber(keyProvider: { nil })
        await #expect(throws: GrokTranscriptionError.missingKey) { try await missing.start(model: .voiceTranscribe2, sourceLanguage: .english, autoDetectLanguage: true) }
        let waiting = GrokSocketStub(readyAutomatically: false)
        let setup = makeService(waiting, timeout: .milliseconds(40))
        await #expect(throws: GrokTranscriptionError.setupTimeout) { try await setup.start(model: .voiceTranscribe2, sourceLanguage: .english, autoDetectLanguage: true) }
        #expect(waiting.isClosed)
        let neverDone = GrokSocketStub(finishAutomatically: false)
        let draining = makeService(neverDone, timeout: .milliseconds(40))
        try await draining.start(model: .voiceTranscribe2, sourceLanguage: .english, autoDetectLanguage: true)
        await #expect(throws: GrokTranscriptionError.finishTimeout) { try await draining.finish() }
        #expect(neverDone.isClosed)
    }

    @Test func badAudioAndBlockedSendStopAtQueueLimit() async throws {
        let socket = GrokSocketStub(blockAudio: true)
        let service = makeService(socket)
        defer { service.stop() }
        let results = GrokTestResults()
        service.onError = { await results.fail($0) }
        try await service.start(model: .voiceTranscribe2, sourceLanguage: .english, autoDetectLanguage: true)
        let sample = try makeSample(frames: 1_600)
        for _ in 0..<55 { service.append(sample) }
        try await waitUntil { await !results.failures.isEmpty }
        #expect(await results.failures == [.backlog])
        #expect(socket.isClosed)
        let badSocket = GrokSocketStub()
        let bad = makeService(badSocket)
        bad.onError = { await results.fail($0) }
        try await bad.start(model: .voiceTranscribe2, sourceLanguage: .english, autoDetectLanguage: true)
        bad.append(try makeSample(frames: 100, sampleRate: 24_000))
        try await waitUntil { await results.failures.count == 2 }
        #expect(await results.failures.last == .audioFormat)
        #expect(badSocket.isClosed)
    }

    @Test func restartRejectsLateEventsAndNamespacesRepeatedUtteranceIDs() async throws {
        let old = GrokSocketStub(finishAutomatically: false, allowLateReceiveAfterClose: true)
        let fresh = GrokSocketStub(finishAutomatically: false)
        let pool = GrokSocketPool([old, fresh])
        let service = GrokRealtimeTranscriber(keyProvider: { "test-only" }, connectionFactory: { _ in pool.next() })
        defer { service.stop() }
        let results = GrokTestResults()
        service.onTranscript = { await results.add($0) }
        try await service.start(model: .voiceTranscribe2, sourceLanguage: .english, autoDetectLanguage: true)
        old.emit(["type": "transcript.partial", "text": "first", "is_final": true, "speech_final": true, "start": 0, "duration": 1])
        try await waitUntil { await results.updates.count == 1 }
        service.stop()
        try await service.start(model: .voiceTranscribe2, sourceLanguage: .english, autoDetectLanguage: true)
        old.emit(["type": "transcript.partial", "text": "late", "is_final": true, "speech_final": true, "start": 1, "duration": 1])
        fresh.emit(["type": "transcript.partial", "text": "new", "is_final": true, "speech_final": true, "start": 0, "duration": 1])
        try await waitUntil { await results.updates.count == 2 }
        let updates = await results.updates
        #expect(updates.map(\.text) == ["first", "new"])
        #expect(updates[0].itemID != updates[1].itemID)
    }

    @Test func setupCancellationClosesConnectionAndFloatSamplesUsePCM16LittleEndian() async throws {
        let pending = GrokSocketStub(readyAutomatically: false)
        let waiting = makeService(pending)
        let task = Task { try await waiting.start(model: .voiceTranscribe2, sourceLanguage: .english, autoDetectLanguage: true) }
        try await waitUntil { pending.isResumed }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(pending.isClosed)

        let socket = GrokSocketStub()
        let service = makeService(socket)
        try await service.start(model: .voiceTranscribe2, sourceLanguage: .english, autoDetectLanguage: true)
        service.append(try makeSample(frames: 4, floatValues: [-2, -0.5, .nan, 2]))
        try await service.finish()
        guard case .audio(let pcm) = socket.messages.first else { Issue.record("PCM frame required"); return }
        let values = pcm.withUnsafeBytes { raw in
            stride(from: 0, to: pcm.count, by: 2).map { raw.loadUnaligned(fromByteOffset: $0, as: Int16.self).littleEndian }
        }
        #expect(values == [-32_767, -16_383, 0, 32_767])
        #expect(socket.messages.last == .finish)
    }

    private func makeService(_ socket: GrokSocketStub, timeout: Duration = .seconds(2)) -> GrokRealtimeTranscriber {
        GrokRealtimeTranscriber(keyProvider: { "test-only" }, connectionFactory: { _ in socket }, setupTimeout: timeout, finishTimeout: timeout)
    }
    private func waitUntil(_ predicate: () async throws -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while try await !predicate() {
            if ContinuousClock.now > deadline { throw GrokTranscriptionError.finishTimeout }
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

private final class GrokSocketPool: @unchecked Sendable {
    let lock = NSLock()
    var sockets: [GrokSocketStub]
    init(_ sockets: [GrokSocketStub]) { self.sockets = sockets }
    func next() -> GrokSocketStub { lock.withLock { sockets.removeFirst() } }
}
