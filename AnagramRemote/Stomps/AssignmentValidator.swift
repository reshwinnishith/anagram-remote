import Foundation

/// Hard validation failures. These can never be acknowledged away.
enum ValidationError: Error, Equatable, LocalizedError {
    case invalidSlot(Int)
    case slotMismatch(expected: Int, actual: Int)
    case invalidChannel(Int)
    case invalidController(Int)
    case invalidValue(name: String, value: Int)
    case invalidProgram(Int)
    case toggleTriggerMustBeNonzero(Int)
    case onOffValuesIdentical(Int)
    case pressReleaseValuesIdentical(Int)
    case unknownAccent(String)
    case nameTooLong(length: Int, max: Int)
    case wrongGlobalSlotCount(Int)
    case invalidOverrideKey(Int)
    case duplicateOverridePreset(Int)
    case duplicateOverrideSlot(preset: Int, slot: Int)

    var errorDescription: String? {
        switch self {
        case .invalidSlot(let s): return "Invalid stomp slot \(s); must be 1–6."
        case .slotMismatch(let e, let a): return "Slot \(a) is in position \(e)."
        case .invalidChannel(let c): return "Invalid MIDI channel \(c); must be 1–16."
        case .invalidController(let c): return "Invalid controller \(c); must be 0–127."
        case .invalidValue(let n, let v): return "Invalid \(n) value \(v); must be 0–127."
        case .invalidProgram(let p): return "Invalid program \(p); must be 1–126."
        case .toggleTriggerMustBeNonzero(let v): return "Toggle trigger value \(v) must be 1–127."
        case .onOffValuesIdentical(let v): return "ON and OFF values are both \(v); they must differ."
        case .pressReleaseValuesIdentical(let v): return "Press and release values are both \(v); they must differ."
        case .unknownAccent(let a): return "Unknown accent '\(a)'."
        case .nameTooLong(let l, let m): return "Name is \(l) characters; maximum is \(m)."
        case .wrongGlobalSlotCount(let n): return "Expected exactly 6 global stomp slots, found \(n)."
        case .invalidOverrideKey(let p): return "Invalid preset override key \(p); must be 1–126."
        case .duplicateOverridePreset(let p): return "Preset \(p) has more than one override entry."
        case .duplicateOverrideSlot(let p, let s): return "Preset \(p) overrides slot \(s) more than once."
        }
    }
}

struct SafetyPolicy: Equatable {
    /// CC numbers the Anagram manual lists as reserved from custom binding assignment: 0, 7, 14–32, 85–87, 89, 102–119
    /// (supplied by the project owner from the manual). These are valid MIDI, so they raise an acknowledgeable
    /// warning, never a hard error. The manual's per-controller defaults / dedicated functions are NOT recorded in
    /// this repo, so none are named or invented here.
    static let manualReservedControllers: Set<Int> =
        Set([0, 7, 89] + Array(14...32) + Array(85...87) + Array(102...119))

    var anagramReservedControllers: Set<Int> = SafetyPolicy.manualReservedControllers
}

struct AssignmentReport: Equatable {
    var errors: [ValidationError] = []
    /// Every warning this assignment triggers.
    var warnings: [SafetyWarning] = []
    /// Triggered warnings the assignment has not acknowledged.
    var unacknowledged: [SafetyWarning] = []

    var isValid: Bool { errors.isEmpty }
    /// Safe to accept and store: no hard errors and every warning acknowledged.
    var isAcceptable: Bool { errors.isEmpty && unacknowledged.isEmpty }
}

enum AssignmentLocation: Equatable {
    case profile
    case global(slot: Int)
    case override(preset: Int, slot: Int)
}

struct ProfileReport: Equatable {
    struct LocatedError: Equatable { let location: AssignmentLocation; let error: ValidationError }
    struct LocatedWarning: Equatable { let location: AssignmentLocation; let warning: SafetyWarning }
    var errors: [LocatedError] = []
    var unacknowledged: [LocatedWarning] = []
    var isAcceptable: Bool { errors.isEmpty && unacknowledged.isEmpty }
}

/// Centralised, pure validation. Never touches MIDI, disk or global state.
struct AssignmentValidator {
    static let slotRange = 1...StompProfile.slotCount
    static let dataRange = 0...127
    static let toggleTriggerRange = 1...127
    static let channelRange = ProgramNumbering.channelRange
    static let programRange = ProgramNumbering.uiRange
    static let presetKeyRange = ProgramNumbering.uiRange

    var policy = SafetyPolicy()

    func validate(_ a: StompAssignment, expectedSlot: Int? = nil) -> AssignmentReport {
        var r = AssignmentReport()
        if !Self.slotRange.contains(a.slot) { r.errors.append(.invalidSlot(a.slot)) }
        else if let e = expectedSlot, e != a.slot { r.errors.append(.slotMismatch(expected: e, actual: a.slot)) }
        if !StompAccent.isValid(a.accentID) { r.errors.append(.unknownAccent(a.accentID)) }
        let n = StompAssignment.normalizedName(a.name).count
        if n > StompAssignment.maxNameLength { r.errors.append(.nameTooLong(length: n, max: StompAssignment.maxNameLength)) }

        switch a.action {
        case .unassigned:
            break
        case let .programChange(channel, program):
            checkChannel(channel, &r)
            if !Self.programRange.contains(program) { r.errors.append(.invalidProgram(program)) }
        case let .controlChange(channel, controller, behavior):
            checkChannel(channel, &r)
            if !Self.dataRange.contains(controller) { r.errors.append(.invalidController(controller)) }
            else { r.warnings.append(contentsOf: warnings(forController: controller)) }
            checkBehavior(behavior, &r)
        }
        r.warnings = Array(Set(r.warnings)).sorted()
        r.unacknowledged = r.warnings.filter { !a.acknowledgedWarnings.contains($0) }
        return r
    }

    func validate(_ p: StompProfile) -> ProfileReport {
        var rep = ProfileReport()
        func absorb(_ r: AssignmentReport, _ loc: AssignmentLocation) {
            rep.errors += r.errors.map { .init(location: loc, error: $0) }
            rep.unacknowledged += r.unacknowledged.map { .init(location: loc, warning: $0) }
        }
        if p.globalSlots.count != StompProfile.slotCount {
            rep.errors.append(.init(location: .profile, error: .wrongGlobalSlotCount(p.globalSlots.count)))
        }
        for (i, a) in p.globalSlots.enumerated() { absorb(validate(a, expectedSlot: i + 1), .global(slot: a.slot)) }

        var seenPresets = Set<Int>()
        for o in p.overrides {
            if !Self.presetKeyRange.contains(o.preset) {
                rep.errors.append(.init(location: .profile, error: .invalidOverrideKey(o.preset)))
            }
            if !seenPresets.insert(o.preset).inserted {
                rep.errors.append(.init(location: .profile, error: .duplicateOverridePreset(o.preset)))
            }
            var seenSlots = Set<Int>()
            for a in o.assignments {
                if !seenSlots.insert(a.slot).inserted {
                    rep.errors.append(.init(location: .profile, error: .duplicateOverrideSlot(preset: o.preset, slot: a.slot)))
                }
                absorb(validate(a), .override(preset: o.preset, slot: a.slot))
            }
        }
        return rep
    }

    // MARK: helpers

    private func checkChannel(_ c: Int, _ r: inout AssignmentReport) {
        if !Self.channelRange.contains(c) { r.errors.append(.invalidChannel(c)) }
    }

    private func checkValue(_ name: String, _ v: Int, _ r: inout AssignmentReport) {
        if !Self.dataRange.contains(v) { r.errors.append(.invalidValue(name: name, value: v)) }
    }

    private func checkBehavior(_ b: CCBehavior, _ r: inout AssignmentReport) {
        switch b {
        case let .toggle(.values(on, off)):
            checkValue("ON", on, &r); checkValue("OFF", off, &r)
            if Self.dataRange.contains(on), on == off { r.errors.append(.onOffValuesIdentical(on)) }
        case let .toggle(.deviceToggle(trigger)):
            if !Self.toggleTriggerRange.contains(trigger) { r.errors.append(.toggleTriggerMustBeNonzero(trigger)) }
        case let .momentary(press, release):
            checkValue("press", press, &r); checkValue("release", release, &r)
            if Self.dataRange.contains(press), press == release { r.errors.append(.pressReleaseValuesIdentical(press)) }
        case let .fixedValue(v):
            checkValue("fixed", v, &r)
        }
    }

    /// At most ONE warning per controller, most specific first, so users never see overlapping or contradictory notices.
    /// CC 0 and 32 are both Bank Select and Anagram-reserved; they get the Bank Select warning, whose text mentions the reservation.
    private func warnings(forController cc: Int) -> [SafetyWarning] {
        if (120...127).contains(cc) { return [.channelModeController] }
        if cc == 0 || cc == 32 { return [.bankSelect] }
        if policy.anagramReservedControllers.contains(cc) { return [.anagramReserved] }
        return []
    }
}
