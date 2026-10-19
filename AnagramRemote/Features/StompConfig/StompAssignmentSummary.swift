import Foundation

/// Plain-language descriptions of stored assignments. Describes configuration only, never device state.
enum StompAssignmentSummary {
    static func typeLabel(_ a: StompAssignment) -> String {
        switch a.action {
        case .unassigned: return "Unassigned"
        case .controlChange: return "Control Change"
        case .programChange: return "Program Change"
        }
    }

    /// e.g. "CC 80 · Ch 2", "PC 5 · Ch 1", "Unassigned".
    static func message(_ a: StompAssignment) -> String {
        switch a.action {
        case .unassigned: return "Unassigned"
        case let .controlChange(ch, cc, _): return "CC \(cc) · Ch \(ch)"
        case let .programChange(ch, pr): return "PC \(pr) · Ch \(ch)"
        }
    }

    static func behavior(_ a: StompAssignment) -> String? {
        guard case let .controlChange(_, _, b) = a.action else {
            if case .programChange = a.action { return "Trigger" }
            return nil
        }
        switch b {
        case let .toggle(.values(on, off)): return "Value toggle \(on)/\(off)"
        case let .toggle(.deviceToggle(t)): return "Device toggle \(t)"
        case let .momentary(p, r): return "Momentary \(p)/\(r)"
        case let .fixedValue(v): return "Fixed \(v)"
        }
    }

    static func isAssigned(_ a: StompAssignment) -> Bool { a.action != .unassigned }
}
