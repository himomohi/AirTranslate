import AppKit
import SwiftUI

struct FloatingCaptionDragSurface: NSViewRepresentable {
    func makeNSView(context _: Context) -> NSView {
        let view = DragView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        return view
    }

    func updateNSView(_: NSView, context _: Context) {}

    private final class DragView: NSView {
        private var initialFrame: NSRect = .zero
        private var initialPointer: NSPoint = .zero
        override var mouseDownCanMoveWindow: Bool {
            true
        }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
            true
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            super.hitTest(point) == nil ? nil : self
        }

        override func resetCursorRects() {
            addCursorRect(bounds, cursor: .openHand)
        }

        override func mouseDown(with event: NSEvent) {
            guard let window else { return }
            initialFrame = window.frame
            initialPointer = window.convertPoint(toScreen: event.locationInWindow)
        }

        override func mouseDragged(with event: NSEvent) {
            guard let window else { return }
            let pointer = window.convertPoint(toScreen: event.locationInWindow)
            var frame = initialFrame
            frame.origin.x += pointer.x - initialPointer.x
            frame.origin.y += pointer.y - initialPointer.y
            if let visibleFrame = (window.screen ?? NSScreen.main)?.visibleFrame {
                frame = FloatingCaptionWindowController.clampedFrame(frame, within: visibleFrame, minimumSize: window.minSize)
            }
            window.setFrame(frame, display: true)
        }
    }
}
