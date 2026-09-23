import AVFoundation
import Foundation
import Testing
@testable import AirTranslate

private final class QwenSocketStub: QwenWebSocketConnection, @unchecked Sendable {
    private let lock = NSLock()
    private var incoming: [Data] = []
    private var waiter: CheckedContinuation<Data, Error>?
    private var blockedSend: CheckedContinuation<Void, Error>?
    private var closed = false
    private var resumed = false
    private var sentMessages: [String] = []
    let createAutomatically: Bool
    let updateAutomatically: Bool
    let finishAutomatically: Bool
    let blockAudio: Bool
    let allowLateReceiveAfterClose: Bool
    let model: QwenTranslationModel

    init(createAutomatically: Bool = true, updateAutomatically: Bool = true, finishAutomatically: Bool = true,
         blockAudio: Bool = false, allowLateReceiveAfterClose: Bool = false,
         model: QwenTranslationModel = .liveTranslateFlashRealtime) {
        self.createAutomatically = createAutomatically
        self.updateAutomatically = updateAutomatically
        self.finishAutomatically = finishAutomatically
        self.blockAudio = blockAudio
        self.allowLateReceiveAfterClose = allowLateReceiveAfterClose
        self.model = model
    }

    var messages: [[String: Any]] {
        lock.withLock { sentMessages.map { try! JSONSerialization.jsonObject(with: Data($0.utf8)) as! [String: Any] } }
    }
    var messageTypes: [String] { messages.compactMap { $0["type"] as? String } }
    var isClosed: Bool { lock.withLock { closed } }
    var isResumed: Bool { lock.withLock { resumed } }

    func resume() {
        lock.withLock { resumed = true }
        if createAutomatically { emit(Self.sessionEvent("session.created", model: model)) }
    }

    func send(_ text: String) async throws {
        try lock.withLock {
            guard !closed else { throw CancellationError() }
            sentMessages.append(text)
        }
        let json = try JSONSerialization.jsonObject(with: Data(text.utf8)) as! [String: Any]
        switch json["type"] as? String {
        case "session.update" where updateAutomatically:
            let session = json["session"] as! [String: Any]
            if model == .audio31RealtimePlus {
                let audio = (session["modalities"] as! [String]).contains("audio")
                emit(Self.sessionEvent("session.updated", audio: audio, model: model))
            } else {
                let target = (session["translation"] as! [String: Any])["language"] as! String
                let audio = (session["output_modalities"] as! [String]).contains("audio")
                emit(Self.sessionEvent("session.updated", target: target, audio: audio, model: model))
            }
        case "session.finish" where finishAutomatically:
            emit(["type": "session.finished"])
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
        let data = try! JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
        lock.withLock {
            guard !closed || allowLateReceiveAfterClose else { return }
            if let waiter { self.waiter = nil; waiter.resume(returning: data) }
            else { incoming.append(data) }
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

    static func sessionEvent(
        _ type: String,
        target: String = "ko",
        audio: Bool = false,
        model: QwenTranslationModel = .liveTranslateFlashRealtime
    ) -> [String: Any] {
        if model == .audio31RealtimePlus {
            return ["type": type, "session": [
                "model": model.rawValue,
                "modalities": audio ? ["text", "audio"] : ["text"],
                "voice": "longanqian_v3.1",
                "input_audio_format": "pcm",
                "output_audio_format": "pcm",
                "instructions": "Translate spoken language to \(target).",
                "turn_detection": ["type": "server_vad", "threshold": 0.5, "silence_duration_ms": 800],
            ]]
        }
        return ["type": type, "session": [
            "model": model.rawValue,
            "output_modalities": audio ? ["text", "audio"] : ["text"],
            "translation": ["language": target],
            "audio": [
                "input": ["format": ["type": "pcm", "sample_rate": 16_000]],
                "output": ["format": ["type": "pcm", "sample_rate": 24_000]]
            ]
        ]]
    }
}

private actor QwenTestResults {
    struct Text: Equatable { let value: String; let final: Bool }
    var source: [Text] = []
    var translation: [Text] = []
    var audio: [Data] = []
    var failures: [QwenTranslationError] = []
    func addSource(_ text: String, _ final: Bool) { source.append(.init(value: text, final: final)) }
    func addTranslation(_ text: String, _ final: Bool) { translation.append(.init(value: text, final: final)) }
    func addAudio(_ data: Data) { audio.append(data) }
    func fail(_ error: Error) { if let error = error as? QwenTranslationError { failures.append(error) } }
}

@Suite(.serialized)
struct QwenRealtimeTranslationServiceTests {
    @Test func requestPinsWorkspaceHostAndKeepsCredentialsInHeader() throws {
        let request = try QwenRealtimeTranslationService.request(key: "test-only", workspaceID: " ws-123 ")
        let url = try #require(request.url)
        #expect(url.scheme == "wss")
        #expect(url.host == "ws-123.ap-southeast-1.maas.aliyuncs.com")
        #expect(url.path == "/api-ws/v1/realtime")
        #expect(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems == [
            .init(name: "model", value: "qwen3.8-livetranslate-flash-realtime")
        ])
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-only")
        #expect(!url.absoluteString.contains("test-only"))
        #expect(request.httpBody == nil)
        for workspace in ["", "host.evil", "ws@evil", "ws/path", "ws?model=other", "ws#fragment", "-bad", "bad-", "한글", String(repeating: "a", count: 64)] {
            #expect(throws: QwenTranslationError.configuration) {
                try QwenRealtimeTranslationService.request(key: "test-only", workspaceID: workspace)
            }
        }
        #expect(throws: QwenTranslationError.missingKey) {
            try QwenRealtimeTranslationService.request(key: "bad\r\nheader", workspaceID: "ws-123")
        }
    }

    @Test func configurationUsesThreePointEightFieldsAndCurrentSupportedLanguages() throws {
        let text = try QwenRealtimeTranslationService.configuration(language: "ko", audioOutputEnabled: false)
        let root = try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        let session = try #require(root["session"] as? [String: Any])
        #expect(root["type"] as? String == "session.update")
        #expect(session["output_modalities"] as? [String] == ["text"])
        #expect((session["translation"] as? [String: String]) == ["language": "ko"])
        #expect(session.count == 2)
        #expect(session["modalities"] == nil && session["input_audio_transcription"] == nil)
        for language in LanguageOption.supported { _ = try QwenRealtimeTranslationService.languageCode(language) }
        #expect(throws: QwenTranslationError.configuration) {
            try QwenRealtimeTranslationService.languageCode(.init(id: "invalid", title: "Invalid", locale: .current))
        }
    }

    @Test func audio31RequestAndConfigurationUseQwenAudioProtocol() throws {
        let request = try QwenRealtimeTranslationService.request(
            key: "test-only", workspaceID: " ws-123 ", model: .audio31RealtimePlus
        )
        let url = try #require(request.url)
        #expect(url.host == "maas.qwencloudapi.com")
        #expect(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems == [
            .init(name: "model", value: "qwen-audio-3.1-realtime-plus")
        ])
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-only")
        #expect(request.value(forHTTPHeaderField: "X-DashScope-WorkSpace") == "ws-123")

        let text = try QwenRealtimeTranslationService.configuration(
            language: "ko", audioOutputEnabled: true, model: .audio31RealtimePlus
        )
        let root = try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        let session = try #require(root["session"] as? [String: Any])
        #expect(session["modalities"] as? [String] == ["text", "audio"])
        #expect(session["input_audio_format"] as? String == "pcm")
        #expect(session["output_audio_format"] as? String == "pcm")
        #expect((session["turn_detection"] as? [String: Any])?["type"] as? String == "server_vad")
        #expect((session["instructions"] as? String)?.contains("Korean") == true)
        #expect(session["translation"] == nil && session["output_modalities"] == nil)
    }

    @Test func audio31ParserAcceptsRealtimeSessionAndTranscriptEvents() throws {
        let created = try QwenServerEvent.parse(
            JSONSerialization.data(withJSONObject: QwenSocketStub.sessionEvent("session.created", model: .audio31RealtimePlus)),
            model: .audio31RealtimePlus
        )
        guard case .created = created else { Issue.record("session.created required"); return }

        let updated = try QwenServerEvent.parse(
            JSONSerialization.data(withJSONObject: QwenSocketStub.sessionEvent("session.updated", audio: true, model: .audio31RealtimePlus)),
            model: .audio31RealtimePlus
        )
        guard case .updated(nil, ["text", "audio"]) = updated else { Issue.record("Qwen Audio session.updated required"); return }

        let source = try QwenServerEvent.parse(Data(#"{"type":"conversation.item.input_audio_transcription.delta","item_id":"source","text":"Hello ","stash":"world"}"#.utf8), model: .audio31RealtimePlus)
        guard case .source("source", "Hello world", false) = source else { Issue.record("stable and provisional source text required"); return }

        let response = try QwenServerEvent.parse(Data(#"{"type":"response.done","response":{"status":"completed"}}"#.utf8), model: .audio31RealtimePlus)
        guard case .responseFinished = response else { Issue.record("response.done required"); return }
    }

    @Test func audio31FinishDrainsVADAndWaitsForResponseDone() async throws {
        let socket = QwenSocketStub(model: .audio31RealtimePlus)
        let service = QwenRealtimeTranslationService(
            keyProvider: { "test-only" }, connectionFactory: { _ in socket },
            setupTimeout: .seconds(2), finishTimeout: .seconds(4)
        )
        defer { service.stop() }
        try await service.start(
            workspaceID: "ws-test", targetLanguage: .korean, audioOutputEnabled: false,
            model: .audio31RealtimePlus
        )
        service.append(try makeSample(frames: 1_600))
        let finishing = Task { try await service.finish() }
        try await waitUntil { socket.messageTypes.filter { $0 == "input_audio_buffer.append" }.count == 11 }
        #expect(!socket.messageTypes.contains("session.finish"))
        for audio in socket.messages.dropFirst().compactMap({ $0["audio"] as? String }).suffix(10) {
            #expect(Data(base64Encoded: audio) == Data(repeating: 0, count: 3_200))
        }
        socket.emit(["type": "response.created", "response": ["status": "in_progress"]])
        socket.emit(["type": "conversation.item.input_audio_transcription.completed", "item_id": "source", "transcript": "Hello."])
        socket.emit(["type": "response.text.done", "item_id": "translated", "text": "안녕하세요."])
        socket.emit(["type": "response.done", "response": ["status": "completed"]])
        try await finishing.value
        #expect(socket.isClosed)
    }

    @Test func audio31FinishDuringSilenceUsesBoundedIdleGrace() async throws {
        let socket = QwenSocketStub(model: .audio31RealtimePlus)
        let service = QwenRealtimeTranslationService(
            keyProvider: { "test-only" }, connectionFactory: { _ in socket },
            setupTimeout: .seconds(2), finishTimeout: .seconds(3), idleDrainGrace: .milliseconds(10)
        )
        defer { service.stop() }
        try await service.start(
            workspaceID: "ws-test", targetLanguage: .korean, audioOutputEnabled: false,
            model: .audio31RealtimePlus
        )

        try await service.finish()

        #expect(socket.messageTypes.filter { $0 == "input_audio_buffer.append" }.count == 10)
        #expect(socket.isClosed)
    }

    @Test func audio31FinishWaitsForResponseThatStartedBeforeDraining() async throws {
        let socket = QwenSocketStub(model: .audio31RealtimePlus)
        let service = QwenRealtimeTranslationService(
            keyProvider: { "test-only" }, connectionFactory: { _ in socket },
            setupTimeout: .seconds(2), finishTimeout: .seconds(3), idleDrainGrace: .milliseconds(20)
        )
        defer { service.stop() }
        let results = QwenTestResults()
        service.onSourceTranscript = { await results.addSource($0, $1) }
        try await service.start(
            workspaceID: "ws-test", targetLanguage: .korean, audioOutputEnabled: false,
            model: .audio31RealtimePlus
        )
        service.append(try makeSample(frames: 1_600))
        socket.emit(["type": "response.created", "response": ["status": "in_progress"]])
        socket.emit(["type": "conversation.item.input_audio_transcription.completed", "item_id": "source", "transcript": "Hello."])
        try await waitUntil { await results.source.count == 1 }

        let finishing = Task { try await service.finish() }
        try await waitUntil { socket.messageTypes.filter { $0 == "input_audio_buffer.append" }.count == 11 }
        try await Task.sleep(for: .milliseconds(60))
        #expect(!socket.isClosed)

        socket.emit(["type": "response.done", "response": ["status": "completed"]])
        try await finishing.value
        #expect(socket.isClosed)
    }

    @Test func ledgerDeliversDeltasAndAuthoritativeFinalOnceWithoutMixingItems() throws {
        var ledger = QwenTextLedger()
        #expect(try ledger.apply(id: "one", text: "안녕", final: false) == "안녕")
        #expect(try ledger.apply(id: "one", text: "하세요", final: false) == "하세요")
        #expect(!ledger.isDrained)
        #expect(throws: QwenTranslationError.invalidResponse) { try ledger.apply(id: "two", text: "later", final: false) }
        #expect(try ledger.apply(id: "one", text: "안녕하세요.", final: true) == "안녕하세요.")
        #expect(ledger.isDrained)
        #expect(try ledger.apply(id: "one", text: "안녕하세요.", final: true) == nil)
        #expect(try ledger.apply(id: "one", text: "stale", final: false) == nil)
        #expect(try ledger.apply(id: "two", text: "", final: true) == "")
        #expect(throws: QwenTranslationError.backlog) { try ledger.apply(id: "three", text: String(repeating: "a", count: 256 * 1_024 + 1), final: false) }
    }

    @Test func createdThenUpdatedGateAudioAndPauseDropsNewInput() async throws {
        let socket = QwenSocketStub(createAutomatically: false, updateAutomatically: false)
        let service = makeService(socket)
        defer { service.stop() }
        let starting = Task { try await service.start(workspaceID: "ws-test", targetLanguage: .korean, audioOutputEnabled: false) }
        try await waitUntil { socket.isResumed }
        let sample = try makeSample(frames: 1_600)
        service.append(sample)
        #expect(socket.messageTypes.isEmpty)
        socket.emit(QwenSocketStub.sessionEvent("session.created"))
        try await waitUntil { socket.messageTypes == ["session.update"] }
        service.append(sample)
        #expect(socket.messageTypes == ["session.update"])
        socket.emit(QwenSocketStub.sessionEvent("session.updated"))
        try await starting.value
        service.append(sample)
        service.setPaused(true)
        service.append(sample)
        try await service.finish()
        #expect(socket.messageTypes == ["session.update", "input_audio_buffer.append", "session.finish"])
        let encoded = try #require(socket.messages[1]["audio"] as? String)
        #expect(Data(base64Encoded: encoded) == Data(repeating: 0, count: 3_200))
        #expect(socket.isClosed)
    }

    @Test func finishFlushesTailAndWaitsForSourceTranslationAudioAndFinished() async throws {
        let socket = QwenSocketStub(finishAutomatically: false)
        let service = makeService(socket)
        defer { service.stop() }
        let results = QwenTestResults()
        service.onSourceTranscript = { await results.addSource($0, $1) }
        service.onTranslation = { text, final in
            try? await Task.sleep(for: .milliseconds(20))
            await results.addTranslation(text, final)
        }
        service.onAudio = { await results.addAudio($0) }
        service.onError = { await results.fail($0) }
        try await service.start(workspaceID: "ws-test", targetLanguage: .korean, audioOutputEnabled: true)
        service.append(try makeSample(frames: 400))
        socket.emit(["type": "conversation.item.input_audio_transcription.delta", "item_id": "source", "delta": "Hello"])
        socket.emit(["type": "conversation.item.input_audio_transcription.completed", "item_id": "source", "transcript": "Hello."])
        socket.emit(["type": "response.audio_transcript.delta", "item_id": "translation", "delta": "안녕"])
        socket.emit(["type": "response.audio_transcript.delta", "item_id": "translation", "delta": "하세요."])
        let finishing = Task { try await service.finish() }
        try await waitUntil { socket.messageTypes.contains("session.finish") }
        #expect(!socket.isClosed)
        socket.emit(["type": "response.audio_transcript.done", "item_id": "translation", "transcript": "안녕하세요."])
        socket.emit(["type": "response.audio_transcript.done", "item_id": "translation", "transcript": "안녕하세요."])
        let pcm = Data([0, 0, 1, 0])
        socket.emit(["type": "response.audio.delta", "delta": pcm.base64EncodedString()])
        socket.emit(["type": "response.done", "response": ["status": "completed"]])
        socket.emit(["type": "session.finished"])
        try await finishing.value
        #expect(await results.source == [.init(value: "Hello", final: false), .init(value: "Hello.", final: true)])
        #expect(await results.translation == [.init(value: "안녕", final: false), .init(value: "하세요.", final: false), .init(value: "안녕하세요.", final: true)])
        #expect(await results.audio == [pcm])
        #expect(await results.failures.isEmpty)
        #expect(socket.messageTypes == ["session.update", "input_audio_buffer.append", "session.finish"])
        #expect(Data(base64Encoded: try #require(socket.messages[1]["audio"] as? String))?.count == 800)
        #expect(socket.isClosed)
    }

    @Test func textOnlyTranslationHasFinalTextAndRejectsAudio() async throws {
        let socket = QwenSocketStub()
        let service = makeService(socket)
        defer { service.stop() }
        let results = QwenTestResults()
        service.onTranslation = { await results.addTranslation($0, $1) }
        service.onError = { await results.fail($0) }
        try await service.start(workspaceID: "ws-test", targetLanguage: .korean, audioOutputEnabled: false)
        socket.emit(["type": "response.text.delta", "item_id": "one", "delta": "안녕"])
        socket.emit(["type": "response.text.done", "item_id": "one", "text": "안녕하세요."])
        try await waitUntil { await results.translation.count == 2 }
        socket.emit(["type": "response.audio.delta", "delta": "AAA="])
        try await waitUntil { await !results.failures.isEmpty }
        #expect(await results.failures == [.invalidResponse])
        #expect(await results.translation.last?.value == "안녕하세요.")
    }

    @Test func missingCredentialsTimeoutsAndCancellationCloseConnections() async throws {
        let missing = QwenRealtimeTranslationService(keyProvider: { nil })
        await #expect(throws: QwenTranslationError.missingKey) {
            try await missing.start(workspaceID: "ws-test", targetLanguage: .korean, audioOutputEnabled: false)
        }
        let waiting = QwenSocketStub(createAutomatically: false)
        let setup = makeService(waiting, timeout: .milliseconds(40))
        await #expect(throws: QwenTranslationError.setupTimeout) {
            try await setup.start(workspaceID: "ws-test", targetLanguage: .korean, audioOutputEnabled: false)
        }
        #expect(waiting.isClosed)
        let draining = QwenSocketStub(finishAutomatically: false)
        let finish = makeService(draining, timeout: .milliseconds(40))
        try await finish.start(workspaceID: "ws-test", targetLanguage: .korean, audioOutputEnabled: false)
        await #expect(throws: QwenTranslationError.finishTimeout) { try await finish.finish() }
        #expect(draining.isClosed)
        let pending = QwenSocketStub(createAutomatically: false)
        let cancelled = makeService(pending)
        let task = Task { try await cancelled.start(workspaceID: "ws-test", targetLanguage: .korean, audioOutputEnabled: false) }
        try await waitUntil { pending.isResumed }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(pending.isClosed)
    }

    @Test func queueAndAudioFormatFailuresAreBounded() async throws {
        let blocked = QwenSocketStub(blockAudio: true)
        let service = makeService(blocked)
        defer { service.stop() }
        let results = QwenTestResults()
        service.onError = { await results.fail($0) }
        try await service.start(workspaceID: "ws-test", targetLanguage: .korean, audioOutputEnabled: false)
        let sample = try makeSample(frames: 1_600)
        for _ in 0..<55 { service.append(sample) }
        try await waitUntil { await !results.failures.isEmpty }
        #expect(await results.failures == [.backlog])
        #expect(blocked.isClosed)
        let bad = QwenSocketStub()
        let badService = makeService(bad)
        defer { badService.stop() }
        badService.onError = { await results.fail($0) }
        try await badService.start(workspaceID: "ws-test", targetLanguage: .korean, audioOutputEnabled: false)
        badService.append(try makeSample(frames: 100, sampleRate: 24_000))
        try await waitUntil { await results.failures.count == 2 }
        #expect(await results.failures.last == .audioFormat)
    }

    @Test func parserRejectsMalformedAudioWrongModelAndPrivateErrorPayloads() throws {
        for delta in ["!invalid", "AA==", ""] {
            #expect(throws: QwenTranslationError.invalidResponse) {
                try parse(["type": "response.audio.delta", "delta": delta])
            }
        }
        var json = QwenSocketStub.sessionEvent("session.created")
        var session = json["session"] as! [String: Any]
        session["model"] = "qwen3.5-livetranslate-flash-realtime"
        json["session"] = session
        #expect(throws: QwenTranslationError.invalidResponse) { try parse(json) }
        #expect(throws: QwenTranslationError.invalidResponse) {
            try QwenServerEvent.parse(Data(repeating: 32, count: QwenRealtimeTranslationService.maximumMessageBytes + 1))
        }
        let event = try parse(["type": "error", "error": ["message": "private-user-text Bearer private-key"]])
        guard case .failure = event else { Issue.record("sanitized failure required"); return }
        #expect(!QwenTranslationError.serviceUnavailable.localizedDescription.contains("private"))
    }

    @Test func unfinishedCaptionCannotBeReportedAsSuccessfulFinish() async throws {
        let socket = QwenSocketStub(finishAutomatically: false)
        let service = makeService(socket)
        defer { service.stop() }
        try await service.start(workspaceID: "ws-test", targetLanguage: .korean, audioOutputEnabled: false)
        socket.emit(["type": "response.text.delta", "item_id": "one", "delta": "partial"])
        let finish = Task { try await service.finish() }
        try await waitUntil { socket.messageTypes.contains("session.finish") }
        socket.emit(["type": "session.finished"])
        await #expect(throws: QwenTranslationError.invalidResponse) { try await finish.value }
    }

    @Test func restartedSessionRejectsLateEventsAndAllowsRepeatedItemIDs() async throws {
        let old = QwenSocketStub(allowLateReceiveAfterClose: true)
        let fresh = QwenSocketStub()
        let pool = QwenSocketPool([old, fresh])
        let service = QwenRealtimeTranslationService(keyProvider: { "test-only" }, connectionFactory: { _ in pool.next() })
        defer { service.stop() }
        let results = QwenTestResults()
        service.onTranslation = { await results.addTranslation($0, $1) }
        try await service.start(workspaceID: "ws-test", targetLanguage: .korean, audioOutputEnabled: false)
        old.emit(["type": "response.text.done", "item_id": "same", "text": "first"])
        try await waitUntil { await results.translation.count == 1 }
        service.stop()
        try await service.start(workspaceID: "ws-test", targetLanguage: .korean, audioOutputEnabled: false)
        old.emit(["type": "response.text.done", "item_id": "late", "text": "stale"])
        fresh.emit(["type": "response.text.done", "item_id": "same", "text": "new"])
        try await waitUntil { await results.translation.count == 2 }
        #expect(await results.translation.map(\.value) == ["first", "new"])
    }

    private func makeService(_ socket: QwenSocketStub, timeout: Duration = .seconds(2)) -> QwenRealtimeTranslationService {
        QwenRealtimeTranslationService(keyProvider: { "test-only" }, connectionFactory: { _ in socket }, setupTimeout: timeout, finishTimeout: timeout)
    }
    private func parse(_ json: [String: Any]) throws -> QwenServerEvent {
        try QwenServerEvent.parse(JSONSerialization.data(withJSONObject: json))
    }
    private func waitUntil(_ predicate: () async throws -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while try await !predicate() {
            if ContinuousClock.now > deadline { throw QwenTranslationError.finishTimeout }
            try await Task.sleep(for: .milliseconds(5))
        }
    }
    private func makeSample(frames: Int, sampleRate: Double = 16_000) throws -> CMSampleBuffer {
        var description = AudioStreamBasicDescription(mSampleRate: sampleRate, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 2, mFramesPerPacket: 1, mBytesPerFrame: 2, mChannelsPerFrame: 1, mBitsPerChannel: 16, mReserved: 0)
        var format: CMAudioFormatDescription?
        #expect(CMAudioFormatDescriptionCreate(allocator: kCFAllocatorDefault, asbd: &description, layoutSize: 0, layout: nil,
            magicCookieSize: 0, magicCookie: nil, extensions: nil, formatDescriptionOut: &format) == noErr)
        var block: CMBlockBuffer?
        #expect(CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: frames * 2,
            blockAllocator: kCFAllocatorDefault, customBlockSource: nil, offsetToData: 0, dataLength: frames * 2,
            flags: kCMBlockBufferAssureMemoryNowFlag, blockBufferOut: &block) == noErr)
        let audioBlock = try #require(block)
        #expect(CMBlockBufferFillDataBytes(with: 0, blockBuffer: audioBlock, offsetIntoDestination: 0, dataLength: frames * 2) == noErr)
        var sample: CMSampleBuffer?
        #expect(CMAudioSampleBufferCreateReadyWithPacketDescriptions(allocator: kCFAllocatorDefault, dataBuffer: audioBlock,
            formatDescription: try #require(format), sampleCount: frames, presentationTimeStamp: .zero,
            packetDescriptions: nil, sampleBufferOut: &sample) == noErr)
        return try #require(sample)
    }
}

private final class QwenSocketPool: @unchecked Sendable {
    private let lock = NSLock()
    private var sockets: [QwenSocketStub]
    init(_ sockets: [QwenSocketStub]) { self.sockets = sockets }
    func next() -> QwenSocketStub { lock.withLock { sockets.removeFirst() } }
}
