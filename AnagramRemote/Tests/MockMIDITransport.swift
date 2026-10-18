import Foundation
@testable import AnagramRemote

@MainActor
final class MockMIDITransport: MIDITransport {
    var destinations: [MIDIDestination]
    var onSetupChanged: (() -> Void)?
    private(set) var sent: [(bytes: [UInt8], destinationID: Int32)] = []

    init(destinations: [MIDIDestination] = []) { self.destinations = destinations }

    func send(_ bytes: [UInt8], to destinationID: Int32) throws {
        sent.append((bytes, destinationID))
    }

    /// Simulates plug/unplug and fires the setup-changed notification.
    func setDestinations(_ new: [MIDIDestination]) {
        destinations = new
        onSetupChanged?()
    }
}
