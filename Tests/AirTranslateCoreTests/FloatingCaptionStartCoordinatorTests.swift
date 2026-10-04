import Foundation
import Observation
import Testing
@testable import AirTranslate

@Suite
@MainActor
struct FloatingCaptionStartCoordinatorTests {
    @Test func idleSelectionStartsOnceAndMinimizesOnlyAfterListeningBegins() async throws {
        let fixture = Fixture(.idle)
        fixture.coordinator.begin()
        #expect(fixture.startCount == 1)
        #expect(fixture.state.phase == .starting)
        #expect(fixture.minimizeCount == 0)
        fixture.coordinator.begin()
        #expect(fixture.startCount == 1)

        fixture.state.phase = .running
        try await fixture.waitForPresentation()
        #expect(fixture.minimizeCount == 1)
        #expect(fixture.showMainCount == 0)
    }

    @Test func pausedSelectionResumesWithoutStartingANewSession() {
        let fixture = Fixture(.paused)
        fixture.coordinator.begin()
        #expect(fixture.resumeCount == 1)
        #expect(fixture.startCount == 0)
        #expect(fixture.minimizeCount == 1)
    }

    @Test func alreadyRunningSelectionDoesNotRestartCapture() {
        let fixture = Fixture(.running)
        fixture.coordinator.begin()
        #expect(fixture.startCount == 0)
        #expect(fixture.resumeCount == 0)
        #expect(fixture.minimizeCount == 1)
    }

    @Test(arguments: [MenuBarCapturePhase.starting, .reconnecting])
    func ongoingStartAndReconnectAreNotDuplicated(_ phase: MenuBarCapturePhase) async throws {
        let fixture = Fixture(phase)
        fixture.coordinator.begin()
        #expect(fixture.startCount == 0)
        #expect(fixture.resumeCount == 0)
        #expect(fixture.minimizeCount == 0)
        fixture.state.phase = .running
        try await fixture.waitForPresentation()
        #expect(fixture.minimizeCount == 1)
    }

    @Test func synchronousReadinessFailureKeepsRecoveryVisible() {
        let fixture = Fixture(.idle)
        fixture.rejectsStart = true
        fixture.coordinator.begin()
        #expect(fixture.startCount == 1)
        #expect(fixture.minimizeCount == 0)
        #expect(fixture.showMainCount == 1)
    }

    @Test func asynchronousPermissionFailureKeepsRecoveryVisible() async throws {
        let fixture = Fixture(.idle)
        fixture.coordinator.begin()
        fixture.state.phase = .idle
        try await fixture.waitForPresentation()
        #expect(fixture.minimizeCount == 0)
        #expect(fixture.showMainCount == 1)
    }

    @Test func cancelledViewRequestCannotHideWindowAfterLateStartSuccess() async throws {
        let fixture = Fixture(.starting)
        fixture.coordinator.begin()
        fixture.state.phase = .running
        // 이미 큐에 들어간 관찰 콜백도 창 닫기·함께 보기·메인 열기에 따라 취소된다.
        fixture.coordinator.cancel()
        try await Task.sleep(for: .milliseconds(30))
        #expect(fixture.minimizeCount == 0)
        #expect(fixture.showMainCount == 0)
    }

    @Test func oldRequestCannotOverrideANewerRequest() async throws {
        let fixture = Fixture(.starting)
        fixture.coordinator.begin()
        fixture.state.phase = .running
        fixture.coordinator.cancel()
        fixture.coordinator.begin()
        try await Task.sleep(for: .milliseconds(30))
        #expect(fixture.minimizeCount == 1)
    }

    @Test func failedResumeAndPausedReconnectDoNotHideMainWindow() async throws {
        let paused = Fixture(.paused)
        paused.rejectsResume = true
        paused.coordinator.begin()
        #expect(paused.minimizeCount == 0)
        #expect(paused.showMainCount == 1)

        let reconnecting = Fixture(.reconnecting)
        reconnecting.coordinator.begin()
        reconnecting.state.phase = .paused
        try await reconnecting.waitForPresentation()
        #expect(reconnecting.resumeCount == 0)
        #expect(reconnecting.minimizeCount == 0)
        #expect(reconnecting.showMainCount == 1)
    }

    @Test func finishingDoesNotRestartCaptureOrHideMainWindow() {
        let fixture = Fixture(.finishing)
        fixture.coordinator.begin()
        #expect(fixture.startCount == 0)
        #expect(fixture.resumeCount == 0)
        #expect(fixture.minimizeCount == 0)
        #expect(fixture.showMainCount == 1)
    }
}

@Observable
@MainActor
private final class CaptureState {
    var phase: MenuBarCapturePhase
    init(_ phase: MenuBarCapturePhase) { self.phase = phase }
}

@MainActor
private final class Fixture {
    let state: CaptureState
    var startCount = 0
    var resumeCount = 0
    var minimizeCount = 0
    var showMainCount = 0
    var rejectsStart = false
    var rejectsResume = false

    lazy var coordinator = FloatingCaptionStartCoordinator(
        phase: { [unowned self] in state.phase },
        start: { [unowned self] in
            startCount += 1
            if !rejectsStart { state.phase = .starting }
        },
        resume: { [unowned self] in
            resumeCount += 1
            if !rejectsResume { state.phase = .running }
        },
        minimizeMainWindows: { [unowned self] in minimizeCount += 1 },
        showMainWindows: { [unowned self] in showMainCount += 1 }
    )

    init(_ phase: MenuBarCapturePhase) { state = CaptureState(phase) }

    func waitForPresentation() async throws {
        let deadline = ContinuousClock.now + .seconds(1)
        while minimizeCount + showMainCount == 0, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(2))
        }
    }
}
