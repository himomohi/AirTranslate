import Foundation

enum StartReadinessIssue: Equatable {
    case openAIAPIKeyMissing
    case geminiAPIKeyMissing
    case azureConfigurationMissing
    case qwenConfigurationMissing
    case grokAPIKeyMissing
    case grokLanguageUnsupported
    case nariAPIKeyMissing
    case nariLanguageUnsupported
    case nariLegacyFreeModelSelected
    case metaAPIKeyMissing
    case localAssetsChecking
    case localAssetsDownloadRequired
    case localAssetsUnavailable(String)
}

struct StartReadinessAssessment: Equatable {
    let issue: StartReadinessIssue?

    var canStart: Bool {
        issue == nil
    }
}

enum StartReadinessPolicy {
    static func assess(
        requiresOpenAIAPIKey: Bool,
        hasOpenAIAPIKey: Bool,
        requiresGeminiAPIKey: Bool = false,
        hasGeminiAPIKey: Bool = false,
        requiresMetaAPIKey: Bool = false,
        hasMetaAPIKey: Bool = false,
        requiresNariAPIKey: Bool = false,
        hasNariAPIKey: Bool = false,
        requiredLocalModelAvailability: ModelAvailability?
    ) -> StartReadinessAssessment {
        if requiresOpenAIAPIKey, !hasOpenAIAPIKey {
            return StartReadinessAssessment(issue: .openAIAPIKeyMissing)
        }
        if requiresGeminiAPIKey, !hasGeminiAPIKey {
            return StartReadinessAssessment(issue: .geminiAPIKeyMissing)
        }
        if requiresMetaAPIKey, !hasMetaAPIKey {
            return StartReadinessAssessment(issue: .metaAPIKeyMissing)
        }
        if requiresNariAPIKey, !hasNariAPIKey {
            return StartReadinessAssessment(issue: .nariAPIKeyMissing)
        }

        guard let requiredLocalModelAvailability else {
            return StartReadinessAssessment(issue: nil)
        }

        switch requiredLocalModelAvailability.state {
        case .installed:
            return StartReadinessAssessment(issue: nil)
        case .checking, .downloading:
            return StartReadinessAssessment(issue: .localAssetsChecking)
        case .downloadRequired:
            return StartReadinessAssessment(issue: .localAssetsDownloadRequired)
        case .unsupported, .unavailable, .failed:
            return StartReadinessAssessment(issue: .localAssetsUnavailable(requiredLocalModelAvailability.detail))
        }
    }
}
