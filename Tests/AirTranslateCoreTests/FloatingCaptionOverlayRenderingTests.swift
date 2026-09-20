import AppKit
import SwiftUI
import Testing
@testable import AirTranslate

@Suite @MainActor
struct FloatingCaptionOverlayRenderingTests {
    @Test func emptyCaptionsLeaveNoVisiblePixelsForEveryStyle() throws {
        let name = "FloatingCaptionOverlayRenderingTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let session = TranslationSessionStore(modelAvailabilityProvider: { _, _ in [:] }, settingsDefaults: defaults)
        // 기존 불투명 배경 설정을 복원해도 빈 자막에는 창이 드러나지 않아야 한다.
        session.floatingCaptionBackgroundOpacity = 1
        session.floatingCaptionBackgroundColorHex = "#FF0000"
        for preset in FloatingCaptionPreset.allCases {
            session.applyFloatingCaptionPreset(preset)
            let view = hostingView(session)
            let bitmap = try render(view)
            #expect(!hasVisiblePixel(bitmap), "빈 \(preset) 자막에 창·상태·안내가 표시됨")
        }
    }

    @Test func sampleShowsTextWithTransparentPerimeter() async throws {
        let name = "FloatingCaptionOverlayRenderingTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let session = TranslationSessionStore(modelAvailabilityProvider: { _, _ in [:] }, settingsDefaults: defaults)
        session.isPreviewingFloatingCaptions = true
        session.floatingCaptionBackgroundOpacity = 1
        let view = hostingView(session)
        var bitmap = try render(view)
        for _ in 0..<10 {
            if hasVisiblePixel(bitmap) { break }
            try await Task.sleep(for: .milliseconds(50))
            bitmap = try render(view)
        }
        #expect(hasVisiblePixel(bitmap), "샘플 자막이 렌더링되어야 함")
        for x in 0..<bitmap.pixelsWide {
            #expect(alpha(bitmap, x: x, y: 0) == 0)
            #expect(alpha(bitmap, x: x, y: bitmap.pixelsHigh - 1) == 0)
        }
        for y in 0..<bitmap.pixelsHigh {
            #expect(alpha(bitmap, x: 0, y: y) == 0)
            #expect(alpha(bitmap, x: bitmap.pixelsWide - 1, y: y) == 0)
        }
    }

    private func hostingView(_ session: TranslationSessionStore) -> NSHostingView<some View> {
        let view = NSHostingView(rootView: FloatingCaptionWindowView(session: session).frame(width: 720, height: 240))
        view.frame = NSRect(x: 0, y: 0, width: 720, height: 240)
        return view
    }

    private func render(_ view: NSView) throws -> NSBitmapImageRep {
        view.layoutSubtreeIfNeeded()
        let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        return bitmap
    }

    private func alpha(_ bitmap: NSBitmapImageRep, x: Int, y: Int) -> CGFloat {
        bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0
    }

    private func hasVisiblePixel(_ bitmap: NSBitmapImageRep) -> Bool {
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide where alpha(bitmap, x: x, y: y) > 0 { return true }
        }
        return false
    }
}
