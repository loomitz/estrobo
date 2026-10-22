# Official-identity updater qualification

The first real updater walkthrough needs a second signed/notarized beta at its
canonical GitHub URL before the update smoke can finish. `prepare-qualification`
is a separate temporary test lane. It never records `physicalSmoke=passed`.
Ordinary `prepare` retains its full final approval gate.

Use an isolated macOS user or VM: `mx.loo.estrobo` shares product storage and
Keychain access with other copies in the same user. Use the unmodified production
client, EdDSA root, Developer ID and `https://estrobo.app/updates/macos/appcast.xml`.
There is no client feed/archive override. A VM does not prove physical Bluetooth
or Intel execution.

## Candidate

Allocate a fresh global build. Merge its exact source through protected `main`
and require green ARM/Intel CI on that exact commit. Build from the clean checkout
with the existing local Developer ID lane, notarize/staple app and DMG separately,
and verify the exact re-downloaded draft DMG/manifest/checksum tuple. Preserve the
older bootstrap DMG unchanged. Keep the manifest's smoke status pending.

Create an owner-only authorization JSON outside Git, tied to the user's explicit
official-feed test request and the final candidate bytes:

```json
{
  "purpose": "official-updater-qualification",
  "authorizedAt": "UTC ISO-8601 start",
  "expiresAt": "UTC ISO-8601 end, at most 48 hours after start",
  "build": "POSITIVE_INTEGER",
  "tag": "vVERSION-beta.BUILD",
  "commit": "FULL_SOURCE_SHA",
  "dmgSHA256": "FINAL_STAPLED_DMG_SHA256"
}
```

With the existing signing environment and Keychain account:

```sh
python3 scripts/macos-update-catalog.py prepare-qualification \
  --archive /PRIVATE/Dist/estrobo-TAG-macos-universal.dmg \
  --manifest /PRIVATE/Dist/estrobo-TAG-manifest.json \
  --checksums /PRIVATE/Dist/SHA256SUMS \
  --notes-en /PRIVATE/notes-en.txt --notes-es /PRIVATE/notes-es.txt \
  --authorization /PRIVATE/qualification-authorization.json \
  --account "$EDDSA_ACCOUNT" --output /PRIVATE/qualification-candidate
```

This reuses the canonical clean-source/exact-CI and DMG verifiers. The feed
signature binds expiry, exact archive identity and authorization receipt digest.
It accepts exactly one beta offer. Review the digest and make the immutable
canonical GitHub archive anonymously available as a clearly labelled
qualification prerelease, using the explicit test authorization. Do not claim
final smoke approval or v1 readiness, or update the website download CTA. Then
`approve` the exact candidate; anonymous download/signature verification applies.

## Restricted official feed

`site` generates a Pages advanced-mode worker only for a qualified catalog.
Configure the Pages production secret `ESTROBO_UPDATER_QUALIFICATION_IPS` with
the test environment's exact public egress addresses, comma separated. Keep
these addresses out of Git and signing credentials out of the VM. The worker
uses the edge-provided `CF-Connecting-IP`, never forwarded client headers.
Missing configuration, a different address, unsupported methods or expiry
returns 404 with `private, no-store`. Allowed feed responses also use
`private, no-store` and preserve exact signed bytes.

Qualified feed bytes are embedded in the Worker, not uploaded as a static
appcast asset. A provider fail-open quota fallback therefore cannot serve that
feed without the gate. Set Pages Functions routing to fail closed as well, and
verify the deployed output has no static `updates/macos/appcast.xml`.

`state.json` remains public and revalidated so another build cannot mistake a
hidden feed for a fresh bootstrap and erase revision/withdrawal history.
Worker routes cover `/updates/macos/*` except this state file. The rest of the
static website stays outside those routes. This limits a network cohort, not
individual users: clients sharing the same egress address can reach the feed
during the bounded window. The canonical GitHub prerelease archive is public.

Review/commit the approved catalog source, build, serialize and recheck live
state immediately before the separately authorized Pages deployment. Verify
both the custom domain and pages.dev gate, allowed exact signed bytes, and fresh
public state. Never remove the gate to work around a failed test. Environments
without the secret fail closed for the qualification feed.

## Walkthrough and retirement

Install the exact bootstrap app in the isolated user's Applications folder.
Seed synthetic product/Keychain records and record digests. Exercise native
Updates: detect the higher build, download from canonical GitHub HTTPS, cancel
installation, exit normally, recover the verified download, then explicitly
install/relaunch. Verify build, certificate, notarization, sandbox entitlements,
data and synthetic Keychain access. Keep evidence outside Git. A shared-folder
bootstrap does not prove browser quarantine; label that gate separately.

Afterward, `withdraw` the qualification offer with a truthful reason, review,
sign and approve the empty feed, preserve permanent build retirement, and deploy
the next revision. Empty signed feeds can retire the last offer. For an ordinary
empty catalog, `site` removes the qualification worker. Never reuse the build or
replace the archive. Allocate a higher build for a corrected/final candidate.
Do not promote a pending manifest by stripping its policy. Ordinary `prepare`
refuses to inherit a qualification offer.
