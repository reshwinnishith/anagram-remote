import XCTest
@testable import AnagramRemote

@MainActor
final class PerformancePresentationTests: XCTestCase {
    private let anagram = MIDIDestination(id: 42, name: "Anagram")

    private func makeVM(_ transport: MockMIDITransport) -> ConnectionViewModel {
        ConnectionViewModel(manager: MIDIConnectionManager(transport: transport))
    }

    // MARK: placeholders

    func testScenesAreThreeDisabledNotConfiguredPlaceholders() {
        XCTAssertEqual(SceneSlotPresentation.all.map(\.letter), ["A", "B", "C"])
        for s in SceneSlotPresentation.all {
            XCTAssertFalse(s.isEnabled)
            XCTAssertEqual(s.statusText, "NOT CONFIGURED")
        }
    }

    func testStompsAreSixDisabledUnassignedPlaceholdersInThreeByTwo() {
        XCTAssertEqual(PerformanceLayout.stompColumns, 3)
        XCTAssertEqual(PerformanceLayout.stompRows, 2)
        XCTAssertEqual(StompPresentation.all.count, 6)
        XCTAssertEqual(StompPresentation.all.map(\.title), (1...6).map { "Stomp \($0)" })
        for s in StompPresentation.all {
            XCTAssertFalse(s.isEnabled)
            XCTAssertEqual(s.statusText, "UNASSIGNED")
            XCTAssertEqual(s.localState, .unassigned)
            XCTAssertEqual(s.confirmedState, .notAvailable)
            XCTAssertNil(s.customLabel)
            XCTAssertNil(s.accent)
        }
    }

    func testBuildingPresentationAndPlaceholdersNeverTransmit() {
        let t = MockMIDITransport(destinations: [anagram])
        let vm = makeVM(t)
        vm.selectDestination(42)
        _ = PerformancePresentation(vm: vm)
        _ = SceneSlotPresentation.all
        _ = StompPresentation.all
        vm.rescan()
        t.setDestinations([])
        t.setDestinations([anagram])   // unplug / replug
        _ = PerformancePresentation(vm: vm)
        XCTAssertTrue(t.sent.isEmpty)
    }

    // MARK: M1 preset behaviour preserved

    func testPresetShortcutsAreExactlyM1_01A_01B() {
        XCTAssertEqual(PresetShortcut.all.map(\.program), [1, 2])
        XCTAssertEqual(PresetShortcut.all.map(\.label), ["01A", "01B"])
    }

    func testPresetShortcutsSendSameBytesAsM1() {
        let t = MockMIDITransport(destinations: [anagram])
        let vm = makeVM(t)
        vm.selectDestination(42)
        for s in PresetShortcut.all { vm.sendPreset(s.program) }
        XCTAssertEqual(t.sent.map(\.bytes), [[0xC0, 0x00], [0xC0, 0x01]])
    }

    func testChannelSelectionStillAppliesToPresetShortcuts() {
        let t = MockMIDITransport(destinations: [anagram])
        let vm = makeVM(t)
        vm.selectDestination(42)
        vm.setChannel(16)
        vm.sendPreset(PresetShortcut.all[1].program)
        XCTAssertEqual(t.sent.first?.bytes, [0xCF, 0x01])
    }

    // MARK: presentation mapping

    func testNoDestinationDisablesSendingAndSaysSo() {
        let vm = makeVM(MockMIDITransport(destinations: [anagram]))
        let p = PerformancePresentation(vm: vm)
        XCTAssertFalse(p.canSend)
        XCTAssertEqual(p.connectionLevel, .warning)
        XCTAssertEqual(p.preset.label, "—")
    }

    func testConnectedShowsDestinationAndDoesNotClaimConfirmation() {
        let vm = makeVM(MockMIDITransport(destinations: [anagram]))
        vm.selectDestination(42)
        let p = PerformancePresentation(vm: vm)
        XCTAssertTrue(p.canSend)
        XCTAssertEqual(p.connectionLevel, .ok)
        XCTAssertEqual(p.destinationLabel, "Anagram")
        XCTAssertNil(p.lastSentText)
    }

    func testPresetReadoutShowsLastSentAsUnconfirmed() {
        let vm = makeVM(MockMIDITransport(destinations: [anagram]))
        vm.selectDestination(42)
        vm.sendPreset(2)
        let p = PerformancePresentation(vm: vm)
        XCTAssertEqual(p.preset.label, "01B")
        XCTAssertTrue(p.preset.subtitle.contains("not confirmed"))
        XCTAssertTrue(p.lastSentText?.contains("not device-confirmed") == true)
    }

    func testDisconnectedIsErrorLevelAndBlocksSending() {
        let t = MockMIDITransport(destinations: [anagram])
        let vm = makeVM(t)
        vm.selectDestination(42)
        t.setDestinations([])
        let p = PerformancePresentation(vm: vm)
        XCTAssertEqual(p.connectionLevel, .error)
        XCTAssertFalse(p.canSend)
    }

    // MARK: errors stay visible

    func testSendFailureIsVisibleInPresentation() {
        let t = MockMIDITransport(destinations: [anagram])
        let vm = makeVM(t)
        vm.selectDestination(42)
        t.sendError = MIDITransportError.sendFailed(-1)
        vm.sendPreset(1)
        let p = PerformancePresentation(vm: vm)
        XCTAssertTrue(p.errorText?.contains("-1") == true)
        XCTAssertEqual(PerformancePresentation(vm: vm).preset.label, "—", "failed send must not update preset readout")
    }

    func testInitializationFailureIsVisibleInPresentation() {
        let t = MockMIDITransport(destinations: [anagram])
        t.initializationError = .outputPortCreationFailed(-50)
        let p = PerformancePresentation(vm: makeVM(t))
        XCTAssertEqual(p.connectionLevel, .error)
        XCTAssertFalse(p.canSend)
        XCTAssertTrue(p.errorText?.contains("-50") == true)
    }
}
