/// 캡처 화면, 메뉴바, 키보드 명령이 같은 전환 상태와 동작 가능 조건을 사용한다.
struct CaptureControlState: Equatable {
    let isRunning: Bool
    let isStarting: Bool
    let isPaused: Bool
    var isFinishing = false
    var isReconnectingQwen = false
    var isReconnectingNari = false
    var isReconnectingGrok = false

    var phase: MenuBarCapturePhase {
        MenuBarCapturePhase(
            isRunning: isRunning,
            isStarting: isStarting,
            isPaused: isPaused,
            isFinishing: isFinishing,
            isReconnecting: isReconnectingQwen || isReconnectingNari || isReconnectingGrok
        )
    }

    // TranslationSessionStore.pause()/resume()의 가드와 일치시킨다.
    var canPause: Bool {
        isRunning && !isPaused && !isFinishing && !isReconnectingQwen
    }

    var canResume: Bool {
        isRunning && isPaused && !isFinishing
            && !isReconnectingQwen && !isReconnectingNari && !isReconnectingGrok
    }

    var canTogglePause: Bool { isPaused ? canResume : canPause }
    var canToggleCapture: Bool { phase != .finishing }

    func statusTitle(statusMessage: String) -> String {
        switch phase {
        case .running: AppText.listening
        case .paused: AppText.paused
        case .idle, .starting, .finishing, .reconnecting: statusMessage
        }
    }
}

@MainActor
extension TranslationSessionStore {
    var captureControlState: CaptureControlState {
        CaptureControlState(
            isRunning: isRunning,
            isStarting: isStarting,
            isPaused: isPaused,
            isFinishing: isFinishingAzureMAI || isFinishingNariSTT
                || isFinishingGrokSTT || isFinishingQwenTranslation,
            isReconnectingQwen: isReconnectingQwenTranslation,
            isReconnectingNari: isReconnectingNariSTT,
            isReconnectingGrok: isReconnectingGrokSTT
        )
    }
}
