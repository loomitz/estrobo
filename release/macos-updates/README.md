# Reviewed macOS update source

This directory is the canonical source used by website builds. It is **unconfigured**: no production public root, signed feed, live appcast or published updater release is supplied here. Beta 4's manual download remains unchanged. Generated public update files are ignored; an editorial build can only copy exact reviewed signed bytes from this directory.

`catalog.json` records full DMG identities, globally assigned build, numeric version, explicit channel, exact tag, system/architecture requirements and inline `releaseNotes: {en, es}`. The appcast uses English `description` as fallback and signed inline `estrobo:releaseNotesEn`/`estrobo:releaseNotesEs` under `https://estrobo.app/xmlns/updates`. The current product adapter accepts full DMGs up to 64 MiB and at most 16,384 UTF-8 bytes per notes language; keep candidates within those limits. No remote notes/assets, deltas, packages or latest-release aliases are allowed. `withdrawals.json` permanently records retired builds and reasons; records are append-only, and withdrawn builds cannot reappear. A corrective release allocates a higher build.

`scripts/macos-update-catalog.py` has four public operations. Shared validation enforces the consumer's 64 MiB archive and 16,384 UTF-8 bytes per notes language bounds for preparation, approval and site generation; preparation rejects oversized payloads before signing or release approval. All mutations are local files; it has no deployment, release publication, key-generation or key-export API.

1. `prepare` must run **before publishing/creating the release tag**, in the unchanged approved app checkout. It reuses final local source approval: clean `HEAD == origin/main`, green architecture checks, and tag absent locally/remotely. Keep notes/candidate output outside the checkout. It verifies the existing final local Developer ID approval for the exact DMG/manifest/checksum tuple, checks the existing Keychain public half against external `SPARKLE_PUBLIC_ED_KEY`, signs/verifies the **same final DMG** with official Sparkle tools, and creates a fresh signed catalog candidate. Example, with the real public root already set in the invoking environment:

   ```sh
   python3 scripts/macos-update-catalog.py prepare \
     --archive /private/release/estrobo-v0.1.0-beta.5-macos-universal.dmg \
     --manifest /private/release/estrobo-v0.1.0-beta.5-manifest.json \
     --checksums /private/release/SHA256SUMS \
     --notes-en /private/release/notes.en.txt --notes-es /private/release/notes.es.txt \
     --account EXISTING_EDDSA_ACCOUNT --output /private/release/catalog-candidate
   ```

2. `withdraw --build BUILD --reason TEXT --account ACCOUNT --output NEW_DIRECTORY` starts from current approved source, removes that offer, appends a retirement record, and produces a newly signed candidate. It preserves existing archives/releases and the approved source until review. It never retags or replaces assets.

3. `approve --candidate DIRECTORY --expected-feed-sha256 REVIEWED_SHA256 --account ACCOUNT` verifies the exact reviewed candidate, its existing approval base, append-only withdrawals and official feed signature. It downloads every exact enclosure anonymously over HTTPS, verifies length/SHA-256 and EdDSA using the same established Keychain root, then archives the previous source under `history/REVISION` and records a new local approval revision. This runs **after** separately authorized release publication. Review and commit the resulting source; deploy it separately. A partial local write fails validation; recover using the preserved history rather than editing hashes to bypass review.

4. `site` validates approved feed/catalog/withdrawal digests and their matching XML identities, then copies exact bytes to `website/public/updates/macos`. It contacts the current public `state.json` with revalidation and an honest `EstroboCatalogVerifier/1.0` User-Agent before building. Lower revisions, changed bytes at the same revision, missing withdrawal history and an unconfigured build over an existing published history fail closed. Only an actual initial 404 permits bootstrap. Network errors do not authorize rollback. `--published-state FILE` is for a freshly retrieved exact state or isolated test fixture; using a stale/fabricated state for deployment would defeat the freshness gate.

`pnpm --dir website build` invokes `site` before Astro. Both appcast and public state have route-specific `Cache-Control: no-cache, max-age=0, must-revalidate`, with no `stale-if-error`; hosting behavior still requires public verification after deployment. The public state carries revision, exact feed digest and cumulative withdrawn builds, rejecting a stale editorial build at validation time. This check runs during the build; it is not infrastructure compare-and-swap. Serialize deployments and promotions, revalidate freshly immediately before uploading a dist, and verify the public result afterward. Never deploy an artifact built before a later withdrawal. Site builds check previously verified signed-byte identity against the reviewed approval record; they do not acquire the signing Keychain or claim to re-verify EdDSA cryptographically themselves.

After each separately authorized deployment, fetch the public appcast/state anonymously with revalidation, verify exact bytes/signature and effective headers, and record observed cache/redirect/withdrawal behavior. No immediate retirement propagation, installer rollback, key-loss recovery or platform smoke is promised by these scripts. In particular, first updater installation remains manual and all signed/notarized pair, Intel/minimum-macOS, public network and real release gates remain pending.

## Promotion and withdrawal commands

The [existing signing guide](../signing/README.md) remains authoritative for exact-source/CI approval, inside-out Developer ID signing, one-submit/resume notarization, final stapled DMG, draft re-download/smoke and final maintainer approval. Prepare the signed catalog candidate after that final approval but before tag/release publication. Review the candidate feed and record its exact digest; publication of the immutable release is a separately authorized step. Only afterward, with assets anonymously available:

```sh
python3 scripts/macos-update-catalog.py approve \
  --candidate /PRIVATE/REVIEWED/catalog-candidate \
  --expected-feed-sha256 REVIEWED_64_HEX_SHA256 \
  --account EXISTING_EDDSA_ACCOUNT --sparkle-dir /VERIFIED/Sparkle
```

The public root is supplied by `SPARKLE_PUBLIC_ED_KEY`; the account must already exist in Keychain and match that public half. No production root or recoverable encrypted offline backup is supplied by this implementation. Never replace it with a fixture key. These scripts expose no key-generation/export, rotation, publication, deployment or catalog-resume command.

Review and commit the new local approved source separately from the app source commit. Build the website, serialize/revalidate immediately before any separately authorized deployment, then verify the public feed/state, signatures, exact bytes and effective headers. Site builds validate the reviewed byte digests without reading a signing Keychain.

Withdrawal uses the same sequence and a new output directory:

```sh
python3 scripts/macos-update-catalog.py withdraw \
  --build BUILD_TO_RETIRE --reason 'REVIEWED_RETIREMENT_REASON' \
  --account EXISTING_EDDSA_ACCOUNT --sparkle-dir /VERIFIED/Sparkle \
  --output /PRIVATE/NEW/withdrawal-candidate
```

Review its new feed digest, `approve` that candidate, commit/rebuild, and promote/verify the next revision. Preserve the assets and append-only withdrawal record; do not retag, replace a published DMG, roll back the public revision, or reset history to unconfigured. A partial local approval needs inspection of the original candidate and preserved `history/REVISION`; changing hashes to bypass validation is not recovery. Correct faulty app behavior with a higher globally assigned build. Data/Keychain compatibility of downgrades is not guaranteed.

After promotion, fetch both URLs anonymously with revalidation and an honest User-Agent. For example, in a new private evidence directory already chosen by the maintainer:

```sh
curl --fail --silent --show-error --location \
  --proto '=https' --proto-redir '=https' \
  --user-agent EstroboCatalogVerifier/1.0 --header 'Cache-Control: no-cache' \
  --dump-header /PRIVATE/EVIDENCE/appcast.headers \
  --output /PRIVATE/EVIDENCE/appcast.xml \
  https://estrobo.app/updates/macos/appcast.xml
curl --fail --silent --show-error --location \
  --proto '=https' --proto-redir '=https' \
  --user-agent EstroboCatalogVerifier/1.0 --header 'Cache-Control: no-cache' \
  --output /PRIVATE/EVIDENCE/state.json \
  https://estrobo.app/updates/macos/state.json
cmp release/macos-updates/appcast.xml /PRIVATE/EVIDENCE/appcast.xml
/VERIFIED/Sparkle/bin/sign_update --account EXISTING_EDDSA_ACCOUNT \
  --verify /PRIVATE/EVIDENCE/appcast.xml
```

Compare public revision/feedSHA/withdrawn builds with approved source, inspect final response headers, and measure fresh-check/previous-download withdrawal behavior in the installed client. Provider/CDN propagation is not instantaneous and an already committed installation cannot be undone. The real public walkthrough remains a pending gate.

If the EdDSA private key is lost, restore and prove the established offline backup first. With mandatory feed/archive verification and zero signature-failure expiration, waiting or publishing an unsigned feed does not recover clients. Without a recoverable root, a newly signed/verified **manual** installation with a new root and higher build is required. A planned trust bridge must be tested before removing old roots; automatic rotation/downgrade is outside this MVP.

Spanish maintainer overview: [Actualizaciones macOS](../../docs/ACTUALIZACIONES-MACOS.md). There is no `reserve`, `validate-only`, `verify-public`, `deploy` or `resume` subcommand to imply additional authority. The current website generator owns the full `_headers` output; review it before adding unrelated header rules.
