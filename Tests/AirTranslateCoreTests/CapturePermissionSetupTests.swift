import Testing
@testable import AirTranslate

@MainActor
struct CapturePermissionSetupTests {
    @Test
    func requestsOnlyPermissionsForTheSelectedInputAndTranscriber() {
        #expect(CapturePermissionSetup.steps(usesMicrophone: true, usesAppleSpeech: false) == [.microphone])
        #expect(CapturePermissionSetup.steps(usesMicrophone: false, usesAppleSpeech: false) == [.screenRecording])
        #expect(CapturePermissionSetup.steps(usesMicrophone: true, usesAppleSpeech: true) == [.microphone, .speechRecognition])
        #expect(CapturePermissionSetup.steps(usesMicrophone: false, usesAppleSpeech: true) == [.speechRecognition, .screenRecording])
    }

    @Test
    func runsOneStepAtATimeAndReportsReady() async {
        let setup = CapturePermissionSetup()
        let steps: [PrivacySettingsPane] = [.microphone, .speechRecognition]
        var checked: [PrivacySettingsPane] = []

        let settings = await setup.run(steps: steps, isCurrent: { true }) { pane in
            #expect(setup.state(for: steps) == .requesting(pane))
            checked.append(pane)
            let duplicate = await setup.run(steps: steps, isCurrent: { true }) { _ in
                Issue.record("Duplicate setup must not request permissions")
                return .allowed
            }
            #expect(duplicate == nil)
            return .allowed
        }

        #expect(settings == nil)
        #expect(checked == steps)
        #expect(setup.state(for: steps) == .ready)
    }

    @Test
    func stoppedStepRoutesToItsOwnSettingsAndResumesAfterApproval() async {
        let setup = CapturePermissionSetup()
        let steps: [PrivacySettingsPane] = [.microphone, .speechRecognition]

        let settings = await setup.run(steps: steps, isCurrent: { true }) { pane in
            #expect(pane == .microphone)
            return .settingsRequired
        }

        #expect(settings == .microphone)
        #expect(setup.state(for: steps) == .waiting(.microphone, .settingsRequired))
        #expect(!setup.canResume(steps: steps, isAllowed: { _ in false }))
        #expect(!setup.canResume(steps: [.screenRecording], isAllowed: { _ in true }))
        #expect(setup.canResume(steps: steps, isAllowed: { $0 == .microphone }))
    }

    @Test
    func pendingSystemPromptDoesNotOpenSettingsOverThePrompt() async {
        let setup = CapturePermissionSetup()
        let steps: [PrivacySettingsPane] = [.screenRecording]
        let settings = await setup.run(steps: steps, isCurrent: { true }) { _ in .approvalNeeded }

        #expect(settings == nil)
        #expect(setup.state(for: steps) == .waiting(.screenRecording, .approvalNeeded))
    }

    @Test
    func configurationChangeDuringARequestStopsBeforeAnotherPrompt() async {
        let setup = CapturePermissionSetup()
        let steps: [PrivacySettingsPane] = [.microphone, .speechRecognition]
        var stillCurrent = true
        let settings = await setup.run(steps: steps, isCurrent: { stillCurrent }) { pane in
            #expect(pane == .microphone)
            stillCurrent = false
            return .allowed
        }

        #expect(settings == nil)
        #expect(setup.state(for: steps) == .idle)
    }
}
