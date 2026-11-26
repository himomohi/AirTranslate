import CoreAudio
import Foundation

/// Lists the Mac's output devices through Core Audio.
enum SpeechOutputDeviceCatalog {
    /// System Default, every connected output device, and the selected speaker even
    /// while it is disconnected (so Settings can show it as not connected).
    static func availableOutputDevices(selectedID: String, selectedName: String) -> [SpeechOutputDevice] {
        var devices = connectedOutputDevices()
            .map { SpeechOutputDevice(id: $0.uid, name: $0.name, isConnected: true) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        if selectedID != SpeechOutputDevice.systemDefaultID, !devices.contains(where: { $0.id == selectedID }) {
            devices.append(SpeechOutputDevice(id: selectedID, name: selectedName, isConnected: false))
        }
        return [.systemDefault] + devices
    }

    /// The Core Audio device for `uid`, if it is connected and has output channels.
    static func deviceID(forUID uid: String) -> AudioDeviceID? {
        connectedOutputDevices().first { $0.uid == uid }?.id
    }

    static func connectedOutputDevices() -> [(id: AudioDeviceID, uid: String, name: String)] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr
        else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids) == noErr
        else { return [] }
        return ids.compactMap { id in
            guard hasOutputChannels(id),
                  let uid = stringProperty(kAudioDevicePropertyDeviceUID, of: id),
                  let name = stringProperty(kAudioObjectPropertyName, of: id) else { return nil }
            return (id, uid, name)
        }
    }

    private static func hasOutputChannels(_ id: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr, size > 0 else { return false }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, raw) == noErr else { return false }
        let buffers = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        return buffers.contains { $0.mNumberChannels > 0 }
    }

    private static func stringProperty(_ selector: AudioObjectPropertySelector, of id: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr,
              let string = value?.takeRetainedValue() else { return nil }
        return string as String
    }
}
