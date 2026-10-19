import Foundation

/// Editor fields a message can be attached to.
enum DraftField: Hashable {
    case name, accent, channel, controller, onValue, offValue, triggerValue, pressValue, releaseValue, fixedValue, program, general
}

/// Editable, possibly-incomplete copy of one stomp assignment. Pure value type: no persistence, no MIDI.
/// Numeric fields are optional so a half-typed field is "missing" rather than a wrong number.
/// All rules come from `AssignmentValidator`; this type only maps results onto fields.
struct StompEditorDraft: Equatable {
    enum Scope: Equatable { case global, preset(Int) }
    enum Kind: CaseIterable { case unassigned, controlChange, programChange }
    enum CCStyle: CaseIterable { case valueToggle, deviceToggle, momentary, fixedValue }

    var slot: Int
    var scope: Scope
    var name: String
    var accentID: String
    var kind: Kind
    var channel: Int?
    var style: CCStyle
    var controller: Int?
    var onValue: Int?
    var offValue: Int?
    var triggerValue: Int?
    var pressValue: Int?
    var releaseValue: Int?
    var fixedValue: Int?
    var program: Int?
    var acknowledged: Set<SafetyWarning>

    /// Starting values for newly chosen CC behaviours. These are editor conveniences, not claims about the Anagram.
    static let suggestedOn = 127, suggestedOff = 0

    init(assignment a: StompAssignment, scope: Scope) {
        slot = a.slot; self.scope = scope; name = a.name; accentID = a.accentID
        acknowledged = Set(a.acknowledgedWarnings)
        kind = .unassigned; channel = 1; style = .valueToggle; controller = nil
        onValue = Self.suggestedOn; offValue = Self.suggestedOff; triggerValue = Self.suggestedOn
        pressValue = Self.suggestedOn; releaseValue = Self.suggestedOff; fixedValue = Self.suggestedOn
        program = nil
        switch a.action {
        case .unassigned: break
        case let .programChange(ch, pr): kind = .programChange; channel = ch; program = pr
        case let .controlChange(ch, cc, behavior):
            kind = .controlChange; channel = ch; controller = cc
            switch behavior {
            case let .toggle(.values(on, off)): style = .valueToggle; onValue = on; offValue = off
            case let .toggle(.deviceToggle(t)): style = .deviceToggle; triggerValue = t
            case let .momentary(p, r): style = .momentary; pressValue = p; releaseValue = r
            case let .fixedValue(v): style = .fixedValue; fixedValue = v
            }
        }
    }

    // MARK: Building

    /// Fields required for the current kind/style that are empty.
    var missingFields: [DraftField] {
        var m: [DraftField] = []
        switch kind {
        case .unassigned: break
        case .programChange:
            if channel == nil { m.append(.channel) }
            if program == nil { m.append(.program) }
        case .controlChange:
            if channel == nil { m.append(.channel) }
            if controller == nil { m.append(.controller) }
            switch style {
            case .valueToggle: if onValue == nil { m.append(.onValue) }; if offValue == nil { m.append(.offValue) }
            case .deviceToggle: if triggerValue == nil { m.append(.triggerValue) }
            case .momentary: if pressValue == nil { m.append(.pressValue) }; if releaseValue == nil { m.append(.releaseValue) }
            case .fixedValue: if fixedValue == nil { m.append(.fixedValue) }
            }
        }
        return m
    }

    /// The assignment this draft describes, or nil while required fields are empty.
    func buildAssignment() -> StompAssignment? {
        guard missingFields.isEmpty else { return nil }
        return placeholderFilledAssignment()
    }

    /// Placeholder-filled form used only to validate the fields that ARE present. Never saved.
    private func placeholderFilledAssignment() -> StompAssignment {
        let action: StompAction
        let ch = channel ?? 1
        switch kind {
        case .unassigned: action = .unassigned
        case .programChange: action = .programChange(channel: ch, program: program ?? 1)
        case .controlChange:
            let behavior: CCBehavior
            switch style {
            case .valueToggle: behavior = .toggle(.values(on: onValue ?? 127, off: offValue ?? 0))
            case .deviceToggle: behavior = .toggle(.deviceToggle(trigger: triggerValue ?? 127))
            case .momentary: behavior = .momentary(press: pressValue ?? 127, release: releaseValue ?? 0)
            case .fixedValue: behavior = .fixedValue(fixedValue ?? 127)
            }
            action = .controlChange(channel: ch, controller: controller ?? 80, behavior: behavior)
        }
        return StompAssignment(slot: slot, name: StompAssignment.normalizedName(name), accentID: accentID,
                               action: action, acknowledgedWarnings: Array(acknowledged))
    }

    // MARK: Evaluation

    func evaluate(using validator: AssignmentValidator = AssignmentValidator()) -> DraftReport {
        let missing = missingFields
        let report = validator.validate(placeholderFilledAssignment(), expectedSlot: slot)
        var fieldErrors: [DraftField: [String]] = [:]
        for e in report.errors { fieldErrors[Self.field(for: e), default: []].append(e.errorDescription ?? "\(e)") }
        for f in missing { fieldErrors[f, default: []].append("Enter a value.") }
        // A missing controller means no controller warning can be judged yet.
        let warnings = missing.contains(.controller) ? [] : report.warnings
        return DraftReport(fieldErrors: fieldErrors, missing: missing, warnings: warnings,
                           unacknowledged: warnings.filter { !acknowledged.contains($0) })
    }

    static func field(for error: ValidationError) -> DraftField {
        switch error {
        case .invalidChannel: return .channel
        case .invalidController: return .controller
        case .invalidProgram: return .program
        case .toggleTriggerMustBeNonzero: return .triggerValue
        case .onOffValuesIdentical: return .offValue
        case .pressReleaseValuesIdentical: return .releaseValue
        case .unknownAccent: return .accent
        case .nameTooLong: return .name
        case .invalidValue(let name, _):
            switch name {
            case "ON": return .onValue
            case "OFF": return .offValue
            case "press": return .pressValue
            case "release": return .releaseValue
            case "fixed": return .fixedValue
            default: return .general
            }
        default: return .general
        }
    }

    /// Acknowledgements are kept only for warnings the final assignment actually triggers.
    func finalAssignment(using validator: AssignmentValidator = AssignmentValidator()) -> StompAssignment? {
        guard var a = buildAssignment() else { return nil }
        let triggered = validator.validate(a, expectedSlot: slot).warnings
        a.acknowledgedWarnings = triggered.filter { acknowledged.contains($0) }.sorted()
        return a
    }
}

struct DraftReport: Equatable {
    var fieldErrors: [DraftField: [String]]
    var missing: [DraftField]
    var warnings: [SafetyWarning]
    var unacknowledged: [SafetyWarning]

    /// Safe to save: no field errors, nothing missing, every warning acknowledged.
    var canSave: Bool { fieldErrors.isEmpty && missing.isEmpty && unacknowledged.isEmpty }
    func errors(for field: DraftField) -> [String] { fieldErrors[field] ?? [] }
}
