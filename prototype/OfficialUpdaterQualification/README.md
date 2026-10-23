# Official macOS updater runtime qualification

Manual workflow: `.github/workflows/official-updater-qualification.yml`.
It uses disposable macOS 15 ARM64 and Intel users. It never signs an app,
receives Developer ID/Apple/EdDSA credentials, approves physical smoke, publishes
a release, or deploys a feed. Its repository token is read-only and is supplied
only while downloading the exact immutable release tuples.

Draft metadata needs write access, while GitHub's download-only CDN JWT lasts
about five minutes and can expire in the macOS runner queue. Prefer a temporary
encrypted bootstrap transfer: encrypt the three unchanged build 5 files as one
JSON object of base64 values using Node's AES-256-GCM implementation. The binary
envelope is a 12-byte nonce, 16-byte authentication tag and ciphertext. Publish
only that ciphertext on an owned temporary `XXXXXXXX.estrobo.pages.dev` preview
under `/qualification-transfer/32_HEX_DIGITS.bin`; never deploy the key or raw
bootstrap files there.

The prepare-step-only repository secret
`ESTROBO_QUALIFICATION_BOOTSTRAP_TRANSFER` supplies `format=aes-256-gcm-json-v1`,
the exact release ID, HTTPS URL, ciphertext SHA-256, one-time 32-byte `keyHex`
and a receipt expiry within two hours. No signing key or maintainer token is
transferred. The runner checks host/path/expiry/digest, authenticates the GCM
envelope, validates all three pinned plaintext hashes before writing files, then
performs the complete canonical signature/notary verification. Neither archive
extraction nor arbitrary filenames are allowed. Delete the secret and owned
temporary ciphertext deployment after testing. Legacy five-minute GitHub URLs
remain supported for immediate transfers. Keep contents:read permissions.

This transport only installs the initial build 5. The real build 6 update still
uses the unmodified production identity, official feed and canonical GitHub URL.

Both production apps remain unchanged. The UI test launches `mx.loo.estrobo`,
uses its native update window and confirmation, downloads from its canonical
GitHub enclosure via the real HTTPS official feed, cancels, quits normally,
recovers the verified download, then explicitly installs and verifies relaunch.
It compares persistent product data and observes a remembered radio hydrated
from the real Keychain before and after the replacement. Automatic checking and
downloading must remain off.

`Fixtures/synthetic-preferences.plist` contains only synthetic data. Its public
six-digit radio code is a test fixture, never a hardware credential. The legacy
v2 record lets build 5 itself create/read the Keychain item and migrate to v3.
The studio/preset payload was generated with `PersistenceServicesFactory.inMemory`
and a captured in-memory studio store; no maintainer storage was read.

## Operation

1. Finish the exact build 6 app/DMG notarization and draft tuple verification on
   the signing Mac. Keep its source checkout at the exact protected main commit
   until `prepare-qualification` has signed the local bounded candidate. No
   smoke result may be fabricated to pass ordinary final approval.
2. Merge this test harness through the required checks only after that local
   preparation. Dispatch the manual workflow with exact release IDs, source,
   DMG, manifest and signed-feed digests. These inputs contain no secrets.
3. Download both `qualification-host-ARCH-RUN` artifacts while jobs wait. Their
   addresses belong to temporary hosted VMs. Add only those exact addresses to
   the separately configured production Pages qualification binding. Preview
   must lack the binding. Nothing is sent to the VMs from the signing Keychain.
4. Publish the separately authorized qualification prerelease, approve its
   exact signed catalog after anonymous download, review/commit and promote the
   guarded site. The jobs allow at most 30 minutes for that exact feed.
5. Inspect both native results and screenshots, plus installed signature/notary
   verification. Retire the qualification offer and promote the next signed
   empty revision as documented in `release/macos-updates/QUALIFICATION.md`.

Only screenshots, scoped JSON and the public signed feed are uploaded as result
artifacts. App bundles, DMGs, signing material, notary authentication and raw
notary logs are never uploaded as Actions artifacts. A downloaded draft is not
browser quarantine evidence. These VMs do not prove macOS 13 or physical
Bluetooth/Godox behavior; those remain separate release gates.

The Xcode project is generated with pinned XcodeGen 2.46.0. `build-for-testing`
is safe locally; running the test requires the disposable `runner` user and its
explicit plan. The test host has a separate identity; only the external signed
Estrobo app is replaced by Sparkle.

The UI runner has explicit sandbox-disabled test entitlements. Xcode otherwise
enables its own sandbox and redirects the runner's home, making the isolation
guard skip the test and blocking synthetic fixture/evidence access. The workflow
checks the built runner's real signature before execution; the test still
requires the actual `/Users/runner` home and its prepared plan. Shipping Estrobo
retains its original signed sandbox entitlements. A skip never counts as success.

Canonical read-only app/DMG verification is repeated at most three times only
when Apple's CloudKit ticket lookup reports the observed lost-connection error
`NSURLErrorDomain Code=-1005`. Each attempt repeats all signature, hash, ticket
and Gatekeeper checks. Other failures stop immediately, and exhausting the
network retries remains a failure. No notary submission is made by this runner.
