import Foundation
import Testing
@testable import AirTranslate

@Suite
struct TranslationQualityContextTests {
    @Test
    func glossaryParsesFriendlySeparatorsAndIgnoresInvalidLines() {
        let context = TranslationQualityContext(
            presentationContext: "AI for ecommerce sellers",
            glossaryText: """
            # One source alias per line
            Gary Hong = ゲイリー・ウォン
            Air Translate -> AirTranslate
            AI for Business → ビジネス向けAI
            FBA => FBA
            incomplete line
            """
        )

        #expect(context.glossaryEntries == [
            TranslationGlossaryEntry(source: "Gary Hong", target: "ゲイリー・ウォン"),
            TranslationGlossaryEntry(source: "Air Translate", target: "AirTranslate"),
            TranslationGlossaryEntry(source: "AI for Business", target: "ビジネス向けAI"),
            TranslationGlossaryEntry(source: "FBA", target: "FBA"),
        ])
        #expect(context.sourceTerms == ["Gary Hong", "Air Translate", "AI for Business", "FBA"])
    }

    @Test
    func glossaryAppliesLongerTermsFirstAndMatchesCaseInsensitively() {
        let context = TranslationQualityContext(
            presentationContext: "",
            glossaryText: """
            AI = AI
            AI for Business = ビジネス向けAI
            Gary Hong = ゲイリー・ウォン
            """
        )

        let result = context.applyingTerminology(
            to: "GARY HONG introduces AI for Business."
        )

        #expect(result == "ゲイリー・ウォン introduces ビジネス向けAI.")
    }

    @Test
    func glossaryMatchesWholeTermsWithoutCascadingReplacements() {
        let context = TranslationQualityContext(
            presentationContext: "",
            glossaryText: """
            AI = 人工知能
            人工知能 = AI技術
            C++ = C-plus-plus
            """
        )

        let result = context.applyingTerminology(
            to: "We said paid AI works. 人工知能 and C++ work, but C++20 stays."
        )

        #expect(result == "We said paid 人工知能 works. AI技術 and C-plus-plus work, but C++20 stays.")
    }

    @Test
    func contextAndGlossaryStayWithinCloudInputLimits() {
        let acceptedSource = String(repeating: "S", count: TranslationQualityContext.maximumGlossaryTermCharacters)
        let acceptedTarget = String(repeating: "T", count: TranslationQualityContext.maximumGlossaryTermCharacters)
        let rejectedSource = acceptedSource + "S"
        let context = TranslationQualityContext(
            presentationContext: String(
                repeating: "C",
                count: TranslationQualityContext.maximumPresentationContextCharacters + 1
            ),
            glossaryText: """
            \(acceptedSource) = \(acceptedTarget)
            \(rejectedSource) = target
            """
        )

        #expect(context.presentationContext.count == TranslationQualityContext.maximumPresentationContextCharacters)
        #expect(context.glossaryEntries == [
            TranslationGlossaryEntry(source: acceptedSource, target: acceptedTarget),
        ])
    }

    @Test
    func instructionsAddLiveJapaneseStyleContextAndExactTerminology() {
        let japanese = LanguageOption.supported.first { $0.id == "ja-JP" }!
        let context = TranslationQualityContext(
            presentationContext: "A practical workshop for ecommerce business owners.",
            glossaryText: "Gary Hong = ゲイリー・ウォン"
        )

        let instructions = context.enhancing(
            instructions: "Translate from English to Japanese.",
            target: japanese
        )

        #expect(instructions.contains("live simultaneous interpretation"))
        #expect(instructions.contains("polite, natural Japanese"))
        #expect(instructions.contains("A practical workshop for ecommerce business owners."))
        #expect(instructions.contains("Gary Hong => ゲイリー・ウォン"))
        #expect(instructions.contains("Do not add explanations"))
    }

    @Test
    func presentationDebounceWaitsForClausesButReleasesFinalTextImmediately() {
        #expect(TranslationQualityPolicy.debounceDelay(
            isEnabled: false,
            isFinal: false,
            sourceText: "Today we will discuss AI"
        ) == nil)
        #expect(TranslationQualityPolicy.debounceDelay(
            isEnabled: true,
            isFinal: true,
            sourceText: "Today we will discuss AI"
        ) == 0)
        #expect(TranslationQualityPolicy.debounceDelay(
            isEnabled: true,
            isFinal: false,
            sourceText: "Today we will discuss AI."
        ) == 120)
        #expect(TranslationQualityPolicy.debounceDelay(
            isEnabled: true,
            isFinal: false,
            sourceText: "Today,"
        ) == 240)
        #expect(TranslationQualityPolicy.debounceDelay(
            isEnabled: true,
            isFinal: false,
            sourceText: "Today we will discuss AI"
        ) == 420)
    }
}
