import Foundation

/// Diagnostic record of one send attempt handed to the MIDI transport.
/// "Accepted" means the transport accepted the bytes; it is NOT confirmation
/// that the Anagram received or acted on them.
struct TransmissionRecord: Equatable {
    let date: Date
    let destinationName: String
    let channel: Int
    let program: Int
    let bytes: [UInt8]

    var hexString: String {
        bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
    }

    var summary: String {
        "Program Change \(program) on ch \(channel) → [\(hexString)] to \(destinationName)"
    }
}
