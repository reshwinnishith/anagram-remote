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
}
