import XCTest
@testable import AnagramRemote

final class AssignmentValidatorTests: XCTestCase {
    private let v = AssignmentValidator()

    private func cc(_ controller: Int, channel: Int = 1, _ b: CCBehavior = .fixedValue(1), ack: [SafetyWarning] = []) -> StompAssignment {
        StompAssignment(slot: 1, name: "", accentID: "blue",
                        action: .controlChange(channel: channel, controller: controller, behavior: b), acknowledgedWarnings: ack)
    }
    private func pc(_ program: Int, channel: Int = 1) -> StompAssignment {
        StompAssignment(slot: 1, name: "", accentID: "blue", action: .programChange(channel: channel, program: program))
    }

    func testUnassignedIsValid() { XCTAssertTrue(v.validate(.unassigned(slot: 1)).isAcceptable) }

    // Slot / channel / controller / program boundaries
    func testSlotBounds() {
        for s in [1, 6] { XCTAssertTrue(v.validate(.unassigned(slot: s)).isValid) }
        for s in [0, 7, -1] { XCTAssertEqual(v.validate(.unassigned(slot: s)).errors, [.invalidSlot(s)]) }
    }
    func testChannelBounds() {
        for c in [1, 16] { XCTAssertTrue(v.validate(cc(80, channel: c)).isValid); XCTAssertTrue(v.validate(pc(1, channel: c)).isValid) }
        for c in [0, 17, -1] {
            XCTAssertEqual(v.validate(cc(80, channel: c)).errors, [.invalidChannel(c)])
            XCTAssertEqual(v.validate(pc(1, channel: c)).errors, [.invalidChannel(c)])
        }
    }
    func testControllerBounds() {
        XCTAssertTrue(v.validate(cc(1)).isAcceptable)
        XCTAssertTrue(v.validate(cc(101)).isAcceptable)
        for c in [-1, 128, 1000] { XCTAssertEqual(v.validate(cc(c)).errors, [.invalidController(c)]) }
    }
    func testProgramBoundsPreserveM1Convention() {
        for p in [1, 2, 126] { XCTAssertTrue(v.validate(pc(p)).isValid) }
        for p in [0, 127, 128, -1] { XCTAssertEqual(v.validate(pc(p)).errors, [.invalidProgram(p)]) }
    }

    // Behaviours
    func testToggleValuesMode() {
        XCTAssertTrue(v.validate(cc(80, .toggle(.values(on: 127, off: 0)))).isValid)
        XCTAssertTrue(v.validate(cc(80, .toggle(.values(on: 0, off: 127)))).isValid)
        XCTAssertTrue(v.validate(cc(80, .toggle(.values(on: 64, off: 1)))).isValid)
        XCTAssertEqual(v.validate(cc(80, .toggle(.values(on: 5, off: 5)))).errors, [.onOffValuesIdentical(5)])
        XCTAssertEqual(v.validate(cc(80, .toggle(.values(on: 128, off: 0)))).errors, [.invalidValue(name: "ON", value: 128)])
        XCTAssertEqual(v.validate(cc(80, .toggle(.values(on: 1, off: -1)))).errors, [.invalidValue(name: "OFF", value: -1)])
    }
    func testDeviceToggleRequiresNonzeroTrigger() {
        for t in [1, 64, 127] { XCTAssertTrue(v.validate(cc(80, .toggle(.deviceToggle(trigger: t)))).isValid) }
        for t in [0, 128, -1] { XCTAssertEqual(v.validate(cc(80, .toggle(.deviceToggle(trigger: t)))).errors, [.toggleTriggerMustBeNonzero(t)]) }
    }
    func testMomentary() {
        XCTAssertTrue(v.validate(cc(80, .momentary(press: 127, release: 0))).isValid)
        XCTAssertEqual(v.validate(cc(80, .momentary(press: 9, release: 9))).errors, [.pressReleaseValuesIdentical(9)])
        XCTAssertEqual(v.validate(cc(80, .momentary(press: 128, release: 0))).errors, [.invalidValue(name: "press", value: 128)])
    }
    func testFixedValue() {
        for x in [0, 127] { XCTAssertTrue(v.validate(cc(80, .fixedValue(x))).isValid) }
        for x in [-1, 128] { XCTAssertEqual(v.validate(cc(80, .fixedValue(x))).errors, [.invalidValue(name: "fixed", value: x)]) }
    }

    // Safety
    func testChannelModeControllersNeedAcknowledgement() {
        for c in 120...127 {
            let r = v.validate(cc(c))
            XCTAssertTrue(r.isValid, "CC \(c) is valid MIDI, not a hard error")
            XCTAssertEqual(r.unacknowledged, [.channelModeController]); XCTAssertFalse(r.isAcceptable)
            XCTAssertTrue(v.validate(cc(c, ack: [.channelModeController])).isAcceptable)
        }
        XCTAssertTrue(v.validate(cc(101)).warnings.isEmpty)
    }
    func testBankSelectNeedsAcknowledgement() {
        for c in [0, 32] {
            XCTAssertEqual(v.validate(cc(c)).unacknowledged, [.bankSelect])
            XCTAssertTrue(v.validate(cc(c, ack: [.bankSelect])).isAcceptable)
            // Acknowledging a different warning does not help.
            XCTAssertFalse(v.validate(cc(c, ack: [.channelModeController])).isAcceptable)
        }
        XCTAssertTrue(v.validate(cc(1)).warnings.isEmpty)
        XCTAssertTrue(v.validate(cc(33)).warnings.isEmpty)
    }
    func testManualReservedList() {
        let expected = Set([0, 7, 89] + Array(14...32) + Array(85...87) + Array(102...119))
        XCTAssertEqual(SafetyPolicy().anagramReservedControllers, expected)
        XCTAssertEqual(expected.count, 3 + 19 + 3 + 18)
    }
    func testEveryReservedControllerIsAnAcknowledgeableWarningNotAnError() {
        for c in SafetyPolicy().anagramReservedControllers {
            let r = v.validate(cc(c))
            XCTAssertTrue(r.isValid, "CC \(c) is valid MIDI")
            XCTAssertEqual(r.warnings.count, 1, "CC \(c) must raise exactly one warning")
            XCTAssertFalse(r.isAcceptable)
            let kind = r.warnings[0]
            XCTAssertTrue(v.validate(cc(c, ack: [kind])).isAcceptable, "CC \(c)")
        }
    }
    func testReservedNeighboursAreNotWarned() {
        for c in [1, 6, 8, 13, 33, 84, 88, 90, 101] { XCTAssertTrue(v.validate(cc(c)).warnings.isEmpty, "CC \(c)") }
    }
    func testAtMostOneWarningForAnyController() {
        for c in 0...127 { XCTAssertLessThanOrEqual(v.validate(cc(c)).warnings.count, 1, "CC \(c)") }
    }
    func testWarningKindPerController() {
        XCTAssertEqual(v.validate(cc(0)).warnings, [.bankSelect])
        XCTAssertEqual(v.validate(cc(32)).warnings, [.bankSelect], "Bank Select takes precedence over reserved")
        XCTAssertEqual(v.validate(cc(7)).warnings, [.anagramReserved])
        XCTAssertEqual(v.validate(cc(20)).warnings, [.anagramReserved])
        XCTAssertEqual(v.validate(cc(119)).warnings, [.anagramReserved])
        for c in 120...127 { XCTAssertEqual(v.validate(cc(c)).warnings, [.channelModeController], "CC \(c)") }
    }
    func testReservedAcknowledgementDoesNotCoverOtherWarnings() {
        XCTAssertFalse(v.validate(cc(7, ack: [.bankSelect])).isAcceptable)
        XCTAssertFalse(v.validate(cc(125, ack: [.anagramReserved])).isAcceptable)
    }
    func testPolicyCanBeEmptiedOrExtended() {
        XCTAssertTrue(AssignmentValidator(policy: SafetyPolicy(anagramReservedControllers: [])).validate(cc(7)).warnings.isEmpty)
        let strict = AssignmentValidator(policy: SafetyPolicy(anagramReservedControllers: [70]))
        XCTAssertEqual(strict.validate(cc(70)).unacknowledged, [.anagramReserved])
    }
    func testWarningTextsExistAndAreDistinct() {
        let texts = SafetyWarning.allCases.map(\.explanation)
        XCTAssertTrue(texts.allSatisfy { !$0.isEmpty }); XCTAssertEqual(Set(texts).count, texts.count)
        XCTAssertTrue(SafetyWarning.bankSelect.explanation.contains("reserved"), "bank select text mentions the reservation")
    }
    func testWarningsDoNotApplyToProgramChange() {
        XCTAssertTrue(v.validate(pc(1)).warnings.isEmpty)
    }
    func testHardErrorsAreNotClearedByAcknowledgement() {
        XCTAssertFalse(v.validate(cc(0, channel: 17, ack: [.bankSelect])).isValid)
    }

    // Name / accent
    func testNameLength() {
        var a = StompAssignment.unassigned(slot: 1)
        a.name = String(repeating: "x", count: 16); XCTAssertTrue(v.validate(a).isValid)
        a.name = String(repeating: "x", count: 17); XCTAssertEqual(v.validate(a).errors, [.nameTooLong(length: 17, max: 16)])
        a.name = "   " + String(repeating: "x", count: 16) + "   "; XCTAssertTrue(v.validate(a).isValid, "length is measured after normalisation")
    }
    func testAccentValidation() {
        for id in StompAccent.ids { var a = StompAssignment.unassigned(slot: 1); a.accentID = id; XCTAssertTrue(v.validate(a).isValid) }
        var a = StompAssignment.unassigned(slot: 1); a.accentID = ""
        XCTAssertEqual(v.validate(a).errors, [.unknownAccent("")])
    }

    // Profile
    func testDefaultProfileIsAcceptable() { XCTAssertTrue(v.validate(StompProfile.defaults).isAcceptable) }
    func testProfileRequiresExactlySixGlobalSlots() {
        var p = StompProfile.defaults; p.globalSlots.removeLast()
        XCTAssertTrue(v.validate(p).errors.contains { $0.error == .wrongGlobalSlotCount(5) })
        p = StompProfile.defaults; p.globalSlots.append(.unassigned(slot: 7))
        XCTAssertTrue(v.validate(p).errors.contains { $0.error == .wrongGlobalSlotCount(7) })
    }
    func testProfileSlotsMustBeInOrder() {
        var p = StompProfile.defaults; p.globalSlots.swapAt(0, 1)
        XCTAssertFalse(v.validate(p).isAcceptable)
    }
    func testOverrideKeyBounds() {
        for k in [1, 126] { var p = StompProfile.defaults; p.setOverride(preset: k, .unassigned(slot: 1)); XCTAssertTrue(v.validate(p).isAcceptable) }
        for k in [0, 127, -5] {
            var p = StompProfile.defaults; p.setOverride(preset: k, .unassigned(slot: 1))
            XCTAssertTrue(v.validate(p).errors.contains { $0.error == .invalidOverrideKey(k) })
        }
    }
    func testDuplicateOverridesRejected() {
        var p = StompProfile.defaults
        p.overrides = [PresetOverride(preset: 2, assignments: [.unassigned(slot: 1), .unassigned(slot: 1)])]
        XCTAssertTrue(v.validate(p).errors.contains { $0.error == .duplicateOverrideSlot(preset: 2, slot: 1) })
        p.overrides = [PresetOverride(preset: 2, assignments: []), PresetOverride(preset: 2, assignments: [])]
        XCTAssertTrue(v.validate(p).errors.contains { $0.error == .duplicateOverridePreset(2) })
    }
    func testUnacknowledgedWarningInOverrideIsReportedWithLocation() {
        var p = StompProfile.defaults
        p.setOverride(preset: 5, cc(0))
        XCTAssertEqual(v.validate(p).unacknowledged, [.init(location: .override(preset: 5, slot: 1), warning: .bankSelect)])
    }
}
