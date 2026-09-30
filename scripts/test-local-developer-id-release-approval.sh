#!/bin/zsh

set -euo pipefail

fail() {
  print -u2 "Local Developer ID release approval test failed: $*"
  exit 1
}

script_dir="${0:A:h}"
source_approval_script="$script_dir/finalize-local-developer-id-release-approval.sh"
[[ -x "$source_approval_script" ]] || fail "approval finalizer is missing or not executable"
/bin/zsh -n "$source_approval_script"

temporary_dir="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/estrobo-local-release-approval-test.XXXXXX")"
temporary_dir="${temporary_dir:A}"
trap '/bin/rm -rf -- "$temporary_dir"' EXIT

fixture_repository="$temporary_dir/repository"
fixture_scripts="$fixture_repository/scripts"
fixture_signing="$fixture_repository/release/signing"
/bin/mkdir -p "$fixture_scripts" "$fixture_signing"
approval_script="$fixture_scripts/finalize-local-developer-id-release-approval.sh"
/bin/cp "$source_approval_script" "$approval_script"
/bin/chmod 755 "$approval_script"

fake_verifier="$fixture_scripts/verify-macos-developer-id-dmg.sh"
cat >"$fake_verifier" <<'FAKE_VERIFIER'
#!/bin/zsh
set -euo pipefail

for name in DMG MANIFEST CHECKSUMS TAG COMMIT FAKE_VERIFY_STATE; do
  [[ -n "${(P)name:-}" ]] || exit 64
done
[[ -f "$DMG" && -f "$MANIFEST" && -f "$CHECKSUMS" ]] || exit 65
[[ "${DMG:h}" == "${MANIFEST:h}" && "${DMG:h}" == "${CHECKSUMS:h}" ]] || exit 66
[[ "${DMG:t}" == "estrobo-${TAG}-macos-universal.dmg" ]] || exit 67
[[ "${MANIFEST:t}" == "estrobo-${TAG}-manifest.json" && "${CHECKSUMS:t}" == SHA256SUMS ]] || exit 68
[[ "$(/usr/bin/plutil -extract source.commit raw -o - "$MANIFEST")" == "$COMMIT" ]] || exit 69
[[ "$(/usr/bin/plutil -extract verification.physicalSmoke raw -o - "$MANIFEST")" == passed ]] || exit 70
[[ "$(/usr/bin/plutil -extract verification.localReleaseApproval.mode raw -o - "$MANIFEST")" == \
  single-maintainer-self-approval ]] || exit 71
(
  cd "${DMG:h}"
  /usr/bin/shasum -a 256 -c "${CHECKSUMS:t}" >/dev/null
) || exit 72

/bin/mkdir -p "$FAKE_VERIFY_STATE"
call_count=0
if [[ -f "$FAKE_VERIFY_STATE/call.count" ]]; then
  call_count="$(<"$FAKE_VERIFY_STATE/call.count")"
fi
call_count="$((call_count + 1))"
print -r -- "$call_count" >"$FAKE_VERIFY_STATE/call.count"
print -r -- "${DMG:h}" >>"$FAKE_VERIFY_STATE/directories"

if [[ -n "${FAKE_VERIFY_BLOCK_MARKER:-}" && \
      "$call_count" == "${FAKE_VERIFY_BLOCK_CALL:-1}" ]]; then
  /usr/bin/touch "$FAKE_VERIFY_BLOCK_MARKER"
  while [[ ! -e "${FAKE_VERIFY_BLOCK_RELEASE:?}" ]]; do
    /bin/sleep 0.02
  done
fi

if [[ -n "${FAKE_CONCURRENT_MANIFEST_PATH:-}" && \
    "$call_count" == "${FAKE_CONCURRENT_MUTATION_CALL:-1}" ]]; then
  print -n -r -- 'concurrent-change' >>"$FAKE_CONCURRENT_MANIFEST_PATH"
fi
if [[ "${FAKE_VERIFY_EXIT_CODE:-0}" -ne 0 && \
      ( "${FAKE_VERIFY_EXIT_CALL:-0}" == 0 || \
        "$call_count" == "${FAKE_VERIFY_EXIT_CALL}" ) ]]; then
  exit "$FAKE_VERIFY_EXIT_CODE"
fi
exit 0
FAKE_VERIFIER
/bin/chmod 755 "$fake_verifier"

fake_app_verifier="$fixture_scripts/verify-macos-developer-id-release.sh"
cat >"$fake_app_verifier" <<'FAKE_APP_VERIFIER'
#!/bin/zsh
exit 0
FAKE_APP_VERIFIER
/bin/chmod 755 "$fake_app_verifier"

fake_source_verifier="$fixture_scripts/verify-local-developer-id-release-source.sh"
cat >"$fake_source_verifier" <<'FAKE_SOURCE_VERIFIER'
#!/bin/zsh
set -euo pipefail
[[ "$VERSION" == 0.1.0 && "$BUILD_NUMBER" == 4 && "$TAG" == v0.1.0-beta.4 ]]
FAKE_SOURCE_VERIFIER
/bin/chmod 755 "$fake_source_verifier"

certificate="$fixture_signing/estrobo-developer-id-application.cer"
certificate_digest_file="$fixture_signing/estrobo-developer-id-application.sha256"
print -n -r -- 'synthetic public certificate' >"$certificate"
/usr/bin/shasum -a 256 "$certificate" >"$certificate_digest_file"
/bin/chmod 644 "$certificate" "$certificate_digest_file"

print -r -- 'synthetic fixture repository' >"$fixture_repository/README.md"
/usr/bin/git -C "$fixture_repository" init -q
/usr/bin/git -C "$fixture_repository" config user.name 'Estrobo Release Test'
/usr/bin/git -C "$fixture_repository" config user.email 'release-test@example.invalid'
/usr/bin/git -C "$fixture_repository" add README.md scripts release
/usr/bin/git -C "$fixture_repository" commit -q -m 'fixture source commit'

tag=v0.1.0-beta.4
commit="$(/usr/bin/git -C "$fixture_repository" rev-parse --verify 'HEAD^{commit}')"
typeset -g case_root case_artifacts case_dmg case_manifest case_checksums case_digest case_output
typeset -ga common_env

prepare_case() {
  local name="$1"
  case_root="$temporary_dir/cases/$name"
  case_artifacts="$case_root/artifacts"
  case_dmg="$case_artifacts/estrobo-${tag}-macos-universal.dmg"
  case_manifest="$case_artifacts/estrobo-${tag}-manifest.json"
  case_checksums="$case_artifacts/SHA256SUMS"
  case_output="$case_root/output.log"
  /bin/mkdir -p "$case_artifacts"
  /bin/chmod 755 "$case_artifacts"
  print -n -r -- "synthetic notarized DMG for $name" >"$case_dmg"
  /bin/chmod 644 "$case_dmg"
  case_digest="$(/usr/bin/shasum -a 256 "$case_dmg" | /usr/bin/awk '{ print tolower($1) }')"

  /usr/bin/plutil -create xml1 "$case_manifest"
  /usr/bin/plutil -insert schemaVersion -integer 3 "$case_manifest"
  /usr/bin/plutil -insert source -dictionary "$case_manifest"
  /usr/bin/plutil -insert source.tag -string "$tag" "$case_manifest"
  /usr/bin/plutil -insert source.commit -string "$commit" "$case_manifest"
  /usr/bin/plutil -insert artifact -dictionary "$case_manifest"
  /usr/bin/plutil -insert artifact.filename -string "${case_dmg:t}" "$case_manifest"
  /usr/bin/plutil -insert artifact.sha256 -string "$case_digest" "$case_manifest"
  /usr/bin/plutil -insert notarization -dictionary "$case_manifest"
  /usr/bin/plutil -insert notarization.diskImage -dictionary "$case_manifest"
  /usr/bin/plutil -insert notarization.diskImage.finalSHA256 -string "$case_digest" "$case_manifest"
  /usr/bin/plutil -insert verification -dictionary "$case_manifest"
  /usr/bin/plutil -insert verification.physicalSmoke -string pending "$case_manifest"
  /usr/bin/plutil -convert json -r "$case_manifest"
  (
    cd "$case_artifacts"
    /usr/bin/shasum -a 256 "${case_dmg:t}" "${case_manifest:t}" >"${case_checksums:t}"
  )
  /bin/chmod 644 "$case_manifest" "$case_checksums"

  common_env=(
    "DMG=$case_dmg"
    "MANIFEST=$case_manifest"
    "CHECKSUMS=$case_checksums"
    'VERSION=0.1.0'
    'BUILD_NUMBER=4'
    "TAG=$tag"
    "COMMIT=$commit"
    'MACOSX_DEPLOYMENT_TARGET=13.0'
    'BUNDLE_IDENTIFIER=mx.loo.estrobo'
    'DEVELOPER_ID_TEAM_ID=XG96FAV89U'
    "DEVELOPER_ID_CERTIFICATE=$certificate"
    "DEVELOPER_ID_CERTIFICATE_SHA256=$certificate_digest_file"
    "APP_VERIFY_SCRIPT=$fake_app_verifier"
    "DMG_VERIFY_SCRIPT=$fake_verifier"
    "APPROVED_TAG=$tag"
    "APPROVED_COMMIT=$commit"
    "APPROVED_DMG_SHA256=$case_digest"
    'PHYSICAL_SMOKE_STATUS=passed'
    "FAKE_VERIFY_STATE=$case_root/verify-state"
  )
}

run_action() {
  local action="$1"
  shift
  /usr/bin/env "${common_env[@]}" "$@" "$approval_script" "$action"
}

artifact_fingerprint() {
  local directory="$1"
  (
    cd "$directory"
    /usr/bin/find . -mindepth 1 -print | LC_ALL=C /usr/bin/sort | while IFS= read -r entry; do
      if [[ -L "$entry" ]]; then
        print -r -- "$entry|link|$(/usr/bin/readlink "$entry")"
      elif [[ -d "$entry" ]]; then
        print -r -- "$entry|dir|$(/usr/bin/stat -f '%Lp' "$entry")"
      else
        print -r -- "$entry|file|$(/usr/bin/stat -f '%Lp' "$entry")|$(/usr/bin/shasum -a 256 "$entry" | /usr/bin/awk '{ print $1 }')"
      fi
    done
  ) | /usr/bin/shasum -a 256 | /usr/bin/awk '{ print $1 }'
}

expect_failure_unchanged() {
  local label="$1"
  local action="$2"
  shift 2
  local before
  before="$(artifact_fingerprint "$case_artifacts")"
  if run_action "$action" "$@" >"$case_output" 2>&1; then
    fail "$label unexpectedly succeeded"
  fi
  local after
  after="$(artifact_fingerprint "$case_artifacts")"
  if [[ "$after" != "$before" ]]; then
    /usr/bin/find "$case_artifacts" -mindepth 1 -maxdepth 3 -print >&2
    /bin/cat "$case_output" >&2
    fail "$label changed public artifacts"
  fi
}

wait_for_marker() {
  local marker="$1"
  local process_id="$2"
  local attempt
  for attempt in {1..500}; do
    [[ -e "$marker" ]] && return 0
    /bin/kill -0 "$process_id" >/dev/null 2>&1 || return 1
    /bin/sleep 0.02
  done
  return 1
}

# Successful finalization records exact self-approval without changing the DMG.
prepare_case success
original_dmg_digest="$case_digest"
run_action finalize >"$case_output"
[[ "$(/usr/bin/shasum -a 256 "$case_dmg" | /usr/bin/awk '{ print $1 }')" == "$original_dmg_digest" ]] || \
  fail "successful finalization changed the DMG"
[[ "$(/usr/bin/plutil -extract verification.physicalSmoke raw -o - "$case_manifest")" == passed ]] || \
  fail "successful finalization did not record the passed physical smoke"
[[ "$(/usr/bin/plutil -extract verification.localReleaseApproval.mode raw -o - "$case_manifest")" == \
  single-maintainer-self-approval ]] || fail "successful finalization omitted self-approval mode"
[[ "$(/usr/bin/plutil -extract verification.localReleaseApproval.tag raw -o - "$case_manifest")" == "$tag" ]] || \
  fail "successful finalization recorded the wrong tag"
[[ "$(/usr/bin/plutil -extract verification.localReleaseApproval.commit raw -o - "$case_manifest")" == "$commit" ]] || \
  fail "successful finalization recorded the wrong commit"
[[ "$(/usr/bin/plutil -extract verification.localReleaseApproval.dmgSHA256 raw -o - "$case_manifest")" == \
  "$original_dmg_digest" ]] || fail "successful finalization recorded the wrong DMG digest"
(
  cd "$case_artifacts"
  /usr/bin/shasum -a 256 -c SHA256SUMS >/dev/null
) || fail "successful finalization produced invalid checksums"
[[ "$(/usr/bin/awk 'NF { count += 1 } END { print count + 0 }' "$case_checksums")" == 2 ]] || \
  fail "successful finalization changed the two-entry checksum contract"
if /usr/bin/find "$case_artifacts" -maxdepth 1 \
  \( -name '.finalize-local-developer-id-release-approval.*' -o \
     -name '.finalize-local-developer-id-release-approval.lock' \) -print -quit | /usr/bin/grep -q .; then
  fail "successful finalization left staging or lock state"
fi

# Verification is repeatable and read-only once approval exists.
approved_fingerprint="$(artifact_fingerprint "$case_artifacts")"
run_action verify >"$case_root/verify-output.log"
[[ "$(artifact_fingerprint "$case_artifacts")" == "$approved_fingerprint" ]] || \
  fail "verify action changed approved public artifacts"

# Pending or non-exact smoke tokens cannot pass either action.
prepare_case verify-pending
expect_failure_unchanged 'verify on pending manifest' verify
prepare_case smoke-skipped
expect_failure_unchanged 'non-passed physical smoke' finalize PHYSICAL_SMOKE_STATUS=skipped

# Approval must bind the exact public tag, commit, and DMG digest.
prepare_case wrong-tag
expect_failure_unchanged 'mismatched approved tag' finalize APPROVED_TAG=v0.1.0-beta.5
prepare_case wrong-commit
expect_failure_unchanged 'mismatched approved commit' finalize \
  APPROVED_COMMIT=2222222222222222222222222222222222222222
prepare_case wrong-digest
expect_failure_unchanged 'mismatched approved DMG digest' finalize \
  APPROVED_DMG_SHA256=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
prepare_case legacy-beta
expect_failure_unchanged 'legacy beta approval' finalize \
  APPROVED_TAG=v0.1.0-beta.2 TAG=v0.1.0-beta.2

# Existing approval evidence and operation locks fail closed.
prepare_case approval-preexists
/usr/bin/plutil -insert verification.localReleaseApproval -dictionary "$case_manifest"
(
  cd "$case_artifacts"
  /usr/bin/shasum -a 256 "${case_dmg:t}" "${case_manifest:t}" >"${case_checksums:t}"
)
expect_failure_unchanged 'preexisting approval evidence' finalize

prepare_case operation-lock
/bin/mkdir "$case_artifacts/.finalize-local-developer-id-release-approval.lock"
/bin/chmod 700 "$case_artifacts/.finalize-local-developer-id-release-approval.lock"
expect_failure_unchanged 'preexisting approval lock' finalize

# A verifier failure must roll back manifest/checksum and leave the DMG exact.
prepare_case verifier-failure
expect_failure_unchanged 'final verifier failure' finalize FAKE_VERIFY_EXIT_CODE=88
[[ "$(/usr/bin/shasum -a 256 "$case_dmg" | /usr/bin/awk '{ print $1 }')" == "$case_digest" ]] || \
  fail "verifier failure changed the DMG"

# Failure after installation must restore the original tuple and remove transaction state.
prepare_case post-install-verifier-failure
expect_failure_unchanged 'post-install verifier failure' finalize \
  FAKE_VERIFY_EXIT_CODE=88 FAKE_VERIFY_EXIT_CALL=2
[[ "$(<"$case_root/verify-state/call.count")" == 2 ]] || \
  fail "post-install verifier failure did not reach the second canonical verification"

# TERM during the post-install verifier must run the same rollback path.
prepare_case term-during-post-install-verification
before_term="$(artifact_fingerprint "$case_artifacts")"
term_marker="$case_root/verifier.blocked"
term_release="$case_root/verifier.release"
/usr/bin/env "${common_env[@]}" \
  "FAKE_VERIFY_BLOCK_MARKER=$term_marker" \
  'FAKE_VERIFY_BLOCK_CALL=2' \
  "FAKE_VERIFY_BLOCK_RELEASE=$term_release" \
  "$approval_script" finalize >"$case_output" 2>&1 &
term_pid=$!
wait_for_marker "$term_marker" "$term_pid" || {
  /bin/kill -TERM "$term_pid" >/dev/null 2>&1 || true
  /usr/bin/touch "$term_release"
  wait "$term_pid" >/dev/null 2>&1 || true
  /bin/cat "$case_output" >&2
  fail "approval finalizer did not reach the cancellable verification gate"
}
/bin/kill -TERM "$term_pid"
/usr/bin/touch "$term_release"
term_status=0
wait "$term_pid" || term_status=$?
[[ "$term_status" -ne 0 ]] || fail "TERM cancellation unexpectedly finalized approval"
after_term="$(artifact_fingerprint "$case_artifacts")"
if [[ "$after_term" != "$before_term" ]]; then
  /usr/bin/find "$case_artifacts" -mindepth 1 -maxdepth 3 -print >&2
  /bin/cat "$case_output" >&2
  fail "TERM cancellation changed public artifacts"
fi

# Concurrent mutation after installation is never overwritten by rollback.
prepare_case concurrent-post-install-mutation
if run_action finalize \
  FAKE_VERIFY_EXIT_CODE=88 \
  FAKE_VERIFY_EXIT_CALL=2 \
  "FAKE_CONCURRENT_MANIFEST_PATH=$case_manifest" \
  FAKE_CONCURRENT_MUTATION_CALL=2 >"$case_output" 2>&1; then
  fail "concurrent post-install mutation unexpectedly finalized approval"
fi
/usr/bin/grep -Fq 'concurrent-change' "$case_manifest" || \
  fail "concurrent mutation was overwritten during rollback"
[[ -d "$case_artifacts/.finalize-local-developer-id-release-approval.lock" ]] || \
  fail "concurrent mutation did not preserve the approval lock"
if ! /usr/bin/find "$case_artifacts" -maxdepth 1 -type d \
  -name '.finalize-local-developer-id-release-approval.*' ! \
  -name '.finalize-local-developer-id-release-approval.lock' -print -quit | /usr/bin/grep -q .; then
  fail "concurrent mutation did not preserve recovery staging"
fi

print "Local Developer ID release approval tests passed"
