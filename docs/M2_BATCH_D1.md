# M2 Batch D1 — Stomp MIDI execution foundation

Base: `33c05af`. **Local, uncommitted.** Execution layer and tests only. **No UI is connected to it: Performance stomps stay disabled and show “NOT ACTIVE YET”,
Performance shows global assignments only, Scenes are untouched, and launch, loading, editing, saving, destination selection and reconnect send nothing.**
No C1 schema, C2/C2.1 editor, CoreMIDI transport or M1 preset behaviour changed.

## Control Change encoding (`MIDICommand`)
`MIDICommand.controlChange(channel:controller:value:)` → `[0xB0 | (channel − 1), controller, value]`. Channel 1–16, controller 0–127, value 0–127 are validated before conversion
(`MIDIValidationError.invalidChannel / invalidController / invalidValue`). Program Change bytes are unchanged and no Bank Select is ever added implicitly.

## Shared send path (`MIDIConnectionManager`)
One manager and one transport serve presets and stomps. The manager now conforms to `MIDICommandSending`:
- `send(_:to:) -> CommandSendResult` with `SendTarget` = `.selected` or `.destination(id:name:)`. Result is `.sent(CommandSendReceipt)` or `.failed(CommandSendFailure)`
  (`transportUnavailable`, `invalidCommand`, `noDestinationSelected`, `destinationUnavailable`, `transportRejected`). Nothing is queued; a failure sends nothing.
- `selectedDestination()` returns the selected destination only while it is available.
- `sendProgramChange(program:)` (the M1 preset path, using the connection screen's channel) is untouched, as is the transport's `onSetupChanged` hook.

### Diagnostics
Command sends update `lastCommandRecord` / `lastCommandFailure` only. Preset sends still own `lastTransmission` / `lastError`, so a CC can never change the preset readout
(tested through `PerformancePresentation`). “Sent” means the bytes were handed to CoreMIDI, not that the Anagram received or acted on them; no hardware-confirmed state exists.

## Executor (`StompExecutor`, `MIDI/StompExecutor.swift`)
Independent of SwiftUI and storage. Callers pass an already-resolved `StompAssignment`; the executor validates it with `AssignmentValidator` and never sends if it is invalid or has unacknowledged warnings.
`activate(_:)` and `release(slot:)` return an `ExecutionOutcome` (`sent`, `skippedUnassigned`, `rejected`, `failed`, `ignored`).
- **Unassigned:** sends nothing.
- **Program Change:** one message on the assignment's channel, M1 numbering.
- **Fixed value / device toggle:** the same value on every activation; device toggle keeps no state.
- **Value toggle:** first activation sends ON; the next sends OFF, and so on. The state advances only after a successful send, is kept per slot, and resets if that slot's assignment changes.
  It records only what this session last sent (`StompLocalToggleState`), never device state.
- **Momentary:** press sends the press value to the destination resolved at press time and records the assignment values and that destination. Release uses the captured values and destination,
  never the current selection; if it is gone the release fails and nothing is sent elsewhere. A duplicate press and a release without a press are ignored; a failed press records nothing.
  The held record is cleared by any release attempt, so a failed release is never retried or replayed on reconnect.
- **Channel:** always the assignment's own; the connection screen's preset channel is never applied to stomps.
- Runtime state (toggles, held presses) is in memory only; `resetRuntimeState()` clears it. The storage schema is unchanged.

## Lifecycle policy required before D3 (not implemented)
D1 does no background cleanup sends. Before momentary stomps are wired to touch, D3 must decide and test: what happens to held presses on touch-cancel, app backgrounding, sheet presentation
(e.g. opening Edit), destination change or disconnect, and app termination (a lost release can leave the Anagram holding the press value). Candidate policy: on any of those events call
`resetRuntimeState()` after attempting a release to the captured destination, and surface a failure visibly. Also decide how the active hardware preset is chosen for override resolution (D1 never infers it),
how failures are shown without touching the preset readout, and whether toggle state should be reset on destination change.

## Tests
`MIDICommandTests` (CC bytes, boundaries, invalid input, unchanged PC), `MIDICommandSendingTests` (manager send path, destinations, failures, diagnostics separation, setup callback),
`StompExecutorTests` (every behaviour, channels, failures, momentary pairing, destination changes, no replay, validation and acknowledgement gating, UI isolation via source scan).
Unit tests do not establish touch, VoiceOver, large-text or hardware correctness.

## Risks
- Anagram toggle, momentary and CC semantics remain hardware-unverified.
- A lost momentary release is possible until the D3 lifecycle policy exists.
- Value-toggle local state can diverge from the device if it is changed elsewhere.
