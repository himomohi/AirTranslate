import AVFAudio
import Foundation

final class TranslatedSpeechOutput: NSObject, AVSpeechSynthesizerDelegate, @unchecked Sendable {
    private static let maximumQueuedUtterances = 3
    private static let catchUpRatePerQueuedUtterance: Float = 0.05
    private static let maximumCatchUpRateBoost: Float = 0.12
    private static let allowedSpeechKeyCharacters = CharacterSet.letters
        .union(.decimalDigits)
        .union(.whitespacesAndNewlines)

    private let synthesizer = AVSpeechSynthesizer()
    private let lock = NSLock()
    private var speechVolume: Float = 1
    private var queuedSpeechKeys: Set<String> = []
    private var utteranceKeys: [ObjectIdentifier: String] = [:]

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func setVolume(_ volume: Double) {
        let clamped = Float(min(max(volume, 0), 1))
        lock.withLock {
            speechVolume = clamped
        }
    }

    func speak(_ text: String, language: LanguageOption) {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }
        let speechKey = normalizedSpeechKey(trimmedText, language: language)
        let utterance = AVSpeechUtterance(string: trimmedText)
        utterance.voice = AVSpeechSynthesisVoice(language: language.id)

        let plan: (shouldStopExisting: Bool, volume: Float, backlogDepth: Int)? = lock.withLock {
            guard !queuedSpeechKeys.contains(speechKey) else { return nil }

            var shouldStopExisting = false
            var backlogDepth = queuedSpeechKeys.count
            if backlogDepth > Self.maximumQueuedUtterances {
                // Live interpretation favors the newest text: skip the stale queue
                // instead of letting the synthesizer fall further behind.
                queuedSpeechKeys.removeAll()
                utteranceKeys.removeAll()
                backlogDepth = 0
                shouldStopExisting = true
            }

            queuedSpeechKeys.insert(speechKey)
            utteranceKeys[ObjectIdentifier(utterance)] = speechKey
            return (shouldStopExisting, speechVolume, backlogDepth)
        }
        guard let plan else { return }

        if plan.shouldStopExisting {
            synthesizer.stopSpeaking(at: .word)
        }
        utterance.volume = plan.volume
        utterance.rate = Self.catchUpSpeechRate(backlogDepth: plan.backlogDepth)
        synthesizer.speak(utterance)
    }

    static func catchUpSpeechRate(backlogDepth: Int) -> Float {
        let boost = min(
            catchUpRatePerQueuedUtterance * Float(max(backlogDepth, 0)),
            maximumCatchUpRateBoost
        )
        return AVSpeechUtteranceDefaultSpeechRate + boost
    }

    func stop() {
        lock.withLock {
            queuedSpeechKeys.removeAll()
            utteranceKeys.removeAll()
        }
        synthesizer.stopSpeaking(at: .immediate)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        removeQueuedSpeechKey(for: utterance)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        removeQueuedSpeechKey(for: utterance)
    }

    private func removeQueuedSpeechKey(for utterance: AVSpeechUtterance) {
        lock.withLock {
            if let key = utteranceKeys.removeValue(forKey: ObjectIdentifier(utterance)) {
                queuedSpeechKeys.remove(key)
            }
        }
    }

    private func normalizedSpeechKey(_ text: String, language: LanguageOption) -> String {
        let foldedText = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: language.locale)
        var result = String()
        result.reserveCapacity(foldedText.utf8.count)
        var pendingSpace = false
        for scalar in foldedText.unicodeScalars {
            let isSeparator = CharacterSet.whitespacesAndNewlines.contains(scalar)
                || !Self.allowedSpeechKeyCharacters.contains(scalar)
            if isSeparator {
                if !result.isEmpty { pendingSpace = true }
            } else {
                if pendingSpace {
                    result.append(" ")
                    pendingSpace = false
                }
                result.unicodeScalars.append(scalar)
            }
        }
        return result
    }
}
