import Foundation
import Testing
@testable import AirTranslate

@Suite
struct NariModelSettingsTests {
    @Test
    func selectableModelsUseDocumentedSTTIDsAndIdentifyGAAccess() {
        #expect(Set(NariTranscriptionModel.selectableCases.map(\.rawValue)) == [
            "qwen3-asr:free", "qwen3-asr-fast:free", "qwen3-asr", "qwen3-asr-fast",
        ])
        let allEnabled = NariTranscriptionModel.selectableCases.allSatisfy { $0.isEnabled }
        #expect(allEnabled)
        #expect(!NariTranscriptionModel.off.isEnabled)
        #expect(NariTranscriptionModel.off.apiModelID.isEmpty)
        #expect(!NariTranscriptionModel.qwen3ASRFree.canStart)
        #expect(!NariTranscriptionModel.qwen3ASRFastFree.canStart)
        #expect(NariTranscriptionModel.qwen3ASR.canStart)
        #expect(NariTranscriptionModel.qwen3ASRFast.canStart)
        #expect(NariTranscriptionModel.qwen3ASR.title.contains("GA"))
        #expect(NariTranscriptionModel.qwen3ASRFast.title.contains("GA"))
        #expect(NariTranscriptionModel.qwen3ASR.billingSummary.contains("$0.06"))
        #expect(NariTranscriptionModel.qwen3ASRFast.billingSummary.contains("$0.12"))
    }

    @Test
    func sourceLanguagesMapToNariCodesWithoutAcceptingUnsupportedLanguages() {
        for language in LanguageOption.supported {
            #expect(NariTranscriptionModel.languageCode(for: language) != nil)
        }
        #expect(NariTranscriptionModel.languageCode(for: .english) == "en")
        #expect(NariTranscriptionModel.languageCode(for: .korean) == "ko")
        #expect(NariTranscriptionModel.languageCode(for: language("zh-TW")) == "zh")
        #expect(NariTranscriptionModel.languageCode(for: language("tl_PH")) == "fil")
        #expect(NariTranscriptionModel.languageCode(for: language("yue-HK")) == "yue")
        #expect(NariTranscriptionModel.languageCode(for: language("uk-UA")) == nil)
    }

    @Test
    func nariReadinessRequiresItsOwnKeyAndDoesNotChangeExistingDefault() {
        let missingKey = StartReadinessPolicy.assess(
            requiresOpenAIAPIKey: false, hasOpenAIAPIKey: true,
            requiresNariAPIKey: true, hasNariAPIKey: false,
            requiredLocalModelAvailability: nil
        )
        #expect(missingKey.issue == .nariAPIKeyMissing)
        #expect(!missingKey.canStart)
        #expect(StartReadinessPolicy.assess(
            requiresOpenAIAPIKey: false, hasOpenAIAPIKey: false,
            requiresNariAPIKey: true, hasNariAPIKey: true,
            requiredLocalModelAvailability: nil
        ).canStart)
        #expect(StartReadinessPolicy.assess(
            requiresOpenAIAPIKey: false, hasOpenAIAPIKey: false,
            requiredLocalModelAvailability: nil
        ).canStart)
    }

    private func language(_ id: String) -> LanguageOption {
        .init(id: id, title: id, locale: Locale(identifier: id))
    }
}
