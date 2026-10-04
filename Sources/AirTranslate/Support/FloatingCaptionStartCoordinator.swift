import Foundation
import Observation

/// 전용 보기 요청을 캡처 수명과 연결하고, 실제 듣기가 시작된 뒤에만 메인 창을 숨긴다.
@MainActor
final class FloatingCaptionStartCoordinator {
    private let phase: () -> MenuBarCapturePhase
    private let start: () -> Void
    private let resume: () -> Void
    private let minimizeMainWindows: () -> Void
    private let showMainWindows: () -> Void
    private var requestID: UUID?

    init(
        phase: @escaping () -> MenuBarCapturePhase,
        start: @escaping () -> Void,
        resume: @escaping () -> Void,
        minimizeMainWindows: @escaping () -> Void,
        showMainWindows: @escaping () -> Void
    ) {
        self.phase = phase
        self.start = start
        self.resume = resume
        self.minimizeMainWindows = minimizeMainWindows
        self.showMainWindows = showMainWindows
    }

    func begin() {
        let id = UUID()
        requestID = id
        switch phase() {
        case .idle: start()
        case .paused: resume()
        case .starting, .running, .finishing, .reconnecting: break
        }
        trackStart(id: id)
    }

    func cancel() {
        // 창을 닫거나 함께 보기로 바꾼 뒤 늦게 끝난 시작 요청이 창을 숨기지 않게 한다.
        requestID = nil
    }

    private func trackStart(id: UUID) {
        guard requestID == id else { return }
        let currentPhase = withObservationTracking {
            phase()
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.trackStart(id: id)
            }
        }

        switch currentPhase {
        case .running:
            requestID = nil
            minimizeMainWindows()
        case .starting, .reconnecting:
            break
        case .idle, .paused, .finishing:
            requestID = nil
            // 권한·자산·연결 실패 또는 취소는 메인 창에서 확인하고 복구한다.
            showMainWindows()
        }
    }
}
