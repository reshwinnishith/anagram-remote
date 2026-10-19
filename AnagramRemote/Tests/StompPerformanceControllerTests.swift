import XCTest
@testable import AnagramRemote

@MainActor
final class StompPerformanceControllerTests: XCTestCase {
    private final class FakeStore: AssignmentPersisting {
        var initial = StompProfile.defaults
        var loadError: Error?
        func load() throws -> LoadOutcome {
            if let loadError { throw loadError }
            return .loaded(initial)
        }
        func save(_ profile: StompProfile) throws { initial = profile }
        func backupURLs() -> [URL] { [] }
    }

    private let anagram = MIDIDestination(id: 42, name: "Anagram")
    private let other = MIDIDestination(id: 7, name: "Other")
    private var transport: MockMIDITransport!
    private var manager: MIDIConnectionManager!
    private var vm: ConnectionViewModel!
    private var store: FakeStore!
    private var config: StompConfigModel!
    private var center: NotificationCenter!
    private var controller: StompPerformanceController!

    override func setUp() async throws {
        try await bootstrap()
    }

    private func bootstrap(profile: StompProfile = .defaults, loadError: Error? = nil, selectAnagram: Bool = true) async throws {
        transport = MockMIDITransport(destinations: [anagram, other])
        manager = MIDIConnectionManager(transport: transport)
        vm = ConnectionViewModel(manager: manager)
        if selectAnagram { vm.selectDestination(42) }
        store = FakeStore()
        store.initial = profile
        store.loadError = loadError
        config = StompConfigModel(store: store)
        center = NotificationCenter()
        controller = StompPerformanceController(connection: vm, config: config, notificationCenter: center)
    }

    private func assignment(_ slot: Int, _ action: StompAction, name: String = "", accent: String = "blue", ack: [SafetyWarning] = []) -> StompAssignment {
        StompAssignment(slot: slot, name: name, accentID: accent, action: action, acknowledgedWarnings: ack)
    }

    @discardableResult
    private func assign(_ a: StompAssignment) -> SaveOutcome {
        config.save(StompEditorDraft(assignment: a, scope: .global))
    }

    private func toggle(_ slot: Int = 1, on: Int = 127, off: Int = 0, controller: Int = 80, channel: Int = 1) -> StompAssignment {
        assignment(slot, .controlChange(channel: channel, controller: controller, behavior: .toggle(.values(on: on, off: off))))
    }

    private var sent: [[UInt8]] { transport.sent.map(\.bytes) }

    func testEachSupportedActionSendsExactlyOnceThroughThePerformancePath() {
        assign(assignment(1, .controlChange(channel: 1, controller: 80, behavior: .fixedValue(64))))
        assign(toggle(2, controller: 81))
        assign(assignment(3, .controlChange(channel: 1, controller: 82, behavior: .toggle(.deviceToggle(trigger: 100)))))
        assign(assignment(4, .programChange(channel: 1, program: 12)))
        for slot in 1...4 { XCTAssertTrue(controller.tile(slot: slot).isEnabled, "slot \(slot)") }
        for slot in 1...4 {
            let before = transport.sent.count
            controller.activate(slot: slot)
            XCTAssertEqual(transport.sent.count, before + 1, "slot \(slot)")
        }
        XCTAssertEqual(sent, [[0xB0, 80, 64], [0xB0, 81, 127], [0xB0, 82, 100], [0xC0, 11]])
    }

    func testAssignmentChannelsAreUsedNotTheConnectionChannel() {
        vm.setChannel(9)
        assign(assignment(1, .controlChange(channel: 2, controller: 80, behavior: .fixedValue(1))))
        assign(assignment(2, .programChange(channel: 5, program: 1)))
        controller.activate(slot: 1); controller.activate(slot: 2)
        vm.sendPreset(1)
        XCTAssertEqual(sent, [[0xB1, 80, 1], [0xC4, 0x00], [0xC8, 0x00]])
    }

    func testUnassignedTilesAreDisabledAndSendNothing() {
        XCTAssertEqual(controller.tile(slot: 1).kind, .unassigned)
        XCTAssertFalse(controller.tile(slot: 1).isEnabled)
        controller.activate(slot: 1)
        XCTAssertTrue(transport.sent.isEmpty)
        XCTAssertNil(controller.failure)
    }

    func testMomentaryTilesAreDisabledWithAnExplanationAndSendNothing() {
        assign(assignment(1, .controlChange(channel: 1, controller: 80, behavior: .momentary(press: 127, release: 0))))
        let tile = controller.tile(slot: 1)
        XCTAssertEqual(tile.kind, .momentaryNotActive)
        XCTAssertFalse(tile.isEnabled)
        XCTAssertEqual(tile.detail, "MOMENTARY NOT ACTIVE YET")
        controller.activate(slot: 1)
        XCTAssertTrue(transport.sent.isEmpty)
    }

    func testInvalidAndUnacknowledgedAssignmentsAreDisabled() async throws {
        var profile = StompProfile.defaults
        profile.setGlobal(assignment(1, .controlChange(channel: 17, controller: 80, behavior: .fixedValue(1))))
        profile.setGlobal(assignment(2, .controlChange(channel: 1, controller: 7, behavior: .fixedValue(1))))
        profile.setGlobal(assignment(3, .controlChange(channel: 1, controller: 7, behavior: .fixedValue(1)), ack: [.anagramReserved]))
        try await bootstrap(profile: profile)
        XCTAssertEqual(controller.tile(slot: 1).kind, .blocked(.invalidAssignment))
        XCTAssertEqual(controller.tile(slot: 2).kind, .blocked(.invalidAssignment))
        XCTAssertEqual(controller.tile(slot: 3).kind, .ready)
        controller.activate(slot: 1); controller.activate(slot: 2)
        XCTAssertTrue(transport.sent.isEmpty)
        controller.activate(slot: 3)
        XCTAssertEqual(sent, [[0xB0, 7, 1]])
    }

    func testStorageUnavailableDisablesEveryStomp() async throws {
        var profile = StompProfile.defaults
        profile.setGlobal(assignment(1, .programChange(channel: 1, program: 1)))
        try await bootstrap(profile: profile, loadError: StoreError.backupFailed("locked"))
        XCTAssertFalse(config.canEdit)
        for slot in 1...6 { XCTAssertFalse(controller.tile(slot: slot).isEnabled) }
        controller.activate(slot: 1)
        XCTAssertTrue(transport.sent.isEmpty)
    }

    func testNoDestinationOrDisconnectedDestinationDisablesConfiguredStomps() async throws {
        try await bootstrap(selectAnagram: false)
        assign(assignment(1, .programChange(channel: 1, program: 1)))
        XCTAssertEqual(controller.tile(slot: 1).kind, .blocked(.noDestination))
        controller.activate(slot: 1)
        XCTAssertTrue(transport.sent.isEmpty)
        vm.selectDestination(42)
        XCTAssertTrue(controller.tile(slot: 1).isEnabled)
        transport.setDestinations([other])
        XCTAssertEqual(controller.tile(slot: 1).kind, .blocked(.noDestination))
        controller.activate(slot: 1)
        XCTAssertTrue(transport.sent.isEmpty)
    }

    func testValueToggleStartsOnAndAlternatesOnlyAfterSuccess() {
        assign(toggle())
        XCTAssertEqual(controller.tile(slot: 1).detail, "LOCAL: NOT SENT YET")
        controller.activate(slot: 1)
        XCTAssertEqual(controller.tile(slot: 1).detail, "LOCAL: LAST SENT ON")
        controller.activate(slot: 1)
        XCTAssertEqual(controller.tile(slot: 1).detail, "LOCAL: LAST SENT OFF")
        controller.activate(slot: 1)
        XCTAssertEqual(sent, [[0xB0, 80, 127], [0xB0, 80, 0], [0xB0, 80, 127]])
    }

    func testFailedSendShowsFailureKeepsToggleStateAndRecoversCleanly() {
        assign(toggle())
        transport.sendError = MIDITransportError.sendFailed(-9)
        controller.activate(slot: 1)
        XCTAssertNotNil(controller.failure)
        XCTAssertEqual(controller.failure?.slot, 1)
        XCTAssertTrue(controller.failure?.message.contains("-9") ?? false)
        XCTAssertNil(controller.lastSendText)
        XCTAssertEqual(controller.tile(slot: 1).detail, "LOCAL: NOT SENT YET")
        transport.sendError = nil
        controller.activate(slot: 1)
        XCTAssertNil(controller.failure)
        XCTAssertEqual(sent, [[0xB0, 80, 127]])
        XCTAssertNotNil(controller.lastSendText)
        transport.sendError = MIDITransportError.sendFailed(-9)
        controller.activate(slot: 1)
        XCTAssertEqual(controller.tile(slot: 1).detail, "LOCAL: LAST SENT ON")
        transport.sendError = nil
        controller.activate(slot: 1)
        XCTAssertEqual(sent.last, [0xB0, 80, 0])
    }

    func testToggleResetsWhenSelectedDestinationChanges() {
        assign(toggle()); controller.activate(slot: 1)
        vm.selectDestination(7)
        XCTAssertEqual(controller.tile(slot: 1).detail, "LOCAL: NOT SENT YET")
        controller.activate(slot: 1)
        XCTAssertEqual(sent, [[0xB0, 80, 127], [0xB0, 80, 127]])
        XCTAssertEqual(transport.sent.map(\.destinationID), [42, 7])
    }

    func testToggleResetsOnDisconnectAndReconnectWithoutSending() {
        assign(toggle()); controller.activate(slot: 1)
        transport.setDestinations([other])
        XCTAssertEqual(transport.sent.count, 1)
        transport.setDestinations([anagram, other])
        XCTAssertEqual(transport.sent.count, 1)
        XCTAssertEqual(controller.tile(slot: 1).detail, "LOCAL: NOT SENT YET")
        controller.activate(slot: 1)
        XCTAssertEqual(sent.last, [0xB0, 80, 127])
    }

    func testToggleResetsWhenTheSlotsEffectiveActionChanges() {
        assign(toggle()); controller.activate(slot: 1)
        assign(toggle(controller: 81))
        controller.activate(slot: 1)
        XCTAssertEqual(sent, [[0xB0, 80, 127], [0xB0, 81, 127]])
    }

    func testEditingAToBToAWithoutActivatingBStillResets() {
        assign(toggle()); controller.activate(slot: 1)
        assign(assignment(1, .programChange(channel: 1, program: 3)))
        assign(toggle())
        XCTAssertEqual(controller.tile(slot: 1).detail, "LOCAL: NOT SENT YET")
        controller.activate(slot: 1)
        XCTAssertEqual(sent, [[0xB0, 80, 127], [0xB0, 80, 127]])
    }

    func testLabelAndAccentOnlyEditsDoNotResetToggleState() {
        assign(toggle()); controller.activate(slot: 1)
        assign(toggle().withName("Renamed", accent: "teal"))
        XCTAssertEqual(controller.tile(slot: 1).label, "Renamed")
        XCTAssertEqual(controller.tile(slot: 1).detail, "LOCAL: LAST SENT ON")
        controller.activate(slot: 1)
        XCTAssertEqual(sent.last, [0xB0, 80, 0])
    }

    func testOtherSlotEditDoesNotResetPerSlotState() {
        assign(toggle()); controller.activate(slot: 1)
        assign(assignment(2, .programChange(channel: 1, program: 1)))
        XCTAssertEqual(controller.tile(slot: 1).detail, "LOCAL: NOT SENT YET")
    }

    func testUnchangedRefreshesRedrawsAndDiagnosticsDoNotResetToggleState() {
        assign(toggle()); controller.activate(slot: 1)
        vm.rescan()
        transport.setDestinations([anagram, other])
        config.reload()
        vm.setChannel(vm.channel)
        for _ in 0..<5 { _ = controller.tile(slot: 1) }
        vm.sendPreset(2)
        XCTAssertEqual(controller.tile(slot: 1).detail, "LOCAL: LAST SENT ON")
        controller.activate(slot: 1)
        XCTAssertEqual(sent.last, [0xB0, 80, 0])
    }

    func testChannelChangeAndOverrideEditsDoNotResetOrActivateOverrides() {
        assign(toggle()); controller.activate(slot: 1)
        vm.setChannel(7)
        var draft = StompEditorDraft(assignment: assignment(1, .programChange(channel: 1, program: 9)), scope: .preset(2))
        draft.name = "Override"
        XCTAssertEqual(config.save(draft), .saved)
        XCTAssertEqual(controller.tile(slot: 1).label, "Stomp 1")
        XCTAssertEqual(controller.tile(slot: 1).detail, "LOCAL: LAST SENT ON")
        controller.activate(slot: 1)
        XCTAssertEqual(sent.last, [0xB0, 80, 0])
    }

    func testLeavingTheActiveStateResetsToggleStateWithoutSending() {
        assign(toggle()); controller.activate(slot: 1)
        center.post(name: UIApplication.willResignActiveNotification, object: nil)
        XCTAssertEqual(transport.sent.count, 1)
        XCTAssertEqual(controller.tile(slot: 1).detail, "LOCAL: NOT SENT YET")
        controller.activate(slot: 1)
        center.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        controller.activate(slot: 1)
        XCTAssertEqual(sent, [[0xB0, 80, 127], [0xB0, 80, 127], [0xB0, 80, 127]])
    }

    func testNothingIsSentAutomaticallyOrReplayed() {
        assign(toggle()); assign(assignment(2, .programChange(channel: 1, program: 1)))
        config.reload()
        _ = config.resetToGlobal(preset: 1, slot: 1)
        vm.selectDestination(7); vm.selectDestination(42); vm.setChannel(3); vm.rescan()
        center.post(name: UIApplication.willResignActiveNotification, object: nil)
        center.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        for slot in 1...6 { _ = controller.tile(slot: slot) }
        XCTAssertTrue(transport.sent.isEmpty)
    }

    func testFailedActivationIsNeverReplayedOnReconnect() {
        assign(toggle())
        transport.setDestinations([other])
        controller.activate(slot: 1)
        transport.setDestinations([anagram, other])
        vm.rescan()
        XCTAssertTrue(transport.sent.isEmpty)
    }

    func testStompSendsNeverTouchThePresetReadoutOrPresetDiagnostics() {
        assign(toggle()); assign(assignment(2, .programChange(channel: 1, program: 5)))
        vm.sendPreset(2)
        let readout = PerformancePresentation(vm: vm).preset
        let history = vm.lastTransmission
        controller.activate(slot: 1); controller.activate(slot: 2)
        transport.sendError = MIDITransportError.sendFailed(-1)
        controller.activate(slot: 1)
        XCTAssertEqual(PerformancePresentation(vm: vm).preset, readout)
        XCTAssertEqual(vm.lastTransmission, history)
        XCTAssertNil(vm.lastError)
        XCTAssertNotNil(controller.failure)
        XCTAssertEqual(readout.label, "01B")
    }

    func testShortcutHistoryStaysOnTheShortcutWhileStompProgramChangeIsRecordedSeparately() {
        assign(assignment(1, .programChange(channel: 1, program: 12)))
        vm.sendPreset(2)
        controller.activate(slot: 1)
        let presentation = PerformancePresentation(vm: vm)
        XCTAssertEqual(presentation.preset.label, "01B")
        XCTAssertEqual(vm.lastTransmission?.program, 2)
        XCTAssertEqual(vm.lastTransmission?.bytes, [0xC0, 0x01])
        XCTAssertTrue(presentation.preset.subtitle.contains("Preset shortcut history"))
        XCTAssertTrue(presentation.preset.subtitle.contains("not confirmed by device"))
        XCTAssertTrue(presentation.lastSentText?.hasPrefix("Preset shortcut: Program Change 2") == true)
        XCTAssertEqual(manager.lastCommandRecord?.command, .programChange(channel: 1, program: 12))
        XCTAssertEqual(manager.lastCommandRecord?.bytes, [0xC0, 0x0B])
        XCTAssertTrue(controller.lastSendText?.contains("Program Change 12") == true)
        XCTAssertFalse(controller.lastSendText?.contains("Preset shortcut") == true)
        XCTAssertEqual(sent, [[0xC0, 0x01], [0xC0, 0x0B]])
    }

    func testEmptyShortcutHistoryWordingDoesNotImplyAHardwarePreset() {
        let presentation = PerformancePresentation(vm: vm)
        XCTAssertEqual(presentation.preset.label, "—")
        XCTAssertTrue(presentation.preset.subtitle.contains("none sent yet"))
        XCTAssertTrue(presentation.preset.subtitle.contains("not confirmed by device"))
        XCTAssertNil(presentation.lastSentText)
    }

    func testPerformanceViewUsesShortcutWordingNotPresetWording() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Features/Performance/PerformanceView.swift")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { throw XCTSkip("Source tree not available at test time") }
        XCTAssertTrue(text.contains("LAST SHORTCUT SENT"))
        XCTAssertTrue(text.contains("Last preset shortcut sent:"))
        XCTAssertTrue(text.contains("No preset shortcut sent this session."))
        XCTAssertFalse(text.contains("LAST PRESET SENT"))
        XCTAssertFalse(text.contains("Last preset sent from this app"))
    }

    func testPresetFailureDoesNotCreateAStompFailure() {
        vm.selectDestination(nil)
        vm.sendPreset(1)
        XCTAssertNotNil(vm.lastError)
        XCTAssertNil(controller.failure)
    }

    func testSendTextDescribesHandOffNotConfirmation() {
        assign(toggle()); controller.activate(slot: 1)
        let text = controller.lastSendText ?? ""
        XCTAssertTrue(text.contains("CC 80 = 127 on ch 1"))
        XCTAssertTrue(text.contains("handed to CoreMIDI, not confirmed by the Anagram"))
    }

    func testTileWordingForEachState() {
        assign(assignment(1, .controlChange(channel: 1, controller: 80, behavior: .fixedValue(64))))
        assign(assignment(2, .controlChange(channel: 1, controller: 81, behavior: .toggle(.deviceToggle(trigger: 127)))))
        assign(assignment(3, .programChange(channel: 1, program: 4)))
        assign(toggle(4, controller: 83))
        XCTAssertEqual(controller.tile(slot: 1).detail, "FIXED VALUE 64")
        XCTAssertEqual(controller.tile(slot: 2).detail, "TOGGLE TRIGGER 127")
        XCTAssertEqual(controller.tile(slot: 3).detail, "PROGRAM CHANGE TRIGGER")
        for slot in 1...3 {
            let text = controller.tile(slot: slot).detail + controller.tile(slot: slot).accessibilityValue
            XCTAssertFalse(text.uppercased().contains("LAST SENT"), "slot \(slot) must not show inferred state")
            XCTAssertFalse(text.uppercased().contains("NOT ACTIVE"))
        }
        XCTAssertFalse(controller.tile(slot: 4).detail.contains("OFF"), "unknown must not look like confirmed OFF")
        XCTAssertEqual(controller.tile(slot: 5).detail, "UNASSIGNED")
    }

    func testAccessibilityDescribesLocalStateAndNonConfirmation() {
        assign(toggle(on: 100, off: 10))
        var tile = controller.tile(slot: 1)
        XCTAssertEqual(tile.accessibilityLabel, "Stomp 1, CC 80 · Ch 1")
        XCTAssertEqual(tile.accessibilityValue, "Local record: nothing sent yet")
        XCTAssertTrue(tile.accessibilityHint.contains("send ON, value 100"))
        XCTAssertTrue(tile.accessibilityHint.contains("Not confirmed by the Anagram"))
        controller.activate(slot: 1)
        tile = controller.tile(slot: 1)
        XCTAssertEqual(tile.accessibilityValue, "Local record: last sent ON")
        XCTAssertTrue(tile.accessibilityHint.contains("send OFF, value 10"))
    }

    func testDisabledTilesExplainWhy() async throws {
        try await bootstrap(selectAnagram: false)
        assign(assignment(1, .programChange(channel: 1, program: 1)))
        XCTAssertEqual(controller.tile(slot: 1).detail, "NOT ACTIVE · NO DESTINATION")
        XCTAssertTrue(controller.tile(slot: 1).accessibilityHint.contains("Connection settings"))
    }

    func testScenesAndM1PresetsRemainUnchanged() {
        XCTAssertTrue(SceneSlotPresentation.all.allSatisfy { !$0.isEnabled && $0.statusText == "NOT CONFIGURED" })
        vm.sendPreset(1); vm.sendPreset(2)
        XCTAssertEqual(sent, [[0xC0, 0x00], [0xC0, 0x01]])
        XCTAssertEqual(PresetShortcut.all.map(\.program), [1, 2])
    }

    func testControllerIsStableAcrossRepeatedStateReads() {
        let before = ObjectIdentifier(controller)
        for _ in 0..<10 { _ = controller.tile(slot: 1) }
        XCTAssertEqual(ObjectIdentifier(controller), before)
    }

    func testPerformanceCoreSharesOneManagerAcrossConnectionAndStomps() {
        let core = PerformanceCore(connection: vm, config: config)
        XCTAssertTrue(core.connection === vm)
        XCTAssertTrue(core.config === config)
        assign(assignment(1, .programChange(channel: 1, program: 1)))
        core.stomps.activate(slot: 1)
        core.connection.sendPreset(1)
        XCTAssertEqual(transport.sent.count, 2)
    }
}

private extension StompAssignment {
    func withName(_ name: String, accent: String) -> StompAssignment {
        var copy = self
        copy.name = name
        copy.accentID = accent
        return copy
    }
}
