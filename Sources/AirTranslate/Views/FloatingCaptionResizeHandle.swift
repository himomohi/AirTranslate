import AppKit
import SwiftUI

struct FloatingCaptionMoveAffordance: View {
    let isVisible: Bool

    var body: some View {
        Capsule(style: .continuous)
            .fill(.white.opacity(isVisible ? 0.58 : 0.28))
            .frame(width: 82, height: 5)
            .shadow(color: .black.opacity(0.24), radius: 3, y: 1)
            .accessibilityLabel(AppText.floatingCaptionDragHandle)
            .accessibilityHidden(!isVisible)
            .animation(AirTranslateDesign.Motion.quick, value: isVisible)
    }
}

struct FloatingCaptionResizeHandle: NSViewRepresentable {
    let minimumSize: NSSize

    func makeNSView(context _: Context) -> NSView {
        let view = ResizeView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        view.setAccessibilityElement(true)
        view.setAccessibilityRole(.handle)
        view.setAccessibilityLabel(AppText.floatingCaptionResizeHandle)
        return view
    }

    func updateNSView(_ view: NSView, context _: Context) {
        (view as? ResizeView)?.minimumSize = minimumSize
    }

    private final class ResizeView: NSView {
        var minimumSize = FloatingCaptionWindowController.minimumWindowSize
        private var initialFrame: NSRect = .zero
        private var initialMouseLocation: NSPoint = .zero

        override var acceptsFirstResponder: Bool { true }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
            true
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            super.hitTest(point) == nil ? nil : self
        }

        override func draw(_ dirtyRect: NSRect) {
            super.draw(dirtyRect)
            let path = NSBezierPath()
            path.lineWidth = 1.4
            for offset in [10.0, 16.0, 22.0] {
                path.move(to: NSPoint(x: bounds.maxX - CGFloat(offset), y: bounds.minY + 6))
                path.line(to: NSPoint(x: bounds.maxX - 6, y: bounds.minY + CGFloat(offset)))
            }
            // 투명 배경이나 밝은 영상에서도 손잡이 윤곽을 유지한다.
            NSColor.black.withAlphaComponent(0.55).setStroke()
            path.lineWidth = 3.4
            path.stroke()
            NSColor.white.withAlphaComponent(0.9).setStroke()
            path.lineWidth = 1.4
            path.stroke()
        }

        override func resetCursorRects() {
            addCursorRect(bounds, cursor: .crosshair)
        }

        override func mouseDown(with event: NSEvent) {
            window?.makeFirstResponder(self)
            initialFrame = window?.frame ?? .zero
            initialMouseLocation = screenLocation(for: event)
        }

        override func mouseDragged(with event: NSEvent) {
            guard let window else { return }
            let currentMouseLocation = screenLocation(for: event)
            let deltaX = currentMouseLocation.x - initialMouseLocation.x
            let deltaY = currentMouseLocation.y - initialMouseLocation.y

            var frame = initialFrame
            frame.size.width += deltaX
            frame.size.height -= deltaY
            frame.origin.y += deltaY

            if let visibleFrame = (window.screen ?? NSScreen.main)?.visibleFrame {
                frame = FloatingCaptionWindowController.clampedFrame(frame, within: visibleFrame, minimumSize: minimumSize)
            }
            window.setFrame(frame, display: true)
        }

        override func keyDown(with event: NSEvent) {
            let step: CGFloat = event.modifierFlags.contains(.shift) ? 40 : 12
            switch event.keyCode {
            case 123:
                resizeBy(width: -step, height: 0)
            case 124:
                resizeBy(width: step, height: 0)
            case 125:
                resizeBy(width: 0, height: step)
            case 126:
                resizeBy(width: 0, height: -step)
            default:
                super.keyDown(with: event)
            }
        }

        override func accessibilityPerformIncrement() -> Bool {
            resizeBy(width: 40, height: 24)
            return true
        }

        override func accessibilityPerformDecrement() -> Bool {
            resizeBy(width: -40, height: -24)
            return true
        }

        private func screenLocation(for event: NSEvent) -> NSPoint {
            guard let window else { return .zero }
            return window.convertPoint(toScreen: event.locationInWindow)
        }

        private func resizeBy(width widthDelta: CGFloat, height heightDelta: CGFloat) {
            guard let window else { return }
            var frame = window.frame
            frame.size.width += widthDelta
            frame.size.height += heightDelta
            frame.origin.y -= heightDelta
            if let visibleFrame = (window.screen ?? NSScreen.main)?.visibleFrame {
                frame = FloatingCaptionWindowController.clampedFrame(frame, within: visibleFrame, minimumSize: minimumSize)
            }
            window.setFrame(frame, display: true)
        }
    }
}
