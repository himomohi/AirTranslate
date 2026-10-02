import AVFoundation
import Foundation
import Testing
@testable import AirTranslate

private final class AzureMAISocketStub: AzureMAIWebSocketConnection, @unchecked Sendable {
    private let lock = NSLock()
    private var incoming: [Data] = []
    private var receiver: CheckedContinuation<Data, Error>?
    private var sender: CheckedContinuation<Void, Error>?
    private var closed = false
    private var sent: [String] = []
    private var item = 0
    let createdAutomatically: Bool
    let configuredAutomatically: Bool
    let completedAutomatically: Bool
    let blockAudio: Bool
    let allowLateReceive: Bool

    init(createdAutomatically: Bool = true, configuredAutomatically: Bool = true,
         completedAutomatically: Bool = true, blockAudio: Bool = false, allowLateReceive: Bool = false) {
        self.createdAutomatically = createdAutomatically
        self.configuredAutomatically = configuredAutomatically
        self.completedAutomatically = completedAutomatically
        self.blockAudio = blockAudio
        self.allowLateReceive = allowLateReceive
    }

    var messages: [String] { lock.withLock { sent } }
    var isClosed: Bool { lock.withLock { closed } }
    func resume() {
        if createdAutomatically { emit(["type": "session.created", "session": ["id": "test-only"]]) }
    }
    func send(_ message: String) async throws {
        let json = try JSONSerialization.jsonObject(with: Data(message.utf8)) as! [String: Any]
        let type = json["type"] as? String
        try lock.withLock { () throws -> Void in
            guard !closed else { throw CancellationError() }
            sent.append(message)
        }
        if type == "session.update", configuredAutomatically {
            emit(["type": "session.updated", "session": json["session"]!])
        } else if type == "input_audio_buffer.commit", completedAutomatically {
            let id = lock.withLock { item += 1; return "item-\(item)" }
            emit(["type": "input_audio_buffer.committed", "item_id": id])
            emit(["type": "conversation.item.input_audio_transcription.completed", "item_id": id, "transcript": "final \(id)"])
        } else if type == "input_audio_buffer.append", blockAudio {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                lock.withLock { () -> Void in
                    if closed { continuation.resume(throwing: CancellationError()) }
                    else { sender = continuation }
                }
            }
        }
    }
    func receive() async throws -> Data {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            lock.withLock {
                if !incoming.isEmpty { continuation.resume(returning: incoming.removeFirst()) }
                else if closed && !allowLateReceive { continuation.resume(throwing: CancellationError()) }
                else { receiver = continuation }
            }
        }
    }
    func emit(_ object: [String: Any]) {
        let data = try! JSONSerialization.data(withJSONObject: object)
        let waiter = lock.withLock { () -> CheckedContinuation<Data, Error>? in
            if let receiver { self.receiver = nil; return receiver }
            incoming.append(data)
            return nil
        }
        waiter?.resume(returning: data)
    }
    func close() {
        let waiters = lock.withLock { () -> (CheckedContinuation<Data, Error>?, CheckedContinuation<Void, Error>?) in
            closed = true
            let waiters = (allowLateReceive ? nil : receiver, sender)
            if !allowLateReceive { receiver = nil }
            sender = nil
            return waiters
        }
        waiters.0?.resume(throwing: CancellationError())
        waiters.1?.resume(throwing: CancellationError())
    }
}

private actor AzureMAIStreamingResults {
    var finals: [String] = []
    var partials: [String] = []
    var errors: [String] = []
    func result(_ result: Result<String, AzureMAIError>) {
        switch result {
        case .success(let text): finals.append(text)
        case .failure(let error):
            switch error {
            case .configuration: errors.append("configuration")
            case .audioFormat: errors.append("audioFormat")
            case .backlog: errors.append("backlog")
            case .connection: errors.append("connection")
            case .response: errors.append("response")
            case .http(let code): errors.append("http-\(code)")
            }
        }
    }
    func partial(_ text: String) { partials.append(text) }
}

private final class AzureMAISocketPool: @unchecked Sendable {
    private let lock = NSLock()
    private var sockets: [AzureMAISocketStub]
    init(_ sockets: [AzureMAISocketStub]) { self.sockets = sockets }
    func next() -> AzureMAISocketStub { lock.withLock { sockets.removeFirst() } }
}

@Suite(.serialized)
struct AzureMAIStreamingTranscriberTests {
    @Test func authenticatedEndpointAndExactSessionContract() throws {
        let request = try AzureMAIStreamingTranscriber.request(endpoint: "https://test-resource.services.ai.azure.com/", key: "test-only")
        #expect(request.url?.absoluteString == "wss://test-resource.services.ai.azure.com/mai/v1/realtime?intent=transcription")
        #expect(request.value(forHTTPHeaderField: "api-key") == "test-only")
        #expect(!request.url!.absoluteString.contains("test-only"))
        #expect(request.value(forHTTPHeaderField: "Ocp-Apim-Subscription-Key") == nil)
        #expect(request.httpBody == nil)
        let message = try AzureMAIStreamingTranscriber.configurationMessage(deployment: "mai-stream-test", language: "ko")
        let json = try #require(JSONSerialization.jsonObject(with: Data(message.utf8)) as? [String: Any])
        #expect(json["type"] as? String == "session.update")
        let session = try #require(json["session"] as? [String: Any])
        #expect(session["type"] as? String == "transcription")
        let audio = try #require(session["audio"] as? [String: Any])
        let input = try #require(audio["input"] as? [String: Any])
        let format = try #require(input["format"] as? [String: Any])
        #expect(format["type"] as? String == "audio/pcm")
        #expect(format["rate"] as? Int == 16_000)
        #expect(input["turn_detection"] is NSNull)
        #expect(input["noise_reduction"] is NSNull)
        let transcription = try #require(input["transcription"] as? [String: Any])
        #expect(transcription["model"] as? String == "mai-stream-test")
        #expect(transcription["language"] as? String == "ko")
        let automatic = try AzureMAIStreamingTranscriber.configurationMessage(deployment: "mai-stream-test", language: nil)
        #expect(automatic.contains("\"language\":null"))
        #expect(AzureMAIStreamingTranscriber.supportedLanguages.count == 60)
    }

    @Test func endpointsAndHeaderInjectionAreRejectedBeforeConnection() {
        let bad = [
            "http://test.services.ai.azure.com", "wss://test.services.ai.azure.com", "https://services.ai.azure.com",
            "https://test.services.ai.azure.com.evil.example", "https://evil.example/test.services.ai.azure.com",
            "https://test.cognitiveservices.azure.com", "https://nested.test.services.ai.azure.com",
            "https://user:password@test.services.ai.azure.com", "https://test.services.ai.azure.com:443",
            "https://test.services.ai.azure.com/path", "https://test.services.ai.azure.com?api-key=secret",
            "https://test.services.ai.azure.com#fragment", "https://-test.services.ai.azure.com"
        ]
        for endpoint in bad {
            #expect(throws: AzureMAIError.self) { try AzureMAIStreamingTranscriber.endpointURL(endpoint) }
        }
        #expect(throws: AzureMAIError.self) {
            try AzureMAIStreamingTranscriber.request(endpoint: "https://test.services.ai.azure.com", key: "bad\r\nheader")
        }
        #expect(throws: AzureMAIError.self) {
            try AzureMAIStreamingTranscriber.configurationMessage(deployment: "", language: nil)
        }
        #expect(throws: AzureMAIError.self) {
            try AzureMAIStreamingTranscriber.configurationMessage(deployment: "test", language: "ko-KR")
        }
    }

    @Test func provisionalSuffixReplacesAndCompletedIsOnlyFinalDelivery() throws {
        var ledger = AzureMAITranscriptLedger()
        #expect(try ledger.apply(.delta("a", "Hello")).partial == "Hello")
        #expect(try ledger.apply(.intermediate("a", " world")).partial == "Hello world")
        #expect(try ledger.apply(.intermediate("a", " there")).partial == "Hello there")
        #expect(try ledger.apply(.delta("a", " there!")).partial == "Hello there!")
        try ledger.registerCommit()
        #expect(try ledger.apply(.committed("a")).finals.isEmpty)
        #expect(try ledger.apply(.completed("a", "Hello there!")).finals == ["Hello there!"])
        #expect(try ledger.apply(.completed("a", "duplicate")).finals.isEmpty)
        #expect(try ledger.apply(.intermediate("a", "stale")).partial == nil)
        #expect(ledger.isDrained)
    }

    @Test func outOfOrderFinalsFollowCommitOrderAndSameTextCanRepeat() throws {
        var ledger = AzureMAITranscriptLedger()
        try ledger.registerCommit(); try ledger.registerCommit()
        _ = try ledger.apply(.committed("a")); _ = try ledger.apply(.committed("b"))
        #expect(try ledger.apply(.completed("b", "same")).finals.isEmpty)
        #expect(!ledger.isDrained)
        #expect(try ledger.apply(.completed("a", "same")).finals == ["same", "same"])
        #expect(ledger.isDrained)
        try ledger.registerCommit()
        _ = try ledger.apply(.committed(nil))
        #expect(try ledger.apply(.completed(nil, "")).finals == [""])
        #expect(try ledger.apply(.completed(nil, "duplicate")).finals.isEmpty)
        #expect(ledger.isDrained)
    }

    @Test func laterPartialWaitsForEarlierFinalThenPublishesLatestSuffix() throws {
        var ledger = AzureMAITranscriptLedger()
        try ledger.registerCommit(); try ledger.registerCommit()
        _ = try ledger.apply(.committed("a")); _ = try ledger.apply(.committed("b"))
        #expect(try ledger.apply(.delta("a", "first")).partial == "first")
        #expect(try ledger.apply(.delta("b", "next")).partial == nil)
        #expect(try ledger.apply(.intermediate("b", " draft")).partial == nil)
        #expect(try ledger.apply(.intermediate("b", " latest")).partial == nil)
        let result = try ledger.apply(.completed("a", "first final"))
        #expect(result.finals == ["first final"])
        #expect(result.partial == "next latest")
        #expect(try ledger.apply(.completed("b", "next final")).finals == ["next final"])
    }

    @Test func emptyCompletionIsDeliveredToClearProvisionalCaption() async throws {
        let socket = AzureMAISocketStub(completedAutomatically: false)
        let service = makeService(socket)
        let results = AzureMAIStreamingResults()
        defer { service.stop() }
        try await start(service, results: results)
        service.append(try makeSample(frames: 400))
        let finishing = Task { await service.finish() }
        try await waitUntil { socket.messages.count == 3 }
        socket.emit(["type": "input_audio_buffer.committed", "item_id": "empty"])
        socket.emit(["type": "conversation.item.input_audio_transcription.intermediate", "item_id": "empty", "intermediate": "discard this draft"])
        socket.emit(["type": "conversation.item.input_audio_transcription.completed", "item_id": "empty", "transcript": ""])
        await finishing.value
        #expect(await results.partials == ["discard this draft"])
        #expect(await results.finals == [""])
        #expect(socket.isClosed)
    }

    @Test func missingFieldsAndUnboundedCommitsAreRejected() throws {
        var ledger = AzureMAITranscriptLedger()
        for _ in 0..<AzureMAIStreamingTranscriber.maximumPendingCommits { try ledger.registerCommit() }
        #expect(throws: AzureMAIError.self) { try ledger.registerCommit() }
        #expect(throws: AzureMAIError.self) { try AzureMAIStreamingEvent.parse(Data("not-json".utf8)) }
        #expect(throws: AzureMAIError.self) {
            try AzureMAIStreamingEvent.parse(Data(#"{"type":"conversation.item.input_audio_transcription.intermediate","item_id":"a","delta":"wrong field"}"#.utf8))
        }
        #expect(throws: AzureMAIError.self) {
            try AzureMAIStreamingEvent.parse(Data(repeating: 32, count: AzureMAIStreamingTranscriber.maximumMessageBytes + 1))
        }
        if case .failure = try AzureMAIStreamingEvent.parse(Data(#"{"type":"error","error":{"message":"secret and private transcript"}}"#.utf8)) {} else {
            Issue.record("공급자 오류는 공개된 오류 종류로만 전달해야 한다.")
        }
    }

    @Test func createdAndUpdatedHandshakeGatesAudioAndPauseFlushesTail() async throws {
        let socket = AzureMAISocketStub(createdAutomatically: false, configuredAutomatically: false)
        let service = makeService(socket)
        defer { service.stop() }
        let results = AzureMAIStreamingResults()
        let starting = Task { try await start(service, results: results) }
        try await Task.sleep(for: .milliseconds(20))
        #expect(socket.messages.isEmpty)
        service.append(try makeSample(frames: 1_600))
        socket.emit(["type": "session.created", "session": ["id": "test-only"]])
        try await waitUntil { socket.messages.count == 1 }
        service.append(try makeSample(frames: 1_600))
        #expect(socket.messages.count == 1)
        let json = try #require(JSONSerialization.jsonObject(with: Data(socket.messages[0].utf8)) as? [String: Any])
        socket.emit(["type": "session.updated", "session": json["session"]!])
        try await starting.value
        service.append(try makeSample(frames: 400)) // 25 ms 잔여 오디오도 pause에서 전송한다.
        service.setPaused(true)
        service.append(try makeSample(frames: 1_600))
        await service.finish()
        #expect(socket.isClosed)
        #expect(socket.messages.count == 3) // session.update, append, commit
        let append = try #require(JSONSerialization.jsonObject(with: Data(socket.messages[1].utf8)) as? [String: Any])
        let base64 = try #require(append["audio"] as? String)
        let pcm = try #require(Data(base64Encoded: base64))
        #expect(pcm.count == 800)
        #expect(Array(pcm.prefix(4)) == [0, 0, 0, 0])
        #expect(await results.finals == ["final item-1"])
    }

    @Test func periodicCommitAndFinishWaitForFinalAndCallbackApplication() async throws {
        let socket = AzureMAISocketStub(completedAutomatically: false)
        let service = makeService(socket)
        defer { service.stop() }
        let results = AzureMAIStreamingResults()
        try await service.start(endpoint: endpoint, key: "test-only", deployment: "mai-stream-test", language: "en",
            handler: { result in try? await Task.sleep(for: .milliseconds(30)); await results.result(result) },
            partialHandler: { await results.partial($0) })
        for _ in 0..<30 { service.append(try makeSample(frames: 1_600)) }
        try await waitUntil { socket.messages.filter { $0.contains("input_audio_buffer.commit") }.count == 1 }
        socket.emit(["type": "input_audio_buffer.committed", "item_id": "a"])
        socket.emit(["type": "conversation.item.input_audio_transcription.delta", "item_id": "a", "delta": "first"])
        socket.emit(["type": "conversation.item.input_audio_transcription.intermediate", "item_id": "a", "intermediate": " partial"])
        service.append(try makeSample(frames: 400))
        let finishing = Task { await service.finish() }
        try await waitUntil { socket.messages.filter { $0.contains("input_audio_buffer.commit") }.count == 2 }
        socket.emit(["type": "input_audio_buffer.committed", "item_id": "b"])
        socket.emit(["type": "conversation.item.input_audio_transcription.completed", "item_id": "b", "transcript": "second"])
        try await Task.sleep(for: .milliseconds(20))
        #expect(!socket.isClosed)
        socket.emit(["type": "conversation.item.input_audio_transcription.completed", "item_id": "a", "transcript": "first final"])
        await finishing.value
        #expect(await results.finals == ["first final", "second"])
        #expect(await results.partials == ["first", "first partial"])
        #expect(socket.isClosed)
    }

    @Test func saturationAndProviderFailureCloseAndReportOnlySanitizedErrors() async throws {
        let socket = AzureMAISocketStub(blockAudio: true)
        let service = makeService(socket)
        let results = AzureMAIStreamingResults()
        try await start(service, results: results)
        service.append(try makeSample(frames: 1_600))
        try await waitUntil { socket.messages.count == 2 }
        for _ in 0...AzureMAIStreamingTranscriber.maximumPendingAudioChunks { service.append(try makeSample(frames: 1_600)) }
        try await waitUntil { socket.isClosed }
        try await waitUntil { await results.errors.count == 1 }
        #expect(await results.errors == ["backlog"])
        #expect(socket.messages.count == 2)
        service.stop()
        let otherSocket = AzureMAISocketStub()
        let other = makeService(otherSocket)
        let otherResults = AzureMAIStreamingResults()
        defer { other.stop() }
        try await start(other, results: otherResults)
        otherSocket.emit(["type": "error", "error": ["message": "secret key and private transcript"]])
        try await waitUntil { await otherResults.errors.count == 1 }
        #expect(await otherResults.errors == ["response"])
        #expect(otherSocket.isClosed)
    }

    @Test func setupFinishAndCancellationHaveFiniteTermination() async throws {
        let socket = AzureMAISocketStub(createdAutomatically: false)
        let service = makeService(socket, timeout: .milliseconds(50))
        await #expect(throws: AzureMAIError.self) { try await start(service, results: AzureMAIStreamingResults()) }
        #expect(socket.isClosed)
        service.stop()
        let noFinal = AzureMAISocketStub(completedAutomatically: false)
        let finishingService = makeService(noFinal, timeout: .milliseconds(50))
        let results = AzureMAIStreamingResults()
        try await finishingService.start(endpoint: endpoint, key: "test-only", deployment: "mai-stream-test", language: nil,
            handler: { result in try? await Task.sleep(for: .milliseconds(30)); await results.result(result) },
            partialHandler: { await results.partial($0) })
        finishingService.append(try makeSample(frames: 400))
        await finishingService.finish()
        #expect(noFinal.isClosed)
        // finish 반환 전에 호출자의 마지막 오류 적용도 끝나야 한다.
        #expect(await results.errors == ["connection"])
        #expect(await results.finals.isEmpty)
        finishingService.stop()
        let pendingSocket = AzureMAISocketStub(createdAutomatically: false)
        let pending = makeService(pendingSocket)
        let task = Task { try await start(pending, results: AzureMAIStreamingResults()) }
        try await Task.sleep(for: .milliseconds(20))
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(pendingSocket.isClosed)
        pending.stop()
    }

    @Test func restartSuppressesOldResultsAndDoesNotReplayPausedAudio() async throws {
        let old = AzureMAISocketStub(allowLateReceive: true)
        let current = AzureMAISocketStub()
        let pool = AzureMAISocketPool([old, current])
        let service = AzureMAIStreamingTranscriber(connectionFactory: { _ in pool.next() })
        let results = AzureMAIStreamingResults()
        defer { service.stop() }
        try await start(service, results: results)
        service.setPaused(true)
        service.append(try makeSample(frames: 1_600))
        service.stop()
        try await start(service, results: results)
        old.emit(["type": "conversation.item.input_audio_transcription.intermediate", "item_id": "stale", "intermediate": "must not appear"])
        service.append(try makeSample(frames: 400))
        await service.finish()
        #expect(await results.partials.isEmpty)
        #expect(await results.finals == ["final item-1"])
        #expect(old.messages.count == 1)
        #expect(current.messages.count == 3)
        #expect(old.isClosed && current.isClosed)
    }

    private var endpoint: String { "https://test-resource.services.ai.azure.com" }
    private func makeService(_ socket: AzureMAISocketStub, timeout: Duration = .seconds(2)) -> AzureMAIStreamingTranscriber {
        AzureMAIStreamingTranscriber(connectionFactory: { _ in socket }, setupTimeout: timeout, finishTimeout: timeout)
    }
    private func start(_ service: AzureMAIStreamingTranscriber, results: AzureMAIStreamingResults) async throws {
        try await service.start(endpoint: endpoint, key: "test-only", deployment: "mai-stream-test", language: nil,
            handler: { await results.result($0) }, partialHandler: { await results.partial($0) })
    }
    private func waitUntil(_ predicate: () async throws -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while try await !predicate() {
            guard ContinuousClock.now < deadline else { throw AzureMAIError.connection }
            try await Task.sleep(for: .milliseconds(5))
        }
    }
    private func makeSample(frames: Int) throws -> CMSampleBuffer {
        var description = AudioStreamBasicDescription(mSampleRate: 16_000, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 2, mFramesPerPacket: 1, mBytesPerFrame: 2,
            mChannelsPerFrame: 1, mBitsPerChannel: 16, mReserved: 0)
        var format: CMAudioFormatDescription?
        #expect(CMAudioFormatDescriptionCreate(allocator: kCFAllocatorDefault, asbd: &description,
            layoutSize: 0, layout: nil, magicCookieSize: 0, magicCookie: nil, extensions: nil,
            formatDescriptionOut: &format) == noErr)
        var block: CMBlockBuffer?
        #expect(CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault, memoryBlock: nil,
            blockLength: frames * 2, blockAllocator: kCFAllocatorDefault, customBlockSource: nil,
            offsetToData: 0, dataLength: frames * 2, flags: kCMBlockBufferAssureMemoryNowFlag,
            blockBufferOut: &block) == noErr)
        let audioBlock = try #require(block)
        #expect(CMBlockBufferFillDataBytes(with: 0, blockBuffer: audioBlock,
            offsetIntoDestination: 0, dataLength: frames * 2) == noErr)
        var sample: CMSampleBuffer?
        #expect(CMSampleBufferCreateReady(allocator: kCFAllocatorDefault, dataBuffer: audioBlock,
            formatDescription: try #require(format), sampleCount: frames,
            sampleTimingEntryCount: 0, sampleTimingArray: nil, sampleSizeEntryCount: 0,
            sampleSizeArray: nil, sampleBufferOut: &sample) == noErr)
        return try #require(sample)
    }
}
