import AirTranslateCore
import Foundation

enum FloatingCaptionPresentationPolicy {
    private static let earlyRevisionWindow: TimeInterval = 0.45
    private static let immediateExtensionCharacterLimit = 28
    private static let minimumDwell: TimeInterval = 1.4
    private static let maximumDwell: TimeInterval = 3.6

    static func canPresentUpdate(
        isImmediateDisplayEnabled: Bool,
        presentedText: String,
        translatedText: String,
        candidateText: String,
        presentedAt: Date,
        now: Date = Date()
    ) -> Bool {
        guard !presentedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return true }
        guard normalized(candidateText) != normalized(presentedText) else { return false }
        guard !isImmediateDisplayEnabled else { return true }

        return canReviseImmediately(
            presentedText: presentedText,
            candidateText: candidateText,
            presentedAt: presentedAt,
            now: now
        ) || canAdvance(
            isImmediateDisplayEnabled: false,
            presentedText: presentedText,
            translatedText: translatedText,
            presentedAt: presentedAt,
            now: now
        )
    }

    static func canAdvance(
        isImmediateDisplayEnabled: Bool,
        presentedText: String,
        translatedText: String,
        presentedAt: Date,
        now: Date = Date()
    ) -> Bool {
        guard !presentedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return true }
        guard !isImmediateDisplayEnabled else { return true }

        return now.timeIntervalSince(presentedAt) >= dwellDuration(
            presentedText: presentedText,
            translatedText: translatedText
        )
    }

    static func dwellDuration(presentedText: String, translatedText: String) -> TimeInterval {
        let sourceLength = normalized(presentedText).count
        let translationLength = normalized(translatedText).count
        let readableLength = max(sourceLength, translationLength)
        let dwell = 1.1 + Double(readableLength) / 32.0
        return min(max(minimumDwell, dwell), maximumDwell)
    }

    private static func canReviseImmediately(
        presentedText: String,
        candidateText: String,
        presentedAt: Date,
        now: Date
    ) -> Bool {
        if now.timeIntervalSince(presentedAt) <= earlyRevisionWindow {
            return true
        }

        let normalizedPresented = normalized(presentedText)
        let normalizedCandidate = normalized(candidateText)
        return normalizedPresented.count < immediateExtensionCharacterLimit
            && TranscriptTextProcessor.isWholeTextPrefix(normalizedPresented, of: normalizedCandidate)
    }

    private static func normalized(_ text: String) -> String {
        TranscriptTextProcessor.normalizedForComparison(text)
    }
}
