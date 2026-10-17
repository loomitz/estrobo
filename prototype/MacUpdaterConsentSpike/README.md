# Sparkle 2.10.0 consent/cache experiment

This is an isolated AppKit application and test runner, outside Estrobo's product target. It uses the **unmodified official Sparkle framework and installer**, real signed appcast XML and a real EdDSA-signed DMG. It never opens Estrobo, uses Bluetooth, accesses user Keychain items, publishes anything, or installs outside its unique temporary directory.

The experiment demonstrates a public cache-only archive handoff. It also demonstrates a separate feed-origin policy incompatibility. **It does not authorize product integration.** Read [the gate report](../../docs/research/macos-updater-consent-gate.md) before interpreting a passing script exit.

## Run

Requires a logged-in macOS desktop and full Xcode. The default toolchain path can be overridden with `DEVELOPER_DIR`.

```sh
python3 prototype/MacUpdaterConsentSpike/run.py --output /tmp/estrobo-consent-evidence
python3 prototype/MacUpdaterConsentSpike/run.py --negative-control --output /tmp/estrobo-consent-negative
python3 prototype/MacUpdaterConsentSpike/run.py --redirect-diagnostic --output /tmp/estrobo-feed-redirect
python3 prototype/MacUpdaterConsentSpike/network_policy/run.py
python3 prototype/MacUpdaterConsentSpike/test_cleanup.py
```

Default execution downloads `Sparkle-2.10.0.tar.xz` from the exact release URL and checks SHA-256 `c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c` before extraction. For offline reuse, `--sparkle /path/to/already-extracted-official-distribution` skips download; the caller must establish that directory's integrity (the script checks its declared version). The recorded runs reused the distribution whose downloaded archive matched that hash.

`--negative-control` passes when it reproduces the **undesired** installation: holding Sparkle's ready callback does not prevent installation on ordinary AppKit quit. `--redirect-diagnostic` passes when it reproduces the **undesired** forbidden-origin request. See `network_gate_passed: false` in its result. Neither successful diagnostic means the product's gate passed.

Each run creates unique fixture bundles, update bytes and an ephemeral CryptoKit key in temporary directories. Signing and verification use Sparkle's official `sign_update` tool with an explicit fixture key file. The key is never placed under the HTTP fixture root, read from Keychain or committed; its deletion runs independently of process and server cleanup failures. The fixture HTTP servers bind only loopback and exist only for the test runner's lifetime. They model distribution endpoints; they are **not** a proposed product cache relay. The official framework's symlinks and permissions are copied with `ditto`; fixture outer bundles use ad hoc signatures and are not notarized.

The runner copies only text evidence to `--output`. It leaves the non-secret temporary bundle/DMG directory printed as `Artifacts:` for inspection. The `FixtureRun` context owns setup and cleanup, including partial startup failures. It bounds process termination, falls back to killing its own stuck process, closes each server independently, and deletes the private fixture key even if another cleanup action raises. Every cleanup error makes the runner fail and records `passed: false` plus `cleanup_errors`; an original test failure is retained. Evidence publication is attempted independently, with artifact results recording publication failures. Cleanup terminates only its tracked fixture process or recorded PIDs whose live executable still matches the isolated fixture; cleanup termination is never counted as a successful quit, consent or replacement test.

## Public seams and what they establish

- Normal AppKit `terminate:` / last-window closure and `applicationShouldTerminate:`: installed `CFBundleVersion` and real process lifecycle establish replacement or preservation.
- `SPUUpdater` + `SPUUserDriver` + `SPUUpdaterDelegate`: real feed verification, selection, cache-only copy, extraction, EdDSA validation, installation and relaunch. No private Sparkle API, fork, swizzling, own signature implementation or event-only installer mock.
- Foundation `URLSession`, `URLCache`, mutable `URLRequest.cachePolicy`: download first, retain disk bytes, prime a sufficiently large cache only after explicit consent, and set `.returnCacheDataDontLoad` through `willDownloadUpdate:withRequest:`. Cache misses fail without fetching the archive. SHA-256 is evidence, not a replacement for Sparkle signature validation.

The fixture obtains a real AppKit veto before preparing Sparkle, deferring accepted termination with `.terminateLater`. This enters a termination runloop mode where ordinary polling/input is suspended. Prepared cancellation, newly unsafe work and quit-during-preparation are therefore invoked as scheduled **public actions from the real ready callback**. They establish installer control and subsequent disk/process outcomes. They do **not** establish that a user can click a cancel button during that modal termination phase. Interactive cancellation remains an explicit open gate.

The standalone Foundation controls distinguish shared sessions (global `URLProtocol` registration consulted) from default configured sessions (not consulted), and demonstrate that `.reloadIgnoringLocalCacheData` does not accept a cache-only feed injection. They are supporting API diagnostics, not substitutes for the Sparkle runtime tests.
