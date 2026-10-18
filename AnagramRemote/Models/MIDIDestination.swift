import Foundation

/// A MIDI output endpoint as seen by the app. `id` is the CoreMIDI unique ID,
/// which stays stable while the device is plugged in and across reconnects.
struct MIDIDestination: Identifiable, Hashable {
    let id: Int32
    let name: String
}
