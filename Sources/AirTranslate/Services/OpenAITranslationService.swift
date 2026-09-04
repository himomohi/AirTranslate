import Foundation

actor OpenAITranslationService {
    private let endpoint = URL(string: "https://api.openai.com/v1/responses")!

    private static let maximumRetryAfterDelay: TimeInterval = 10
    private static let retryJitterRange: ClosedRange<TimeInterval> = 0.5...1.5
    private static let streamProgressPublishInterval: TimeInterval = 0.08

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 30
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }()

    func translate(
        _ text: String,
        source: LanguageOption,
        target: LanguageOption,
        model selectedModel: OpenAIRealtimeTranslationModel,
        qualityContext: TranslationQualityContext? = nil,
        progress: (@MainActor @Sendable (String) -> Void)? = nil
    ) async throws -> String {
        guard !text.isEmpty else { return text }
        guard selectedModel.isEnabled else { return text }
        guard let apiKey = try OpenAIAPIKeyStore.readAPIKey(), !apiKey.isEmpty else {
            throw OpenAITranslationError.missingAPIKey
        }

        if let progress {
            let streamingRequest = try makeRequest(
                apiKey: apiKey,
                text: text,
                source: source,
                target: target,
                model: selectedModel,
                qualityContext: qualityContext,
                streaming: true
            )
            if let streamedText = try await streamTranslation(streamingRequest, progress: progress) {
                return streamedText.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        let request = try makeRequest(
            apiKey: apiKey,
            text: text,
            source: source,
            target: target,
            model: selectedModel,
            qualityContext: qualityContext,
            streaming: false
        )
        let (data, httpResponse) = try await send(request)
        guard (200..<300).contains(httpResponse.statusCode) else {
            let errorResponse = try? JSONDecoder().decode(OpenAIErrorResponse.self, from: data)
            throw OpenAITranslationError.requestFailed(
                statusCode: httpResponse.statusCode,
                message: errorResponse?.error.message
            )
        }

        let responseBody = try JSONDecoder().decode(OpenAIResponseBody.self, from: data)
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
        qualityContext: TranslationQualityContext?,
        streaming: Bool
    ) throws -> URLRequest {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let baseInstructions = AppText.openAITranslationInstructions(
            source: source.localizedTitle,
            target: target.localizedTitle
        )
        let instructions = qualityContext?.enhancing(
            instructions: baseInstructions,
            target: target
        ) ?? baseInstructions
        request.httpBody = try JSONEncoder().encode(
            OpenAIResponseRequest(
                model: model.apiModelID,
                instructions: instructions,
                input: text,
                store: false,
                stream: streaming ? true : nil
            )
        )
        return request
    }

    // Returns nil whenever the streaming attempt cannot produce usable text, so the
    // caller falls back to the non-streaming request (which owns error reporting).
    private func streamTranslation(
        _ request: URLRequest,
        progress: @MainActor @Sendable (String) -> Void
    ) async throws -> String? {
        let bytes: URLSession.AsyncBytes
        let response: URLResponse
        do {
            (bytes, response) = try await Self.session.bytes(for: request)
        } catch {
            if error is CancellationError || Task.isCancelled { throw CancellationError() }
            return nil
        }

        guard let httpResponse = response as? HTTPURLResponse else { return nil }
        guard (200..<300).contains(httpResponse.statusCode) else {
            if Self.isRetryableStatusCode(httpResponse.statusCode) {
                let delay = Self.retryDelay(retryAfterHeader: httpResponse.value(forHTTPHeaderField: "Retry-After"))
                try await Task.sleep(for: .seconds(delay))
            }
            return nil
        }

        var parser = OpenAITranslationStreamParser()
        var lastProgressPublishAt = Date.distantPast

        do {
            for try await line in bytes.lines {
                guard let partialText = parser.consume(line: line) else {
                    if parser.didEncounterFailureEvent { return nil }
                    continue
                }

                let now = Date()
                let trimmedPartialText = partialText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmedPartialText.isEmpty,
                      now.timeIntervalSince(lastProgressPublishAt) >= Self.streamProgressPublishInterval
                else { continue }
                lastProgressPublishAt = now
                await progress(trimmedPartialText)
            }
        } catch {
            if error is CancellationError || Task.isCancelled { throw CancellationError() }
            return nil
        }

        return parser.finalText
    }

    private func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await Self.session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAITranslationError.invalidResponse
        }
        guard Self.isRetryableStatusCode(httpResponse.statusCode) else {
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
    private let decoder = JSONDecoder()

    init() {}

    // Returns the accumulated output text whenever the line carried a new text delta.
    mutating func consume(line: String) -> String? {
        guard line.hasPrefix("data:") else { return nil }
        let payload = line.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
        guard !payload.isEmpty,
              let payloadData = payload.data(using: .utf8),
              let event = try? decoder.decode(OpenAIStreamEvent.self, from: payloadData)
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
