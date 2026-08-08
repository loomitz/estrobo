# Privacy

<p align="center"><a href="PRIVACY.md">Español</a> &nbsp;·&nbsp; <strong>English</strong></p>

Estrobo controls a transmitter locally over Bluetooth. The app does not create accounts, has no backend, does not request network access, includes no analytics or telemetry, and does not send data over the Internet.

This policy describes the `0.1.x` beta. Your browser, GitHub, macOS, and any other app you use to download, report, or diagnose have their own practices; they are not part of Estrobo’s traffic.

## Data Estrobo stores locally

The app’s sandbox container may retain:

- language, appearance, view, and change delivery mode;
- compatibility profile, working/visible groups, and assigned models;
- desired A0/A1 snapshots and the latest confirmed local baselines;
- named presets;
- visual identity of groups;
- recovery points containing the radio UUID, group, and previous A1 snapshot;
- if you choose, the remembered radio’s name, CoreBluetooth UUID, and Radio Code.

Presets and recovery points do not include the Radio Code. Session activity excludes authentication payloads and codes.

## Radio Code

The Radio Code is a six-digit local compatibility/proximity parameter, not an account password or a strong credential. The Godox protocol transmits it over BLE within the `Psub` challenge and does not provide strong authentication.

- **Remembering it is opt-in and disabled by default.**
- If you enable it, it is stored only after completing `PWOK` and Sync.
- It is stored locally and **unencrypted** in the sandbox preferences; this beta does not use Keychain.
- It is never sent over the Internet because Estrobo has no network flow.
- Do not reuse a personal PIN.
- **Forget** removes the saved name, UUID, and code and clears the visible value.
- Canceling, a failure, or disconnecting clears the in-memory session code according to the relevant flow.

Estrobo can still read valid local records for previously remembered radios, but the public `mx.loo.estrobo` bundle has a separate, clean preferences identity from the prototype bundle. It does not automatically migrate prototype data.

## Bluetooth

The app requests Bluetooth permission to scan, display name/RSSI/UUID, connect, and write to the selected transmitter through CoreBluetooth. Name, RSSI, and UUID help reduce the chance of selecting the wrong device, but they do not cryptographically authenticate the radio.

Commands travel directly between the Mac and transmitter. Estrobo does not upload device inventories, UUIDs, values, or results to a remote service.

## Network, analytics, and telemetry

The bundle retains App Sandbox and Bluetooth and does not declare network client or server entitlements. The app’s code includes no analytics SDK, advertising, remote crash reporting, or telemetry.

When you open links to documentation, GitHub Releases, Issues, or Private Vulnerability Reporting, that action takes place outside Estrobo in your browser or on GitHub.

## Logs, diagnostics, and reports

Visible activity is limited to operational states and errors. It must not include:

- the Radio Code;
- the complete `Psub` payload or `PWOK` response;
- tokens, keys, or private certificates;
- preset contents as a substitute for diagnostics;
- personal information.

GitHub Issues are public. Redact complete UUIDs, personal names, and studio data. Report vulnerabilities through [Private Vulnerability Reporting](SECURITY.md), not through Issues.

## Deleting data

- Use **Forget** to remove the saved radio and Radio Code.
- Delete presets or modify the workspace using the app options available for those items.
- Uninstalling the app does not always remove macOS preferences. For complete deletion, quit Estrobo and also remove the application container associated with `mx.loo.estrobo` from your user account. Back up any presets you want to keep before doing so.

A recovery point may be deliberately retained after an uncertain write to prevent further unsafe writes. It is removed when confirmed recovery finishes or when the container data is completely removed.

## Children’s data, payments, and accounts

Estrobo does not offer accounts, payments, remote profiles, or social features and does not request age, name, email address, or location. The Radio Code does not protect any of those categories.

## Changes

Material changes to this policy will be documented in the repository and in [CHANGELOG.md](CHANGELOG.md). For non-sensitive questions, use [Support](SUPPORT.en.md); there is no published support email address.
