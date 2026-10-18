# Anagram Remote — Milestone 1

Native SwiftUI iPad app (Apple frameworks only) that sends MIDI Program Change to a Darkglass Anagram over USB MIDI.
M1 scope only: destination list/picker, channel 1–16, Preset 01A / 01B buttons, send diagnostics, safe unplug/replug.

## Build on the MacBook Pro
1. `open AnagramRemote.xcodeproj` (Xcode 15+, iOS 16+ target, iPad only).
2. Select the `AnagramRemote` target → Signing & Capabilities → choose your Team
   `com.reshwinnishith.anagramremote` to one you own.
3. Run unit tests: Product → Test (⌘U) on any iPad simulator. Or:
   `xcodebuild test -project AnagramRemote.xcodeproj -scheme AnagramRemote -destination 'platform=iOS Simulator,name=iPad (10th generation)'`
4. Run on the USB-C iPad (connected via powered hub to the Anagram).

If the project file ever needs rebuilding after adding files: `python3 Tools/generate_xcodeproj.py`.

## MIDI mapping (UNVERIFIED on hardware)
Program Change status = `0xC0 | (channel-1)`, one data byte. UI program N → data byte N-1:
- Preset 01A = program 1 → `C0 00` (channel 1)
- Preset 01B = program 2 → `C0 01` (channel 1)

The offset lives only in `ProgramNumbering.dataByteOffset` (`AnagramRemote/MIDI/MIDICommand.swift`). No Bank Select is sent.
Nothing is ever sent on launch, reselect, or reconnect — only on a button tap.
"Last transmitted" means handed to CoreMIDI, not confirmed by the Anagram.

## Inspecting MIDI on macOS
- Use **MIDI Monitor** (snoize.com) or Audio MIDI Setup → MIDI Studio. To test without the pedal on a Mac/iPad-simulator-free setup,
  create a virtual destination (e.g. with MIDI Monitor, or an IAC Driver bus enabled in Audio MIDI Setup) and select it in the app
  running on a device/Mac that can see it. On the iPad, a USB-connected Mac does not expose destinations by default; use the Anagram itself and
  check the preset change on its display.

## CI and unsigned IPA
GitHub Actions (`.github/workflows/ios-build.yml`) builds for the iPad simulator, runs the unit tests, and builds an
**UNSIGNED** device IPA artifact. It cannot be installed without signing — see `docs/INSTALL_PREPARATION.md`.
Audit notes: `docs/M1_AUDIT.md`. The PC 1→0 / PC 2→1 mapping remains **provisional until tested on the Anagram**.
