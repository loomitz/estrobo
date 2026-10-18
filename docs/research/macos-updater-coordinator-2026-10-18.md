# macOS update coordinator — 2026-10-18

Ticket 11 implements the app-local update policy boundary. Sparkle integration,
AppKit installer choreography, product views and composition remain tickets 12/13;
the controlled service in these tests is not proof of installing Estrobo.

## Ownership and contract

`prototype/EstroboMac/Sources/UpdateCoordinator.swift` owns one MainActor operation,
read-only `UpdateSnapshot`, preferences and absolute-date scheduling. UI callers
share this coordinator and pass the exact `UpdateOfferIdentity` captured by their
confirmation dialog to `confirmInstall(expectedIdentity:)`.

`UpdateService` is the sole real/controlled update boundary. Successful checks
return candidates from a verified fresh signed feed. The coordinator selects the
highest compatible newer build for the installed bundle's explicit stable/beta
channel, validates immutable DMG metadata, and retains compatible candidates when
newer ones require an unsupported system. Localized notes remain plain strings
for the app's selected language. No Sparkle types enter this boundary.

Installation must freshly validate catalog eligibility and the full downloaded
identity. The service calls the synchronous MainActor precommit closure immediately
before archive preparation and again before committing installation. Either call
can veto. Cancellation intent does not release the session lock: async installation
must finish cancelling the actual prepared installer before returning/throwing.
Ordinary quit cancels approval and waits for that completion. The AppKit adapter
must preserve the normal close veto and window restoration proved by ticket 10.

`GodoxSessionController.suspendOperations()` adds a generic independent token gate
to command entrypoints without disconnecting or changing foreground state. Safety
observations still flow. Resuming the scene does not release another owner's token.
Close safety checks Apply eligibility independently of this gate, so a temporary
lock cannot disguise a resolvable draft as an unresolvable persisted draft.

## Behavior coverage

The focused executable drives the coordinator through one controlled update
service, a controlled clock, isolated preferences, and real session controllers
using simulated/control-only radio transports and existing in-memory persistence.
It covers:

- Disabled network defaults; manual successful lookup without opt-in; second
  post-onboarding launch invitation and persisted dismissal.
- Daily cadence, persistent known Retry-After across relaunch/preference toggles,
  conservative 24-hour opaque failures, manual retries and no false up-to-date.
- One check/download at a time; visible progress; disabling only automatic work;
  late callbacks cannot revive cancelled automation; radio Test stays responsive.
- Stable/beta filtering, same marketing version with higher build, incompatible,
  equal/lower and withdrawn offers, immutable URL rejection and payload identity.
- Exact-dialog approval, duplicate confirmation, fresh-offer mismatch, ordinary
  quit, delayed cancellation acknowledgement, errors, retry and successful commit.
- Real scan/connection/discovery/authentication/sync/disconnection/connected-idle,
  Test, interactive edits, debounce, resolvable drafts, Apply, recovery and invalid
  journal blockers. New transport state cancels consent during commitment.
- The existing persisted derived Multi draft exception, restored workspace value,
  and continued close blocking for its connected/resolvable form under suspension.

## Validation

Use the full Xcode toolchain:

```sh
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
make -C prototype/EstroboMac test-updates test-session-recovery test-interactive-editing test-workspace-chrome
swift test
make -C prototype/EstroboMac check
```

These are coordinator/session and compilation checks. Signed/notarized replacement,
production sandbox/HTTPS, Intel/minimum-macOS runtime, physical radio behavior,
public catalog/promotion and product accessibility remain separate acceptance gates.

All commands above passed on Apple Silicon with the full Xcode beta toolchain:
14 coordinator scenarios, the existing session/interactive/window checks, 67 shared
SwiftPM tests, module-boundary compilation and the macOS 13 deployment-target
typecheck. The last coordinator rerun also reconstructs preferences from a fresh
UserDefaults adapter to verify the persisted server deadline. During development,
an overlapping compile rejected a source modified while adding localized notes;
the final unchanged-source checks passed. No product runtime, physical transmitter
or signed/notarized installation was exercised by this ticket.
