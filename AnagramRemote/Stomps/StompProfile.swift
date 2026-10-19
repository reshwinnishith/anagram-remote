import Foundation

/// Whole-slot overrides for one preset. `preset` uses M1's 1–126 numbering.
struct PresetOverride: Equatable, Codable {
    var preset: Int
    var assignments: [StompAssignment]
}

/// Six global stomp assignments plus optional whole-slot per-preset overrides.
///
/// Resolution is a pure function of (preset, slot): an override for that preset and slot wins, even when
/// it is `.unassigned`; otherwise the global slot applies. The app never infers the hardware's active
/// preset: callers pass the preset (e.g. the last one the app sent) or `nil` for global-only.
struct StompProfile: Equatable, Codable {
    static let slotCount = 6

    var globalSlots: [StompAssignment]
    var overrides: [PresetOverride] = []

    static var defaults: StompProfile {
        StompProfile(globalSlots: (1...slotCount).map { StompAssignment.unassigned(slot: $0) })
    }

    // MARK: Resolution

    func resolved(slot: Int, preset: Int?) -> StompAssignment? {
        guard (1...Self.slotCount).contains(slot), globalSlots.indices.contains(slot - 1) else { return nil }
        if let preset, let o = override(preset: preset, slot: slot) { return o }
        return globalSlots[slot - 1]
    }

    func resolvedSlots(preset: Int?) -> [StompAssignment] {
        (1...Self.slotCount).compactMap { resolved(slot: $0, preset: preset) }
    }

    func override(preset: Int, slot: Int) -> StompAssignment? {
        overrides.first(where: { $0.preset == preset })?.assignments.first(where: { $0.slot == slot })
    }

    func hasOverride(preset: Int, slot: Int) -> Bool { override(preset: preset, slot: slot) != nil }

    // MARK: Mutation (structure only; run `AssignmentValidator` before persisting)

    /// Replaces the global assignment for `assignment.slot`. Returns false if the slot is out of range.
    @discardableResult
    mutating func setGlobal(_ assignment: StompAssignment) -> Bool {
        guard (1...Self.slotCount).contains(assignment.slot), globalSlots.indices.contains(assignment.slot - 1) else { return false }
        globalSlots[assignment.slot - 1] = assignment
        return true
    }

    /// Sets a whole-slot override. An `.unassigned` assignment is a valid explicit override.
    @discardableResult
    mutating func setOverride(preset: Int, _ assignment: StompAssignment) -> Bool {
        guard (1...Self.slotCount).contains(assignment.slot) else { return false }
        if let i = overrides.firstIndex(where: { $0.preset == preset }) {
            if let j = overrides[i].assignments.firstIndex(where: { $0.slot == assignment.slot }) {
                overrides[i].assignments[j] = assignment
            } else {
                overrides[i].assignments.append(assignment)
            }
        } else {
            overrides.append(PresetOverride(preset: preset, assignments: [assignment]))
        }
        sortOverrides()
        return true
    }

    /// Removes the override so the slot follows the global assignment again.
    mutating func resetToGlobal(preset: Int, slot: Int) {
        guard let i = overrides.firstIndex(where: { $0.preset == preset }) else { return }
        overrides[i].assignments.removeAll { $0.slot == slot }
        if overrides[i].assignments.isEmpty { overrides.remove(at: i) }
    }

    mutating func resetAllToGlobal(preset: Int) { overrides.removeAll { $0.preset == preset } }

    /// Deterministic form for storage and comparison: names/acks normalised, overrides sorted, empty overrides dropped.
    func normalized() -> StompProfile {
        var p = self
        p.globalSlots = globalSlots.map { $0.normalized() }
        p.overrides = overrides
            .map { PresetOverride(preset: $0.preset, assignments: $0.assignments.map { $0.normalized() }) }
            .filter { !$0.assignments.isEmpty }
        p.sortOverrides()
        return p
    }

    private mutating func sortOverrides() {
        overrides.sort { $0.preset < $1.preset }
        for i in overrides.indices { overrides[i].assignments.sort { $0.slot < $1.slot } }
    }
}
