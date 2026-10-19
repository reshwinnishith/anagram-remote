import Foundation
import SwiftUI

enum StatusLevel: Equatable { case ok, warning, error }

enum PresetLabel {
    /// M1 numbering: program 1 = preset 01A, program 2 = 01B. Provisional until hardware-verified.
    static func text(forProgram program: Int) -> String {
        switch program {
        case 1: return "01A"
        case 2: return "01B"
        default: return "P\(program)"
        }
    }
}

/// The two M1 direct-preset controls, kept on the Performance screen.
struct PresetShortcut: Identifiable, Equatable {
    let program: Int
    var id: Int { program }
    var label: String { PresetLabel.text(forProgram: program) }
    static let all = [PresetShortcut(program: 1), PresetShortcut(program: 2)]
}

/// Batch A: scenes are placeholders. No MIDI mapping exists and none is sent.
struct SceneSlotPresentation: Identifiable, Equatable {
    let letter: String
    var id: String { letter }
    var isEnabled: Bool { false }
    var statusText: String { "NOT CONFIGURED" }
    static let all = ["A", "B", "C"].map(SceneSlotPresentation.init(letter:))
}

enum StompLocalState: Equatable { case unassigned }          // later: off/on/held
enum StompConfirmedState: Equatable { case notAvailable }    // later: confirmed by device input

/// Batch A: stomps are placeholders. Label/accent/state fields are reserved for later batches.
struct StompPresentation: Identifiable {
    let index: Int
    var id: Int { index }
    var title: String { "Stomp \(index)" }
    var customLabel: String? = nil
    var accent: Color? = nil
    var localState: StompLocalState = .unassigned
    var confirmedState: StompConfirmedState = .notAvailable
    /// Set when a saved assignment exists (C2). Display only: stomps stay inert and send nothing.
    var assignedSummary: String? = nil
    var isConfigured: Bool { assignedSummary != nil }
    var isEnabled: Bool { false }
    var statusText: String { assignedSummary ?? "UNASSIGNED" }
    static let all = (1...PerformanceLayout.stompCount).map { StompPresentation(index: $0) }

    /// Display model for a saved global assignment. No state (ON/OFF, confirmed) is implied.
    init(assignment a: StompAssignment) {
        index = a.slot
        customLabel = a.name.isEmpty ? nil : a.name
        accent = StompAccent.color(for: a.accentID)
        assignedSummary = StompAssignmentSummary.isAssigned(a) ? StompAssignmentSummary.message(a) : nil
    }
    init(index: Int) { self.index = index }
}

enum PerformanceLayout {
    static let stompColumns = 3
    static let stompRows = 2
    static var stompCount: Int { stompColumns * stompRows }
}

struct PresetReadout: Equatable {
    let label: String
    let subtitle: String
}

/// Maps ConnectionViewModel state to what the Performance screen shows. Pure; sends nothing.
struct PerformancePresentation {
    let connectionLabel: String
    let connectionLevel: StatusLevel
    let destinationLabel: String
    let preset: PresetReadout
    let lastSentText: String?
    let errorText: String?
    let canSend: Bool

    @MainActor
    init(vm: ConnectionViewModel) {
        canSend = vm.canSend
        switch vm.state {
        case .connected(let name):
            connectionLabel = "Destination ready"; connectionLevel = .ok; destinationLabel = name
        case .disconnected(let name):
            connectionLabel = "Disconnected"; connectionLevel = .error; destinationLabel = name
        case .noDestinationSelected:
            connectionLabel = "No destination selected"; connectionLevel = .warning; destinationLabel = "—"
        case .noDestinationsAvailable:
            connectionLabel = "No MIDI devices found"; connectionLevel = .warning; destinationLabel = "—"
        case .transportUnavailable:
            connectionLabel = "MIDI unavailable"; connectionLevel = .error; destinationLabel = "—"
        }
        if let sent = vm.lastTransmission {
            preset = PresetReadout(label: PresetLabel.text(forProgram: sent.program),
                                   subtitle: "Last sent · not confirmed by device")
            lastSentText = sent.summary + " — handed to CoreMIDI, not device-confirmed"
        } else {
            preset = PresetReadout(label: "—", subtitle: "Unknown · no preset sent yet")
            lastSentText = nil
        }
        if let e = vm.lastError {
            errorText = e
        } else if case .transportUnavailable(let message) = vm.state {
            errorText = message
        } else {
            errorText = nil
        }
    }
}
