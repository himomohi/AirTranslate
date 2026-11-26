import Foundation
import Testing
@testable import AirTranslate

@MainActor
@Suite
struct GeminiLiveTextInterpreterTests {
    private final class Sent { var turns: [(lane: Int, text: String)] = [] }

    private final class FakeAudio: ScreenTextAudioSink {
        var played: [String] = []
        var rate: Float = 1
        func playPCM16Base64(_ audio: String, sampleRate: Double) { played.append(audio) }
        func setRate(_ rate: Float) { self.rate = rate }
        func setVolume(_ volume: Double) {}
        func stop() {}
    }

    private func makeInterpreter(_ sent: Sent, audio: FakeAudio = FakeAudio()) -> GeminiLiveTextInterpreter {
        GeminiLiveTextInterpreter(
            configuration: .init(sourceLanguage: "English", targetLanguage: "Vietnamese"),
            audio: audio,
            sendOverride: { lane, text in await MainActor.run { sent.turns.append((lane, text)) } }
        )
    }

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<300 where !condition() { try? await Task.sleep(for: .milliseconds(5)) }
    }

    private func audio(_ data: String) -> [String: Any] {
        ["serverContent": ["modelTurn": ["parts": [["inlineData": ["data": data]]]]]]
    }

    private let complete: [String: Any] = ["serverContent": ["turnComplete": true]]

    @Test func sendsPhrasesOnTwoSessionsAndJoinsTheRest() async {
        let sent = Sent()
        let interpreter = makeInterpreter(sent)
        interpreter.enqueue("First sentence.")
        interpreter.enqueue("Second sentence.")
        interpreter.enqueue("Third")
        interpreter.enqueue("and fourth.")
        await waitUntil { sent.turns.count == 2 }
        #expect(sent.turns.map(\.lane) == [0, 1])
        #expect(sent.turns.map(\.text) == ["First sentence.", "Second sentence."])
        interpreter.handleServerMessage(complete, lane: 0)
        await waitUntil { sent.turns.count == 3 }
        #expect(sent.turns.last?.text == "Third and fourth.")
        #expect(sent.turns.last?.lane == 0)
        interpreter.stop()
    }

    @Test func fragmentWaitsBrieflyForMoreWords() async {
        let sent = Sent()
        let interpreter = makeInterpreter(sent)
        interpreter.enqueue("Um, it's")
        try? await Task.sleep(for: .milliseconds(100))
        #expect(sent.turns.isEmpty)
        interpreter.enqueue("just going to be fine")
        await waitUntil { sent.turns.count == 1 }
        #expect(sent.turns.first?.text == "Um, it's just going to be fine")
        interpreter.stop()
    }

    @Test func fragmentIsSentAfterThePhraseDelay() async {
        let sent = Sent()
        let interpreter = makeInterpreter(sent)
        interpreter.enqueue("architectures")
        await waitUntil { sent.turns.count == 1 }
        #expect(sent.turns.first?.text == "architectures")
        interpreter.stop()
    }

    @Test func audioOfALaterTurnWaitsForTheEarlierTurn() async {
        let sent = Sent()
        let speaker = FakeAudio()
        let interpreter = makeInterpreter(sent, audio: speaker)
        interpreter.enqueue("One.")
        interpreter.enqueue("Two.")
        await waitUntil { sent.turns.count == 2 }
        interpreter.handleServerMessage(audio("b1"), lane: 1)  // Turn 2 arrives first: held.
        interpreter.handleServerMessage(audio("a1"), lane: 0)
        #expect(speaker.played == ["a1"])
        interpreter.handleServerMessage(audio("b2"), lane: 1)
        interpreter.handleServerMessage(complete, lane: 0)
        #expect(speaker.played == ["a1", "b1", "b2"])
        interpreter.handleServerMessage(audio("b3"), lane: 1)
        #expect(speaker.played == ["a1", "b1", "b2", "b3"])
        interpreter.stop()
    }

    @Test func reportsTranscriptPerTurn() async {
        let sent = Sent()
        let interpreter = makeInterpreter(sent)
        var started: [(Int, String)] = []
        var transcripts: [(Int, String)] = []
        interpreter.onTurnStarted = { started.append(($0, $1)) }
        interpreter.onTranscript = { transcripts.append(($0, $1)) }
        interpreter.enqueue("Hello.")
        await waitUntil { sent.turns.count == 1 }
        interpreter.handleServerMessage(["serverContent": ["outputTranscription": ["text": "Xin "]]], lane: 0)
        interpreter.handleServerMessage(["serverContent": ["outputTranscription": ["text": "chào."]]], lane: 0)
        #expect(started.first?.0 == 1)
        #expect(started.first?.1 == "Hello.")
        #expect(transcripts.last?.0 == 1)
        #expect(transcripts.last?.1 == "Xin chào.")
        interpreter.stop()
    }

    @Test func phraseRules() {
        #expect(GeminiLiveTextInterpreter.isPhrase("Done."))
        #expect(GeminiLiveTextInterpreter.isPhrase("one two three four five six"))
        #expect(!GeminiLiveTextInterpreter.isPhrase("Um, it's"))
    }

    @Test func setupAsksForAudioInTheTargetLanguage() throws {
        let setup = try #require(GeminiLiveTextInterpreter.setupMessage(
            for: .init(sourceLanguage: "English", targetLanguage: "Vietnamese"))["setup"] as? [String: Any])
        let config = try #require(setup["generationConfig"] as? [String: Any])
        #expect(config["responseModalities"] as? [String] == ["AUDIO"])
        let instruction = try #require(
            ((setup["systemInstruction"] as? [String: Any])?["parts"] as? [[String: Any]])?.first?["text"] as? String
        )
        #expect(instruction.contains("Vietnamese"))
    }
}
