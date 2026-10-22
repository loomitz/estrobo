# Official macOS updater runtime qualification

Manual workflow: `.github/workflows/official-updater-qualification.yml`.
It uses disposable macOS 15 ARM64 and Intel users. It never signs an app,
receives Developer ID/Apple/EdDSA credentials, approves physical smoke, publishes
a release, or deploys a feed. Its repository token is read-only and is supplied
only while downloading the exact immutable release tuples.

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
