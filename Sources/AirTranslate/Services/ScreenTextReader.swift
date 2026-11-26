import AppKit
import CoreGraphics
import ScreenCaptureKit
@preconcurrency import Vision

/// Watches one screen region (for example a video's subtitle strip) and reports
/// its text each time it changes.
///
/// The region is captured every `interval` and re-read only when its pixels change.
/// A new text is reported only after two matching reads, so fade-in frames and OCR
/// jitter don't flicker. AirTranslate's own windows are left out of the capture, so
/// captions may sit on top of the watched region.
@MainActor
final class ScreenTextReader {
    /// Called with each new stable text ("" once the region no longer shows text).
    var onTextChanged: ((String) -> Void)?
    /// Called once when capturing keeps failing (for example the display went away).
    var onFailure: ((Error) -> Void)?

    let region: CGRect
    private let interval: Duration
    private let recognitionLanguages: [String]
    private var stabilizer = ScreenTextStabilizer()
    private var loopTask: Task<Void, Never>?
    private var outline: ScreenTextRegionOutline?
    private var filter: SCContentFilter?
    private var configuration: SCStreamConfiguration?
    private var lastFingerprint: [UInt8]?
    private var lastRawText = ""
    private var lastRecognition = ContinuousClock.now
    private var consecutiveFailures = 0

    /// Gap before the confirming read of a new line, well under one interval.
    private static let confirmDelay: Duration = .milliseconds(60)
    /// Re-read at least this often even when the frame looks unchanged.
    private static let maxSkip: Duration = .seconds(1)

    init(region: CGRect, language: LanguageOption, interval: Duration = .milliseconds(250)) {
        self.region = region.integral
        self.interval = interval
        recognitionLanguages = Self.visionLanguages(for: language)
    }

    func start() {
        guard loopTask == nil else { return }
        outline = ScreenTextRegionOutline(region: region)
        outline?.orderFrontRegardless()
        loopTask = Task { [weak self] in
            while !Task.isCancelled {
                let started = ContinuousClock.now
                guard let self else { return }
                await self.tick()
                let delay = self.stabilizer.isConfirming ? Self.confirmDelay : self.interval
                try? await Task.sleep(until: started + delay, clock: .continuous)
            }
        }
    }

    func stop() {
        loopTask?.cancel()
        loopTask = nil
        outline?.orderOut(nil)
        outline = nil
    }

    private func tick() async {
        do {
            let image = try await captureFrame()
            consecutiveFailures = 0
            let fingerprint = Self.fingerprint(of: image)
            if let lastFingerprint, let fingerprint, Self.isSameFrame(lastFingerprint, fingerprint),
               ContinuousClock.now - lastRecognition < Self.maxSkip {
                emit(stabilizer.ingest(lastRawText))
                return
            }
            lastFingerprint = fingerprint
            lastRecognition = .now
            let languages = recognitionLanguages
            let text = await Task.detached(priority: .userInitiated) {
                Self.recognizeText(in: image, languages: languages)
            }.value
            guard !Task.isCancelled else { return }
            lastRawText = text
            emit(stabilizer.ingest(text))
        } catch is CancellationError {
            return
        } catch {
            consecutiveFailures += 1
            filter = nil  // Displays or windows may have changed; rebuild on the next pass.
            if consecutiveFailures >= 5 {
                stop()
                onFailure?(error)
            }
        }
    }

    private func emit(_ text: String?) {
        guard let text, !Task.isCancelled else { return }
        onTextChanged?(text)
    }

    // MARK: - Capture

    private func captureFrame() async throws -> CGImage {
        if filter == nil { try await prepareCapture() }
        guard let filter, let configuration else { throw ScreenTextReaderError.captureFailed }
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
    }

    private func prepareCapture() async throws {
        let center = CGPoint(x: region.midX, y: region.midY)
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(center) }) ?? NSScreen.main,
              let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
        else { throw ScreenTextReaderError.noDisplay }

        let clipped = screen.frame.intersection(region)
        guard !clipped.isNull, clipped.width >= 4, clipped.height >= 4 else { throw ScreenTextReaderError.invalidRegion }

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw ScreenTextReaderError.noDisplay
        }
        let ownApps = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
        let config = SCStreamConfiguration()
        config.sourceRect = Self.sourceRect(clipped, on: screen.frame)
        config.width = Int(ceil(clipped.width))
        config.height = Int(ceil(clipped.height))
        config.showsCursor = false

        filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])
        configuration = config
    }

    /// Converts a global AppKit rect (bottom-left origin) into the display's top-left coordinates.
    nonisolated static func sourceRect(_ region: CGRect, on screenFrame: CGRect) -> CGRect {
        CGRect(x: region.minX - screenFrame.minX, y: screenFrame.maxY - region.maxY,
               width: region.width, height: region.height)
    }

    // MARK: - Recognition

    /// Vision language codes for `language`, or [] to let Vision detect it.
    nonisolated static func visionLanguages(
        for language: LanguageOption,
        supported: [String] = supportedVisionLanguages()
    ) -> [String] {
        if supported.contains(language.id) { return [language.id] }
        let code = Locale.Language(identifier: language.id).languageCode?.identifier ?? language.id
        let wanted = code == "zh" ? "zh-Hans" : code
        if let match = supported.first(where: { $0 == wanted || $0.hasPrefix(wanted + "-") }) { return [match] }
        return []
    }

    private nonisolated static func supportedVisionLanguages() -> [String] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        return (try? request.supportedRecognitionLanguages()) ?? []
    }

    /// Recognized lines top to bottom, joined with spaces: subtitle lines usually split one sentence.
    nonisolated static func recognizeText(in image: CGImage, languages: [String]) -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        if languages.isEmpty {
            request.automaticallyDetectsLanguage = true
        } else {
            request.recognitionLanguages = languages
        }
        do {
            try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        } catch {
            return ""
        }
        return (request.results ?? [])
            .filter { $0.confidence >= 0.3 }
            .sorted { $0.boundingBox.midY > $1.boundingBox.midY }
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: " ")
    }

    // MARK: - Change detection

    private nonisolated static let fingerprintSize = (width: 128, height: 32)

    /// A tiny grayscale thumbnail; comparing two is far cheaper than OCR.
    nonisolated static func fingerprint(of image: CGImage) -> [UInt8]? {
        let (width, height) = fingerprintSize
        var pixels = [UInt8](repeating: 0, count: width * height)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width,
                                          space: CGColorSpaceCreateDeviceGray(),
                                          bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            context.interpolationQuality = .low
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return drawn ? pixels : nil
    }

    /// Unchanged unless more than a couple of pixels moved noticeably.
    nonisolated static func isSameFrame(_ a: [UInt8], _ b: [UInt8]) -> Bool {
        guard a.count == b.count, !a.isEmpty else { return false }
        var changed = 0
        for index in a.indices where abs(Int(a[index]) - Int(b[index])) > 24 {
            changed += 1
            if changed > 2 { return false }
        }
        return true
    }
}

enum ScreenTextReaderError: LocalizedError {
    case captureFailed
    case noDisplay
    case invalidRegion

    var errorDescription: String? { AppText.screenTextCaptureFailed }
}

// MARK: - Stabilizer

/// Turns a stream of raw OCR reads into stable text changes.
struct ScreenTextStabilizer {
    var requiredReads = 2
    var clearAfterEmptyReads = 3

    private(set) var committed = ""
    var isConfirming: Bool { candidateReads > 0 }
    private var candidate = ""
    private var candidateReads = 0
    private var emptyReads = 0

    /// Returns the new committed text when it changes, otherwise nil.
    mutating func ingest(_ raw: String) -> String? {
        let text = raw.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !text.isEmpty else {
            candidate = ""
            candidateReads = 0
            emptyReads += 1
            if !committed.isEmpty, emptyReads >= clearAfterEmptyReads {
                committed = ""
                return ""
            }
            return nil
        }
        emptyReads = 0
        if Self.isSimilar(text, committed) {
            candidate = ""
            candidateReads = 0
            return nil
        }
        candidateReads = Self.isSimilar(text, candidate) ? candidateReads + 1 : 1
        candidate = text
        guard candidateReads >= requiredReads else { return nil }
        committed = candidate
        candidate = ""
        candidateReads = 0
        return committed
    }

    /// The same subtitle read twice with a few characters of OCR noise counts as equal.
    static func isSimilar(_ a: String, _ b: String) -> Bool {
        if a == b { return true }
        guard !a.isEmpty, !b.isEmpty else { return false }
        let tolerance = max(1, max(a.count, b.count) / 12)
        guard abs(a.count - b.count) <= tolerance else { return false }
        return editDistance(Array(a.lowercased()), Array(b.lowercased())) <= tolerance
    }

    private static func editDistance(_ a: [Character], _ b: [Character]) -> Int {
        var previous = Array(0...b.count)
        var current = previous
        for i in 1...a.count {
            current[0] = i
            for j in 1...b.count {
                current[j] = min(previous[j] + 1, current[j - 1] + 1,
                                 previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
            swap(&previous, &current)
        }
        return previous[b.count]
    }
}

// MARK: - Region outline

/// Click-through dashed frame showing which region is being watched.
private final class ScreenTextRegionOutline: NSWindow {
    init(region: CGRect) {
        super.init(contentRect: region.insetBy(dx: -4, dy: -4), styleMask: .borderless,
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        ignoresMouseEvents = true
        hasShadow = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isReleasedWhenClosed = false
        contentView = OutlineView()
    }

    private final class OutlineView: NSView {
        override func draw(_ dirtyRect: NSRect) {
            let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1.5, dy: 1.5), xRadius: 4, yRadius: 4)
            path.lineWidth = 2
            path.setLineDash([6, 4], count: 2, phase: 0)
            NSColor.systemOrange.withAlphaComponent(0.85).setStroke()
            path.stroke()
        }
    }
}

// MARK: - Region picker

/// Full-screen overlay for dragging out the region to watch. Esc or a click cancels.
final class ScreenTextRegionPicker: NSWindow {
    var onPicked: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?

    init() {
        let frame = NSScreen.screens.reduce(CGRect.null) { $0.union($1.frame) }
        super.init(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        level = .screenSaver
        hasShadow = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let view = PickerView(frame: CGRect(origin: .zero, size: frame.size))
        view.onFinish = { [weak self] rect in self?.finish(rect) }
        contentView = view
    }

    func begin() {
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
        makeFirstResponder(contentView)
        NSCursor.crosshair.push()
    }

    func end() {
        NSCursor.pop()
        orderOut(nil)
    }

    private func finish(_ rect: CGRect?) {
        end()
        if let rect { onPicked?(convertToScreen(rect)) } else { onCancel?() }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { finish(nil) } else { super.keyDown(with: event) }
    }

    override var canBecomeKey: Bool { true }

    private final class PickerView: NSView {
        var onFinish: ((CGRect?) -> Void)?
        private var start: NSPoint?
        private var current: NSPoint?

        override var acceptsFirstResponder: Bool { true }

        private var selection: CGRect? {
            guard let start, let current else { return nil }
            return CGRect(x: min(start.x, current.x), y: min(start.y, current.y),
                          width: abs(start.x - current.x), height: abs(start.y - current.y))
        }

        override func draw(_ dirtyRect: NSRect) {
            NSColor.black.withAlphaComponent(0.3).setFill()
            bounds.fill()
            guard let selection else {
                drawHint()
                return
            }
            NSColor.clear.setFill()
            selection.fill(using: .copy)
            NSColor.systemOrange.withAlphaComponent(0.15).setFill()
            selection.fill()
            let border = NSBezierPath(rect: selection)
            border.lineWidth = 1.5
            border.setLineDash([5, 3], count: 2, phase: 0)
            NSColor.white.setStroke()
            border.stroke()
        }

        private func drawHint() {
            let text = NSAttributedString(string: AppText.screenTextPickRegionHint, attributes: [
                .font: NSFont.systemFont(ofSize: 20, weight: .medium),
                .foregroundColor: NSColor.white,
            ])
            let size = text.size()
            // Center on the screen under the mouse, not the union of all screens.
            let mouse = NSEvent.mouseLocation
            let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
            let screenFrame = window.map { w in screen.map { w.convertFromScreen($0.frame) } ?? bounds } ?? bounds
            let pill = CGRect(x: screenFrame.midX - size.width / 2 - 20, y: screenFrame.midY - size.height / 2 - 14,
                              width: size.width + 40, height: size.height + 28)
            NSColor.black.withAlphaComponent(0.65).setFill()
            NSBezierPath(roundedRect: pill, xRadius: 14, yRadius: 14).fill()
            text.draw(at: CGPoint(x: pill.minX + 20, y: pill.minY + 14))
        }

        override func mouseDown(with event: NSEvent) {
            start = convert(event.locationInWindow, from: nil)
            current = start
            needsDisplay = true
        }

        override func mouseDragged(with event: NSEvent) {
            current = convert(event.locationInWindow, from: nil)
            needsDisplay = true
        }

        override func mouseUp(with event: NSEvent) {
            let picked = selection.flatMap { $0.width >= 20 && $0.height >= 10 ? $0 : nil }
            start = nil
            current = nil
            onFinish?(picked)
        }
    }
}
