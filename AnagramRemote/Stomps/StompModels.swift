import Foundation

/// Stomp accent palette identifiers. Order mirrors `Theme.stompAccents` so a UI can map id → colour later.
/// Kept as plain strings (not an enum) in stored data so an unknown id decodes and is then reported by the validator.
enum StompAccent {
    static let ids = ["blue", "violet", "pink", "orange", "yellow", "green", "teal", "silver"]
    static func isValid(_ id: String) -> Bool { ids.contains(id) }
    static func defaultID(forSlot slot: Int) -> String { ids[(max(slot, 1) - 1) % ids.count] }
}

/// How a Control Change toggle is interpreted.
/// The Anagram's toggle interpretation is hardware-dependent and unverified, so both are modelled explicitly.
enum ToggleMode: Equatable {
    /// The app tracks local ON/OFF and alternately sends `on` / `off`. Any 0–127 values, `on != off`.
    case values(on: Int, off: Int)
    /// The app sends the same nonzero `trigger` on every press and the device flips its own state.
    case deviceToggle(trigger: Int)
}

enum CCBehavior: Equatable {
    case toggle(ToggleMode)
    /// Sends `press` on touch-down and `release` on touch-up.
    case momentary(press: Int, release: Int)
    /// Sends one fixed value on every press.
    case fixedValue(Int)
}

enum StompAction: Equatable {
    case unassigned
    /// `channel` 1–16, `controller` 0–127.
    case controlChange(channel: Int, controller: Int, behavior: CCBehavior)
    /// `channel` 1–16, `program` in M1's user-facing 1–126 numbering. Trigger-only.
    case programChange(channel: Int, program: Int)
}

/// Advanced-safety categories that must be explicitly acknowledged before an assignment is accepted.
enum SafetyWarning: String, Codable, CaseIterable, Comparable {
    case channelModeController   // CC 120–127
    case bankSelect              // CC 0 and 32
    case anagramReserved         // only if a documented reserved list is configured in the validator policy
    static func < (a: SafetyWarning, b: SafetyWarning) -> Bool { a.rawValue < b.rawValue }

    var title: String {
        switch self {
        case .channelModeController: return "Channel-mode message"
        case .bankSelect: return "Bank Select"
        case .anagramReserved: return "Reserved by the Anagram"
        }
    }

    /// User-facing explanation. Shared by every screen so wording is not duplicated in views.
    var explanation: String {
        switch self {
        case .channelModeController:
            return "CC 120–127 are MIDI channel-mode messages (such as All Notes Off or Reset All Controllers). They can silence or reset devices on this channel. Assign one only if you intend that."
        case .bankSelect:
            return "CC 0 and 32 are Bank Select, which changes the bank used by the next Program Change. The Anagram manual also lists them as reserved from custom binding assignment. Advanced use only."
        case .anagramReserved:
            return "The Anagram manual lists this controller as reserved from custom binding assignment. It is still a valid MIDI message and can be sent, but it cannot trigger a custom binding and may be tied to a dedicated function or default on the Anagram. This app does not know which."
        }
    }
}

/// One stomp's full configuration. Also used as a whole-slot preset override.
struct StompAssignment: Equatable, Codable {
    var slot: Int
    var name: String
    var accentID: String
    var action: StompAction
    /// Warnings the user has explicitly accepted for this assignment (stored sorted, unique).
    var acknowledgedWarnings: [SafetyWarning] = []

    static let maxNameLength = 16

    static func unassigned(slot: Int) -> StompAssignment {
        StompAssignment(slot: slot, name: "", accentID: StompAccent.defaultID(forSlot: slot), action: .unassigned)
    }

    /// Name shown on the stomp; falls back to "Stomp N" when no custom name is set.
    var displayName: String { name.isEmpty ? "Stomp \(slot)" : name }

    /// Trims, collapses internal whitespace runs to one space.
    static func normalizedName(_ raw: String) -> String {
        raw.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).joined(separator: " ")
    }

    func normalized() -> StompAssignment {
        var copy = self
        copy.name = Self.normalizedName(name)
        copy.acknowledgedWarnings = Array(Set(acknowledgedWarnings)).sorted()
        return copy
    }
}

// MARK: - Codable (explicit "kind" discriminators: stable on disk, independent of compiler synthesis)

extension CCBehavior: Codable {
    private enum Key: String, CodingKey { case kind, on, off, trigger, press, release, value }
    private enum Kind: String, Codable { case toggleValues, toggleDevice, momentary, fixed }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        switch try c.decode(Kind.self, forKey: .kind) {
        case .toggleValues: self = .toggle(.values(on: try c.decode(Int.self, forKey: .on), off: try c.decode(Int.self, forKey: .off)))
        case .toggleDevice: self = .toggle(.deviceToggle(trigger: try c.decode(Int.self, forKey: .trigger)))
        case .momentary: self = .momentary(press: try c.decode(Int.self, forKey: .press), release: try c.decode(Int.self, forKey: .release))
        case .fixed: self = .fixedValue(try c.decode(Int.self, forKey: .value))
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Key.self)
        switch self {
        case let .toggle(.values(on, off)):
            try c.encode(Kind.toggleValues, forKey: .kind); try c.encode(on, forKey: .on); try c.encode(off, forKey: .off)
        case let .toggle(.deviceToggle(trigger)):
            try c.encode(Kind.toggleDevice, forKey: .kind); try c.encode(trigger, forKey: .trigger)
        case let .momentary(press, release):
            try c.encode(Kind.momentary, forKey: .kind); try c.encode(press, forKey: .press); try c.encode(release, forKey: .release)
        case let .fixedValue(value):
            try c.encode(Kind.fixed, forKey: .kind); try c.encode(value, forKey: .value)
        }
    }
}

extension StompAction: Codable {
    private enum Key: String, CodingKey { case kind, channel, controller, behavior, program }
    private enum Kind: String, Codable { case unassigned, controlChange, programChange }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        switch try c.decode(Kind.self, forKey: .kind) {
        case .unassigned:
            self = .unassigned
        case .controlChange:
            self = .controlChange(channel: try c.decode(Int.self, forKey: .channel),
                                  controller: try c.decode(Int.self, forKey: .controller),
                                  behavior: try c.decode(CCBehavior.self, forKey: .behavior))
        case .programChange:
            self = .programChange(channel: try c.decode(Int.self, forKey: .channel),
                                  program: try c.decode(Int.self, forKey: .program))
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Key.self)
        switch self {
        case .unassigned:
            try c.encode(Kind.unassigned, forKey: .kind)
        case let .controlChange(channel, controller, behavior):
            try c.encode(Kind.controlChange, forKey: .kind)
            try c.encode(channel, forKey: .channel); try c.encode(controller, forKey: .controller)
            try c.encode(behavior, forKey: .behavior)
        case let .programChange(channel, program):
            try c.encode(Kind.programChange, forKey: .kind)
            try c.encode(channel, forKey: .channel); try c.encode(program, forKey: .program)
        }
    }
}
