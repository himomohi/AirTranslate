import Foundation

enum QwenTranslationModel: String, CaseIterable, Identifiable, Sendable {
    case off
    case liveTranslateFlashRealtime = "qwen3.8-livetranslate-flash-realtime"

    var id: String { rawValue }
    var isEnabled: Bool { self != .off }

    // 워크스페이스는 고정된 싱가포르 서비스 호스트의 단일 DNS 레이블이다.
    static func isValidWorkspaceID(_ value: String) -> Bool {
        value.range(of: "^[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?$", options: .regularExpression) == value.startIndex..<value.endIndex
    }
}

// delta를 그대로 이어 붙이고, final은 현재 발화만 교체한다.
// 서로 같은 단어가 반복되어도 중복으로 판단해 제거하지 않는다.
struct QwenCaptionTranscript {
    private(set) var completed = ""
    private(set) var partial = ""
    private(set) var isFinal = false
    var text: String { completed + partial }

    mutating func receive(_ value: String, isFinal: Bool) {
        if isFinal {
            let final = value
            completed += final
            if !final.isEmpty && !final.hasSuffix("\n") { completed += "\n" }
            partial = ""
        } else {
            partial += value
        }
        self.isFinal = isFinal
    }
}
