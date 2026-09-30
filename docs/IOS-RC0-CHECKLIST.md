# iOS RC0 checklist

This checklist defines the first reproducible iPhone/iPad release-candidate gate. It does not authorize signing, device installation, TestFlight upload, App Store submission, or broader compatibility claims.

The 2026-09-29 consolidation is a development candidate. Xcode 27 beta / iOS 26 or 27 results must remain separate from this stable-toolchain gate. The historical August installation and test counts do not validate the consolidated source. Checkboxes below remain open until each has evidence from the exact final candidate.

## Source candidate

- [ ] The intended source changes are split into reviewed commits with explicit path lists; never stage the worktree with `git add -A`.
- [ ] The candidate branch is reconciled with the current `origin/main` and has an explicit upstream.
- [ ] A fresh clone can generate `ios/EstroboIOS.xcodeproj` with XcodeGen 2.46.0.
- [ ] English and Spanish localization keys remain in parity.
- [ ] Privacy and support links are visible from Settings and resolve to public documents matching the binary.
- [ ] Before distribution, candidate branch links are pinned to the reviewed release tag or commit and checked from the exact binary.

## Credential-free automated gate

Run with a stable Xcode 26 installation selected through `IOS_DEVELOPER_DIR`:

```sh
export IOS_DEVELOPER_DIR=/Applications/Xcode_26.6.app/Contents/Developer
test -d "$IOS_DEVELOPER_DIR"
command -v xcodegen jq
make ios-core-test
make ios-check
make ios-test
make ios-ui-test
make ios-archive
```

`make ios-archive` must create a Release `.xcarchive` without signing credentials and verify its arm64 executable, dSYM, privacy manifest, bundle identifier, and unsigned state. This proves archive reproducibility only; it is not a distributable TestFlight or App Store artifact.

`.github/workflows/ios-ci.yml` uses a GitHub-hosted `macos-26` runner with stable Xcode 26.6 and a checksum-pinned XcodeGen 2.46.0 download. Pull requests run shared and app unit tests, the metadata/build check, a focused UI smoke on iPhone and iPad, and a generic Release build. A separate `macos-15` lane uses Xcode 16.4 and iOS 18.5 simulators to exercise the declared iOS 18 family. Pushes to `main` and manual candidate runs additionally execute the complete non-screenshot UI suite and validate the unsigned archive.

## Signed internal-pilot gate

- [ ] Decide the Apple Developer team that owns the app.
- [ ] Register the final explicit App ID and replace the development bundle identifier only after that decision.
- [ ] Set a deliberate marketing version and monotonically increasing build number.
- [ ] Archive, validate, and export with stable Xcode and Apple Distribution signing.
- [ ] Complete export-compliance, privacy, beta-description, feedback-email, review-contact, and “What to Test” fields.
- [ ] Confirm the public privacy and support URLs from the exact uploaded build.
- [ ] Publish a real support contact (legal address, email address, or telephone number) at the Support URL; GitHub Issues may supplement that contact but do not replace this App Store Connect requirement.

## Physical smoke gate

Use the exact candidate archive and record transmitter, flash, firmware, iPhone/iPad model, and OS version in [`IOS-PHYSICAL-TEST-MATRIX.md`](IOS-PHYSICAL-TEST-MATRIX.md).

- [ ] Fresh Bluetooth permission flow.
- [ ] Exclusive discovery and connection to the intended transmitter.
- [ ] `Psub` / `PWOK` / deliberate Sync.
- [ ] One group `−`, `+`, and slider commit with matching GATT write, `FEC8`, and physical power result.
- [ ] Disconnect, foreground resume, reconnect, and fail-closed recovery behavior.
- [ ] Forget removes saved metadata and the Radio Code from Keychain.
- [ ] Exercise the exact iOS 18.0 deployment floor on a physical device or installed 18.0 runtime; the hosted compatibility lane proves iOS 18.5, not 18.0.

Installation, launch, GATT delivery, `FEC8`, and optical output are separate results. Stop the physical run if power controls are unreliable. Do not include Test or Multi in pilot instructions until each has its own authorized optical validation.

## RC0 exit

RC0 is complete only when the source candidate, credential-free automation, signed internal-pilot archive, and minimum physical smoke are all green. Repository extraction and a broader external TestFlight pilot begin after this gate; neither can substitute for it.
