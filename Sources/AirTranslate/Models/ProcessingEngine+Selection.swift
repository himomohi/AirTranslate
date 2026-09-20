import Foundation

extension ProcessingEngine {
    var credentialProvider: CredentialProvider? {
        switch self {
        case .apple: nil
        case .openAI: .openAI
        case .gemini: .gemini
        case .meta: .meta
        case .azure: .azure
        case .nari: .nari
        case .qwen: .qwen
        case .grok: .grok
        }
    }

    @MainActor
    func hasRequiredKey(in session: TranslationSessionStore) -> Bool {
        switch self {
        case .apple: true
        case .openAI: session.hasOpenAIAPIKey
        case .gemini: session.hasGeminiAPIKey
        case .meta: session.hasMetaAPIKey
        case .azure: session.hasAzureSpeechAPIKey
        case .nari: session.hasNariAPIKey
        case .qwen: session.hasQwenAPIKey
        case .grok: session.hasGrokAPIKey
        }
    }

    @MainActor
    func canSelect(in session: TranslationSessionStore) -> Bool {
        hasRequiredKey(in: session)
            && !SidebarSessionConfigurationAccess.isLocked(isRunning: session.isRunning, isStarting: session.isStarting)
    }

    @MainActor
    @discardableResult
    func select(in session: TranslationSessionStore) -> Bool {
        guard canSelect(in: session) else { return false }
        // 같은 모드를 다시 누르면 전사/번역 등 기존 세부 설정을 그대로 유지한다.
        guard self != Self.current(for: session) else { return true }
        switch self {
        case .apple: session.useAppleDefaultMode()
        case .openAI: session.useOpenAIMode()
        case .gemini: session.usePreferredGeminiMode()
        case .meta: session.useMetaScribeMode()
        case .azure: session.useAzureMAIMode()
        case .nari: session.useNariSTTMode()
        case .qwen: session.useQwenTranslationMode()
        case .grok: session.useGrokSTTMode()
        }
        return true
    }

    @MainActor
    func requestSettings(in session: TranslationSessionStore) {
        if let credentialProvider {
            session.requestAPIKeySettings(provider: credentialProvider)
        } else {
            session.requestGeneralSettings()
        }
    }
}
