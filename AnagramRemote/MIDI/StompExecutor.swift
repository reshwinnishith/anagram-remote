import Foundation

enum ExecutionRejection: Equatable {
    case invalidAssignment([ValidationError])
    case unacknowledgedWarnings([SafetyWarning])
}

enum ExecutionIgnoredReason: Equatable {
    case alreadyPressed
    case notPressed
}

enum ExecutionOutcome: Equatable {
    case sent(CommandSendReceipt)
    case skippedUnassigned
    case rejected(ExecutionRejection)
    case failed(CommandSendFailure)
    case ignored(ExecutionIgnoredReason)

    var receipt: CommandSendReceipt? {
        if case .sent(let r) = self { return r }
        return nil
    }
}

enum StompLocalToggleState: Equatable {
    case noneSent
    case lastSentOn
    case lastSentOff
}

@MainActor
final class StompExecutor {
    private struct ToggleRuntime {
        let action: StompAction
        var lastSentOn: Bool
    }

    private struct PressedMomentary {
        let channel: Int
        let controller: Int
        let releaseValue: Int
        let destination: SendTarget
    }

    private let sender: MIDICommandSending
    private let validator: AssignmentValidator
    private var toggles: [Int: ToggleRuntime] = [:]
    private var pressed: [Int: PressedMomentary] = [:]

    init(sender: MIDICommandSending, validator: AssignmentValidator = AssignmentValidator()) {
        self.sender = sender
        self.validator = validator
    }

    var pressedSlots: Set<Int> { Set(pressed.keys) }

    func localToggleState(slot: Int, for action: StompAction) -> StompLocalToggleState {
        guard let runtime = toggles[slot], runtime.action == action else { return .noneSent }
        return runtime.lastSentOn ? .lastSentOn : .lastSentOff
    }

    func resetRuntimeState() {
        toggles.removeAll()
        pressed.removeAll()
    }

    @discardableResult
    func activate(_ assignment: StompAssignment) -> ExecutionOutcome {
        if let runtime = toggles[assignment.slot], runtime.action != assignment.action {
            toggles.removeValue(forKey: assignment.slot)
        }
        if assignment.action == .unassigned { return .skippedUnassigned }
        if let rejection = rejection(for: assignment) { return .rejected(rejection) }
        let slot = assignment.slot

        switch assignment.action {
        case .unassigned:
            return .skippedUnassigned

        case let .programChange(channel, program):
            return outcome(sender.send(.programChange(channel: channel, program: program), to: .selected))

        case let .controlChange(channel, controller, behavior):
            switch behavior {
            case .fixedValue(let value):
                return outcome(sender.send(.controlChange(channel: channel, controller: controller, value: value), to: .selected))

            case .toggle(.deviceToggle(let trigger)):
                return outcome(sender.send(.controlChange(channel: channel, controller: controller, value: trigger), to: .selected))

            case .toggle(.values(let on, let off)):
                let wasOn = (toggles[slot].flatMap { $0.action == assignment.action ? $0.lastSentOn : nil }) ?? false
                let value = wasOn ? off : on
                let result = sender.send(.controlChange(channel: channel, controller: controller, value: value), to: .selected)
                if case .sent = result { toggles[slot] = ToggleRuntime(action: assignment.action, lastSentOn: !wasOn) }
                return outcome(result)

            case .momentary(let press, let release):
                if pressed[slot] != nil { return .ignored(.alreadyPressed) }
                guard let destination = sender.selectedDestination() else {
                    return outcome(sender.send(.controlChange(channel: channel, controller: controller, value: press), to: .selected))
                }
                let target = SendTarget.destination(id: destination.id, name: destination.name)
                let result = sender.send(.controlChange(channel: channel, controller: controller, value: press), to: target)
                if case .sent = result {
                    pressed[slot] = PressedMomentary(channel: channel, controller: controller, releaseValue: release, destination: target)
                }
                return outcome(result)
            }
        }
    }

    @discardableResult
    func release(slot: Int) -> ExecutionOutcome {
        guard let held = pressed.removeValue(forKey: slot) else { return .ignored(.notPressed) }
        return outcome(sender.send(.controlChange(channel: held.channel, controller: held.controller, value: held.releaseValue),
                                   to: held.destination))
    }

    private func rejection(for assignment: StompAssignment) -> ExecutionRejection? {
        let report = validator.validate(assignment)
        if !report.errors.isEmpty { return .invalidAssignment(report.errors) }
        if !report.unacknowledged.isEmpty { return .unacknowledgedWarnings(report.unacknowledged) }
        return nil
    }

    private func outcome(_ result: CommandSendResult) -> ExecutionOutcome {
        switch result {
        case .sent(let receipt): return .sent(receipt)
        case .failed(let failure): return .failed(failure)
        }
    }
}
