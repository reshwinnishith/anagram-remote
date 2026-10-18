import XCTest
@testable import AnagramRemote

@MainActor
final class MIDIConnectionManagerTests: XCTestCase {
    private let anagram = MIDIDestination(id: 42, name: "Anagram")
    private let other = MIDIDestination(id: 7, name: "Other")

    func testNoAutomaticTransmissionOnInit() {
        let t = MockMIDITransport(destinations: [anagram])
        let m = MIDIConnectionManager(transport: t)
        m.selectDestination(id: 42)
        m.setChannel(3)
        m.refresh()
        XCTAssertTrue(t.sent.isEmpty)
        XCTAssertNil(m.lastTransmission)
    }

    func testSendWithoutDestinationFails() {
        let t = MockMIDITransport(destinations: [anagram])
        let m = MIDIConnectionManager(transport: t)
        XCTAssertFalse(m.canSend)
        XCTAssertFalse(m.sendProgramChange(program: 1))
        XCTAssertTrue(t.sent.isEmpty)
        XCTAssertEqual(m.lastError, MIDISendError.noDestinationSelected.localizedDescription)
    }

    func testSendPreset01AAnd01B() {
        let t = MockMIDITransport(destinations: [anagram])
        let m = MIDIConnectionManager(transport: t)
        m.selectDestination(id: 42)
        XCTAssertTrue(m.sendProgramChange(program: 1))
        XCTAssertTrue(m.sendProgramChange(program: 2))
        XCTAssertEqual(t.sent.map(\.bytes), [[0xC0, 0x00], [0xC0, 0x01]])
        XCTAssertEqual(t.sent.map(\.destinationID), [42, 42])
        XCTAssertEqual(m.lastTransmission?.bytes, [0xC0, 0x01])
    }

    func testChannelAppliedToStatusByte() {
        let t = MockMIDITransport(destinations: [anagram])
        let m = MIDIConnectionManager(transport: t)
        m.selectDestination(id: 42)
        m.setChannel(16)
        m.sendProgramChange(program: 1)
        XCTAssertEqual(t.sent.first?.bytes, [0xCF, 0x00])
    }

    func testInvalidChannelRejectedAndInvalidProgramNotSent() {
        let t = MockMIDITransport(destinations: [anagram])
        let m = MIDIConnectionManager(transport: t)
        m.selectDestination(id: 42)
        m.setChannel(17)
        XCTAssertEqual(m.channel, 1)
        XCTAssertNotNil(m.lastError)
        XCTAssertFalse(m.sendProgramChange(program: 0))
        XCTAssertFalse(m.sendProgramChange(program: 127))
        XCTAssertTrue(t.sent.isEmpty)
    }

    func testDestinationRemovalDisablesSendAndSendsNothing() {
        let t = MockMIDITransport(destinations: [anagram, other])
        let m = MIDIConnectionManager(transport: t)
        m.selectDestination(id: 42)
        t.setDestinations([other])
        XCTAssertEqual(m.state, .disconnected("Anagram"))
        XCTAssertFalse(m.canSend)
        XCTAssertFalse(m.sendProgramChange(program: 1))
        XCTAssertTrue(t.sent.isEmpty)
    }

    func testReconnectionDoesNotTransmit() {
        let t = MockMIDITransport(destinations: [anagram])
        let m = MIDIConnectionManager(transport: t)
        m.selectDestination(id: 42)
        t.setDestinations([])
        t.setDestinations([anagram])
        XCTAssertEqual(m.state, .connected("Anagram"))
        XCTAssertTrue(t.sent.isEmpty)
        XCTAssertNil(m.lastTransmission)
    }

    func testOneTapOneTransmission() {
        let t = MockMIDITransport(destinations: [anagram])
        let m = MIDIConnectionManager(transport: t)
        m.selectDestination(id: 42)
        m.sendProgramChange(program: 1)
        m.refresh(); m.refresh()
        XCTAssertEqual(t.sent.count, 1)
    }

    func testTransportFailureRecordsErrorAndNoTransmission() {
        let t = MockMIDITransport(destinations: [anagram])
        let m = MIDIConnectionManager(transport: t)
        m.selectDestination(id: 42)
        t.sendError = MIDITransportError.sendFailed(-1)
        XCTAssertFalse(m.sendProgramChange(program: 1))
        XCTAssertNil(m.lastTransmission)
        XCTAssertEqual(m.lastError, MIDITransportError.sendFailed(-1).localizedDescription)
    }

    func testSelectingUnknownDestinationClearsSelection() {
        let t = MockMIDITransport(destinations: [anagram])
        let m = MIDIConnectionManager(transport: t)
        m.selectDestination(id: 42)
        m.selectDestination(id: 999)
        XCTAssertEqual(m.state, .noDestinationSelected)
        XCTAssertFalse(m.canSend)
    }

    /// Tripwire: the one-based→wire mapping is PROVISIONAL until verified on a real Anagram.
    /// If hardware shows a different offset, change ProgramNumbering.dataByteOffset and this test together.
    func testProvisionalProgramOffsetIsMinusOne() {
        XCTAssertEqual(ProgramNumbering.dataByteOffset, -1)
    }

    func testInitializationFailureIsSurfacedAndBlocksSending() {
        let t = MockMIDITransport(destinations: [anagram])
        t.initializationError = .outputPortCreationFailed(-50)
        let m = MIDIConnectionManager(transport: t)
        m.selectDestination(id: 42)
        XCTAssertEqual(m.state, .transportUnavailable(MIDITransportError.outputPortCreationFailed(-50).localizedDescription))
        XCTAssertFalse(m.canSend)
        XCTAssertTrue(m.lastError?.contains("-50") == true)
        XCTAssertFalse(m.sendProgramChange(program: 1))
        XCTAssertTrue(m.lastError?.contains("-50") == true)
        XCTAssertTrue(t.sent.isEmpty)
        XCTAssertNil(m.lastTransmission)
    }

    func testInitializationFailureVisibleInViewModel() {
        let t = MockMIDITransport()
        t.initializationError = .clientCreationFailed(-50)
        let vm = ConnectionViewModel(manager: MIDIConnectionManager(transport: t))
        XCTAssertFalse(vm.canSend)
        XCTAssertTrue(vm.statusText.contains("-50"))
        XCTAssertTrue(vm.lastError?.contains("-50") == true)
        vm.sendPreset(1)
        XCTAssertTrue(t.sent.isEmpty)
    }
}
