import Foundation
import Testing
@testable import AirTranslate

@Suite("Qwen Audio file transcription")
struct QwenAudioFileTranscriptionServiceTests {
    @Test func submitUsesOfficialModelAndOnlyPublicFileURL() throws {
        let fileURL = try QwenAudioFileTranscriptionService.publicAudioURL(" https://media.example.org/meeting.wav?sig=abc ")
        let request = try QwenAudioFileTranscriptionService.submitRequest(fileURL: fileURL, key: "test-key")
        let body = try #require(request.httpBody)
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let input = try #require(json["input"] as? [String: Any])

        #expect(request.url == QwenAudioFileTranscriptionService.endpoint)
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-key")
        #expect(request.value(forHTTPHeaderField: "X-DashScope-Async") == "enable")
        #expect(json["model"] as? String == "qwen-audio-3.1-asr-flash-filetrans")
        #expect(input["file_urls"] as? [String] == ["https://media.example.org/meeting.wav?sig=abc"])
    }

    @Test func rejectsNonPublicOrCredentialBearingURL() {
        for value in [
            "http://media.example.org/audio.wav",
            "https://localhost/audio.wav",
            "https://127.0.0.1/audio.wav",
            "https://speaker.local/audio.wav",
            "https://user:secret@media.example.org/audio.wav",
            "https://media.example.org:8443/audio.wav",
            "not-a-url",
        ] {
            #expect(throws: QwenFileTranscriptionError.invalidFileURL) {
                try QwenAudioFileTranscriptionService.publicAudioURL(value)
            }
        }
    }

    @Test func pollsTaskAndLoadsTranscriptWithoutForwardingAPIKey() async throws {
        let client = QwenAudioFileTranscriptionTestClient()
        let service = QwenAudioFileTranscriptionService(
            keyProvider: { "test-key" },
            httpClient: client,
            pollInterval: .milliseconds(1),
            maximumPollCount: 3
        )

        let transcript = try await service.transcribe(fileURL: "https://media.example.org/meeting.wav")
        #expect(transcript == "Hello world.\nNext line.")
        #expect(await client.didAvoidKeyOnTranscriptFetch)
        #expect(await client.submittedModel == "qwen-audio-3.1-asr-flash-filetrans")
        #expect(await client.pollCount == 2)
        #expect(await client.pollMethod == "POST")
        #expect(await client.pollAsyncHeader == "enable")
    }

    @Test func mapsFailedTaskToSafeError() async throws {
        let client = QwenAudioFileTranscriptionTestClient(taskStatus: "FAILED")
        let service = QwenAudioFileTranscriptionService(
            keyProvider: { "test-key" },
            httpClient: client,
            pollInterval: .milliseconds(1),
            maximumPollCount: 2
        )

        await #expect(throws: QwenFileTranscriptionError.transcriptionFailed) {
            try await service.transcribe(fileURL: "https://media.example.org/meeting.wav")
        }
    }

    @Test func parsesSentenceSegmentsAndTranscriptFallback() throws {
        let sentenceData = try JSONSerialization.data(withJSONObject: [
            "transcripts": [["sentences": [["text": "Hello "], ["text": "world."]]]]
        ])
        let fallbackData = try JSONSerialization.data(withJSONObject: [
            "transcripts": [["text": "Full transcript."]]
        ])

        #expect(try QwenAudioFileTranscriptionService.transcriptText(from: sentenceData) == "Hello\nworld.")
        #expect(try QwenAudioFileTranscriptionService.transcriptText(from: fallbackData) == "Full transcript.")
    }
}

private actor QwenAudioFileTranscriptionTestClient: QwenFileTranscriptionHTTPClient {
    private let taskStatus: String
    private(set) var pollCount = 0
    private(set) var submittedModel: String?
    private(set) var pollMethod: String?
    private(set) var pollAsyncHeader: String?
    private(set) var didAvoidKeyOnTranscriptFetch = false

    init(taskStatus: String = "SUCCEEDED") {
        self.taskStatus = taskStatus
    }

    func send(_ request: URLRequest) async throws -> (Data, Int) {
        guard let url = request.url else { return (Data(), 400) }
        if url == QwenAudioFileTranscriptionService.endpoint {
            if let body = request.httpBody,
               let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
                submittedModel = json["model"] as? String
            }
            return (try JSONSerialization.data(withJSONObject: ["output": ["task_id": "task-123"]]), 200)
        }
        if url == QwenAudioFileTranscriptionService.tasksEndpoint.appendingPathComponent("task-123") {
            pollCount += 1
            pollMethod = request.httpMethod
            pollAsyncHeader = request.value(forHTTPHeaderField: "X-DashScope-Async")
            let status = taskStatus == "SUCCEEDED" && pollCount == 1 ? "RUNNING" : taskStatus
            var output: [String: Any] = ["task_status": status]
            if status == "SUCCEEDED" {
                output["results"] = [[
                    "subtask_status": "SUCCEEDED",
                    "transcription_url": "https://results.qwencloud.example/transcript.json",
                ]]
            }
            return (try JSONSerialization.data(withJSONObject: ["output": output]), 200)
        }
        if url.host == "results.qwencloud.example" {
            didAvoidKeyOnTranscriptFetch = request.value(forHTTPHeaderField: "Authorization") == nil
            return (try JSONSerialization.data(withJSONObject: [
                "transcripts": [[
                    "sentences": [["text": "Hello world."], ["text": "Next line."]]
                ]]
            ]), 200)
        }
        return (Data(), 404)
    }
}
