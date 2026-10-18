# M2 Batch A — Performance UI foundation

Base: M1 `14cd06d`. Local branch `feature/m2-performance-ui` (uncommitted). Layout and design system only.
**Scene MIDI mappings and stomp assignments are NOT implemented.** No new MIDI command, CC encoding or transport change exists in this batch.

## Component hierarchy
```
PerformanceView (@StateObject ConnectionViewModel)
 ├─ header: title · connection pill (opens sheet) · NavChip ×4
 │            Presets / Tuner / Edit = disabled "LATER"; Connection = opens sheet
 ├─ presetBar: PRESET readout (last SENT, never "confirmed") · PresetShortcutButton 01A / 01B
 ├─ HStack: sceneRail (SceneButton ×3, disabled) | stompGrid (StompButton ×6, 3×2, disabled)
 ├─ statusStrip: last sent text · "Error: …" (always inline, never a modal)
 └─ sheet: ConnectionSettingsView (destination, channel 1–16, rescan, diagnostics — the M1 controls)
```
Files: `App/Theme.swift` (tokens), `Features/Performance/{PerformanceView,PerformanceComponents,PerformancePresentation}.swift`,
`Features/Connection/ConnectionSettingsView.swift` (replaces `ConnectionView.swift`).

## Functional vs placeholder
| Control | Status |
|---|---|
| Preset 01A / 01B | **Functional** — `ConnectionViewModel.sendPreset(1/2)`, identical bytes to M1 (`C0 00` / `C0 01` on ch 1); disabled when no destination |
| Connection pill / Connection chip → sheet | **Functional** (destination, channel, rescan, diagnostics, errors) |
| Scene A/B/C | Placeholder, disabled, "NOT CONFIGURED", never show device state |
| Stomp 1–6 | Placeholder, disabled, "UNASSIGNED"; label/accent/local/confirmed fields reserved in `StompPresentation` |
| Presets, Tuner, Edit | Disabled, marked LATER |

The preset readout shows only what the app last *sent* ("Last sent · not confirmed by device"); no preset names are invented.
A failed send does not change the readout. CoreMIDI-initialisation errors remain visible (status strip + connection pill).

## Responsive approach
Pure SwiftUI stacks with flexible frames (`maxWidth/maxHeight: .infinity`), no absolute coordinates. Scene rail 160–220 pt wide;
stomp grid fills the rest. Budget at 1080×744: margins 48 + header ~64 + preset bar ~88 + status ~40 + 3 gutters 48 ⇒ ~456 pt content ⇒
scene buttons ≈141 pt, stomp rows ≈220 pt (≥ 60 pt minimum, `Theme.minTouch`). Dynamic Type capped at `.xxxLarge`; labels use
`minimumScaleFactor`; status text limited to 2 lines. Landscape-only, iPad-only (unchanged project settings). Not yet visually verified on any device size.

## Tests (`PerformancePresentationTests`, 12)
Placeholders disabled/non-transmitting; building presentations and unplug/replug send nothing; preset shortcuts = 01A/01B with M1 bytes;
channel 16 applies; no-destination, connected, disconnected mapping; readout "not confirmed"; send-failure and init-failure errors visible.

## Limitations
- SwiftUI view rendering, taps, layout at the four sizes, and sheet behaviour are **untested** (no UI tests; a mock-transport launch hook was not added — needs approval).
- Compilation and the full suite are unverified until CI runs.
- Idle timer is **not** disabled; deciding to do so (stage-safety) is deferred for approval.
- Edit is unavailable, so there is no unlock/lock mechanism yet.

## Remaining M2 dependencies
Batch B (scenes) needs verified CC107 semantics/values (manual: CC107 selects scenes, slot interpretation still to validate on hardware).
Batches C/D (stomp model, editor, execution) must account for Value vs Toggle logic modes and must not assume six fixed CCs (CC17–19 are default bindings only).
M1 hardware validation (preset offset) is still pending.
