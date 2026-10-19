import Foundation

enum SendTarget: Equatable {
    case selected
    case destination(id: Int32, name: String)
}

struct CommandSendReceipt: Equatable {
    let date: Date
    let destinationID: Int32
    let destinationName: String
    let command: MIDICommand
    let bytes: [UInt8]
}

enum CommandSendFailure: Error, Equatable, LocalizedError {
    case transportUnavailable(String)
    case invalidCommand(MIDIValidationError)
    case noDestinationSelected
    case destinationUnavailable(String)
    case transportRejected(String)

    var errorDescription: String? {
        switch self {
        case .transportUnavailable(let m), .transportRejected(let m): return m
        case .invalidCommand(let e): return e.errorDescription
        case .noDestinationSelected: return MIDISendError.noDestinationSelected.errorDescription
        case .destinationUnavailable(let n): return MIDISendError.destinationUnavailable(n).errorDescription
        }
    }
}

enum CommandSendResult: Equatable {
    case sent(CommandSendReceipt)
    case failed(CommandSendFailure)

    var receipt: CommandSendReceipt? {
        if case .sent(let r) = self { return r }
        return nil
    }
}

@MainActor
protocol MIDICommandSending: AnyObject {
    func selectedDestination() -> MIDIDestination?
    func send(_ command: MIDICommand, to target: SendTarget) -> CommandSendResult
}
