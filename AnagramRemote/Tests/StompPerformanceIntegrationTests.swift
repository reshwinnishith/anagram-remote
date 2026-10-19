import XCTest
@testable import AnagramRemote

@MainActor
final class StompPerformanceIntegrationTests: XCTestCase {
    func testConfiguredStompShowsLabelAccentAndMessageButStaysInert() {
        let a = StompAssignment(slot: 2, name: "Chorus", accentID: "pink",
                                action: .controlChange(channel: 3, controller: 80, behavior: .toggle(.values(on: 127, off: 0))))
        let p = StompPresentation(assignment: a)
        XCTAssertEqual(p.index, 2); XCTAssertEqual(p.customLabel, "Chorus"); XCTAssertEqual(p.statusText, "CC 80 · Ch 3")
        XCTAssertTrue(p.isConfigured); XCTAssertFalse(p.isEnabled)
        XCTAssertEqual(p.localState, .unassigned, "no ON/OFF state is implied")
        XCTAssertEqual(p.confirmedState, .notAvailable)
        XCTAssertNotNil(p.accent)
    }

    func testUnassignedStompKeepsPlaceholderText() {
        let p = StompPresentation(assignment: .unassigned(slot: 4))
        XCTAssertFalse(p.isConfigured); XCTAssertEqual(p.statusText, "UNASSIGNED"); XCTAssertNil(p.customLabel)
        XCTAssertEqual(p.title, "Stomp 4"); XCTAssertFalse(p.isEnabled)
    }

    func testProgramChangeAssignmentSummary() {
        let a = StompAssignment(slot: 1, name: "", accentID: "blue", action: .programChange(channel: 1, program: 12))
        XCTAssertEqual(StompPresentation(assignment: a).statusText, "PC 12 · Ch 1")
    }

    func testPlaceholdersAndScenesAreUnchanged() {
        XCTAssertEqual(StompPresentation.all.count, 6)
        XCTAssertTrue(StompPresentation.all.allSatisfy { !$0.isConfigured && $0.statusText == "UNASSIGNED" })
        XCTAssertTrue(SceneSlotPresentation.all.allSatisfy { !$0.isEnabled && $0.statusText == "NOT CONFIGURED" })
    }

    func testPerformanceUsesGlobalAssignmentsOnly() {
        var p = StompProfile.defaults
        p.setGlobal(StompAssignment(slot: 1, name: "G", accentID: "blue", action: .programChange(channel: 1, program: 1)))
        p.setOverride(preset: 2, StompAssignment(slot: 1, name: "O", accentID: "blue", action: .unassigned))
        XCTAssertEqual(p.resolved(slot: 1, preset: nil)?.name, "G", "no hardware preset is inferred for the live view")
    }

    func testM1PresetBehaviourUnchanged() throws {
        let t = MockMIDITransport(destinations: [MIDIDestination(id: 42, name: "Anagram")])
        let vm = ConnectionViewModel(manager: MIDIConnectionManager(transport: t))
        vm.selectDestination(42)
        _ = StompPresentation(assignment: .unassigned(slot: 1))
        XCTAssertTrue(t.sent.isEmpty)
        vm.sendPreset(1); vm.sendPreset(2)
        XCTAssertEqual(t.sent.map(\.bytes), [[0xC0, 0x00], [0xC0, 0x01]])
    }
}
