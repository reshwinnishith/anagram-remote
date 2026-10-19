import Combine
import Foundation

@MainActor
final class ConnectionViewModel: ObservableObject {
    @Published private(set) var destinations: [MIDIDestination] = []
    @Published private(set) var selectedDestinationID: Int32?
    @Published private(set) var channel: Int = 1
    @Published private(set) var state: ConnectionState = .noDestinationsAvailable
    @Published private(set) var lastTransmission: TransmissionRecord?
    @Published private(set) var lastError: String?

    let manager: MIDIConnectionManager

    init(manager: MIDIConnectionManager) {
        self.manager = manager
        manager.onChange = { [weak self] in self?.sync() }
        sync()
    }

    convenience init() {
        self.init(manager: MIDIConnectionManager(transport: CoreMIDITransport()))
    }

    var canSend: Bool { manager.canSend }

    var statusText: String {
        switch state {
        case .transportUnavailable(let m): return m
        case .noDestinationsAvailable: return "No MIDI destinations found"
        case .noDestinationSelected: return "Select a MIDI destination"
        case .connected(let n): return "Ready: \(n)"
        case .disconnected(let n): return "Disconnected: \(n) (re-select or replug; nothing is sent automatically)"
        }
    }

    func selectDestination(_ id: Int32?) { manager.selectDestination(id: id) }
    func setChannel(_ c: Int) { manager.setChannel(c) }
    func rescan() { manager.refresh() }
    func sendPreset(_ program: Int) { manager.sendProgramChange(program: program) }

    private func sync() {
        destinations = manager.destinations
        selectedDestinationID = manager.selectedDestinationID
        channel = manager.channel
        state = manager.state
        lastTransmission = manager.lastTransmission
        lastError = manager.lastError
    }
}
