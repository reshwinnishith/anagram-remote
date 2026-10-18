import CoreMIDI
import Foundation

/// The CoreMIDI calls used during initialisation, injectable so failure paths can be tested
/// without touching the real MIDI subsystem.
struct CoreMIDIInitializer {
    var createClient: (_ onSetupChanged: @escaping @Sendable () -> Void) -> (status: OSStatus, client: MIDIClientRef)
    var createOutputPort: (_ client: MIDIClientRef) -> (status: OSStatus, port: MIDIPortRef)
    var disposeClient: (_ client: MIDIClientRef) -> Void

    static let live = CoreMIDIInitializer(
        createClient: { onSetupChanged in
            var client = MIDIClientRef()
            let status = MIDIClientCreateWithBlock("AnagramRemote" as CFString, &client) { notification in
                guard notification.pointee.messageID == .msgSetupChanged else { return }
                onSetupChanged()
            }
            return (status, client)
        },
        createOutputPort: { client in
            var port = MIDIPortRef()
            let status = MIDIOutputPortCreate(client, "AnagramRemote Out" as CFString, &port)
            return (status, port)
        },
        disposeClient: { MIDIClientDispose($0) })
}

@MainActor
final class CoreMIDITransport: MIDITransport {
    var onSetupChanged: (() -> Void)?
    private(set) var initializationError: MIDITransportError?

    private var client = MIDIClientRef()
    private var outPort = MIDIPortRef()

    init(initializer: CoreMIDIInitializer = .live) {
        let created = initializer.createClient { [weak self] in
            Task { @MainActor in self?.onSetupChanged?() }
        }
        guard created.status == noErr, created.client != 0 else {
            initializationError = .clientCreationFailed(created.status == noErr ? -1 : created.status)
            return
        }
        let port = initializer.createOutputPort(created.client)
        guard port.status == noErr, port.port != 0 else {
            initializer.disposeClient(created.client)  // don't leak the half-initialised client
            initializationError = .outputPortCreationFailed(port.status == noErr ? -1 : port.status)
            return
        }
        client = created.client
        outPort = port.port
    }

    var destinations: [MIDIDestination] {
        guard initializationError == nil else { return [] }
        return (0..<MIDIGetNumberOfDestinations()).compactMap { index in
            let endpoint = MIDIGetDestination(index)
            guard endpoint != 0 else { return nil }
            return MIDIDestination(id: Self.uniqueID(of: endpoint), name: Self.name(of: endpoint))
        }
    }

    func send(_ bytes: [UInt8], to destinationID: Int32) throws {
        if let initializationError { throw initializationError }
        guard let endpoint = (0..<MIDIGetNumberOfDestinations())
            .map({ MIDIGetDestination($0) })
            .first(where: { $0 != 0 && Self.uniqueID(of: $0) == destinationID })
        else { throw MIDITransportError.destinationNotFound(destinationID) }

        let size = 256
        let raw = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: 4)
        defer { raw.deallocate() }
        let list = raw.bindMemory(to: MIDIPacketList.self, capacity: 1)
        let packet = MIDIPacketListInit(list)
        guard MIDIPacketListAdd(list, size, packet, 0, bytes.count, bytes) != nil else {
            throw MIDITransportError.sendFailed(-1)
        }
        let status = MIDISend(outPort, endpoint, list)
        guard status == noErr else { throw MIDITransportError.sendFailed(status) }
    }

    private static func uniqueID(of endpoint: MIDIEndpointRef) -> Int32 {
        var id: Int32 = 0
        MIDIObjectGetIntegerProperty(endpoint, kMIDIPropertyUniqueID, &id)
        return id
    }

    private static func name(of endpoint: MIDIEndpointRef) -> String {
        var name: Unmanaged<CFString>?
        MIDIObjectGetStringProperty(endpoint, kMIDIPropertyDisplayName, &name)
        return (name?.takeRetainedValue() as String?) ?? "Unknown"
    }
}
