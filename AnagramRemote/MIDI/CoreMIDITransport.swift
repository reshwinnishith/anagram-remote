import CoreMIDI
import Foundation

@MainActor
final class CoreMIDITransport: MIDITransport {
    var onSetupChanged: (() -> Void)?

    private var client = MIDIClientRef()
    private var outPort = MIDIPortRef()

    init() {
        MIDIClientCreateWithBlock("AnagramRemote" as CFString, &client) { [weak self] notification in
            guard notification.pointee.messageID == .msgSetupChanged else { return }
            Task { @MainActor in self?.onSetupChanged?() }
        }
        MIDIOutputPortCreate(client, "AnagramRemote Out" as CFString, &outPort)
    }

    var destinations: [MIDIDestination] {
        (0..<MIDIGetNumberOfDestinations()).compactMap { index in
            let endpoint = MIDIGetDestination(index)
            guard endpoint != 0 else { return nil }
            return MIDIDestination(id: Self.uniqueID(of: endpoint), name: Self.name(of: endpoint))
        }
    }

    func send(_ bytes: [UInt8], to destinationID: Int32) throws {
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
