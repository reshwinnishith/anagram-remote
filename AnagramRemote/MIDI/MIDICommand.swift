import Foundation

enum MIDIValidationError: Error, Equatable, LocalizedError {
    case invalidChannel(Int)
    case invalidProgram(Int)

    var errorDescription: String? {
        switch self {
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

enum MIDICommand: Equatable {
    /// `channel` 1–16, `program` 1–126 (one-based). No Bank Select in M1.
    case programChange(channel: Int, program: Int)

    /// Raw MIDI bytes. Program Change = 0xC0 | (channel − 1), then one data byte.
    func bytes() throws -> [UInt8] {
        switch self {
        case let .programChange(channel, program):
            guard ProgramNumbering.channelRange.contains(channel) else {
                throw MIDIValidationError.invalidChannel(channel)
            }
            let data = try ProgramNumbering.dataByte(forProgram: program)
            return [0xC0 | UInt8(channel - 1), data]
        }
    }
}
