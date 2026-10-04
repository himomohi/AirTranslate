import Foundation

/// 화면 폭이나 문자열 유사도가 아니라 제공자의 발화 경계로 기록을 구분한다.
enum FloatingCaptionIdentity: Hashable, Sendable {
    case appleSegment(String)
    case line(UUID)
}

struct FloatingCaptionHistory: Equatable {
    static let retention: TimeInterval = 8
    static let maximumCharacters = 576
    static let maximumLines = 2

    struct Caption: Hashable {
        let identity: FloatingCaptionIdentity?
        let text: String

        init(identity: FloatingCaptionIdentity?, text: String) {
            self.identity = identity
            self.text = String(text.suffix(FloatingCaptionHistory.maximumCharacters))
        }
    }

    struct Previous: Hashable {
        let caption: Caption
        let retiredAt: Date

        var expiresAt: Date { retiredAt.addingTimeInterval(FloatingCaptionHistory.retention) }
    }

    private(set) var source: Caption?
    private(set) var translation: Caption?
    private(set) var previousSource: Previous?
    private(set) var previousTranslation: Previous?

    var nextExpiry: Date? {
        [previousSource?.expiresAt, previousTranslation?.expiresAt].compactMap { $0 }.min()
    }

    mutating func presentSource(_ text: String, identity: FloatingCaptionIdentity?, keepsHistory: Bool, now: Date) {
        expire(at: now)
        Self.present(text, identity: identity, current: &source, previous: &previousSource, keepsHistory: keepsHistory, now: now)
    }

    mutating func presentTranslation(_ text: String, identity: FloatingCaptionIdentity?, keepsHistory: Bool, now: Date) {
        expire(at: now)
        Self.present(text, identity: identity, current: &translation, previous: &previousTranslation, keepsHistory: keepsHistory, now: now)
    }

    mutating func expire(at now: Date) {
        if let previousSource, previousSource.expiresAt <= now { self.previousSource = nil }
        if let previousTranslation, previousTranslation.expiresAt <= now { self.previousTranslation = nil }
    }

    private static func present(
        _ text: String, identity: FloatingCaptionIdentity?, current: inout Caption?,
        previous: inout Previous?, keepsHistory: Bool, now: Date
    ) {
        guard !text.isEmpty else { current = nil; return }
        if keepsHistory, let current, let oldIdentity = current.identity,
           let identity, oldIdentity != identity, !current.text.isEmpty {
            previous = Previous(caption: current, retiredAt: now)
        }
        // 같은 발화의 확장·교정과 식별자 없는 누적 스트림은 기록을 만들지 않는다.
        current = Caption(identity: identity, text: text)
        if !keepsHistory { previous = nil }
    }
}

/// 기록 유무와 무관하게 같은 공간을 예약해 현재 자막 위치와 창 높이를 고정한다.
struct FloatingCaptionHistoryLayout: Equatable {
    static let historySpacing: CGFloat = 6
    static let historyMotionHeight: CGFloat = 4

    let currentLines: Int
    let historyLines: Int
    let contentHeight: CGFloat

    init(configuredLines: Int, primaryLineHeight: CGFloat, secondaryLineHeight: CGFloat,
         lineSpacing: CGFloat, usesTwoPanes: Bool, availableHeight: CGFloat) {
        let configured = max(1, configuredLines)
        let budget = availableHeight.isFinite && availableHeight > 0 ? availableHeight : 688
        var selection: (Int, Int, CGFloat)?
        // 현재 한 줄과 이전 한 줄을 우선 확보한 다음 설정한 현재 줄 수를 유지한다.
        for current in stride(from: configured, through: 1, by: -1) {
            for history in stride(from: FloatingCaptionHistory.maximumLines, through: 1, by: -1) {
                let height = Self.height(current: current, history: history, primary: primaryLineHeight,
                                         secondary: secondaryLineHeight, spacing: lineSpacing, twoPanes: usesTwoPanes)
                if height <= budget { selection = (current, history, height); break }
            }
            if selection != nil { break }
        }
        if selection == nil {
            for current in stride(from: configured, through: 1, by: -1) {
                let height = Self.height(current: current, history: 0, primary: primaryLineHeight,
                                         secondary: secondaryLineHeight, spacing: lineSpacing, twoPanes: usesTwoPanes)
                if height <= budget || current == 1 { selection = (current, 0, height); break }
            }
        }
        let selected = selection!
        currentLines = selected.0
        historyLines = selected.1
        contentHeight = selected.2
    }

    static func height(current: Int, history: Int, primary: CGFloat, secondary: CGFloat,
                       spacing: CGFloat, twoPanes: Bool) -> CGFloat {
        func pane(_ lineHeight: CGFloat) -> CGFloat {
            FloatingCaptionAppearance.blockHeight(lineHeight: lineHeight, lineCount: current, lineSpacing: spacing)
                + (history > 0 ? FloatingCaptionAppearance.blockHeight(lineHeight: lineHeight, lineCount: history, lineSpacing: spacing)
                   + historySpacing + historyMotionHeight : 0)
        }
        return pane(primary) + (twoPanes ? pane(secondary) + FloatingCaptionAppearance.captionBlockSpacing : 0)
    }
}
