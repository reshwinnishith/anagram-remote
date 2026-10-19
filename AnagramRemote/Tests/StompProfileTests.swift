import XCTest
@testable import AnagramRemote

final class StompProfileTests: XCTestCase {
    private func pc(_ slot: Int, _ program: Int) -> StompAssignment {
        StompAssignment(slot: slot, name: "PC\(program)", accentID: "green", action: .programChange(channel: 1, program: program))
    }

    func testDefaultsAreExactlySixUnassignedSlotsInOrder() {
        let p = StompProfile.defaults
        XCTAssertEqual(p.globalSlots.map(\.slot), [1, 2, 3, 4, 5, 6])
        XCTAssertTrue(p.globalSlots.allSatisfy { $0.action == .unassigned })
        XCTAssertTrue(p.overrides.isEmpty)
        XCTAssertEqual(p.globalSlots.map(\.accentID), Array(StompAccent.ids.prefix(6)))
    }

    func testGlobalAppliesWithoutOverride() {
        var p = StompProfile.defaults; p.setGlobal(pc(2, 10))
        XCTAssertEqual(p.resolved(slot: 2, preset: nil)?.action, .programChange(channel: 1, program: 10))
        XCTAssertEqual(p.resolved(slot: 2, preset: 7)?.action, .programChange(channel: 1, program: 10))
    }

    func testOverrideWinsOnlyForItsPresetAndSlot() {
        var p = StompProfile.defaults; p.setGlobal(pc(2, 10)); p.setOverride(preset: 3, pc(2, 20))
        XCTAssertEqual(p.resolved(slot: 2, preset: 3)?.action, .programChange(channel: 1, program: 20))
        XCTAssertEqual(p.resolved(slot: 2, preset: 4)?.action, .programChange(channel: 1, program: 10))
        XCTAssertEqual(p.resolved(slot: 2, preset: nil)?.action, .programChange(channel: 1, program: 10))
        XCTAssertEqual(p.resolved(slot: 1, preset: 3), p.globalSlots[0], "other slots of the same preset stay global")
    }

    func testExplicitUnassignedOverrideBeatsGlobal() {
        var p = StompProfile.defaults; p.setGlobal(pc(1, 5))
        p.setOverride(preset: 9, .unassigned(slot: 1))
        XCTAssertEqual(p.resolved(slot: 1, preset: 9)?.action, .unassigned)
        XCTAssertTrue(p.hasOverride(preset: 9, slot: 1))
        XCTAssertEqual(p.resolved(slot: 1, preset: 8)?.action, .programChange(channel: 1, program: 5))
    }

    func testResetToGlobalRemovesOverride() {
        var p = StompProfile.defaults; p.setGlobal(pc(1, 5)); p.setOverride(preset: 9, .unassigned(slot: 1))
        p.resetToGlobal(preset: 9, slot: 1)
        XCTAssertFalse(p.hasOverride(preset: 9, slot: 1))
        XCTAssertEqual(p.resolved(slot: 1, preset: 9)?.action, .programChange(channel: 1, program: 5))
        XCTAssertTrue(p.overrides.isEmpty, "empty preset entry is removed")
    }

    func testResetKeepsOtherOverrides() {
        var p = StompProfile.defaults
        p.setOverride(preset: 1, pc(1, 1)); p.setOverride(preset: 1, pc(2, 2)); p.setOverride(preset: 2, pc(1, 3))
        p.resetToGlobal(preset: 1, slot: 1)
        XCTAssertFalse(p.hasOverride(preset: 1, slot: 1)); XCTAssertTrue(p.hasOverride(preset: 1, slot: 2)); XCTAssertTrue(p.hasOverride(preset: 2, slot: 1))
        p.resetAllToGlobal(preset: 1)
        XCTAssertEqual(p.overrides.map(\.preset), [2])
    }

    func testResetOfMissingOverrideIsNoOp() {
        var p = StompProfile.defaults; let before = p
        p.resetToGlobal(preset: 4, slot: 1); XCTAssertEqual(p, before)
    }

    func testReplacingAnOverrideDoesNotDuplicate() {
        var p = StompProfile.defaults
        p.setOverride(preset: 1, pc(1, 1)); p.setOverride(preset: 1, pc(1, 2))
        XCTAssertEqual(p.overrides.count, 1); XCTAssertEqual(p.overrides[0].assignments.count, 1)
        XCTAssertEqual(p.resolved(slot: 1, preset: 1)?.action, .programChange(channel: 1, program: 2))
    }

    func testResolutionIsDeterministicRegardlessOfInsertionOrder() {
        var a = StompProfile.defaults; a.setOverride(preset: 5, pc(3, 1)); a.setOverride(preset: 2, pc(1, 2)); a.setOverride(preset: 5, pc(1, 3))
        var b = StompProfile.defaults; b.setOverride(preset: 5, pc(1, 3)); b.setOverride(preset: 2, pc(1, 2)); b.setOverride(preset: 5, pc(3, 1))
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.resolvedSlots(preset: 5), b.resolvedSlots(preset: 5))
        XCTAssertEqual(a.overrides.map(\.preset), [2, 5])
    }

    func testResolvedSlotsReturnsSix() {
        XCTAssertEqual(StompProfile.defaults.resolvedSlots(preset: 3).count, 6)
        XCTAssertNil(StompProfile.defaults.resolved(slot: 0, preset: nil))
        XCTAssertNil(StompProfile.defaults.resolved(slot: 7, preset: nil))
    }

    func testSetGlobalRejectsOutOfRangeSlot() {
        var p = StompProfile.defaults
        XCTAssertFalse(p.setGlobal(pc(7, 1))); XCTAssertFalse(p.setGlobal(pc(0, 1)))
        XCTAssertFalse(p.setOverride(preset: 1, pc(9, 1)))
        XCTAssertEqual(p, StompProfile.defaults)
    }

    func testProfileCodableRoundTrip() throws {
        var p = StompProfile.defaults; p.setGlobal(pc(1, 5)); p.setOverride(preset: 7, .unassigned(slot: 2))
        let back = try JSONDecoder().decode(StompProfile.self, from: JSONEncoder().encode(p))
        XCTAssertEqual(back, p)
    }

    func testResolutionNeverNeedsHardwarePresetState() {
        // The API takes the preset as an argument; nothing reads or caches an "active hardware preset".
        let p = StompProfile.defaults
        XCTAssertEqual(p.resolved(slot: 1, preset: 1), p.resolved(slot: 1, preset: 2))
    }
}
