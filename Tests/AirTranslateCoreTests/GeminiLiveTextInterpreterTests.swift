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
        func backlogSeconds() -> Double { 0 }
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

    private func translated(_ message: String) -> String {
        message.components(separatedBy: "Translate: ").last?.components(separatedBy: "\n").first ?? message
    }

    @Test func sendsUnitsOnTwoSessionsAndJoinsTheRest() async {
        let sent = Sent()
        let interpreter = makeInterpreter(sent)
        interpreter.enqueue("First line", endsUnit: true)
        interpreter.enqueue("Second line", endsUnit: true)
        interpreter.enqueue("Third", endsUnit: false)
        interpreter.enqueue("and fourth", endsUnit: true)
        await waitUntil { sent.turns.count == 2 }
        #expect(sent.turns.map(\.lane) == [0, 1])
        #expect(sent.turns.map { translated($0.text) } == ["First line", "Second line"])
        interpreter.handleServerMessage(complete, lane: 0)
        await waitUntil { sent.turns.count == 3 }
        #expect(translated(sent.turns[2].text) == "Third and fourth")
        #expect(sent.turns[2].text.hasPrefix("Context (do not translate): First line Second line"))
        interpreter.stop()
    }

    @Test func wordsWaitForTheEndOfTheUnit() async {
        let sent = Sent()
        let interpreter = makeInterpreter(sent)
        interpreter.enqueue("Um, it's", endsUnit: false)
        try? await Task.sleep(for: .milliseconds(150))
        #expect(sent.turns.isEmpty)
        interpreter.enqueue("just going to be fine", endsUnit: true)
        await waitUntil { sent.turns.count == 1 }
        #expect(translated(sent.turns[0].text) == "Um, it's just going to be fine")
        interpreter.stop()
    }

    @Test func lagSetsRateAndCondenses() {
        #expect(GeminiLiveTextInterpreter.rate(forLag: 0.5) == 1.1)
        #expect(abs(GeminiLiveTextInterpreter.rate(forLag: 2.75) - 1.65) < 0.001)
        #expect(GeminiLiveTextInterpreter.rate(forLag: 4) == 2.2)
        #expect(GeminiLiveTextInterpreter.rate(forLag: 9) == 2.2)
        let calm = GeminiLiveTextInterpreter.turnMessage("one two three", context: "", lag: 1)
        #expect(calm == "Translate: one two three")
        let behind = GeminiLiveTextInterpreter.turnMessage(
            "a b c d e f g h i j k l", context: "ctx", lag: 4)
        #expect(behind.contains("at most 6 words"))
        let far = GeminiLiveTextInterpreter.turnMessage("a b c d e f g h i j k l", context: "", lag: 7)
        #expect(far.contains("at most 4 words"))
    }

    @Test func leadingSilenceIsTrimmed() throws {
        var samples: [Int16] = [0, 10, -20, 3000, 5]
        let data = Data(bytes: &samples, count: samples.count * 2)
        let trimmed = try #require(GeminiLiveTextInterpreter.trimmingLeadingSilence(data.base64EncodedString()))
        #expect(Data(base64Encoded: trimmed)?.count == 4)
        var silent: [Int16] = [0, 1, -2]
        #expect(GeminiLiveTextInterpreter.trimmingLeadingSilence(
            Data(bytes: &silent, count: 6).base64EncodedString()) == nil)
    }

    @Test func audioOfALaterTurnWaitsForTheEarlierTurn() async {
        let sent = Sent()
        let speaker = FakeAudio()
        let interpreter = makeInterpreter(sent, audio: speaker)
        interpreter.enqueue("One", endsUnit: true)
        interpreter.enqueue("Two", endsUnit: true)
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
        interpreter.enqueue("Hello.", endsUnit: true)
        await waitUntil { sent.turns.count == 1 }
        interpreter.handleServerMessage(["serverContent": ["outputTranscription": ["text": "Xin "]]], lane: 0)
        interpreter.handleServerMessage(["serverContent": ["outputTranscription": ["text": "chào."]]], lane: 0)
        #expect(started.first?.0 == 1)
        #expect(started.first?.1 == "Hello.")
        #expect(transcripts.last?.0 == 1)
        #expect(transcripts.last?.1 == "Xin chào.")
        interpreter.stop()
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
