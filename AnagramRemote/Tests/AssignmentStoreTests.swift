import XCTest
@testable import AnagramRemote

final class AssignmentStoreTests: XCTestCase {
    private var dir: URL!
    private var fixedNow = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("AnagramStoreTests-\(UUID().uuidString)", isDirectory: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    private func makeStore() -> AssignmentStore { AssignmentStore(directory: dir, now: { self.fixedNow }) }
    private func files() throws -> [String] { try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted() }
    private func write(_ s: String) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(s.utf8).write(to: dir.appendingPathComponent(AssignmentStore.fileName))
    }
    private func sample() -> StompProfile {
        var p = StompProfile.defaults
        p.setGlobal(StompAssignment(slot: 1, name: "Drive", accentID: "orange",
                                    action: .controlChange(channel: 2, controller: 80, behavior: .toggle(.values(on: 127, off: 0)))))
        p.setGlobal(StompAssignment(slot: 2, name: "Delay", accentID: "violet",
                                    action: .controlChange(channel: 2, controller: 81, behavior: .toggle(.deviceToggle(trigger: 64)))))
        p.setOverride(preset: 12, .unassigned(slot: 1))
        return p
    }

    // Missing / defaults
    func testMissingFileCreatesSafeDefaults() throws {
        let out = try makeStore().load()
        XCTAssertEqual(out, .createdDefaults(StompProfile.defaults))
        XCTAssertEqual(try files(), [AssignmentStore.fileName])
        XCTAssertEqual(try makeStore().load(), .loaded(StompProfile.defaults), "created file is itself loadable")
    }

    func testMissingDirectoryIsCreated() throws {
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.path))
        _ = try makeStore().load()
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.path))
    }

    // Round trip
    func testSaveThenLoadRoundTrips() throws {
        let s = makeStore(); try s.save(sample())
        XCTAssertEqual(try makeStore().load(), .loaded(sample().normalized()))
    }

    func testFileIsVersionedJSON() throws {
        let s = makeStore(); try s.save(sample())
        let obj = try JSONSerialization.jsonObject(with: Data(contentsOf: s.fileURL)) as? [String: Any]
        XCTAssertEqual(obj?["schemaVersion"] as? Int, AssignmentStore.currentSchemaVersion)
        XCTAssertNotNil(obj?["profile"])
    }

    func testLoadingValidFileDoesNotRewriteIt() throws {
        let s = makeStore(); try s.save(sample())
        let before = try Data(contentsOf: s.fileURL)
        _ = try s.load()
        XCTAssertEqual(try Data(contentsOf: s.fileURL), before)
    }

    func testLoadNormalisesNames() throws {
        var p = StompProfile.defaults; p.globalSlots[0].name = "  Big   Muff "
        let doc = StompProfileDocument(schemaVersion: 1, profile: p)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try JSONEncoder().encode(doc).write(to: dir.appendingPathComponent(AssignmentStore.fileName))
        XCTAssertEqual(try makeStore().load().profile.globalSlots[0].name, "Big Muff")
    }

    // Corrupt / incompatible: preserved, never destroyed
    private func assertRecovered(_ content: String, expecting: (LoadFailure) -> Bool, file: StaticString = #filePath, line: UInt = #line) throws {
        try write(content)
        let out = try makeStore().load()
        guard case let .recoveredWithDefaults(profile, backup, reason) = out else { return XCTFail("expected recovery, got \(out)", file: file, line: line) }
        XCTAssertEqual(profile, StompProfile.defaults, file: file, line: line)
        XCTAssertTrue(expecting(reason), "unexpected reason \(reason)", file: file, line: line)
        XCTAssertEqual(try String(contentsOf: backup, encoding: .utf8), content, "original bytes preserved", file: file, line: line)
        XCTAssertEqual(try makeStore().load(), .loaded(StompProfile.defaults), "fresh defaults now in place", file: file, line: line)
    }

    func testGarbageFileIsBackedUp() throws {
        try assertRecovered("not json {{{", expecting: { if case .unreadable = $0 { return true }; return false })
    }
    func testEmptyFileIsBackedUp() throws {
        try assertRecovered("", expecting: { if case .unreadable = $0 { return true }; return false })
    }
    func testTruncatedJSONIsBackedUp() throws {
        try assertRecovered(#"{"schemaVersion":1,"profile":{"globalSlots":[{"slot":1,"na"#, expecting: { if case .unreadable = $0 { return true }; return false })
    }
    func testNewerSchemaIsBackedUp() throws {
        try assertRecovered(#"{"schemaVersion":99,"profile":{"future":true}}"#, expecting: { $0 == .newerSchema(99) })
    }
    func testUnsupportedOlderSchemaIsBackedUp() throws {
        try assertRecovered(#"{"schemaVersion":0,"profile":{}}"#, expecting: { $0 == .unsupportedSchema(0) })
    }
    func testWrongShapeForCurrentSchemaIsBackedUp() throws {
        try assertRecovered(#"{"schemaVersion":1,"profile":{"oops":1}}"#, expecting: { if case .unreadable = $0 { return true }; return false })
    }
    func testValidJSONThatFailsValidationIsBackedUp() throws {
        var p = StompProfile.defaults; p.globalSlots.removeLast()
        let json = String(data: try JSONEncoder().encode(StompProfileDocument(schemaVersion: 1, profile: p)), encoding: .utf8)!
        try assertRecovered(json, expecting: { if case .failedValidation = $0 { return true }; return false })
    }
    func testOutOfRangeMIDIValueOnDiskIsBackedUp() throws {
        var p = StompProfile.defaults
        p.globalSlots[0].action = .controlChange(channel: 1, controller: 200, behavior: .fixedValue(1))
        let json = String(data: try JSONEncoder().encode(StompProfileDocument(schemaVersion: 1, profile: p)), encoding: .utf8)!
        try assertRecovered(json, expecting: { if case .failedValidation = $0 { return true }; return false })
    }
    func testUnacknowledgedSafetyWarningOnDiskIsBackedUp() throws {
        var p = StompProfile.defaults
        p.globalSlots[0].action = .controlChange(channel: 1, controller: 123, behavior: .fixedValue(1))
        let json = String(data: try JSONEncoder().encode(StompProfileDocument(schemaVersion: 1, profile: p)), encoding: .utf8)!
        try assertRecovered(json, expecting: { if case .failedValidation = $0 { return true }; return false })
    }

    func testRecoveryOutcomeExposesBackupPathAndReasonAndBackupsAreListed() throws {
        try write("garbage")
        let s = makeStore()
        guard case let .recoveredWithDefaults(_, backup, reason) = try s.load() else { return XCTFail() }
        XCTAssertTrue(backup.lastPathComponent.hasPrefix(AssignmentStore.backupPrefix))
        XCTAssertTrue(FileManager.default.fileExists(atPath: backup.path))
        if case .unreadable = reason {} else { XCTFail("reason \(reason)") }
        XCTAssertEqual(s.backupURLs().map(\.lastPathComponent), [backup.lastPathComponent])
        XCTAssertEqual(try makeStore().load(), .loaded(StompProfile.defaults), "second load is clean, so a UI must retain the notice itself")
        XCTAssertEqual(s.backupURLs().count, 1, "backup survives later loads and saves")
        try s.save(sample()); XCTAssertEqual(s.backupURLs().count, 1)
    }

    func testValidProfileIsNeverReplacedByDefaultsOrBackedUp() throws {
        let s = makeStore(); try s.save(sample())
        for _ in 0..<3 { XCTAssertEqual(try s.load(), .loaded(sample().normalized())) }
        XCTAssertTrue(s.backupURLs().isEmpty)
    }

    func testRepeatedRecoveriesNeverOverwriteEarlierBackups() throws {
        var backups = Set<URL>()
        for i in 0..<3 {
            try write("bad \(i)")
            guard case let .recoveredWithDefaults(_, b, _) = try makeStore().load() else { return XCTFail() }
            backups.insert(b)
        }
        XCTAssertEqual(backups.count, 3)
        let contents = try backups.map { try String(contentsOf: $0, encoding: .utf8) }.sorted()
        XCTAssertEqual(contents, ["bad 0", "bad 1", "bad 2"])
    }

    // Save safety / atomicity
    func testSaveRefusesInvalidProfileAndLeavesFileUntouched() throws {
        let s = makeStore(); try s.save(sample())
        let before = try Data(contentsOf: s.fileURL)
        var bad = sample(); bad.globalSlots[0].action = .programChange(channel: 99, program: 1)
        XCTAssertThrowsError(try s.save(bad)) { XCTAssertTrue(($0 as? StoreError).map { if case .invalidProfile = $0 { return true }; return false } ?? false) }
        XCTAssertEqual(try Data(contentsOf: s.fileURL), before)
    }

    func testSaveRefusesUnacknowledgedWarning() throws {
        var p = StompProfile.defaults
        p.globalSlots[0].action = .controlChange(channel: 1, controller: 0, behavior: .fixedValue(1))
        XCTAssertThrowsError(try makeStore().save(p))
        p.globalSlots[0].acknowledgedWarnings = [.bankSelect]
        XCTAssertNoThrow(try makeStore().save(p))
        XCTAssertEqual(try makeStore().load().profile.globalSlots[0].acknowledgedWarnings, [.bankSelect])
    }

    func testAtomicSaveLeavesNoTemporaryFiles() throws {
        let s = makeStore()
        for _ in 0..<5 { try s.save(sample()) }
        XCTAssertEqual(try files(), [AssignmentStore.fileName])
    }

    func testSaveReplacesExistingContent() throws {
        let s = makeStore(); try s.save(sample())
        var p = sample(); p.setGlobal(StompAssignment(slot: 3, name: "New", accentID: "pink", action: .programChange(channel: 1, program: 4)))
        try s.save(p)
        XCTAssertEqual(try s.load().profile.globalSlots[2].name, "New")
    }

    func testBackupFailureDoesNotOverwriteOriginal() throws {
        final class FailingMove: FileManager {
            override func moveItem(at srcURL: URL, to dstURL: URL) throws { throw CocoaError(.fileWriteNoPermission) }
        }
        try write("precious but corrupt")
        let s = AssignmentStore(directory: dir, fileManager: FailingMove(), now: { self.fixedNow })
        XCTAssertThrowsError(try s.load()) { XCTAssertTrue(($0 as? StoreError).map { if case .backupFailed = $0 { return true }; return false } ?? false) }
        XCTAssertEqual(try String(contentsOf: s.fileURL, encoding: .utf8), "precious but corrupt")
    }

    // Migration policy
    func testMigrationPolicy() {
        let d = Data("{}".utf8)
        XCTAssertEqual(AssignmentStore.migrate(d, from: AssignmentStore.currentSchemaVersion), d)
        XCTAssertNil(AssignmentStore.migrate(d, from: 0))
        XCTAssertNil(AssignmentStore.migrate(d, from: -3))
    }

    // Location
    func testDefaultDirectoryIsInApplicationSupport() throws {
        let url = try AssignmentStore.defaultDirectory()
        XCTAssertTrue(url.path.contains("Application Support"))
        XCTAssertEqual(url.lastPathComponent, "AnagramRemote")
    }

    // No MIDI / side effects
    func testStoreAndModelsHaveNoMIDIDependency() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Stomps")
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: root.path), !names.isEmpty else {
            throw XCTSkip("Source tree not available at test time")
        }
        for name in names where name.hasSuffix(".swift") {
            let text = try String(contentsOf: root.appendingPathComponent(name), encoding: .utf8)
            for banned in ["import CoreMIDI", "MIDITransport", "CoreMIDITransport", "MIDISend", "MIDICommand", "ConnectionViewModel"] {
                XCTAssertFalse(text.contains(banned), "\(name) must not reference \(banned)")
            }
        }
    }
}
