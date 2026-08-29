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
  vault and atomic restoration journal. The central manager is created lazily,
  after the Bluetooth explanation.
- **Demo**: `SimulatedRadioTransport` plus new in-memory repositories. It never
  reads, migrates or clears live transmitters, Keychain entries or journals.

Changing runtime destroys the previous controller and its dependencies before
creating the replacement. Views observe the one controller owned by the app;
they never create their own transport or session.

## Foreground lifecycle

The app-level scene observer is the only bridge from `scenePhase` to the
session controller.

When the scene leaves `.active`, the controller:

1. stops scanning;
2. cancels the 700 ms automatic-delivery deadline;
3. ends or cancels every interactive edit without transmitting a stale value;
4. refuses to arm Test, Multi or any new write;
5. preserves an already-written journal when delivery is uncertain;
6. marks reconnection, Sync or recovery as required.

Returning to `.active` never resumes a debounce and never sends a pending
change silently. Process termination callbacks are not part of the safety
model.

## Delivery and recovery invariants

- A0 precedes dependent A1 frames.
- Control writes are serial and advance only after the expected GATT/FEC8
  evidence.
- Test is explicit, fail-fast, never queued and never retried.
- A continuous gesture emits no intermediate writes and at most one final write
  after it ends while the scene remains active.
- The restoration journal is committed before a physical write. A corrupt,
  indeterminate or unreadable journal blocks delivery instead of being cleared.
- Recovery accepts only the same local device UUID recorded by that Apple
  device.
- Sync means Estrobo to radio: it deliberately overwrites configured state and
  does not claim to import the radio's complete state.

## AccessorySetupKit boundary

AccessorySetupKit is not the GATT transport. The initial hardware probe runs in
a diagnostic configuration without the AccessorySetupKit support declaration
and records advertisement data without assuming FFF0/FEC0 are advertised.
Only verified service UUIDs or Company IDs may become discovery descriptors.
If the X3Pro cannot be identified reliably, the app remains CoreBluetooth
foreground-only. See `IOS-ACCESSORY-SETUP-SPIKE.md` and
`IOS-PHYSICAL-TEST-MATRIX.md`.
