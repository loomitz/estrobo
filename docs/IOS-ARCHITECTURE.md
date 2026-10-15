# Estrobo iOS architecture

This document records the implementation boundary for the native iPhone and
iPad app. It is intentionally narrower than a product roadmap: every rule here
exists to keep the physical-radio behavior shared with the macOS app.

## Dependency direction

```text
EstroboMac  ───────────────┐
                          ├── EstroboCore
EstroboIOS ─ AppCoordinator┤       ▲
            │             │       │
            ├── EstroboBluetooth ──┘
            └── EstroboPersistence ┘
```

- `EstroboCore` owns radio-independent models, A0/A1 codecs, capabilities,
  session sequencing, delivery rules and recovery rules. It imports neither
  AppKit, UIKit, SwiftUI nor CoreBluetooth.
- `EstroboBluetooth` implements the small `RadioTransport` boundary. The live
  adapter is CoreBluetooth foreground-only; the simulated adapter is
  deterministic and does not construct `CBCentralManager`.
- `EstroboPersistence` implements preferences, workspace/preset storage,
  transmitter metadata, the Keychain radio-code vault and the atomic recovery
  journal. Demo and tests use separate in-memory implementations.
- `EstroboMac` continues to compile the same shared sources through its current
  command-line build and release pipeline.
- `EstroboIOS` is a platform-native SwiftUI shell. It owns navigation,
  presentation state and scene lifecycle, not protocol or transport rules.

The transport boundary uses only `RadioCandidate`, `RadioCommand`,
`RadioTransportState`, `RadioNotificationSource`, `RadioTransportError` and
`TransportEvent`. A local CoreBluetooth UUID identifies a candidate only on the
Apple device that discovered it; it is never synchronized across macOS and iOS.

## Composition roots

`AppSessionCoordinator` creates exactly one runtime at a time:

- **Live**: `CoreBluetoothRadioTransport`, persistent repositories, Keychain
  vault and atomic restoration journal. On first use the central manager is
  created only after the Bluetooth explanation; on a later cold launch with a
  saved radio, the live runtime is restored immediately so the last-radio
  offer or automatic exact-UUID search can run.
- **Demo**: `SimulatedRadioTransport` plus new in-memory repositories. It never
  reads, migrates or clears live transmitters, Keychain entries or journals.

Changing runtime suspends the previous controller and releases the
coordinator's ownership before creating the replacement. A view that is still
leaving the hierarchy can retain that controller briefly, but it is already
inert. Views observe the one current controller owned by the app; they never
create their own transport or session.

## Operational presentation seam

The Groups surface keeps frequent power work out of group detail. Per-group
power sliders expose discrete 1/3 EV positions with ruler marks, while a
long press on the card header opens advanced settings. The gesture is scoped
away from the slider and step buttons, and the header also exposes a named
accessibility action. Detail reuses the same physical power scale through its
own slider and maps modeling to three presentation choices: Off, Proportional,
and Manual. Manual reveals a capability-derived intensity slider whose lower
bound is never below 10%.

Global relative power is a final-only domain command. Presentation tracks a
temporary signed offset from -9 through +9 steps (−3 through +3 EV) without
mutating the controller on every drag tick. On release it calls
`adjustGlobalPower(offsetSteps:)` once. The controller captures the current
eligible Manual groups, intersects their physical ranges, clamps once, assigns
the resulting group drafts as one batch and invokes persistence/delivery
planning once. Disabled groups do not participate. After the outcome returns,
presentation resets the relative slider to 0; this resets only the visual
offset, not the newly committed absolute group powers.

Multi owns the participant controls while it is active. The normal group cards
are therefore hidden in that mode, and each participant identity exposes the
same long press and named accessibility action as a normal card. That action
remains independent of whether the participant toggle is currently enabled and
opens the same iPhone destination or iPad inspector. Both entry points share a
press-state modifier: tonal feedback begins while the header is held, a haptic
is emitted when the 0.55 s threshold is recognized, and Reduce Motion removes
the scale change without removing the tonal response.

The iOS Multi frequency scrubber is index-backed rather than numerically
continuous. Its 41 values are 1 through 20, 25 through 50 by five, 60 through
190 by ten, and 199. The shared editable protocol domain accepts 1 through 199
for compatibility and byte round-tripping, while the existing macOS editor
remains limited to its prior 1 through 100 range. Frequencies outside a model's
published table remain visibly unverified; presentation never extrapolates a
manufacturer limit.

Beep, the modeling-light master, Standby and Multi are direct gated actions.
The modeling-light master changes only the A0 `modelingLightEnabled` bit; it
never rewrites the per-group A1 Off/Proportional/Manual mode or manual
intensity. `desiredGlobalSnapshot()` reads that explicit master so a later
power Apply cannot silently turn it back on. A deliberate per-group modeling
edit re-enables the master.

These actions do not create a
confirmation sheet or a synthetic completion phase. Automatic-delivery
feedback is derived only from a genuinely armed debounce or active control
I/O; it disappears as soon as both are idle and never inserts a timed
`complete`/`updated` state. Beep, modeling and Standby publish direct-operation
provenance before their first visible mutation, so neither automatic nor
manual delivery can flash an unrelated Apply surface while their A0/A1 work is
in flight. Multi still exposes Apply when the user deliberately selected manual
delivery. While Standby is active, normal cards and Multi participants retain
their local values but render a persistent `Off in Standby` overlay.

Test presentation consumes its own attempt-correlated delivery result rather
than inferring success or failure from the generic activity stream. Session
cancel, background and reset clear that presentation.

## Foreground lifecycle

The app-level scene observer is the only bridge from `scenePhase` to the
session controller.

When the scene leaves `.active`, the controller always stops scanning, cancels
the 700 ms automatic-delivery deadline, closes interactive edits without
transmitting a stale value and refuses to arm Test, Multi or any new write.

If the session is already Ready, has a known device and has no control intent,
response, synchronization or disconnect resolution in flight, the controller
retains the CoreBluetooth connection. Returning to `.active` keeps that same
session Ready: it does not repeat authentication, Sync, A0 or A1 and does not
repeat a completed delivery. If an automatic-delivery debounce was waiting
when the scene became inactive, it is armed once again only after the same
Ready session returns to foreground.

A physical disconnect observed while inactive is captured against the exact
local CoreBluetooth identifier. On return, the controller makes at most one
foreground-only reconnection attempt to that identifier. It may reuse a
process-local credential from the interrupted session even when Remember was
off, but that credential is never logged or persisted and is cleared by an
explicit Disconnect, Cancel, Forget or runtime replacement. Names are never a
fallback. If the exact radio or a usable credential is unavailable, the app
remains fail-closed and exposes the manual reconnect or recovery action.

Every setup or unsafe state remains fail-closed. Leaving `.active` while
connecting, authenticating, synchronizing, applying or resolving an uncertain
write disconnects and resets the adapter while preserving any durable journal.
Foreground return may reconnect the exact interrupted radio once, but a
durable journal still keeps normal edits and synchronization blocked until the
explicit recovery flow completes.

This is best-effort connection retention, not background execution. The app
declares no `UIBackgroundModes`, does not issue writes while inactive and does
not promise restoration after process termination. Process termination
callbacks are not part of the safety model.

## Remembered connection policy

- A successful PWOK + transport Sync records the local CoreBluetooth UUID as
  the last connected radio only when that radio is saved on this device.
- A successful unsaved connection may retain its exact UUID and radio
  credential in memory only for foreground recovery during that process. It
  does not silently enable Remember or survive process termination.
- On cold launch, the live composition root is restored only when saved radios
  exist. The last connected radio is offered explicitly before scanning.
- A per-radio automatic-connection preference replaces that offer with an
  exact-UUID scan. Discovery names are never used as a fallback and only one
  saved radio can be automatic at a time.
- If Bluetooth is not ready at launch, the exact target remains pending and
  the scan timeout starts only after CoreBluetooth reports an active scan.
- Forgetting a radio removes its last/automatic preference. Missing or corrupt
  preference records normalize to no target without exposing radio codes.
- An invalid saved-radio catalogue exposes no remembered target for that
  process but does not erase otherwise valid last/automatic preferences.

## Delivery and recovery invariants

- A0 precedes dependent A1 frames.
- Control writes are serial and advance only after the expected GATT/FEC8
  evidence.
- Test is explicit, fail-fast, never queued and never retried.
- A continuous gesture emits no intermediate writes. Per-group and Multi
  controls commit at most one final draft after release; global relative power
  commits one atomic multi-group delta and schedules delivery only once while
  the scene remains active.
- The restoration journal is committed before a physical write. A corrupt,
  indeterminate or unreadable journal blocks delivery instead of being cleared.
- Recovery accepts only the same local device UUID recorded by that Apple
  device.
- Sync means Estrobo to radio: it deliberately overwrites configured state and
  does not claim to import the radio's complete state.
- The iOS live composition root follows the same direct synchronization
  contract as macOS: after PWOK and the transport Sync, it waits for the
  technical settle and schedules A0 followed by the configured A1 sequence
  without a second presentation confirmation. Connecting therefore accepts
  the documented local-state overwrite.
- A heartbeat received while connecting, authenticating or performing the
  initial synchronization is retained at most once by phase, independently of
  presentation state. It is released only after A0/A1 reach Ready, so it cannot
  interleave ahead of the initial global write.
- Every CoreBluetooth disconnection path cancels the delayed control task and
  resets queued writes before requesting the asynchronous peripheral teardown.
- In the iOS live runtime, a group newly introduced during workspace
  reconfiguration is staged OFF at its resolved common minimum, with modeling
  and beep disabled, before it can participate in the next connection
  synchronization.

## AccessorySetupKit boundary

AccessorySetupKit is not the GATT transport. The initial hardware probe runs in
a diagnostic configuration without the AccessorySetupKit support declaration
and records advertisement data without assuming FFF0/FEC0 are advertised.
Only verified service UUIDs or Company IDs may become discovery descriptors.
If the X3Pro cannot be identified reliably, the app remains CoreBluetooth
foreground-only. See `IOS-ACCESSORY-SETUP-SPIKE.md` and
`IOS-PHYSICAL-TEST-MATRIX.md`.

The 2026-08-29 physical probe found `FFC0` + `GDBH-A681` in three independent
runs. A second, isolated iOS 26.1 diagnostic app may therefore present an ASK
picker after manually verifying exact advertisement equality. On the physical
iPhone, ASK found an existing authorization and CoreBluetooth resolved its
identifier exactly once without connecting. After explicit removal and
verification in a fresh session, the picker displayed exactly one
`GDBH-A681` candidate. After deliberate selection, a later activation found
the new authorization and resolved the same local identifier exactly once
without connecting; the same result passed after terminating and relaunching
the diagnostic process. A background/foreground pass also confirmed that the
session stops and does not reactivate or resolve silently. The diagnostic
authorization and identifier also survived both an iPhone reboot and an
in-place build update, while deleting the diagnostic app removed its ASK
authorization. The diagnostic contains no direct CoreBluetooth scan,
connection, GATT or write path. `EstroboIOS` still has no dependency on
AccessorySetupKit. The isolated spike has a limited viability GO, while
adoption remains a separate product and architecture decision outside this
physical run.
