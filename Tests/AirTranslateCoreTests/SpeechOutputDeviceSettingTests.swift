import Foundation
import Testing
@testable import AirTranslate

@MainActor
@Suite
struct SpeechOutputDeviceSettingTests {
    private func makeDefaults() -> UserDefaults {
        let name = "SpeechOutputDeviceSettingTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func makeStore(_ defaults: UserDefaults) -> TranslationSessionStore {
        TranslationSessionStore(modelAvailabilityProvider: { _, _ in [:] }, settingsDefaults: defaults)
    }

    @Test
    func defaultsToSystemDefaultSpeaker() {
        let store = makeStore(makeDefaults())
        #expect(store.speechOutputDeviceID == SpeechOutputDevice.systemDefaultID)
        #expect(store.speechOutputDevices.first == .systemDefault)
    }

    @Test
    func chosenSpeakerPersistsAcrossStores() {
        let defaults = makeDefaults()
        let store = makeStore(defaults)
        store.speechOutputDeviceID = "test-speaker-uid"
        #expect(makeStore(defaults).speechOutputDeviceID == "test-speaker-uid")
    }

    @Test
    func disconnectedSpeakerStaysSelectedAndListedAsNotConnected() {
        let defaults = makeDefaults()
        defaults.set("gone-speaker-uid", forKey: "speechOutputDeviceID")
        defaults.set("Desk Speakers", forKey: "speechOutputDeviceName")
        let store = makeStore(defaults)
        #expect(store.speechOutputDeviceID == "gone-speaker-uid")
        let selected = store.selectedSpeechOutputDevice
        #expect(selected?.name == "Desk Speakers")
        #expect(selected?.isConnected == false)
        store.refreshSpeechOutputDevices()
        #expect(store.speechOutputDeviceID == "gone-speaker-uid")
    }
}
