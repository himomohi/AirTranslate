import AVFoundation
import CoreGraphics
import Observation
import Speech

enum CapturePermissionStatus: Equatable {
    case allowed, notGranted, denied, restricted, notDetermined, unknown

    static func read(_ pane: PrivacySettingsPane) -> Self {
        switch pane {
        case .screenRecording:
            return CGPreflightScreenCaptureAccess() ? .allowed : .notGranted
        case .microphone:
            switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .authorized: return .allowed
            case .denied: return .denied
            case .restricted: return .restricted
            case .notDetermined: return .notDetermined
            @unknown default: return .unknown
            }
        case .speechRecognition:
            switch SFSpeechRecognizer.authorizationStatus() {
            case .authorized: return .allowed
            case .denied: return .denied
            case .restricted: return .restricted
            case .notDetermined: return .notDetermined
            @unknown default: return .unknown
            }
        }
    }
}

@MainActor
@Observable
final class CapturePermissionSetup {
    enum RequestResult: Equatable {
        case allowed, approvalNeeded, settingsRequired, restricted
    }

    enum State: Equatable {
        case idle
        case requesting(PrivacySettingsPane)
        case waiting(PrivacySettingsPane, RequestResult)
        case ready

        var isRequesting: Bool {
            if case .requesting = self { return true }
            return false
        }
    }

    private var plan: [PrivacySettingsPane] = []
    private var state: State = .idle

    var isRequesting: Bool { state.isRequesting }

    static func steps(usesMicrophone: Bool, usesAppleSpeech: Bool) -> [PrivacySettingsPane] {
        // 화면 기록은 macOS에서 앱 재실행이 필요한 경우가 있어 마지막에 요청한다.
        let input: PrivacySettingsPane = usesMicrophone ? .microphone : .screenRecording
        guard usesAppleSpeech else { return [input] }
        return usesMicrophone ? [.microphone, .speechRecognition] : [.speechRecognition, .screenRecording]
    }

    func state(for steps: [PrivacySettingsPane]) -> State {
        steps == plan ? state : .idle
    }

    func canResume(
        steps: [PrivacySettingsPane],
        isAllowed: (PrivacySettingsPane) -> Bool
    ) -> Bool {
        guard case .waiting(let pane, let result) = state(for: steps),
              result != .restricted else { return false }
        return isAllowed(pane)
    }

    func run(
        steps: [PrivacySettingsPane],
        isCurrent: () -> Bool,
        request: (PrivacySettingsPane) async -> RequestResult
    ) async -> PrivacySettingsPane? {
        guard !isRequesting else { return nil }
        plan = steps
        for pane in steps {
            guard isCurrent(), !Task.isCancelled else {
                state = .idle
                return nil
            }
            state = .requesting(pane)
            let result = await request(pane)
            guard isCurrent(), !Task.isCancelled else {
                state = .idle
                return nil
            }
            guard result == .allowed else {
                state = .waiting(pane, result)
                return result == .settingsRequired ? pane : nil
            }
        }
        state = .ready
        return nil
    }

    func dismissPendingSetup() {
        if !isRequesting { state = .idle }
    }
}
