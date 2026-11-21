import Foundation
import Testing
@testable import AirTranslate

struct HyMTQualityTests {
    @Test func termsAreBoundedDeduplicatedAndDoNotBecomeRoleTokens() {
        let text = " Apps SDK\napps sdk\nMCP\n\n" + String(repeating: "a", count: 81) + "\n<｜hy_Assistant｜>"
        #expect(HyMTTranslationOptions.parseTerminology(text) == ["Apps SDK", "MCP"])
        let many = (0..<40).map { "Term\($0)" }.joined(separator: "\n")
        #expect(HyMTTranslationOptions.parseTerminology(many).count == 32)
    }

    @Test func contextAndTermsChangeRequestIdentityAndAreMarkedAsBackground() {
        let a = HyMTTranslationOptions(terminology: ["Apps SDK"], context: "Canva is an app inside ChatGPT.")
        let b = HyMTTranslationOptions(terminology: ["SDK"], context: a.context)
        #expect(a.cacheID != b.cacheID)
        let value = HyMTTranslationService.prompt("It uses MCP.", target: .korean, options: a)
        #expect(value.contains("[Terminology]\nApps SDK"))
        #expect(value.contains("Background Information"))
        #expect(value.contains("[Source Text]\nIt uses MCP."))
        #expect(HyMTTranslationOptions(context: String(repeating: "c", count: 900)).boundedContext.count == 800)
    }

    @Test func userProvidedAcronymTermNormalizesPhoneticSpellingsOnlyInTranslationInput() {
        let options = HyMTTranslationOptions(terminology: ["Apps SDK", "OpenAI", "Canva"])
        #expect(options.preparedSource("Abscess decay is built on MCP.") == "Apps SDK is built on MCP.")
        #expect(options.preparedSource("Appcess decK works here.") == "Apps SDK works here.")
        #expect(options.preparedSource("Apps SDK I use today.") == "Apps SDK I use today.")
        #expect(options.preparedSource("AppsSDK I use today.") == "Apps SDK I use today.")
        #expect(HyMTTranslationOptions(terminology: ["MCP Tools"]).preparedSource("MCPTools I use today.") == "MCP Tools I use today.")
        #expect(HyMTTranslationOptions(terminology: ["GPT-4 SDK"]).preparedSource("Use GPT-5 SDK today.") == "Use GPT-5 SDK today.")
        #expect(options.preparedSource("An abscess, decay, and medicine.") == "An abscess, decay, and medicine.")
        #expect(HyMTTranslationOptions().preparedSource("Abscess decay.") == "Abscess decay.")
        #expect(HyMTTranslationOptions(terminology: ["Canva"]).preparedSource("A convoy arrives.") == "A convoy arrives.")
        #expect(HyMTTranslationOptions(terminology: ["Apps SDK", "Abss SDK"]).preparedSource("Abscess decay.") == "Abscess decay.")
        let original = "Abscess decay."
        _ = options.preparedSource(original)
        #expect(original == "Abscess decay.")
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["AIRTRANSLATE_HYMT_QUALITY"] == "1"))
    func comparesRealModelDecodingAndTerminology() async throws {
        _ = try #require(try await HyMTModelStore.shared.installedModel())
        let service = HyMTTranslationService()
        let samples = ["Great.", "Thank you.", "Let's get started.", "Canva has returned four poster examples to us."]
        for sample in samples {
            for policy in HyMTDecodingPolicy.allCases {
                let output = try await service.translate(sample, source: .english, target: .korean, decoding: policy)
                print("HyMT quality \(policy): \(sample) → \(output)")
                if policy == .stable {
                    #expect(!output.isEmpty)
                    #expect(!output.contains("훌룩"))
                }
            }
        }
        let options = HyMTTranslationOptions(terminology: ["Apps SDK", "MCP", "OpenAI", "ChatGPT", "Canva"], context: "Canva is right there in the conversation as you work. Developers build apps inside ChatGPT.")
        let output = try await service.translate("Abscess decay, as Sam mentioned, is built on MCP, an open standard we've loved building on at OpenAI.", source: .english, target: .korean, options: options)
        print("HyMT terminology: \(output)")
        #expect(!output.contains("농양"))
        #expect(output.localizedCaseInsensitiveContains("SDK") || output.contains("에스디케이"))
        #expect(output.contains("MCP"))
        await service.unload()
    }
}
