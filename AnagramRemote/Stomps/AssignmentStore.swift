import Foundation

/// On-disk envelope. `schemaVersion` gates compatibility.
struct StompProfileDocument: Codable, Equatable {
    var schemaVersion: Int
    var profile: StompProfile
}

enum LoadFailure: Error, Equatable {
    case unreadable(String)                 // file exists but is not valid JSON / does not match the schema
    case newerSchema(Int)                   // written by a newer app version
    case unsupportedSchema(Int)             // older than any version this build can migrate
    case failedValidation([String])         // decodes but violates the rules (messages for display)
}

enum LoadOutcome: Equatable {
    /// File existed, was valid and was returned unchanged (apart from normalisation).
    case loaded(StompProfile)
    /// No file existed; safe defaults were written.
    case createdDefaults(StompProfile)
    /// File was unusable. The original was MOVED (never deleted) to `backup`; fresh defaults were written.
    case recoveredWithDefaults(StompProfile, backup: URL, reason: LoadFailure)

    var profile: StompProfile {
        switch self {
        case .loaded(let p), .createdDefaults(let p), .recoveredWithDefaults(let p, _, _): return p
        }
    }
}

enum StoreError: Error, Equatable {
    case invalidProfile([String])
    case backupFailed(String)
    case writeFailed(String)
}

/// Versioned JSON persistence for `StompProfile`. Pure file I/O: it holds no MIDI transport and sends nothing.
final class AssignmentStore {
    static let currentSchemaVersion = 1
    static let fileName = "stomp-assignments.json"
    static let backupPrefix = "stomp-assignments.invalid-"

    let directory: URL
    private let fileManager: FileManager
    private let validator: AssignmentValidator
    private let now: () -> Date

    var fileURL: URL { directory.appendingPathComponent(Self.fileName) }

    /// `directory` is injected so tests use a temporary folder.
    init(directory: URL, validator: AssignmentValidator = AssignmentValidator(),
         fileManager: FileManager = .default, now: @escaping () -> Date = Date.init) {
        self.directory = directory
        self.validator = validator
        self.fileManager = fileManager
        self.now = now
    }

    /// `~/Library/Application Support/AnagramRemote` on device.
    static func defaultDirectory(fileManager: FileManager = .default) throws -> URL {
        try fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("AnagramRemote", isDirectory: true)
    }

    // MARK: Load

    func load() throws -> LoadOutcome {
        try ensureDirectory()
        guard fileManager.fileExists(atPath: fileURL.path) else {
            let defaults = StompProfile.defaults
            try write(defaults)
            return .createdDefaults(defaults)
        }
        let data: Data
        do { data = try Data(contentsOf: fileURL) }
        catch { return try recover(.unreadable(error.localizedDescription)) }

        switch decode(data) {
        case .success(let profile): return .loaded(profile)
        case .failure(let failure): return try recover(failure)
        }
    }

    private func decode(_ data: Data) -> Result<StompProfile, LoadFailure> {
        // Read the version first so a newer/older schema is reported as such instead of as "corrupt".
        struct Header: Decodable { let schemaVersion: Int }
        let version: Int
        do { version = try JSONDecoder().decode(Header.self, from: data).schemaVersion }
        catch { return .failure(.unreadable(String(describing: error))) }

        if version > Self.currentSchemaVersion { return .failure(.newerSchema(version)) }
        guard let migrated = Self.migrate(data, from: version) else { return .failure(.unsupportedSchema(version)) }

        let doc: StompProfileDocument
        do { doc = try JSONDecoder().decode(StompProfileDocument.self, from: migrated) }
        catch { return .failure(.unreadable(String(describing: error))) }

        let profile = doc.profile.normalized()
        let report = validator.validate(profile)
        if !report.isAcceptable { return .failure(.failedValidation(Self.messages(report))) }
        return .success(profile)
    }

    /// Schema migration hook. Each future version adds one `case` that rewrites the JSON to version N+1;
    /// versions below 1 are unsupported (never shipped). Returns nil when no migration path exists.
    static func migrate(_ data: Data, from version: Int) -> Data? {
        switch version {
        case currentSchemaVersion: return data
        default: return nil
        }
    }

    /// Preserved copies of unusable profiles, oldest first. Lets a UI keep surfacing recovery after a relaunch.
    func backupURLs() -> [URL] {
        let names = (try? fileManager.contentsOfDirectory(atPath: directory.path)) ?? []
        return names.filter { $0.hasPrefix(Self.backupPrefix) && $0.hasSuffix(".json") }
            .sorted().map { directory.appendingPathComponent($0) }
    }

    // MARK: Save

    /// Validates, normalises and atomically writes. Never writes an invalid or unacknowledged profile.
    func save(_ profile: StompProfile) throws {
        let normalized = profile.normalized()
        let report = validator.validate(normalized)
        guard report.isAcceptable else { throw StoreError.invalidProfile(Self.messages(report)) }
        try ensureDirectory()
        try write(normalized)
    }

    private func write(_ profile: StompProfile) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            let data = try encoder.encode(StompProfileDocument(schemaVersion: Self.currentSchemaVersion, profile: profile))
            try data.write(to: fileURL, options: .atomic)
        } catch {
            throw StoreError.writeFailed(error.localizedDescription)
        }
    }

    // MARK: Recovery

    /// Preserves the unusable file under a unique name, then writes safe defaults. If the backup cannot be made,
    /// nothing is overwritten and `backupFailed` is thrown.
    private func recover(_ reason: LoadFailure) throws -> LoadOutcome {
        let backup = uniqueBackupURL()
        do { try fileManager.moveItem(at: fileURL, to: backup) }
        catch { throw StoreError.backupFailed(error.localizedDescription) }
        let defaults = StompProfile.defaults
        try write(defaults)
        return .recoveredWithDefaults(defaults, backup: backup, reason: reason)
    }

    private func uniqueBackupURL() -> URL {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        let stamp = f.string(from: now())
        var url = directory.appendingPathComponent("\(Self.backupPrefix)\(stamp).json")
        var n = 1
        while fileManager.fileExists(atPath: url.path) {
            url = directory.appendingPathComponent("\(Self.backupPrefix)\(stamp)-\(n).json"); n += 1
        }
        return url
    }

    private func ensureDirectory() throws {
        do { try fileManager.createDirectory(at: directory, withIntermediateDirectories: true) }
        catch { throw StoreError.writeFailed(error.localizedDescription) }
    }

    private static func messages(_ r: ProfileReport) -> [String] {
        r.errors.map { "\($0.location): \($0.error.errorDescription ?? "\($0.error)")" }
            + r.unacknowledged.map { "\($0.location): unacknowledged warning \($0.warning.rawValue)" }
    }
}
