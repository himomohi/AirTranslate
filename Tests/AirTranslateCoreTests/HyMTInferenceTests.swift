import Foundation
import Testing
@testable import AirTranslate

struct HyMTInferenceTests {
    @Test func promptUsesEnglishTargetNameRegardlessOfAppLanguage() {
        let value = HyMTTranslationService.prompt("Hello.", target: .korean)
        #expect(value.hasPrefix("<｜hy_begin▁of▁sentence｜><｜hy_User｜>"))
        #expect(value.contains("Korean"))
        #expect(value.hasSuffix("Hello.<｜hy_Assistant｜>"))
        #expect(!value.contains("hy_System"))
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["AIRTRANSLATE_HYMT_INTEGRATION"] == "1"))
    func installedModelTranslatesLocallyAndReusesResources() async throws {
        _ = try #require(try await HyMTModelStore.shared.installedModel())
        let service = HyMTTranslationService()
        let cold = ContinuousClock.now
        let korean = try await service.translate("Hello. Thank you for joining today's meeting.", source: .english, target: .korean)
        let coldDuration = ContinuousClock.now - cold
        #expect(korean.contains("회의"))
        #expect(korean.contains("감사"))
        let warm = ContinuousClock.now
        let english = try await service.translate("오늘 날씨가 좋습니다.", source: .korean, target: .english)
        let warmDuration = ContinuousClock.now - warm
        #expect(english.lowercased().contains("weather"))
        #expect(english.lowercased().contains("today"))
        print("Hy-MT2 local inference: cold=\(coldDuration), warm=\(warmDuration)")
        print("English → Korean: \(korean)")
        print("Korean → English: \(english)")
        await service.unload()
    }

    @Test func cancellationDoesNotStartLoadingWeights() async {
        let service = HyMTTranslationService()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await service.translate("Hello.", source: .english, target: .korean)
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }
}
