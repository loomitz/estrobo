# Support

<p align="center"><a href="SUPPORT.md">Español</a> &nbsp;·&nbsp; <strong>English</strong></p>

Estrobo is a limited public beta, and its support channel is **GitHub Issues**. There is no published support email address.

## Before opening an issue

1. Read [Troubleshooting](docs/TROUBLESHOOTING.md).
2. Confirm that you are using the latest public beta and macOS 13 or later.
3. Quit any other app connected to the trigger.
4. Try to reproduce the problem with `--mock-radio` if it involves the interface, interaction, presets, or session state.
5. Search for an existing issue to avoid duplicates.

[Open an issue in this repository](../../issues/new) only for non-sensitive information.

## Useful information

- Estrobo version and build;
- macOS version and Intel/Apple Silicon architecture;
- visible session phase and exact message;
- expected and observed steps;
- whether it also occurs in simulated mode;
- for compatibility reports, the trigger and flash models and firmware versions, if known;
- a redacted screenshot or short video when helpful.

We do not need a Radio Code to diagnose a problem. Use synthetic values in every example.

## Never post in Issues

- an actual Radio Code;
- a `Psub` payload, `PWOK` response, or temporary token;
- a full UUID, station name, or personal information;
- keys, private certificates, P12 files, `.p8` API keys, notarization credentials, passwords, or GitHub Secrets;
- a suspicious DMG or third-party binaries;
- details of an exploitable vulnerability.

For vulnerabilities, use [GitHub Private Vulnerability Reporting](SECURITY.md).

## What to expect

Compatibility is expanded only after reversible physical validation for each model and firmware combination. A BLE name, RSSI, UUID, or `FEC8` acknowledgment is not enough to claim support. You may be asked to reproduce the problem in simulated mode or participate in a coordinated physical validation gate; no date or SLA is promised.

The `Psub`/`PWOK` handshake is mandatory; the Radio Code is the trigger’s local PIN, not a strong credential. The official beta uses Developer ID signing and notarization: if Gatekeeper does not identify it as `Notarized Developer ID`, verify the checksum and download it again before opening an issue.

## Independent project

This repository is not a Godox support channel. Estrobo is not affiliated with, sponsored by, or officially maintained by Godox.
