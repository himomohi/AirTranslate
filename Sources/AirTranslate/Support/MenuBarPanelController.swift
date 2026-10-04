import AppKit
import Observation
import SwiftUI

@MainActor
final class MenuBarPanelController: NSObject {
    private let popover = NSPopover()
    private let hostingController = NSHostingController(rootView: AnyView(EmptyView()))
    private var statusItem: NSStatusItem?
    private weak var session: TranslationSessionStore?
    private var isObservingSession = false

    override init() {
        super.init()
        popover.animates = true
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 360, height: 430)
        hostingController.sizingOptions = .preferredContentSize
        popover.contentViewController = hostingController
    }

    func install(session: TranslationSessionStore, openWindow: OpenWindowAction) {
        if self.session !== session {
            self.session = session
            // AppKit이 호스팅하는 상태바 패널에도 실제 Scene의 창 열기 동작을 전달한다.
            hostingController.rootView = AnyView(
                MenuBarStatusView(session: session, openWindow: openWindow)
            )
        }
        ensureStatusItem()
        updateStatusButton(using: session)
        observeSessionStateIfNeeded()
    }

    @objc
    private func togglePopover(_ sender: Any?) {
        guard let button = statusItem?.button else {
            return
        }

        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    private func ensureStatusItem() {
        guard statusItem == nil else {
            return
        }

        let item = NSStatusBar.system.statusItem(withLength: 28)
        item.isVisible = true
        statusItem = item

        guard let button = item.button else {
            return
        }

        button.target = self
        button.action = #selector(togglePopover(_:))
        button.sendAction(on: [.leftMouseDown])
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.image = MenuBarMiniAppIconRenderer.image()
        button.toolTip = AppText.menuBarTitle
    }

    private func updateStatusButton(using session: TranslationSessionStore) {
        guard let button = statusItem?.button else {
            return
        }

        let title = menuBarTitle(for: session)
        if button.toolTip != title {
            button.toolTip = title
        }
        if button.accessibilityTitle() != title {
            button.setAccessibilityTitle(title)
        }
    }

    private func observeSessionStateIfNeeded() {
        guard !isObservingSession, session != nil else {
            return
        }

        isObservingSession = true
        trackSessionState()
    }

    private func trackSessionState() {
        guard let session else {
            isObservingSession = false
            return
        }

        withObservationTracking {
            _ = session.isRunning
            _ = session.isPaused
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else {
                    return
                }
                guard let session = self.session else {
                    self.isObservingSession = false
                    return
                }
                self.updateStatusButton(using: session)
                self.trackSessionState()
            }
        }
    }

    private func menuBarTitle(for session: TranslationSessionStore) -> String {
        if session.isPaused {
            return AppText.menuBarPausedTitle
        }
        if session.isRunning {
            return AppText.menuBarRunningTitle
        }
        return AppText.menuBarTitle
    }

}

@MainActor
private enum MenuBarMiniAppIconRenderer {
    private static let cachedImage: NSImage = appIconImage() ?? fallbackImage()

    static func image() -> NSImage {
        cachedImage
    }

    private static func appIconImage() -> NSImage? {
        guard let source = Bundle.main.url(forResource: "AppIcon", withExtension: "icns")
            .flatMap(NSImage.init(contentsOf:))
            ?? NSImage(named: "AppIcon")
        else {
            return nil
        }

        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)
        image.lockFocus()
        source.draw(
            in: NSRect(origin: .zero, size: size),
            from: .zero,
            operation: .sourceOver,
            fraction: 1.0,
            respectFlipped: true,
            hints: [.interpolation: NSImageInterpolation.high]
        )
        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    private static func fallbackImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18))
        image.lockFocus()

        let iconRect = NSRect(x: 1, y: 1, width: 16, height: 16)
        let background = NSBezierPath(roundedRect: iconRect, xRadius: 4.5, yRadius: 4.5)
        NSColor.white.setFill()
        background.fill()
        NSColor.black.withAlphaComponent(0.18).setStroke()
        background.lineWidth = 0.75
        background.stroke()

        NSColor.black.setFill()
        drawPixelSoundBars(in: iconRect)
        drawPixelABC(in: iconRect)

        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    private static func drawPixelSoundBars(in iconRect: NSRect) {
        let pixel: CGFloat = 1.35
        let baseline = iconRect.minY + 8.6
        let centerX = iconRect.midX

        fillPixelRect(x: centerX - 5.1, y: baseline - 2.0, width: pixel, height: 4.0)
        fillPixelRect(x: centerX - 2.5, y: baseline - 4.0, width: pixel, height: 6.0)
        fillPixelRect(x: centerX, y: baseline - 5.5, width: pixel, height: 7.5)
        fillPixelRect(x: centerX + 2.5, y: baseline - 4.0, width: pixel, height: 6.0)
        fillPixelRect(x: centerX + 5.1, y: baseline - 2.0, width: pixel, height: 4.0)
    }

    private static func drawPixelABC(in iconRect: NSRect) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 5.8, weight: .black),
            .foregroundColor: NSColor.black
        ]
        let text = "abc" as NSString
        let textSize = text.size(withAttributes: attributes)
        let origin = NSPoint(
            x: iconRect.midX - textSize.width / 2,
            y: iconRect.maxY - textSize.height - 2.4
        )
        text.draw(at: origin, withAttributes: attributes)
    }

    private static func fillPixelRect(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) {
        NSBezierPath(rect: NSRect(x: round(x), y: round(y), width: round(width), height: round(height))).fill()
    }
}
