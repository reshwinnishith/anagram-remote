import SwiftUI

/// Chooses the editor arrangement. Pure so it can be tested.
enum StompEditorLayout {
    /// Minimum available width for two columns (each column then gets about 340 pt or more).
    static let twoColumnMinWidth: CGFloat = 720

    /// Two columns on wide landscape iPads at normal text sizes; otherwise one accessible column (no horizontal scrolling).
    static func usesTwoColumns(width: CGFloat, typeSize: DynamicTypeSize) -> Bool {
        width >= twoColumnMinWidth && typeSize <= .xxLarge
    }
}

/// Edits one stomp. Works on a draft; the stored profile changes only when Save succeeds.
///
/// Landscape: left column = what the stomp is (label, accent, message, channel, number);
/// right column = how it behaves and what to check (behaviour, values, safety warnings).
struct StompEditorView: View {
    @ObservedObject var model: StompConfigModel
    let slot: Int
    let scope: StompEditorDraft.Scope

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var draft: StompEditorDraft
    @State private var original: StompEditorDraft
    @State private var saveError: String?
    @State private var confirmDiscard = false
    @State private var confirmReset = false

    init(model: StompConfigModel, slot: Int, scope: StompEditorDraft.Scope) {
        self.model = model; self.slot = slot; self.scope = scope
        let d = model.draft(slot: slot, scope: scope)
        _draft = State(initialValue: d); _original = State(initialValue: d)
    }

    private var report: DraftReport { draft.evaluate() }
    private var isDirty: Bool { draft != original }
    private var saveStatus: String {
        if !model.canEdit { return "Saving unavailable: controls storage needs attention." }
        if !report.fieldErrors.isEmpty || !report.missing.isEmpty { return "Complete or correct the highlighted fields to save." }
        if !report.unacknowledged.isEmpty { return "Acknowledge the controller warnings to save." }
        return isDirty ? "Unsaved changes" : "No changes to save"
    }
    private var presetNumber: Int? { if case .preset(let p) = scope { return p } else { return nil } }
    private var title: String {
        let n = StompAssignment.normalizedName(draft.name)
        return n.isEmpty ? "Stomp \(slot)" : "Stomp \(slot) — \(n)"
    }

    var body: some View {
        VStack(spacing: 0) {
            contextBar
            GeometryReader { geo in
                if StompEditorLayout.usesTwoColumns(width: geo.size.width, typeSize: typeSize) {
                    HStack(alignment: .top, spacing: 0) {
                        column { assignmentSections }
                        column { behaviourSections }
                    }
                } else {
                    column { assignmentSections; behaviourSections }
                }
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .interactiveDismissDisabled(isDirty)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { if isDirty { confirmDiscard = true } else { dismiss() } }
                    .accessibilityIdentifier("editor-cancel")
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save)
                    .disabled(!report.canSave || !isDirty || !model.canEdit)
                    .accessibilityHint(saveStatus)
                    .accessibilityIdentifier("editor-save")
            }
        }
        .confirmationDialog("Discard your changes?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Discard changes", role: .destructive) { dismiss() }
            Button("Keep editing", role: .cancel) {}
        }
        .confirmationDialog("Reset this stomp to the global assignment?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Reset to Global", role: .destructive) { reset() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("The override for this preset is removed. Nothing is sent to the Anagram.") }
    }

    /// One independently scrolling column.
    private func column<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        Form { content() }
            .scrollContentBackground(.hidden)
            .frame(maxWidth: .infinity)
    }

    // MARK: Context bar (compact Global / Override indicator, save errors)

    private var contextBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: Theme.Spacing.gutter) {
                switch scope {
                case .global:
                    tag("GLOBAL", systemImage: "globe", tint: Theme.textSecondary)
                    Text("Applies to every preset without an override.").font(.footnote).foregroundStyle(Theme.textSecondary)
                    Spacer(minLength: 0)
                case .preset(let p):
                    let isOverride = model.isOverride(slot: slot, preset: p)
                    tag(isOverride ? "OVERRIDE" : "NEW OVERRIDE", systemImage: isOverride ? "pin.fill" : "pin", tint: Theme.sceneAccent)
                    Text("Preset \(PresetLabel.text(forProgram: p))").font(.subheadline.weight(.semibold))
                    Text(isOverride ? "" : "Follows Global until saved.").font(.footnote).foregroundStyle(Theme.textSecondary)
                    Spacer(minLength: 0)
                    if isOverride {
                        Button("Reset to Global…", role: .destructive) { confirmReset = true }
                            .font(.subheadline.weight(.semibold))
                            .accessibilityIdentifier("reset-to-global")
                    }
                }
            }
            Text(saveStatus)
                .font(.footnote).foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("editor-save-status")
            if let e = saveError {
                Label(e, systemImage: "xmark.octagon.fill")
                    .font(.footnote.weight(.semibold)).foregroundStyle(Theme.error)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("save-error")
            }
        }
        .padding(.horizontal, Theme.Spacing.margin)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.border).frame(height: 1) }
    }

    private func tag(_ text: String, systemImage: String, tint: Color) -> some View {
        Label(text, systemImage: systemImage)
            .font(.caption.bold()).tracking(0.6)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .overlay(Capsule().strokeBorder(tint, lineWidth: 1.5))
            .foregroundStyle(tint)
    }

    // MARK: Left column — assignment

    @ViewBuilder private var assignmentSections: some View {
        Section {
            TextField("Label (shown on the stomp)", text: $draft.name).accessibilityIdentifier("field-name")
            fieldErrors(.name)
        } header: { Text("Label") } footer: {
            Text("\(StompAssignment.normalizedName(draft.name).count)/\(StompAssignment.maxNameLength) · empty shows “Stomp \(slot)”")
        }

        Section {
            accentRow
            fieldErrors(.accent)
        } header: { Text("Accent colour") }

        Section {
            Picker("Message type", selection: $draft.kind) {
                Text("Unassigned").tag(StompEditorDraft.Kind.unassigned)
                Text("Control Change").tag(StompEditorDraft.Kind.controlChange)
                Text("Program Change").tag(StompEditorDraft.Kind.programChange)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("field-kind")
            if draft.kind != .unassigned {
                channelPicker
                if draft.kind == .controlChange {
                    numberField("Controller number (0–127)", value: $draft.controller, id: "field-controller")
                    fieldErrors(.controller)
                } else {
                    numberField("Program number (1–126)", value: $draft.program, id: "field-program")
                    fieldErrors(.program)
                }
            }
        } header: { Text("MIDI message") }
    }

    private var accentRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                ForEach(StompAccent.ids, id: \.self) { id in
                    let selected = draft.accentID == id
                    Button { draft.accentID = id } label: {
                        Circle().fill(StompAccent.color(for: id))
                            .frame(width: 30, height: 30)
                            .overlay { if selected { Image(systemName: "checkmark").font(.footnote.bold()).foregroundStyle(.black) } }
                            .padding(5)
                            .overlay(Circle().strokeBorder(selected ? Theme.textPrimary : .clear, lineWidth: 2))
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(StompAccent.displayName(for: id)) accent")
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            Text(StompAccent.isValid(draft.accentID) ? StompAccent.displayName(for: draft.accentID) : "Unknown accent")
                .font(.footnote).foregroundStyle(Theme.textSecondary)
        }
    }

    private var channelPicker: some View {
        Picker("MIDI channel", selection: Binding(get: { draft.channel ?? 1 }, set: { draft.channel = $0 })) {
            ForEach(ProgramNumbering.channelRange, id: \.self) { Text("Channel \($0)").tag($0) }
        }
        .accessibilityIdentifier("field-channel")
    }

    // MARK: Right column — behaviour and safety

    @ViewBuilder private var behaviourSections: some View {
        switch draft.kind {
        case .unassigned:
            Section {
                Text(presetNumber == nil
                     ? "This stomp does nothing and shows as Unassigned."
                     : "Saving this makes the stomp explicitly Unassigned for this preset, even if the global default is assigned.")
                    .font(.footnote).foregroundStyle(Theme.textSecondary)
            } header: { Text("Behaviour") }
        case .programChange:
            Section {
                Label("Trigger only", systemImage: "bolt.fill").font(.headline)
                Text("Sends the Program Change each time the stomp is used, with the same numbering as the preset buttons. It cannot be switched on or off.")
                    .font(.footnote).foregroundStyle(Theme.textSecondary)
            } header: { Text("Behaviour") }
        case .controlChange:
            Section {
                Picker("Behaviour", selection: $draft.style) {
                    Text("Value toggle").tag(StompEditorDraft.CCStyle.valueToggle)
                    Text("Device toggle").tag(StompEditorDraft.CCStyle.deviceToggle)
                    Text("Momentary").tag(StompEditorDraft.CCStyle.momentary)
                    Text("Fixed value").tag(StompEditorDraft.CCStyle.fixedValue)
                }
                .accessibilityIdentifier("field-style")
                switch draft.style {
                case .valueToggle:
                    numberField("ON value", value: $draft.onValue, id: "field-on"); fieldErrors(.onValue)
                    numberField("OFF value", value: $draft.offValue, id: "field-off"); fieldErrors(.offValue)
                case .deviceToggle:
                    numberField("Toggle trigger value (1–127)", value: $draft.triggerValue, id: "field-trigger"); fieldErrors(.triggerValue)
                case .momentary:
                    numberField("Press value", value: $draft.pressValue, id: "field-press"); fieldErrors(.pressValue)
                    numberField("Release value", value: $draft.releaseValue, id: "field-release"); fieldErrors(.releaseValue)
                case .fixedValue:
                    numberField("Value", value: $draft.fixedValue, id: "field-fixed"); fieldErrors(.fixedValue)
                }
            } header: { Text("Behaviour") } footer: { Text(styleExplanation) }
        }

        if !report.warnings.isEmpty {
            Section {
                ForEach(report.warnings, id: \.self) { w in
                    VStack(alignment: .leading, spacing: 6) {
                        Label(w.title, systemImage: "exclamationmark.triangle.fill").font(.headline).foregroundStyle(Theme.warning)
                        Text(w.explanation).font(.footnote)
                        Toggle("I understand and want to use this controller", isOn: Binding(
                            get: { draft.acknowledged.contains(w) },
                            set: { on in if on { draft.acknowledged.insert(w) } else { draft.acknowledged.remove(w) } }))
                            .accessibilityIdentifier("ack-\(w.rawValue)")
                    }
                }
            } header: { Text("Check before saving") }
        }

        Section {
            Label("Stomps are not active in this version.", systemImage: "info.circle")
                .font(.footnote.weight(.semibold))
                .accessibilityIdentifier("editor-inactive-notice")
            Text("The behaviour described above applies when stomp MIDI execution is available. The Anagram must be set up to respond to this message. Editing and saving never send anything to it, and there is no test send in this version.")
                .font(.footnote).foregroundStyle(Theme.textSecondary)
        }
    }

    private var styleExplanation: String {
        switch draft.style {
        case .valueToggle:
            return "Value toggle: the app alternates between the ON and OFF values you set. It remembers what it last sent but cannot know the Anagram's real state. 127/0 is only a starting suggestion; use the values your Anagram binding expects."
        case .deviceToggle:
            return "Device toggle: the app sends the same nonzero value on every press and the Anagram flips its own state. Use this if your binding toggles on a trigger. Neither toggle mode works on every setup."
        case .momentary:
            return "Momentary: sends the press value when you touch the stomp and the release value when you lift."
        case .fixedValue:
            return "Fixed value: sends one value every time the stomp is used."
        }
    }

    // MARK: Pieces

    private func numberField(_ title: String, value: Binding<Int?>, id: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("—", value: value, format: .number.grouping(.never))
                .keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(maxWidth: 90)
                .padding(.vertical, 6).padding(.horizontal, 10)
                .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 8))
                .accessibilityLabel(title).accessibilityIdentifier(id)
        }
    }

    @ViewBuilder private func fieldErrors(_ f: DraftField) -> some View {
        ForEach(report.errors(for: f), id: \.self) {
            Label($0, systemImage: "exclamationmark.circle.fill").font(.footnote).foregroundStyle(Theme.error)
        }
    }

    // MARK: Actions

    private func save() {
        switch model.save(draft) {
        case .saved: dismiss()
        case .failed(let message): saveError = message
        }
    }

    private func reset() {
        guard let p = presetNumber else { return }
        switch model.resetToGlobal(preset: p, slot: slot) {
        case .saved: dismiss()
        case .failed(let message): saveError = message
        }
    }
}
