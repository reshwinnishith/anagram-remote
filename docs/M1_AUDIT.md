# M1 audit (static review at commit 03b0773 + packaging changes)

Method: source/config/workflow review plus CI results from run 39101128122. No hardware, no local Xcode.

| Sev | Area | Finding | Suggested fix |
|---|---|---|---|
| Medium | `CoreMIDITransport.swift` | `MIDIClientCreateWithBlock` / `MIDIOutputPortCreate` OSStatus ignored; a failure surfaces only later as a send error. | Check statuses; expose a transport-init error in diagnostics. |
| Medium | `MIDIConnectionManager.swift` | Selection keyed by CoreMIDI unique ID. If the Anagram re-enumerates with a different ID after replug, state stays "Disconnected" until re-selected (never sends). | Verify on hardware; if it happens, add name-based re-match (changes behaviour — needs approval). |
| Low | Client/port lifecycle | Client and port are never disposed. Acceptable (single app-lifetime instance) but undocumented. | Add `deinit` disposal if the transport ever becomes non-singleton. |
| Low | `MIDIConnectionManager.swift` | `lastError` is not cleared on re-select/channel change; stale error can persist until next successful send. | Clear on successful state changes. |
| Low | UI | Rapid double-tap sends twice (each tap is an explicit user action; no state-driven resends exist). | Optional short debounce if hardware shows it matters. |
| Low | `CoreMIDITransport.swift` | `send` re-enumerates endpoints per call (fine at this rate). | None. |
| Info | MIDI semantics | PC 1 → wire 0, PC 2 → wire 1 and range 1–126 are provisional/unverified; manual not read. | Hardware test. Tripwire test added. |
| Info | Config | iPad-only (`TARGETED_DEVICE_FAMILY=2`), landscape-only, iOS 16. Landscape-only on iPad requires full-screen; `UIRequiresFullScreen` added so Xcode/App Store validation does not demand all orientations. | — |
| Info | Reproducibility | `.pbxproj`/scheme generated deterministically (CI checks no diff). Xcode version is the runner default (16.4 on macos-15), not pinned. | Pin if a runner image change breaks the build. |
| Info | Coverage | 15 tests cover encoding, validation, no-destination, removal/reconnect, no auto-send. Added: transport failure, unknown destination, offset tripwire. `CoreMIDITransport` and SwiftUI views are untested (need hardware/UI tests). | — |
