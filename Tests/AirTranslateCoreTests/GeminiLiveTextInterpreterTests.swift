import Foundation
import Testing
@testable import AirTranslate

@MainActor
@Suite
struct GeminiLiveTextInterpreterTests {
    private final class Sent { var lines: [String] = [] }

    private func makeInterpreter(_ sent: Sent) -> GeminiLiveTextInterpreter {
        GeminiLiveTextInterpreter(
            configuration: .init(sourceLanguage: "English", targetLanguage: "Vietnamese"),
            audio: OpenAIRealtimeAudioOutput(),
            sendOverride: { line in await MainActor.run { sent.lines.append(line) } }
        )
    }

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<200 where !condition() { try? await Task.sleep(for: .milliseconds(5)) }
    }

    @Test func sendsOneLineAtATimeAndKeepsOnlyTheNewestWaiting() async {
        let sent = Sent()
        let interpreter = makeInterpreter(sent)
        interpreter.enqueue("one")
        interpreter.enqueue("two")
        interpreter.enqueue("three")
        await waitUntil { sent.lines.count == 1 }
        try? await Task.sleep(for: .milliseconds(50))
        #expect(sent.lines == ["one"])
        interpreter.handleServerMessage(["serverContent": ["turnComplete": true]])
        await waitUntil { sent.lines.count == 2 }
        #expect(sent.lines == ["one", "three"])
        interpreter.stop()
    }

    @Test func reportsTranscriptForTheLineInFlight() async {
        let sent = Sent()
        let interpreter = makeInterpreter(sent)
        var transcripts: [(String, String)] = []
        interpreter.onTranscript = { transcripts.append(($0, $1)) }
        interpreter.enqueue("Hello")
        interpreter.handleServerMessage(["serverContent": ["outputTranscription": ["text": "Xin "]]])
        interpreter.handleServerMessage(["serverContent": ["outputTranscription": ["text": "chào"]]])
        #expect(transcripts.last?.0 == "Hello")
        #expect(transcripts.last?.1 == "Xin chào")
        interpreter.stop()
    }

    @Test func setupAsksForAudioInTheTargetLanguage() throws {
        let interpreter = makeInterpreter(Sent())
        let setup = try #require(interpreter.setupMessage()["setup"] as? [String: Any])
        let config = try #require(setup["generationConfig"] as? [String: Any])
        #expect(config["responseModalities"] as? [String] == ["AUDIO"])
        let instruction = try #require(
            ((setup["systemInstruction"] as? [String: Any])?["parts"] as? [[String: Any]])?.first?["text"] as? String
        )
        #expect(instruction.contains("Vietnamese"))
    }
}
