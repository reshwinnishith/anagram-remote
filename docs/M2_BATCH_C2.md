# M2 Batch C2 — Stomp configuration UI

Base: C1 `0bfd1e6` on `feature/m2-performance-ui`. **Local, uncommitted.**
**Stomp MIDI execution is NOT implemented.** Nothing in C2 sends MIDI: stomps remain inert, Scenes remain placeholders,
there is no Test Send, and no send happens when opening, editing, saving, resetting or changing presets.
No change to `MIDICommand`, the CoreMIDI transport, or the M1 preset buttons.

## Navigation and UX
```
Performance (default, unchanged layout)
 └─ Edit  ──confirm "Edit controls?"──►  Edit Controls (full-screen cover, separate from live controls)
        ├─ scope: [Global defaults | Per-preset override + Preset menu 1–126]
        ├─ 3×2 overview: label · accent ring + number · message · behaviour · GLOBAL/OVERRIDE tag
        ├─ recovery / storage banners (top, persistent)
        └─ tap a stomp ► Stomp editor (Cancel / Save)
```
**Entry decision:** a deliberate two-step (tap *Edit*, then confirm *Edit Controls*) instead of hold-to-edit. A long press is easy to miss with
gloves/VoiceOver/Switch Control and hard to discover; the confirm dialog is equally deliberate, accessible and testable.
**Preset scope:** the preset is chosen by the user in a menu (default 1). It is never inferred from the last-sent preset or hardware.
The Performance screen shows **global** assignments only, for the same reason.

## Responsive editor layout (C2.1)
`StompEditorView` is a fixed navigation bar (**Cancel · “Stomp N — label” · Save**) over a compact context bar and either:
- **Two columns** (available width ≥ 720 pt and text size ≤ xxLarge — every iPad landscape): **left** = label, accent (compact swatch row + selected colour name), message type, channel, controller/program number;
  **right** = behaviour and its values, safety warnings with acknowledgements, and the “Anagram must be set up to respond” note. Each column is its own scrolling `Form`.
- **One column** below that width or at larger text sizes (left sections, then right sections; vertical scroll only, no horizontal scrolling). The decision is `StompEditorLayout.usesTwoColumns` (unit-tested).
On an iPad mini in landscape the Control Change editor, including values and the warning card, fits without scrolling.
The old banner is replaced by a one-line **GLOBAL** / **OVERRIDE · Preset 01B** / **NEW OVERRIDE** indicator; *Reset to Global…* sits at its right edge for existing overrides. Save errors show persistently in the same bar.

## Editing an assignment
Label (≤16 chars, whitespace normalised, empty shows “Stomp N”), accent (8 named swatches, text + colour), message type (Unassigned / Control Change / Program Change), channel 1–16.
- **Control Change:** controller 0–127 and one behaviour — *Value toggle* (ON/OFF values), *Device toggle* (one nonzero trigger), *Momentary* (press/release), *Fixed value*.
  The text explains each and says neither toggle mode works on every setup; 127/0 is only a starting suggestion.
- **Program Change:** 1–126 (M1 numbering), trigger-only.
Footer text states that the Anagram must be configured to respond and that nothing is sent while editing.

## Validation and safety
`StompEditorDraft` is a pure draft; empty numeric fields are “missing”, not zero. It builds a placeholder assignment and runs **`AssignmentValidator`** (C1) — rules live only there;
`DraftField` just routes each error to its field for inline display. **Save is disabled** while any field has an error, is missing, a warning is unacknowledged, the draft is unchanged, or storage is unavailable.
Warnings come from C1 (one per controller): channel-mode CC 120–127, Bank Select CC 0/32, and Anagram-reserved CCs (0, 7, 14–32, 85–87, 89, 102–119).
Each shows `SafetyWarning.title/explanation` and a toggle “I understand and want to use this controller”. Stale acknowledgements are dropped when the controller changes.

## Save / Cancel
The editor works on a copy. **Cancel** discards it (confirmation if there are unsaved changes; swipe-dismiss is disabled while dirty; the back button is hidden so Cancel is the only exit).
**Save** → `StompConfigModel.save` → `AssignmentStore.save` (validates, atomic write). The in-memory profile changes **only after the write succeeds**; on failure the editor stays open with a persistent red message
and `lastSavedAt` is not updated, so the UI never claims an unsaved success. Overview shows “Last saved HH:MM” only after a real save.

## Overrides
In *Per-preset override* scope, saving a slot creates a whole-slot override for the chosen preset (the editor starts from the resolved assignment). Cards are tagged OVERRIDE or GLOBAL (text, not colour only).
Setting the type to Unassigned saves an **explicit Unassigned override**. **Reset to Global…** (with confirmation) removes the override. Unassigned global slots are shown dashed.

## Persistence and recovery UX
The model loads through `AssignmentStore` at startup (outside view bodies) and exposes:
- **Recovery banner** (amber, top of Edit Controls) when an unusable file was replaced: reason, the preserved backup path (selectable + *Copy path*), and an explicit *I understand, dismiss* button.
  It is never auto-dismissed; saving, editing or reloading do not clear it. After a relaunch only a quiet “N preserved backup files exist” line remains (C1's `backupURLs()`).
- **Storage-problem banner** (red) if the store cannot be read safely (e.g. backup failed): editing and saving are disabled so defaults can never overwrite unread data; *Try again* reloads.
Production storage is `Application Support/AnagramRemote`. Simulator builds only (`#if targetEnvironment(simulator)`) honour `ANAGRAM_STOMP_DIR` to redirect storage for demos/screenshots; it does not exist in device builds.

## Performance view integration
Layout from Batch A.1 is kept; an **Edit** button was added beside Connection. Stomp tiles show the configured label, accent ring, and `CC 80 · Ch 1` / `PC 12 · Ch 1`, plus **“NOT ACTIVE YET”**;
unassigned tiles keep “UNASSIGNED”. All stay inert (dashed, hollow LED, no ON/OFF or confirmed state).

## Files
New: `Features/StompConfig/{StompEditorDraft, StompAssignmentSummary, StompAccentColor, StompConfigModel, StompConfigView, StompEditorView}.swift`;
tests `StompEditorDraftTests`, `StompConfigModelTests`, `StompPerformanceIntegrationTests`.
Modified: `PerformanceView`, `PerformanceComponents`, `PerformancePresentation` (display only), `Tools/generate_xcodeproj.py` + regenerated `project.pbxproj` (file registration only).

## Tests
Draft validation and field routing, every action round-trip, boundaries, advanced acknowledgement (and stale-ack removal), save/cancel semantics, global/override/explicit-Unassigned/reset flows,
refusal of incomplete/invalid/unacknowledged drafts with the file untouched, store write failure and recovery-from-failure, recovery notice persistence, storage-problem lockout,
no-MIDI checks (source scan of `Features/StompConfig` + a live mock transport that stays empty), presentation mapping, and unchanged M1 preset bytes.

## Accessibility limitations
Layout, labels and Dynamic Type fallback are implemented but **not exercised with VoiceOver or at accessibility text sizes on screen**; the app caps text at xxxLarge, so the editor's accessibility-size path is unreachable today.
Accent swatches are 44 pt targets with text/checkmark selection, but their names are only announced, not shown, except the selected one.

## Known limitations
- Follow-up UX review: the editor repeats that stomps are inactive and that behaviour descriptions refer to future MIDI execution. Its context bar explains unchanged drafts, invalid fields, unacknowledged warnings and unavailable storage; Save also exposes this status as an accessibility hint. Overview scope badges use a stronger outline. These refinements do not change save validation or MIDI behaviour.
- No interactive/UI automation: the views were rendered and reviewed as screenshots but taps, VoiceOver and Dynamic Type were **not exercised** on screen.
- The Preset menu lists 126 entries; presets other than 01A/01B are labelled “P3…”, matching M1's provisional numbering.
- Real-device Application Support, concurrent writers and disk-full are untested. Anagram toggle semantics, reserved-CC behaviour and Program numbering remain hardware-unverified.
- Per-controller Anagram defaults / dedicated functions for reserved CCs are not recorded, so none are shown.
