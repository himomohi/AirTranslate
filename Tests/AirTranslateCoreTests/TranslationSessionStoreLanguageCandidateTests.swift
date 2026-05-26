import Foundation
import Testing
@testable import AirTranslate

@Suite
struct TranslationSessionStoreLanguageCandidateTests {
    @Test
    func supportedLanguageOrderIsUsedForAutoDetectionCandidateSelection() {
        let candidates = LanguageOption.prioritizedAutoDetectionCandidates(
            sourceLanguage: LanguageOption.korean,
            targetLanguage: LanguageOption.korean
        )

        #expect(candidates.first == LanguageOption.english)
    }

    @Test
    func targetLanguageIsExcludedFromAutoDetectionCandidates() {
        let candidates = LanguageOption.prioritizedAutoDetectionCandidates(
            sourceLanguage: LanguageOption.korean,
            targetLanguage: LanguageOption.english
        )

        #expect(!candidates.contains(LanguageOption.english))
    }

    @Test
    func targetLanguageIsExcludedWhenManualSourceMatchesTarget() {
        let candidates = LanguageOption.prioritizedAutoDetectionCandidates(
            sourceLanguage: LanguageOption.korean,
            targetLanguage: LanguageOption.korean
        )

        #expect(candidates.first == LanguageOption.english)
        #expect(!candidates.contains(LanguageOption.korean))
    }

    @Test
    func autoDetectionCandidatesIncludeAllNonTargetSupportedLanguagesInSourcePriorityOrder() {
        let candidates = LanguageOption.prioritizedAutoDetectionCandidates(
            sourceLanguage: LanguageOption.korean,
            targetLanguage: LanguageOption.english
        )
        let expected = LanguageOption.supported.filter { $0 != LanguageOption.english }

        #expect(candidates == expected)
        #expect(Set(candidates.map({ $0.id })) == Set(expected.map({ $0.id })))
    }

    @Test
    func everySupportedLanguageIsExcludedWhenItIsTheTarget() {
        for target in LanguageOption.supported {
            let candidates = LanguageOption.prioritizedAutoDetectionCandidates(
                sourceLanguage: LanguageOption.english,
                targetLanguage: target
            )

            #expect(!candidates.contains(target))
            #expect(candidates.count == LanguageOption.supported.count - 1)
        }
    }

    @Test
    func autoDetectionRequestsConfirmationForLanguageChangeAfterSilence() {
        let shouldConfirm = AutoDetectionLanguageChangePolicy.shouldRequestConfirmation(
            isAutoDetectionEnabled: true,
            activeLanguage: LanguageOption.english,
            detectedLanguage: LanguageOption.supported[2],
            confidence: 0.9,
            hadLongSilence: true,
            hasVisibleTranscript: true,
            minimumSwitchConfidence: 0.72
        )

        #expect(shouldConfirm)
    }

    @Test
    func autoDetectionDoesNotRequestConfirmationWithoutSilence() {
        let shouldConfirm = AutoDetectionLanguageChangePolicy.shouldRequestConfirmation(
            isAutoDetectionEnabled: true,
            activeLanguage: LanguageOption.english,
            detectedLanguage: LanguageOption.supported[2],
            confidence: 0.9,
            hadLongSilence: false,
            hasVisibleTranscript: true,
            minimumSwitchConfidence: 0.72
        )

        #expect(!shouldConfirm)
    }

    @Test
    func autoDetectionDoesNotRequestConfirmationForLowConfidenceSwitch() {
        let shouldConfirm = AutoDetectionLanguageChangePolicy.shouldRequestConfirmation(
            isAutoDetectionEnabled: true,
            activeLanguage: LanguageOption.english,
            detectedLanguage: LanguageOption.supported[2],
            confidence: 0.5,
            hadLongSilence: true,
            hasVisibleTranscript: true,
            minimumSwitchConfidence: 0.72
        )

        #expect(!shouldConfirm)
    }

    @Test
    func autoDetectionDoesNotRequestConfirmationForInitialLanguageDetection() {
        let shouldConfirm = AutoDetectionLanguageChangePolicy.shouldRequestConfirmation(
            isAutoDetectionEnabled: true,
            activeLanguage: nil,
            detectedLanguage: LanguageOption.supported[2],
            confidence: 0.9,
            hadLongSilence: true,
            hasVisibleTranscript: false,
            minimumSwitchConfidence: 0.72
        )

        #expect(!shouldConfirm)
    }

    @Test
    func longSessionCaptionLineTrimsDisplayOnly() {
        let text = (1...500)
            .map { "Live transcript line \($0) keeps accumulating during a long session." }
            .joined(separator: "\n")
        let line = CaptionLine(
            sourceText: text,
            translatedText: text,
            createdAt: Date(),
            isFinal: false,
            usesLongSessionDisplay: true
        )

        #expect(line.sourceText == text)
        #expect(line.translatedText == text)
        #expect(line.sourceDisplayText != text)
        #expect(line.translatedDisplayText != text)
        #expect(line.sourceDisplayText.hasPrefix("..."))
        #expect(line.translatedDisplayText.hasPrefix("..."))
    }

    @Test
    @MainActor
    func transcribeOnlyModeHidesTranslationPane() {
        let session = TranslationSessionStore()

        session.selectedModel = .appleSpeechOnly
        #expect(!session.shouldShowTranslationPane)

        session.selectedModel = .appleSystem
        #expect(session.shouldShowTranslationPane)
    }

    @Test
    @MainActor
    func sameLanguagePairSwitchesToTranscribeOnlyMode() {
        let session = TranslationSessionStore()

        session.sourceLanguage = LanguageOption.english
        session.targetLanguage = LanguageOption.english

        #expect(session.liveOutputMode == .transcription)
        #expect(!session.shouldShowTranslationPane)
    }

    @Test
    @MainActor
    func manualTranscribeOnlyModePersistsAcrossLanguageChanges() {
        let session = TranslationSessionStore()

        session.sourceLanguage = LanguageOption.english
        session.targetLanguage = LanguageOption.korean
        session.useTranscribeOnlyMode()
        session.sourceLanguage = LanguageOption.supported[2]

        #expect(session.liveOutputMode == .transcription)
        #expect(!session.shouldShowTranslationPane)
    }

    @Test
    @MainActor
    func sameLanguageAutoTranscribeOnlyRestoresTranslationWhenPairDiffers() {
        let session = TranslationSessionStore()

        session.sourceLanguage = LanguageOption.english
        session.targetLanguage = LanguageOption.english

        #expect(session.liveOutputMode == .transcription)

        session.targetLanguage = LanguageOption.korean

        #expect(session.liveOutputMode == .translation)
        #expect(session.shouldShowTranslationPane)
    }

    @Test
    @MainActor
    func transcribeOnlyModeUsesOriginalOnlyFloatingCaptionsAndRestoresPreviousMode() {
        let session = TranslationSessionStore()

        session.floatingCaptionDisplayMode = .originalAndTranslation
        #expect(session.floatingCaptionDisplayMode == .originalAndTranslation)

        session.useTranscribeOnlyMode()
        #expect(session.floatingCaptionDisplayMode == .original)
        #expect(session.floatingNoticeText == nil)

        session.useTranslationMode()
        #expect(session.floatingCaptionDisplayMode == .originalAndTranslation)
    }
}
