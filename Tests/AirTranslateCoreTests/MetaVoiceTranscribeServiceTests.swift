import Foundation
import Testing
@testable import AirTranslate

@Suite
struct MetaVoiceTranscribeServiceTests {
    @Test
    func handshakeEncodesRealtimeContractAndOptionalBias() throws {
        let data = try MetaVoiceTranscribeService.encodedHandshake(
            accessToken: "test-key",
            model: .museVoiceTranscribe,
            usesSpeakerLabels: true,
            languageBias: ["English", "Korean"],
            keywords: ["AirTranslate"]
        )
        let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let authorization = try #require(root["authorization"] as? [String: Any])

        #expect(authorization["accessToken"] as? String == "Bearer test-key")
        #expect(root["audioEncoding"] as? String == "PCM_24KHZ")
        #expect(root["model"] as? String == "muse-voice-transcribe-1.0")
        #expect(root["mode"] as? String == "DIARIZATION")
        #expect(root["partialMode"] as? String == "CUMULATIVE")
        #expect(root["emitAudioProgress"] as? Bool == false)
        #expect(root["languageBias"] as? [String] == ["English", "Korean"])
        #expect(root["keywords"] as? [String] == ["AirTranslate"])

        let endpointingData = try MetaVoiceTranscribeService.encodedHandshake(
            accessToken: "test-key",
            model: .museVoiceTranscribe,
            usesSpeakerLabels: false,
            languageBias: nil,
            keywords: []
        )
        let endpointing = try #require(
            try JSONSerialization.jsonObject(with: endpointingData) as? [String: Any]
        )
        #expect(endpointing["mode"] as? String == "ENDPOINTING")
        #expect(endpointing["languageBias"] == nil)
    }

    @Test(arguments: [
        (#"{"sessionId":"session"}"#, MetaVoiceServerEvent.acknowledgement(sessionId: "session")),
        (#"{"type":"speechStart","turnId":1,"audioProcessedMs":1200}"#, .speechStart(turnId: 1, audioProcessedMs: 1200)),
        (#"{"type":"transcript","transcript":"hello","final":false,"audioProcessedMs":2400}"#, .transcript(text: "hello", final: false, audioProcessedMs: 2400)),
        (#"{"type":"speaker","label":"A","audioProcessedMs":2480}"#, .speaker(label: "A", audioProcessedMs: 2480)),
        (#"{"type":"speechEnd","turnId":1,"audioProcessedMs":3600}"#, .speechEnd(turnId: 1, audioProcessedMs: 3600)),
        (#"{"type":"speechComplete","turnId":1,"transcript":"Hello.","audioProcessedMs":3600}"#, .speechComplete(turnId: 1, transcript: "Hello.", audioProcessedMs: 3600)),
        (#"{"type":"audioProgress","audioProcessedMs":4000}"#, .audioProgress(audioProcessedMs: 4000)),
        (#"{"type":"error","message":"failed","sessionId":"session"}"#, .error(message: "failed", sessionId: "session")),
    ])
    func decodesEveryKnownServerEvent(text: String, expected: MetaVoiceServerEvent) {
        #expect(MetaVoiceTranscribeService.decodeServerEvent(text) == expected)
    }

    @Test
    func ignoresUnknownAndMalformedEvents() {
        #expect(MetaVoiceTranscribeService.decodeServerEvent(#"{"type":"futureEvent"}"#) == nil)
        #expect(MetaVoiceTranscribeService.decodeServerEvent(#"{"unexpected":true}"#) == nil)
        #expect(MetaVoiceTranscribeService.decodeServerEvent("not-json") == nil)
    }

    @Test
    func acknowledgementMarksRealtimeInputReady() {
        let service = MetaVoiceTranscribeService()
        #expect(!service.isReadyForRealtimeInput)
        service.handleEventText(#"{"sessionId":"session"}"#)
        #expect(service.isReadyForRealtimeInput)
    }

    @Test
    func assemblerReplacesCumulativePartialAndFinalOverridesIt() {
        var assembler = MetaTurnAssembler()
        #expect(assembler.apply(.speechStart(turnId: 1, audioProcessedMs: nil)) == .started(turnId: 1))
        #expect(
            assembler.apply(.transcript(text: "how", final: false, audioProcessedMs: nil))
                == .partial(turnId: 1, transcript: "how", speakerLabel: nil)
        )
        #expect(
            assembler.apply(.transcript(text: "how is the", final: false, audioProcessedMs: nil))
                == .partial(turnId: 1, transcript: "how is the", speakerLabel: nil)
        )
        #expect(
            assembler.apply(.speechComplete(turnId: 1, transcript: "How is it?", audioProcessedMs: nil))
                == .completed(
                    turn: MetaTurn(
                        turnId: 1,
                        transcript: "How is it?",
                        speakerLabel: nil,
                        isComplete: true
                    )
                )
        )
        #expect(assembler.turns[1]?.transcript == "How is it?")
    }

    @Test
    func assemblerKeepsOverlappingTurnsAndSpeakerAttribution() {
        var assembler = MetaTurnAssembler()
        _ = assembler.apply(.speechStart(turnId: 1, audioProcessedMs: nil))
        _ = assembler.apply(.speaker(label: "A", audioProcessedMs: nil))
        _ = assembler.apply(.transcript(text: "first", final: false, audioProcessedMs: nil))
        _ = assembler.apply(.speechStart(turnId: 2, audioProcessedMs: nil))
        _ = assembler.apply(.speaker(label: "B", audioProcessedMs: nil))
        _ = assembler.apply(.transcript(text: "second", final: false, audioProcessedMs: nil))

        let first = assembler.apply(
            .speechComplete(turnId: 1, transcript: "First.", audioProcessedMs: nil)
        )
        let second = assembler.apply(
            .speechComplete(turnId: 2, transcript: "Second.", audioProcessedMs: nil)
        )

        #expect(first == .completed(turn: MetaTurn(turnId: 1, transcript: "First.", speakerLabel: "A", isComplete: true)))
        #expect(second == .completed(turn: MetaTurn(turnId: 2, transcript: "Second.", speakerLabel: "B", isComplete: true)))
    }

    @Test
    func preHandshakeBufferDropsOldestWithMetaDegradation() {
        let service = MetaVoiceTranscribeService()
        let chunk = Data(repeating: 1, count: 48_000)
        service.sendOrBufferAudioChunks([chunk, chunk, chunk, chunk])

        #expect(service.bufferedPreHandshakeAudioChunks.count == 3)
        #expect(service.audioTransportDegradation?.provider == .meta)
        #expect(service.audioTransportDegradation?.phase == .preSetupBuffer)
        #expect(service.audioTransportDegradation?.policy == .dropOldest)
        #expect(service.audioTransportDegradation?.droppedChunkCount == 1)
    }

    @Test
    func saturatedSendWindowDropsNewestWithMetaDegradation() {
        let service = MetaVoiceTranscribeService()
        for _ in 0..<48 {
            #expect(service.reserveAudioSendSlot(audioByteCount: 3_840))
        }
        #expect(!service.reserveAudioSendSlot(audioByteCount: 3_840))
        #expect(service.audioTransportDegradation?.provider == .meta)
        #expect(service.audioTransportDegradation?.phase == .sendWindow)
        #expect(service.audioTransportDegradation?.policy == .dropNewest)
        #expect(service.audioTransportDegradation?.pendingSendCount == 48)
    }

    @Test
    func languageBiasMapsSupportedLanguagesAndRejectsUnsupportedOnes() {
        #expect(LanguageOption.english.metaLanguageBiasName == "English")
        #expect(LanguageOption.korean.metaLanguageBiasName == "Korean")
        #expect(LanguageOption.supported.first { $0.id == "ja-JP" }?.metaLanguageBiasName == "Japanese")
        #expect(LanguageOption.supported.first { $0.id == "zh-CN" }?.metaLanguageBiasName == "Mandarin Chinese")
        #expect(LanguageOption.supported.first { $0.id == "vi-VN" }?.metaLanguageBiasName == "Vietnamese")
        #expect(
            LanguageOption(
                id: "ru-RU",
                title: "Russian",
                locale: Locale(identifier: "ru-RU")
            ).metaLanguageBiasName == nil
        )
    }
}
