import AppKit
import SwiftUI

enum MainCaptionWindowVisibility {
    /// 비활성 앱의 창도 화면에 보이면 그린다. 키 창/앱 활성 여부는 조건이 아니다.
    static func shouldRender(
        isWindowAttached: Bool,
        isVisible: Bool,
        isMiniaturized: Bool,
        isOcclusionVisible: Bool,
        isApplicationHidden: Bool
    ) -> Bool {
        isWindowAttached && isVisible && !isMiniaturized
            && isOcclusionVisible && !isApplicationHidden
    }
}

struct MainCaptionWindowObserver: NSViewRepresentable {
    @Binding var isCaptionVisible: Bool

    @MainActor private static let windowsMinimizedForFloatingCaptions = NSHashTable<NSWindow>.weakObjects()
    @MainActor private static let windowsAwaitingMinimizationToRestore = NSHashTable<NSWindow>.weakObjects()
    @MainActor private static let windowsRequestingMinimization = NSMapTable<NSWindow, NSUUID>(keyOptions: .weakMemory, valueOptions: .strongMemory)

    @MainActor static func minimizeMainWindowsForFloatingCaptions() {
        let windows = MainCaptionVisibilityView.attachedMainWindows
        PipelineDiagnostics.record("main.minimize.request", values: ["windows": Double(windows.count)])
        for window in windows where window.isVisible && !window.isMiniaturized
            && window.styleMask.contains(.miniaturizable) {
            if windowsAwaitingMinimizationToRestore.contains(window) {
                windowsAwaitingMinimizationToRestore.remove(window)
                if windowsRequestingMinimization.object(forKey: window) == nil {
                    windowsMinimizedForFloatingCaptions.add(window)
                }
                continue
            }
            guard !windowsMinimizedForFloatingCaptions.contains(window),
                  windowsRequestingMinimization.object(forKey: window) == nil else { continue }
            // 실제 시작 알림에서만 소유권을 얻어 거절된 요청이 남지 않게 한다.
            let request = NSUUID()
            windowsRequestingMinimization.setObject(request, forKey: window)
            window.miniaturize(nil)
            // 시작 알림도 비동기다. 시작되지 않은 요청만 만료시켜 수동 최소화를 보호한다.
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak window] in
                guard let window,
                      windowsRequestingMinimization.object(forKey: window) === request else { return }
                windowsRequestingMinimization.removeObject(forKey: window)
                windowsAwaitingMinimizationToRestore.remove(window)
                PipelineDiagnostics.record("main.minimize.unstarted")
            }
            PipelineDiagnostics.record("main.minimize.result", values: [
                "minimized": window.isMiniaturized ? 1 : 0,
                "accepted": windowsMinimizedForFloatingCaptions.contains(window) ? 1 : 0,
                "pending": windowsRequestingMinimization.object(forKey: window) != nil ? 1 : 0
            ])
        }
    }

    @MainActor static func willMinimizeMainWindow(_ window: NSWindow) {
        guard windowsRequestingMinimization.object(forKey: window) != nil else { return }
        windowsRequestingMinimization.removeObject(forKey: window)
        windowsMinimizedForFloatingCaptions.add(window)
        PipelineDiagnostics.record("main.minimize.accepted")
    }

    @MainActor static func restoreMainWindowsAfterFloatingCaptions() {
        let attachedWindows = MainCaptionVisibilityView.attachedMainWindows
        let ownedWindows = windowsMinimizedForFloatingCaptions.allObjects
            + windowsRequestingMinimization.keyEnumerator().allObjects.compactMap { $0 as? NSWindow }
        PipelineDiagnostics.record("main.restore.request", values: ["windows": Double(ownedWindows.count)])
        windowsMinimizedForFloatingCaptions.removeAllObjects()
        for window in ownedWindows where attachedWindows.contains(where: { $0 === window }) {
            if window.isMiniaturized {
                window.deminiaturize(nil)
                window.makeKeyAndOrderFront(nil)
            } else {
                // 최소화 도중 자막을 끈 경우 완료 알림을 받은 뒤 복원한다.
                windowsAwaitingMinimizationToRestore.add(window)
            }
        }
    }

    @MainActor static func didMinimizeMainWindow(_ window: NSWindow) {
        guard windowsAwaitingMinimizationToRestore.contains(window) else { return }
        windowsAwaitingMinimizationToRestore.remove(window)
        windowsRequestingMinimization.removeObject(forKey: window)
        PipelineDiagnostics.record("main.restore.after_minimize")
        window.deminiaturize(nil)
        window.makeKeyAndOrderFront(nil)
    }

    @MainActor static func releaseFloatingCaptionMinimizationOwnership(of window: NSWindow) {
        windowsMinimizedForFloatingCaptions.remove(window)
        windowsAwaitingMinimizationToRestore.remove(window)
        windowsRequestingMinimization.removeObject(forKey: window)
    }

    @MainActor @discardableResult
    static func showMainWindows() -> Bool {
        restoreMainWindowsAfterFloatingCaptions()
        let windows = MainCaptionVisibilityView.attachedMainWindows
        for window in windows {
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
        }
        return !windows.isEmpty
    }

    func makeNSView(context: Context) -> MainCaptionVisibilityView {
        let view = MainCaptionVisibilityView()
        view.onVisibilityChange = { isCaptionVisible = $0 }
        return view
    }

    func updateNSView(_ view: MainCaptionVisibilityView, context: Context) {
        view.onVisibilityChange = { isCaptionVisible = $0 }
    }

    static func dismantleNSView(_ view: MainCaptionVisibilityView, coordinator: ()) {
        view.stopObserving()
    }
}

@MainActor
final class MainCaptionVisibilityView: NSView {
    // 관찰 뷰를 약하게 보관해 창을 붙잡지 않고 실제 부착된 메인 창만 찾는다.
    private static let attachedObservers = NSHashTable<MainCaptionVisibilityView>.weakObjects()

    static var attachedMainWindows: [NSWindow] {
        var seen = Set<ObjectIdentifier>()
        return attachedObservers.allObjects.compactMap { observer in
            guard !observer.isWindowClosing,
                  let window = observer.observedWindow,
                  observer.window === window,
                  seen.insert(ObjectIdentifier(window)).inserted else { return nil }
            return window
        }
    }

    var onVisibilityChange: ((Bool) -> Void)?
    private weak var observedWindow: NSWindow?
    private var lastReportedVisibility: Bool?
    private var isRefreshScheduled = false
    private var isWindowClosing = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        NotificationCenter.default.removeObserver(self)
        observedWindow = window
        isWindowClosing = false
        lastReportedVisibility = nil

        if let observedWindow {
            Self.attachedObservers.add(self)
            for name in [
                NSWindow.didChangeOcclusionStateNotification,
                NSWindow.willMiniaturizeNotification,
                NSWindow.didMiniaturizeNotification,
                NSWindow.didDeminiaturizeNotification,
                NSWindow.willCloseNotification
            ] {
                NotificationCenter.default.addObserver(
                    self, selector: #selector(windowStateChanged(_:)),
                    name: name, object: observedWindow
                )
            }
            for name in [NSApplication.didHideNotification, NSApplication.didUnhideNotification] {
                NotificationCenter.default.addObserver(
                    self, selector: #selector(windowStateChanged(_:)),
                    name: name, object: NSApplication.shared
                )
            }
        } else {
            Self.attachedObservers.remove(self)
        }
        scheduleVisibilityRefresh()
    }

    func stopObserving() {
        NotificationCenter.default.removeObserver(self)
        Self.attachedObservers.remove(self)
        observedWindow = nil
        onVisibilityChange = nil
    }

    @objc private func windowStateChanged(_ notification: Notification) {
        if notification.name == NSWindow.willMiniaturizeNotification {
            PipelineDiagnostics.record("main.minimize.begin")
            if let window = notification.object as? NSWindow {
                MainCaptionWindowObserver.willMinimizeMainWindow(window)
            }
        } else if notification.name == NSWindow.didMiniaturizeNotification {
            PipelineDiagnostics.record("main.minimized")
            if let window = notification.object as? NSWindow {
                MainCaptionWindowObserver.didMinimizeMainWindow(window)
            }
        } else if notification.name == NSWindow.didDeminiaturizeNotification {
            PipelineDiagnostics.record("main.restored")
        }
        if notification.name == NSWindow.didDeminiaturizeNotification
            || notification.name == NSWindow.willCloseNotification,
           let window = notification.object as? NSWindow {
            MainCaptionWindowObserver.releaseFloatingCaptionMinimizationOwnership(of: window)
        }
        if notification.name == NSWindow.willCloseNotification {
            isWindowClosing = true
        } else if observedWindow?.isVisible == true {
            isWindowClosing = false
        }
        scheduleVisibilityRefresh()
    }

    private func scheduleVisibilityRefresh() {
        guard !isRefreshScheduled else { return }
        isRefreshScheduled = true
        // AppKit의 창 상태 갱신과 SwiftUI의 현재 뷰 갱신이 끝난 뒤 한 번만 반영한다.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isRefreshScheduled = false
            let visible = MainCaptionWindowVisibility.shouldRender(
                isWindowAttached: self.observedWindow != nil,
                isVisible: self.observedWindow?.isVisible == true && !self.isWindowClosing,
                isMiniaturized: self.observedWindow?.isMiniaturized == true,
                isOcclusionVisible: self.observedWindow?.occlusionState.contains(.visible) == true,
                isApplicationHidden: NSApplication.shared.isHidden
            )
            guard visible != self.lastReportedVisibility else { return }
            PipelineDiagnostics.record("main.visibility", values: ["visible": visible ? 1 : 0])
            self.lastReportedVisibility = visible
            self.onVisibilityChange?(visible)
        }
    }
}
