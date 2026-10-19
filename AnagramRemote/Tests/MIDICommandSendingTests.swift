import XCTest
@testable import AnagramRemote

@MainActor
final class MIDICommandSendingTests: XCTestCase {
    private let anagram = MIDIDestination(id: 42, name: "Anagram")
    private let other = MIDIDestination(id: 7, name: "Other")

    private func make(_ destinations: [MIDIDestination]? = nil) -> (MockMIDITransport, MIDIConnectionManager) {
        let t = MockMIDITransport(destinations: destinations ?? [anagram, other])
        return (t, MIDIConnectionManager(transport: t))
    }

    func testSendToSelectedDestination() {
        let (t, m) = make()
        m.selectDestination(id: 42)
        let result = m.send(.controlChange(channel: 2, controller: 80, value: 127), to: .selected)
        XCTAssertEqual(result.receipt?.bytes, [0xB1, 80, 127])
        XCTAssertEqual(result.receipt?.destinationID, 42)
        XCTAssertEqual(result.receipt?.destinationName, "Anagram")
        XCTAssertEqual(t.sent.map(\.bytes), [[0xB1, 80, 127]])
        XCTAssertEqual(t.sent.map(\.destinationID), [42])
    }

    func testExplicitDestinationIgnoresCurrentSelection() {
        let (t, m) = make()
        m.selectDestination(id: 7)
        m.send(.controlChange(channel: 1, controller: 1, value: 1), to: .destination(id: 42, name: "Anagram"))
        XCTAssertEqual(t.sent.map(\.destinationID), [42])
    }

    func testNoDestinationSelectedFailsWithoutSending() {
        let (t, m) = make()
        XCTAssertEqual(m.send(.controlChange(channel: 1, controller: 1, value: 1), to: .selected), .failed(.noDestinationSelected))
        XCTAssertTrue(t.sent.isEmpty)
    }

    func testSelectedDestinationRemovedFailsWithoutSending() {
        let (t, m) = make()
        m.selectDestination(id: 42)
        t.setDestinations([other])
        XCTAssertEqual(m.send(.controlChange(channel: 1, controller: 1, value: 1), to: .selected), .failed(.destinationUnavailable("Anagram")))
        XCTAssertTrue(t.sent.isEmpty)
    }

    func testExplicitDestinationRemovedFailsWithoutSendingElsewhere() {
        let (t, m) = make()
        m.selectDestination(id: 7)
        t.setDestinations([other])
        XCTAssertEqual(m.send(.controlChange(channel: 1, controller: 1, value: 1), to: .destination(id: 42, name: "Anagram")),
                       .failed(.destinationUnavailable("Anagram")))
        XCTAssertTrue(t.sent.isEmpty)
    }

    func testInvalidCommandFailsBeforeTransport() {
        let (t, m) = make()
        m.selectDestination(id: 42)
        XCTAssertEqual(m.send(.controlChange(channel: 17, controller: 1, value: 1), to: .selected), .failed(.invalidCommand(.invalidChannel(17))))
        XCTAssertEqual(m.send(.controlChange(channel: 1, controller: 128, value: 1), to: .selected), .failed(.invalidCommand(.invalidController(128))))
        XCTAssertEqual(m.send(.controlChange(channel: 1, controller: 1, value: 128), to: .selected), .failed(.invalidCommand(.invalidValue(128))))
        XCTAssertTrue(t.sent.isEmpty)
    }

    func testTransportRejectionIsReported() {
        let (t, m) = make()
        m.selectDestination(id: 42)
        t.sendError = MIDITransportError.sendFailed(-50)
        guard case .failed(.transportRejected(let message)) = m.send(.controlChange(channel: 1, controller: 1, value: 1), to: .selected) else {
            return XCTFail()
        }
        XCTAssertTrue(message.contains("-50"))
        XCTAssertTrue(t.sent.isEmpty)
        XCTAssertNil(m.lastCommandRecord)
        XCTAssertEqual(m.lastCommandFailure, message)
    }

    func testTransportUnavailableFails() {
        let (t, m) = make()
        t.initializationError = .clientCreationFailed(-1)
        guard case .failed(.transportUnavailable) = m.send(.controlChange(channel: 1, controller: 1, value: 1), to: .selected) else {
            return XCTFail()
        }
        XCTAssertTrue(t.sent.isEmpty)
    }

    func testCommandDiagnosticsAreSeparateFromPresetDiagnostics() {
        let (_, m) = make()
        m.selectDestination(id: 42)
        m.sendProgramChange(program: 2)
        let preset = m.lastTransmission
        m.send(.controlChange(channel: 1, controller: 80, value: 127), to: .selected)
        XCTAssertEqual(m.lastTransmission, preset)
        XCTAssertEqual(m.lastCommandRecord?.bytes, [0xB0, 80, 127])
        XCTAssertEqual(m.lastCommandRecord?.summary, "CC 80 = 127 on ch 1 → [B0 50 7F] to Anagram")
        XCTAssertNil(m.lastError)
    }

    func testFailedCommandDoesNotTouchPresetErrorOrTransmission() {
        let (_, m) = make()
        m.selectDestination(id: 42)
        m.sendProgramChange(program: 1)
        let preset = m.lastTransmission
        m.send(.controlChange(channel: 99, controller: 1, value: 1), to: .selected)
        XCTAssertEqual(m.lastTransmission, preset)
        XCTAssertNil(m.lastError)
        XCTAssertNotNil(m.lastCommandFailure)
    }

    func testSuccessfulCommandClearsCommandFailureOnly() {
        let (t, m) = make()
        m.selectDestination(id: 42)
        t.sendError = MIDITransportError.sendFailed(1)
        m.send(.controlChange(channel: 1, controller: 1, value: 1), to: .selected)
        t.sendError = nil
        m.send(.controlChange(channel: 1, controller: 1, value: 1), to: .selected)
        XCTAssertNil(m.lastCommandFailure)
        XCTAssertNotNil(m.lastCommandRecord)
    }

    func testPresetFailureDoesNotTouchCommandDiagnostics() {
        let (_, m) = make()
        m.selectDestination(id: 42)
        m.send(.controlChange(channel: 1, controller: 1, value: 1), to: .selected)
        let record = m.lastCommandRecord
        m.sendProgramChange(program: 0)
        XCTAssertEqual(m.lastCommandRecord, record)
        XCTAssertNotNil(m.lastError)
    }

    func testPresetReadoutUnchangedByControlChange() {
        let t = MockMIDITransport(destinations: [anagram])
        let m = MIDIConnectionManager(transport: t)
        let vm = ConnectionViewModel(manager: m)
        vm.selectDestination(42)
        let before = PerformancePresentation(vm: vm).preset
        m.send(.controlChange(channel: 1, controller: 80, value: 127), to: .selected)
        XCTAssertEqual(PerformancePresentation(vm: vm).preset, before)
        vm.sendPreset(2)
        let afterPreset = PerformancePresentation(vm: vm).preset
        m.send(.controlChange(channel: 1, controller: 80, value: 0), to: .selected)
        XCTAssertEqual(PerformancePresentation(vm: vm).preset, afterPreset)
        XCTAssertEqual(afterPreset.label, "01B")
    }

    func testSetupChangeCallbackStillRefreshesAfterCommandSends() {
        let (t, m) = make()
        m.selectDestination(id: 42)
        m.send(.controlChange(channel: 1, controller: 1, value: 1), to: .selected)
        t.setDestinations([other])
        XCTAssertEqual(m.destinations, [other])
        XCTAssertFalse(m.canSend)
    }

    func testSelectedDestinationAccessor() {
        let (t, m) = make()
        XCTAssertNil(m.selectedDestination())
        m.selectDestination(id: 42)
        XCTAssertEqual(m.selectedDestination(), anagram)
        t.setDestinations([other])
        XCTAssertNil(m.selectedDestination())
    }

    func testOnlyExplicitSendsTransmit() {
        let (t, m) = make()
        m.selectDestination(id: 42)
        m.setChannel(5)
        m.refresh()
        t.setDestinations([other])
        t.setDestinations([anagram, other])
        XCTAssertTrue(t.sent.isEmpty)
        XCTAssertNil(m.lastCommandRecord)
    }

    func testM1PresetPathStillUsesManagerChannel() {
        let (t, m) = make()
        m.selectDestination(id: 42)
        m.setChannel(5)
        m.sendProgramChange(program: 2)
        m.send(.controlChange(channel: 2, controller: 80, value: 1), to: .selected)
        XCTAssertEqual(t.sent.map(\.bytes), [[0xC4, 0x01], [0xB1, 80, 1]])
    }
}
