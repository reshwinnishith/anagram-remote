import XCTest
@testable import AnagramRemote

final class StompEditorDraftTests: XCTestCase {
    private func draft(_ a: StompAssignment = .unassigned(slot: 1), scope: StompEditorDraft.Scope = .global) -> StompEditorDraft {
        StompEditorDraft(assignment: a, scope: scope)
    }
    private func ccDraft(controller: Int? = 80) -> StompEditorDraft {
        var d = draft(); d.kind = .controlChange; d.controller = controller; return d
    }

    // Round trips
    func testEveryActionRoundTripsThroughDraft() {
        let cases: [StompAction] = [
            .unassigned,
            .programChange(channel: 16, program: 126),
            .controlChange(channel: 2, controller: 80, behavior: .toggle(.values(on: 100, off: 10))),
            .controlChange(channel: 3, controller: 81, behavior: .toggle(.deviceToggle(trigger: 64))),
            .controlChange(channel: 4, controller: 82, behavior: .momentary(press: 127, release: 0)),
            .controlChange(channel: 5, controller: 83, behavior: .fixedValue(33))]
        for action in cases {
            let a = StompAssignment(slot: 4, name: "Hold", accentID: "teal", action: action)
            XCTAssertEqual(draft(a).finalAssignment(), a, "\(action)")
        }
    }

    func testNewCCDraftUsesSuggestedValuesButNeedsAController() {
        let d = ccDraft(controller: nil)
        XCTAssertEqual(d.missingFields, [.controller])
        XCTAssertNil(d.buildAssignment())
        XCTAssertFalse(d.evaluate().canSave)
        XCTAssertEqual(d.evaluate().errors(for: .controller), ["Enter a value."])
    }

    // Validation mapped to fields (rules come from AssignmentValidator)
    func testValidCCDraftCanSave() { XCTAssertTrue(ccDraft().evaluate().canSave) }

    func testFieldErrorsAreAttachedToTheRightField() {
        var d = ccDraft(controller: 200); XCTAssertFalse(d.evaluate().errors(for: .controller).isEmpty)
        d = ccDraft(); d.channel = 17; XCTAssertFalse(d.evaluate().errors(for: .channel).isEmpty)
        d = ccDraft(); d.style = .valueToggle; d.onValue = 5; d.offValue = 5; XCTAssertFalse(d.evaluate().errors(for: .offValue).isEmpty)
        d = ccDraft(); d.onValue = 128; XCTAssertFalse(d.evaluate().errors(for: .onValue).isEmpty)
        d = ccDraft(); d.style = .deviceToggle; d.triggerValue = 0; XCTAssertFalse(d.evaluate().errors(for: .triggerValue).isEmpty)
        d = ccDraft(); d.style = .momentary; d.pressValue = 9; d.releaseValue = 9; XCTAssertFalse(d.evaluate().errors(for: .releaseValue).isEmpty)
        d = ccDraft(); d.style = .momentary; d.pressValue = -1; XCTAssertFalse(d.evaluate().errors(for: .pressValue).isEmpty)
        d = ccDraft(); d.style = .fixedValue; d.fixedValue = 128; XCTAssertFalse(d.evaluate().errors(for: .fixedValue).isEmpty)
        d = ccDraft(); d.accentID = "nope"; XCTAssertFalse(d.evaluate().errors(for: .accent).isEmpty)
        d = ccDraft(); d.name = String(repeating: "x", count: 17); XCTAssertFalse(d.evaluate().errors(for: .name).isEmpty)
    }

    func testProgramChangeBounds() {
        var d = draft(); d.kind = .programChange
        XCTAssertEqual(d.missingFields, [.program])
        for p in [1, 126] { d.program = p; XCTAssertTrue(d.evaluate().canSave, "program \(p)") }
        for p in [0, 127] { d.program = p; XCTAssertFalse(d.evaluate().canSave, "program \(p)"); XCTAssertFalse(d.evaluate().errors(for: .program).isEmpty) }
    }

    func testUnassignedDraftIgnoresStaleInvalidCCFields() {
        var d = ccDraft(controller: 999)
        d.kind = .unassigned
        XCTAssertTrue(d.evaluate().canSave)
        XCTAssertEqual(d.finalAssignment()?.action, .unassigned)
    }

    func testOnlyFieldsForTheChosenStyleAreRequired() {
        var d = ccDraft(); d.style = .deviceToggle; d.onValue = nil; d.offValue = nil
        XCTAssertTrue(d.missingFields.isEmpty)
        d.style = .valueToggle; XCTAssertEqual(Set(d.missingFields), [.onValue, .offValue])
    }

    // Advanced acknowledgement
    func testReservedControllerNeedsAcknowledgementThenSaves() {
        var d = ccDraft(controller: 7)
        var r = d.evaluate()
        XCTAssertEqual(r.warnings, [.anagramReserved]); XCTAssertEqual(r.unacknowledged, [.anagramReserved]); XCTAssertFalse(r.canSave)
        d.acknowledged.insert(.anagramReserved)
        r = d.evaluate(); XCTAssertTrue(r.canSave)
        XCTAssertEqual(d.finalAssignment()?.acknowledgedWarnings, [.anagramReserved])
    }

    func testBankSelectAndChannelModeNeedTheirOwnAcknowledgement() {
        var d = ccDraft(controller: 32); d.acknowledged = [.channelModeController]
        XCTAssertFalse(d.evaluate().canSave)
        d.acknowledged = [.bankSelect]; XCTAssertTrue(d.evaluate().canSave)
        d = ccDraft(controller: 123); XCTAssertEqual(d.evaluate().unacknowledged, [.channelModeController])
    }

    func testStaleAcknowledgementIsNotStoredWhenControllerChanges() {
        var d = ccDraft(controller: 7); d.acknowledged = [.anagramReserved]
        d.controller = 80
        XCTAssertTrue(d.evaluate().warnings.isEmpty)
        XCTAssertEqual(d.finalAssignment()?.acknowledgedWarnings, [])
    }

    func testNoWarningJudgedWhileControllerEmpty() {
        XCTAssertTrue(ccDraft(controller: nil).evaluate().warnings.isEmpty)
    }

    func testProgramChangeNeverNeedsAcknowledgement() {
        var d = draft(); d.kind = .programChange; d.program = 7
        XCTAssertTrue(d.evaluate().warnings.isEmpty); XCTAssertTrue(d.evaluate().canSave)
    }

    // Dirty tracking / scope
    func testDraftEqualityDrivesDirtyState() {
        let original = draft(); var d = original
        XCTAssertEqual(d, original)
        d.name = "Edited"; XCTAssertNotEqual(d, original)
        d.name = original.name; XCTAssertEqual(d, original)
    }

    func testNameIsNormalisedOnBuild() {
        var d = ccDraft(); d.name = "  Big   Muff "
        XCTAssertEqual(d.finalAssignment()?.name, "Big Muff")
    }

    func testDraftKeepsItsScope() {
        XCTAssertEqual(draft(scope: .preset(5)).scope, .preset(5))
    }

    // Responsive layout decision
    func testEditorLayoutUsesTwoColumnsOnlyWhenWideAndTextIsNotLarge() {
        let wide = StompEditorLayout.twoColumnMinWidth
        XCTAssertTrue(StompEditorLayout.usesTwoColumns(width: 1133, typeSize: .large))
        XCTAssertTrue(StompEditorLayout.usesTwoColumns(width: wide, typeSize: .xxLarge))
        XCTAssertFalse(StompEditorLayout.usesTwoColumns(width: wide - 1, typeSize: .large), "narrow width falls back to one column")
        XCTAssertFalse(StompEditorLayout.usesTwoColumns(width: 1133, typeSize: .xxxLarge), "large text falls back to one column")
        XCTAssertFalse(StompEditorLayout.usesTwoColumns(width: 1133, typeSize: .accessibility3))
        XCTAssertFalse(StompEditorLayout.usesTwoColumns(width: 0, typeSize: .large))
    }
}
