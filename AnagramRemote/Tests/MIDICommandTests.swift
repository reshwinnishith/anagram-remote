import XCTest
@testable import AnagramRemote

final class MIDICommandTests: XCTestCase {
    func testProgramChangeChannel1() throws {
        XCTAssertEqual(try MIDICommand.programChange(channel: 1, program: 1).bytes(), [0xC0, 0x00])
    }

    func testProgramChangeChannel16() throws {
        XCTAssertEqual(try MIDICommand.programChange(channel: 16, program: 1).bytes(), [0xCF, 0x00])
    }

    func testPreset01A() throws {
        XCTAssertEqual(try MIDICommand.programChange(channel: 1, program: 1).bytes(), [0xC0, 0x00])
    }

    func testPreset01B() throws {
        XCTAssertEqual(try MIDICommand.programChange(channel: 1, program: 2).bytes(), [0xC0, 0x01])
    }

    func testProgram126() throws {
        XCTAssertEqual(try MIDICommand.programChange(channel: 1, program: 126).bytes(), [0xC0, 125])
    }

    func testInvalidChannels() {
        for c in [0, 17, -1] {
            XCTAssertThrowsError(try MIDICommand.programChange(channel: c, program: 1).bytes()) {
                XCTAssertEqual($0 as? MIDIValidationError, .invalidChannel(c))
            }
        }
    }

    func testInvalidPrograms() {
        for p in [0, 127, 128, -1] {
            XCTAssertThrowsError(try MIDICommand.programChange(channel: 1, program: p).bytes()) {
                XCTAssertEqual($0 as? MIDIValidationError, .invalidProgram(p))
            }
        }
    }

    func testControlChangeBytes() throws {
        XCTAssertEqual(try MIDICommand.controlChange(channel: 1, controller: 80, value: 127).bytes(), [0xB0, 80, 127])
        XCTAssertEqual(try MIDICommand.controlChange(channel: 2, controller: 7, value: 0).bytes(), [0xB1, 7, 0])
        XCTAssertEqual(try MIDICommand.controlChange(channel: 16, controller: 127, value: 64).bytes(), [0xBF, 127, 64])
    }

    func testControlChangeBoundaries() throws {
        XCTAssertEqual(try MIDICommand.controlChange(channel: 1, controller: 0, value: 0).bytes(), [0xB0, 0, 0])
        XCTAssertEqual(try MIDICommand.controlChange(channel: 16, controller: 127, value: 127).bytes(), [0xBF, 127, 127])
    }

    func testControlChangeInvalidInputThrowsSpecificErrors() {
        for c in [0, 17, -1] {
            XCTAssertThrowsError(try MIDICommand.controlChange(channel: c, controller: 1, value: 1).bytes()) {
                XCTAssertEqual($0 as? MIDIValidationError, .invalidChannel(c))
            }
        }
        for c in [-1, 128, 1000] {
            XCTAssertThrowsError(try MIDICommand.controlChange(channel: 1, controller: c, value: 1).bytes()) {
                XCTAssertEqual($0 as? MIDIValidationError, .invalidController(c))
            }
        }
        for v in [-1, 128, 255] {
            XCTAssertThrowsError(try MIDICommand.controlChange(channel: 1, controller: 1, value: v).bytes()) {
                XCTAssertEqual($0 as? MIDIValidationError, .invalidValue(v))
            }
        }
    }

    func testControlChangeIsNeverPrecededByBankSelectOrExtraBytes() throws {
        XCTAssertEqual(try MIDICommand.controlChange(channel: 1, controller: 80, value: 1).bytes().count, 3)
    }

    func testProgramChangeBytesUnchangedAfterControlChangeWasAdded() throws {
        XCTAssertEqual(try MIDICommand.programChange(channel: 3, program: 1).bytes(), [0xC2, 0x00])
        XCTAssertEqual(try MIDICommand.programChange(channel: 1, program: 126).bytes(), [0xC0, 125])
    }
}
