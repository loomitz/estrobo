#!/bin/zsh

set -euo pipefail
umask 077

fail() {
  print -u2 "Local Developer ID release approval failed: $*"
  exit 1
}

[[ $# -eq 1 ]] || fail "usage: ${0:t} finalize|verify"
action="$1"
case "$action" in
  finalize|verify)
    ;;
  *)
    fail "action must be exactly 'finalize' or 'verify'"
    ;;
esac

[[ ! -L "$0" && "${0:a}" == "${0:A}" ]] || \
  fail "approval script path must not traverse symbolic links"
script_dir="${0:A:h}"
repository_root="${script_dir:h}"
canonical_dmg_verify_script="$script_dir/verify-macos-developer-id-dmg.sh"
canonical_app_verify_script="$script_dir/verify-macos-developer-id-release.sh"
canonical_source_verify_script="$script_dir/verify-local-developer-id-release-source.sh"
canonical_certificate="$repository_root/release/signing/estrobo-developer-id-application.cer"
canonical_certificate_sha256="$repository_root/release/signing/estrobo-developer-id-application.sha256"
canonical_bundle_identifier=mx.loo.estrobo
canonical_team_identifier=XG96FAV89U
canonical_macos_deployment_target=13.0

require_value() {
  local name="$1"
  [[ -n "${(P)name:-}" ]] || fail "missing environment variable ${name}"
}

for required_name in \
  DMG \
  MANIFEST \
  CHECKSUMS \
  VERSION \
  BUILD_NUMBER \
  TAG \
  COMMIT \
  MACOSX_DEPLOYMENT_TARGET \
  BUNDLE_IDENTIFIER \
  DEVELOPER_ID_TEAM_ID \
  DEVELOPER_ID_CERTIFICATE \
  DEVELOPER_ID_CERTIFICATE_SHA256 \
  APP_VERIFY_SCRIPT \
  APPROVED_TAG \
  APPROVED_COMMIT \
  APPROVED_DMG_SHA256 \
  PHYSICAL_SMOKE_STATUS \
  DMG_VERIFY_SCRIPT; do
  require_value "$required_name"
done

[[ "$APPROVED_TAG" =~ '^v[0-9]+\.[0-9]+\.[0-9]+-beta\.[0-9]+$' ]] || \
  fail "APPROVED_TAG is not a beta release tag"
beta_number="${APPROVED_TAG##*.}"
(( 10#$beta_number >= 3 )) || fail "Developer ID approval is not valid for legacy beta.1 or beta.2"
[[ "$APPROVED_COMMIT" =~ '^[0-9a-f]{40}$' ]] || \
  fail "APPROVED_COMMIT must be a full lowercase Git commit SHA"
[[ "$APPROVED_DMG_SHA256" =~ '^[0-9a-f]{64}$' ]] || \
  fail "APPROVED_DMG_SHA256 must be a lowercase SHA-256 digest"
[[ "$PHYSICAL_SMOKE_STATUS" =~ '^[A-Za-z0-9][A-Za-z0-9 .;:_/-]{0,127}$' ]] || \
  fail "PHYSICAL_SMOKE_STATUS contains unsupported characters"
[[ "$PHYSICAL_SMOKE_STATUS" == passed ]] || \
  fail "PHYSICAL_SMOKE_STATUS must be exactly 'passed'"
[[ "$TAG" == "$APPROVED_TAG" ]] || fail "TAG does not match APPROVED_TAG"
[[ "$COMMIT" == "$APPROVED_COMMIT" ]] || fail "COMMIT does not match APPROVED_COMMIT"

raw_dmg="$DMG"
raw_manifest="$MANIFEST"
raw_checksums="$CHECKSUMS"
raw_verify_script="$DMG_VERIFY_SCRIPT"

for path_label in \
  "DMG:$raw_dmg" \
  "manifest:$raw_manifest" \
  "checksums:$raw_checksums"; do
  label="${path_label%%:*}"
  path="${path_label#*:}"
  [[ -f "$path" && -r "$path" ]] || fail "$label is not a readable regular file: $path"
  [[ ! -L "$path" ]] || fail "$label must not be a symbolic link: $path"
  [[ "${path:a}" == "${path:A}" ]] || fail "$label path must not traverse symbolic links: $path"
done

[[ -f "$raw_verify_script" && -x "$raw_verify_script" ]] || \
  fail "DMG_VERIFY_SCRIPT is not an executable regular file: $raw_verify_script"
[[ ! -L "$raw_verify_script" ]] || fail "DMG_VERIFY_SCRIPT must not be a symbolic link"
[[ "${raw_verify_script:a}" == "${raw_verify_script:A}" ]] || \
  fail "DMG_VERIFY_SCRIPT path must not traverse symbolic links"
[[ "${raw_verify_script:A}" == "${canonical_dmg_verify_script:A}" ]] || \
  fail "DMG_VERIFY_SCRIPT must be the repository's canonical DMG verifier"
[[ -f "$APP_VERIFY_SCRIPT" && -x "$APP_VERIFY_SCRIPT" && ! -L "$APP_VERIFY_SCRIPT" ]] || \
  fail "APP_VERIFY_SCRIPT is not a non-symlink executable regular file"
[[ "${APP_VERIFY_SCRIPT:a}" == "${APP_VERIFY_SCRIPT:A}" && \
   "${APP_VERIFY_SCRIPT:A}" == "${canonical_app_verify_script:A}" ]] || \
  fail "APP_VERIFY_SCRIPT must be the repository's canonical app verifier"
[[ -f "$canonical_source_verify_script" && -x "$canonical_source_verify_script" && \
   ! -L "$canonical_source_verify_script" ]] || \
  fail "canonical local source verifier is missing or unsafe"
[[ "${canonical_source_verify_script:a}" == "${canonical_source_verify_script:A}" ]] || \
  fail "canonical local source verifier path must not traverse symbolic links"
for anchor_path in "$DEVELOPER_ID_CERTIFICATE" "$DEVELOPER_ID_CERTIFICATE_SHA256"; do
  [[ -f "$anchor_path" && -r "$anchor_path" && ! -L "$anchor_path" ]] || \
    fail "Developer ID trust anchor is not a readable non-symlink regular file: $anchor_path"
  [[ "${anchor_path:a}" == "${anchor_path:A}" ]] || \
    fail "Developer ID trust anchor path must not traverse symbolic links"
done
[[ "${DEVELOPER_ID_CERTIFICATE:A}" == "${canonical_certificate:A}" ]] || \
  fail "DEVELOPER_ID_CERTIFICATE must be the repository's canonical certificate"
[[ "${DEVELOPER_ID_CERTIFICATE_SHA256:A}" == "${canonical_certificate_sha256:A}" ]] || \
  fail "DEVELOPER_ID_CERTIFICATE_SHA256 must be the repository's canonical certificate digest"
[[ "$BUNDLE_IDENTIFIER" == "$canonical_bundle_identifier" ]] || fail "unexpected bundle identifier"
[[ "$DEVELOPER_ID_TEAM_ID" == "$canonical_team_identifier" ]] || fail "unexpected Developer ID Team ID"
[[ "$MACOSX_DEPLOYMENT_TARGET" == "$canonical_macos_deployment_target" ]] || \
  fail "unexpected macOS deployment target"

DMG="${raw_dmg:A}"
MANIFEST="${raw_manifest:A}"
CHECKSUMS="${raw_checksums:A}"
DMG_VERIFY_SCRIPT="${canonical_dmg_verify_script:A}"
APP_VERIFY_SCRIPT="${canonical_app_verify_script:A}"
DEVELOPER_ID_CERTIFICATE="${canonical_certificate:A}"
DEVELOPER_ID_CERTIFICATE_SHA256="${canonical_certificate_sha256:A}"
output_dir="${DMG:h}"
operation_lock="$output_dir/.finalize-local-developer-id-release-approval.lock"

[[ "${MANIFEST:h}" == "$output_dir" && "${CHECKSUMS:h}" == "$output_dir" ]] || \
  fail "DMG, manifest, and SHA256SUMS must share one directory"
[[ "${DMG:t}" == "estrobo-${APPROVED_TAG}-macos-universal.dmg" ]] || \
  fail "DMG filename does not match APPROVED_TAG"
[[ "${MANIFEST:t}" == "estrobo-${APPROVED_TAG}-manifest.json" ]] || \
  fail "manifest filename does not match APPROVED_TAG"
[[ "${CHECKSUMS:t}" == SHA256SUMS ]] || fail "checksums file must be named SHA256SUMS"
[[ -d "$output_dir" && ! -L "$output_dir" && -x "$output_dir" ]] || \
  fail "artifact directory is not an accessible non-symlink directory"
if [[ "$action" == finalize ]]; then
  [[ -w "$output_dir" ]] || fail "artifact directory is not writable for finalization"
fi
[[ ! -e "$operation_lock" && ! -L "$operation_lock" ]] || \
  fail "another approval operation is active or a stale lock requires inspection"

current_uid="$(/usr/bin/id -u)"

file_mode() {
  /usr/bin/stat -f '%Lp' "$1"
}

file_owner() {
  /usr/bin/stat -f '%u' "$1"
}

require_owned_safe_mode() {
  local path="$1"
  local label="$2"
  local mode
  mode="$(file_mode "$path")" || fail "could not inspect $label permissions"
  [[ "$mode" =~ '^0?[0-7]{3}$' ]] || fail "$label has unsafe special permission bits"
  [[ "$(file_owner "$path")" == "$current_uid" ]] || fail "$label is not owned by the current user"
  (( (8#$mode & 8#22) == 0 )) || fail "$label must not be group- or world-writable"
}

require_trusted_safe_mode() {
  local path="$1"
  local label="$2"
  local mode
  local owner
  mode="$(file_mode "$path")" || fail "could not inspect $label permissions"
  owner="$(file_owner "$path")" || fail "could not inspect $label ownership"
  [[ "$mode" =~ '^0?[0-7]{3}$' ]] || fail "$label has unsafe special permission bits"
  [[ "$owner" == "$current_uid" || "$owner" == 0 ]] || fail "$label has an untrusted owner"
  (( (8#$mode & 8#22) == 0 )) || fail "$label must not be group- or world-writable"
}

require_owned_safe_mode "$output_dir" "artifact directory"
require_owned_safe_mode "$DMG" "DMG"
require_owned_safe_mode "$MANIFEST" "manifest"
require_owned_safe_mode "$CHECKSUMS" "SHA256SUMS"
require_trusted_safe_mode "$DMG_VERIFY_SCRIPT" "canonical DMG verifier"
require_trusted_safe_mode "$APP_VERIFY_SCRIPT" "canonical app verifier"
require_trusted_safe_mode "$canonical_source_verify_script" "canonical local source verifier"
require_trusted_safe_mode "$DEVELOPER_ID_CERTIFICATE" "canonical Developer ID certificate"
require_trusted_safe_mode "$DEVELOPER_ID_CERTIFICATE_SHA256" "canonical Developer ID certificate digest"

dmg_mode="$(file_mode "$DMG")"
manifest_mode="$(file_mode "$MANIFEST")"
checksums_mode="$(file_mode "$CHECKSUMS")"
output_dir_mode="$(file_mode "$output_dir")"

/usr/bin/plutil -convert xml1 -o /dev/null "$MANIFEST" >/dev/null 2>&1 || \
  fail "manifest is not a valid property list"

manifest_value() {
  /usr/bin/plutil -extract "$1" raw -o - "$2" 2>/dev/null
}

expect_manifest_value() {
  local key="$1"
  local expected="$2"
  local manifest_path="$3"
  local actual
  actual="$(manifest_value "$key" "$manifest_path")" || fail "manifest is missing $key"
  [[ "$actual" == "$expected" ]] || \
    fail "manifest $key is '$actual', expected '$expected'"
}

file_sha256() {
  /usr/bin/shasum -a 256 "$1" | /usr/bin/awk '{ print tolower($1) }'
}

expect_exact_owned_file() {
  local path="$1"
  local label="$2"
  local expected_digest="$3"
  local expected_mode="$4"
  [[ -f "$path" && -r "$path" && ! -L "$path" ]] || \
    fail "$label is no longer a readable non-symlink regular file"
  [[ "${path:a}" == "${path:A}" ]] || fail "$label path now traverses symbolic links"
  [[ "$(file_owner "$path")" == "$current_uid" ]] || fail "$label owner changed"
  [[ "$(file_mode "$path")" == "$expected_mode" ]] || fail "$label mode changed"
  [[ "$(file_sha256 "$path")" == "$expected_digest" ]] || fail "$label bytes changed"
}

run_canonical_dmg_verifier() {
  local verifier_dmg="$1"
  local verifier_manifest="$2"
  local verifier_checksums="$3"
  /usr/bin/env \
    -u DMG_IDENTIFIER \
    -u DMG_VOLUME_NAME \
    -u REPOSITORY_URL \
    -u HDIUTIL_COMMAND \
    -u CODESIGN_COMMAND \
    -u SPCTL_COMMAND \
    -u DISKUTIL_COMMAND \
    -u XCRUN_COMMAND \
    -u DEVELOPER_ID_SIGNATURE_VERIFY_SCRIPT \
    DMG="$verifier_dmg" \
    MANIFEST="$verifier_manifest" \
    CHECKSUMS="$verifier_checksums" \
    VERSION="$VERSION" \
    BUILD_NUMBER="$BUILD_NUMBER" \
    TAG="$APPROVED_TAG" \
    COMMIT="$APPROVED_COMMIT" \
    MACOSX_DEPLOYMENT_TARGET="$canonical_macos_deployment_target" \
    BUNDLE_IDENTIFIER="$canonical_bundle_identifier" \
    DEVELOPER_ID_TEAM_ID="$canonical_team_identifier" \
    DEVELOPER_ID_CERTIFICATE="$DEVELOPER_ID_CERTIFICATE" \
    DEVELOPER_ID_CERTIFICATE_SHA256="$DEVELOPER_ID_CERTIFICATE_SHA256" \
    APP_VERIFY_SCRIPT="$APP_VERIFY_SCRIPT" \
      "$DMG_VERIFY_SCRIPT"
}

run_canonical_git() {
  /usr/bin/env \
    -u GIT_DIR \
    -u GIT_WORK_TREE \
    -u GIT_COMMON_DIR \
    -u GIT_INDEX_FILE \
    -u GIT_OBJECT_DIRECTORY \
    -u GIT_ALTERNATE_OBJECT_DIRECTORIES \
    -u GIT_CONFIG_COUNT \
    -u GIT_CONFIG_GLOBAL \
    -u GIT_CONFIG_SYSTEM \
    -u GIT_CONFIG_PARAMETERS \
    -u GIT_EXEC_PATH \
    -u GIT_SSH \
    -u GIT_SSH_COMMAND \
    -u GIT_PROXY_COMMAND \
      /usr/bin/git -C "$repository_root" "$@"
}

expect_approved_repository_head() {
  local actual_head
  actual_head="$(run_canonical_git rev-parse --verify 'HEAD^{commit}' 2>/dev/null)" || \
    fail "could not resolve repository HEAD"
  [[ "$actual_head" == "$APPROVED_COMMIT" ]] || \
    fail "APPROVED_COMMIT is not the repository's verified HEAD"
}

expect_clean_approved_repository() {
  expect_approved_repository_head
  local worktree_status
  worktree_status="$(run_canonical_git status --porcelain=v1 --untracked-files=all)" || \
    fail "could not inspect repository cleanliness"
  [[ -z "$worktree_status" ]] || {
    print -u2 -- "$worktree_status"
    fail "repository changed after source approval"
  }
}

run_canonical_source_verifier() {
  expect_clean_approved_repository
  /usr/bin/env \
    -u GIT_COMMAND \
    -u GH_COMMAND \
    -u GIT_DIR \
    -u GIT_WORK_TREE \
    -u GIT_COMMON_DIR \
    -u GIT_INDEX_FILE \
    -u GIT_OBJECT_DIRECTORY \
    -u GIT_ALTERNATE_OBJECT_DIRECTORIES \
    -u GIT_CONFIG_COUNT \
    -u GIT_CONFIG_GLOBAL \
    -u GIT_CONFIG_SYSTEM \
    -u GIT_CONFIG_PARAMETERS \
    -u GIT_EXEC_PATH \
    -u GIT_SSH \
    -u GIT_SSH_COMMAND \
    -u GIT_PROXY_COMMAND \
    -u GITHUB_API_URL \
    GH_HOST=github.com \
    PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin \
    VERSION="$VERSION" \
    BUILD_NUMBER="$BUILD_NUMBER" \
    TAG="$APPROVED_TAG" \
      "$canonical_source_verify_script"
  expect_clean_approved_repository
}

run_canonical_source_verifier

expect_manifest_value schemaVersion 3 "$MANIFEST"
expect_manifest_value source.tag "$APPROVED_TAG" "$MANIFEST"
expect_manifest_value source.commit "$APPROVED_COMMIT" "$MANIFEST"
expect_manifest_value artifact.filename "${DMG:t}" "$MANIFEST"
expect_manifest_value artifact.sha256 "$APPROVED_DMG_SHA256" "$MANIFEST"
expect_manifest_value notarization.diskImage.finalSHA256 "$APPROVED_DMG_SHA256" "$MANIFEST"
case "$action" in
  finalize)
    expect_manifest_value verification.physicalSmoke pending "$MANIFEST"
    if /usr/bin/plutil -type verification.localReleaseApproval "$MANIFEST" >/dev/null 2>&1; then
      fail "manifest already contains local release approval evidence"
    fi
    ;;
  verify)
    expect_manifest_value verification.physicalSmoke passed "$MANIFEST"
    expect_manifest_value verification.localReleaseApproval.mode single-maintainer-self-approval "$MANIFEST"
    expect_manifest_value verification.localReleaseApproval.tag "$APPROVED_TAG" "$MANIFEST"
    expect_manifest_value verification.localReleaseApproval.commit "$APPROVED_COMMIT" "$MANIFEST"
    expect_manifest_value verification.localReleaseApproval.dmgSHA256 "$APPROVED_DMG_SHA256" "$MANIFEST"
    expect_manifest_value verification.localReleaseApproval.physicalSmokeStatus passed "$MANIFEST"
    ;;
esac

actual_dmg_digest="$(file_sha256 "$DMG")"
[[ "$actual_dmg_digest" == "$APPROVED_DMG_SHA256" ]] || \
  fail "APPROVED_DMG_SHA256 does not match the exact DMG"

checksum_entries="$({
  /usr/bin/awk '
    NF {
      if (NF != 2 || $1 !~ /^[0-9A-Fa-f]{64}$/) exit 2
      print $2
    }
  ' "$CHECKSUMS"
} 2>/dev/null)" || fail "SHA256SUMS has an invalid entry"
expected_checksum_entries="$(print -rl -- "${DMG:t}" "${MANIFEST:t}" | LC_ALL=C /usr/bin/sort)"
actual_checksum_entries="$(print -r -- "$checksum_entries" | LC_ALL=C /usr/bin/sort)"
[[ "$actual_checksum_entries" == "$expected_checksum_entries" ]] || \
  fail "SHA256SUMS must contain exactly the DMG and manifest entries"
(
  cd "$output_dir"
  /usr/bin/shasum -a 256 -c "${CHECKSUMS:t}"
) || fail "existing SHA256SUMS does not verify"

original_manifest_digest="$(file_sha256 "$MANIFEST")"
original_checksums_digest="$(file_sha256 "$CHECKSUMS")"

if [[ "$action" == verify ]]; then
  run_canonical_dmg_verifier "$DMG" "$MANIFEST" "$CHECKSUMS" || \
    fail "canonical DMG verification rejected the approved tuple"
  expect_exact_owned_file "$DMG" "DMG" "$actual_dmg_digest" "$dmg_mode"
  expect_exact_owned_file "$MANIFEST" "manifest" "$original_manifest_digest" "$manifest_mode"
  expect_exact_owned_file "$CHECKSUMS" "SHA256SUMS" "$original_checksums_digest" "$checksums_mode"
  [[ "$(file_mode "$output_dir")" == "$output_dir_mode" ]] || fail "artifact directory mode changed"
  [[ ! -e "$operation_lock" && ! -L "$operation_lock" ]] || \
    fail "approval operation lock appeared during verification"
  expect_clean_approved_repository
  (
    cd "$output_dir"
    /usr/bin/shasum -a 256 -c "${CHECKSUMS:t}"
  ) || fail "SHA256SUMS changed or stopped verifying during approval verification"
  print "Local Developer ID release approval evidence verified: $APPROVED_TAG"
  print "Verification is read-only and is not authorization to publish."
  exit 0
fi

lock_acquired=false
stage_dir=""
transaction_started=false
transaction_committed=false
cleanup_running=false
preserve_recovery=false
installed_manifest_digest=""
installed_checksums_digest=""

cleanup() {
  local exit_status=$?
  [[ "$cleanup_running" == false ]] || return
  cleanup_running=true
  trap - EXIT HUP INT TERM

  if [[ "$transaction_started" == true && "$transaction_committed" != true ]]; then
    if [[ -n "$stage_dir" && -d "$stage_dir" && ! -L "$stage_dir" ]]; then
      local current_manifest_digest=""
      local current_checksums_digest=""
      local destinations_known=true
      if [[ ! -f "$DMG" || -L "$DMG" || \
            "$(file_owner "$DMG")" != "$current_uid" || \
            "$(file_mode "$DMG")" != "$dmg_mode" || \
            "$(file_sha256 "$DMG")" != "$actual_dmg_digest" ]]; then
        destinations_known=false
      fi
      if [[ -f "$MANIFEST" && ! -L "$MANIFEST" && \
            "$(file_owner "$MANIFEST")" == "$current_uid" && \
            "$(file_mode "$MANIFEST")" == "$manifest_mode" ]]; then
        current_manifest_digest="$(file_sha256 "$MANIFEST")" || destinations_known=false
        [[ "$current_manifest_digest" == "$original_manifest_digest" || \
           "$current_manifest_digest" == "$installed_manifest_digest" ]] || destinations_known=false
      else
        destinations_known=false
      fi
      if [[ -f "$CHECKSUMS" && ! -L "$CHECKSUMS" && \
            "$(file_owner "$CHECKSUMS")" == "$current_uid" && \
            "$(file_mode "$CHECKSUMS")" == "$checksums_mode" ]]; then
        current_checksums_digest="$(file_sha256 "$CHECKSUMS")" || destinations_known=false
        [[ "$current_checksums_digest" == "$original_checksums_digest" || \
           "$current_checksums_digest" == "$installed_checksums_digest" ]] || destinations_known=false
      else
        destinations_known=false
      fi

      local restore_manifest="$stage_dir/restore-manifest"
      local restore_checksums="$stage_dir/restore-checksums"
      if [[ "$destinations_known" == true ]] && \
         /bin/cp "$stage_dir/original-manifest" "$restore_manifest" && \
         /bin/cp "$stage_dir/original-checksums" "$restore_checksums" && \
         /bin/chmod "$manifest_mode" "$restore_manifest" && \
         /bin/chmod "$checksums_mode" "$restore_checksums" && \
         /bin/mv -f -- "$restore_manifest" "$MANIFEST" && \
         /bin/mv -f -- "$restore_checksums" "$CHECKSUMS" && \
         [[ -f "$MANIFEST" && ! -L "$MANIFEST" && \
            "$(file_sha256 "$MANIFEST")" == "$original_manifest_digest" ]] && \
         [[ -f "$CHECKSUMS" && ! -L "$CHECKSUMS" && \
            "$(file_sha256 "$CHECKSUMS")" == "$original_checksums_digest" ]]; then
        print -u2 "Local Developer ID release approval rolled back; public artifacts are unchanged."
      else
        preserve_recovery=true
        print -u2 "WARNING: outputs changed concurrently or rollback failed; preserving $stage_dir and $operation_lock for inspection."
      fi
    else
      preserve_recovery=true
      print -u2 "WARNING: approval transaction failed without usable recovery evidence; preserving the operation lock."
    fi
  fi

  if [[ "$preserve_recovery" != true && -n "$stage_dir" && \
        "$stage_dir" == "$output_dir"/.finalize-local-developer-id-release-approval.* && \
        -d "$stage_dir" && ! -L "$stage_dir" ]]; then
    /bin/rm -rf -- "$stage_dir"
  fi
  if [[ "$lock_acquired" == true && "$preserve_recovery" != true ]]; then
    /bin/rmdir "$operation_lock" >/dev/null 2>&1 || true
  fi
  if [[ "$preserve_recovery" == true && "$exit_status" -eq 0 ]]; then
    exit_status=1
  fi
  exit "$exit_status"
}

trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

/bin/mkdir -m 700 "$operation_lock" 2>/dev/null || \
  fail "could not acquire the approval operation lock"
lock_acquired=true
[[ "$(file_owner "$operation_lock")" == "$current_uid" && "$(file_mode "$operation_lock")" == 700 ]] || \
  fail "approval operation lock is not owner-only"

stage_dir="$(/usr/bin/mktemp -d "$output_dir/.finalize-local-developer-id-release-approval.XXXXXX")"
[[ -d "$stage_dir" && ! -L "$stage_dir" ]] || fail "could not create approval staging directory"
[[ "$(file_owner "$stage_dir")" == "$current_uid" && "$(file_mode "$stage_dir")" == 700 ]] || \
  fail "approval staging directory is not owner-only"

original_manifest="$stage_dir/original-manifest"
original_checksums="$stage_dir/original-checksums"
staged_manifest="$stage_dir/staged-manifest"
staged_checksums="$stage_dir/staged-checksums"
/bin/cp "$MANIFEST" "$original_manifest"
/bin/cp "$CHECKSUMS" "$original_checksums"
/bin/cp "$MANIFEST" "$staged_manifest"
/bin/chmod 600 "$original_manifest" "$original_checksums" "$staged_manifest"
[[ "$(file_owner "$original_manifest")" == "$current_uid" && \
   "$(file_owner "$original_checksums")" == "$current_uid" && \
   "$(file_owner "$staged_manifest")" == "$current_uid" && \
   "$(file_mode "$original_manifest")" == 600 && \
   "$(file_mode "$original_checksums")" == 600 && \
   "$(file_mode "$staged_manifest")" == 600 ]] || \
  fail "approval staging files are not owner-only"

/usr/bin/plutil -replace verification.physicalSmoke -string "$PHYSICAL_SMOKE_STATUS" "$staged_manifest"
/usr/bin/plutil -insert verification.localReleaseApproval -dictionary "$staged_manifest"
/usr/bin/plutil -insert verification.localReleaseApproval.mode -string single-maintainer-self-approval "$staged_manifest"
/usr/bin/plutil -insert verification.localReleaseApproval.tag -string "$APPROVED_TAG" "$staged_manifest"
/usr/bin/plutil -insert verification.localReleaseApproval.commit -string "$APPROVED_COMMIT" "$staged_manifest"
/usr/bin/plutil -insert verification.localReleaseApproval.dmgSHA256 -string "$APPROVED_DMG_SHA256" "$staged_manifest"
/usr/bin/plutil -insert verification.localReleaseApproval.physicalSmokeStatus -string "$PHYSICAL_SMOKE_STATUS" "$staged_manifest"
/usr/bin/plutil -convert json -r "$staged_manifest"
/usr/bin/plutil -convert xml1 -o /dev/null "$staged_manifest" >/dev/null 2>&1 || \
  fail "finalized manifest is invalid"

expect_manifest_value schemaVersion 3 "$staged_manifest"
expect_manifest_value verification.physicalSmoke "$PHYSICAL_SMOKE_STATUS" "$staged_manifest"
expect_manifest_value verification.localReleaseApproval.mode single-maintainer-self-approval "$staged_manifest"
expect_manifest_value verification.localReleaseApproval.tag "$APPROVED_TAG" "$staged_manifest"
expect_manifest_value verification.localReleaseApproval.commit "$APPROVED_COMMIT" "$staged_manifest"
expect_manifest_value verification.localReleaseApproval.dmgSHA256 "$APPROVED_DMG_SHA256" "$staged_manifest"
expect_manifest_value verification.localReleaseApproval.physicalSmokeStatus "$PHYSICAL_SMOKE_STATUS" "$staged_manifest"

final_manifest_digest="$(/usr/bin/shasum -a 256 "$staged_manifest" | /usr/bin/awk '{ print tolower($1) }')"
{
  print -r -- "$actual_dmg_digest  ${DMG:t}"
  print -r -- "$final_manifest_digest  ${MANIFEST:t}"
} >"$staged_checksums"
/bin/chmod 600 "$staged_checksums"
[[ "$(file_owner "$staged_checksums")" == "$current_uid" && \
   "$(file_mode "$staged_checksums")" == 600 ]] || fail "staged SHA256SUMS is not owner-only"
[[ "$(/usr/bin/awk 'NF { count += 1 } END { print count + 0 }' "$staged_checksums")" == 2 ]] || \
  fail "staged SHA256SUMS does not contain exactly two entries"
staged_checksums_digest="$(file_sha256 "$staged_checksums")"

verification_dir="$stage_dir/verification"
/bin/mkdir -m 700 "$verification_dir"
[[ -d "$verification_dir" && ! -L "$verification_dir" && \
   "$(file_owner "$verification_dir")" == "$current_uid" && \
   "$(file_mode "$verification_dir")" == 700 ]] || \
  fail "staged verification directory is not owner-only"
verification_dmg="$verification_dir/${DMG:t}"
verification_manifest="$verification_dir/${MANIFEST:t}"
verification_checksums="$verification_dir/${CHECKSUMS:t}"
/bin/cp "$DMG" "$verification_dmg"
/bin/cp "$staged_manifest" "$verification_manifest"
/bin/cp "$staged_checksums" "$verification_checksums"
/bin/chmod 600 "$verification_dmg" "$verification_manifest" "$verification_checksums"
expect_exact_owned_file "$verification_dmg" "staged verification DMG" "$actual_dmg_digest" 600
expect_exact_owned_file "$verification_manifest" "staged verification manifest" "$final_manifest_digest" 600
expect_exact_owned_file "$verification_checksums" "staged verification SHA256SUMS" "$staged_checksums_digest" 600
run_canonical_dmg_verifier "$verification_dmg" "$verification_manifest" "$verification_checksums" || \
  fail "canonical DMG verification rejected the staged approval tuple"
expect_exact_owned_file "$verification_dmg" "staged verification DMG" "$actual_dmg_digest" 600
expect_exact_owned_file "$verification_manifest" "staged verification manifest" "$final_manifest_digest" 600
expect_exact_owned_file "$verification_checksums" "staged verification SHA256SUMS" "$staged_checksums_digest" 600
(
  cd "$verification_dir"
  /usr/bin/shasum -a 256 -c "${verification_checksums:t}"
) || fail "staged approval tuple stopped verifying"

expect_exact_owned_file "$DMG" "DMG" "$actual_dmg_digest" "$dmg_mode"
expect_exact_owned_file "$MANIFEST" "manifest" "$original_manifest_digest" "$manifest_mode"
expect_exact_owned_file "$CHECKSUMS" "SHA256SUMS" "$original_checksums_digest" "$checksums_mode"
expect_clean_approved_repository

/bin/chmod "$manifest_mode" "$staged_manifest"
/bin/chmod "$checksums_mode" "$staged_checksums"
installed_manifest_digest="$final_manifest_digest"
installed_checksums_digest="$staged_checksums_digest"
transaction_started=true
/bin/mv -f -- "$staged_manifest" "$MANIFEST"
/bin/mv -f -- "$staged_checksums" "$CHECKSUMS"

[[ ! -L "$MANIFEST" && ! -L "$CHECKSUMS" ]] || fail "a finalized output is a symbolic link"
[[ "$actual_dmg_digest" == "$(/usr/bin/shasum -a 256 "$DMG" | /usr/bin/awk '{ print tolower($1) }')" ]] || \
  fail "DMG changed during approval finalization"

run_canonical_dmg_verifier "$DMG" "$MANIFEST" "$CHECKSUMS" || \
  fail "canonical DMG verification rejected the finalized tuple"

expect_exact_owned_file "$DMG" "DMG" "$actual_dmg_digest" "$dmg_mode"
expect_exact_owned_file "$MANIFEST" "finalized manifest" "$installed_manifest_digest" "$manifest_mode"
expect_exact_owned_file "$CHECKSUMS" "finalized SHA256SUMS" "$installed_checksums_digest" "$checksums_mode"
[[ "$(file_owner "$output_dir")" == "$current_uid" && \
   "$(file_mode "$output_dir")" == "$output_dir_mode" ]] || \
  fail "artifact directory ownership or mode changed"
[[ -d "$operation_lock" && ! -L "$operation_lock" && \
   "$(file_owner "$operation_lock")" == "$current_uid" && \
   "$(file_mode "$operation_lock")" == 700 ]] || \
  fail "approval operation lock changed during final verification"
expect_clean_approved_repository
expect_manifest_value verification.physicalSmoke passed "$MANIFEST"
expect_manifest_value verification.localReleaseApproval.mode single-maintainer-self-approval "$MANIFEST"
expect_manifest_value verification.localReleaseApproval.tag "$APPROVED_TAG" "$MANIFEST"
expect_manifest_value verification.localReleaseApproval.commit "$APPROVED_COMMIT" "$MANIFEST"
expect_manifest_value verification.localReleaseApproval.dmgSHA256 "$APPROVED_DMG_SHA256" "$MANIFEST"
expect_manifest_value verification.localReleaseApproval.physicalSmokeStatus passed "$MANIFEST"
(
  cd "$output_dir"
  /usr/bin/shasum -a 256 -c "${CHECKSUMS:t}"
) || fail "finalized SHA256SUMS stopped verifying"

transaction_committed=true
print "Local Developer ID release approval recorded: $APPROVED_TAG"
print "Commit: $APPROVED_COMMIT"
print "DMG SHA-256: $APPROVED_DMG_SHA256"
print "Physical smoke: $PHYSICAL_SMOKE_STATUS"
print "Approval evidence was recorded; publication remains a separate gate."
