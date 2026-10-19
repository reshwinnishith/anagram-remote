import XCTest
@testable import AnagramRemote

final class StompModelsTests: XCTestCase {
    private func roundTrip(_ a: StompAssignment, file: StaticString = #filePath, line: UInt = #line) throws {
        let data = try JSONEncoder().encode(a)
        XCTAssertEqual(try JSONDecoder().decode(StompAssignment.self, from: data), a, file: file, line: line)
    }

    func testRoundTripUnassigned() throws { try roundTrip(.unassigned(slot: 3)) }

    func testRoundTripProgramChange() throws {
        try roundTrip(StompAssignment(slot: 1, name: "Verb", accentID: "blue", action: .programChange(channel: 16, program: 126)))
    }

    func testRoundTripEveryCCBehavior() throws {
        let behaviors: [CCBehavior] = [
            .toggle(.values(on: 127, off: 0)), .toggle(.values(on: 64, off: 1)),
            .toggle(.deviceToggle(trigger: 127)), .toggle(.deviceToggle(trigger: 1)),
            .momentary(press: 127, release: 0), .fixedValue(0), .fixedValue(127)]
        for (i, b) in behaviors.enumerated() {
            try roundTrip(StompAssignment(slot: 1 + i % 6, name: "N\(i)", accentID: "teal",
                                          action: .controlChange(channel: 1 + i, controller: i * 10, behavior: b),
                                          acknowledgedWarnings: [.bankSelect]))
        }
    }

    func testBoundaryValuesRoundTrip() throws {
        try roundTrip(StompAssignment(slot: 6, name: "", accentID: "silver",
                                      action: .controlChange(channel: 1, controller: 0, behavior: .momentary(press: 0, release: 127))))
        try roundTrip(StompAssignment(slot: 6, name: "", accentID: "silver",
                                      action: .controlChange(channel: 16, controller: 127, behavior: .fixedValue(127))))
    }

    func testUnknownActionKindFailsToDecode() {
        let json = #"{"slot":1,"name":"","accentID":"blue","acknowledgedWarnings":[],"action":{"kind":"sysex"}}"#
        XCTAssertThrowsError(try JSONDecoder().decode(StompAssignment.self, from: Data(json.utf8)))
    }

    func testUnknownAccentDecodesButIsLaterRejected() throws {
        let json = #"{"slot":1,"name":"","accentID":"chartreuse","acknowledgedWarnings":[],"action":{"kind":"unassigned"}}"#
        let a = try JSONDecoder().decode(StompAssignment.self, from: Data(json.utf8))
        XCTAssertEqual(AssignmentValidator().validate(a).errors, [.unknownAccent("chartreuse")])
    }

    func testNameNormalization() {
        XCTAssertEqual(StompAssignment.normalizedName("  Big   Muff \n Pi "), "Big Muff Pi")
        XCTAssertEqual(StompAssignment.normalizedName("   "), "")
    }

    func testDisplayNameFallsBackToStompN() {
        XCTAssertEqual(StompAssignment.unassigned(slot: 4).displayName, "Stomp 4")
        var a = StompAssignment.unassigned(slot: 4); a.name = "Drive"
        XCTAssertEqual(a.displayName, "Drive")
    }

    func testNormalizedSortsAndDedupesAcknowledgements() {
        var a = StompAssignment.unassigned(slot: 1)
        a.acknowledgedWarnings = [.bankSelect, .channelModeController, .bankSelect]
        XCTAssertEqual(a.normalized().acknowledgedWarnings, [.bankSelect, .channelModeController])
    }

    func testAccentPaletteMatchesThemeCount() {
        XCTAssertEqual(StompAccent.ids.count, Theme.stompAccents.count)
        XCTAssertEqual(Set(StompAccent.ids).count, StompAccent.ids.count)
    }
}
