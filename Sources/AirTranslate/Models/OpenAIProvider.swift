import Foundation

enum OpenAIProvider: String, CaseIterable, Identifiable {
    case openAI
    case azure

    var id: String { rawValue }

    var title: String {
        switch self {
        case .openAI:
            AppText.openAIProviderOpenAITitle
        case .azure:
            AppText.openAIProviderAzureTitle
        }
    }
}
