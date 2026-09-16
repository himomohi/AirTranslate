import Foundation
import Testing
@testable import AirTranslate

@Suite
struct FloatingCaptionWindowFrameVisibilityTests {
    private let mainScreen = NSRect(x: 0, y: 0, width: 1920, height: 1080)
    private let secondaryScreen = NSRect(x: 1920, y: 0, width: 1440, height: 900)

    @Test
    func frameInsideScreenIsVisible() {
        let frame = NSRect(x: 600, y: 120, width: 720, height: 170)

        #expect(FloatingCaptionWindowController.frameIsReasonablyVisible(frame, within: [mainScreen]))
    }

    @Test
    func frameOnSecondaryScreenIsVisible() {
        let frame = NSRect(x: 2200, y: 200, width: 720, height: 170)

        #expect(FloatingCaptionWindowController.frameIsReasonablyVisible(frame, within: [mainScreen, secondaryScreen]))
    }

    @Test
    func frameFromDisconnectedDisplayIsNotVisible() {
        let frame = NSRect(x: 2200, y: 200, width: 720, height: 170)

        #expect(!FloatingCaptionWindowController.frameIsReasonablyVisible(frame, within: [mainScreen]))
    }

    @Test
    func frameBarelyOverlappingScreenEdgeIsNotVisible() {
        let frame = NSRect(x: 1920 - 40, y: 120, width: 720, height: 170)

        #expect(!FloatingCaptionWindowController.frameIsReasonablyVisible(frame, within: [mainScreen]))
    }

    @Test
    func sufficientOverlapAtScreenEdgeIsVisible() {
        let frame = NSRect(x: 1920 - 200, y: 120, width: 720, height: 170)

        #expect(FloatingCaptionWindowController.frameIsReasonablyVisible(frame, within: [mainScreen]))
    }

    @Test
    func corruptZeroFrameIsNotVisible() {
        #expect(!FloatingCaptionWindowController.frameIsReasonablyVisible(.zero, within: [mainScreen]))
    }

    @Test
    func frameIsNotVisibleWithoutScreens() {
        let frame = NSRect(x: 600, y: 120, width: 720, height: 170)

        #expect(!FloatingCaptionWindowController.frameIsReasonablyVisible(frame, within: []))
    }

    @Test
    func clampedFrameKeepsResizeWithinVisibleScreenBounds() {
        let oversized = NSRect(x: -200, y: -100, width: 2400, height: 1400)
        let clamped = FloatingCaptionWindowController.clampedFrame(oversized, within: mainScreen)

        #expect(clamped.width == mainScreen.width - FloatingCaptionWindowController.screenInset * 2)
        #expect(clamped.height == mainScreen.height - FloatingCaptionWindowController.screenInset * 2)
        #expect(clamped.minX == mainScreen.minX + FloatingCaptionWindowController.screenInset)
        #expect(clamped.minY == mainScreen.minY + FloatingCaptionWindowController.screenInset)
    }

    @Test
    func clampedFrameEnforcesMinimumCaptionWindowSize() {
        let tiny = NSRect(x: 500, y: 200, width: 12, height: 8)
        let clamped = FloatingCaptionWindowController.clampedFrame(tiny, within: mainScreen)

        #expect(clamped.width == FloatingCaptionWindowController.minimumWindowSize.width)
        #expect(clamped.height == FloatingCaptionWindowController.minimumWindowSize.height)
    }


    @Test
    func clampedFrameHonorsDynamicCaptionMinimumSize() {
        let mainScreen = NSRect(x: 0, y: 0, width: 1280, height: 800)
        let dynamicMinimum = NSSize(width: 420, height: 186)
        let tiny = NSRect(x: 20, y: 20, width: 120, height: 90)

        let clamped = FloatingCaptionWindowController.clampedFrame(
            tiny,
            within: mainScreen,
            minimumSize: dynamicMinimum
        )

        #expect(clamped.width == dynamicMinimum.width)
        #expect(clamped.height == dynamicMinimum.height)
    }

    @Test
    func corruptResizeFrameFallsBackToDefaultFiniteSize() {
        let corrupt = NSRect(x: CGFloat.nan, y: 0, width: CGFloat.infinity, height: 100)
        let clamped = FloatingCaptionWindowController.clampedFrame(corrupt, within: mainScreen)

        #expect(clamped.size == FloatingCaptionWindowController.defaultWindowSize)
        #expect(clamped.origin == mainScreen.origin)
    }
}
