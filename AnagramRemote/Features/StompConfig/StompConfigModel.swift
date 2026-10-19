import Foundation

/// What the config UI needs from persistence. `AssignmentStore` is the production implementation;
/// tests inject fakes (failing saves, throwing loads).
protocol AssignmentPersisting {
    func load() throws -> LoadOutcome
    func save(_ profile: StompProfile) throws
    func backupURLs() -> [URL]
}
extension AssignmentStore: AssignmentPersisting {}

/// Shown prominently until the user explicitly dismisses it.
struct RecoveryNotice: Equatable {
    let backup: URL
    let reason: LoadFailure

    var reasonText: String {
        switch reason {
        case .unreadable: return "The saved controls file was damaged or unreadable."
        case .newerSchema(let v): return "The saved controls file was written by a newer version of the app (format \(v))."
        case .unsupportedSchema(let v): return "The saved controls file uses an unsupported format (\(v))."
        case .failedValidation(let m): return "The saved controls file contained invalid settings (\(m.count) problem\(m.count == 1 ? "" : "s"))."
        }
    }
}

enum SaveOutcome: Equatable {
    case saved
    case failed(String)
}

/// Owns the persisted profile for the UI. Persistence happens here, never in view bodies.
/// It only ever saves a complete, validated draft, and it updates `profile` only after the store confirms the write.
@MainActor
final class StompConfigModel: ObservableObject {
    @Published private(set) var profile = StompProfile.defaults
    @Published private(set) var recovery: RecoveryNotice?
    /// Set when the store could not be read safely. Editing is disabled so defaults can never overwrite unread data.
    @Published private(set) var storageProblem: String?
    @Published private(set) var lastSaveError: String?
    @Published private(set) var lastSavedAt: Date?
    @Published private(set) var backups: [URL] = []

    private let store: AssignmentPersisting
    private let validator: AssignmentValidator
    private let now: () -> Date

    var canEdit: Bool { storageProblem == nil }

    init(store: AssignmentPersisting, validator: AssignmentValidator = AssignmentValidator(), now: @escaping () -> Date = Date.init) {
        self.store = store; self.validator = validator; self.now = now
        reload()
    }

    /// Production wiring. Simulator builds (never device builds) may redirect storage with `ANAGRAM_STOMP_DIR`
    /// so demos and screenshots never touch a real configuration.
    static func live() -> StompConfigModel {
        #if targetEnvironment(simulator)
        if let path = ProcessInfo.processInfo.environment["ANAGRAM_STOMP_DIR"], !path.isEmpty {
            return StompConfigModel(store: AssignmentStore(directory: URL(fileURLWithPath: path, isDirectory: true)))
        }
        #endif
        do {
            return StompConfigModel(store: AssignmentStore(directory: try AssignmentStore.defaultDirectory()))
        } catch {
            return StompConfigModel(store: UnavailableStore(message: error.localizedDescription))
        }
    }

    // MARK: Loading

    func reload() {
        do {
            switch try store.load() {
            case .loaded(let p), .createdDefaults(let p):
                profile = p; storageProblem = nil
            case let .recoveredWithDefaults(p, backup, reason):
                profile = p; storageProblem = nil
                recovery = RecoveryNotice(backup: backup, reason: reason)
            }
        } catch {
            storageProblem = Self.describe(error)
            profile = .defaults
        }
        backups = store.backupURLs()
    }

    func dismissRecovery() { recovery = nil }

    // MARK: Reading

    func resolved(slot: Int, preset: Int?) -> StompAssignment { profile.resolved(slot: slot, preset: preset) ?? .unassigned(slot: slot) }
    func isOverride(slot: Int, preset: Int) -> Bool { profile.hasOverride(preset: preset, slot: slot) }

    func draft(slot: Int, scope: StompEditorDraft.Scope) -> StompEditorDraft {
        switch scope {
        case .global: return StompEditorDraft(assignment: resolved(slot: slot, preset: nil), scope: scope)
        case .preset(let p): return StompEditorDraft(assignment: resolved(slot: slot, preset: p), scope: scope)
        }
    }

    // MARK: Writing

    /// Saves a draft. Refuses anything incomplete or invalid; `profile` changes only if the write succeeds.
    @discardableResult
    func save(_ draft: StompEditorDraft) -> SaveOutcome {
        guard canEdit else { return fail("Controls storage is unavailable, so nothing was saved.") }
        guard draft.evaluate(using: validator).canSave, let assignment = draft.finalAssignment(using: validator) else {
            return fail("This stomp has errors or missing values, so nothing was saved.")
        }
        var next = profile
        switch draft.scope {
        case .global: next.setGlobal(assignment)
        case .preset(let p): next.setOverride(preset: p, assignment)
        }
        return commit(next)
    }

    @discardableResult
    func resetToGlobal(preset: Int, slot: Int) -> SaveOutcome {
        guard canEdit else { return fail("Controls storage is unavailable, so nothing was changed.") }
        var next = profile
        next.resetToGlobal(preset: preset, slot: slot)
        return commit(next)
    }

    private func commit(_ next: StompProfile) -> SaveOutcome {
        do {
            try store.save(next)
            profile = next.normalized()
            lastSaveError = nil
            lastSavedAt = now()
            backups = store.backupURLs()
            return .saved
        } catch {
            return fail(Self.describe(error))
        }
    }

    private func fail(_ message: String) -> SaveOutcome {
        lastSaveError = message
        return .failed(message)
    }

    static func describe(_ error: Error) -> String {
        switch error {
        case StoreError.invalidProfile(let m): return "Invalid settings: \(m.joined(separator: "; "))"
        case StoreError.backupFailed(let m): return "Could not preserve the existing controls file (\(m)); it was left untouched."
        case StoreError.writeFailed(let m): return "Could not write the controls file: \(m)"
        default: return error.localizedDescription
        }
    }
}

/// Used only when Application Support cannot be located at all.
private struct UnavailableStore: AssignmentPersisting {
    let message: String
    func load() throws -> LoadOutcome { throw StoreError.writeFailed(message) }
    func save(_ profile: StompProfile) throws { throw StoreError.writeFailed(message) }
    func backupURLs() -> [URL] { [] }
}
