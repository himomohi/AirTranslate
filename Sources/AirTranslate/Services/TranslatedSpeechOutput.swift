@preconcurrency import AVFAudio
import CoreAudio
import Foundation

final class TranslatedSpeechOutput: NSObject, AVSpeechSynthesizerDelegate, SpeechOutputRouting, @unchecked Sendable {
    private static let maximumQueuedUtterances = 3
    private static let catchUpRatePerQueuedUtterance: Float = 0.05
    private static let maximumCatchUpRateBoost: Float = 0.12

    private let synthesizer = AVSpeechSynthesizer()
    private let devicePlayer = SpeechDevicePlayer()
    private var speechVolume: Float = 1
    private var queuedSpeechKeys: Set<String> = []
    private var outputDeviceUID: String?
    /// The connected speaker `outputDeviceUID` resolved to last; nil is the system default.
    private var outputDeviceID: AudioDeviceID?
    /// Utterances rendered with `write` and played on the chosen speaker; their keys
    /// clear once the audio has played, not when the synthesizer finishes rendering.
    private var routedUtterances: [ObjectIdentifier: RoutedUtterance] = [:]
    private var routingGeneration: UInt64 = 0

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func setVolume(_ volume: Double) {
        speechVolume = Float(min(max(volume, 0), 1))
        devicePlayer.setVolume(speechVolume)
    }

    func setOutputDevice(uid: String?) {
        outputDeviceUID = uid
        outputDeviceID = uid.flatMap(SpeechOutputDeviceCatalog.deviceID(forUID:))
        if outputDeviceID == nil, routedUtterances.isEmpty {
            devicePlayer.reset()
        }
    }

    func speak(_ text: String, language: LanguageOption) {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }
        let speechKey = normalizedSpeechKey(trimmedText, language: language)
        guard !queuedSpeechKeys.contains(speechKey) else { return }

        var backlogDepth = queuedSpeechKeys.count
        if backlogDepth > Self.maximumQueuedUtterances {
            // Live interpretation favors the newest text: skip the stale queue
            // instead of letting the synthesizer fall further behind.
            synthesizer.stopSpeaking(at: .word)
            dropRoutedSpeech()
            queuedSpeechKeys.removeAll()
            backlogDepth = 0
        }

        queuedSpeechKeys.insert(speechKey)

        let utterance = AVSpeechUtterance(string: trimmedText)
        utterance.voice = AVSpeechSynthesisVoice(language: language.id)
        utterance.volume = speechVolume
        utterance.rate = Self.catchUpSpeechRate(backlogDepth: backlogDepth)
        outputDeviceID = outputDeviceUID.flatMap(SpeechOutputDeviceCatalog.deviceID(forUID:))
        if outputDeviceID != nil {
            speakOnOutputDevice(utterance, key: speechKey)
        } else {
            synthesizer.speak(utterance)
        }
    }

    static func catchUpSpeechRate(backlogDepth: Int) -> Float {
        let boost = min(
            catchUpRatePerQueuedUtterance * Float(max(backlogDepth, 0)),
            maximumCatchUpRateBoost
        )
        return AVSpeechUtteranceDefaultSpeechRate + boost
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        dropRoutedSpeech()
        queuedSpeechKeys.removeAll()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        finishSpeaking(utterance)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        finishSpeaking(utterance)
    }

    /// AVSpeechSynthesizer cannot pick a speaker, so render the utterance and play
    /// its buffers on the chosen device, which applies the volume (never twice).
    /// Buffers follow the current route, so a speaker change mid-utterance moves the rest.
    private func speakOnOutputDevice(_ utterance: AVSpeechUtterance, key: String) {
        utterance.volume = 1
        let id = ObjectIdentifier(utterance)
        let generation = routingGeneration
        routedUtterances[id] = RoutedUtterance(key: key)
        synthesizer.write(utterance) { [weak self] buffer in
            nonisolated(unsafe) let buffer = buffer as? AVAudioPCMBuffer
            DispatchQueue.main.async {
                self?.playRendered(buffer, utteranceID: id, generation: generation)
            }
        }
    }

    private func playRendered(
        _ buffer: AVAudioPCMBuffer?,
        utteranceID: ObjectIdentifier,
        generation: UInt64
    ) {
        guard generation == routingGeneration, routedUtterances[utteranceID] != nil else { return }
        // A zero-length buffer marks the end of the rendered utterance.
        guard let buffer, buffer.frameLength > 0 else {
            updateRoutedUtterance(utteranceID) { $0.finishRendering() }
            return
        }
        routedUtterances[utteranceID]?.schedule()
        devicePlayer.play(buffer, on: outputDeviceID) { [weak self] in
            DispatchQueue.main.async {
                self?.finishPlayingBuffer(of: utteranceID, generation: generation)
            }
        }
    }

    private func finishPlayingBuffer(of utteranceID: ObjectIdentifier, generation: UInt64) {
        guard generation == routingGeneration else { return }
        updateRoutedUtterance(utteranceID) { $0.finishPlaying() }
    }

    private func finishSpeaking(_ utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        if routedUtterances[id] != nil {
            updateRoutedUtterance(id) { $0.finishRendering() }
        } else {
            removeQueuedSpeechKey(for: utterance)
        }
    }

    private func updateRoutedUtterance(_ id: ObjectIdentifier, _ update: (inout RoutedUtterance) -> Void) {
        guard var routed = routedUtterances[id] else { return }
        update(&routed)
        if routed.isDone {
            routedUtterances[id] = nil
            queuedSpeechKeys.remove(routed.key)
        } else {
            routedUtterances[id] = routed
        }
    }

    private func dropRoutedSpeech() {
        routingGeneration &+= 1
        routedUtterances.removeAll()
        devicePlayer.stop()
    }

    private func removeQueuedSpeechKey(for utterance: AVSpeechUtterance) {
        let languageID = utterance.voice?.language ?? Locale.current.identifier
        let language = LanguageOption(id: languageID, title: languageID, locale: Locale(identifier: languageID))
        queuedSpeechKeys.remove(normalizedSpeechKey(utterance.speechString, language: language))
    }

    private func normalizedSpeechKey(_ text: String, language: LanguageOption) -> String {
        let foldedText = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: language.locale)
        let allowedCharacters = CharacterSet.letters
            .union(.decimalDigits)
            .union(.whitespacesAndNewlines)
        let filteredText = String(foldedText.unicodeScalars.map { scalar in
            allowedCharacters.contains(scalar) ? Character(scalar) : " "
        })

        return filteredText
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Playback progress of one utterance rendered for a chosen speaker: done once
/// rendering has finished and every scheduled buffer has played (or been dropped).
struct RoutedUtterance: Equatable {
    let key: String
    private var pendingBuffers = 0
    private var isRendered = false

    init(key: String) {
        self.key = key
    }

    var isDone: Bool { isRendered && pendingBuffers == 0 }

    mutating func schedule() { pendingBuffers += 1 }
    mutating func finishPlaying() { pendingBuffers = max(0, pendingBuffers - 1) }
    mutating func finishRendering() { isRendered = true }
}

/// Plays rendered speech buffers on a Core Audio output device (nil follows the
/// system default). Main thread only.
private final class SpeechDevicePlayer: @unchecked Sendable {
    private var engine: AVAudioEngine?
    private let player = AVAudioPlayerNode()
    private var format: AVAudioFormat?
    private var configurationObserver: NSObjectProtocol?
    private var deviceID: AudioDeviceID?
    private var volume: Float = 1

    deinit {
        reset()
    }

    func setVolume(_ volume: Float) {
        self.volume = volume
        player.volume = volume
    }

    /// Calls `completion` once the buffer has played, was dropped, or could not play.
    func play(_ buffer: AVAudioPCMBuffer, on deviceID: AudioDeviceID?, completion: @escaping @Sendable () -> Void) {
        guard let buffer = Self.floatBuffer(buffer) else { return completion() }
        do {
            let engine = engine(for: deviceID)
            if format != buffer.format {
                player.stop()
                engine.disconnectNodeOutput(player)
                engine.connect(player, to: engine.mainMixerNode, format: buffer.format)
                player.volume = volume
                format = buffer.format
            }
            if !engine.isRunning {
                try engine.start()
            }
            player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { _ in completion() }
            if !player.isPlaying {
                player.play()
            }
        } catch {
            reset()
            completion()
        }
    }

    func stop() {
        player.stop()
    }

    func reset() {
        player.stop()
        if let configurationObserver {
            NotificationCenter.default.removeObserver(configurationObserver)
        }
        if let engine {
            engine.stop()
            engine.detach(player)
        }
        configurationObserver = nil
        engine = nil
        format = nil
        deviceID = nil
    }

    private func engine(for deviceID: AudioDeviceID?) -> AVAudioEngine {
        if let engine, self.deviceID == deviceID { return engine }
        reset()
        let engine = AVAudioEngine()
        if let deviceID {
            // A speaker that just went away leaves the engine on the system default.
            try? engine.outputNode.auAudioUnit.setDeviceID(deviceID)
        }
        engine.attach(player)
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: .main
        ) { [weak self] _ in
            // The engine stopped itself (the device or its format changed); the next
            // buffer builds a fresh one. Dropped buffers still report completion.
            self?.reset()
        }
        self.engine = engine
        self.deviceID = deviceID
        return engine
    }

    /// The engine mixes Float32 only; some voices render Int16.
    private static func floatBuffer(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard buffer.format.commonFormat != .pcmFormatFloat32 else { return buffer }
        guard let format = AVAudioFormat(
            standardFormatWithSampleRate: buffer.format.sampleRate,
            channels: buffer.format.channelCount
        ),
            let converter = AVAudioConverter(from: buffer.format, to: format),
            let converted = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: buffer.frameLength),
            (try? converter.convert(to: converted, from: buffer)) != nil
        else { return nil }
        return converted
    }
}
