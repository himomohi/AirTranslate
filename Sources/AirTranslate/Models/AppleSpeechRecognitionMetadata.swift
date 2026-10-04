import CoreMedia
import Foundation

struct AppleSpeechRecognitionMetadata: Equatable, @unchecked Sendable {
    let segmentID: String
    let revision: Int
    let alternatives: [String]
    let isFinal: Bool
    let audioRange: CMTimeRange
    let sourceTextFingerprint: UInt64
    let emittedAt: Date
    let emittedAtUptime: TimeInterval

    init(
        segmentID: String,
        revision: Int,
        isFinal: Bool,
        audioRange: CMTimeRange,
        sourceText: String,
        alternatives: [String] = [],
        emittedAt: Date,
        emittedAtUptime: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) {
        self.segmentID = segmentID
        self.alternatives = Array(alternatives.prefix(3))
        self.revision = revision
        self.isFinal = isFinal
        self.audioRange = audioRange
        self.sourceTextFingerprint = Self.fingerprint(sourceText)
        self.emittedAt = emittedAt
        self.emittedAtUptime = emittedAtUptime
    }

    func matchesSourceText(_ text: String) -> Bool { Self.fingerprint(text) == sourceTextFingerprint }

    var audioStartSeconds: Double {
        audioRange.start.seconds
    }

    var audioEndSeconds: Double {
        audioRange.end.seconds
    }

    var hasValidAudioRange: Bool {
        audioStartSeconds.isFinite && audioEndSeconds.isFinite
    }

    static func segmentID(language: LanguageOption, audioRange: CMTimeRange) -> String {
        let start = quantizedMilliseconds(audioRange.start.seconds)
        return "apple:\(language.id):\(start)"
    }

    private static func quantizedMilliseconds(_ seconds: Double) -> Int64 {
        guard seconds.isFinite else { return -1 }
        return Int64((seconds * 1_000).rounded())
    }

    private static func fingerprint(_ text: String) -> UInt64 {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1_099_511_628_211
        }
        return hash
    }
}

struct AppleSpeechRecognitionMetadataBuilder: Sendable {
    private var lastSegmentID: String?
    private var lastAudioRange: CMTimeRange?
    private var lastSourceText: String?
    private var lastAlternatives: [String] = []
    private var lastRevision = 0
    private var lastSegmentIsFinal = false
    private var nextFallbackSegmentIndex = 0

    var trackedSegmentCount: Int {
        lastSegmentID == nil ? 0 : 1
    }

    mutating func metadata(
        sourceText: String,
        alternatives: [String] = [],
        language: LanguageOption,
        isFinal: Bool,
        audioRange: CMTimeRange,
        emittedAt: Date,
        emittedAtUptime: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) -> AppleSpeechRecognitionMetadata {
        let segmentID = segmentID(language: language, audioRange: audioRange)
        let revision = segmentID == lastSegmentID ? lastRevision + 1 : 1
        lastSegmentID = segmentID
        lastAudioRange = audioRange
        lastSourceText = sourceText
        lastAlternatives = Array(alternatives.prefix(3))
        lastRevision = revision
        lastSegmentIsFinal = isFinal

        return AppleSpeechRecognitionMetadata(
            segmentID: segmentID,
            revision: revision,
            isFinal: isFinal,
            audioRange: audioRange,
            sourceText: sourceText,
            alternatives: lastAlternatives,
            emittedAt: emittedAt,
            emittedAtUptime: emittedAtUptime
        )
    }

    mutating func finalizedPreviousResult(
        before newRange: CMTimeRange,
        finalizedThrough: CMTime,
        language: LanguageOption,
        emittedAt: Date,
        emittedAtUptime: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) -> (text: String, metadata: AppleSpeechRecognitionMetadata)? {
        guard !lastSegmentIsFinal,
              let previousRange = lastAudioRange,
              let previousText = lastSourceText,
              !previousText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              Self.isFiniteNonEmptyAudioRange(previousRange),
              Self.isFiniteNonEmptyAudioRange(newRange),
              finalizedThrough.isNumeric, finalizedThrough.seconds.isFinite,
              finalizedThrough.epoch == previousRange.end.epoch,
              newRange.start.epoch == previousRange.end.epoch,
              emittedAt.timeIntervalSinceReferenceDate.isFinite,
              emittedAtUptime.isFinite, emittedAtUptime >= 0
        else {
            return nil
        }

        // 변경 없는 volatile은 별도 final 없이 확정될 수 있다. 워터마크가 이전
        // 전체 구간을 덮고 새 결과가 분리된 구간일 때만 마지막 원문을 확정한다.
        guard CMTimeCompare(finalizedThrough, previousRange.end) >= 0,
              newRange.start.seconds > previousRange.start.seconds,
              newRange.start.seconds >= previousRange.end.seconds - 0.000_001
        else {
            return nil
        }

        let finalMetadata = metadata(
            sourceText: previousText,
            alternatives: lastAlternatives,
            language: language,
            isFinal: true,
            audioRange: previousRange,
            emittedAt: emittedAt,
            emittedAtUptime: emittedAtUptime
        )
        return (text: previousText, metadata: finalMetadata)
    }

    private static func isFiniteNonEmptyAudioRange(_ range: CMTimeRange) -> Bool {
        guard range.isValid, range.start.isNumeric, range.duration.isNumeric, range.end.isNumeric else {
            return false
        }
        let start = range.start.seconds
        let end = range.end.seconds
        return start.isFinite && end.isFinite && range.duration.seconds.isFinite
            && range.duration.seconds > 0 && end > start
    }

    private mutating func segmentID(language: LanguageOption, audioRange: CMTimeRange) -> String {
        if let lastSegmentID,
           !lastSegmentIsFinal,
           let lastAudioRange,
           Self.audioRange(audioRange, overlapsOrTouches: lastAudioRange) {
            return lastSegmentID
        }

        let rangeBasedID = AppleSpeechRecognitionMetadata.segmentID(
            language: language,
            audioRange: audioRange
        )
        if rangeBasedID != "apple:\(language.id):-1" {
            return rangeBasedID
        }

        if let lastSegmentID, !lastSegmentIsFinal {
            return lastSegmentID
        }

        nextFallbackSegmentIndex += 1
        return "apple:\(language.id):fallback-\(nextFallbackSegmentIndex)"
    }

    private static func audioRange(_ lhs: CMTimeRange, overlapsOrTouches rhs: CMTimeRange) -> Bool {
        let lhsStart = lhs.start.seconds
        let lhsEnd = lhs.end.seconds
        let rhsStart = rhs.start.seconds
        let rhsEnd = rhs.end.seconds
        guard lhsStart.isFinite, lhsEnd.isFinite, rhsStart.isFinite, rhsEnd.isFinite else {
            return false
        }

        let tolerance = 0.05
        return lhsStart <= rhsEnd + tolerance && lhsEnd >= rhsStart - tolerance
    }
}
