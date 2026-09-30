# Estrobo integration candidate — 2026-09-29

The review branch is `codex/integration-20260929`. It combines the current public macOS Beta 4 source, the pending Estrobo directory/app rename and modeling fixes, and the iPhone/iPad app with shared Swift packages. This is a development candidate; it does not approve a stable release, a new public beta, TestFlight, or production deployment.

## Recovered work

| Work | Source | Integration result |
| --- | --- | --- |
| Public macOS Beta 4, native menu accessibility, Test action and local Developer ID/DMG tooling | `origin/main` at `c1e67ce` | Retained, including release verification and exact-artifact approval gates. |
| Estrobo naming, main-window reopening and modeling activation A0 followed by all configured A1 states | Local macOS work based on `e053f8a` | Preserved in `61cd557`, then reconciled with Beta 4 and the shared controller. |
| Shared Core, Bluetooth and Persistence modules plus native iPhone/iPad shell | `codex/ios-app` at `0bbc4a4` | All five development commits included. |
| iOS deterministic sliders, global controls, UUID reconnect, Keychain/journal, 199 Hz Multi, diagnostics and tests | Pending iOS work, snapshot `b4c6e6f` | Included without duplicating the former macOS engine. |
| Older beta branches | Published beta branches and the local-release lane | Their functional changes are already in Beta 4; the local-release lane was squash-merged as PR #19. |
| Earlier iOS rescue branch | `codex/ios-rescue-20260829` | Superseded by the current iOS extraction, canonical radio names, deterministic mock timeline and runtime-isolation fixes. Its older shell/release content is not reapplied. |

Local work was backed up before consolidation. The original iOS worktree and its physical diagnostic captures remain available locally. Unrelated local files and tool settings are outside the candidate. Physical captures are not distributed in this branch; historical evidence documents clearly identify their local-only status.

## Integration fixes

- Use `prototype/EstroboMac` and `prototype/EstroboBLEPoC` for current builds, CI, simulator visual helpers and source-verification fixtures.
- Keep the historical Beta 1/2 rebuild workflow on the paths actually present in those old tags.
- Keep one Core/Bluetooth/Persistence implementation and apply the pending modeling recovery changes there. Retain the published menu-bar Test and accessibility behavior.
- Reconcile macOS regression fixtures with saved-radio selection and the shared foreground/reconnect contract.
- Make privacy, security, support and iOS installation documentation distinguish the public Beta 4 binary from this candidate.
- Validate shared packages on both macOS architectures, run the website with its declared Node/pnpm versions, and retain the iOS 18 compatibility lane.

## Verification

Validation is in progress. The final review records local results and the exact GitHub checks before this candidate is offered for production assessment. Local Xcode 27 beta evidence is development validation and does not replace the stable-Xcode/iOS-18 CI gates.

## Production decision

**NO-GO for a new production release.** The published `v0.1.0-beta.4` remains the existing macOS prerelease; its signed/notarized artifact is a baseline, not a validation of this new source tree.

| Remaining gate | Required evidence |
| --- | --- |
| Automated release-candidate validation | Green macOS arm64/Intel, website, stable-Xcode iOS tests, iOS 18 compatibility, full UI suite and unsigned archive on the exact candidate. |
| Physical Bluetooth and optical validation | The exact candidate installed on a recorded device/radio/firmware matrix; authentication and Sync; power minus/plus/slider matched to GATT, FEC8 and observed output; lifecycle/recovery; separate Test/Multi results. Stop if power controls are unreliable. |
| macOS distribution | A newly built universal candidate, Developer ID signing, accepted app/DMG notarization, stapling, Gatekeeper and clean-Mac installation/upgrade smoke. Beta 4 signing evidence does not transfer to a new binary. |
| iOS distribution | Deliberate final App ID/team/version/build, stable-Xcode signed archive/export, matching public privacy/support documents and signed internal-pilot validation. Current development identity/version remains explicit until that decision. |
| Public release | Review the exact candidate and artifacts after the applicable gates pass, then authorize the specific publication. |

Use [`RELEASE-CHECKLIST.md`](RELEASE-CHECKLIST.md) for macOS and [`IOS-RC0-CHECKLIST.md`](IOS-RC0-CHECKLIST.md) plus [`IOS-PHYSICAL-TEST-MATRIX.md`](IOS-PHYSICAL-TEST-MATRIX.md) for iOS. AccessorySetupKit/probe apps are isolated diagnostics; their recorded viability does not add ASK to the product or broaden hardware compatibility.
