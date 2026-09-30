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

## Verification

The executable-source candidate is `a573d130bc273412fe7d2e8ee08735c8e67f652f` ([review PR #21](https://github.com/loomitz/estrobo/pull/21)). Later status-only documentation commits do not change that executable source.

| Local validation | Result |
| --- | --- |
| Shared Swift packages | 62 tests passed: 53 Core, 6 Persistence, 3 Bluetooth. |
| macOS | Typecheck and all 13 test targets passed; the CI-discovered simulation/window fixtures passed focused retests after repair. Native ad-hoc and unsigned universal development bundles contain the exact candidate SHA and pass bundle-content and slice checks; native mock launch passes. |
| iOS | Simulator check, 31 app unit tests per idiom, the candidate document-link test, generic arm64 Release build and unsigned archive verification passed. UI: 26 iPhone passes before the compiler workaround, 8 iPad passes with it, 18 deliberate iPad omissions for phone-specific cases, and one focused iPhone pass after it; zero failures. The focused case confirms Off/Proportional/Manual and the 10% minimum. |
| Release tools | Four suites passed, including 32 isolated DMG cases, source hygiene and exact-artifact approval checks. The portable universal-signature verifier also passed against the existing public Beta 4 artifact. |
| Website | Fresh Node 24/pnpm 11.16 frozen-lockfile installation and build passed; 17 checked files, zero diagnostics and five generated pages. |
| Documentation | Local Markdown links resolve; all four candidate privacy/support URLs return HTTP 200. |

The [macOS/website CI run](https://github.com/loomitz/estrobo/actions/runs/36662529262) passed for this executable-source commit on arm64 and Intel. Both stable iOS compilers passed the build after the enum-setter repair. Current unit/smoke results are attached to the [review PR checks](https://github.com/loomitz/estrobo/pull/21/checks); the [full stable iOS candidate run](https://github.com/loomitz/estrobo/actions/runs/36663272611) also exercises the complete UI suite and unsigned archive after its required and iOS 18 gates. Inspect those live results when evaluating the gate rather than treating the local beta compiler as stable-Xcode proof.

The local post-workaround iOS archive has executable SHA-256 `55a01fcef4d45a044241827c51d2502822f34ba915fde0f92d99d29e4f783782`; its arm64 executable/dSYM UUIDs, privacy manifest, assets, development bundle ID and unsigned state were verified. It is not distributable. CLI build instructions select a complete Xcode installation explicitly so SwiftUI macro plugins, SDK and shared packages agree.

## Production decision

**NO-GO for a new production release.** The published `v0.1.0-beta.4` remains the existing macOS prerelease; its signed/notarized artifact is a baseline, not a validation of this new source tree.

| Remaining gate | Required evidence |
| --- | --- |
| Automated release-candidate validation | Confirm the live PR checks and full stable candidate run above are green: macOS arm64/Intel, website, stable-Xcode iOS tests, iOS 18 compatibility, UI suite and unsigned archive. Documentation-only follow-ups leave the executable-source candidate unchanged. |
| Physical Bluetooth and optical validation | The exact candidate installed on a recorded device/radio/firmware matrix; authentication and Sync; power minus/plus/slider matched to GATT, FEC8 and observed output; lifecycle/recovery; separate Test/Multi results. Stop if power controls are unreliable. |
| macOS distribution | Choose a new version/build/tag and matching notes (the published Beta 4 tag is immutable and cannot be reused), then build a universal candidate, Developer ID signing, accepted app/DMG notarization, stapling, Gatekeeper and clean-Mac installation/upgrade smoke. Beta 4 signing evidence does not transfer to a new binary. |
| iOS distribution | Deliberate final App ID/team/version/build, stable-Xcode signed archive/export, matching public privacy/support documents and signed internal-pilot validation. Current development identity/version remains explicit until that decision. |
| Public release | Review the exact candidate and artifacts after the applicable gates pass, then authorize the specific publication. |

Use [`RELEASE-CHECKLIST.md`](RELEASE-CHECKLIST.md) for macOS and [`IOS-RC0-CHECKLIST.md`](IOS-RC0-CHECKLIST.md) plus [`IOS-PHYSICAL-TEST-MATRIX.md`](IOS-PHYSICAL-TEST-MATRIX.md) for iOS. AccessorySetupKit/probe apps are isolated diagnostics; their recorded viability does not add ASK to the product or broaden hardware compatibility.
