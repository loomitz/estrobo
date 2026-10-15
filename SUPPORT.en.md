# Support

<p align="center"><a href="SUPPORT.md">Español</a> &nbsp;·&nbsp; <strong>English</strong></p>

Estrobo is a limited beta, and its support channel is **GitHub Issues**. There is no published support email address.

The current public distribution is macOS `0.1.0-beta.4`. iOS and iPadOS remain local candidates; their declared requirements and Simulator results do not constitute an available distribution or validated physical compatibility. A qualifying public support contact is still required before TestFlight or App Store distribution.

## Before opening an issue

1. Read [Troubleshooting](docs/TROUBLESHOOTING.md).
2. Confirm that you are using the latest build available to you on macOS 13 or later, iOS 18 or later, or iPadOS 18 or later.
3. Quit any other app connected to the trigger.
4. If the issue involves the interface, interaction, presets, or session state, try to reproduce it in iPhone/iPad Demo mode or with `--mock-radio` on Mac.
5. Search for an existing issue to avoid duplicates.

[Open an issue in this repository](https://github.com/loomitz/estrobo/issues/new) only for non-sensitive information.

## Useful information

- Estrobo version and build;
- platform, operating-system version, and iPhone/iPad model or Mac architecture;
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

The `Psub`/`PWOK` handshake is mandatory; the Radio Code is the trigger’s local PIN, not a strong credential. On macOS, the official beta uses Developer ID signing and notarization: if Gatekeeper does not identify it as `Notarized Developer ID`, verify the checksum and download it again before opening an issue. On iOS and iPadOS, use only the TestFlight or App Store build published by Estrobo when one is available; Estrobo never requires a configuration profile or third-party installer.

## Independent project

This repository is not a Godox support channel. Estrobo is not affiliated with, sponsored by, or officially maintained by Godox.
