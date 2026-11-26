import Foundation

/// A speaker translated speech can play on.
struct SpeechOutputDevice: Identifiable, Equatable, Sendable {
    static let systemDefaultID = "system-default"

    /// The Core Audio device UID, or `systemDefaultID`.
    let id: String
    let name: String
    /// False for a remembered speaker that is not connected right now.
    let isConnected: Bool

    /// The device UID to route to, or nil for the system default.
    var uid: String? { id == Self.systemDefaultID ? nil : id }

    static var systemDefault: SpeechOutputDevice {
        SpeechOutputDevice(id: systemDefaultID, name: AppText.systemDefaultSpeaker, isConnected: true)
    }
}

/// A speech output that can play on a chosen speaker.
protocol SpeechOutputRouting: AnyObject {
    /// Plays on the speaker with this Core Audio UID; nil, or a UID that is not
    /// connected, means the system default output (and follows it when it changes).
    func setOutputDevice(uid: String?)
}
