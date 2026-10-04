import Foundation
import CoreMedia
import Testing
@testable import AirTranslate

@Suite(.serialized)
@MainActor
struct AppleTranslationSettingsTests {
    @Test func protectedPhraseRemainsIntactWhenAppliedToCaptionInLongSession() async throws {
        guard AppleTranslationOptions.supportsStrategySelection else { return }
        let fixture = try AppleSettingsFixture()
        defer { fixture.cleanUp() }
        let translated = "Dr. House 방문을 환영합니다."
        let service = AppleTranslationService { _, _ in translated }
        let session = TranslationSessionStore(appleTranslationService: service,
            modelAvailabilityProvider: { _, _ in [:] }, settingsDefaults: fixture.defaults,
            transcriptsDirectoryURL: fixture.directory)
        defer { session.prepareForTermination() }
        session.sourceLanguage = .english
        session.targetLanguage = .korean
        session.isAppleSourceAutoDetectionEnabled = false
        session.isTranscriptPersistenceEnabled = false
        session.isDubbingEnabled = false
        session.sessionDurationMode = .thirtyMinutesOrMore
        session.appleProtectedTermsText = "Dr. House"
        var stages: [String] = []
        session.translationEventForTesting = { stage, _, _ in stages.append(stage) }
        _ = session.activateLiveCallbackPipelineForTesting()
        let text = "Welcome Dr. House."
        session.receiveCaptionForTesting(text, metadata: .init(segmentID: "protected-phrase", revision: 1, isFinal: true,
            audioRange: CMTimeRange(start: .zero, duration: CMTime(seconds: 1, preferredTimescale: 1_000)), sourceText: text, emittedAt: Date()))
        let deadline = ContinuousClock.now + .seconds(3)
        while !stages.contains("translation.apply"), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(2))
        }
        #expect(stages.contains("translation.apply"))
        #expect(session.lines.last?.translatedText == translated)
        #expect(!session.didKeepOriginalForAppleProtectedTerms)
        session.pause()
        #expect(session.isPaused)
        #expect(session.lines.last?.sourceText == text)
        #expect(session.lines.last?.translatedText == translated)
    }

    @Test func longSessionFormattingPreservesProtectedPhraseBeforeAndAfterTranslation() async throws {
        let fixture = try AppleSettingsFixture()
        defer { fixture.cleanUp() }
        fixture.session.sessionDurationMode = .thirtyMinutesOrMore
        fixture.session.appleProtectedTermsText = "Dr. House"
        let source = "Welcome Dr. House to New York."
        let prepared = try await fixture.session.preparedTranslationSourceText(source, language: .english)
        #expect(prepared == source)
        let groups = TranslationSessionStore.translationSegmentGroups(from: prepared, options: fixture.session.appleTranslationOptions)
        #expect(groups.flatMap { $0 }.contains { $0.contains("Dr. House") })
        let translated = "Dr. House 방문을 환영합니다."
        #expect(TranslationSessionStore.organizedTranslationSegment(translated, language: .korean,
            options: fixture.session.appleTranslationOptions) == translated)
        fixture.session.appleProtectedTermsText = ""
        let unprotected = try await fixture.session.preparedTranslationSourceText(source, language: .english)
        #expect(unprotected.contains("Dr.\nHouse"))
    }

    @Test func segmentBoundariesNeverSplitRegisteredMultiwordTerms() {
        let whitespaceBoundary = String(repeating: "a ", count: 118) + "New York"
        let sentenceBoundary = String(repeating: "a ", count: 40) + "Dr. House " + String(repeating: "rest ", count: 40)
        for (text, term) in [(whitespaceBoundary, "New York"), (sentenceBoundary, "Dr. House")] {
            let options = AppleTranslationOptions(protectedTerms: [term])
            let segments = TranslationSessionStore.translationSegmentGroups(from: text, options: options).flatMap { $0 }
            #expect(segments.contains { $0.contains(term) })
            #expect(segments.flatMap { options.protectedRanges(in: $0) }.count == 1)
            let originalSegments = TranslationSessionStore.translationSegmentGroups(from: text).flatMap { $0 }
            #expect(!originalSegments.contains { $0.contains(term) })
        }
    }

    @Test func ignoredProtectedTermIsNotRecordedAsCompletedTranslation() async throws {
        guard AppleTranslationOptions.supportsStrategySelection else { return }
        let fixture = try AppleSettingsFixture()
        defer { fixture.cleanUp() }
        let service = AppleTranslationService { _, _ in "구름이 은행을 덮습니다." }
        let session = TranslationSessionStore(appleTranslationService: service,
            modelAvailabilityProvider: { _, _ in [:] }, settingsDefaults: fixture.defaults,
            transcriptsDirectoryURL: fixture.directory)
        defer { session.prepareForTermination() }
        session.sourceLanguage = .english
        session.targetLanguage = .korean
        session.isAppleSourceAutoDetectionEnabled = false
        session.isTranscriptPersistenceEnabled = false
        session.isDubbingEnabled = false
        session.appleProtectedTermsText = "cloud"
        var stages: [String] = []
        session.translationEventForTesting = { stage, _, _ in stages.append(stage) }
        _ = session.activateLiveCallbackPipelineForTesting()
        let text = "The cloud covers the bank."
        session.receiveCaptionForTesting(text, metadata: .init(segmentID: "protected-term", revision: 1, isFinal: true,
            audioRange: CMTimeRange(start: .zero, duration: CMTime(seconds: 1, preferredTimescale: 1_000)), sourceText: text, emittedAt: Date()))
        let deadline = ContinuousClock.now + .seconds(3)
        while !stages.contains("translation.failed"), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(2))
        }
        #expect(stages.contains("translation.failed"))
        #expect(!stages.contains("translation.result"))
        #expect(!stages.contains("translation.apply"))
        #expect(session.lines.last?.sourceText == text)
        #expect(session.didKeepOriginalForAppleProtectedTerms)
    }

    @Test func settingsPersistAndNormalizeTermsWithoutChangingRealtimeDefault() throws {
        let fixture = try AppleSettingsFixture()
        defer { fixture.cleanUp() }
        #expect(fixture.session.appleTranslationQuality == .realtime)
        #expect(fixture.session.appleProtectedTermsText.isEmpty)
        fixture.session.appleTranslationQuality = .highQuality
        fixture.session.appleProtectedTermsText = " API\napi\nAirTranslate "
        #expect(fixture.session.appleTranslationOptions.normalizedProtectedTerms == ["API", "AirTranslate"])
        let restored = fixture.makeSession()
        defer { restored.prepareForTermination() }
        #expect(restored.appleTranslationQuality == .highQuality)
        #expect(restored.appleProtectedTermsText == " API\napi\nAirTranslate ")
    }

    @Test func runningCaptureRejectsBothPolicyChangesAndPreservesSavedValues() throws {
        let fixture = try AppleSettingsFixture()
        defer { fixture.cleanUp() }
        fixture.session.appleProtectedTermsText = "API"
        _ = fixture.session.activateLiveCallbackPipelineForTesting()
        fixture.session.appleTranslationQuality = .highQuality
        fixture.session.appleProtectedTermsText = "Changed"
        #expect(fixture.session.appleTranslationQuality == .realtime)
        #expect(fixture.session.appleProtectedTermsText == "API")
        let restored = fixture.makeSession()
        defer { restored.prepareForTermination() }
        #expect(restored.appleTranslationQuality == .realtime)
        #expect(restored.appleProtectedTermsText == "API")
    }

    @Test func pendingStartRejectsChangesUntilStopped() throws {
        let fixture = try AppleSettingsFixture()
        defer { fixture.cleanUp() }
        let generation = fixture.session.beginPermissionSuspendedStartForTesting()
        #expect(generation != nil)
        #expect(fixture.session.isStarting)
        fixture.session.appleTranslationQuality = .highQuality
        fixture.session.appleProtectedTermsText = "API"
        #expect(fixture.session.appleTranslationQuality == .realtime)
        #expect(fixture.session.appleProtectedTermsText.isEmpty)
        fixture.session.stop()
        fixture.session.appleTranslationQuality = .highQuality
        fixture.session.appleProtectedTermsText = "API"
        #expect(fixture.session.appleTranslationQuality == .highQuality)
        #expect(fixture.session.appleProtectedTermsText == "API")
    }

    @Test func overlongEditorInputIsBoundedBeforePersistence() throws {
        let fixture = try AppleSettingsFixture()
        defer { fixture.cleanUp() }
        fixture.session.appleProtectedTermsText = String(repeating: "😀", count: 8_010)
        #expect(fixture.session.appleProtectedTermsText.count == 8_000)
        let restored = fixture.makeSession()
        defer { restored.prepareForTermination() }
        #expect(restored.appleProtectedTermsText.count == 8_000)
        #expect(restored.appleTranslationOptions.normalizedProtectedTerms.isEmpty)
    }
}

@MainActor
private final class AppleSettingsFixture {
    let suite = "AppleTranslationSettingsTests.\(UUID().uuidString)"
    let defaults: UserDefaults
    let directory: URL
    lazy var session = makeSession()

    init() throws {
        defaults = try #require(UserDefaults(suiteName: suite))
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func makeSession() -> TranslationSessionStore {
        TranslationSessionStore(
            modelAvailabilityProvider: { _, _ in
                Dictionary(uniqueKeysWithValues: IntelligenceModel.allCases.map {
                    ($0.id, ModelAvailability(state: .installed, detail: "test"))
                })
            },
            settingsDefaults: defaults, transcriptsDirectoryURL: directory
        )
    }

    func cleanUp() {
        session.prepareForTermination()
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: directory)
    }
}
