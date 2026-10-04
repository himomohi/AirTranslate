import AppKit
import Foundation
import Testing
@testable import AirTranslate

@Suite
struct CaptureControlStateTests {
    @Test func ordinaryCaptureAndPauseOfferOnlyTheApplicableAction() {
        let running = CaptureControlState(isRunning: true, isStarting: false, isPaused: false)
        #expect(running.canPause)
        #expect(!running.canResume)
        #expect(running.canTogglePause)

        let paused = CaptureControlState(isRunning: true, isStarting: false, isPaused: true)
        #expect(!paused.canPause)
        #expect(paused.canResume)
        #expect(paused.canTogglePause)
    }

    @Test func finishingOverridesPausedPresentationUntilTheSessionEnds() {
        var state = CaptureControlState(
            isRunning: true, isStarting: false, isPaused: true, isFinishing: true
        )
        #expect(state.phase == .finishing)
        #expect(state.phase.showsProgress)
        #expect(state.phase.actionTitle == AppText.finishingCapture)
        #expect(state.statusTitle(statusMessage: "Finalizing translation") == "Finalizing translation")
        #expect(!state.canPause && !state.canResume && !state.canToggleCapture)

        state = CaptureControlState(isRunning: false, isStarting: false, isPaused: false)
        #expect(state.phase == .idle)
        #expect(state.phase.actionTitle == AppText.start)
        #expect(state.canToggleCapture && !state.canTogglePause)
    }

    @Test func preparingCanBeCancelledAndStartedAgain() {
        let preparing = CaptureControlState(isRunning: false, isStarting: true, isPaused: false)
        #expect(preparing.phase == .starting)
        #expect(preparing.phase.actionTitle == AppText.cancel)
        #expect(preparing.canToggleCapture && !preparing.canTogglePause)
        #expect(preparing.statusTitle(statusMessage: "Preparing capture") == "Preparing capture")

        let cancelled = CaptureControlState(isRunning: false, isStarting: false, isPaused: false)
        #expect(cancelled.phase.actionTitle == AppText.start)
        #expect(cancelled.canToggleCapture)

        let restarted = CaptureControlState(isRunning: false, isStarting: true, isPaused: false)
        #expect(restarted.phase.actionTitle == AppText.cancel)
    }

    @Test func ordinarySilenceDoesNotOverrideListeningWithAWarning() {
        let state = CaptureControlState(isRunning: true, isStarting: false, isPaused: false)
        #expect(state.statusTitle(statusMessage: "Silent input; check permissions") == AppText.listening)
        #expect(state.phase == .running)
    }

    @Test @MainActor
    func everyProviderTransitionIsIncludedInTheSharedSessionAdapter() {
        let suiteName = "CaptureControlStateTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let session = TranslationSessionStore(
            modelAvailabilityProvider: { _, _ in [:] }, settingsDefaults: defaults
        )
        session.isRunning = true
        let finishingFlags: [ReferenceWritableKeyPath<TranslationSessionStore, Bool>] = [
            \.isFinishingAzureMAI, \.isFinishingNariSTT,
            \.isFinishingGrokSTT, \.isFinishingQwenTranslation
        ]
        for flag in finishingFlags {
            session[keyPath: flag] = true
            for paused in [false, true] {
                session.isPaused = paused
                #expect(session.captureControlState.phase == .finishing)
                #expect(!session.captureControlState.canTogglePause)
                #expect(!session.captureControlState.canToggleCapture)
            }
            session[keyPath: flag] = false
        }

        let reconnectingFlags: [ReferenceWritableKeyPath<TranslationSessionStore, Bool>] = [
            \.isReconnectingQwenTranslation, \.isReconnectingNariSTT, \.isReconnectingGrokSTT
        ]
        session.isPaused = true
        for flag in reconnectingFlags {
            session[keyPath: flag] = true
            #expect(session.captureControlState.phase == .reconnecting)
            #expect(session.captureControlState.phase.actionTitle == AppText.cancel)
            #expect(!session.captureControlState.canResume)
            #expect(session.captureControlState.canToggleCapture)
            #expect(session.captureControlState.statusTitle(statusMessage: "Reconnecting") == "Reconnecting")
            session[keyPath: flag] = false
            #expect(session.captureControlState.phase == .paused)
            #expect(session.captureControlState.canResume)
        }
        session.isRunning = false
        session.isPaused = false
        #expect(session.captureControlState.phase == .idle)
    }
}

@Suite
struct CaptionFeedFollowStateTests {
    @Test func captionGrowthDoesNotPretendTheUserScrolledAway() {
        var state = CaptionFeedFollowState()
        state.updateLatestVisibility(false)
        #expect(state.isFollowingLatest)
        #expect(state.shouldFollowUpdates)
    }

    @Test func readingBackPausesFollowingUntilTheUserReturnsToLatest() {
        var state = CaptionFeedFollowState()
        state.setUserScrolling(true)
        state.updateLatestVisibility(false)
        #expect(!state.shouldFollowUpdates)
        state.setUserScrolling(false)
        #expect(!state.isFollowingLatest)

        state.updateLatestVisibility(false)
        #expect(!state.shouldFollowUpdates)
        state.returnToLatest()
        #expect(state.isFollowingLatest)
        #expect(state.shouldFollowUpdates)
        state.updateLatestVisibility(true)
        state.updateLatestVisibility(false)
        #expect(state.shouldFollowUpdates)
    }

    @Test func manuallyScrollingToTheBottomAlsoResumesFollowing() {
        var state = CaptionFeedFollowState()
        state.setUserScrolling(true)
        state.updateLatestVisibility(false)
        state.setUserScrolling(false)
        state.setUserScrolling(true)
        state.updateLatestVisibility(true)
        #expect(!state.shouldFollowUpdates)
        state.setUserScrolling(false)
        #expect(state.shouldFollowUpdates)
    }
}

@Suite
struct CaptionFeedViewportStateTests {
    @Test func readingPositionSurvivesRemountAndEarlierCaptionHeightChanges() throws {
        let first = UUID()
        let reading = UUID()
        var viewport = CaptionFeedViewportState()
        viewport.followState.setUserScrolling(true)
        viewport.followState.updateLatestVisibility(false)
        viewport.recordReadingPosition(offsetY: 275, lineFrames: [
            first: CGRect(x: 0, y: 0, width: 500, height: 200),
            reading: CGRect(x: 0, y: 200, width: 500, height: 300)
        ])
        viewport.followState.suspendInteraction()

        // 숨겨진 동안 피드가 사라져도 창에 남아 있는 상태로 새 피드를 복원한다.
        let restored = try #require(viewport.restorationAnchor)
        let changedLayout = [
            first: CGRect(x: 0, y: 0, width: 500, height: 450),
            reading: CGRect(x: 0, y: 450, width: 500, height: 300)
        ]
        let metrics = CaptionFeedScrollMetrics(offsetY: 0, minimumY: 0, maximumY: 1_000)
        #expect(restored.lineID == reading)
        #expect(restored.resolvedOffset(in: changedLayout, metrics: metrics) == 525)
        #expect(!viewport.followState.isFollowingLatest)
        #expect(!viewport.followState.shouldFollowUpdates)
    }

    @Test func liveFollowerStillReturnsToLatestAfterRemount() {
        var viewport = CaptionFeedViewportState()
        viewport.followState.setUserScrolling(true)
        viewport.followState.updateLatestVisibility(true)
        viewport.followState.suspendInteraction()
        #expect(viewport.followState.shouldFollowUpdates)
        #expect(viewport.restorationAnchor == nil)
    }

    @Test func expiredAnchorUsesOldestRemainingCaptionWithoutEnablingFollow() throws {
        let expired = UUID()
        var viewport = CaptionFeedViewportState()
        viewport.followState.setUserScrolling(true)
        viewport.followState.updateLatestVisibility(false)
        viewport.recordReadingPosition(offsetY: 80, lineFrames: [
            expired: CGRect(x: 0, y: 24, width: 500, height: 300)
        ])
        viewport.followState.suspendInteraction()
        let anchor = try #require(viewport.restorationAnchor)
        let remaining = [
            UUID(): CGRect(x: 0, y: 24, width: 500, height: 300),
            UUID(): CGRect(x: 0, y: 332, width: 500, height: 300)
        ]
        let metrics = CaptionFeedScrollMetrics(offsetY: 400, minimumY: 0, maximumY: 500)
        #expect(anchor.resolvedOffset(in: remaining, metrics: metrics) == 24)
        #expect(!viewport.followState.shouldFollowUpdates)
    }

    @Test func windowsKeepIndependentReadingPositionsAndExplicitLatestClearsTheAnchor() {
        var readingWindow = CaptionFeedViewportState()
        let otherWindow = CaptionFeedViewportState()
        readingWindow.followState.setUserScrolling(true)
        readingWindow.followState.updateLatestVisibility(false)
        readingWindow.recordReadingPosition(offsetY: 100, lineFrames: [
            UUID(): CGRect(x: 0, y: 24, width: 500, height: 300)
        ])
        #expect(readingWindow.restorationAnchor != nil)
        #expect(otherWindow.followState.shouldFollowUpdates)
        #expect(otherWindow.restorationAnchor == nil)
        readingWindow.returnToLatest()
        #expect(readingWindow.restorationAnchor == nil)
        #expect(readingWindow.followState.shouldFollowUpdates)
    }
}

@Suite
struct MainCaptionWindowVisibilityTests {
    @Test @MainActor
    func windowRegistryIncludesOnlyAttachedMainObservers() {
        _ = NSApplication.shared
        let mainWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 400),
            styleMask: [], backing: .buffered, defer: true
        )
        let unrelatedWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 200),
            styleMask: [], backing: .buffered, defer: true
        )
        let observer = MainCaptionVisibilityView()
        mainWindow.contentView = observer
        defer {
            mainWindow.contentView = nil
            observer.stopObserving()
        }

        #expect(MainCaptionVisibilityView.attachedMainWindows.contains { $0 === mainWindow })
        #expect(!MainCaptionVisibilityView.attachedMainWindows.contains { $0 === unrelatedWindow })
        mainWindow.contentView = nil
        #expect(!MainCaptionVisibilityView.attachedMainWindows.contains { $0 === mainWindow })
    }

    @Test func hiddenMinimizedAndOccludedWindowsSuspendThenResumeRendering() {
        #expect(visibility())
        #expect(!visibility(isWindowAttached: false))
        #expect(!visibility(isVisible: false))
        #expect(!visibility(isMiniaturized: true))
        #expect(!visibility(isOcclusionVisible: false))
        #expect(!visibility(isApplicationHidden: true))
        #expect(visibility())
    }

    @Test func eachVisibleWindowRendersWithoutAnAppActivationRequirement() {
        // 앱/키 창 활성 상태는 정책의 입력이 아니다. 각 창의 가시성만 독립적으로 판단한다.
        let hiddenWindow = visibility(isVisible: false)
        let visibleWindow = visibility()
        #expect(!hiddenWindow)
        #expect(visibleWindow)
    }

    private func visibility(
        isWindowAttached: Bool = true,
        isVisible: Bool = true,
        isMiniaturized: Bool = false,
        isOcclusionVisible: Bool = true,
        isApplicationHidden: Bool = false
    ) -> Bool {
        MainCaptionWindowVisibility.shouldRender(
            isWindowAttached: isWindowAttached,
            isVisible: isVisible,
            isMiniaturized: isMiniaturized,
            isOcclusionVisible: isOcclusionVisible,
            isApplicationHidden: isApplicationHidden
        )
    }
}
