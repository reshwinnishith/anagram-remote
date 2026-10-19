import SwiftUI
import UIKit

/// Separate, full-screen editing area. Nothing here sends MIDI.
struct StompConfigView: View {
    @ObservedObject var model: StompConfigModel
    let onClose: () -> Void

    @State private var scopeIsPreset = false
    @State private var presetNumber = 1

    private var scope: StompEditorDraft.Scope { scopeIsPreset ? .preset(presetNumber) : .global }
    private var preset: Int? { scopeIsPreset ? presetNumber : nil }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.gutter) {
                    if let r = model.recovery { RecoveryBanner(notice: r, dismiss: model.dismissRecovery) }
                    if let problem = model.storageProblem { StorageProblemBanner(message: problem, retry: model.reload) }
                    scopePicker
                    grid
                    footer
                }
                .padding(Theme.Spacing.margin)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Edit Controls")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onClose).accessibilityIdentifier("edit-done")
                }
            }
            .navigationDestination(for: Int.self) { slot in
                StompEditorView(model: model, slot: slot, scope: scope)
            }
        }
        .preferredColorScheme(.dark)
        .foregroundStyle(Theme.textPrimary)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    private var scopePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: Theme.Spacing.gutter) {
                Picker("Configure", selection: $scopeIsPreset) {
                    Text("Global defaults").tag(false)
                    Text("Per-preset override").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 420)
                .accessibilityIdentifier("scope-picker")
                if scopeIsPreset {
                    Picker("Preset", selection: $presetNumber) {
                        ForEach(ProgramNumbering.uiRange, id: \.self) { n in Text(presetTitle(n)).tag(n) }
                    }
                    .pickerStyle(.menu)
                    .accessibilityIdentifier("preset-picker")
                }
                Spacer(minLength: 0)
            }
            Text(scopeIsPreset
                 ? "Overrides apply only to the preset you choose here. Slots without an override follow the global defaults. This is your own selection; the app does not know which preset the hardware is on."
                 : "Global defaults apply to every preset unless that preset has an override.")
                .font(.footnote).foregroundStyle(Theme.textSecondary)
        }
    }

    private func presetTitle(_ n: Int) -> String { "Preset \(PresetLabel.text(forProgram: n))" }

    private var grid: some View {
        VStack(spacing: Theme.Spacing.gutter) {
            ForEach(0..<PerformanceLayout.stompRows, id: \.self) { row in
                HStack(spacing: Theme.Spacing.gutter) {
                    ForEach(0..<PerformanceLayout.stompColumns, id: \.self) { col in
                        let slot = row * PerformanceLayout.stompColumns + col + 1
                        let a = model.resolved(slot: slot, preset: preset)
                        NavigationLink(value: slot) {
                            OverviewCard(assignment: a, scopeTag: scopeTag(slot))
                        }
                        .buttonStyle(.plain)
                        .disabled(!model.canEdit)
                        .accessibilityIdentifier("edit-stomp-\(slot)")
                    }
                }
            }
        }
    }

    private func scopeTag(_ slot: Int) -> String {
        guard let p = preset else { return "GLOBAL" }
        return model.isOverride(slot: slot, preset: p) ? "OVERRIDE" : "GLOBAL"
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Editing never sends MIDI. Performance uses the global assignments only; preset overrides are not applied there yet.", systemImage: "info.circle")
            if let t = model.lastSavedAt {
                Text("Last saved \(t.formatted(date: .omitted, time: .shortened))")
            }
            if model.recovery == nil, !model.backups.isEmpty {
                Text("\(model.backups.count) preserved backup file\(model.backups.count == 1 ? "" : "s") of earlier unusable settings exist in the app's storage folder.")
            }
        }
        .font(.footnote).foregroundStyle(Theme.textSecondary)
    }
}

private struct OverviewCard: View {
    let assignment: StompAssignment
    let scopeTag: String

    var body: some View {
        let assigned = StompAssignmentSummary.isAssigned(assignment)
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("\(assignment.slot)")
                    .font(.footnote.bold().monospacedDigit())
                    .frame(width: 30, height: 30)
                    .background(Circle().strokeBorder(StompAccent.color(for: assignment.accentID), lineWidth: 3))
                Spacer(minLength: 0)
                Text(scopeTag).font(.caption2.bold()).tracking(0.6)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .overlay(Capsule().strokeBorder(scopeTag == "OVERRIDE" ? Theme.sceneAccent : Theme.textSecondary, lineWidth: 1.5))
                    .foregroundStyle(scopeTag == "OVERRIDE" ? Theme.sceneAccent : Theme.textSecondary)
            }
            Spacer(minLength: 0)
            Text(assignment.displayName).font(.title3.weight(.bold)).lineLimit(1).minimumScaleFactor(0.6)
            Text(StompAssignmentSummary.message(assignment))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(assigned ? Theme.textPrimary : Theme.textSecondary)
            Text(StompAssignmentSummary.behavior(assignment) ?? "Tap to assign")
                .font(.caption).foregroundStyle(Theme.textSecondary).lineLimit(1)
        }
        .padding(Theme.Spacing.gutter)
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .leading)
        .themedCard(raised: assigned, dashed: !assigned)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Stomp \(assignment.slot), \(assignment.displayName), \(StompAssignmentSummary.message(assignment)), \(scopeTag == "OVERRIDE" ? "override" : "global"). Opens editor.")
    }
}

struct RecoveryBanner: View {
    let notice: RecoveryNotice
    let dismiss: () -> Void
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Your saved controls could not be used", systemImage: "exclamationmark.triangle.fill")
                .font(.headline).foregroundStyle(Theme.warning)
            Text("\(notice.reasonText) Controls were reset to defaults. The original file was preserved, not deleted:")
                .font(.subheadline)
            Text(notice.backup.path)
                .font(.system(.footnote, design: .monospaced)).textSelection(.enabled)
                .foregroundStyle(Theme.textSecondary)
            HStack(spacing: Theme.Spacing.gutter) {
                Button(copied ? "Path copied" : "Copy path") {
                    UIPasteboard.general.string = notice.backup.path; copied = true
                }
                Button("I understand, dismiss", action: dismiss).accessibilityIdentifier("recovery-dismiss")
            }
            .buttonStyle(.bordered)
        }
        .padding(Theme.Spacing.gutter)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.warning.opacity(0.14), in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).strokeBorder(Theme.warning, lineWidth: 2))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("recovery-banner")
    }
}

struct StorageProblemBanner: View {
    let message: String
    let retry: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Controls storage unavailable — editing is disabled", systemImage: "xmark.octagon.fill")
                .font(.headline).foregroundStyle(Theme.error)
            Text(message).font(.subheadline)
            Button("Try again", action: retry).buttonStyle(.bordered)
        }
        .padding(Theme.Spacing.gutter)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.error.opacity(0.14), in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).strokeBorder(Theme.error, lineWidth: 2))
    }
}
