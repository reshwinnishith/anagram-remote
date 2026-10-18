import SwiftUI

/// Landscape Performance screen. Batch A: layout only; the only MIDI sends are the M1 preset buttons.
struct PerformanceView: View {
    @StateObject private var vm = ConnectionViewModel()
    @State private var showConnection = false

    var body: some View {
        let p = PerformancePresentation(vm: vm)
        VStack(spacing: Theme.Spacing.gutter) {
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
    }

    private func header(_ p: PerformancePresentation) -> some View {
        HStack(spacing: Theme.Spacing.gutter) {
            Text("Anagram Remote").font(.title2.bold()).lineLimit(1).minimumScaleFactor(0.7)
            Button { showConnection = true } label: {
                HStack(spacing: 10) {
                    Circle().fill(p.connectionLevel.color).frame(width: 14, height: 14)
                    VStack(alignment: .leading, spacing: 2) {
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
            NavChip(title: "Presets", systemImage: "list.bullet")
            NavChip(title: "Tuner", systemImage: "tuningfork")
            NavChip(title: "Edit", systemImage: "slider.horizontal.3")
            NavChip(title: "Connection", systemImage: "gearshape") { showConnection = true }
        }
    }

    private func presetBar(_ p: PerformancePresentation) -> some View {
        HStack(spacing: Theme.Spacing.gutter) {
            VStack(alignment: .leading, spacing: 2) {
                Text("PRESET").font(.caption.bold()).foregroundStyle(Theme.textSecondary)
                Text(p.preset.label)
                    .font(.system(size: 48, weight: .heavy).monospacedDigit())
                    .accessibilityIdentifier("preset-readout")
                Text(p.preset.subtitle).font(.caption).foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 0)
            ForEach(PresetShortcut.all) { shortcut in
                PresetShortcutButton(shortcut: shortcut, enabled: p.canSend) { vm.sendPreset(shortcut.program) }
            }
        }
        .padding(Theme.Spacing.gutter)
        .frame(minHeight: 88)
        .themedCard()
        .fixedSize(horizontal: false, vertical: true)
    }

    private var sceneRail: some View {
        VStack(spacing: Theme.Spacing.gutter) {
            ForEach(SceneSlotPresentation.all) { SceneButton(slot: $0) }
        }
        .frame(minWidth: 160, idealWidth: 200, maxWidth: 220)
    }

    private var stompGrid: some View {
        VStack(spacing: Theme.Spacing.gutter) {
            ForEach(0..<PerformanceLayout.stompRows, id: \.self) { row in
                HStack(spacing: Theme.Spacing.gutter) {
                    ForEach(0..<PerformanceLayout.stompColumns, id: \.self) { col in
                        StompButton(stomp: StompPresentation.all[row * PerformanceLayout.stompColumns + col])
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
                Text("Error: \(e)").font(.footnote.bold()).foregroundStyle(Theme.error)
            }
        }
        .lineLimit(2)
        .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("status-strip")
    }
}
