import Testing
@testable import AirTranslate

@Suite("EmbeddingGemma 설치 확인 수명주기")
struct EmbeddingGemmaModelCheckLifecycleTests {
    @Test func openingDuringCaptureChecksWhenCaptureEnds() {
        var lifecycle = EmbeddingGemmaModelCheckLifecycle()
        lifecycle.appear(isCaptureActive: true)
        let duringCapture = lifecycle.beginIfPossible(isWorking: false)
        #expect(!duringCapture)
        lifecycle.captureChanged(isActive: false)
        let afterCapture = lifecycle.beginIfPossible(isWorking: false)
        #expect(afterCapture)
    }

    @Test func captureEndingBeforeCancellationFinishesRetainsPendingCheck() {
        var lifecycle = EmbeddingGemmaModelCheckLifecycle()
        lifecycle.appear(isCaptureActive: false)
        let initialCheck = lifecycle.beginIfPossible(isWorking: false)
        #expect(initialCheck)
        lifecycle.captureChanged(isActive: true)
        lifecycle.captureChanged(isActive: false)
        let duringCancellation = lifecycle.beginIfPossible(isWorking: true)
        #expect(!duringCancellation)
        lifecycle.finish()
        let afterCancellation = lifecycle.beginIfPossible(isWorking: false)
        #expect(afterCancellation)
        lifecycle.finish()
        let repeatedCheck = lifecycle.beginIfPossible(isWorking: false)
        #expect(!repeatedCheck)
    }

    @Test func cancellationCompletionUsesLatestCaptureState() {
        var lifecycle = EmbeddingGemmaModelCheckLifecycle()
        lifecycle.appear(isCaptureActive: false)
        let initialCheck = lifecycle.beginIfPossible(isWorking: false)
        #expect(initialCheck)
        lifecycle.captureChanged(isActive: true)
        lifecycle.finish()
        let whileCaptureContinues = lifecycle.beginIfPossible(isWorking: false)
        #expect(!whileCaptureContinues)
        lifecycle.captureChanged(isActive: false)
        let afterCapture = lifecycle.beginIfPossible(isWorking: false)
        #expect(afterCapture)
    }

    @Test func hidingSettingsDiscardsRetryAfterCancellation() {
        var lifecycle = EmbeddingGemmaModelCheckLifecycle()
        lifecycle.appear(isCaptureActive: false)
        let initialCheck = lifecycle.beginIfPossible(isWorking: false)
        #expect(initialCheck)
        lifecycle.captureChanged(isActive: true)
        lifecycle.disappear()
        lifecycle.captureChanged(isActive: false)
        lifecycle.finish()
        #expect(!lifecycle.isVisible)
        let hiddenCheck = lifecycle.beginIfPossible(isWorking: false)
        #expect(!hiddenCheck)
    }

    @Test func reopeningWhileCancellationFinishesChecksOnce() {
        var lifecycle = EmbeddingGemmaModelCheckLifecycle()
        lifecycle.appear(isCaptureActive: false)
        let initialCheck = lifecycle.beginIfPossible(isWorking: false)
        #expect(initialCheck)
        lifecycle.disappear()
        lifecycle.appear(isCaptureActive: false)
        let duringCancellation = lifecycle.beginIfPossible(isWorking: true)
        #expect(!duringCancellation)
        lifecycle.finish()
        let afterCancellation = lifecycle.beginIfPossible(isWorking: false)
        #expect(afterCancellation)
        lifecycle.finish()
        let repeatedCheck = lifecycle.beginIfPossible(isWorking: false)
        #expect(!repeatedCheck)
    }

    @Test func completedOrUserCancelledCheckDoesNotRetryMissingModels() {
        var lifecycle = EmbeddingGemmaModelCheckLifecycle()
        lifecycle.appear(isCaptureActive: false)
        let initialCheck = lifecycle.beginIfPossible(isWorking: false)
        #expect(initialCheck)
        lifecycle.finish()
        let afterCompletion = lifecycle.beginIfPossible(isWorking: false)
        #expect(!afterCompletion)
        lifecycle.captureChanged(isActive: true)
        lifecycle.captureChanged(isActive: false)
        let afterLaterCapture = lifecycle.beginIfPossible(isWorking: false)
        #expect(!afterLaterCapture)
    }
}
