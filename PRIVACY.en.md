# Privacy

<p align="center"><a href="PRIVACY.md">Español</a> &nbsp;·&nbsp; <strong>English</strong></p>

Estrobo controls a transmitter locally over Bluetooth. The app does not create accounts, has no backend, does not request network access, includes no analytics or telemetry, and does not send data over the Internet.

This policy describes the `0.1.x` beta on macOS, iOS, and iPadOS. Your browser, GitHub, Apple operating system, and any other app you use to download, report, or diagnose have their own practices; they are not part of Estrobo’s traffic.

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
- It is stored in the local Keychain as a device-only item that is available only while the device is unlocked. Keychain synchronization is disabled.
- The remembered name and CoreBluetooth UUID may be stored in app preferences, but the Radio Code is not stored in that metadata record.
- If Estrobo finds a supported plaintext record from an earlier beta, it migrates every code to Keychain and verifies the result before deleting the old plaintext record. An incomplete migration fails closed and remains retryable.
- It is never sent over the Internet because Estrobo has no network flow.
- Do not reuse a personal PIN.
- **Forget** removes the saved name, UUID, and code and clears the visible value.
- Canceling, a failure, or disconnecting clears the in-memory session code according to the relevant flow.

Each app bundle has its own local container and Keychain access identity. A development, prototype, TestFlight, or App Store build with a different bundle identity does not automatically inherit another build’s saved data.

## Bluetooth

The app requests Bluetooth permission to scan, display name/RSSI/UUID, connect, and write to the selected transmitter through CoreBluetooth. Name, RSSI, and UUID help reduce the chance of selecting the wrong device, but they do not cryptographically authenticate the radio.

Commands travel directly between the iPhone, iPad, or Mac and the transmitter. Estrobo does not upload device inventories, UUIDs, values, or results to a remote service.

## Network, analytics, and telemetry

The app has no network client or server flow. Its code includes no analytics SDK, advertising, remote crash reporting, or telemetry.

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

- Use **Forget** to remove the saved radio metadata and its Radio Code from Keychain.
- Delete presets or modify the workspace using the app options available for those items.
- Apple operating systems may retain Keychain items after an app is deleted. Use **Forget** before uninstalling. Removing the app container clears its preferences and recovery journal; on macOS, Keychain Access can also remove entries for the `mx.loo.estrobo.radio-code` service. Back up any presets you want to keep before deleting the container.

A recovery point may be deliberately retained after an uncertain write to prevent further unsafe writes. It is removed when confirmed recovery finishes or when the container data is completely removed.

## Children’s data, payments, and accounts

Estrobo does not offer accounts, payments, remote profiles, or social features and does not request age, name, email address, or location. The Radio Code does not protect any of those categories.

## Changes

Material changes to this policy will be documented in the repository and in [CHANGELOG.md](CHANGELOG.md). For non-sensitive questions, use [Support](SUPPORT.en.md); there is no published support email address.
