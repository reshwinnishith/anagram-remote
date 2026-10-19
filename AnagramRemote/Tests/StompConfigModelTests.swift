import XCTest
@testable import AnagramRemote

@MainActor
final class StompConfigModelTests: XCTestCase {
    private var dir: URL!
    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("StompConfigModelTests-\(UUID().uuidString)", isDirectory: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    private func store() -> AssignmentStore { AssignmentStore(directory: dir) }
    private func model() -> StompConfigModel { StompConfigModel(store: store()) }

    private func ccDraft(_ m: StompConfigModel, slot: Int = 1, scope: StompEditorDraft.Scope = .global, cc: Int = 80, name: String = "Drive") -> StompEditorDraft {
        var d = m.draft(slot: slot, scope: scope)
        d.name = name; d.kind = .controlChange; d.controller = cc; d.channel = 2; d.style = .valueToggle
        return d
    }

    /// Fake whose behaviour tests control.
    private final class FakeStore: AssignmentPersisting {
        var loadResult: Result<LoadOutcome, Error> = .success(.loaded(StompProfile.defaults))
        var saveError: Error?
        var saved: [StompProfile] = []
        var backups: [URL] = []
        func load() throws -> LoadOutcome { try loadResult.get() }
        func save(_ profile: StompProfile) throws { if let e = saveError { throw e }; saved.append(profile) }
        func backupURLs() -> [URL] { backups }
    }

    // Global
    func testFirstLaunchHasSixUnassignedSlots() {
        let m = model()
        XCTAssertEqual(m.profile, StompProfile.defaults); XCTAssertNil(m.recovery); XCTAssertTrue(m.canEdit)
    }

    func testSaveGlobalPersistsAndSurvivesReload() {
        let m = model()
        XCTAssertEqual(m.save(ccDraft(m)), .saved)
        XCTAssertEqual(m.resolved(slot: 1, preset: nil).name, "Drive")
        XCTAssertNotNil(m.lastSavedAt); XCTAssertNil(m.lastSaveError)
        let reloaded = model()
        XCTAssertEqual(reloaded.resolved(slot: 1, preset: nil).action,
                       .controlChange(channel: 2, controller: 80, behavior: .toggle(.values(on: 127, off: 0))))
    }

    // Overrides
    func testPresetOverrideAppliesOnlyToThatPreset() {
        let m = model()
        m.save(ccDraft(m, name: "Global"))
        XCTAssertEqual(m.save(ccDraft(m, scope: .preset(5), cc: 81, name: "Five")), .saved)
        XCTAssertEqual(m.resolved(slot: 1, preset: 5).name, "Five")
        XCTAssertEqual(m.resolved(slot: 1, preset: 6).name, "Global")
        XCTAssertEqual(m.resolved(slot: 1, preset: nil).name, "Global")
        XCTAssertTrue(m.isOverride(slot: 1, preset: 5)); XCTAssertFalse(m.isOverride(slot: 1, preset: 6))
    }

    func testExplicitUnassignedOverride() {
        let m = model()
        m.save(ccDraft(m))
        var d = m.draft(slot: 1, scope: .preset(3)); d.kind = .unassigned
        XCTAssertEqual(m.save(d), .saved)
        XCTAssertTrue(m.isOverride(slot: 1, preset: 3))
        XCTAssertEqual(m.resolved(slot: 1, preset: 3).action, .unassigned)
        XCTAssertNotEqual(m.resolved(slot: 1, preset: nil).action, .unassigned)
    }

    func testResetToGlobalRemovesOverrideAndPersists() {
        let m = model()
        m.save(ccDraft(m, name: "Global")); m.save(ccDraft(m, scope: .preset(2), name: "Over"))
        XCTAssertEqual(m.resetToGlobal(preset: 2, slot: 1), .saved)
        XCTAssertFalse(m.isOverride(slot: 1, preset: 2))
        XCTAssertEqual(m.resolved(slot: 1, preset: 2).name, "Global")
        XCTAssertFalse(model().isOverride(slot: 1, preset: 2), "persisted")
    }

    func testOverrideDraftStartsFromGlobalAssignment() {
        let m = model(); m.save(ccDraft(m, cc: 81, name: "Global"))
        let d = m.draft(slot: 1, scope: .preset(9))
        XCTAssertEqual(d.name, "Global"); XCTAssertEqual(d.controller, 81)
        XCTAssertEqual(d.scope, .preset(9))
    }

    // Cancel / draft separation
    func testDraftChangesDoNotTouchStoredProfileUntilSaved() {
        let m = model(); let before = m.profile
        var d = ccDraft(m); d.name = "Edited"      // "Cancel" == dropping the draft
        _ = d
        XCTAssertEqual(m.profile, before)
        XCTAssertEqual(try? Data(contentsOf: store().fileURL), try? Data(contentsOf: store().fileURL))
    }

    // Refusals leave persisted data untouched
    private func fileBytes() -> Data? { try? Data(contentsOf: store().fileURL) }

    func testIncompleteDraftIsRefusedAndNothingWritten() {
        let m = model(); let before = fileBytes()
        var d = ccDraft(m); d.controller = nil
        guard case .failed = m.save(d) else { return XCTFail() }
        XCTAssertEqual(m.profile, StompProfile.defaults); XCTAssertEqual(fileBytes(), before); XCTAssertNotNil(m.lastSaveError)
        XCTAssertNil(m.lastSavedAt, "never claims a save that did not happen")
    }

    func testInvalidDraftIsRefused() {
        let m = model(); let before = fileBytes()
        var d = ccDraft(m); d.channel = 99
        guard case .failed = m.save(d) else { return XCTFail() }
        XCTAssertEqual(fileBytes(), before)
    }

    func testAdvancedControllerRequiresAcknowledgement() {
        let m = model()
        var d = ccDraft(m, cc: 0)
        guard case .failed = m.save(d) else { return XCTFail() }
        XCTAssertEqual(m.resolved(slot: 1, preset: nil).action, .unassigned)
        d.acknowledged = [.bankSelect]
        XCTAssertEqual(m.save(d), .saved)
        XCTAssertEqual(m.resolved(slot: 1, preset: nil).acknowledgedWarnings, [.bankSelect])
    }

    // Save failures are visible and non-destructive to in-memory state
    func testStoreWriteFailureIsReportedAndProfileUnchanged() {
        let fake = FakeStore(); fake.saveError = StoreError.writeFailed("disk full")
        let m = StompConfigModel(store: fake)
        let d = ccDraft(m)
        guard case let .failed(msg) = m.save(d) else { return XCTFail() }
        XCTAssertTrue(msg.contains("disk full"))
        XCTAssertEqual(m.profile, StompProfile.defaults)
        XCTAssertEqual(m.lastSaveError, msg); XCTAssertNil(m.lastSavedAt)
    }

    func testSuccessfulSaveClearsEarlierError() {
        let fake = FakeStore(); fake.saveError = StoreError.writeFailed("x")
        let m = StompConfigModel(store: fake)
        _ = m.save(ccDraft(m)); XCTAssertNotNil(m.lastSaveError)
        fake.saveError = nil
        XCTAssertEqual(m.save(ccDraft(m)), .saved)
        XCTAssertNil(m.lastSaveError); XCTAssertNotNil(m.lastSavedAt); XCTAssertEqual(fake.saved.count, 1)
    }

    func testResetFailureKeepsOverride() {
        let fake = FakeStore(); let m = StompConfigModel(store: fake)
        m.save(ccDraft(m, scope: .preset(2)))
        fake.saveError = StoreError.writeFailed("nope")
        guard case .failed = m.resetToGlobal(preset: 2, slot: 1) else { return XCTFail() }
        XCTAssertTrue(m.isOverride(slot: 1, preset: 2))
    }

    // Recovery
    func testRecoveryNoticeExposesBackupAndReasonAndPersistsUntilDismissed() throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("garbage".utf8).write(to: dir.appendingPathComponent(AssignmentStore.fileName))
        let m = model()
        let notice = try XCTUnwrap(m.recovery)
        XCTAssertTrue(FileManager.default.fileExists(atPath: notice.backup.path))
        XCTAssertEqual(try String(contentsOf: notice.backup, encoding: .utf8), "garbage")
        XCTAssertFalse(notice.reasonText.isEmpty)
        XCTAssertEqual(m.profile, StompProfile.defaults); XCTAssertTrue(m.canEdit)
        // Editing and saving do not dismiss it.
        m.save(ccDraft(m)); XCTAssertNotNil(m.recovery)
        m.reload(); XCTAssertNotNil(m.recovery, "a clean reload must not silently erase the notice")
        m.dismissRecovery(); XCTAssertNil(m.recovery)
        XCTAssertEqual(m.backups.count, 1)
    }

    func testReasonTextForEachFailure() {
        let url = URL(fileURLWithPath: "/tmp/x")
        for r: LoadFailure in [.unreadable("x"), .newerSchema(9), .unsupportedSchema(0), .failedValidation(["a", "b"])] {
            XCTAssertFalse(RecoveryNotice(backup: url, reason: r).reasonText.isEmpty)
        }
    }

    func testStorageProblemDisablesEditingAndNeverSaves() {
        let fake = FakeStore(); fake.loadResult = .failure(StoreError.backupFailed("locked"))
        let m = StompConfigModel(store: fake)
        XCTAssertFalse(m.canEdit); XCTAssertNotNil(m.storageProblem)
        guard case .failed = m.save(ccDraft(m)) else { return XCTFail() }
        guard case .failed = m.resetToGlobal(preset: 1, slot: 1) else { return XCTFail() }
        XCTAssertTrue(fake.saved.isEmpty, "defaults must never overwrite data that could not be read")
        fake.loadResult = .success(.loaded(StompProfile.defaults))
        m.reload(); XCTAssertTrue(m.canEdit); XCTAssertNil(m.storageProblem)
    }

    // No MIDI
    func testEditingFilesHaveNoMIDIDependency() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Features/StompConfig")
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: root.path), !names.isEmpty else {
            throw XCTSkip("Source tree not available at test time")
        }
        for name in names where name.hasSuffix(".swift") {
            let text = try String(contentsOf: root.appendingPathComponent(name), encoding: .utf8)
            for banned in ["import CoreMIDI", "MIDITransport", "MIDICommand", "MIDISend", "sendPreset", "ConnectionViewModel", "MIDIConnectionManager"] {
                XCTAssertFalse(text.contains(banned), "\(name) must not reference \(banned)")
            }
        }
    }

    func testEditingAndSavingWithAMockTransportAliveSendsNothing() {
        let transport = MockMIDITransport(destinations: [MIDIDestination(id: 1, name: "Anagram")])
        let vm = ConnectionViewModel(manager: MIDIConnectionManager(transport: transport))
        vm.selectDestination(1)
        let m = model()
        m.save(ccDraft(m)); m.save(ccDraft(m, scope: .preset(4))); m.resetToGlobal(preset: 4, slot: 1); m.reload()
        XCTAssertTrue(transport.sent.isEmpty)
    }
}
