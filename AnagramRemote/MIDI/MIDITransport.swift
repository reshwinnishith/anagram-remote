import Foundation

enum MIDITransportError: Error, Equatable, LocalizedError {
    case destinationNotFound(Int32)
    case sendFailed(Int32)
    case clientCreationFailed(Int32)
    case outputPortCreationFailed(Int32)

    var errorDescription: String? {
        switch self {
        case .destinationNotFound(let id): return "MIDI destination \(id) not found."
        case .sendFailed(let s): return "CoreMIDI send failed (OSStatus \(s))."
        case .clientCreationFailed(let s):
            return "Could not start CoreMIDI (client creation failed, OSStatus \(s)). Quit and relaunch the app; if it persists, restart the iPad."
        case .outputPortCreationFailed(let s):
            return "Could not open the CoreMIDI output port (OSStatus \(s)). Quit and relaunch the app; if it persists, restart the iPad."
        }
    }
}

/// Abstraction over the platform MIDI layer so it can be mocked in tests.
@MainActor
protocol MIDITransport: AnyObject {
    /// Current destinations. Reading this must never transmit anything.
    var destinations: [MIDIDestination] { get }
    /// Non-nil if the transport failed to initialise. Such a transport reports no
    /// destinations and `send` always throws this error.
    var initializationError: MIDITransportError? { get }
    /// Called (on the main actor) when the MIDI setup changes (device added/removed).
    var onSetupChanged: (() -> Void)? { get set }
    func send(_ bytes: [UInt8], to destinationID: Int32) throws
}
