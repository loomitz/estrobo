# Privacy

<p align="center"><a href="PRIVACY.md">Español</a> &nbsp;·&nbsp; <strong>English</strong></p>

Estrobo controls the transmitter locally over Bluetooth, without accounts, a user backend, advertising, analytics, or telemetry. Public macOS `0.1.0-beta.4` and the iOS/iPadOS candidates have no updater or app network flow. The new macOS implementation adds connections exclusively to check for and download updates; no release containing that implementation has been published yet.

This policy describes the shared development candidate for macOS, iOS, and iPadOS. The public macOS `0.1.0-beta.4` stores the Radio Code unencrypted in preferences only by opt-in; the Keychain migration described here belongs to the candidate and is not yet a new public release. There is no public iOS or iPadOS distribution. The production signing root, public catalog, and updater distribution gates remain pending. Your browser, GitHub, and Apple operating system have their own practices; opening a link or an operating-system validation is distinct from an updater request.

## Data Estrobo stores locally

The app’s sandbox container may retain:

- language, appearance, view, and change delivery mode;
- compatibility profile, working/visible groups, and assigned models;
- desired A0/A1 snapshots and the latest confirmed local baselines;
- named presets;
- visual identity of groups;
- in the new macOS implementation, update check/download preferences, the latest successful check, the next automatic attempt, and a cached DMG with its offer identity; installation confirmation is never stored as permanent authorization;
- recovery points containing the radio UUID, group, and previous A1 snapshot;
- if you choose, the remembered radio’s name and CoreBluetooth UUID; its Radio Code is stored separately in Keychain.

Presets and recovery points do not include the Radio Code. Session activity excludes authentication payloads and codes.

## Radio Code

The Radio Code is a six-digit local compatibility/proximity parameter, not an account password or a strong credential. The Godox protocol transmits it over BLE within the `Psub` challenge and does not provide strong authentication.

- **Remembering it is opt-in and disabled by default.**
- If you enable it, it is stored only after completing `PWOK` and Sync.
- It is stored in the local Keychain as a device-only item that is available only while the device is unlocked. Keychain synchronization is disabled.
- The remembered name and CoreBluetooth UUID may be stored in app preferences, but the Radio Code is not stored in that metadata record.
- If Estrobo finds a supported plaintext record from an earlier beta, it migrates every code to Keychain and verifies the result before deleting the old plaintext record. An incomplete migration fails closed and remains retryable.
- It is never sent over the Internet: update requests exclude the Radio Code and session data, even though the new macOS app has network access.
- Do not reuse a personal PIN.
- **Forget** removes the saved name, UUID, and code and clears the visible value.
- Canceling, a failure, or disconnecting clears the in-memory session code according to the relevant flow.

Each app bundle has its own local container and Keychain access identity. A development, prototype, TestFlight, or App Store build with a different bundle identity does not automatically inherit another build’s saved data.

## Bluetooth

The app requests Bluetooth permission to scan, display name/RSSI/UUID, connect, and write to the selected transmitter through CoreBluetooth. Name, RSSI, and UUID help reduce the chance of selecting the wrong device, but they do not cryptographically authenticate the radio.

Commands travel directly between the iPhone, iPad, or Mac and the transmitter. Estrobo does not upload device inventories, UUIDs, values, or results to a remote service.

## Network, analytics, and telemetry

Bluetooth control does not require Internet access. Public macOS `0.1.0-beta.4` and the iOS/iPadOS candidates retain their behavior without app network traffic. The updater belongs only to the new macOS implementation; it does not update iOS/iPadOS or add HTTP to the radio core.

In a future macOS release configured for updates, automatic checks and downloads start disabled. You can enable them separately in Updates; automatic downloading requires automatic checking. A manual check contacts the services even without automatic opt-in and does not change your preferences. Disabling automatic checks stops pending automatic work; local control remains available without Internet access.

Checks contact `estrobo.app`; DMGs come from exact GitHub releases. These services and their providers receive ordinary technical data, such as IP address, User-Agent, and HTTPS connection data, and may retain logs under their own practices. The feed uses Sparkle’s standard HTTPS redirects: there is no domain allowlist that vetoes every feed origin before contacting it. HTTPS/ATS and mandatory signed-feed/archive verification remain enabled; actual public traffic remains a pending distribution gate.

Requests exclude the Radio Code, authentication payloads, UUIDs, transmitter names, presets, snapshots, profiles, and studio identifiers. Sparkle system profiling is disabled. There is no analytics, advertising, remote crash reporting, or telemetry. Release notes are signed inline English/Spanish text, without automatic downloads of external pages, images, scripts, or resources.

Installing and relaunching always requires confirmation of a specific offer with the transmitter disconnected and local work in a safe state. Downloading, quitting, or restarting the Mac grants no such permission. Updating retains the app identity and uses existing persistence/migration; it never deletes recovery to enable installation or connects to the radio because an update occurred. Real validation between signed/notarized builds remains pending.

Opening documentation, manual-download, Issues, or Private Vulnerability Reporting links explicitly uses your browser/GitHub and follows those services’ practices.

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
