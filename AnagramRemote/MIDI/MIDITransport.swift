import Foundation

enum MIDITransportError: Error, Equatable, LocalizedError {
    case destinationNotFound(Int32)
    case sendFailed(Int32)

    var errorDescription: String? {
        switch self {
        case .destinationNotFound(let id): return "MIDI destination \(id) not found."
        case .sendFailed(let s): return "CoreMIDI send failed (OSStatus \(s))."
        }
    }
}

/// Abstraction over the platform MIDI layer so it can be mocked in tests.
@MainActor
protocol MIDITransport: AnyObject {
    /// Current destinations. Reading this must never transmit anything.
    var destinations: [MIDIDestination] { get }
    /// Called (on the main actor) when the MIDI setup changes (device added/removed).
    var onSetupChanged: (() -> Void)? { get set }
    func send(_ bytes: [UInt8], to destinationID: Int32) throws
}
