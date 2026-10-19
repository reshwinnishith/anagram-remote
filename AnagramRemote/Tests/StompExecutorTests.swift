import XCTest
@testable import AnagramRemote

@MainActor
final class StompExecutorTests: XCTestCase {
    private let anagram = MIDIDestination(id: 42, name: "Anagram")
    private let other = MIDIDestination(id: 7, name: "Other")
    private var transport: MockMIDITransport!
    private var manager: MIDIConnectionManager!
    private var executor: StompExecutor!

    override func setUp() async throws {
        transport = MockMIDITransport(destinations: [anagram, other])
        manager = MIDIConnectionManager(transport: transport)
        manager.selectDestination(id: 42)
        executor = StompExecutor(sender: manager)
    }

    private func cc(_ slot: Int, channel: Int = 1, controller: Int = 80, _ behavior: CCBehavior, ack: [SafetyWarning] = []) -> StompAssignment {
        StompAssignment(slot: slot, name: "", accentID: "blue",
                        action: .controlChange(channel: channel, controller: controller, behavior: behavior), acknowledgedWarnings: ack)
    }
    private func cc(channel: Int = 1, controller: Int = 80, _ behavior: CCBehavior, ack: [SafetyWarning] = []) -> StompAssignment {
        cc(1, channel: channel, controller: controller, behavior, ack: ack)
    }
    private func pc(_ slot: Int = 1, channel: Int = 1, program: Int) -> StompAssignment {
        StompAssignment(slot: slot, name: "", accentID: "blue", action: .programChange(channel: channel, program: program))
    }
    private var bytes: [[UInt8]] { transport.sent.map(\.bytes) }

    func testConstructionAndSetupSendNothing() {
        XCTAssertTrue(transport.sent.isEmpty)
        XCTAssertTrue(executor.pressedSlots.isEmpty)
        manager.refresh(); manager.selectDestination(id: 7); manager.selectDestination(id: 42)
        XCTAssertTrue(transport.sent.isEmpty)
    }

    func testUnassignedSendsNothing() {
        XCTAssertEqual(executor.activate(.unassigned(slot: 3)), .skippedUnassigned)
        XCTAssertTrue(transport.sent.isEmpty)
    }

    func testFixedValue() {
        XCTAssertNotNil(executor.activate(cc(.fixedValue(64))).receipt)
        executor.activate(cc(.fixedValue(64)))
        XCTAssertEqual(bytes, [[0xB0, 80, 64], [0xB0, 80, 64]])
    }

    func testProgramChangeTriggerUsesAssignmentChannelAndM1Numbering() {
        manager.setChannel(9)
        executor.activate(pc(channel: 5, program: 1))
        executor.activate(pc(channel: 16, program: 126))
        XCTAssertEqual(bytes, [[0xC4, 0x00], [0xCF, 125]])
    }

    func testControlChangeUsesAssignmentChannelNotConnectionChannel() {
        manager.setChannel(9)
        executor.activate(cc(channel: 2, .fixedValue(1)))
        XCTAssertEqual(bytes, [[0xB1, 80, 1]])
    }

    func testProgramChangeDoesNotChangePresetReadout() {
        executor.activate(pc(program: 2))
        XCTAssertNil(manager.lastTransmission)
        XCTAssertEqual(manager.lastCommandRecord?.bytes, [0xC0, 0x01])
    }

    func testValueToggleStartsOnThenAlternates() {
        let a = cc(.toggle(.values(on: 100, off: 10)))
        XCTAssertEqual(executor.localToggleState(slot: 1, for: a.action), .noneSent)
        executor.activate(a); XCTAssertEqual(executor.localToggleState(slot: 1, for: a.action), .lastSentOn)
        executor.activate(a); XCTAssertEqual(executor.localToggleState(slot: 1, for: a.action), .lastSentOff)
        executor.activate(a)
        XCTAssertEqual(bytes, [[0xB0, 80, 100], [0xB0, 80, 10], [0xB0, 80, 100]])
    }

    func testValueToggleDoesNotAdvanceOnFailure() {
        let a = cc(.toggle(.values(on: 127, off: 0)))
        transport.sendError = MIDITransportError.sendFailed(-1)
        guard case .failed = executor.activate(a) else { return XCTFail() }
        XCTAssertEqual(executor.localToggleState(slot: 1, for: a.action), .noneSent)
        transport.sendError = nil
        executor.activate(a)
        XCTAssertEqual(bytes, [[0xB0, 80, 127]])
        transport.sendError = MIDITransportError.sendFailed(-1)
        executor.activate(a)
        XCTAssertEqual(executor.localToggleState(slot: 1, for: a.action), .lastSentOn)
        transport.sendError = nil
        executor.activate(a)
        XCTAssertEqual(bytes, [[0xB0, 80, 127], [0xB0, 80, 0]])
    }

    func testValueToggleStateIsPerSlotAndResetsWhenAssignmentChanges() {
        let a = cc(1, .toggle(.values(on: 127, off: 0)))
        let b = cc(2, controller: 81, .toggle(.values(on: 127, off: 0)))
        executor.activate(a); executor.activate(b); executor.activate(a)
        XCTAssertEqual(bytes, [[0xB0, 80, 127], [0xB0, 81, 127], [0xB0, 80, 0]])
        let changed = cc(1, .toggle(.values(on: 90, off: 5)))
        executor.activate(changed)
        XCTAssertEqual(bytes.last, [0xB0, 80, 90])
        XCTAssertEqual(executor.localToggleState(slot: 1, for: a.action), .noneSent)
    }

    func testValueToggleOnZeroOffHigh() {
        let a = cc(.toggle(.values(on: 0, off: 127)))
        executor.activate(a); executor.activate(a)
        XCTAssertEqual(bytes, [[0xB0, 80, 0], [0xB0, 80, 127]])
    }

    func testResetRuntimeStateStartsToggleOverWithOn() {
        let a = cc(.toggle(.values(on: 127, off: 0)))
        executor.activate(a); executor.resetRuntimeState(); executor.activate(a)
        XCTAssertEqual(bytes, [[0xB0, 80, 127], [0xB0, 80, 127]])
    }

    func testDeviceToggleSendsSameTriggerAndKeepsNoState() {
        let a = cc(.toggle(.deviceToggle(trigger: 64)))
        for _ in 0..<3 { executor.activate(a) }
        XCTAssertEqual(bytes, Array(repeating: [0xB0, 80, 64], count: 3))
        XCTAssertEqual(executor.localToggleState(slot: 1, for: a.action), .noneSent)
    }

    func testInvalidAssignmentsSendNothing() {
        let bad: [StompAssignment] = [
            cc(channel: 17, .fixedValue(1)),
            cc(controller: 200, .fixedValue(1)),
            cc(.fixedValue(300)),
            cc(.toggle(.values(on: 5, off: 5))),
            cc(.toggle(.deviceToggle(trigger: 0))),
            cc(.momentary(press: 9, release: 9)),
            pc(program: 0), pc(program: 127), pc(channel: 0, program: 1),
            StompAssignment(slot: 9, name: "", accentID: "blue", action: .programChange(channel: 1, program: 1)),
            StompAssignment(slot: 1, name: "", accentID: "nope", action: .programChange(channel: 1, program: 1))]
        for a in bad {
            guard case .rejected(.invalidAssignment) = executor.activate(a) else { return XCTFail("\(a)") }
        }
        XCTAssertTrue(transport.sent.isEmpty)
        XCTAssertTrue(executor.pressedSlots.isEmpty)
    }

    func testUnacknowledgedWarningsSendNothingUntilAcknowledged() {
        for controller in [0, 7, 32, 123] {
            guard case .rejected(.unacknowledgedWarnings) = executor.activate(cc(controller: controller, .fixedValue(1))) else {
                return XCTFail("CC \(controller)")
            }
        }
        XCTAssertTrue(transport.sent.isEmpty)
        XCTAssertNotNil(executor.activate(cc(controller: 7, .fixedValue(1), ack: [.anagramReserved])).receipt)
        XCTAssertNotNil(executor.activate(cc(controller: 0, .fixedValue(1), ack: [.bankSelect])).receipt)
        XCTAssertNotNil(executor.activate(cc(controller: 123, .fixedValue(1), ack: [.channelModeController])).receipt)
        XCTAssertEqual(bytes, [[0xB0, 7, 1], [0xB0, 0, 1], [0xB0, 123, 1]])
    }

    func testWrongAcknowledgementStillRejected() {
        guard case .rejected = executor.activate(cc(controller: 7, .fixedValue(1), ack: [.bankSelect])) else { return XCTFail() }
        XCTAssertTrue(transport.sent.isEmpty)
    }

    func testNoDestinationSelected() {
        manager.selectDestination(id: nil)
        XCTAssertEqual(executor.activate(cc(.fixedValue(1))), .failed(.noDestinationSelected))
        XCTAssertEqual(executor.activate(cc(.momentary(press: 127, release: 0))), .failed(.noDestinationSelected))
        XCTAssertTrue(executor.pressedSlots.isEmpty)
        XCTAssertTrue(transport.sent.isEmpty)
    }

    func testDestinationUnavailable() {
        transport.setDestinations([other])
        XCTAssertEqual(executor.activate(cc(.fixedValue(1))), .failed(.destinationUnavailable("Anagram")))
        XCTAssertTrue(transport.sent.isEmpty)
    }

    func testTransportFailureReported() {
        transport.sendError = MIDITransportError.sendFailed(-7)
        guard case .failed(.transportRejected) = executor.activate(pc(program: 1)) else { return XCTFail() }
        XCTAssertTrue(transport.sent.isEmpty)
    }

    func testTransportUnavailableReported() {
        transport.initializationError = .outputPortCreationFailed(-3)
        guard case .failed(.transportUnavailable) = executor.activate(cc(.fixedValue(1))) else { return XCTFail() }
    }

    func testNoDeferredSendsOnReconnect() {
        transport.setDestinations([other])
        executor.activate(cc(.fixedValue(1)))
        executor.activate(cc(.toggle(.values(on: 127, off: 0))))
        transport.sendError = MIDITransportError.sendFailed(-1)
        transport.setDestinations([anagram, other])
        transport.sendError = nil
        manager.refresh()
        XCTAssertTrue(transport.sent.isEmpty)
    }

    private var momentary: StompAssignment { cc(.momentary(press: 127, release: 0)) }

    func testMomentaryPressThenRelease() {
        XCTAssertNotNil(executor.activate(momentary).receipt)
        XCTAssertEqual(executor.pressedSlots, [1])
        XCTAssertNotNil(executor.release(slot: 1).receipt)
        XCTAssertTrue(executor.pressedSlots.isEmpty)
        XCTAssertEqual(bytes, [[0xB0, 80, 127], [0xB0, 80, 0]])
    }

    func testDuplicatePressIgnoredAndStillReleasesOnce() {
        executor.activate(momentary)
        XCTAssertEqual(executor.activate(momentary), .ignored(.alreadyPressed))
        executor.release(slot: 1)
        XCTAssertEqual(executor.release(slot: 1), .ignored(.notPressed))
        XCTAssertEqual(bytes, [[0xB0, 80, 127], [0xB0, 80, 0]])
    }

    func testReleaseWithoutPressSendsNothing() {
        XCTAssertEqual(executor.release(slot: 1), .ignored(.notPressed))
        XCTAssertTrue(transport.sent.isEmpty)
    }

    func testFailedPressLeavesNothingToRelease() {
        transport.sendError = MIDITransportError.sendFailed(-1)
        guard case .failed = executor.activate(momentary) else { return XCTFail() }
        transport.sendError = nil
        XCTAssertEqual(executor.release(slot: 1), .ignored(.notPressed))
        XCTAssertTrue(transport.sent.isEmpty)
    }

    func testReleaseGoesToOriginalDestinationAfterSelectionChange() {
        executor.activate(momentary)
        manager.selectDestination(id: 7)
        let release = executor.release(slot: 1)
        XCTAssertEqual(release.receipt?.destinationID, 42)
        XCTAssertEqual(transport.sent.map(\.destinationID), [42, 42])
    }

    func testReleaseNeverRedirectsWhenOriginalDestinationDisconnects() {
        executor.activate(momentary)
        manager.selectDestination(id: 7)
        transport.setDestinations([other])
        XCTAssertEqual(executor.release(slot: 1), .failed(.destinationUnavailable("Anagram")))
        XCTAssertEqual(transport.sent.map(\.destinationID), [42])
        XCTAssertTrue(executor.pressedSlots.isEmpty)
    }

    func testFailedReleaseIsNotReplayedOnReconnect() {
        executor.activate(momentary)
        transport.setDestinations([other])
        executor.release(slot: 1)
        transport.setDestinations([anagram, other])
        manager.refresh()
        XCTAssertEqual(executor.release(slot: 1), .ignored(.notPressed))
        XCTAssertEqual(bytes, [[0xB0, 80, 127]])
    }

    func testReleaseUsesCapturedAssignmentValues() {
        executor.activate(cc(channel: 3, controller: 81, .momentary(press: 100, release: 20)))
        executor.activate(cc(channel: 3, controller: 81, .fixedValue(1)))
        executor.release(slot: 1)
        XCTAssertEqual(bytes, [[0xB2, 81, 100], [0xB2, 81, 1], [0xB2, 81, 20]])
    }

    func testMomentarySlotsAreIndependent() {
        executor.activate(cc(1, controller: 80, .momentary(press: 127, release: 0)))
        executor.activate(cc(2, controller: 81, .momentary(press: 127, release: 0)))
        XCTAssertEqual(executor.pressedSlots, [1, 2])
        executor.release(slot: 2)
        XCTAssertEqual(executor.pressedSlots, [1])
        XCTAssertEqual(bytes.last, [0xB0, 81, 0])
    }

    func testResetRuntimeStateForgetsHeldPresses() {
        executor.activate(momentary)
        executor.resetRuntimeState()
        XCTAssertEqual(executor.release(slot: 1), .ignored(.notPressed))
        XCTAssertEqual(bytes, [[0xB0, 80, 127]])
    }

    func testControlChangesNeverChangePresetReadout() {
        let vm = ConnectionViewModel(manager: manager)
        let before = PerformancePresentation(vm: vm).preset
        executor.activate(cc(.toggle(.values(on: 127, off: 0))))
        executor.activate(pc(program: 5))
        XCTAssertEqual(PerformancePresentation(vm: vm).preset, before)
        XCTAssertNil(vm.lastTransmission)
        XCTAssertNil(vm.lastError)
    }

    func testExecutorIsNotReferencedFromViewsOrEditor() throws {
        let features = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Features")
        guard let enumerator = FileManager.default.enumerator(at: features, includingPropertiesForKeys: nil) else {
            throw XCTSkip("Source tree not available at test time")
        }
        var scanned = 0
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            let text = try String(contentsOf: url, encoding: .utf8)
            for banned in ["StompExecutor", "MIDICommandSending", "MIDICommand.controlChange", "SendTarget"] {
                XCTAssertFalse(text.contains(banned), "\(url.lastPathComponent) must not reference \(banned)")
            }
            scanned += 1
        }
        if scanned == 0 { throw XCTSkip("Source tree not available at test time") }
    }

    func testPerformanceStompsRemainInactive() {
        XCTAssertTrue(StompPresentation.all.allSatisfy { !$0.isEnabled })
        let configured = StompPresentation(assignment: cc(.fixedValue(1)))
        XCTAssertFalse(configured.isEnabled)
        XCTAssertEqual(configured.localState, .unassigned)
        XCTAssertEqual(configured.confirmedState, .notAvailable)
    }

    func testToggleStateIsClearedWhenSlotSwitchesToFixedValueAndBack() {
        let toggle = cc(.toggle(.values(on: 127, off: 0)))
        executor.activate(toggle)
        executor.activate(cc(.fixedValue(5)))
        XCTAssertEqual(executor.localToggleState(slot: 1, for: toggle.action), .noneSent)
        executor.activate(toggle)
        XCTAssertEqual(bytes, [[0xB0, 80, 127], [0xB0, 80, 5], [0xB0, 80, 127]])
    }

    func testToggleStateIsClearedWhenSlotSwitchesToProgramChangeAndBack() {
        let toggle = cc(.toggle(.values(on: 127, off: 0)))
        executor.activate(toggle)
        executor.activate(pc(program: 3))
        executor.activate(toggle)
        XCTAssertEqual(bytes, [[0xB0, 80, 127], [0xC0, 0x02], [0xB0, 80, 127]])
    }

    func testToggleStateIsClearedWhenSlotSwitchesToUnassignedAndBack() {
        let toggle = cc(.toggle(.values(on: 127, off: 0)))
        executor.activate(toggle)
        XCTAssertEqual(executor.activate(.unassigned(slot: 1)), .skippedUnassigned)
        XCTAssertEqual(executor.localToggleState(slot: 1, for: toggle.action), .noneSent)
        executor.activate(toggle)
        XCTAssertEqual(bytes, [[0xB0, 80, 127], [0xB0, 80, 127]])
    }

    func testToggleStateIsClearedWhenSlotSwitchesToDeviceToggleAndBack() {
        let toggle = cc(.toggle(.values(on: 127, off: 0)))
        executor.activate(toggle)
        executor.activate(cc(.toggle(.deviceToggle(trigger: 64))))
        executor.activate(toggle)
        XCTAssertEqual(bytes, [[0xB0, 80, 127], [0xB0, 80, 64], [0xB0, 80, 127]])
    }

    func testToggleStateIsClearedWhenSlotSwitchesToAnInvalidAssignmentAndBack() {
        let toggle = cc(.toggle(.values(on: 127, off: 0)))
        executor.activate(toggle)
        guard case .rejected = executor.activate(cc(channel: 17, .fixedValue(1))) else { return XCTFail() }
        executor.activate(toggle)
        XCTAssertEqual(bytes, [[0xB0, 80, 127], [0xB0, 80, 127]])
    }

    func testToggleStateIsClearedWhenSlotSwitchesToAnotherControllerAndBack() {
        let toggle = cc(.toggle(.values(on: 127, off: 0)))
        executor.activate(toggle)
        executor.activate(cc(controller: 81, .toggle(.values(on: 127, off: 0))))
        executor.activate(toggle)
        XCTAssertEqual(bytes, [[0xB0, 80, 127], [0xB0, 81, 127], [0xB0, 80, 127]])
    }

    func testTransitionsOnOneSlotDoNotDisturbAnotherSlotsToggle() {
        let a = cc(1, .toggle(.values(on: 127, off: 0)))
        let b = cc(2, controller: 81, .toggle(.values(on: 127, off: 0)))
        executor.activate(a); executor.activate(b)
        executor.activate(cc(1, .fixedValue(5)))
        executor.activate(b)
        XCTAssertEqual(bytes.last, [0xB0, 81, 0])
    }

    func testRepeatedSameActionStillAlternatesAfterTransitionFix() {
        let toggle = cc(.toggle(.values(on: 127, off: 0)))
        executor.activate(toggle); executor.activate(toggle); executor.activate(toggle)
        XCTAssertEqual(bytes, [[0xB0, 80, 127], [0xB0, 80, 0], [0xB0, 80, 127]])
    }
}
