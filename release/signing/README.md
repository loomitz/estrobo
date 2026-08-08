# Release signing contracts

Estrobo has two deliberately separate signing contracts. A verifier or workflow must never infer one from the other, and passing one contract does not satisfy the other.

## Legacy self-signed public beta

Public betas 1 and 2 used one stable, self-signed code-signing identity that is independent of Apple. This historical signature provided continuity between those builds; it is not Developer ID, notarization, or a way to suppress Gatekeeper. The legacy rebuild workflow is manual-only and refuses beta 3 or any later tag.

These public files are the immutable identity for that lane:

- `estrobo-beta-signing.cer`: the leaf X.509 certificate in DER format.
- `estrobo-beta-signing.sha256`: the SHA-256 digest of those exact DER bytes.

Never replace either file with Developer ID material. Doing so would break verification of beta 1 and beta 2. The private key must never enter this repository. Its password-protected PKCS#12 representation exists only as `ESTROBO_SIGNING_P12_BASE64` and `ESTROBO_SIGNING_P12_PASSWORD` in GitHub Secrets. The workflow derives `SIGNING_IDENTITY` from the versioned public certificate and does not consume a separate identity secret; remove any unused legacy `ESTROBO_SIGNING_IDENTITY` secret.

The legacy workflow is restricted to an ephemeral GitHub-hosted signing runner. It imports the PKCS#12 file into an ephemeral keychain, grants the self-signed public certificate runner-scoped code-signing trust, verifies its exact fingerprint, and signs without an Apple timestamp. Removing administrator trust hangs on the current macOS 15 runner, so the public certificate and its trust remain isolated until GitHub destroys that VM. The `always()` cleanup removes and verifies the absence of the P12, imported-certificate copies, and private-key keychain before the signed app can continue to a separate verification host.

Participants must not install or trust this certificate. For this lane, `codesign --verify` must pass and Gatekeeper rejection is expected.

## Developer ID candidate lane

`.github/workflows/developer-id-candidate.yml` is a manual, encrypted-candidate workflow. It has read-only repository permissions, runs only from a commit contained in protected `main`, and has no job capable of creating, editing, or publishing a GitHub Release. Because this repository is public, every Actions artifact from this lane is ciphertext plus its SHA-256 checksum; the workflow must never upload a raw app, package, notarization log, or transfer directory.

The Apple Developer membership and identity now exist. These public pinning files belong in the repository; neither contains a private key:

- `estrobo-developer-id-application.cer`: the Apple-issued **Developer ID Application** leaf certificate in DER format.
- `estrobo-developer-id-application.sha256`: the SHA-256 digest of those exact DER bytes.

Configure these repository variables:

- `ESTROBO_APPLE_TEAM_ID`
- `ESTROBO_DEVELOPER_ID_CERT_SHA256`

Before loading any secret, configure both GitHub environments with these protection rules:

- deployment branches restricted to the protected `main` branch only;
- at least one required reviewer and **Prevent self-review** enabled;
- administrator/protection-rule bypass disabled when the repository plan exposes that control;
- protected `main` must itself require review and the normal architecture checks.

Configure these Apple secrets only in `developer-id-signing` after those rules exist:

- `ESTROBO_DEVELOPER_ID_P12_BASE64`
- `ESTROBO_DEVELOPER_ID_P12_PASSWORD`
- `ESTROBO_NOTARY_API_KEY_P8_BASE64`
- `ESTROBO_NOTARY_API_KEY_ID`
- `ESTROBO_NOTARY_API_ISSUER_ID`

Create a second protected environment named `developer-id-verification`. Configure `ESTROBO_CANDIDATE_ARTIFACT_PASSWORD` with the same value in both `developer-id-signing` and `developer-id-verification`; this is the only secret shared between them. The verification environment must not receive the P12, P12 password, `.p8`, Key ID, or Issuer ID. Generate this transfer password independently with at least 32 random characters, keep it outside the repository, and rotate it if its confidentiality is uncertain.

The encrypted sign-to-verification transfer is retained for 35 days so it outlives GitHub's maximum 30-day environment-approval wait; encrypted recovery evidence is retained for 30 days. Approve or reject pending jobs promptly rather than treating retention as a release hold.

The API key must be an App Store Connect **Team API Key** that is authorized for `notarytool`; an Individual API Key is not accepted by that tool. The P12 private key and `.p8` API key are separate credentials and must have separate rotation and revocation procedures.

The candidate contract is fail-closed and ordered:

1. verify the pinned Apple certificate, Team ID, and imported private identity;
2. build both architecture slices and sign once with Hardened Runtime, the exact entitlements, and `--timestamp`;
3. verify Developer ID authority, TeamIdentifier, secure timestamp, certificate bytes, slices, plist, and the App Sandbox + Bluetooth entitlement allowlist;
4. create a temporary ZIP and submit it without automatic retry;
5. persist the submission ID, exact upload ZIP, wait result, and log, and require matching IDs, upload digest, and `Accepted` status;
6. staple and validate the ticket on the `.app`;
7. delete and verify the absence of the P12, `.p8`, and private-key keychain;
8. encrypt the sanitized transfer before uploading it, then decrypt it only inside the clean verification runner;
9. require `stapler` and Gatekeeper acceptance on that runner, create the final candidate ZIP, manifest, and checksums, and encrypt the complete candidate before upload.

An encrypted Actions artifact is not a release and does not reproduce public-download quarantine. Anyone can download the ciphertext from this public repository, so access depends on the transfer password remaining secret. A successful candidate run therefore does not authorize publication or prove the clean-Mac/hardware smoke.

If `notarytool wait` times out or a later transfer step fails, the workflow uploads encrypted recovery evidence instead of submitting again. When a submission exists, that recovery archive contains the original `notary-upload.zip` and `notary-submit.json`. Decrypt it on a secured Mac, extract the exact app, and resume the same Submission ID:

```sh
shasum -a 256 -c estrobo-developer-id-diagnostics.tar.gz.enc.sha256
read -s CANDIDATE_ARTIFACT_PASSWORD
export CANDIDATE_ARTIFACT_PASSWORD
mkdir -p DeveloperIDRecovery BuildDeveloperIDRecovery/Universal
openssl enc -d -aes-256-cbc -pbkdf2 -iter 200000 -md sha256 \
  -pass env:CANDIDATE_ARTIFACT_PASSWORD \
  -in estrobo-developer-id-diagnostics.tar.gz.enc | \
  tar -xzf - -C DeveloperIDRecovery
ditto -x -k \
  DeveloperIDRecovery/notary-upload.zip \
  BuildDeveloperIDRecovery/Universal
NOTARY_SUBMISSION_ID="$(plutil -extract id raw -o - DeveloperIDRecovery/notary-submit.json)"
make mac-prototype-developer-id-resume-notarization-existing \
  BUILD_DIR="$PWD/BuildDeveloperIDRecovery" \
  NOTARIZATION_DIR="$PWD/DeveloperIDRecovery" \
  DEVELOPER_ID_TEAM_ID="$DEVELOPER_ID_TEAM_ID" \
  NOTARY_API_KEY_PATH="$NOTARY_API_KEY_PATH" \
  NOTARY_API_KEY_ID="$NOTARY_API_KEY_ID" \
  NOTARY_API_ISSUER_ID="$NOTARY_API_ISSUER_ID" \
  NOTARY_SUBMISSION_ID="$NOTARY_SUBMISSION_ID"
unset CANDIDATE_ARTIFACT_PASSWORD NOTARY_SUBMISSION_ID
```

This target verifies the recovered signature before waiting, never calls `submit`, and removes the temporary upload ZIP only after the same request is accepted and stapled. A recovery containing only `candidate-app-recovery.zip` represents a later workflow/transfer failure; inspect its saved evidence and verify that app rather than starting a new submission blindly.

The signing/notarization job runs only when `github.run_attempt == 1`. Do not use **Re-run all jobs** or **Re-run failed jobs** after that job fails: GitHub reruns do not retain its workspace and could otherwise create a second submission. Resume from the encrypted recovery artifact when a Submission ID exists. Start a new manual workflow dispatch only after the evidence proves that Apple never created a submission. If only the clean verification job failed, **Re-run failed jobs** is safe because GitHub keeps the already successful signing job and its 35-day encrypted transfer.

After downloading the final artifact, verify and decrypt it without placing the password on the command line:

```sh
cd /path/to/download
shasum -a 256 -c estrobo-developer-id-candidate.tar.gz.enc.sha256
read -s CANDIDATE_ARTIFACT_PASSWORD
export CANDIDATE_ARTIFACT_PASSWORD
openssl enc -d -aes-256-cbc -pbkdf2 -iter 200000 -md sha256 \
  -pass env:CANDIDATE_ARTIFACT_PASSWORD \
  -in estrobo-developer-id-candidate.tar.gz.enc | tar -xzf -
unset CANDIDATE_ARTIFACT_PASSWORD
```

Run this only on the clean smoke-test Mac. The extracted `DistDeveloperID` directory remains a candidate until every promotion gate below passes.

## Promotion and public DMG

A candidate may become a public release only after the exact app has all of this evidence:

- Apple returns `Accepted` and its log matches the submitted ZIP;
- the ticket is stapled and validates after re-extraction;
- Gatekeeper reports `Notarized Developer ID` on clean Apple Silicon and Intel Macs with quarantine preserved;
- checksums, manifest, certificate, Team ID, version, build, slices, plist, and entitlements match;
- the exact artifact completes the required Bluetooth smoke;
- publication is separately authorized while the GitHub prerelease is still a draft.

Public distribution adds a second notarized container contract after the app ticket is stapled:

1. create a read-only compressed UDIF containing only `estrobo.app` and `Applications -> /Applications`;
2. sign the DMG with the same Developer ID Application identity, a secure timestamp, and identifier `mx.loo.estrobo.dmg`;
3. submit that final signed DMG as a new notarization request, require `Accepted` with no issues, and staple its ticket;
4. verify the DMG with `hdiutil`, `codesign`, `stapler`, and Gatekeeper, mount it read-only, and repeat app verification from inside the mounted image;
5. calculate the public checksum and manifest only after DMG stapling, then upload those exact immutable bytes to a draft prerelease;
6. download the draft asset again and compare its digest before publishing.

The `0.1.0-beta.3` release followed this manual exact-asset promotion path. Its public manifest records both the app and DMG notarization requests. Because this DMG was promoted manually rather than built by the tag workflow, its release notes use checksum, Developer ID, and Apple notarization verification and do not claim a GitHub build-provenance attestation.
