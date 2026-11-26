import AVFAudio
import Foundation

final class OpenAIRealtimeAudioOutput: @unchecked Sendable {
    private let queue = DispatchQueue(label: "AirTranslate.OpenAIRealtimeAudioOutput")
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    /// Speeds playback up without raising pitch (screen text catches up with the video).
    private let timePitch = AVAudioUnitTimePitch()
    private let translatedSampleGain: Float = 1.6
    private let maximumBacklogSeconds: Double
    private var outputVolume: Float = 1
    private var format: AVAudioFormat?
    private var isConfigured = false
    private var scheduledFrames: AVAudioFramePosition = 0

    init(maximumBacklogSeconds: Double = 3) {
        self.maximumBacklogSeconds = maximumBacklogSeconds
    }

    func setVolume(_ volume: Double) {
        queue.async { [weak self] in
            guard let self else { return }
            outputVolume = Float(min(max(volume, 0), 1))
            player.volume = outputVolume
        }
    }

    /// Playback speed, 1 = normal. Clamped to 0.5...2.
    func setRate(_ rate: Float) {
        queue.async { [weak self] in
            self?.timePitch.rate = min(max(rate, 0.5), 2)
        }
    }

    func playPCM16Base64(_ audio: String, sampleRate: Double) {
        queue.async { [weak self, audio] in
            guard let data = Data(base64Encoded: audio), !data.isEmpty else { return }
            self?.playPCM16Data(data, sampleRate: sampleRate)
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            player.stop()
            engine.stop()
            scheduledFrames = 0
        }
    }

    private func playPCM16Data(_ data: Data, sampleRate: Double) {
        let sampleCount = data.count / MemoryLayout<Int16>.size
        guard sampleCount > 0,
              let format = configuredFormat(sampleRate: sampleRate),
              let buffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount(sampleCount)
              ),
              let channel = buffer.floatChannelData?.pointee
        else {
            return
        }

        data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return }
            let samples = baseAddress.assumingMemoryBound(to: Int16.self)
            for index in 0..<sampleCount {
                let sample = Int16(littleEndian: samples[index])
                let normalizedSample = Float(sample) / Float(Int16.max)
                channel[index] = min(1, max(-1, normalizedSample * translatedSampleGain))
            }
        }
        buffer.frameLength = AVAudioFrameCount(sampleCount)

        do {
            if !engine.isRunning {
                try engine.start()
            }
            discardBacklogIfNeeded(sampleRate: sampleRate)
            scheduledFrames += AVAudioFramePosition(buffer.frameLength)
            player.scheduleBuffer(buffer, completionHandler: nil)
            if !player.isPlaying {
                player.play()
            }
        } catch {
            player.stop()
            engine.stop()
            scheduledFrames = 0
        }
    }

    private func discardBacklogIfNeeded(sampleRate: Double) {
        guard player.isPlaying,
              let nodeTime = player.lastRenderTime,
              let playerTime = player.playerTime(forNodeTime: nodeTime),
              playerTime.isSampleTimeValid
        else {
            return
        }

        let playedFrames = max(0, playerTime.sampleTime)
        if scheduledFrames <= playedFrames {
            // Playback caught up with the queue (underrun); realign the accounting.
            scheduledFrames = playedFrames
            return
        }

        let backlogSeconds = Double(scheduledFrames - playedFrames) / sampleRate
        guard backlogSeconds > maximumBacklogSeconds else { return }

        // Live interpretation favors the newest audio: drop the stale queue and
        // restart playback from the incoming chunk.
        player.stop()
        scheduledFrames = 0
    }

    private func configuredFormat(sampleRate: Double) -> AVAudioFormat? {
        if let format, format.sampleRate == sampleRate {
            return format
        }

        if isConfigured {
            player.stop()
            engine.stop()
            engine.disconnectNodeOutput(player)
            engine.disconnectNodeOutput(timePitch)
            scheduledFrames = 0
        } else {
            engine.attach(player)
            engine.attach(timePitch)
            isConfigured = true
        }

        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        ) else {
            return nil
        }

        engine.connect(player, to: timePitch, format: format)
        engine.connect(timePitch, to: engine.mainMixerNode, format: format)
        player.volume = outputVolume
        engine.mainMixerNode.outputVolume = 1
        engine.prepare()
        self.format = format
        return format
    }
}
