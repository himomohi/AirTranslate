import Foundation
import Testing
@preconcurrency import Translation
@testable import AirTranslate

@Suite
struct AppleTranslationOptionsTests {
    @Test func defaultsKeepRealtimeStringTranslation() {
        let options = AppleTranslationOptions()
        #expect(options.quality == .realtime)
        #expect(options.normalizedProtectedTerms.isEmpty)
        #expect(options.protectedRanges(in: "Translate this sentence.").isEmpty)
        if #available(macOS 26.4, *) {
            #expect(options.attributedTextPreservingTerms(in: "Translate this sentence.") == nil)
            #expect(options.quality.strategy == .lowLatency)
            #expect(AppleTranslationQuality.highQuality.strategy == .highFidelity)
        }
    }

    @Test func parserTrimsLinesAndKeepsFirstSpellingOfCaseInsensitiveDuplicates() {
        #expect(AppleTranslationOptions.parseProtectedTerms("  AirTranslate \r\nAPI\napi\n\t\n한국어\r한국어\nAIRTRANSLATE")
            == ["AirTranslate", "API", "한국어"])
    }

    @Test func parserRejectsOverlongTermsAndLimitsDistinctEntries() {
        let eighty = String(repeating: "가", count: 80)
        let eightyOne = String(repeating: "나", count: 81)
        let numbered = (1...110).map { "Term \($0)" }
        let parsed = AppleTranslationOptions.parseProtectedTerms(([eightyOne, eighty, eighty] + numbered).joined(separator: "\n"))
        #expect(parsed.count == 100)
        #expect(parsed.first == eighty)
        #expect(parsed.last == "Term 99")
        #expect(!parsed.contains(eightyOne))
    }

    @Test func directOptionsCannotBypassNormalizationOrLengthLimits() {
        let options = AppleTranslationOptions(protectedTerms: [" API ", "api", "", "two\nlines", String(repeating: "x", count: 81)])
        #expect(options.normalizedProtectedTerms == ["API"])
    }

    @Test func latinTermsRespectUnicodeWordBoundariesAndPreserveCase() {
        let text = "API api Api capital capi APIClient XAPI API2 2API _API API_ API's API. αAPIβ ١API"
        let options = AppleTranslationOptions(protectedTerms: ["API"])
        #expect(matches(options, in: text) == ["API", "api", "Api", "API", "API"])
    }

    @Test func latinTermsCanBorderKoreanChineseAndJapaneseText() {
        let text = "API를 中文API APIカナ"
        #expect(matches(.init(protectedTerms: ["API"]), in: text) == ["API", "API", "API"])
    }

    @Test func cjkTermsMatchWithoutSpacesAndLongerTermsWin() {
        let text = "한국한국어東京都"
        let options = AppleTranslationOptions(protectedTerms: ["한국", "한국어", "東京"])
        #expect(matches(options, in: text) == ["한국", "한국어", "東京"])
    }

    @Test func multiwordTermsPreventOverlappingShorterMatches() {
        let options = AppleTranslationOptions(protectedTerms: ["York", "New", "New York"])
        #expect(matches(options, in: "New York, new york and York.") == ["New York", "new york", "York"])
    }

    @Test func rejectedOverlapDoesNotHideLaterValidOccurrence() {
        let options = AppleTranslationOptions(protectedTerms: ["가가나", "나나나"])
        let text = "가가나나나나"
        #expect(matches(options, in: text) == ["가가나", "나나나"])
        let ranges = options.protectedRanges(in: text)
        #expect(ranges.count == 2)
        #expect(ranges[0].upperBound == ranges[1].lowerBound)
    }

    @Test func matchingDoesNotSplitEmojiGraphemes() {
        let options = AppleTranslationOptions(protectedTerms: ["👩"])
        #expect(matches(options, in: "👩‍💻 👩🏽 👩") == ["👩"])
    }

    @Test func canonicalAccentMatchesKeepOriginalUnicodeRepresentation() {
        let text = "CAFÉ cafe\u{301} café"
        let options = AppleTranslationOptions(protectedTerms: ["café"])
        let found = matches(options, in: text)
        #expect(found.count == 3)
        #expect(found[1].utf8.elementsEqual("cafe\u{301}".utf8))
    }

    @Test func attributedProtectionMarksOnlyMatchedRangesWithoutChangingText() throws {
        guard #available(macOS 26.4, *) else { return }
        let text = "Use aPi and cafe\u{301}, then capital and 한국어."
        let options = AppleTranslationOptions(protectedTerms: ["API", "café", "한국어"])
        let attributed = try #require(options.attributedTextPreservingTerms(in: text))
        #expect(String(attributed.characters).utf8.elementsEqual(text.utf8))
        let protected = attributed.runs.compactMap { run in
            run.skipsTranslation == true ? String(attributed[run.range].characters) : nil
        }
        #expect(protected == ["aPi", "cafe\u{301}", "한국어"])
        #expect(attributed.runs.contains { $0.skipsTranslation != true })
    }

    @Test func registeredButUnmatchedTermsKeepStringFastPath() {
        guard #available(macOS 26.4, *) else { return }
        let options = AppleTranslationOptions(protectedTerms: ["API"])
        #expect(options.attributedTextPreservingTerms(in: "The capital city.") == nil)
    }

    @Test func outputValidationChecksSpellingCountsAndNonOverlappingTerms() {
        let options = AppleTranslationOptions(protectedTerms: ["API", "New York", "York"])
        #expect(options.preservesRegisteredText(source: "API in New York and York", translated: "New York 및 York의 API"))
        #expect(!options.preservesRegisteredText(source: "API API", translated: "API 한 번"))
        #expect(!options.preservesRegisteredText(source: "API", translated: "api"))
        #expect(!options.preservesRegisteredText(source: "API", translated: "APIClient"))
        #expect(options.preservesRegisteredText(source: "API", translated: "API를 확인"))
        #expect(!options.preservesRegisteredText(source: "New York and York", translated: "New York"))
        #expect(options.preservesRegisteredText(source: "Nothing registered", translated: "등록된 용어 없음"))
    }

    @Test func oldOSResolvesBothQualitiesToExistingRealtimeBehavior() {
        let options = AppleTranslationOptions(quality: .highQuality, protectedTerms: ["API"])
        #expect(options.effectiveQuality(supportsStrategySelection: false) == .realtime)
        #expect(options.effectiveQuality(supportsStrategySelection: true) == .highQuality)
    }

    @Test func strategyAwareCacheSeparatesQualitiesAndLanguageDirections() {
        let realtime = cacheKey(.init(), supportsStrategySelection: true)
        let highQuality = cacheKey(.init(quality: .highQuality), supportsStrategySelection: true)
        let reverse = AppleTranslationService.cacheKey(
            source: .korean, target: .english, options: .init(), supportsStrategySelection: true
        )
        let statuses: [AppleTranslationService.CacheKey: LanguageAvailability.Status] = [
            realtime: .installed, highQuality: .supported, reverse: .unsupported
        ]
        #expect(statuses.count == 3)
        #expect(statuses[realtime] == .installed)
        #expect(statuses[highQuality] == .supported)
        #expect(statuses[reverse] == .unsupported)
    }

    @Test func sessionCacheIgnoresPerRequestTermsAndCollapsesUnsupportedStrategy() {
        let realtime = cacheKey(.init(), supportsStrategySelection: true)
        let withTerms = cacheKey(.init(protectedTerms: ["API"]), supportsStrategySelection: true)
        #expect(realtime == withTerms)
        #expect(cacheKey(.init(quality: .highQuality), supportsStrategySelection: false)
            == cacheKey(.init(), supportsStrategySelection: false))
        #expect(cacheKey(.init(quality: .highQuality), supportsStrategySelection: true) != realtime)
    }

    private func matches(_ options: AppleTranslationOptions, in text: String) -> [String] {
        options.protectedRanges(in: text).map { String(text[$0]) }
    }

    private func cacheKey(_ options: AppleTranslationOptions, supportsStrategySelection: Bool) -> AppleTranslationService.CacheKey {
        AppleTranslationService.cacheKey(
            source: .english, target: .korean, options: options,
            supportsStrategySelection: supportsStrategySelection
        )
    }
}
