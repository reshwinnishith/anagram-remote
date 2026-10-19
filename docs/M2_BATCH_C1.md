# M2 Batch C1 — Programmable stomp assignment foundation

Base: Batch A.1 `44f6d51` on `feature/m2-performance-ui`. **Local, uncommitted.**
Pure data, validation and persistence for six freely assignable MIDI stomps. **Nothing here sends MIDI, and the
Performance UI is unchanged** (stomps stay inert placeholders). No M1 code (`MIDICommand`, CoreMIDI transport,
`ProgramNumbering`) was modified; C1 only *reads* `ProgramNumbering`'s channel/program ranges so there is one source of truth.

## Files (`AnagramRemote/Stomps/`)
| File | Role |
|---|---|
| `StompModels.swift` | `StompAssignment`, `StompAction`, `CCBehavior`, `ToggleMode`, `SafetyWarning`, `StompAccent`; explicit Codable |
| `AssignmentValidator.swift` | `AssignmentValidator`, `ValidationError`, `SafetyPolicy`, `AssignmentReport`, `ProfileReport` |
| `StompProfile.swift` | `StompProfile` (6 globals + `PresetOverride`s), deterministic resolution and mutation |
| `AssignmentStore.swift` | Versioned JSON persistence, recovery, `LoadOutcome`, `StoreError` |

Foundation only; the files import no CoreMIDI and reference no transport (a unit test enforces this).
New files were added by editing and re-running `Tools/generate_xcodeproj.py` (the project is generated); the diff only adds entries.

## Data schema (schema version 1)
```
{ "schemaVersion": 1,
  "profile": {
    "globalSlots": [ StompAssignment ×6, slot 1…6 in order ],
    "overrides":   [ { "preset": 1…126, "assignments": [ StompAssignment … ] } ] } }

StompAssignment { slot 1…6, name (≤16 chars after normalisation, "" = show "Stomp N"),
                  accentID (blue|violet|pink|orange|yellow|green|teal|silver),
                  action, acknowledgedWarnings [channelModeController|bankSelect|anagramReserved] }

action: { "kind":"unassigned" }
      | { "kind":"controlChange", channel 1…16, controller 0…127, behavior }
      | { "kind":"programChange", channel 1…16, program 1…126 }          // trigger-only

behavior: toggleValues  {on, off}        0…127 each, on ≠ off — app tracks local state, alternates on/off
          toggleDevice  {trigger}        1…127 — same nonzero value each press; the device flips its own state
          momentary     {press, release} 0…127 each, press ≠ release
          fixed         {value}          0…127
```
JSON uses explicit `kind` discriminators rather than compiler-synthesised enum coding, so the on-disk format does not depend on the Swift version.
`accentID` is a string so an unknown id decodes and is reported by the validator instead of corrupting the whole file.
Overrides are stored as arrays (not Int-keyed dictionaries, which Codable would emit as flat alternating arrays) and are sorted for deterministic output.

## Validation and safety policy
`AssignmentValidator` is pure and centralised. **Hard errors** (`ValidationError`) can never be acknowledged: slot ≠ 1…6 or out of position,
channel ≠ 1…16, controller or value outside 0…127, program outside 1…126 (M1's user-facing convention, offset untouched),
Toggle trigger of 0, identical ON/OFF or press/release values, unknown accent, name > 16 characters, ≠ 6 global slots,
override preset outside 1…126, duplicate override presets or slots.

**Warnings** (`SafetyWarning`) are valid MIDI that need an explicit per-assignment acknowledgement stored in `acknowledgedWarnings`.
A controller raises **at most one** warning (most specific first), so notices never overlap or contradict:
- `channelModeController` — CC 120–127 (channel-mode messages). Protected against accidental assignment, not banned.
- `bankSelect` — CC 0 and 32 (Bank Select). Both are also Anagram-reserved; they get this single warning, whose text mentions the reservation.
- `anagramReserved` — the remaining controllers the Anagram manual lists as **reserved from custom binding assignment**:
  7, 14–31, 85–87, 89, 102–119 (the full manual list is 0, 7, 14–32, 85–87, 89, 102–119; `SafetyPolicy.manualReservedControllers`).

Anagram custom-binding restrictions are **not** MIDI protocol invalidity: a reserved controller is valid to send and is never a hard error.
The warning text says it cannot trigger a custom binding and may be tied to a dedicated function or default on the Anagram.
**The manual's per-controller defaults and dedicated functions are not recorded in this repo, so none are named; this is an open documentation item.**
Warning titles/explanations live on `SafetyWarning` so every screen uses the same wording.

`AssignmentReport.isValid` = no hard errors; `isAcceptable` = valid **and** every triggered warning acknowledged. Persistence requires `isAcceptable`.
Whitespace is trimmed and collapsed (`StompAssignment.normalizedName`); length is measured after normalisation.

## Global / override resolution
`StompProfile.resolved(slot:preset:)`: an override for that preset **and** slot wins (even if `.unassigned`); otherwise the global slot applies.
`preset: nil` means global only. Whole-slot overrides only. `resetToGlobal(preset:slot:)` deletes the override (and drops the preset entry once empty).
The app never infers the hardware's active preset — the caller supplies it (e.g. the last preset the app sent, which the UI already labels "not confirmed by device").
Mutators change structure only; validate before persisting (`AssignmentStore.save` does).

## Persistence and recovery
`AssignmentStore(directory:)` — directory injected (tests use a temp folder); production uses `defaultDirectory()` = `Application Support/AnagramRemote/stomp-assignments.json`.
- **Missing file:** safe defaults (six unassigned) are written; outcome `.createdDefaults`.
- **Save:** validates + normalises, then `Data.write(options: .atomic)`. Invalid or unacknowledged profiles are refused and the existing file is untouched.
- **Load:** a valid file is returned without being rewritten.
- **Unusable file** (invalid JSON, wrong shape, failed validation, unacknowledged warning, newer or unsupported schema): the original is **moved, never deleted**,
  to `stomp-assignments.invalid-<UTC timestamp>[-n].json` (unique, so earlier backups are never overwritten), then defaults are written and
  `.recoveredWithDefaults(profile, backup:, reason:)` is returned so a UI can tell the user. A valid profile is never replaced or backed up.
  Because the *next* load is clean, a UI must retain the recovery notice itself and may also list `AssignmentStore.backupURLs()`.
  **C2 must display recovery prominently and persistently** (see `docs/M2_BATCH_C2.md`). If the backup move fails, nothing is overwritten and `StoreError.backupFailed` is thrown.
- **Migration:** `AssignmentStore.migrate(_:from:)` is the single hook. Version 1 is current; each future schema adds one case rewriting N → N+1.
  Versions below 1 are unsupported; **newer** versions are treated as incompatible and preserved as a backup rather than guessed at.
- Loading and saving never transmit MIDI.

## Toggle logic and state
Both interpretations are modelled because the Anagram's behaviour is unverified: `toggleValues` (explicit ON/OFF, any values — 127/0 is **not** assumed)
and `toggleDevice` (one nonzero trigger). The Anagram is **not** assumed to send state feedback. Runtime state is deliberately not stored:
the future execution layer should keep *local* state (what the app last sent) separate from *device-confirmed* state
(the reserved `StompLocalState` / `StompConfirmedState` in `PerformancePresentation.swift`), and never persist or display local state as confirmed.

## Future work
- **C2 (editor):** UI over `StompAssignment`, showing `AssignmentReport` errors/warnings and an acknowledgement step; use `LoadOutcome` to surface recovery.
  Needs a view model that owns an `AssignmentStore`.
- **D (execution):** map a stomp press to `MIDICommand`-style bytes. CC needs a new command case and encoder, which C1 deliberately does not add.
  PC must reuse M1's `ProgramNumbering` so encoding stays single-sourced.

## Known limitations / hardware-dependent assumptions
- Anagram toggle semantics, Bank Select behaviour and whether CC 120–127 are honoured are **unverified on hardware**. The reserved list comes from the manual as relayed by the project owner.
- Program 1–126 and its zero-based wire offset remain M1's unverified assumption.
- Preset override keys are 1–126 and assume a preset *is* its program number.
- `StompProfile.slotCount` (6) is defined separately from the UI's `PerformanceLayout.stompCount`; keep them in step if the grid ever changes.
- Not covered by tests: real Application Support on device, concurrent writers, disk-full conditions.
