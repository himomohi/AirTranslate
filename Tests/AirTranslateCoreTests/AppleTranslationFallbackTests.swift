import Foundation
import Testing
@preconcurrency import Translation
@testable import AirTranslate

@Suite
struct AppleTranslationFallbackTests {
    private enum Failure: Error { case modelUnavailable }
    private actor Calls {
        var options: [AppleTranslationOptions] = []
        func record(_ value: AppleTranslationOptions) { options.append(value) }
    }

    @Test func nativeIgnoringProtectedTermKeepsOriginalAndReportsIt() async throws {
        guard AppleTranslationOptions.supportsStrategySelection else { return }
        let service = AppleTranslationService { _, _ in "구름이 은행을 덮습니다." }
        let original = "The cloud covers the bank."
        let result = try await service.translate(original, source: .english, target: .korean, model: .appleSystem,
            options: .init(protectedTerms: ["cloud", "bank"]))
        #expect(result == original)
        #expect(await service.didKeepOriginalForProtectedTerms)
        let next = try await service.translate(original, source: .english, target: .korean, model: .appleSystem)
        #expect(next == "구름이 은행을 덮습니다.")
        #expect(!(await service.didKeepOriginalForProtectedTerms))
    }

    @Test func failedHighQualityFallsBackOnceAndKeepsProtectedTerms() async throws {
        guard AppleTranslationOptions.supportsStrategySelection else { return }
        let calls = Calls()
        let service = AppleTranslationService { text, options in
            await calls.record(options)
            if options.quality == .highQuality { throw Failure.modelUnavailable }
            return "translated: " + text
        }
        let options = AppleTranslationOptions(quality: .highQuality, protectedTerms: ["API"])
        let first = try await service.translate("API one", source: .english, target: .korean, model: .appleSystem, options: options)
        let second = try await service.translate("API two", source: .english, target: .korean, model: .appleSystem, options: options)
        #expect(first == "translated: API one" && second == "translated: API two")
        let recorded = await calls.options
        #expect(recorded.map(\.quality) == [.highQuality, .realtime, .realtime])
        #expect(recorded.allSatisfy { $0.protectedTerms == ["API"] })
        #expect(await service.usesRealtimeFallback(source: .english, target: .korean))
        #expect(!(await service.usesRealtimeFallback(source: .korean, target: .english)))
    }

    @Test func cancellationNeverInvokesFallback() async {
        let calls = Calls()
        let service = AppleTranslationService { _, options in
            await calls.record(options)
            throw CancellationError()
        }
        do {
            _ = try await service.translate("API", source: .english, target: .korean, model: .appleSystem, options: .init(quality: .highQuality))
            Issue.record("취소는 결과를 반환하지 않아야 한다")
        } catch is CancellationError {} catch { Issue.record("예상하지 못한 오류: \(error)") }
        #expect(await calls.options.count == 1)
        #expect(!(await service.usesRealtimeFallback(source: .english, target: .korean)))
    }

    @Test func frameworkCancelledSessionNeverInvokesFallback() async {
        let calls = Calls()
        let service = AppleTranslationService { _, options in
            await calls.record(options)
            throw TranslationError.alreadyCancelled
        }
        do {
            _ = try await service.translate("API", source: .english, target: .korean, model: .appleSystem, options: .init(quality: .highQuality))
            Issue.record("취소된 프레임워크 세션은 재시도하지 않아야 한다")
        } catch {}
        #expect(await calls.options.count == 1)
        #expect(!(await service.usesRealtimeFallback(source: .english, target: .korean)))
    }

    @Test func realtimeFailurePropagatesWithoutRetry() async {
        let calls = Calls()
        let service = AppleTranslationService { _, options in
            await calls.record(options)
            throw Failure.modelUnavailable
        }
        do {
            _ = try await service.translate("API", source: .english, target: .korean, model: .appleSystem)
            Issue.record("실패가 호출자에 전달되어야 한다")
        } catch {}
        #expect(await calls.options.count == 1)
        #expect(!(await service.usesRealtimeFallback(source: .english, target: .korean)))
    }

    @Test func successfulHighQualityDoesNotSwitchStrategies() async throws {
        let calls = Calls()
        let service = AppleTranslationService { _, options in
            await calls.record(options)
            return "번역"
        }
        _ = try await service.translate("API", source: .english, target: .korean, model: .appleSystem, options: .init(quality: .highQuality))
        #expect(await calls.options.map(\.quality) == [.highQuality])
        #expect(!(await service.usesRealtimeFallback(source: .english, target: .korean)))
    }
}
