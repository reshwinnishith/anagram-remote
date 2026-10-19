import SwiftUI

/// Landscape Performance screen. Batch A: layout only; the only MIDI sends are the M1 preset buttons.
struct PerformanceView: View {
    @StateObject private var vm = ConnectionViewModel()
    @State private var showConnection = false
    @StateObject private var stompConfig = StompConfigModel.live()
    @State private var confirmEdit = false
    @State private var showEditor = false

    var body: some View {
        let p = PerformancePresentation(vm: vm)
        VStack(spacing: 12) {
            header(p)
            presetBar(p)
            HStack(spacing: Theme.Spacing.gutter) {
                sceneRail
                stompGrid
            }
            statusStrip(p)
        }
        .padding(Theme.Spacing.margin)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background.ignoresSafeArea())
        .foregroundStyle(Theme.textPrimary)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showConnection) { ConnectionSettingsView(vm: vm) }
        .confirmationDialog("Edit controls?", isPresented: $confirmEdit, titleVisibility: .visible) {
            Button("Edit Controls") { showEditor = true }
            Button("Stay on Performance", role: .cancel) {}
        } message: { Text("Editing is separate from performance and never sends MIDI.") }
        .fullScreenCover(isPresented: $showEditor) {
            StompConfigView(model: stompConfig) { showEditor = false }
        }
    }

    private func header(_ p: PerformancePresentation) -> some View {
        HStack(spacing: Theme.Spacing.gutter) {
            Button { showConnection = true } label: {
                HStack(spacing: 10) {
                    Image(systemName: p.connectionLevel.symbol)
                        .font(.title3)
                        .foregroundStyle(p.connectionLevel.color)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(p.connectionLabel).font(.headline).lineLimit(1)
                        Text(p.destinationLabel).font(.caption).foregroundStyle(Theme.textSecondary).lineLimit(1)
                    }
                }
                .padding(.horizontal, Theme.Spacing.gutter)
                .frame(minHeight: Theme.minTouch)
                .themedCard()
            }
            .buttonStyle(.plain)
            .accessibilityLabel("MIDI connection: \(p.connectionLabel), \(p.destinationLabel). Opens connection settings.")
            .accessibilityIdentifier("connection-pill")
            Spacer(minLength: 0)
            Text("ANAGRAM REMOTE")
                .font(.caption.bold()).tracking(1.5)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1).minimumScaleFactor(0.7)
                .accessibilityAddTraits(.isHeader)
            EditControlsButton { confirmEdit = true }
            ConnectionSettingsButton { showConnection = true }
        }
    }

    /// Compact single-row strip: preset identity on the left, the two working M1 shortcuts on the right.
    private func presetBar(_ p: PerformancePresentation) -> some View {
        HStack(spacing: Theme.Spacing.gutter) {
            Text("PRESET").font(.caption.bold()).tracking(1).foregroundStyle(Theme.textSecondary)
            Text(p.preset.label)
                .font(.system(size: 44, weight: .heavy, design: .rounded).monospacedDigit())
                .lineLimit(1).minimumScaleFactor(0.6)
                .accessibilityLabel("Preset \(p.preset.label). \(p.preset.subtitle)")
                .accessibilityIdentifier("preset-readout")
            Text(p.preset.subtitle)
                .font(.footnote).foregroundStyle(Theme.textSecondary)
                .lineLimit(2).minimumScaleFactor(0.8)
                .accessibilityHidden(true)
            Spacer(minLength: 0)
            ForEach(PresetShortcut.all) { shortcut in
                PresetShortcutButton(shortcut: shortcut, enabled: p.canSend) { vm.sendPreset(shortcut.program) }
            }
        }
        .padding(.horizontal, Theme.Spacing.gutter)
        .padding(.vertical, 8)
        .frame(minHeight: Theme.minTouch + 16)
        .themedCard()
        .fixedSize(horizontal: false, vertical: true)
    }

    private var sceneRail: some View {
        VStack(spacing: Theme.Spacing.gutter) {
            ForEach(SceneSlotPresentation.all) { SceneButton(slot: $0) }
        }
        .frame(minWidth: 150, idealWidth: 190, maxWidth: 210)
    }

    private var stompGrid: some View {
        VStack(spacing: Theme.Spacing.gutter) {
            ForEach(0..<PerformanceLayout.stompRows, id: \.self) { row in
                HStack(spacing: Theme.Spacing.gutter) {
                    ForEach(0..<PerformanceLayout.stompColumns, id: \.self) { col in
                        StompButton(stomp: StompPresentation(assignment: stompConfig.resolved(slot: row * PerformanceLayout.stompColumns + col + 1, preset: nil)))
                    }
                }
            }
        }
    }

    private func statusStrip(_ p: PerformancePresentation) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(p.lastSentText ?? "No MIDI sent this session")
                .font(.system(.footnote, design: .monospaced)).foregroundStyle(Theme.textSecondary)
            if let e = p.errorText {
                Label("Error: \(e)", systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote.bold()).foregroundStyle(Theme.error)
            }
        }
        .lineLimit(2)
        .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("status-strip")
    }
}
