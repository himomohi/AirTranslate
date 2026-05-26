import Foundation

actor OpenAITranslationService {
    private let endpoint = URL(string: "https://api.openai.com/v1/responses")!

    func translate(
        _ text: String,
        source: LanguageOption,
        target: LanguageOption,
        model selectedModel: OpenAIRealtimeTranslationModel
    ) async throws -> String {
        guard !text.isEmpty else { return text }
        guard selectedModel.isEnabled else { return text }
        guard let apiKey = try OpenAIAPIKeyStore.readAPIKey(), !apiKey.isEmpty else {
            throw OpenAITranslationError.missingAPIKey
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(
            OpenAIResponseRequest(
                model: selectedModel.apiModelID,
                instructions: AppText.openAITranslationInstructions(
                    source: source.localizedTitle,
                    target: target.localizedTitle
                ),
                input: text,
                store: false
            )
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAITranslationError.invalidResponse
        }
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
}

private struct OpenAIResponseRequest: Encodable {
    let model: String
    let instructions: String
    let input: String
    let store: Bool
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

private struct OpenAIErrorResponse: Decodable {
    let error: OpenAIErrorBody
}

private struct OpenAIErrorBody: Decodable {
    let message: String
}

enum OpenAITranslationError: LocalizedError {
    case missingAPIKey
    case missingAzureEndpoint
    case missingAzureAPIKey
    case transcriptionEndpointUnsupported
    case invalidResponse
    case emptyOutput
    case requestFailed(statusCode: Int, message: String?)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            AppText.openAIAPIKeyMissing
        case .missingAzureEndpoint:
            AppText.azureOpenAIEndpointMissing
        case .missingAzureAPIKey:
            AppText.azureOpenAIAPIKeyMissing
        case .transcriptionEndpointUnsupported:
            AppText.azureOpenAITranscriptionUnsupported
        case .invalidResponse:
            AppText.openAIInvalidResponse
        case .emptyOutput:
            AppText.openAIEmptyOutput
        case let .requestFailed(statusCode, message):
            AppText.openAIRequestFailed(statusCode: statusCode, message: message)
        }
    }
}
