import AVFoundation
import CoreMedia
import Foundation

protocol GeminiLiveTranslationServiceDelegate: AnyObject {
    func geminiLiveTranslationService(
        _ service: GeminiLiveTranslationService,
        didReceiveInputTranscript text: String,
        languageCode: String?,
        isFinal: Bool
    )
    func geminiLiveTranslationService(
        _ service: GeminiLiveTranslationService,
        didReceiveOutputTranscript text: String,
        languageCode: String?
    )
    func geminiLiveTranslationService(
        _ service: GeminiLiveTranslationService,
        didOutputAudioPCM16Base64 audio: String,
        sampleRate: Double
    )
    func geminiLiveTranslationServiceDidInterruptOutputAudio(_ service: GeminiLiveTranslationService)
    func geminiLiveTranslationService(_ service: GeminiLiveTranslationService, didFail error: Error)
}

final class GeminiLiveTranslationService: @unchecked Sendable {
    private static let inputAudioSampleRate = 16_000
    private static let outputAudioSampleRate = 24_000.0
    private static let maxAudioChunkMilliseconds = 40
    private static let bytesPerPCM16Sample = 2
    private static let maxPCM16AudioChunkByteCount = inputAudioSampleRate
        * bytesPerPCM16Sample
        * maxAudioChunkMilliseconds
        / 1_000
    private static let maxPendingAudioSendCount = 48
    private static let connectionTimeoutMilliseconds = 10_000
    private static let maxPreSetupAudioSeconds = 3
    static let maxPreSetupAudioByteCount = inputAudioSampleRate
        * bytesPerPCM16Sample
        * maxPreSetupAudioSeconds
    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    private enum PreSetupAudioItem {
        case pcm(Data)
        case base64(String, byteCount: Int)

        var byteCount: Int {
            switch self {
            case let .pcm(data): data.count
            case let .base64(_, byteCount): byteCount
            }
        }

        var base64String: String {
            switch self {
            case let .pcm(data): data.base64EncodedString()
            case let .base64(value, _): value
            }
        }
    }

    var delegate: GeminiLiveTranslationServiceDelegate? {
        get {
            withStateLock { serviceDelegate }
        }
        set {
            withStateLock {
                serviceDelegate = newValue
            }
        }
    }
    /// Store integration can observe loss metrics without making the translation delegate requirement mandatory.
    /// The callback runs after the state lock is released and never contains audio, URLs, or provider diagnostics.
    var onAudioTransportDegraded: (@Sendable (RealtimeAudioTransportDegradation) -> Void)? {
        get {
            stateLock.lock()
            defer { stateLock.unlock() }
            return audioTransportDegradationHandler
        }
        set {
            stateLock.lock()
            audioTransportDegradationHandler = newValue
            stateLock.unlock()
        }
    }
    /// Called when Gemini announces that the current socket will close soon.
    /// The callback receives the newest resumable session handle, when available.
    var onSessionReconnectRecommended: (@Sendable (String?) -> Void)? {
        get {
            withStateLock { sessionReconnectRecommendationHandler }
        }
        set {
            withStateLock {
                sessionReconnectRecommendationHandler = newValue
            }
        }
    }

    private let stateLock = NSLock()
    private let conversionLock = NSLock()
    private let sendQueue = DispatchQueue(label: "AirTranslate.GeminiLiveTranslationService.send", qos: .userInitiated)
    private let setupWaiters = LockConditionWaiters()
    private weak var serviceDelegate: GeminiLiveTranslationServiceDelegate?
    private var urlSession: URLSession?
    private var webSocketTask: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var connectionGeneration: UInt64 = 0
    private var isPaused = false
    private var isSetupComplete = false
    private var setupError: Error?
    private var pendingAudioSendCount = 0
    private var droppedAudioChunkCount = 0
    private var droppedAudioByteCount = 0
    private var lastAudioDropPhase = RealtimeAudioDropPhase.sendWindow
    private var audioTransportDegradationHandler:
        (@Sendable (RealtimeAudioTransportDegradation) -> Void)?
    private var sessionReconnectRecommendationHandler: (@Sendable (String?) -> Void)?
    private var sessionResumptionHandle: String?
    private var preSetupAudioItems: [PreSetupAudioItem] = []
    private var preSetupAudioByteCount = 0

    func start(
        targetLanguage: LanguageOption,
        model: GeminiTranslationModel,
        resumptionHandle: String? = nil
    ) async throws {
        stop()

        guard model.isEnabled else { return }
        guard let apiKey = try GeminiAPIKeyStore.readAPIKey(), !apiKey.isEmpty else {
            throw GeminiLiveTranslationError.missingAPIKey
        }
        guard var components = URLComponents(
            string: "wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent"
        ) else {
            throw GeminiLiveTranslationError.invalidResponse
        }
        components.queryItems = [URLQueryItem(name: "key", value: apiKey)]
        guard let url = components.url else {
            throw GeminiLiveTranslationError.invalidResponse
        }

        let connectionObserver = GeminiLiveWebSocketConnectionObserver()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        let urlSession = URLSession(configuration: configuration, delegate: connectionObserver, delegateQueue: nil)
        let webSocketTask = urlSession.webSocketTask(with: url)
        let installation: (
            generation: UInt64,
            receiveTask: Task<Void, Never>?,
            webSocketTask: URLSessionWebSocketTask?,
            urlSession: URLSession?
        ) = withStateLock {
            let displacedReceiveTask = self.receiveTask
            let displacedWebSocketTask = self.webSocketTask
            let displacedURLSession = self.urlSession
            connectionGeneration &+= 1
            self.urlSession = urlSession
            self.webSocketTask = webSocketTask
            self.receiveTask = nil
            isPaused = false
            isSetupComplete = false
            setupError = nil
            pendingAudioSendCount = 0
            droppedAudioChunkCount = 0
            droppedAudioByteCount = 0
            lastAudioDropPhase = .sendWindow
            preSetupAudioItems = []
            preSetupAudioByteCount = 0
            return (
                generation: connectionGeneration,
                receiveTask: displacedReceiveTask,
                webSocketTask: displacedWebSocketTask,
                urlSession: displacedURLSession
            )
        }
        installation.receiveTask?.cancel()
        installation.webSocketTask?.cancel(
            with: URLSessionWebSocketTask.CloseCode.goingAway,
            reason: Data?.none
        )
        installation.urlSession?.finishTasksAndInvalidate()
        let generation = installation.generation
        webSocketTask.resume()

        do {
            try await connectionObserver.waitForOpen(timeoutMilliseconds: Self.connectionTimeoutMilliseconds)
        } catch {
            guard isCurrentConnection(generation, webSocketTask: webSocketTask) else {
                throw CancellationError()
            }
            throw Self.publicConnectionError(from: error)
        }
        guard isCurrentConnection(generation, webSocketTask: webSocketTask) else {
            throw CancellationError()
        }
        let receiveTask = Task<Void, Never> { [weak self] in
            guard let self else { return }
            await self.receiveLoop(
                webSocketTask: webSocketTask,
                connectionGeneration: generation
            )
        }
        let installedReceiveTask = withStateLock {
            guard isCurrentConnectionLocked(generation, webSocketTask: webSocketTask) else {
                return false
            }
            self.receiveTask = receiveTask
            return true
        }
        guard installedReceiveTask else {
            receiveTask.cancel()
            throw CancellationError()
        }
        try await sendSetupMessage(
            model: model,
            targetLanguage: targetLanguage,
            resumptionHandle: resumptionHandle,
            connectionGeneration: generation
        )
        try await waitForSetupComplete(connectionGeneration: generation)
    }

    func append(_ sampleBuffer: CMSampleBuffer) {
        let state = withStateLock {
            (
                isPaused: isPaused,
                hasActiveWebSocketTask: webSocketTask != nil,
                connectionGeneration: connectionGeneration
            )
        }

        guard !state.isPaused, state.hasActiveWebSocketTask else { return }

        conversionLock.lock()
        let pcmChunks = pcm16AudioDataChunks(from: sampleBuffer)
        conversionLock.unlock()
        guard !pcmChunks.isEmpty else { return }

        let items = pcmChunks.map { PreSetupAudioItem.pcm($0) }
        sendOrBufferAudioItems(items, connectionGeneration: state.connectionGeneration)
    }

    func sendOrBufferAudioChunks(_ audioChunks: [String]) {
        let items = audioChunks.map { PreSetupAudioItem.base64($0, byteCount: Self.decodedAudioByteCount($0)) }
        sendOrBufferAudioItems(items, connectionGeneration: nil)
    }

    private func sendOrBufferAudioItems(
        _ items: [PreSetupAudioItem],
        connectionGeneration expectedGeneration: UInt64?
    ) {
        guard !items.isEmpty else { return }

        stateLock.lock()
        if let expectedGeneration,
           !isCurrentConnectionLocked(expectedGeneration) {
            stateLock.unlock()
            return
        }
        guard isSetupComplete else {
            let degradation = bufferPreSetupAudioItemsLocked(items)
            let callback = audioTransportDegradationHandler
            stateLock.unlock()
            if let degradation {
                callback?(degradation)
            }
            return
        }
        guard let webSocketTask else {
            stateLock.unlock()
            return
        }
        let connectionGeneration = self.connectionGeneration
        let encodedPayloads = items.map { (base64: $0.base64String, byteCount: $0.byteCount) }
        sendQueue.async { [weak self] in
            self?.sendAudioPayloads(encodedPayloads, over: webSocketTask, connectionGeneration: connectionGeneration)
        }
        stateLock.unlock()
    }

    private func sendAudioPayloads(
        _ payloads: [(base64: String, byteCount: Int)],
        over webSocketTask: URLSessionWebSocketTask,
        connectionGeneration: UInt64
    ) {
        for payload in payloads {
            let text = "{\"realtimeInput\":{\"audio\":{\"data\":\"\(payload.base64)\",\"mimeType\":\"audio/pcm;rate=16000\"}}}"
            guard reserveAudioSendSlot(
                audioByteCount: payload.byteCount,
                connectionGeneration: connectionGeneration
            ) else {
                continue
            }

            webSocketTask.send(.string(text)) { [weak self] error in
                self?.releaseAudioSendSlot(connectionGeneration: connectionGeneration)
                guard let error, let self else { return }
                self.notifyDelegate(connectionGeneration: connectionGeneration) {
                    $0.geminiLiveTranslationService(
                        self,
                        didFail: Self.publicConnectionError(from: error)
                    )
                }
            }
        }
    }

    private func bufferPreSetupAudioItemsLocked(
        _ items: [PreSetupAudioItem]
    ) -> RealtimeAudioTransportDegradation? {
        var droppedChunkInThisCall = false
        for item in items {
            preSetupAudioItems.append(item)
            preSetupAudioByteCount += item.byteCount
        }
        while preSetupAudioByteCount > Self.maxPreSetupAudioByteCount, !preSetupAudioItems.isEmpty {
            let removed = preSetupAudioItems.removeFirst()
            let removedByteCount = removed.byteCount
            preSetupAudioByteCount = max(0, preSetupAudioByteCount - removedByteCount)
            droppedAudioChunkCount += 1
            droppedAudioByteCount += removedByteCount
            lastAudioDropPhase = .preSetupBuffer
            droppedChunkInThisCall = true
        }
        return droppedChunkInThisCall ? audioTransportDegradationLocked(phase: .preSetupBuffer) : nil
    }

    private static func decodedAudioByteCount(_ base64: String) -> Int {
        Data(base64Encoded: base64)?.count ?? (base64.utf8.count / 4 * 3)
    }

    var bufferedPreSetupAudioChunks: [String] {
        withStateLock { preSetupAudioItems.map(\.base64String) }
    }

    func setPaused(_ isPaused: Bool) {
        stateLock.lock()
        self.isPaused = isPaused
        stateLock.unlock()
    }

    func stop() {
        stateLock.lock()
        connectionGeneration &+= 1
        let receiveTask = receiveTask
        let webSocketTask = webSocketTask
        let urlSession = urlSession
        self.receiveTask = nil
        self.webSocketTask = nil
        self.urlSession = nil
        isPaused = false
        isSetupComplete = false
        setupError = nil
        pendingAudioSendCount = 0
        droppedAudioChunkCount = 0
        droppedAudioByteCount = 0
        lastAudioDropPhase = .sendWindow
        sessionResumptionHandle = nil
        preSetupAudioItems = []
        preSetupAudioByteCount = 0
        let waiters = setupWaiters.takeAllLocked()
        stateLock.unlock()
        LockConditionWaiters.resume(waiters)
        receiveTask?.cancel()
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        urlSession?.finishTasksAndInvalidate()
    }

    private func sendSetupMessage(
        model: GeminiTranslationModel,
        targetLanguage: LanguageOption,
        resumptionHandle: String?,
        connectionGeneration: UInt64
    ) async throws {
        let data = try Self.encodedSetupMessage(
            model: model,
            targetLanguage: targetLanguage,
            resumptionHandle: resumptionHandle
        )
        guard let text = String(data: data, encoding: .utf8) else {
            throw GeminiLiveTranslationError.invalidResponse
        }
        try await send(text, connectionGeneration: connectionGeneration)
    }

    nonisolated static func encodedSetupMessage(
        model: GeminiTranslationModel,
        targetLanguage: LanguageOption,
        resumptionHandle: String? = nil
    ) throws -> Data {
        let isTranscription = model.isTranscription
        let event = GeminiLiveSetupMessage(
            setup: GeminiLiveSetup(
                model: "models/\(model.apiModelID)",
                generationConfig: GeminiLiveGenerationConfig(
                    responseModalities: [isTranscription ? "TEXT" : "AUDIO"],
                    translationConfig: isTranscription
                        ? nil
                        : GeminiLiveTranslationConfig(
                            targetLanguageCode: targetLanguage.geminiLiveLanguageCode,
                            echoTargetLanguage: true
                        )
                ),
                realtimeInputConfig: isTranscription
                    ? nil
                    : GeminiLiveRealtimeInputConfig(
                        automaticActivityDetection: GeminiLiveActivityDetection(
                            startOfSpeechSensitivity: "START_SENSITIVITY_HIGH",
                            endOfSpeechSensitivity: "END_SENSITIVITY_HIGH",
                            silenceDurationMs: 250,
                            prefixPaddingMs: 120
                        )
                    ),
                inputAudioTranscription: GeminiLiveAudioTranscriptionConfig(
                    languageCodes: isTranscription ? [] : nil,
                    mode: isTranscription ? "SMART" : nil
                ),
                outputAudioTranscription: isTranscription ? nil : GeminiLiveEmptyObject(),
                sessionResumption: GeminiLiveSessionResumptionConfig(
                    handle: resumptionHandle
                ),
                contextWindowCompression: GeminiLiveContextWindowCompressionConfig(
                    triggerTokens: 25_000,
                    slidingWindow: GeminiLiveSlidingWindow(targetTokens: 8_000)
                )
            )
        )
        return try Self.encoder.encode(event)
    }

    private func waitForSetupComplete(connectionGeneration: UInt64) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        try await setupWaiters.wait(
            lock: stateLock,
            deadline: deadline,
            timeoutError: GeminiLiveTranslationError.setupTimedOut
        ) {
            guard isCurrentConnectionLocked(connectionGeneration) else { throw CancellationError() }
            if let setupError { throw setupError }
            return isSetupComplete
        }
    }

    private func send(_ text: String, connectionGeneration: UInt64) async throws {
        var retryCount = 0
        while true {
            do {
                try await sendOnce(text, connectionGeneration: connectionGeneration)
                return
            } catch {
                guard retryCount < 40, Self.isSocketNotConnectedError(error) else {
                    throw Self.publicConnectionError(from: error)
                }

                retryCount += 1
                try await Task.sleep(for: .milliseconds(min(100 + (retryCount * 50), 500)))
            }
        }
    }

    private func sendOnce(_ text: String, connectionGeneration: UInt64) async throws {
        let webSocketTask: URLSessionWebSocketTask? = withStateLock {
            guard isCurrentConnectionLocked(connectionGeneration) else { return nil }
            return self.webSocketTask
        }
        guard let webSocketTask else { throw CancellationError() }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            webSocketTask.send(.string(text)) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    nonisolated static func isSocketNotConnectedError(_ error: Error) -> Bool {
        var nsError = error as NSError
        while true {
            if nsError.domain == NSPOSIXErrorDomain, nsError.code == Int(ENOTCONN) {
                return true
            }
            if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorNetworkConnectionLost {
                return true
            }
            guard let underlyingError = nsError.userInfo[NSUnderlyingErrorKey] as? NSError else {
                return false
            }
            nsError = underlyingError
        }
    }

    nonisolated static func publicConnectionError(from error: Error) -> Error {
        if error is CancellationError {
            return error
        }
        if error is GeminiLiveTranslationError {
            return error
        }
        return GeminiLiveTranslationError.connectionFailed
    }

    private func withStateLock<T>(_ body: () throws -> T) rethrows -> T {
        stateLock.lock()
        defer { stateLock.unlock() }
        return try body()
    }

    private func isCurrentConnection(
        _ generation: UInt64,
        webSocketTask expectedWebSocketTask: URLSessionWebSocketTask? = nil
    ) -> Bool {
        withStateLock {
            isCurrentConnectionLocked(
                generation,
                webSocketTask: expectedWebSocketTask
            )
        }
    }

    private func isCurrentConnectionLocked(
        _ generation: UInt64,
        webSocketTask expectedWebSocketTask: URLSessionWebSocketTask? = nil
    ) -> Bool {
        guard isCurrentGenerationLocked(generation),
              let webSocketTask
        else {
            return false
        }
        guard let expectedWebSocketTask else { return true }
        return webSocketTask === expectedWebSocketTask
    }

    private func isCurrentGenerationLocked(_ generation: UInt64) -> Bool {
        connectionGeneration == generation
    }

    private func notifyDelegate(
        connectionGeneration expectedGeneration: UInt64?,
        _ notification: (GeminiLiveTranslationServiceDelegate) -> Void
    ) {
        let delegate: GeminiLiveTranslationServiceDelegate? = withStateLock {
            if let expectedGeneration,
               !isCurrentGenerationLocked(expectedGeneration) {
                return nil
            }
            return serviceDelegate
        }
        if let delegate {
            notification(delegate)
        }
    }

    private func receiveLoop(
        webSocketTask: URLSessionWebSocketTask,
        connectionGeneration: UInt64
    ) async {
        while !Task.isCancelled {
            guard isCurrentConnection(
                connectionGeneration,
                webSocketTask: webSocketTask
            ) else {
                return
            }
            do {
                let message = try await webSocketTask.receive()
                guard isCurrentConnection(
                    connectionGeneration,
                    webSocketTask: webSocketTask
                ) else {
                    return
                }
                switch message {
                case let .string(text):
                    handleEventText(text, connectionGeneration: connectionGeneration)
                case let .data(data):
                    guard let text = String(data: data, encoding: .utf8) else { continue }
                    handleEventText(text, connectionGeneration: connectionGeneration)
                @unknown default:
                    continue
                }
            } catch {
                guard !Task.isCancelled,
                      isCurrentConnection(
                        connectionGeneration,
                        webSocketTask: webSocketTask
                      )
                else {
                    return
                }
                let publicError = Self.publicConnectionError(from: error)
                recordSetupFailureIfNeeded(
                    publicError,
                    connectionGeneration: connectionGeneration
                )
                notifyDelegate(connectionGeneration: connectionGeneration) {
                    $0.geminiLiveTranslationService(self, didFail: publicError)
                }
                return
            }
        }
    }

    func handleEventText(_ text: String) {
        handleEventText(text, connectionGeneration: nil)
    }

    func handleEventText(_ text: String, connectionGeneration: UInt64) {
        handleEventText(text, connectionGeneration: Optional(connectionGeneration))
    }

    private func handleEventText(
        _ text: String,
        connectionGeneration: UInt64?
    ) {
        if let connectionGeneration,
           !withStateLock({ isCurrentGenerationLocked(connectionGeneration) }) {
            return
        }
        guard let data = text.data(using: .utf8),
              let event = try? Self.decoder.decode(GeminiLiveServerMessage.self, from: data)
        else { return }

        if event.error != nil {
            let serviceError = GeminiLiveTranslationError.server
            recordSetupFailureIfNeeded(
                serviceError,
                connectionGeneration: connectionGeneration
            )
            notifyDelegate(connectionGeneration: connectionGeneration) {
                $0.geminiLiveTranslationService(
                    self,
                    didFail: serviceError
                )
            }
            return
        }

        if let update = event.sessionResumptionUpdate {
            withStateLock {
                if update.resumable == true,
                   let newHandle = update.newHandle,
                   !newHandle.isEmpty {
                    sessionResumptionHandle = newHandle
                } else if update.resumable == false {
                    sessionResumptionHandle = nil
                }
            }
        }

        if event.goAway != nil {
            let reconnectState = withStateLock {
                (
                    handler: sessionReconnectRecommendationHandler,
                    handle: sessionResumptionHandle
                )
            }
            reconnectState.handler?(reconnectState.handle)
        }

        if event.setupComplete != nil {
            markSetupComplete(connectionGeneration: connectionGeneration)
            return
        }

        guard let content = event.serverContent else { return }
        if content.interrupted == true {
            notifyDelegate(connectionGeneration: connectionGeneration) {
                $0.geminiLiveTranslationServiceDidInterruptOutputAudio(self)
            }
        }
        if let interimTranscript = content.interimInputTranscription?.text,
           !interimTranscript.isEmpty {
            notifyDelegate(connectionGeneration: connectionGeneration) {
                $0.geminiLiveTranslationService(
                    self,
                    didReceiveInputTranscript: interimTranscript,
                    languageCode: content.interimInputTranscription?.languageCode,
                    isFinal: false
                )
            }
        }
        if let inputTranscript = content.inputTranscription?.text,
           !inputTranscript.isEmpty {
            let isFinal = content.inputTranscription?.finished ?? true
            notifyDelegate(connectionGeneration: connectionGeneration) {
                $0.geminiLiveTranslationService(
                    self,
                    didReceiveInputTranscript: inputTranscript,
                    languageCode: content.inputTranscription?.languageCode,
                    isFinal: isFinal
                )
            }
        }
        if let outputTranscript = content.outputTranscription?.text,
           !outputTranscript.isEmpty {
            notifyDelegate(connectionGeneration: connectionGeneration) {
                $0.geminiLiveTranslationService(
                    self,
                    didReceiveOutputTranscript: outputTranscript,
                    languageCode: content.outputTranscription?.languageCode
                )
            }
        }
        for part in content.modelTurn?.parts ?? [] {
            guard let inlineData = part.inlineData,
                  let audioData = inlineData.data,
                  !audioData.isEmpty
            else { continue }

            notifyDelegate(connectionGeneration: connectionGeneration) {
                $0.geminiLiveTranslationService(
                    self,
                    didOutputAudioPCM16Base64: audioData,
                    sampleRate: Self.outputAudioSampleRate(from: inlineData.mimeType)
                )
            }
        }
    }

    var isReadyForRealtimeInput: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return isSetupComplete
    }

    private func markSetupComplete(connectionGeneration expectedGeneration: UInt64?) {
        stateLock.lock()
        if let expectedGeneration,
           !isCurrentGenerationLocked(expectedGeneration) {
            stateLock.unlock()
            return
        }
        let bufferedItems = preSetupAudioItems
        preSetupAudioItems = []
        preSetupAudioByteCount = 0
        isSetupComplete = true
        setupError = nil
        let waiters = setupWaiters.takeAllLocked()
        if let webSocketTask, !bufferedItems.isEmpty {
            let connectionGeneration = self.connectionGeneration
            let payloads = Self.coalescedAudioPayloads(bufferedItems)
            sendQueue.async { [weak self] in
                self?.sendAudioPayloads(payloads, over: webSocketTask, connectionGeneration: connectionGeneration)
            }
        }
        stateLock.unlock()
        LockConditionWaiters.resume(waiters)
    }

    private static func coalescedAudioPayloads(_ items: [PreSetupAudioItem]) -> [(base64: String, byteCount: Int)] {
        var audioData = Data()
        for item in items {
            switch item {
            case let .pcm(data):
                audioData.append(data)
            case let .base64(chunk, _):
                if let decoded = Data(base64Encoded: chunk) {
                    audioData.append(decoded)
                }
            }
        }
        guard !audioData.isEmpty else { return [] }
        return chunkedAudioData(audioData).map { ($0.base64EncodedString(), $0.count) }
    }

    func coalescedAudioChunks(_ chunks: [String]) -> [String] {
        var audioData = Data()
        for chunk in chunks {
            guard let decoded = Data(base64Encoded: chunk) else { continue }
            audioData.append(decoded)
        }
        guard !audioData.isEmpty else { return [] }
        return Self.chunkedAudioData(audioData).map { $0.base64EncodedString() }
    }

    private func recordSetupFailureIfNeeded(
        _ error: Error,
        connectionGeneration expectedGeneration: UInt64?
    ) {
        stateLock.lock()
        if let expectedGeneration,
           !isCurrentGenerationLocked(expectedGeneration) {
            stateLock.unlock()
            return
        }
        var waiters: [CheckedContinuation<Void, Error>] = []
        if !isSetupComplete {
            setupError = error
            waiters = setupWaiters.takeAllLocked()
        }
        stateLock.unlock()
        LockConditionWaiters.resume(waiters)
    }

    nonisolated static func outputAudioSampleRate(from mimeType: String?) -> Double {
        guard let mimeType else { return outputAudioSampleRate }

        for part in mimeType.split(separator: ";") {
            let trimmedPart = part.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmedPart.hasPrefix("rate=") else { continue }

            let value = trimmedPart.dropFirst("rate=".count)
            return Double(value) ?? outputAudioSampleRate
        }

        return outputAudioSampleRate
    }

    @discardableResult
    func reserveAudioSendSlot(audioByteCount: Int) -> Bool {
        reserveAudioSendSlot(
            audioByteCount: audioByteCount,
            connectionGeneration: nil
        )
    }

    func reserveAudioSendSlot(
        audioByteCount: Int,
        connectionGeneration expectedGeneration: UInt64?
    ) -> Bool {
        stateLock.lock()
        if let expectedGeneration,
           !isCurrentGenerationLocked(expectedGeneration) {
            stateLock.unlock()
            return false
        }
        guard pendingAudioSendCount < Self.maxPendingAudioSendCount else {
            droppedAudioChunkCount += 1
            droppedAudioByteCount += max(0, audioByteCount)
            lastAudioDropPhase = .sendWindow
            let degradation = audioTransportDegradationLocked(phase: .sendWindow)
            let callback = audioTransportDegradationHandler
            stateLock.unlock()
            callback?(degradation)
            return false
        }

        pendingAudioSendCount += 1
        stateLock.unlock()
        return true
    }

    func releaseAudioSendSlot() {
        releaseAudioSendSlot(connectionGeneration: nil)
    }

    func releaseAudioSendSlot(connectionGeneration expectedGeneration: UInt64?) {
        stateLock.lock()
        if let expectedGeneration,
           !isCurrentGenerationLocked(expectedGeneration) {
            stateLock.unlock()
            return
        }
        pendingAudioSendCount = max(0, pendingAudioSendCount - 1)
        stateLock.unlock()
    }

    var audioTransportDegradation: RealtimeAudioTransportDegradation? {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard droppedAudioChunkCount > 0 else { return nil }
        return audioTransportDegradationLocked(phase: lastAudioDropPhase)
    }

    var currentConnectionGeneration: UInt64 {
        withStateLock { connectionGeneration }
    }

    var latestSessionResumptionHandle: String? {
        withStateLock { sessionResumptionHandle }
    }

    var pendingAudioSendSlotCount: Int {
        withStateLock { pendingAudioSendCount }
    }

    private func audioTransportDegradationLocked(
        phase: RealtimeAudioDropPhase
    ) -> RealtimeAudioTransportDegradation {
        RealtimeAudioTransportDegradation(
            provider: .gemini,
            policy: phase == .preSetupBuffer ? .dropOldest : .dropNewest,
            phase: phase,
            droppedChunkCount: droppedAudioChunkCount,
            droppedAudioDuration: TimeInterval(droppedAudioByteCount)
                / TimeInterval(Self.inputAudioSampleRate * Self.bytesPerPCM16Sample),
            pendingSendCount: pendingAudioSendCount,
            pendingSendLimit: Self.maxPendingAudioSendCount
        )
    }

    private func pcm16AudioDataChunks(from sampleBuffer: CMSampleBuffer) -> [Data] {
        guard let audioData = AzureMAITranscriber.pcm16AudioData(from: sampleBuffer) else { return [] }
        return Self.chunkedAudioData(audioData)
    }

    private static func chunkedAudioData(_ audioData: Data) -> [Data] {
        guard audioData.count > maxPCM16AudioChunkByteCount else {
            return [audioData]
        }

        var chunks: [Data] = []
        chunks.reserveCapacity((audioData.count + maxPCM16AudioChunkByteCount - 1) / maxPCM16AudioChunkByteCount)
        var offset = 0
        while offset < audioData.count {
            let end = min(offset + maxPCM16AudioChunkByteCount, audioData.count)
            chunks.append(Data(audioData[offset..<end]))
            offset = end
        }
        return chunks
    }
}

final class GeminiLiveWebSocketConnectionObserver: NSObject, URLSessionWebSocketDelegate, URLSessionTaskDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Error>?
    private var completedResult: Result<Void, Error>?

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }

    func waitForOpen(timeoutMilliseconds: Int) async throws {
        let timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(timeoutMilliseconds))
            guard !Task.isCancelled else { return }
            self?.resolve(.failure(GeminiLiveTranslationError.setupTimedOut))
        }
        defer { timeoutTask.cancel() }

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                register(continuation)
            }
        } onCancel: {
            resolve(.failure(CancellationError()))
        }
    }

    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol `protocol`: String?
    ) {
        resolve(.success(()))
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        resolve(.failure(error))
    }

    func urlSession(_ session: URLSession, didBecomeInvalidWithError error: Error?) {
        resolve(.failure(error ?? GeminiLiveTranslationError.setupTimedOut))
    }

    private func register(_ continuation: CheckedContinuation<Void, Error>) {
        lock.lock()
        if let completedResult {
            lock.unlock()
            continuation.resume(with: completedResult)
            return
        }
        self.continuation = continuation
        lock.unlock()
    }

    private func resolve(_ result: Result<Void, Error>) {
        lock.lock()
        guard completedResult == nil else {
            lock.unlock()
            return
        }
        completedResult = result
        let continuation = continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(with: result)
    }
}

private struct GeminiLiveSetupMessage: Encodable {
    let setup: GeminiLiveSetup
}

private struct GeminiLiveSetup: Encodable {
    let model: String
    let generationConfig: GeminiLiveGenerationConfig
    let realtimeInputConfig: GeminiLiveRealtimeInputConfig?
    let inputAudioTranscription: GeminiLiveAudioTranscriptionConfig
    let outputAudioTranscription: GeminiLiveEmptyObject?
    let sessionResumption: GeminiLiveSessionResumptionConfig
    let contextWindowCompression: GeminiLiveContextWindowCompressionConfig
}

private struct GeminiLiveSessionResumptionConfig: Encodable {
    let handle: String?
}

private struct GeminiLiveContextWindowCompressionConfig: Encodable {
    let triggerTokens: Int
    let slidingWindow: GeminiLiveSlidingWindow
}

private struct GeminiLiveSlidingWindow: Encodable {
    let targetTokens: Int
}

private struct GeminiLiveRealtimeInputConfig: Encodable {
    let automaticActivityDetection: GeminiLiveActivityDetection
}

private struct GeminiLiveActivityDetection: Encodable {
    let startOfSpeechSensitivity: String
    let endOfSpeechSensitivity: String
    let silenceDurationMs: Int
    let prefixPaddingMs: Int
}

private struct GeminiLiveGenerationConfig: Encodable {
    let responseModalities: [String]
    let translationConfig: GeminiLiveTranslationConfig?
}

private struct GeminiLiveTranslationConfig: Encodable {
    let targetLanguageCode: String
    let echoTargetLanguage: Bool
}

private struct GeminiLiveEmptyObject: Encodable {}

private struct GeminiLiveAudioTranscriptionConfig: Encodable {
    let languageCodes: [String]?
    let mode: String?
}

private struct GeminiLiveRealtimeInputMessage: Encodable {
    let realtimeInput: GeminiLiveRealtimeInput
}

private struct GeminiLiveRealtimeInput: Encodable {
    let audio: GeminiLiveAudioBlob
}

private struct GeminiLiveAudioBlob: Encodable {
    let data: String
    let mimeType: String
}

private struct GeminiLiveServerMessage: Decodable {
    let setupComplete: GeminiLiveSetupComplete?
    let serverContent: GeminiLiveServerContent?
    let goAway: GeminiLiveGoAway?
    let sessionResumptionUpdate: GeminiLiveSessionResumptionUpdate?
    let error: GeminiLiveErrorBody?
}

private struct GeminiLiveGoAway: Decodable {
    let timeLeft: String?
}

private struct GeminiLiveSessionResumptionUpdate: Decodable {
    let newHandle: String?
    let resumable: Bool?
}

private struct GeminiLiveSetupComplete: Decodable {}

private struct GeminiLiveServerContent: Decodable {
    let interimInputTranscription: GeminiLiveTranscript?
    let inputTranscription: GeminiLiveTranscript?
    let outputTranscription: GeminiLiveTranscript?
    let modelTurn: GeminiLiveModelTurn?
    let interrupted: Bool?
}

private struct GeminiLiveTranscript: Decodable {
    let text: String?
    let languageCode: String?
    let finished: Bool?
}

private struct GeminiLiveModelTurn: Decodable {
    let parts: [GeminiLivePart]?
}

private struct GeminiLivePart: Decodable {
    let inlineData: GeminiLiveInlineData?
}

private struct GeminiLiveInlineData: Decodable {
    let data: String?
    let mimeType: String?
}

private struct GeminiLiveErrorBody: Decodable {
    let message: String?
}

enum GeminiLiveTranslationError: LocalizedError {
    case missingAPIKey
    case invalidResponse
    case setupTimedOut
    case connectionFailed
    case server

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            AppText.geminiAPIKeyMissing
        case .invalidResponse:
            AppText.geminiInvalidResponse
        case .setupTimedOut:
            AppText.geminiInvalidResponse
        case .connectionFailed:
            AppText.geminiConnectionFailed
        case .server:
            AppText.geminiInvalidResponse
        }
    }
}

private extension LanguageOption {
    var geminiLiveLanguageCode: String {
        String(id.prefix(2))
    }
}
