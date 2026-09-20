import AppKit
import SwiftUI

@MainActor
final class FloatingCaptionWindowController: NSObject, NSWindowDelegate {
    static let visibilityDidChangeNotification = Notification.Name("AirTranslateFloatingCaptionVisibilityDidChange")

    static var isOpen: Bool {
        shared.window?.isVisible == true
    }

    static func toggle(session: TranslationSessionStore) {
        isOpen ? close() : open(session: session)
    }

    static func open(session: TranslationSessionStore, preview: Bool = false) {
        session.isPreviewingFloatingCaptions = preview && !session.isRunning && !session.isStarting
        shared.open(session: session)
    }

    static func close() {
        shared.close()
    }

    static func resetSize() {
        shared.resetSize()
    }

    static func setWidth(_ width: CGFloat) {
        guard width.isFinite, let panel = shared.window else { return }
        var frame = panel.frame
        frame.origin.x = frame.midX - width / 2
        frame.size.width = width
        if let visibleFrame = (panel.screen ?? NSScreen.main)?.visibleFrame {
            frame = clampedFrame(frame, within: visibleFrame, minimumSize: panel.minSize)
        }
        panel.setFrame(frame, display: true)
    }

    private static let shared = FloatingCaptionWindowController()
    private static let frameDefaultsKey = "floatingCaptionWindowFrame"
    nonisolated static let defaultWindowSize = NSSize(width: 720, height: 170)
    nonisolated static let minimumWindowSize = NSSize(width: 420, height: 90)
    nonisolated static let screenInset: CGFloat = 16

    private var window: NSPanel?
    private weak var currentSession: TranslationSessionStore?

    private func open(session: TranslationSessionStore) {
        currentSession = session
        let isFirstOpen = window == nil
        let panel = window ?? makeWindow(session: session)
        configure(panel, session: session)
        let screenFrames = NSScreen.screens.map(\.visibleFrame)
        let needsPlacement = isFirstOpen || !Self.frameIsReasonablyVisible(panel.frame, within: screenFrames)
        if needsPlacement, !restorePersistedFrame(panel) {
            positionForFirstOpen(panel)
        }
        window = panel
        panel.orderFrontRegardless()
        notifyVisibilityChanged()
    }

    private func close() {
        currentSession?.isPreviewingFloatingCaptions = false
        guard let panel = window else { return }
        persistFrame(of: panel)
        panel.orderOut(nil)
        notifyVisibilityChanged()
    }

    func windowWillClose(_ notification: Notification) {
        guard notification.object as? NSWindow === window else { return }
        currentSession?.isPreviewingFloatingCaptions = false
        if let panel = window {
            persistFrame(of: panel)
        }
        window = nil
        Self.notifyVisibilityChanged()
    }

    func windowDidMove(_ notification: Notification) {
        persistFrameIfCurrent(notification)
    }

    func windowDidResize(_ notification: Notification) {
        persistFrameIfCurrent(notification)
    }

    private func makeWindow(session: TranslationSessionStore) -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.defaultWindowSize),
            styleMask: [.borderless, .nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.contentView = NSHostingView(rootView: FloatingCaptionWindowView(session: session))
        panel.delegate = self
        panel.isReleasedWhenClosed = false
        return panel
    }

    private func configure(_ panel: NSPanel, session: TranslationSessionStore) {
        panel.identifier = NSUserInterfaceItemIdentifier(AirTranslateWindowID.floatingCaptions)
        panel.title = AppText.floatingCaptions
        panel.level = session.keepsFloatingCaptionAboveOtherWindows ? .floating : .normal
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.minSize = Self.minimumWindowSize
        panel.maxSize = Self.maximumWindowSize(for: panel.screen ?? NSScreen.main)
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
    }

    private func positionForFirstOpen(_ panel: NSPanel) {
        guard let visibleFrame = NSScreen.main?.visibleFrame else { return }

        let frame = panel.frame
        let x = visibleFrame.midX - frame.width / 2
        let y = visibleFrame.minY + min(180, visibleFrame.height * 0.18)
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func persistFrameIfCurrent(_ notification: Notification) {
        guard let panel = notification.object as? NSWindow, panel === window, panel.isVisible else { return }
        persistFrame(of: panel)
    }

    private func persistFrame(of panel: NSWindow) {
        UserDefaults.standard.set(NSStringFromRect(panel.frame), forKey: Self.frameDefaultsKey)
    }

    private func resetSize() {
        UserDefaults.standard.removeObject(forKey: Self.frameDefaultsKey)
        guard let panel = window else { return }

        var frame = panel.frame
        frame.origin.x = frame.midX - Self.defaultWindowSize.width / 2
        frame.origin.y = frame.midY - Self.defaultWindowSize.height / 2
        frame.size = Self.defaultWindowSize
        if let visibleFrame = (panel.screen ?? NSScreen.main)?.visibleFrame {
            frame = Self.clampedFrame(frame, within: visibleFrame)
        }
        panel.setFrame(frame, display: true)
        persistFrame(of: panel)
    }

    private func restorePersistedFrame(_ panel: NSPanel) -> Bool {
        guard let frameString = UserDefaults.standard.string(forKey: Self.frameDefaultsKey) else {
            return false
        }

        let frame = NSRectFromString(frameString)
        let screenFrames = NSScreen.screens.map(\.visibleFrame)
        guard Self.frameIsReasonablyVisible(frame, within: screenFrames) else {
            return false
        }

        panel.setFrame(frame, display: false)
        return true
    }

    nonisolated static func frameIsReasonablyVisible(_ frame: NSRect, within screenVisibleFrames: [NSRect]) -> Bool {
        guard frame.width > 0, frame.height > 0 else { return false }

        return screenVisibleFrames.contains { visibleFrame in
            let intersection = visibleFrame.intersection(frame)
            return intersection.width >= 160 && intersection.height >= 60
        }
    }

    nonisolated static func maximumWindowSize(for screen: NSScreen?) -> NSSize {
        guard let visibleFrame = screen?.visibleFrame else {
            return NSSize(width: 1400, height: 900)
        }
        return NSSize(
            width: max(minimumWindowSize.width, visibleFrame.width - screenInset * 2),
            height: max(minimumWindowSize.height, visibleFrame.height - screenInset * 2)
        )
    }

    nonisolated static func clampedFrame(
        _ frame: NSRect,
        within visibleFrame: NSRect,
        minimumSize requestedMinimumSize: NSSize = minimumWindowSize
    ) -> NSRect {
        let minimumSize = NSSize(
            width: max(Self.minimumWindowSize.width, requestedMinimumSize.width),
            height: max(Self.minimumWindowSize.height, requestedMinimumSize.height)
        )
        guard frame.width.isFinite, frame.height.isFinite,
              frame.origin.x.isFinite, frame.origin.y.isFinite else {
            return NSRect(origin: visibleFrame.origin, size: Self.defaultWindowSize)
        }

        let maximumSize = NSSize(
            width: max(minimumSize.width, visibleFrame.width - screenInset * 2),
            height: max(minimumSize.height, visibleFrame.height - screenInset * 2)
        )
        var clamped = frame
        clamped.size.width = min(max(clamped.width, minimumSize.width), maximumSize.width)
        clamped.size.height = min(max(clamped.height, minimumSize.height), maximumSize.height)
        let minimumX = visibleFrame.minX + screenInset
        let maximumX = max(minimumX, visibleFrame.maxX - clamped.width - screenInset)
        let minimumY = visibleFrame.minY + screenInset
        let maximumY = max(minimumY, visibleFrame.maxY - clamped.height - screenInset)
        clamped.origin.x = min(max(clamped.origin.x, minimumX), maximumX)
        clamped.origin.y = min(max(clamped.origin.y, minimumY), maximumY)
        return clamped
    }

    private func notifyVisibilityChanged() {
        Self.notifyVisibilityChanged()
    }

    private static func notifyVisibilityChanged() {
        NotificationCenter.default.post(name: visibilityDidChangeNotification, object: nil)
    }
}
