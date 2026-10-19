import Combine
import Foundation
import UIKit

enum StompTileKind: Equatable {
    case unassigned
    case momentaryNotActive
    case blocked(StompBlockReason)
    case ready
}

enum StompBlockReason: Equatable {
    case storageUnavailable
    case invalidAssignment
    case noDestination
}

struct StompTile: Identifiable, Equatable {
    let slot: Int
    let label: String
    let accentID: String
    let summary: String
    let detail: String
    let kind: StompTileKind
    let accessibilityValue: String
    let accessibilityHint: String

    var id: Int { slot }
    var isEnabled: Bool { kind == .ready }
    var accessibilityLabel: String { "\(label), \(summary)" }
}

struct StompFailureNotice: Equatable {
    let slot: Int
    let message: String
}

@MainActor
final class StompPerformanceController: ObservableObject {
    @Published private(set) var failure: StompFailureNotice?
    @Published private(set) var lastSendText: String?

    private let connection: ConnectionViewModel
    private let config: StompConfigModel
    private let executor: StompExecutor
    private let validator: AssignmentValidator
    private var cancellables = Set<AnyCancellable>()
    private var destinationKey: DestinationKey
    private var actionSignature: [StompAction]

    private struct DestinationKey: Equatable {
        let selected: Int32?
        let connected: Bool
    }

    init(connection: ConnectionViewModel, config: StompConfigModel,
         validator: AssignmentValidator = AssignmentValidator(),
         notificationCenter: NotificationCenter = .default) {
        self.connection = connection
        self.config = config
        self.validator = validator
        self.executor = StompExecutor(sender: connection.manager, validator: validator)
        self.destinationKey = Self.key(selected: connection.selectedDestinationID, state: connection.state)
        self.actionSignature = Self.signature(config.profile)

        connection.$selectedDestinationID
            .combineLatest(connection.$state)
            .sink { [weak self] selected, state in
                self?.destinationMayHaveChanged(Self.key(selected: selected, state: state))
            }
            .store(in: &cancellables)

        config.$profile
            .sink { [weak self] profile in self?.profileMayHaveChanged(Self.signature(profile)) }
            .store(in: &cancellables)

        for name in [UIApplication.willResignActiveNotification, UIApplication.didEnterBackgroundNotification] {
            notificationCenter.publisher(for: name)
                .sink { [weak self] _ in self?.leaveActiveState() }
                .store(in: &cancellables)
        }
    }

    func leaveActiveState() {
        executor.resetToggleState()
        objectWillChange.send()
    }

    func tile(slot: Int) -> StompTile {
        let assignment = config.resolved(slot: slot, preset: nil)
        let label = assignment.displayName
        let summary = StompAssignmentSummary.message(assignment)

        func make(_ kind: StompTileKind, detail: String, value: String, hint: String) -> StompTile {
            StompTile(slot: slot, label: label, accentID: assignment.accentID, summary: summary, detail: detail,
                      kind: kind, accessibilityValue: value, accessibilityHint: hint)
        }

        guard assignment.action != .unassigned else {
            return make(.unassigned, detail: "UNASSIGNED", value: "Unassigned", hint: "Assign this stomp in Edit.")
        }
        if case .controlChange(_, _, .momentary) = assignment.action {
            return make(.momentaryNotActive, detail: "MOMENTARY NOT ACTIVE YET", value: "Momentary, not active yet",
                        hint: "Momentary stomps are not available in this version.")
        }
        if !config.canEdit {
            return make(.blocked(.storageUnavailable), detail: "NOT ACTIVE · STORAGE UNAVAILABLE", value: "Not active, controls storage unavailable",
                        hint: "Open Edit to see the storage problem.")
        }
        if !validator.validate(assignment).isAcceptable {
            return make(.blocked(.invalidAssignment), detail: "NOT ACTIVE · CHECK SETTINGS", value: "Not active, settings need attention",
                        hint: "Open Edit to fix this stomp.")
        }
        if !connection.manager.canSend {
            return make(.blocked(.noDestination), detail: "NOT ACTIVE · NO DESTINATION", value: "Not active, no MIDI destination ready",
                        hint: "Select a MIDI destination in Connection settings.")
        }

        let delivery = "Sends to the selected destination. Not confirmed by the Anagram."
        switch assignment.action {
        case .unassigned:
            return make(.unassigned, detail: "UNASSIGNED", value: "Unassigned", hint: "Assign this stomp in Edit.")
        case .programChange(_, let program):
            return make(.ready, detail: "PROGRAM CHANGE TRIGGER", value: "Program Change \(program) trigger",
                        hint: "Double tap to send. \(delivery)")
        case .controlChange(_, _, let behavior):
            switch behavior {
            case .fixedValue(let value):
                return make(.ready, detail: "FIXED VALUE \(value)", value: "Fixed value \(value)",
                            hint: "Double tap to send value \(value). \(delivery)")
            case .toggle(.deviceToggle(let trigger)):
                return make(.ready, detail: "TOGGLE TRIGGER \(trigger)", value: "Device toggle trigger \(trigger)",
                            hint: "Double tap to send trigger \(trigger). The Anagram decides what it does. \(delivery)")
            case .toggle(.values(let on, let off)):
                switch executor.localToggleState(slot: slot, for: assignment.action) {
                case .noneSent:
                    return make(.ready, detail: "LOCAL: NOT SENT YET", value: "Local record: nothing sent yet",
                                hint: "Double tap to send ON, value \(on). \(delivery)")
                case .lastSentOn:
                    return make(.ready, detail: "LOCAL: LAST SENT ON", value: "Local record: last sent ON",
                                hint: "Double tap to send OFF, value \(off). \(delivery)")
                case .lastSentOff:
                    return make(.ready, detail: "LOCAL: LAST SENT OFF", value: "Local record: last sent OFF",
                                hint: "Double tap to send ON, value \(on). \(delivery)")
                }
            case .momentary:
                return make(.momentaryNotActive, detail: "MOMENTARY NOT ACTIVE YET", value: "Momentary, not active yet",
                            hint: "Momentary stomps are not available in this version.")
            }
        }
    }

    func activate(slot: Int) {
        guard tile(slot: slot).isEnabled else { return }
        let assignment = config.resolved(slot: slot, preset: nil)
        switch executor.activate(assignment) {
        case .sent(let receipt):
            failure = nil
            lastSendText = Self.sendText(receipt)
        case .failed(let reason):
            failure = StompFailureNotice(slot: slot, message: "Stomp \(slot) not sent: \(reason.errorDescription ?? "send failed")")
        case .rejected:
            failure = StompFailureNotice(slot: slot, message: "Stomp \(slot) not sent: its settings are invalid. Open Edit to fix them.")
        case .skippedUnassigned, .ignored:
            break
        }
        objectWillChange.send()
    }

    private func destinationMayHaveChanged(_ new: DestinationKey) {
        guard new != destinationKey else { return }
        destinationKey = new
        executor.resetToggleState()
        objectWillChange.send()
    }

    private func profileMayHaveChanged(_ new: [StompAction]) {
        guard new != actionSignature else { return }
        actionSignature = new
        executor.resetToggleState()
        objectWillChange.send()
    }

    private static func key(selected: Int32?, state: ConnectionState) -> DestinationKey {
        if case .connected = state { return DestinationKey(selected: selected, connected: true) }
        return DestinationKey(selected: selected, connected: false)
    }

    private static func signature(_ profile: StompProfile) -> [StompAction] {
        profile.globalSlots.map(\.action)
    }

    private static func sendText(_ receipt: CommandSendReceipt) -> String {
        let record = CommandRecord(date: receipt.date, destinationName: receipt.destinationName,
                                   command: receipt.command, bytes: receipt.bytes)
        return "\(record.summary) — handed to CoreMIDI, not confirmed by the Anagram"
    }
}
