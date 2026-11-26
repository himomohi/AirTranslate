import CoreGraphics
import Foundation
import Testing
@testable import AirTranslate

@Suite
struct ScreenTextRegionTests {
    private let main = CGRect(x: 0, y: 0, width: 1440, height: 900)
    private let external = CGRect(x: 1440, y: 0, width: 1920, height: 1080)

    @Test func savedRegionRoundTrips() throws {
        let defaults = try #require(UserDefaults(suiteName: "ScreenTextRegionTests-\(UUID().uuidString)"))
        #expect(ScreenTextRegion.saved(in: defaults) == nil)
        let region = CGRect(x: -1200.5, y: 80, width: 640, height: 90)
        ScreenTextRegion.save(region, in: defaults)
        #expect(ScreenTextRegion.saved(in: defaults) == region)
    }

    @Test func regionIsUsableOnlyOnAConnectedScreen() {
        let screens = [main, external]
        #expect(ScreenTextRegion.isOnScreen(CGRect(x: 1600, y: 100, width: 600, height: 80), screens: screens))
        #expect(!ScreenTextRegion.isOnScreen(CGRect(x: 1600, y: 100, width: 600, height: 80), screens: [main]))
        // Center on screen but only a sliver visible.
        #expect(!ScreenTextRegion.isOnScreen(CGRect(x: 1430, y: 100, width: 20, height: 80), screens: [main]))
    }

    @Test func resizingKeepsTheMinimumSizeAndOppositeEdge() {
        let region = CGRect(x: 100, y: 100, width: 300, height: 60)
        let minimum = ScreenTextRegion.minimumSize
        let shrunk = ScreenTextRegion.adjusted(region, edges: [.left, .top], by: CGVector(dx: 1000, dy: -1000))
        #expect(shrunk == CGRect(x: 400 - minimum.width, y: 100, width: minimum.width, height: minimum.height))
        let grown = ScreenTextRegion.adjusted(region, edges: [.right], by: CGVector(dx: 50, dy: 20))
        #expect(grown == CGRect(x: 100, y: 100, width: 350, height: 60))
        let moved = ScreenTextRegion.adjusted(region, edges: [], by: CGVector(dx: -30, dy: 40))
        #expect(moved == CGRect(x: 70, y: 140, width: 300, height: 60))
    }

    @Test func fittingMovesTheRegionOntoTheScreenUnderItsCenter() {
        let screens = [main, external]
        // Dragged partly off the bottom of the external display.
        #expect(ScreenTextRegion.fitted(CGRect(x: 2000, y: -30, width: 600, height: 80), screens: screens)
            == CGRect(x: 2000, y: 0, width: 600, height: 80))
        // Centered on the main screen but hanging past its right edge stays on the main screen.
        #expect(ScreenTextRegion.fitted(CGRect(x: 1000, y: 100, width: 600, height: 80), screens: [main])
            == CGRect(x: 840, y: 100, width: 600, height: 80))
        // Larger than the screen shrinks to fit.
        #expect(ScreenTextRegion.fitted(CGRect(x: -100, y: 0, width: 2000, height: 50), screens: [main])
            == CGRect(x: 0, y: 0, width: 1440, height: 50))
    }

    @Test func onlyTheBorderGrabsEdges() {
        let region = CGRect(x: 100, y: 100, width: 300, height: 60)
        #expect(ScreenTextRegion.edges(at: CGPoint(x: 250, y: 130), of: region, margin: 6) == nil)
        #expect(ScreenTextRegion.edges(at: CGPoint(x: 50, y: 130), of: region, margin: 6) == nil)
        #expect(ScreenTextRegion.edges(at: CGPoint(x: 98, y: 130), of: region, margin: 6) == [.left])
        #expect(ScreenTextRegion.edges(at: CGPoint(x: 403, y: 158), of: region, margin: 6) == [.right, .top])
    }
}
