import Foundation

enum MIDIValidationError: Error, Equatable, LocalizedError {
    case invalidChannel(Int)
    case invalidProgram(Int)
    case invalidController(Int)
    case invalidValue(Int)

    var errorDescription: String? {
        switch self {
        case .invalidController(let c): return "Invalid controller \(c); must be 0–127."
        case .invalidValue(let v): return "Invalid value \(v); must be 0–127."
        case .invalidChannel(let c): return "Invalid MIDI channel \(c); must be 1–16."
        case .invalidProgram(let p): return "Invalid program \(p); must be 1–126."
        }
    }
}

/// One-based (UI / manual) to zero-based (wire) preset numbering.
///
/// ASSUMPTION — UNVERIFIED ON HARDWARE: preset/program 1 is sent as data byte 0,
/// program 2 as data byte 1. If the Anagram turns out to use a different offset,
/// change `dataByteOffset` here (and the tests) deliberately; do not adjust it elsewhere.
enum ProgramNumbering {
    /// Presets documented as 1–126 (per product brief; manual not independently checked).
    static let uiRange = 1...126
    static let dataByteOffset = -1
    static let channelRange = 1...16

    static func dataByte(forProgram program: Int) throws -> UInt8 {
        guard uiRange.contains(program) else { throw MIDIValidationError.invalidProgram(program) }
        return UInt8(program + dataByteOffset)
    }
}

enum MIDIDataBytes {
    static let range = 0...127
}

enum MIDICommand: Equatable {
    /// `channel` 1–16, `program` 1–126 (one-based). No Bank Select in M1.
    case programChange(channel: Int, program: Int)
    case controlChange(channel: Int, controller: Int, value: Int)

    /// Raw MIDI bytes. Program Change = 0xC0 | (channel − 1), then one data byte.
    func bytes() throws -> [UInt8] {
        switch self {
        case let .programChange(channel, program):
            guard ProgramNumbering.channelRange.contains(channel) else {
                throw MIDIValidationError.invalidChannel(channel)
            }
            let data = try ProgramNumbering.dataByte(forProgram: program)
            return [0xC0 | UInt8(channel - 1), data]
        case let .controlChange(channel, controller, value):
            guard ProgramNumbering.channelRange.contains(channel) else {
                throw MIDIValidationError.invalidChannel(channel)
            }
            guard MIDIDataBytes.range.contains(controller) else {
                throw MIDIValidationError.invalidController(controller)
            }
            guard MIDIDataBytes.range.contains(value) else {
                throw MIDIValidationError.invalidValue(value)
            }
            return [0xB0 | UInt8(channel - 1), UInt8(controller), UInt8(value)]
        }
    }
}
