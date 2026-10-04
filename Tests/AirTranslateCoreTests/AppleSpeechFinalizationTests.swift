import CoreMedia
import Foundation
import Testing
@testable import AirTranslate

@Suite
struct AppleSpeechFinalizationTests {
    private let now = Date(timeIntervalSinceReferenceDate: 1_000)

    @Test func touchingNewRangeFinalizesAndPreservesThePreviousVolatileText() throws {
        var builder = AppleSpeechRecognitionMetadataBuilder()
        let previousRange = range(start: 0, end: 0.8)
        let nextRange = range(start: 0.8, end: 1.6)
        let first = builder.metadata(
            sourceText: "We need", language: .english, isFinal: false,
            audioRange: previousRange, emittedAt: now, emittedAtUptime: 10
        )

        let finalResult = builder.finalizedPreviousResult(
            before: nextRange, finalizedThrough: time(0.8), language: .english,
            emittedAt: now.addingTimeInterval(1), emittedAtUptime: 11
        )
        let final = try #require(finalResult)
        #expect(final.text == "We need")
        #expect(final.metadata.segmentID == first.segmentID)
        #expect(final.metadata.revision == 2)
        #expect(final.metadata.isFinal)
        #expect(final.metadata.audioRange == previousRange)
        #expect(final.metadata.sourceTextFingerprint == first.sourceTextFingerprint)
        #expect(final.metadata.emittedAt == now.addingTimeInterval(1))
        #expect(final.metadata.emittedAtUptime == 11)
        #expect(builder.finalizedPreviousResult(
            before: nextRange, finalizedThrough: time(0.8), language: .english,
            emittedAt: now.addingTimeInterval(1), emittedAtUptime: 11
        ) == nil)

        let next = builder.metadata(
            sourceText: "more context", language: .english, isFinal: false,
            audioRange: nextRange, emittedAt: now.addingTimeInterval(1), emittedAtUptime: 11
        )
        #expect(next.segmentID != first.segmentID)
        #expect(next.revision == 1)
        #expect(!next.isFinal)
        #expect(builder.trackedSegmentCount == 1)
    }

    @Test func watermarkFinalPreservesLatestCandidatesWithoutLeakingToNextSegment() throws {
        var builder = AppleSpeechRecognitionMetadataBuilder()
        _ = builder.metadata(sourceText: "cash", alternatives: ["cache"], language: .english, isFinal: false,
                             audioRange: range(start: 0, end: 1), emittedAt: now)
        _ = builder.metadata(sourceText: "cash size", alternatives: ["cache size"], language: .english, isFinal: false,
                             audioRange: range(start: 0, end: 1), emittedAt: now)
        let finalized = builder.finalizedPreviousResult(before: range(start: 1, end: 2), finalizedThrough: time(1), language: .english, emittedAt: now)
        let final = try #require(finalized)
        #expect(final.metadata.alternatives == ["cache size"])
        #expect(final.metadata.matchesSourceText("cash size"))
        #expect(!final.metadata.matchesSourceText("cache size"))
        let next = builder.metadata(sourceText: "next", language: .english, isFinal: false,
                                    audioRange: range(start: 1, end: 2), emittedAt: now)
        #expect(next.alternatives.isEmpty)
    }

    @Test func anExplicitFinalIsNotEmittedAgainAtTheNextBoundary() {
        var builder = AppleSpeechRecognitionMetadataBuilder()
        let first = builder.metadata(
            sourceText: "We need", language: .english, isFinal: true,
            audioRange: range(start: 0, end: 0.8), emittedAt: now
        )
        let nextRange = range(start: 0.8, end: 1.6)
        #expect(builder.finalizedPreviousResult(
            before: nextRange, finalizedThrough: time(1.6), language: .english,
            emittedAt: now.addingTimeInterval(1)
        ) == nil)

        let next = builder.metadata(
            sourceText: "more context", language: .english, isFinal: false,
            audioRange: nextRange, emittedAt: now.addingTimeInterval(1)
        )
        #expect(next.segmentID != first.segmentID)
        #expect(next.revision == 1)
    }

    @Test func implicitFinalUsesTheLatestVolatileCorrection() throws {
        var builder = AppleSpeechRecognitionMetadataBuilder()
        _ = builder.metadata(
            sourceText: "We", language: .english, isFinal: false,
            audioRange: range(start: 0, end: 0.4), emittedAt: now
        )
        let latest = builder.metadata(
            sourceText: "We need", language: .english, isFinal: false,
            audioRange: range(start: 0, end: 0.8), emittedAt: now.addingTimeInterval(0.4)
        )
        let finalResult = builder.finalizedPreviousResult(
            before: range(start: 0.8, end: 1.6), finalizedThrough: time(0.8),
            language: .english, emittedAt: now.addingTimeInterval(1)
        )
        let final = try #require(finalResult)
        #expect(final.text == "We need")
        #expect(final.metadata.segmentID == latest.segmentID)
        #expect(final.metadata.revision == 3)
        #expect(final.metadata.audioRange == latest.audioRange)
        #expect(final.metadata.sourceTextFingerprint == latest.sourceTextFingerprint)
    }

    @Test func sameAndOverlappingFinalCorrectionsKeepTheOriginalIdentity() {
        for correctedRange in [
            range(start: 0, end: 0.8),
            range(start: 0, end: 1.6),
            range(start: 0.5, end: 1.6),
            range(start: 0.7995, end: 1.6)
        ] {
            var builder = AppleSpeechRecognitionMetadataBuilder()
            let first = builder.metadata(
                sourceText: "We need", language: .english, isFinal: false,
                audioRange: range(start: 0, end: 0.8), emittedAt: now
            )
            #expect(builder.finalizedPreviousResult(
                before: correctedRange, finalizedThrough: time(1.6), language: .english,
                emittedAt: now.addingTimeInterval(1)
            ) == nil)

            let corrected = builder.metadata(
                sourceText: "We need more context", language: .english, isFinal: true,
                audioRange: correctedRange, emittedAt: now.addingTimeInterval(1)
            )
            #expect(corrected.segmentID == first.segmentID)
            #expect(corrected.revision == 2)
            #expect(corrected.isFinal)
        }
    }

    @Test func finalizationWatermarkMustReachTheWholePreviousRange() throws {
        var builder = AppleSpeechRecognitionMetadataBuilder()
        _ = builder.metadata(
            sourceText: "We need", language: .english, isFinal: false,
            audioRange: range(start: 0, end: 0.8), emittedAt: now
        )
        let nextRange = range(start: 0.8, end: 1.6)
        #expect(builder.finalizedPreviousResult(
            before: nextRange, finalizedThrough: time(0.799999), language: .english,
            emittedAt: now.addingTimeInterval(1)
        ) == nil)
        let finalResult = builder.finalizedPreviousResult(
            before: nextRange, finalizedThrough: time(0.8), language: .english,
            emittedAt: now.addingTimeInterval(1)
        )
        let final = try #require(finalResult)
        #expect(final.text == "We need")
        #expect(final.metadata.revision == 2)
    }

    @Test func subMicrosecondBoundaryRoundingDoesNotLoseThePreviousResult() throws {
        var builder = AppleSpeechRecognitionMetadataBuilder()
        _ = builder.metadata(
            sourceText: "We need", language: .english, isFinal: false,
            audioRange: range(start: 0, end: 0.8), emittedAt: now
        )
        let finalResult = builder.finalizedPreviousResult(
            before: range(start: 0.7999995, end: 1.6), finalizedThrough: time(0.8),
            language: .english, emittedAt: now.addingTimeInterval(1)
        )
        let final = try #require(finalResult)
        #expect(final.text == "We need")
        #expect(final.metadata.isFinal)
    }

    @Test func invalidNextRangesAndTimesDoNotFinalizeOrDiscardPendingText() throws {
        var builder = AppleSpeechRecognitionMetadataBuilder()
        _ = builder.metadata(
            sourceText: "We need", language: .english, isFinal: false,
            audioRange: range(start: 0, end: 0.8), emittedAt: now
        )
        for invalidRange in invalidRanges {
            #expect(builder.finalizedPreviousResult(
                before: invalidRange, finalizedThrough: time(2), language: .english,
                emittedAt: now.addingTimeInterval(1)
            ) == nil)
        }
        let nextRange = range(start: 0.8, end: 1.6)
        for invalidTime in [CMTime.invalid, .indefinite, .positiveInfinity, .negativeInfinity] {
            #expect(builder.finalizedPreviousResult(
                before: nextRange, finalizedThrough: invalidTime, language: .english,
                emittedAt: now.addingTimeInterval(1)
            ) == nil)
        }
        #expect(builder.finalizedPreviousResult(
            before: nextRange, finalizedThrough: time(0.8), language: .english,
            emittedAt: Date(timeIntervalSinceReferenceDate: .infinity), emittedAtUptime: 11
        ) == nil)
        #expect(builder.finalizedPreviousResult(
            before: nextRange, finalizedThrough: time(0.8), language: .english,
            emittedAt: now.addingTimeInterval(1), emittedAtUptime: .nan
        ) == nil)
        let finalResult = builder.finalizedPreviousResult(
            before: nextRange, finalizedThrough: time(0.8), language: .english,
            emittedAt: now.addingTimeInterval(1), emittedAtUptime: 11
        )
        let final = try #require(finalResult)
        #expect(final.text == "We need")
        #expect(final.metadata.revision == 2)
    }

    @Test func missingOrInvalidPreviousRangesCannotBeSynthesizedAsFinal() {
        var emptyBuilder = AppleSpeechRecognitionMetadataBuilder()
        #expect(emptyBuilder.finalizedPreviousResult(
            before: range(start: 0.8, end: 1.6), finalizedThrough: time(1.6),
            language: .english, emittedAt: now
        ) == nil)
        #expect(emptyBuilder.trackedSegmentCount == 0)

        for invalidRange in invalidRanges {
            var builder = AppleSpeechRecognitionMetadataBuilder()
            _ = builder.metadata(
                sourceText: "We need", language: .english, isFinal: false,
                audioRange: invalidRange, emittedAt: now
            )
            #expect(builder.finalizedPreviousResult(
                before: range(start: 0.8, end: 1.6), finalizedThrough: time(1.6),
                language: .english, emittedAt: now.addingTimeInterval(1)
            ) == nil)
        }
    }

    @Test func repeatedImplicitFinalizationKeepsOnlyTheLatestSegment() throws {
        var builder = AppleSpeechRecognitionMetadataBuilder()
        var previous = builder.metadata(
            sourceText: "segment 0", language: .english, isFinal: false,
            audioRange: range(start: 0, end: 1), emittedAt: now
        )
        for index in 1...2_000 {
            let nextRange = range(start: Double(index), end: Double(index + 1))
            let finalResult = builder.finalizedPreviousResult(
                before: nextRange, finalizedThrough: time(Double(index)), language: .english,
                emittedAt: now.addingTimeInterval(Double(index))
            )
            let final = try #require(finalResult)
            #expect(final.text == "segment \(index - 1)")
            #expect(final.metadata.segmentID == previous.segmentID)
            #expect(final.metadata.revision == 2)
            #expect(final.metadata.isFinal)

            let next = builder.metadata(
                sourceText: "segment \(index)", language: .english, isFinal: false,
                audioRange: nextRange, emittedAt: now.addingTimeInterval(Double(index))
            )
            #expect(next.segmentID != previous.segmentID)
            #expect(next.revision == 1)
            #expect(builder.trackedSegmentCount == 1)
            previous = next
        }
    }

    private var invalidRanges: [CMTimeRange] {
        [
            .invalid,
            .zero,
            CMTimeRange(start: time(1), duration: time(-0.2)),
            CMTimeRange(start: .invalid, duration: time(0.8)),
            CMTimeRange(start: .zero, duration: .indefinite),
            CMTimeRange(start: .zero, duration: .positiveInfinity)
        ]
    }

    private func range(start: Double, end: Double) -> CMTimeRange {
        CMTimeRange(start: time(start), duration: time(end - start))
    }

    private func time(_ seconds: Double) -> CMTime {
        CMTime(seconds: seconds, preferredTimescale: 1_000_000_000)
    }
}
