import Foundation

protocol QwenFileTranscriptionHTTPClient: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, Int)
}

private final class QwenFileTranscriptionURLSession: QwenFileTranscriptionHTTPClient, @unchecked Sendable {
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.httpShouldSetCookies = false
        session = URLSession(configuration: configuration, delegate: QwenFileTranscriptionRejectRedirects(), delegateQueue: nil)
    }

    func send(_ request: URLRequest) async throws -> (Data, Int) {
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw QwenFileTranscriptionError.invalidResponse
        }
        return (data, response.statusCode)
    }
}

private final class QwenFileTranscriptionRejectRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        // Do not forward the API-key header to a redirected host.
        completionHandler(nil)
    }
}

final class QwenAudioFileTranscriptionService: Sendable {
    static let modelID = "qwen-audio-3.1-asr-flash-filetrans"
    static let maximumURLBytes = 2_048
    static let maximumTranscriptBytes = 2 * 1_024 * 1_024
    static let endpoint = URL(string: "https://maas.qwencloudapi.com/api/v1/services/audio/asr/transcription")!
    static let tasksEndpoint = URL(string: "https://maas.qwencloudapi.com/api/v1/tasks")!

    private let keyProvider: @Sendable () throws -> String?
    private let httpClient: any QwenFileTranscriptionHTTPClient
    private let pollInterval: Duration
    private let maximumPollCount: Int

    init(
        keyProvider: @escaping @Sendable () throws -> String? = { try QwenAPIKeyStore.readAPIKey() },
        httpClient: any QwenFileTranscriptionHTTPClient = QwenFileTranscriptionURLSession(),
        pollInterval: Duration = .seconds(5),
        maximumPollCount: Int = 1_440
    ) {
        self.keyProvider = keyProvider
        self.httpClient = httpClient
        self.pollInterval = pollInterval
        self.maximumPollCount = maximumPollCount
    }

    func transcribe(fileURL value: String) async throws -> String {
        let fileURL = try Self.publicAudioURL(value)
        let key: String
        do {
            key = try keyProvider()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        } catch {
            throw QwenFileTranscriptionError.missingKey
        }
        guard !key.isEmpty, key.utf8.allSatisfy({ $0 >= 0x21 && $0 <= 0x7E }) else {
            throw QwenFileTranscriptionError.missingKey
        }

        let taskID = try await submit(fileURL: fileURL, key: key)
        for _ in 0..<maximumPollCount {
            try Task.checkCancellation()
            let task = try await fetchTask(taskID: taskID, key: key)
            switch task.status {
            case "PENDING", "RUNNING":
                try await Task.sleep(for: pollInterval)
            case "SUCCEEDED":
                guard !task.resultURLs.isEmpty else { throw QwenFileTranscriptionError.invalidResponse }
                var transcripts: [String] = []
                for resultURL in task.resultURLs {
                    try Task.checkCancellation()
                    let (data, status) = try await httpClient.send(URLRequest(url: resultURL))
                    guard (200..<300).contains(status) else { throw QwenFileTranscriptionError.serviceUnavailable }
                    transcripts.append(try Self.transcriptText(from: data))
                }
                let result = transcripts.filter { !$0.isEmpty }.joined(separator: "\n\n")
                guard !result.isEmpty else { throw QwenFileTranscriptionError.emptyTranscript }
                guard result.utf8.count <= Self.maximumTranscriptBytes else { throw QwenFileTranscriptionError.transcriptTooLarge }
                return result
            case "FAILED":
                throw QwenFileTranscriptionError.transcriptionFailed
            default:
                throw QwenFileTranscriptionError.invalidResponse
            }
        }
        throw QwenFileTranscriptionError.timeout
    }

    static func publicAudioURL(_ value: String) throws -> URL {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.utf8.count <= maximumURLBytes,
              let components = URLComponents(string: text),
              components.scheme?.lowercased() == "https",
              components.user == nil, components.password == nil,
              components.port == nil || components.port == 443,
              let host = components.host?.lowercased(), host.contains("."),
              host.range(of: "^[a-z0-9.-]+$", options: .regularExpression) != nil,
              !isIPv4Literal(host),
              host != "localhost", !host.hasSuffix(".localhost"), !host.hasSuffix(".local"),
              !host.hasSuffix(".internal"), !host.hasSuffix(".test"),
              let url = components.url else {
            throw QwenFileTranscriptionError.invalidFileURL
        }
        return url
    }

    private static func isIPv4Literal(_ host: String) -> Bool {
        let parts = host.split(separator: ".")
        return parts.count == 4 && parts.allSatisfy { !$0.isEmpty && $0.allSatisfy(\.isNumber) }
    }

    static func submitRequest(fileURL: URL, key: String) throws -> URLRequest {
        guard !key.isEmpty, key.utf8.allSatisfy({ $0 >= 0x21 && $0 <= 0x7E }) else {
            throw QwenFileTranscriptionError.missingKey
        }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("enable", forHTTPHeaderField: "X-DashScope-Async")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": modelID,
            "input": ["file_urls": [fileURL.absoluteString]],
            "parameters": ["channel_id": [0]],
        ], options: [.sortedKeys])
        return request
    }

    private func submit(fileURL: URL, key: String) async throws -> String {
        let request = try Self.submitRequest(fileURL: fileURL, key: key)
        let (data, status) = try await httpClient.send(request)
        guard (200..<300).contains(status),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let output = json["output"] as? [String: Any],
              let taskID = output["task_id"] as? String,
              Self.isValidTaskID(taskID) else {
            throw QwenFileTranscriptionError.serviceUnavailable
        }
        return taskID
    }

    private func fetchTask(taskID: String, key: String) async throws -> TaskResult {
        guard Self.isValidTaskID(taskID) else { throw QwenFileTranscriptionError.invalidResponse }
        let url = Self.tasksEndpoint.appendingPathComponent(taskID)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("enable", forHTTPHeaderField: "X-DashScope-Async")
        let (data, status) = try await httpClient.send(request)
        guard (200..<300).contains(status),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let output = json["output"] as? [String: Any],
              let taskStatus = output["task_status"] as? String else {
            throw QwenFileTranscriptionError.serviceUnavailable
        }
        guard taskStatus == "SUCCEEDED" else { return TaskResult(status: taskStatus, resultURLs: []) }
        guard let results = output["results"] as? [[String: Any]], !results.isEmpty else {
            throw QwenFileTranscriptionError.invalidResponse
        }
        let resultURLs = try results.map { result -> URL in
            guard result["subtask_status"] as? String == "SUCCEEDED",
                  let value = result["transcription_url"] as? String,
                  let url = URL(string: value), url.scheme?.lowercased() == "https",
                  url.host != nil, url.user == nil, url.password == nil else {
                throw QwenFileTranscriptionError.transcriptionFailed
            }
            return url
        }
        return TaskResult(status: taskStatus, resultURLs: resultURLs)
    }

    private static func isValidTaskID(_ value: String) -> Bool {
        value.range(of: "^[A-Za-z0-9_-]{1,256}$", options: .regularExpression) != nil
    }

    static func transcriptText(from data: Data) throws -> String {
        guard data.count <= maximumTranscriptBytes,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let transcripts = json["transcripts"] as? [[String: Any]], !transcripts.isEmpty else {
            throw QwenFileTranscriptionError.invalidResponse
        }
        let values = transcripts.compactMap { transcript -> String? in
            if let sentences = transcript["sentences"] as? [[String: Any]] {
                let text = sentences.compactMap { $0["text"] as? String }
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                    .joined(separator: "\n")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty { return text }
            }
            return (transcript["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let text = values.filter { !$0.isEmpty }.joined(separator: "\n\n")
        guard !text.isEmpty else { throw QwenFileTranscriptionError.emptyTranscript }
        return text
    }

    private struct TaskResult {
        let status: String
        let resultURLs: [URL]
    }
}

enum QwenFileTranscriptionError: LocalizedError, Equatable, Sendable {
    case invalidFileURL, missingKey, serviceUnavailable, invalidResponse
    case transcriptionFailed, emptyTranscript, transcriptTooLarge, timeout

    var errorDescription: String? {
        switch self {
        case .invalidFileURL: QwenCopy.fileTranscriptionInvalidURL
        case .missingKey: QwenCopy.keyInvalid
        case .serviceUnavailable: QwenCopy.fileTranscriptionUnavailable
        case .invalidResponse: QwenCopy.fileTranscriptionInvalidResponse
        case .transcriptionFailed: QwenCopy.fileTranscriptionFailed
        case .emptyTranscript: QwenCopy.fileTranscriptionEmpty
        case .transcriptTooLarge: QwenCopy.fileTranscriptionTooLarge
        case .timeout: QwenCopy.fileTranscriptionTimeout
        }
    }
}
