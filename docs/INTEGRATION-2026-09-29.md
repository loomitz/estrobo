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
- Wrap actor-isolated enum setters explicitly so stable Swift 6.1–6.3 can compile the iOS controls; verify universal slices separately for portable `lipo` parsing; replace fixed-delay macOS fixtures with bounded waits for actual events/window restoration.
- Preserve the selected radio and its code when a bounded scan finishes and the transport reports `idle` later. Explicit cancellation, inactive scenes, Bluetooth failures and loss of an active connection still clear the code. A deterministic Core regression and the iOS form test reproduce the failure before this repair.
- Reveal the native iPad sidebar or Groups column when iOS 18 initially shows fewer columns. The connection test explicitly covers portrait and uses native navigation before opening the session. Keep connection start, Ready, sheet dismissal and FEC8 assertions, with UI state attachments on failures.

## Verification

The [review PR #21](https://github.com/loomitz/estrobo/pull/21) tracks the consolidated candidate and its exact head commit. Application source was last changed in `6d384959f09fac1ecf44c4060101c05bc287faf9`, which repairs scan completion; subsequent test, CI scheduling and report changes retain that application source. Local macOS bundles record their source commit in `EstroboSourceCommit`.

| Local validation | Result |
| --- | --- |
| Shared Swift packages | 67 tests passed after the scan-completion repair: 58 Core, 6 Persistence, 3 Bluetooth. The regression suite exposes the failure before the repair; five new cases cover synchronous/deferred scan completion plus cancellation, inactive scenes and real link failures. |
| macOS | Typecheck and all 13 test targets passed; the CI-discovered simulation/window fixtures passed focused retests after repair. Native ad-hoc and unsigned universal development bundles contain the exact candidate SHA and pass bundle-content and slice checks; native mock launch passes. |
| iOS | Simulator check, 31 app unit tests per idiom, the candidate document-link test, generic arm64 Release build and unsigned archive verification passed. Initial full UI: 26 iPhone passes, 8 iPad passes and 18 deliberate iPad omissions for phone-specific cases. Focused modeling confirms Off/Proportional/Manual and the 10% minimum. After the scan-completion repair, 3 iPhone and 2 iPad focused tests pass with zero omissions/failures, including connection after scan expiry, Ready, sheet dismissal and simulated FEC8 delivery. The native-navigation refinement also passes 3 focused iPad cases, including explicit portrait, adaptive layouts and Settings. |
| Release tools | Four suites passed, including 32 isolated DMG cases, source hygiene and exact-artifact approval checks. The portable universal-signature verifier also passed against the existing public Beta 4 artifact. |
| Website | Fresh Node 24/pnpm 11.16 frozen-lockfile installation and build passed; 17 checked files, zero diagnostics and five generated pages. |
| Documentation | Local Markdown links resolve; all four candidate privacy/support URLs return HTTP 200. |

The initial baseline [macOS/website CI run](https://github.com/loomitz/estrobo/actions/runs/36662529262) passed on arm64 and Intel. Both stable iOS compilers passed the build after the enum-setter repair. The subsequent stable UI run exposed the scan-completion race; a local form test then reproduced it before the repair. Current unit/smoke results are attached to the [review PR checks](https://github.com/loomitz/estrobo/pull/21/checks). Select the latest integration-branch run in the [stable iOS candidate workflow](https://github.com/loomitz/estrobo/actions/workflows/ios-ci.yml?query=branch%3Acodex%2Fintegration-20260929) for the full UI suite and unsigned archive. These independent verification jobs run in parallel; the workflow and release gate still require all three jobs to succeed. Match each run to the PR head when evaluating the gate.

Unsigned archive checks verify arm64 executable/dSYM UUIDs, the privacy manifest, assets, development bundle ID and absence of a distribution signature. Local validation records retain the executable hashes and source commits; earlier archive evidence does not validate a binary rebuilt after the scan-completion repair. These archives are not distributable. CLI build instructions select a complete Xcode installation explicitly so SwiftUI macro plugins, SDK and shared packages agree.

## Production decision

**NO-GO for a new production release.** The published `v0.1.0-beta.4` remains the existing macOS prerelease; its signed/notarized artifact is a baseline, not a validation of this new source tree.

| Remaining gate | Required evidence |
| --- | --- |
| Automated release-candidate validation | Confirm the live PR checks and full stable candidate run above are green for the final head: macOS arm64/Intel, website, stable-Xcode iOS tests, iOS 18 compatibility, UI suite and unsigned archive. |
| Physical Bluetooth and optical validation | The exact candidate installed on a recorded device/radio/firmware matrix; authentication and Sync; power minus/plus/slider matched to GATT, FEC8 and observed output; lifecycle/recovery; separate Test/Multi results. Stop if power controls are unreliable. |
| macOS distribution | Choose a new version/build/tag and matching notes (the published Beta 4 tag is immutable and cannot be reused), then build a universal candidate, Developer ID signing, accepted app/DMG notarization, stapling, Gatekeeper and clean-Mac installation/upgrade smoke. Beta 4 signing evidence does not transfer to a new binary. |
| iOS distribution | Deliberate final App ID/team/version/build, stable-Xcode signed archive/export, matching public privacy/support documents and signed internal-pilot validation. Current development identity/version remains explicit until that decision. |
| Public release | Review the exact candidate and artifacts after the applicable gates pass, then authorize the specific publication. |

Use [`RELEASE-CHECKLIST.md`](RELEASE-CHECKLIST.md) for macOS and [`IOS-RC0-CHECKLIST.md`](IOS-RC0-CHECKLIST.md) plus [`IOS-PHYSICAL-TEST-MATRIX.md`](IOS-PHYSICAL-TEST-MATRIX.md) for iOS. AccessorySetupKit/probe apps are isolated diagnostics; their recorded viability does not add ASK to the product or broaden hardware compatibility.
