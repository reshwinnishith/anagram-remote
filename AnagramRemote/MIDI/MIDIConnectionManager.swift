import Foundation

enum MIDISendError: Error, Equatable, LocalizedError {
    case noDestinationSelected
    case destinationUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .noDestinationSelected: return "No MIDI destination selected."
        case .destinationUnavailable(let n): return "Destination “\(n)” is not connected."
        }
    }
}

enum ConnectionState: Equatable {
    /// CoreMIDI could not be initialised; the message is user-facing. Nothing can be sent.
    case transportUnavailable(String)
    case noDestinationsAvailable
    case noDestinationSelected
    case connected(String)
    /// Selected destination vanished. Selection is remembered so we can show
    /// "reconnected" when it returns — but nothing is ever sent automatically.
    case disconnected(String)
}

/// Owns destination list, selection, channel, and send diagnostics.
/// Sends happen ONLY via `sendProgramChange`, which is called from explicit user actions.
@MainActor
final class MIDIConnectionManager: MIDICommandSending {
    private let transport: MIDITransport

    private(set) var destinations: [MIDIDestination] = []
    private(set) var selectedDestinationID: Int32?
    private var selectedDestinationName: String?
    private(set) var channel: Int = 1
    private(set) var lastTransmission: TransmissionRecord?
    private(set) var lastError: String?
    private(set) var lastCommandRecord: CommandRecord?
    private(set) var lastCommandFailure: String?

    /// Fired after any state change so the view model can republish.
    var onChange: (() -> Void)?

    init(transport: MIDITransport) {
        self.transport = transport
        lastError = transport.initializationError?.localizedDescription
        refresh()
        transport.onSetupChanged = { [weak self] in self?.refresh() }
    }

    var state: ConnectionState {
        if let e = transport.initializationError { return .transportUnavailable(e.localizedDescription) }
        guard let id = selectedDestinationID, let name = selectedDestinationName else {
            return destinations.isEmpty ? .noDestinationsAvailable : .noDestinationSelected
        }
        return destinations.contains { $0.id == id } ? .connected(name) : .disconnected(name)
    }

    var canSend: Bool {
        if case .connected = state { return true }
        return false
    }

    func refresh() {
        let new = transport.destinations
        if new != destinations {
            destinations = new
            if let id = selectedDestinationID, let match = new.first(where: { $0.id == id }) {
                selectedDestinationName = match.name
            }
        }
        onChange?()
    }

    func selectDestination(id: Int32?) {
        if let id, let d = destinations.first(where: { $0.id == id }) {
            selectedDestinationID = d.id
            selectedDestinationName = d.name
        } else {
            selectedDestinationID = nil
            selectedDestinationName = nil
        }
        onChange?()
    }

    func setChannel(_ newChannel: Int) {
        guard ProgramNumbering.channelRange.contains(newChannel) else {
            lastError = MIDIValidationError.invalidChannel(newChannel).localizedDescription
            onChange?()
            return
        }
        guard newChannel != channel else { return }
        channel = newChannel
        onChange?()
    }

    /// Validates, then hands exactly one Program Change to the transport.
    @discardableResult
    func sendProgramChange(program: Int) -> Bool {
        do {
            if let e = transport.initializationError { throw e }
            let bytes = try MIDICommand.programChange(channel: channel, program: program).bytes()
            guard let id = selectedDestinationID, let name = selectedDestinationName else {
                throw MIDISendError.noDestinationSelected
            }
            guard destinations.contains(where: { $0.id == id }) else {
                throw MIDISendError.destinationUnavailable(name)
            }
            try transport.send(bytes, to: id)
            lastTransmission = TransmissionRecord(date: Date(), destinationName: name,
                                                  channel: channel, program: program, bytes: bytes)
            lastError = nil
            onChange?()
            return true
        } catch {
            lastError = error.localizedDescription
            onChange?()
            return false
        }
    }

    func selectedDestination() -> MIDIDestination? {
        guard let id = selectedDestinationID else { return nil }
        return destinations.first { $0.id == id }
    }

    @discardableResult
    func send(_ command: MIDICommand, to target: SendTarget) -> CommandSendResult {
        let result = deliver(command, to: target)
        switch result {
        case .sent(let receipt):
            lastCommandRecord = CommandRecord(date: receipt.date, destinationName: receipt.destinationName,
                                              command: command, bytes: receipt.bytes)
            lastCommandFailure = nil
        case .failed(let failure):
            lastCommandFailure = failure.localizedDescription
        }
        onChange?()
        return result
    }

    private func deliver(_ command: MIDICommand, to target: SendTarget) -> CommandSendResult {
        if let e = transport.initializationError { return .failed(.transportUnavailable(e.localizedDescription)) }
        let bytes: [UInt8]
        do { bytes = try command.bytes() }
        catch let e as MIDIValidationError { return .failed(.invalidCommand(e)) }
        catch { return .failed(.transportRejected(error.localizedDescription)) }

        let id: Int32
        let name: String
        switch target {
        case .selected:
            guard let selectedID = selectedDestinationID, let selectedName = selectedDestinationName else {
                return .failed(.noDestinationSelected)
            }
            id = selectedID; name = selectedName
        case let .destination(targetID, targetName):
            id = targetID; name = targetName
        }
        guard destinations.contains(where: { $0.id == id }) else { return .failed(.destinationUnavailable(name)) }

        do { try transport.send(bytes, to: id) }
        catch { return .failed(.transportRejected(error.localizedDescription)) }
        return .sent(CommandSendReceipt(date: Date(), destinationID: id, destinationName: name, command: command, bytes: bytes))
    }
}
