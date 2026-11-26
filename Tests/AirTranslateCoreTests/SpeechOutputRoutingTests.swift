import Testing
@testable import AirTranslate

@Suite
struct SpeechOutputRoutingTests {
    private static let unknownUID = "AirTranslate.Tests.NoSuchSpeaker"

    @Test
    func unknownSpeakerResolvesToSystemDefault() {
        #expect(SpeechOutputDeviceCatalog.deviceID(forUID: Self.unknownUID) == nil)
    }

    @Test
    func realtimeOutputSwitchesBetweenUnknownSpeakerAndSystemDefault() {
        let output = OpenAIRealtimeAudioOutput()
        output.setOutputDevice(uid: Self.unknownUID)
        output.setOutputDevice(uid: nil)
        output.stop()

        #expect(output.backlogSeconds() == 0)
    }

    @Test
    func appleVoiceOutputSwitchesBetweenUnknownSpeakerAndSystemDefault() {
        let output = TranslatedSpeechOutput()
        output.setOutputDevice(uid: Self.unknownUID)
        output.setOutputDevice(uid: nil)
        output.stop()
    }

    @Test @MainActor
    func audioPlayerOutputsAcceptUnknownSpeakerAndSystemDefault() {
        let outputs: [any SpeechOutputRouting] = [GeminiSpeechOutput(), MAIVoiceSpeechOutput(keyProvider: { nil })]
        for output in outputs {
            output.setOutputDevice(uid: Self.unknownUID)
            output.setOutputDevice(uid: nil)
        }
    }

    @Test
    func routedUtteranceFinishesOnlyAfterRenderingAndPlayback() {
        var utterance = RoutedUtterance(key: "hello")
        utterance.schedule()
        utterance.schedule()
        #expect(!utterance.isDone)

        utterance.finishRendering()
        utterance.finishPlaying()
        #expect(!utterance.isDone)

        utterance.finishPlaying()
        #expect(utterance.isDone)
    }

    @Test
    func routedUtteranceWithoutAudioFinishesWhenRenderingEnds() {
        var utterance = RoutedUtterance(key: "hello")
        #expect(!utterance.isDone)

        utterance.finishRendering()
        #expect(utterance.isDone)
    }

    @Test
    func droppedBuffersNeverLeaveRoutedUtterancePending() {
        var utterance = RoutedUtterance(key: "hello")
        utterance.schedule()
        utterance.finishPlaying()
        utterance.finishPlaying()
        utterance.finishRendering()

        #expect(utterance.isDone)
    }
}
