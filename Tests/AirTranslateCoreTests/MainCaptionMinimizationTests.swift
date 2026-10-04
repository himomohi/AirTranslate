import AppKit
import Testing
@testable import AirTranslate

@MainActor
private final class CaptionMinimizationWindow: NSWindow {
    var testVisible = true
    var testMiniaturized = false
    var completesMinimizationImmediately = true
    var rejectsMinimization = false
    var defersMinimizationStart = false
    private(set) var minimizeCount = 0
    private(set) var restoreCount = 0

    override var isVisible: Bool { testVisible }
    override var isMiniaturized: Bool { testMiniaturized }

    override func miniaturize(_ sender: Any?) {
        minimizeCount += 1
        guard !rejectsMinimization else { return }
        guard !defersMinimizationStart else { return }
        beginMinimization()
        if completesMinimizationImmediately { completeMinimization() }
    }

    func beginMinimization() {
        NotificationCenter.default.post(name: NSWindow.willMiniaturizeNotification, object: self)
    }

    func completeMinimization() {
        testMiniaturized = true
        NotificationCenter.default.post(name: NSWindow.didMiniaturizeNotification, object: self)
    }

    override func deminiaturize(_ sender: Any?) {
        restoreCount += 1
        testMiniaturized = false
        NotificationCenter.default.post(name: NSWindow.didDeminiaturizeNotification, object: self)
    }

    override func makeKeyAndOrderFront(_ sender: Any?) {}
}

@Suite
@MainActor
struct MainCaptionMinimizationTests {
    @Test
    func onlyVisibleAttachedMainWindowsAreMinimizedAndRestoredOnce() {
        let visible = fixture()
        let userMinimized = fixture()
        let hidden = fixture()
        let unrelated = CaptionMinimizationWindow()
        userMinimized.window.testMiniaturized = true
        hidden.window.testVisible = false
        defer { cleanup([visible, userMinimized, hidden]) }

        MainCaptionWindowObserver.minimizeMainWindowsForFloatingCaptions()
        MainCaptionWindowObserver.minimizeMainWindowsForFloatingCaptions()
        #expect(visible.window.minimizeCount == 1)
        #expect(userMinimized.window.minimizeCount == 0)
        #expect(hidden.window.minimizeCount == 0)
        #expect(unrelated.minimizeCount == 0)

        MainCaptionWindowObserver.restoreMainWindowsAfterFloatingCaptions()
        MainCaptionWindowObserver.restoreMainWindowsAfterFloatingCaptions()
        #expect(visible.window.restoreCount == 1)
        #expect(!visible.window.isMiniaturized)
        #expect(userMinimized.window.restoreCount == 0)
        #expect(userMinimized.window.isMiniaturized)
        #expect(hidden.window.restoreCount == 0)
        #expect(unrelated.restoreCount == 0)
    }

    @Test
    func manuallyRestoredThenMinimizedWindowIsNoLongerOwned() {
        let main = fixture()
        defer { cleanup([main]) }
        MainCaptionWindowObserver.minimizeMainWindowsForFloatingCaptions()
        main.window.deminiaturize(nil)
        main.window.miniaturize(nil)

        MainCaptionWindowObserver.restoreMainWindowsAfterFloatingCaptions()
        #expect(main.window.restoreCount == 1)
        #expect(main.window.isMiniaturized)
    }

    @Test
    func detachedWindowIsNotRestored() {
        let main = fixture()
        defer { cleanup([main]) }
        MainCaptionWindowObserver.minimizeMainWindowsForFloatingCaptions()
        main.window.contentView = nil

        MainCaptionWindowObserver.restoreMainWindowsAfterFloatingCaptions()
        #expect(main.window.restoreCount == 0)
    }

    @Test
    func asynchronousMinimizationRetainsRestoreOwnership() {
        let main = fixture()
        main.window.completesMinimizationImmediately = false
        defer { cleanup([main]) }
        MainCaptionWindowObserver.minimizeMainWindowsForFloatingCaptions()
        MainCaptionWindowObserver.minimizeMainWindowsForFloatingCaptions()
        #expect(main.window.minimizeCount == 1)
        #expect(!main.window.isMiniaturized)
        main.window.completeMinimization()

        MainCaptionWindowObserver.restoreMainWindowsAfterFloatingCaptions()
        #expect(main.window.restoreCount == 1)
        #expect(!main.window.isMiniaturized)
    }

    @Test
    func closingCaptionsDuringMinimizationRestoresAfterCompletion() {
        let main = fixture()
        main.window.completesMinimizationImmediately = false
        defer { cleanup([main]) }
        MainCaptionWindowObserver.minimizeMainWindowsForFloatingCaptions()
        MainCaptionWindowObserver.restoreMainWindowsAfterFloatingCaptions()
        #expect(main.window.restoreCount == 0)

        main.window.completeMinimization()
        #expect(main.window.restoreCount == 1)
        #expect(!main.window.isMiniaturized)
    }

    @Test
    func returningToExclusiveModeDuringMinimizationCancelsPendingRestore() {
        let main = fixture()
        main.window.completesMinimizationImmediately = false
        defer { cleanup([main]) }
        MainCaptionWindowObserver.minimizeMainWindowsForFloatingCaptions()
        MainCaptionWindowObserver.restoreMainWindowsAfterFloatingCaptions()
        MainCaptionWindowObserver.minimizeMainWindowsForFloatingCaptions()
        main.window.completeMinimization()
        #expect(main.window.restoreCount == 0)
        #expect(main.window.minimizeCount == 1)
        #expect(main.window.isMiniaturized)

        MainCaptionWindowObserver.restoreMainWindowsAfterFloatingCaptions()
        #expect(main.window.restoreCount == 1)
    }

    @Test
    func rejectedMinimizationDoesNotOwnLaterManualMinimization() async throws {
        let main = fixture()
        main.window.rejectsMinimization = true
        defer { cleanup([main]) }
        MainCaptionWindowObserver.minimizeMainWindowsForFloatingCaptions()
        MainCaptionWindowObserver.minimizeMainWindowsForFloatingCaptions()
        #expect(main.window.minimizeCount == 1)
        MainCaptionWindowObserver.restoreMainWindowsAfterFloatingCaptions()
        try await Task.sleep(for: .milliseconds(2100))

        main.window.rejectsMinimization = false
        main.window.miniaturize(nil)
        #expect(main.window.restoreCount == 0)
        #expect(main.window.isMiniaturized)
    }

    @Test
    func asynchronouslyDeliveredStartNotificationKeepsRestoreOwnership() {
        let main = fixture()
        main.window.defersMinimizationStart = true
        defer { cleanup([main]) }
        MainCaptionWindowObserver.minimizeMainWindowsForFloatingCaptions()
        main.window.beginMinimization()
        main.window.completeMinimization()
        MainCaptionWindowObserver.restoreMainWindowsAfterFloatingCaptions()
        #expect(main.window.restoreCount == 1)
        #expect(!main.window.isMiniaturized)
    }

    @Test
    func requestingMainWindowBeforeMinimizationStartsRestoresAfterCompletion() {
        let main = fixture()
        main.window.defersMinimizationStart = true
        defer { cleanup([main]) }
        MainCaptionWindowObserver.minimizeMainWindowsForFloatingCaptions()
        MainCaptionWindowObserver.showMainWindows()
        main.window.beginMinimization()
        main.window.completeMinimization()
        #expect(main.window.restoreCount == 1)
        #expect(!main.window.isMiniaturized)
    }

    @Test
    func nonMinimizableWindowIsNotRequested() {
        let main = fixture()
        main.window.styleMask.remove(.miniaturizable)
        defer { cleanup([main]) }
        MainCaptionWindowObserver.minimizeMainWindowsForFloatingCaptions()
        #expect(main.window.minimizeCount == 0)
    }

    private typealias Fixture = (window: CaptionMinimizationWindow, observer: MainCaptionVisibilityView)

    private func fixture() -> Fixture {
        _ = NSApplication.shared
        let window = CaptionMinimizationWindow(contentRect: .zero, styleMask: [.titled, .miniaturizable], backing: .buffered, defer: false)
        let observer = MainCaptionVisibilityView()
        window.contentView = observer
        return (window, observer)
    }

    private func cleanup(_ fixtures: [Fixture]) {
        for fixture in fixtures {
            fixture.window.contentView = nil
            fixture.observer.stopObserving()
        }
        MainCaptionWindowObserver.restoreMainWindowsAfterFloatingCaptions()
    }
}
