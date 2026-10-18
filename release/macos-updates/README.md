# Reviewed macOS update source

This directory is the canonical source used by website builds. It is **unconfigured**: no production public root, signed feed, live appcast or published updater release is supplied here. Beta 4's manual download remains unchanged. Generated public update files are ignored; an editorial build can only copy exact reviewed signed bytes from this directory.

`catalog.json` records full DMG identities, globally assigned build, numeric version, explicit channel, exact tag, system/architecture requirements and inline `releaseNotes: {en, es}`. The appcast uses English `description` as fallback and signed inline `estrobo:releaseNotesEn`/`estrobo:releaseNotesEs` under `https://estrobo.app/xmlns/updates`. No remote notes/assets, deltas, packages or latest-release aliases are allowed. `withdrawals.json` permanently records retired builds and reasons; records are append-only, and withdrawn builds cannot reappear. A corrective release allocates a higher build.

`scripts/macos-update-catalog.py` has four public operations. All mutations are local files; it has no deployment, release publication, key-generation or key-export API.

1. `prepare` verifies the existing final local Developer ID approval for the exact DMG/manifest/checksum tuple, checks the existing Keychain public half against external `SPARKLE_PUBLIC_ED_KEY`, signs/verifies the **same final DMG** with official Sparkle tools, and creates a fresh signed catalog candidate. Example, with the real public root already set in the invoking environment:

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

`pnpm --dir website build` invokes `site` before Astro. Both appcast and public state have route-specific `Cache-Control: no-cache, max-age=0, must-revalidate`, with no `stale-if-error`; hosting behavior still requires public verification after deployment. The public state carries revision, exact feed digest and cumulative withdrawn builds, preventing a later editorial checkout from restoring a retired offer. Site builds check previously verified signed-byte identity against the reviewed approval record; they do not acquire the signing Keychain or claim to re-verify EdDSA cryptographically themselves.

After each separately authorized deployment, fetch the public appcast/state anonymously with revalidation, verify exact bytes/signature and effective headers, and record observed cache/redirect/withdrawal behavior. No immediate retirement propagation, installer rollback, key-loss recovery or platform smoke is promised by these scripts. In particular, first updater installation remains manual and all signed/notarized pair, Intel/minimum-macOS, public network and real release gates remain pending.
