# M2 Batch D2 — Discrete stomp performance controls

Base: `8505be3`. **Local, uncommitted.** Performance stomps now send MIDI for four action types. **Momentary stomps and Scenes remain disabled** (momentary is D3).
No change to C1 models/schema/validation, the C2 editor flows, M1 preset mapping or the CoreMIDI transport.

## What is active
| Assignment | Performance tile | Sends on each tap |
|---|---|---|
| Fixed-value CC | enabled | one CC with the configured value |
| Value-toggle CC | enabled | ON first, then OFF, alternating only after successful sends |
| Device-toggle CC | enabled | the same configured nonzero trigger |
| Program Change | enabled | one Program Change (M1 numbering) |
| Momentary CC | disabled: “MOMENTARY NOT ACTIVE YET” | nothing |
| Unassigned | disabled: “UNASSIGNED” | nothing |

A tile is enabled only if its assignment is valid with all warnings acknowledged, configuration storage is available, and the selected destination is ready. Otherwise it is disabled with
“NOT ACTIVE · STORAGE UNAVAILABLE / CHECK SETTINGS / NO DESTINATION”. Each tap is one native `Button` action → one `activate`, with no gesture handlers. Stomps use the **assignment's** channel;
the connection screen's channel still governs only the M1 preset shortcuts. Performance resolves **global** assignments only; editor preset selection and the last-sent preset never activate overrides.

## Architecture
- `PerformanceCore` (created once by a `@StateObject`) owns the single `MIDIConnectionManager`, `ConnectionViewModel`, `StompConfigModel` and `StompPerformanceController`. `PerformanceContent` observes them, so redraws never recreate the executor or the transport.
  The view model's `onChange` callback and the transport's setup callback are unchanged.
- `StompPerformanceController` (`MIDI/`) wraps `StompExecutor` (shared manager via `ConnectionViewModel.manager`), builds `StompTile`s, activates a slot, and publishes the last stomp send and failure.
  Tile construction and views never send; only `activate(slot:)` does.
- `StompExecutor.resetToggleState()` was added (momentary handling is untouched).

## Local toggle state and resets (no MIDI is ever sent by a reset)
The state is session-only memory and is described as “LOCAL: NOT SENT YET / LAST SENT ON / LAST SENT OFF” — never as confirmed device state; an unknown state does not look like OFF.
All toggle state is reset when: the selected destination id or its connected/disconnected status changes; any slot's effective action (global profile) changes — compared against the previous snapshot on every profile change, so A → B → A resets twice even if B was never used;
the app resigns active or enters the background. Not reset by: label/accent-only edits, other fields, unchanged destination refreshes, channel changes, diagnostics publishing, redraws, or override edits.
The first activation after a reset sends ON. Nothing is queued or replayed on reconnect.

## Feedback
- Enabled tiles use a solid raised card and an accent bar; disabled tiles stay dashed. LEDs stay hollow (no inferred ON state).
- Status strip: preset-shortcut line (“No preset shortcut sent this session.” / “Preset shortcut: Program Change 2 on ch 1 → … — handed to CoreMIDI, not device-confirmed”), **last stomp send** (“… handed to CoreMIDI, not confirmed by the Anagram”) and a red **stomp failure** line.
  A failure never alters toggle state or the preset readout and is cleared by the next successful stomp send. Preset errors remain a separate line.
- The readout tracks **only the M1 preset shortcuts (01A/01B)**, so it is labelled “LAST SHORTCUT SENT”; its subtitle reads “Preset shortcut history · not confirmed by device” (or “… none sent yet · not confirmed by device”),
  and its accessibility label is “Last preset shortcut sent: …”. A stomp Program Change never changes it; it is recorded in the separate stomp send line (regression-tested: shortcut 01B then stomp PC 12 leaves 01B in place).
- Accessibility: each tile has a label (“Stomp name, CC 80 · Ch 1”), a value (the local-state wording) and a hint (what a double tap sends, “Not confirmed by the Anagram”); disabled tiles say why.
- The editor footer no longer says stomps are inactive; it states that editing never sends MIDI and that Performance ignores preset overrides for now.

## Verification boundaries
- **Unit tests:** controller behaviour, resets, diagnostics separation, disabled states, no automatic or replayed sends, unchanged M1 bytes.
- **Simulator:** the real app was launched on the iPad mini (iOS 18.3); it has no MIDI destinations, so tiles show disabled “NO DESTINATION”. Connected, after-send and failure states were rendered by a temporary harness (since removed).
  Simulated touch is not available in this environment, so no tap, repeated-activation or press-feedback interaction was exercised.
- **Not verified:** VoiceOver, large Dynamic Type, real hardware behaviour (toggle/momentary semantics, CC acceptance).

## Remaining D3 work
Momentary press/release with the lifecycle policy in `docs/M2_BATCH_D1.md`; an explicit way to choose preset context for overrides; Scene commands; reconsidering whether toggle state should reset on editing the destination list; device testing.
