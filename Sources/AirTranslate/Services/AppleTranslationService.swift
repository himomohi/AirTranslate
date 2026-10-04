import Foundation
@preconcurrency import Translation

actor AppleTranslationService {
    struct CacheKey: Hashable, Sendable {
        let sourceID: String
        let targetID: String
        let quality: AppleTranslationQuality
    }

    private var availabilityByQuality: [AppleTranslationQuality: LanguageAvailability] = [:]
    private var sessionsByLanguagePair: [CacheKey: TranslationSession] = [:]
    private var availabilityByLanguagePair: [CacheKey: LanguageAvailability.Status] = [:]

    private var realtimeFallbackPairs = Set<String>()
    private(set) var didKeepOriginalForProtectedTerms = false
#if DEBUG
    private var translationForTesting: (@Sendable (String, AppleTranslationOptions) async throws -> String)?
    init(translationForTesting: (@Sendable (String, AppleTranslationOptions) async throws -> String)? = nil) {
        self.translationForTesting = translationForTesting
    }
#endif

    func usesRealtimeFallback(source: LanguageOption, target: LanguageOption) -> Bool {
        realtimeFallbackPairs.contains(Self.pairID(source: source, target: target))
    }

    private nonisolated static func pairID(source: LanguageOption, target: LanguageOption) -> String {
        "\(source.id)\t\(target.id)"
    }

    private func resolvedOptions(_ options: AppleTranslationOptions, source: LanguageOption, target: LanguageOption) -> AppleTranslationOptions {
        guard options.effectiveQuality == .highQuality, usesRealtimeFallback(source: source, target: target) else { return options }
        var fallback = options
        fallback.quality = .realtime
        return fallback
    }

    func prepare(
        source: LanguageOption, target: LanguageOption, model: IntelligenceModel,
        options: AppleTranslationOptions = .init()
    ) async throws {
        let resolved = resolvedOptions(options, source: source, target: target)
        do {
            try await prepareOnce(source: source, target: target, model: model, options: resolved)
        } catch {
            try Task.checkCancellation()
            guard resolved.effectiveQuality == .highQuality, !(error is CancellationError),
                  !(TranslationError.alreadyCancelled ~= error) else { throw error }
            realtimeFallbackPairs.insert(Self.pairID(source: source, target: target))
            var fallback = options
            fallback.quality = .realtime
            try await prepareOnce(source: source, target: target, model: model, options: fallback)
        }
    }

    func translate(
        _ text: String, source: LanguageOption, target: LanguageOption, model: IntelligenceModel,
        options: AppleTranslationOptions = .init()
    ) async throws -> String {
        didKeepOriginalForProtectedTerms = false
        let resolved = resolvedOptions(options, source: source, target: target)
        do {
            let result = try await translateOnce(text, source: source, target: target, model: model, options: resolved)
            return checkedProtectedTerms(result, source: text, options: options)
        } catch {
            try Task.checkCancellation()
            guard resolved.effectiveQuality == .highQuality, !(error is CancellationError),
                  !(TranslationError.alreadyCancelled ~= error) else { throw error }
            // 같은 언어쌍에서 실패한 고품질 모델을 매 문장마다 재호출하지 않는다.
            realtimeFallbackPairs.insert(Self.pairID(source: source, target: target))
            var fallback = options
            fallback.quality = .realtime
            let result = try await translateOnce(text, source: source, target: target, model: model, options: fallback)
            return checkedProtectedTerms(result, source: text, options: options)
        }
    }

    private func checkedProtectedTerms(_ result: String, source: String, options: AppleTranslationOptions) -> String {
        guard AppleTranslationOptions.supportsStrategySelection,
              !options.preservesRegisteredText(source: source, translated: result) else { return result }
        didKeepOriginalForProtectedTerms = true
        return source
    }

    private func prepareOnce(
        source: LanguageOption,
        target: LanguageOption,
        model: IntelligenceModel,
        options: AppleTranslationOptions = .init()
    ) async throws {
        guard model != .appleSpeechOnly else { return }

        let sourceLanguage = Locale.Language(identifier: source.id)
        let targetLanguage = Locale.Language(identifier: target.id)
        let cacheKey = Self.cacheKey(source: source, target: target, options: options)
        let status = try await availabilityStatus(
            source: sourceLanguage,
            target: targetLanguage,
            cacheKey: cacheKey,
            sourceTitle: source.localizedTitle,
            targetTitle: target.localizedTitle
        )
        guard status != .unsupported else {
            throw TranslationServiceError.unsupportedPair(source.localizedTitle, target.localizedTitle)
        }

        let session = translationSession(
            source: sourceLanguage,
            target: targetLanguage,
            cacheKey: cacheKey
        )
        if !(await session.isReady) {
            try await session.prepareTranslation()
        }
    }

    private func translateOnce(
        _ text: String,
        source: LanguageOption,
        target: LanguageOption,
        model: IntelligenceModel,
        options: AppleTranslationOptions = .init()
    ) async throws -> String {
        guard !text.isEmpty else { return text }
        guard model != .appleSpeechOnly else { return text }
#if DEBUG
        if let translationForTesting { return try await translationForTesting(text, options) }
#endif

        let sourceLanguage = Locale.Language(identifier: source.id)
        let targetLanguage = Locale.Language(identifier: target.id)
        let cacheKey = Self.cacheKey(source: source, target: target, options: options)
        let status = try await availabilityStatus(
            source: sourceLanguage,
            target: targetLanguage,
            cacheKey: cacheKey,
            sourceTitle: source.localizedTitle,
            targetTitle: target.localizedTitle
        )

        guard status != .unsupported else {
            throw TranslationServiceError.unsupportedPair(source.localizedTitle, target.localizedTitle)
        }

        let session = translationSession(
            source: sourceLanguage,
            target: targetLanguage,
            cacheKey: cacheKey
        )
        if !(await session.isReady) {
            try await session.prepareTranslation()
        }

        let response: TranslationSession.Response
        if #available(macOS 26.4, *),
           let attributed = options.attributedTextPreservingTerms(in: text) {
            response = try await session.translate(attributed)
        } else {
            response = try await session.translate(text)
        }
        return response.targetText
    }

    nonisolated static func cacheKey(
        source: LanguageOption,
        target: LanguageOption,
        options: AppleTranslationOptions,
        supportsStrategySelection: Bool = AppleTranslationOptions.supportsStrategySelection
    ) -> CacheKey {
        CacheKey(
            sourceID: source.id, targetID: target.id,
            quality: options.effectiveQuality(supportsStrategySelection: supportsStrategySelection)
        )
    }

    private func availabilityStatus(
        source: Locale.Language,
        target: Locale.Language,
        cacheKey: CacheKey,
        sourceTitle: String,
        targetTitle: String
    ) async throws -> LanguageAvailability.Status {
        if let status = availabilityByLanguagePair[cacheKey] {
            return status
        }

        let status = await languageAvailability(quality: cacheKey.quality).status(from: source, to: target)
        availabilityByLanguagePair[cacheKey] = status
        if status == .unsupported {
            throw TranslationServiceError.unsupportedPair(sourceTitle, targetTitle)
        }
        return status
    }

    private func translationSession(
        source: Locale.Language,
        target: Locale.Language,
        cacheKey: CacheKey
    ) -> TranslationSession {
        if let session = sessionsByLanguagePair[cacheKey] {
            return session
        }

        let session: TranslationSession
        if #available(macOS 26.4, *) {
            session = TranslationSession(
                installedSource: source, target: target, preferredStrategy: cacheKey.quality.strategy
            )
        } else {
            session = TranslationSession(installedSource: source, target: target)
        }
        sessionsByLanguagePair[cacheKey] = session
        return session
    }

    private func languageAvailability(quality: AppleTranslationQuality) -> LanguageAvailability {
        if let availability = availabilityByQuality[quality] { return availability }
        let availability: LanguageAvailability
        if #available(macOS 26.4, *) {
            availability = LanguageAvailability(preferredStrategy: quality.strategy)
        } else {
            availability = LanguageAvailability()
        }
        availabilityByQuality[quality] = availability
        return availability
    }
}

enum TranslationServiceError: LocalizedError {
    case unsupportedPair(String, String)
    case protectedTermsNotPreserved

    var errorDescription: String? {
        switch self {
        case let .unsupportedPair(source, target):
            AppText.unsupportedTranslation(source: source, target: target)
        case .protectedTermsNotPreserved:
            AppleTranslationCopy.termsFallback
        }
    }
}
