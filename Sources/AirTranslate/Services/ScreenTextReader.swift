import AppKit
import CoreGraphics
import os
import ScreenCaptureKit
@preconcurrency import Vision

/// Watches one screen region (for example a video's subtitle strip) and reports new
/// caption words as they appear.
///
/// The region is captured every `interval` and read line by line. `ScreenTextTracker`
/// turns those reads into new words and caption units (a finished line or a pause), so
/// roll-up captions are neither repeated nor cut into small chunks. AirTranslate's own
/// windows are left out of the capture, so captions may sit on top of the watched region.
private let ocrLog = Logger(subsystem: "dev.appcaster.AirTranslate", category: "ScreenTextOCR")

@MainActor
final class ScreenTextReader {
    /// Logs every OCR read and committed word to the unified log, for diagnosing misreads.
    /// Off by default: it records whatever text is on screen. Turn on with
    /// `defaults write dev.appcaster.AirTranslate ScreenTextDebugLog -bool YES`.
    private let logsReads = UserDefaults.standard.bool(forKey: "ScreenTextDebugLog")
    private var lastLoggedLines: [String] = []
    /// New words (possibly "") and whether they end a caption unit.
    var onText: ((String, Bool) -> Void)?
    /// Called once when capturing keeps failing (for example the display went away).
    var onFailure: ((Error) -> Void)?

    let region: CGRect
    private let interval: Duration
    private let recognitionLanguages: [String]
    private var tracker = ScreenTextTracker()
    private var loopTask: Task<Void, Never>?
    private var outline: ScreenTextRegionOutline?
    private var filter: SCContentFilter?
    private var configuration: SCStreamConfiguration?
    private var consecutiveFailures = 0

    init(region: CGRect, language: LanguageOption, interval: Duration = .milliseconds(100)) {
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
                try? await Task.sleep(until: started + self.interval, clock: .continuous)
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
            if filter == nil {
                do {
                    try await prepareCapture()
                } catch is CancellationError {
                    return
                } catch {
                    // Setting up asks macOS for screen access, and each refused attempt can
                    // show another permission prompt: give up at once instead of retrying.
                    fail(with: error)
                    return
                }
            }
            let started = ContinuousClock.now
            let image = try await captureFrame()
            consecutiveFailures = 0
            let captured = ContinuousClock.now
            let languages = recognitionLanguages
            // Vision takes ~40 ms here, so every frame is read; no change detection to miss words.
            let lines = await Task.detached(priority: .userInitiated) {
                Self.recognizeLines(in: image, languages: languages)
            }.value
            guard !Task.isCancelled else { return }
            let finished = ContinuousClock.now
            if logsReads, finished - started > .milliseconds(300) {
                ocrLog.notice("slow pass: capture \(String(describing: captured - started), privacy: .public), OCR \(String(describing: finished - captured), privacy: .public)")
            }
            if logsReads, lines != lastLoggedLines {
                lastLoggedLines = lines
                ocrLog.notice("read: \(lines.joined(separator: " | "), privacy: .public)")
            }
            for (text, endsUnit) in tracker.ingest(lines, now: .now) {
                if logsReads {
                    ocrLog.notice("commit\(endsUnit ? " ⏎" : "", privacy: .public): \(text, privacy: .public)")
                }
                onText?(text, endsUnit)
            }
        } catch is CancellationError {
            return
        } catch {
            if Self.isPermissionDenial(error) {
                fail(with: error)
                return
            }
            consecutiveFailures += 1
            // A display or window may have changed: rebuild once, but not on every failure.
            if consecutiveFailures == 2 { filter = nil }
            if consecutiveFailures >= 5 { fail(with: error) }
        }
    }

    private func fail(with error: Error) {
        guard loopTask != nil else { return }
        stop()
        onFailure?(error)
    }

    nonisolated static func isPermissionDenial(_ error: Error) -> Bool {
        let error = error as NSError
        return error.domain == SCStreamErrorDomain && error.code == SCStreamError.Code.userDeclined.rawValue
    }

    // MARK: - Capture

    private func captureFrame() async throws -> CGImage {
        guard let filter, let configuration else { throw ScreenTextReaderError.captureFailed }
        return try await Self.withTimeout(.seconds(2)) {
            try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        }
    }

    /// Gives up on a capture that never returns, which would otherwise stall reading.
    /// (Unlike a task group, this does not wait for an operation that ignores cancellation.)
    private static func withTimeout<T: Sendable>(
        _ limit: Duration, _ operation: @escaping @MainActor () async throws -> T
    ) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            var finished = false
            let finish: @MainActor (Result<T, Error>) -> Void = { result in
                guard !finished else { return }
                finished = true
                continuation.resume(with: result)
            }
            let work = Task { @MainActor in
                do { finish(.success(try await operation())) } catch { finish(.failure(error)) }
            }
            Task { @MainActor in
                try? await Task.sleep(for: limit)
                work.cancel()
                finish(.failure(ScreenTextReaderError.captureFailed))
            }
        }
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
        // Small captions read more reliably at 2x.
        let scale: CGFloat = clipped.height < 100 ? 2 : 1
        config.width = Int(ceil(clipped.width * scale))
        config.height = Int(ceil(clipped.height * scale))
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

    /// A recognized piece of text with its box in normalized image coordinates (origin bottom-left).
    struct TextBox: Equatable {
        var text: String
        var box: CGRect
    }

    /// Caption lines top to bottom, without lines cut off at the region's edge.
    nonisolated static func recognizeLines(in image: CGImage, languages: [String]) -> [String] {
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
            return []
        }
        let boxes = (request.results ?? []).compactMap { observation -> TextBox? in
            guard observation.confidence >= 0.3, let text = observation.topCandidates(1).first?.string else { return nil }
            return TextBox(text: text, box: observation.boundingBox)
        }
        return captionLines(from: boxes)
    }

    /// Groups boxes into rows (top to bottom, left to right) and keeps only caption-like text:
    /// - boxes whose height is far from the caption height (taken from boxes with 3+ words)
    ///   are video graphics, and all-caps snippets are titles or map labels;
    /// - a box sitting well apart from the caption on the same row is not part of it;
    /// - a row that touches the top or bottom edge while shorter than the tallest row is a
    ///   line scrolled half out.
    nonisolated static func captionLines(from boxes: [TextBox]) -> [String] {
        let wordy = boxes.filter { $0.text.split(separator: " ").count >= 3 }.map(\.box.height).sorted()
        let captionHeight = wordy.isEmpty ? nil : wordy[wordy.count / 2]
        // Drop all-caps snippets only next to normal dialogue, so all-caps subtitles still work.
        let hasDialogue = boxes.contains { !isLabel($0.text) && $0.text.split(separator: " ").count >= 3 }
        let candidates = boxes.filter { box in
            if hasDialogue, isLabel(box.text) { return false }
            guard let captionHeight else { return true }
            return box.box.height > captionHeight * 0.75 && box.box.height < captionHeight * 1.35
        }
        var rows: [[TextBox]] = []
        for box in candidates.sorted(by: { $0.box.midY > $1.box.midY }) {
            if let last = rows.last?.last, abs(last.box.midY - box.box.midY) < last.box.height / 2 {
                rows[rows.count - 1].append(box)
            } else {
                rows.append([box])
            }
        }
        rows = rows.map(mainRun)
        let tallest = rows.map { $0.map(\.box.height).max() ?? 0 }.max() ?? 0
        return rows.compactMap { row in
            let minY = row.map(\.box.minY).min() ?? 0
            let maxY = row.map(\.box.maxY).max() ?? 0
            let height = row.map(\.box.height).max() ?? 0
            let touchesEdge = minY < 0.02 || maxY > 0.98
            if touchesEdge, height < tallest * 0.85 { return nil }
            return row.map(\.text).joined(separator: " ")
        }
    }

    /// The horizontally adjacent boxes around the longest one (gaps under 1.5 line heights).
    private nonisolated static func mainRun(_ row: [TextBox]) -> [TextBox] {
        let sorted = row.sorted { $0.box.minX < $1.box.minX }
        var runs: [[TextBox]] = []
        for box in sorted {
            if let last = runs.last?.last, box.box.minX - last.box.maxX < last.box.height * 1.5 {
                runs[runs.count - 1].append(box)
            } else {
                runs.append([box])
            }
        }
        return runs.max { $0.map(\.text.count).reduce(0, +) < $1.map(\.text.count).reduce(0, +) } ?? sorted
    }

    /// Short all-caps text (CHINA, MOUNTAIN RANGES RANKED) is a label, not dialogue.
    private nonisolated static func isLabel(_ text: String) -> Bool {
        let letters = text.filter(\.isLetter)
        return letters.count >= 2 && letters == letters.uppercased() && text.split(separator: " ").count <= 5
    }
}

enum ScreenTextReaderError: LocalizedError {
    case captureFailed
    case noDisplay
    case invalidRegion

    var errorDescription: String? { AppText.screenTextCaptureFailed }
}

// MARK: - Caption tracking

/// Turns per-frame caption lines into newly appeared words and caption units.
///
/// Committed words form a rolling transcript. Each frame is aligned against its tail with
/// fuzzy word matching (one misread word does not break the match), so roll-up captions
/// only yield their new words. A word is committed as soon as another word follows it;
/// the last word on screen waits until the frame has been stable for `settleDelay`.
/// A unit ends when the bottom line moves up (a new line starts) or the text pauses.
struct ScreenTextTracker {
    static let settleDelay: Duration = .milliseconds(500)
    private static let transcriptLimit = 60

    private(set) var transcript: [String] = []
    private var lastFrame: [String] = []
    /// Words of the last frame not committed yet (the last word, until it settles).
    private var uncommitted: [String] = []
    private var lastChange = ContinuousClock.now
    private var signaledPause = true

    mutating func ingest(_ lines: [String], now: ContinuousClock.Instant) -> [(String, Bool)] {
        let rows = lines.map { $0.split(whereSeparator: \.isWhitespace).map(String.init) }.filter { !$0.isEmpty }
        let frame = rows.flatMap { $0 }
        if frame != lastFrame {
            lastFrame = frame
            lastChange = now
            signaledPause = false
            if frame.isEmpty {
                // The caption cleared: whatever was still pending is complete.
                let rest = uncommitted
                uncommitted = []
                return [(commit(rest), true)]
            }
        }
        guard !frame.isEmpty else { return [] }

        let stable = now - lastChange >= Self.settleDelay
        let known = Self.overlap(transcript, frame)
        let bottomStart = frame.count - (rows.last?.count ?? 0)
        let commitEnd = stable ? frame.count : frame.count - 1
        var out: [(String, Bool)] = []

        if known < bottomStart {
            // Upper lines have scrolled up, so they are complete.
            out.append((commit(Array(frame[known..<min(bottomStart, commitEnd)])), true))
        } else if known == bottomStart, bottomStart > 0, commitEnd > bottomStart {
            // A new bottom line started after complete lines.
            out.append(("", true))
        }
        let start = max(known, bottomStart)
        if start < commitEnd {
            out.append((commit(Array(frame[start..<commitEnd])), false))
        }
        uncommitted = Array(frame[max(commitEnd, known)...])
        if stable, !signaledPause {
            signaledPause = true
            out.append(("", true))
        }
        return out.filter { !$0.0.isEmpty || $0.1 }
    }

    private mutating func commit(_ words: [String]) -> String {
        transcript.append(contentsOf: words)
        if transcript.count > Self.transcriptLimit { transcript.removeFirst(transcript.count - Self.transcriptLimit) }
        return words.joined(separator: " ")
    }

    /// How many leading words of `frame` are already in the transcript.
    static func overlap(_ transcript: [String], _ frame: [String]) -> Int {
        let tail = transcript.suffix(transcriptLimit).map(normalized)
        let words = frame.map(normalized)
        guard !tail.isEmpty, !words.isEmpty else { return 0 }
        // The whole frame is old text (for example the bottom line briefly not read).
        if words.count >= 2, tail.count >= words.count {
            for end in stride(from: tail.count, through: words.count, by: -1)
            where matches(Array(tail[(end - words.count)..<end]), words) {
                return words.count
            }
        }
        // A suffix of the transcript is a prefix of the frame (roll-up).
        for length in stride(from: min(tail.count, words.count), through: 1, by: -1) {
            guard length >= 2 || words.count == 1 else { break }
            if matches(Array(tail.suffix(length)), Array(words.prefix(length))) { return length }
        }
        return 0
    }

    private static func matches(_ a: [String], _ b: [String]) -> Bool {
        let misses = zip(a, b).filter { !similar($0, $1) }.count
        return misses <= a.count / 4
    }

    private static func similar(_ a: String, _ b: String) -> Bool {
        if a == b { return true }
        guard a.count >= 4, b.count >= 4, abs(a.count - b.count) <= 1 else { return false }
        return editDistance(Array(a), Array(b)) <= 1
    }

    private static func normalized(_ word: String) -> String {
        word.lowercased().trimmingCharacters(in: .punctuationCharacters)
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
