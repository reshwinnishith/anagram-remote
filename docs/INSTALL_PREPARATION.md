# Installation preparation (M1) — UNSIGNED IPA

## Get the IPA
GitHub → repo → **Actions** → latest "iOS build and test" run on `claude/anagram-remote-m1-pqc1jd` →
**Artifacts** → `AnagramRemote-UNSIGNED-ipa-<commit>`. It contains `AnagramRemote-unsigned.ipa` and
`UNSIGNED-IPA-PROVENANCE.txt` (commit, run link, Xcode version, SHA-256, bundle id, platform checks).
Artifacts expire after 14 days.

## Why it cannot be installed as-is
iPadOS only runs apps signed by an Apple identity with a provisioning profile that lists the device.
CI builds with `CODE_SIGNING_ALLOWED=NO` and has no certificates, profiles or Apple credentials, so the IPA is
**unsigned**. Do not try to sideload it directly; do not treat a successful CI build as an installed app.

## What is still required
1. An Apple Account (free is enough for personal testing) and a Mac with Xcode, or a signing service you trust.
2. A signing certificate + provisioning profile for bundle id `com.reshwinnishith.anagramremote`
   (Xcode creates both automatically with "Automatically manage signing").
3. The iPad registered as a development device (connect by USB-C once; enable Developer Mode on the iPad).

## Future route: free Apple Account + Mac
1. `git clone` the repo, `open AnagramRemote.xcodeproj`.
2. Target *AnagramRemote* → Signing & Capabilities → pick your personal Team.
3. If the bundle id is taken for your account, change it locally (do not commit that change).
4. Select the connected iPad → Run. On the iPad: Settings → General → VPN & Device Management → trust the developer app.

Free-provisioning limits: the app/profile expires after **7 days** (re-run from Xcode to renew), roughly 3 active
apps and 10 App IDs per week per account, no TestFlight/App Store distribution (needs the paid Developer Program).

## Hardware tests required before M1 can be called complete
Nothing below has been done; CI covers only compilation and mock-transport unit tests.
- [ ] Anagram appears in the destination picker over iPad → powered USB-C hub → Anagram USB.
- [ ] Nothing is sent at launch, on destination selection, or on replug.
- [ ] Preset 01A button → Anagram shows preset 1; 01B → preset 2. Observe the offset: **PC 1 → wire 0 and
      PC 2 → wire 1 are PROVISIONAL** (`ProgramNumbering.dataByteOffset`). Record the observed result.
- [ ] Channel 1 and 16 status bytes (`C0 xx` / `CF xx`) seen on a MIDI monitor, if available; Anagram MIDI channel matches.
- [ ] Unplug mid-session: buttons disable, status shows Disconnected, no crash. Replug: no automatic send; re-select if needed.
- [ ] Confirm the manual's preset range (1–126) — the manual was not read during development.
