import Foundation

actor OpenAITranslationService {
    private let endpoint = URL(string: "https://api.openai.com/v1/responses")!

    private static let maximumRetryAfterDelay: TimeInterval = 10
    private static let retryJitterRange: ClosedRange<TimeInterval> = 0.5...1.5
    private static let streamProgressPublishInterval: Duration = .milliseconds(80)
    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 30
        configuration.waitsForConnectivity = false
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        return URLSession(
            configuration: configuration,
            delegate: OpenAITranslationRejectRedirects(),
            delegateQueue: nil
        )
    }()

    private enum StreamAttemptResult {
        case completed(String)
        case fallback(allowRetry: Bool)
    }

    private final class StreamProgressCoalescer: @unchecked Sendable {
        private let lock = NSLock()
        private let handler: @MainActor @Sendable (String) -> Void
        private var latestText: String?
        private var isScheduled = false
        private var stopped = false

        init(_ handler: @escaping @MainActor @Sendable (String) -> Void) {
            self.handler = handler
        }

        func publish(_ text: String) {
            let shouldSchedule = lock.withLock {
                guard !stopped else { return false }
                latestText = text
                if isScheduled { return false }
                isScheduled = true
                return true
            }
            guard shouldSchedule else { return }
            Task { @MainActor [weak self] in
                self?.drainOnMainActor()
            }
        }

        func stop() {
            lock.withLock {
                stopped = true
                latestText = nil
            }
        }

        @MainActor
        private func drainOnMainActor() {
            while true {
                let next: String? = lock.withLock {
                    guard !stopped, let text = latestText else {
                        isScheduled = false
                        return nil
                    }
                    latestText = nil
                    return text
                }
                guard let next else { return }
                handler(next)
            }
        }
    }

    func translate(
        _ text: String,
        source: LanguageOption,
        target: LanguageOption,
        model selectedModel: OpenAIRealtimeTranslationModel,
        progress: (@MainActor @Sendable (String) -> Void)? = nil
    ) async throws -> String {
        guard !text.isEmpty else { return text }
        guard selectedModel.isEnabled else { return text }
        guard let apiKey = try OpenAIAPIKeyStore.readAPIKey(), !apiKey.isEmpty else {
            throw OpenAITranslationError.missingAPIKey
        }

        var allowFallbackRetry = true
        if let progress {
            let streamingRequest = try makeRequest(
                apiKey: apiKey,
                text: text,
                source: source,
                target: target,
                model: selectedModel,
                streaming: true
            )
            switch try await streamTranslation(streamingRequest, progress: progress) {
            case let .completed(streamedText):
                return streamedText.trimmingCharacters(in: .whitespacesAndNewlines)
            case let .fallback(allowRetry):
                allowFallbackRetry = allowRetry
            }
        }

        let request = try makeRequest(
            apiKey: apiKey,
            text: text,
            source: source,
            target: target,
            model: selectedModel,
            streaming: false
        )
        let (data, httpResponse) = try await send(request, allowRetry: allowFallbackRetry)
        guard (200..<300).contains(httpResponse.statusCode) else {
            let errorResponse = try? Self.decoder.decode(OpenAIErrorResponse.self, from: data)
            throw OpenAITranslationError.requestFailed(
                statusCode: httpResponse.statusCode,
                message: errorResponse?.error.message
            )
        }

        let responseBody = try Self.decoder.decode(OpenAIResponseBody.self, from: data)
        guard let outputText = responseBody.firstOutputText else {
            throw OpenAITranslationError.emptyOutput
        }
        return outputText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func makeRequest(
        apiKey: String,
        text: String,
        source: LanguageOption,
        target: LanguageOption,
        model: OpenAIRealtimeTranslationModel,
        streaming: Bool
    ) throws -> URLRequest {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try Self.encoder.encode(
            OpenAIResponseRequest(
                model: model.apiModelID,
                instructions: AppText.openAITranslationInstructions(
                    source: source.localizedTitle,
                    target: target.localizedTitle
                ),
                input: text,
                store: false,
                stream: streaming ? true : nil
            )
        )
        return request
    }

    // Returns fallback whenever the streaming attempt cannot produce usable text, so the
    // caller falls back to the non-streaming request (which owns error reporting).
    private func streamTranslation(
        _ request: URLRequest,
        progress: @escaping @MainActor @Sendable (String) -> Void
    ) async throws -> StreamAttemptResult {
        let bytes: URLSession.AsyncBytes
        let response: URLResponse
        do {
            (bytes, response) = try await Self.session.bytes(for: request)
        } catch {
            if error is CancellationError || Task.isCancelled { throw CancellationError() }
            return .fallback(allowRetry: true)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            return .fallback(allowRetry: true)
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            if Self.isRetryableStatusCode(httpResponse.statusCode) {
                let delay = Self.retryDelay(retryAfterHeader: httpResponse.value(forHTTPHeaderField: "Retry-After"))
                try await Task.sleep(for: .seconds(delay))
                return .fallback(allowRetry: false)
            }
            return .fallback(allowRetry: true)
        }

        var parser = OpenAITranslationStreamParser()
        var lastProgressPublishAt: ContinuousClock.Instant?
        let coalescer = StreamProgressCoalescer(progress)
        defer { coalescer.stop() }

        do {
            for try await line in bytes.lines {
                try Task.checkCancellation()
                guard let partialText = parser.consume(line: line) else {
                    if parser.didEncounterFailureEvent { return .fallback(allowRetry: true) }
                    continue
                }

                let now = ContinuousClock.now
                let trimmedPartialText = partialText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmedPartialText.isEmpty,
                      lastProgressPublishAt.map({ now - $0 >= Self.streamProgressPublishInterval }) ?? true
                else { continue }
                lastProgressPublishAt = now
                coalescer.publish(trimmedPartialText)
            }
        } catch {
            if error is CancellationError || Task.isCancelled { throw CancellationError() }
            return .fallback(allowRetry: true)
        }

        guard let finalText = parser.finalText else {
            return .fallback(allowRetry: true)
        }
        return .completed(finalText)
    }

    private func send(_ request: URLRequest, allowRetry: Bool) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await Self.session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAITranslationError.invalidResponse
        }
        guard allowRetry, Self.isRetryableStatusCode(httpResponse.statusCode) else {
            return (data, httpResponse)
        }

        let delay = Self.retryDelay(retryAfterHeader: httpResponse.value(forHTTPHeaderField: "Retry-After"))
        try await Task.sleep(for: .seconds(delay))

        let (retriedData, retriedResponse) = try await Self.session.data(for: request)
        guard let retriedHTTPResponse = retriedResponse as? HTTPURLResponse else {
            throw OpenAITranslationError.invalidResponse
        }
        return (retriedData, retriedHTTPResponse)
    }

    static func isRetryableStatusCode(_ statusCode: Int) -> Bool {
        statusCode == 429 || (500...599).contains(statusCode)
    }

    static func retryDelay(retryAfterHeader: String?) -> TimeInterval {
        if let retryAfterHeader,
           let seconds = TimeInterval(retryAfterHeader.trimmingCharacters(in: .whitespaces)),
           seconds >= 0 {
            return min(seconds, maximumRetryAfterDelay)
        }
        return TimeInterval.random(in: retryJitterRange)
    }
}

private struct OpenAIResponseRequest: Encodable {
    let model: String
    let instructions: String
    let input: String
    let store: Bool
    let stream: Bool?
}

private struct OpenAIResponseBody: Decodable {
    let outputText: String?
    let output: [OpenAIOutputItem]?

    var firstOutputText: String? {
        if let outputText, !outputText.isEmpty {
            return outputText
        }

        return output?
            .flatMap(\.content)
            .compactMap(\.text)
            .first { !$0.isEmpty }
    }

    private enum CodingKeys: String, CodingKey {
        case outputText = "output_text"
        case output
    }
}

private struct OpenAIOutputItem: Decodable {
    let content: [OpenAIContentItem]
}

private struct OpenAIContentItem: Decodable {
    let text: String?
}

struct OpenAITranslationStreamParser {
    private(set) var didEncounterFailureEvent = false
    private var accumulatedDeltaText = ""
    private var doneText: String?
    private var completedText: String?
    private static let decoder = JSONDecoder()

    init() {}

    // Returns the accumulated output text whenever the line carried a new text delta.
    mutating func consume(line: String) -> String? {
        guard line.hasPrefix("data:") else { return nil }
        let payload = line.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
        guard !payload.isEmpty,
              let payloadData = payload.data(using: .utf8),
              let event = try? Self.decoder.decode(OpenAIStreamEvent.self, from: payloadData)
        else { return nil }

        switch event.type {
        case "response.output_text.delta":
            guard let delta = event.delta, !delta.isEmpty else { return nil }
            accumulatedDeltaText += delta
            return accumulatedDeltaText
        case "response.output_text.done":
            doneText = event.text
        case "response.completed":
            completedText = event.response?.firstOutputText
        case "response.failed", "response.incomplete", "error":
            didEncounterFailureEvent = true
        default:
            break
        }
        return nil
    }

    var finalText: String? {
        guard !didEncounterFailureEvent else { return nil }
        if let completedText, !completedText.isEmpty {
            return completedText
        }
        if let doneText, !doneText.isEmpty {
            return doneText
        }
        let trimmedDeltaText = accumulatedDeltaText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedDeltaText.isEmpty ? nil : accumulatedDeltaText
    }
}

private struct OpenAIStreamEvent: Decodable {
    let type: String
    let delta: String?
    let text: String?
    let response: OpenAIResponseBody?
}

private struct OpenAIErrorResponse: Decodable {
    let error: OpenAIErrorBody
}

private struct OpenAIErrorBody: Decodable {
    let message: String
}

enum OpenAITranslationError: LocalizedError {
    case missingAPIKey
    case invalidResponse
    case emptyOutput
    case requestFailed(statusCode: Int, message: String?)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            AppText.openAIAPIKeyMissing
        case .invalidResponse:
            AppText.openAIInvalidResponse
        case .emptyOutput:
            AppText.openAIEmptyOutput
        case let .requestFailed(statusCode, message):
            AppText.openAIRequestFailed(statusCode: statusCode, message: message)
        }
    }
}

private final class OpenAITranslationRejectRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}
