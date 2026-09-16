import Foundation
import Speech
@preconcurrency import Translation

enum ModelAvailabilityChecker {
    static func availability(
        source: LanguageOption,
        target: LanguageOption
    ) async -> [String: ModelAvailability] {
        async let speechStatus = speechAvailability(for: source)
        async let translationStatus = translationAvailability(source: source, target: target)

        let speech = await speechStatus
        let translation = await translationStatus

        return [
            IntelligenceModel.appleSystem.id: combinedAvailability(
                model: .appleSystem,
                speech: speech,
                translation: translation
            ),
            IntelligenceModel.appleOnDevice.id: ModelAvailability(
                state: translation.state,
                detail: AppText.translationModelAvailabilityDetail(
                    source: source.localizedTitle,
                    target: target.localizedTitle,
                    status: translation.state.title
                )
            ),
            IntelligenceModel.appleSpeechOnly.id: ModelAvailability(
                state: speech.state,
                detail: AppText.speechModelAvailabilityDetail(
                    source: source.localizedTitle,
                    status: speech.state.title
                )
            )
        ]
    }

    @MainActor
    static func downloadAssets(
        for model: IntelligenceModel,
        source: LanguageOption,
        target: LanguageOption,
        translationDownloader: @MainActor @Sendable (LanguageOption, LanguageOption) async throws -> Void
    ) async throws {
        switch model {
        case .appleSystem:
            async let speechDownload: Void = downloadSpeechAssets(for: source)
            async let translationDownload: Void = translationDownloader(source, target)
            _ = try await (speechDownload, translationDownload)
        case .appleOnDevice:
            try await translationDownloader(source, target)
        case .appleSpeechOnly:
            try await downloadSpeechAssets(for: source)
        }
    }

    private static func combinedAvailability(
        model: IntelligenceModel,
        speech: ModelAvailability,
        translation: ModelAvailability
    ) -> ModelAvailability {
        let state = combinedState([speech.state, translation.state])
        return ModelAvailability(
            state: state,
            detail: AppText.combinedModelAvailabilityDetail(
                model: model.title,
                speechStatus: speech.state.title,
                translationStatus: translation.state.title
            )
        )
    }

    static func openAIAvailability() -> ModelAvailability {
        let hasAPIKey = OpenAIAPIKeyStore.hasAPIKey()
        return ModelAvailability(
            state: hasAPIKey ? .installed : .unavailable,
            detail: AppText.openAIModelAvailabilityDetail(hasAPIKey: hasAPIKey)
        )
    }

    private static func combinedState(_ states: [ModelAvailabilityState]) -> ModelAvailabilityState {
        if states.contains(.failed) { return .failed }
        if states.contains(.unavailable) { return .unavailable }
        if states.contains(.unsupported) { return .unsupported }
        if states.contains(.downloading) { return .downloading }
        if states.allSatisfy({ $0 == .installed }) { return .installed }
        return .downloadRequired
    }

    private static func speechAvailability(for language: LanguageOption) async -> ModelAvailability {
        guard SpeechTranscriber.isAvailable else {
            return ModelAvailability(
                state: .unavailable,
                detail: AppText.speechModelAvailabilityDetail(
                    source: language.localizedTitle,
                    status: ModelAvailabilityState.unavailable.title
                )
            )
        }

        guard let supportedLocale = await SpeechTranscriber.supportedLocale(equivalentTo: language.locale) else {
            return ModelAvailability(
                state: .unsupported,
                detail: AppText.speechModelAvailabilityDetail(
                    source: language.localizedTitle,
                    status: ModelAvailabilityState.unsupported.title
                )
            )
        }

        let transcriber = SpeechTranscriber(locale: supportedLocale, preset: .progressiveTranscription)
        let status = await AssetInventory.status(forModules: [transcriber])

        return ModelAvailability(
            state: availabilityState(for: status),
            detail: AppText.speechModelAvailabilityDetail(
                source: language.localizedTitle,
                status: availabilityState(for: status).title
            )
        )
    }

    private static func downloadSpeechAssets(for language: LanguageOption) async throws {
        guard let supportedLocale = await SpeechTranscriber.supportedLocale(equivalentTo: language.locale) else {
            return
        }

        let transcriber = SpeechTranscriber(locale: supportedLocale, preset: .progressiveTranscription)
        guard let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) else {
            return
        }

        try await request.downloadAndInstall()
    }

    private static func translationAvailability(
        source: LanguageOption,
        target: LanguageOption
    ) async -> ModelAvailability {
        let availability = LanguageAvailability()
        let status = await availability.status(
            from: Locale.Language(identifier: source.id),
            to: Locale.Language(identifier: target.id)
        )
        let state = availabilityState(for: status)

        return ModelAvailability(
            state: state,
            detail: AppText.translationModelAvailabilityDetail(
                source: source.localizedTitle,
                target: target.localizedTitle,
                status: state.title
            )
        )
    }

    private static func availabilityState(
        for status: AssetInventory.Status
    ) -> ModelAvailabilityState {
        switch status {
        case .installed:
            .installed
        case .downloading:
            .downloading
        case .supported:
            .downloadRequired
        case .unsupported:
            .unsupported
        @unknown default:
            .failed
        }
    }

    private static func availabilityState(
        for status: LanguageAvailability.Status
    ) -> ModelAvailabilityState {
        switch status {
        case .installed:
            .installed
        case .supported:
            .downloadRequired
        case .unsupported:
            .unsupported
        @unknown default:
            .failed
        }
    }
}
