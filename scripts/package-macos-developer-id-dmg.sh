#!/bin/zsh

unsetopt XTRACE
set -euo pipefail
umask 077

fail() {
  print -u2 "Developer ID DMG packaging failed: $*"
  exit 1
}

require_value() {
  local name="$1"
  [[ -n "${(P)name:-}" ]] || fail "missing environment variable ${name}"
}

for required_name in \
  APP_BUNDLE \
  APP_NOTARIZATION_METADATA \
  DIST_DIR \
  DMG_EVIDENCE_DIR \
  VERSION \
  BUILD_NUMBER \
  TAG \
  COMMIT \
  MACOSX_DEPLOYMENT_TARGET \
  BUNDLE_IDENTIFIER \
  DEVELOPER_ID_TEAM_ID \
  DEVELOPER_ID_SIGNING_IDENTITY \
  DEVELOPER_ID_CERTIFICATE \
  DEVELOPER_ID_CERTIFICATE_SHA256 \
  APP_VERIFY_SCRIPT \
  DMG_VERIFY_SCRIPT; do
  require_value "$required_name"
done

dmg_submission_id_requested="${DMG_NOTARY_SUBMISSION_ID:-}"
notary_timeout="${NOTARY_TIMEOUT:-30m}"
notary_keychain_profile="${NOTARY_KEYCHAIN_PROFILE:-}"
notary_api_key_path="${NOTARY_API_KEY_PATH:-}"
notary_api_key_id="${NOTARY_API_KEY_ID:-}"
notary_api_issuer_id="${NOTARY_API_ISSUER_ID:-}"
developer_id_signing_keychain="${DEVELOPER_ID_SIGNING_KEYCHAIN:-}"
dmg_identifier="${DMG_IDENTIFIER:-mx.loo.estrobo.dmg}"
dmg_volume_name="${DMG_VOLUME_NAME:-Estrobo}"
repository_url="${REPOSITORY_URL:-https://github.com/loomitz/estrobo}"
hdiutil_command="${HDIUTIL_COMMAND:-/usr/bin/hdiutil}"
codesign_command="${CODESIGN_COMMAND:-/usr/bin/codesign}"
spctl_command="${SPCTL_COMMAND:-/usr/sbin/spctl}"
diskutil_command="${DISKUTIL_COMMAND:-/usr/sbin/diskutil}"
xcrun_command="${XCRUN_COMMAND:-/usr/bin/xcrun}"
ditto_command="${DITTO_COMMAND:-/usr/bin/ditto}"
repository_root="${0:A:h:h}"

for command_path in \
  "$hdiutil_command" \
  "$codesign_command" \
  "$spctl_command" \
  "$diskutil_command" \
  "$xcrun_command" \
  "$ditto_command" \
  "$APP_VERIFY_SCRIPT" \
  "$DMG_VERIFY_SCRIPT"; do
  [[ -x "$command_path" ]] || fail "required command is not executable: $command_path"
done

APP_BUNDLE="${APP_BUNDLE:A}"
APP_NOTARIZATION_METADATA="${APP_NOTARIZATION_METADATA:A}"
DIST_DIR="${DIST_DIR:A}"
DMG_EVIDENCE_DIR="${DMG_EVIDENCE_DIR:A}"
DEVELOPER_ID_CERTIFICATE="${DEVELOPER_ID_CERTIFICATE:A}"
DEVELOPER_ID_CERTIFICATE_SHA256="${DEVELOPER_ID_CERTIFICATE_SHA256:A}"

[[ -d "$APP_BUNDLE" ]] || fail "app bundle not found: $APP_BUNDLE"
[[ -r "$APP_NOTARIZATION_METADATA" ]] || fail "app notarization metadata not found"
[[ -r "$DEVELOPER_ID_CERTIFICATE" ]] || fail "Developer ID certificate not found"
[[ -r "$DEVELOPER_ID_CERTIFICATE_SHA256" ]] || fail "Developer ID certificate digest not found"
[[ "$TAG" =~ '^v[0-9]+\.[0-9]+\.[0-9]+-beta\.[0-9]+$' ]] || fail "invalid release tag: $TAG"
[[ "$TAG" == "v${VERSION}-beta.${BUILD_NUMBER}" ]] || \
  fail "tag '$TAG' does not match version/build 'v${VERSION}-beta.${BUILD_NUMBER}'"
[[ "$COMMIT" =~ '^[0-9a-f]{40}$' ]] || fail "COMMIT must be a full lowercase Git commit SHA"
[[ "$DEVELOPER_ID_TEAM_ID" =~ '^[A-Z0-9]{10}$' ]] || fail "invalid Developer ID Team ID"
[[ "$DEVELOPER_ID_SIGNING_IDENTITY" != - ]] || fail "Developer ID signing identity cannot be ad hoc"
[[ "$dmg_identifier" == mx.loo.estrobo.dmg ]] || fail "unexpected DMG signing identifier"
[[ "$dmg_volume_name" == Estrobo ]] || fail "unexpected DMG volume name"
[[ "$notary_timeout" =~ '^[1-9][0-9]*([smh])?$' ]] || fail "invalid NOTARY_TIMEOUT"
[[ "$DMG_EVIDENCE_DIR" != / && "$DIST_DIR" != / ]] || fail "release paths cannot be the filesystem root"
[[ "$DMG_EVIDENCE_DIR" != "$APP_BUNDLE" && "$DMG_EVIDENCE_DIR" != "$APP_BUNDLE/"* ]] || \
  fail "DMG evidence must not be inside the signed app bundle"
[[ "$DMG_EVIDENCE_DIR" != "$repository_root" && "$DMG_EVIDENCE_DIR" != "$repository_root/"* ]] || \
  fail "private DMG evidence must be outside the repository"
[[ "$DMG_EVIDENCE_DIR" != "$DIST_DIR" && \
   "$DMG_EVIDENCE_DIR" != "$DIST_DIR/"* && \
   "$DIST_DIR" != "$DMG_EVIDENCE_DIR/"* ]] || \
  fail "evidence and public distribution directories must not contain one another"
[[ ! -e "$DIST_DIR" || ( -d "$DIST_DIR" && ! -L "$DIST_DIR" ) ]] || \
  fail "public distribution path must be a non-symlink directory"
if [[ -n "$developer_id_signing_keychain" ]]; then
  developer_id_signing_keychain="${developer_id_signing_keychain:A}"
  [[ -f "$developer_id_signing_keychain" ]] || fail "Developer ID signing keychain not found"
fi
if [[ -n "$dmg_submission_id_requested" ]]; then
  [[ "$dmg_submission_id_requested" =~ '^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$' ]] || \
    fail "DMG_NOTARY_SUBMISSION_ID must use UUID format"
fi

auth_args=()
if [[ -n "$notary_keychain_profile" ]]; then
  [[ -z "${notary_api_key_path}${notary_api_key_id}${notary_api_issuer_id}" ]] || \
    fail "NOTARY_KEYCHAIN_PROFILE cannot be combined with notary API key credentials"
  [[ "$notary_keychain_profile" =~ '^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$' ]] || \
    fail "NOTARY_KEYCHAIN_PROFILE contains unsupported characters"
  auth_args=(--keychain-profile "$notary_keychain_profile")
else
  [[ -n "$notary_api_key_path" && -n "$notary_api_key_id" && -n "$notary_api_issuer_id" ]] || \
    fail "provide either NOTARY_KEYCHAIN_PROFILE or the complete notary API key credential set"
  notary_api_key_path="${notary_api_key_path:A}"
  [[ -r "$notary_api_key_path" ]] || fail "notary API private key not found"
  [[ "$notary_api_key_id" =~ '^[A-Za-z0-9]{10,}$' ]] || fail "invalid notary API Key ID"
  [[ "$notary_api_issuer_id" =~ '^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$' ]] || \
    fail "invalid notary API Issuer ID"
  auth_args=(--key "$notary_api_key_path" --key-id "$notary_api_key_id" --issuer "$notary_api_issuer_id")
fi

app_metadata_value() {
  /usr/bin/plutil -extract "$1" raw -o - "$APP_NOTARIZATION_METADATA" 2>/dev/null
}

[[ "$(app_metadata_value schemaVersion)" == 1 ]] || fail "unsupported app notarization metadata schema"
[[ "$(app_metadata_value appBundle)" == "${APP_BUNDLE:t}" ]] || fail "app notarization metadata names a different bundle"
[[ "$(app_metadata_value teamIdentifier)" == "$DEVELOPER_ID_TEAM_ID" ]] || fail "app notarization Team ID mismatch"
[[ "$(app_metadata_value status)" == Accepted ]] || fail "app notarization metadata is not Accepted"
[[ "$(app_metadata_value ticketStapled)" == true ]] || fail "app notarization metadata does not confirm stapling"
[[ "$(app_metadata_value bundleIdentifier)" == "$BUNDLE_IDENTIFIER" ]] || \
  fail "app notarization metadata bundle identifier mismatch"
app_metadata_code_directory_hash="$(app_metadata_value codeDirectoryHash)" || \
  fail "app notarization metadata lacks a CodeDirectory hash"
[[ "$app_metadata_code_directory_hash" =~ '^[0-9a-f]{40}$' ]] || \
  fail "app notarization metadata contains an invalid CodeDirectory hash"
app_submission_id_raw="$(app_metadata_value submissionId)" || fail "app notarization metadata lacks a submission ID"
app_upload_digest="$(app_metadata_value uploadSHA256)" || fail "app notarization metadata lacks an upload digest"
[[ "$app_submission_id_raw" =~ '^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$' ]] || \
  fail "invalid app notarization submission ID"
app_submission_id="${app_submission_id_raw:l}"
[[ "$app_upload_digest" =~ '^[0-9a-f]{64}$' ]] || fail "invalid app notarization upload digest"

APP_BUNDLE="$APP_BUNDLE" \
VERSION="$VERSION" \
BUILD_NUMBER="$BUILD_NUMBER" \
SOURCE_COMMIT="$COMMIT" \
BUNDLE_IDENTIFIER="$BUNDLE_IDENTIFIER" \
MACOSX_DEPLOYMENT_TARGET="$MACOSX_DEPLOYMENT_TARGET" \
DEVELOPER_ID_TEAM_ID="$DEVELOPER_ID_TEAM_ID" \
DEVELOPER_ID_CERTIFICATE="$DEVELOPER_ID_CERTIFICATE" \
DEVELOPER_ID_CERTIFICATE_SHA256="$DEVELOPER_ID_CERTIFICATE_SHA256" \
  "$APP_VERIFY_SCRIPT"

current_app_signature_details="$("$codesign_command" -dvvv "$APP_BUNDLE" 2>&1)" || \
  fail "could not inspect the notarized app identity"
current_app_code_directory_hash="$(
  print -r -- "$current_app_signature_details" | \
    /usr/bin/awk -F= '$1 == "CDHash" { print tolower(substr($0, index($0, "=") + 1)); exit }'
)"
[[ "$current_app_code_directory_hash" == "$app_metadata_code_directory_hash" ]] || \
  fail "app notarization evidence does not belong to this signed app"

dmg_name="estrobo-${TAG}-macos-universal.dmg"
manifest_name="estrobo-${TAG}-manifest.json"
checksums_name=SHA256SUMS
public_dmg="$DIST_DIR/$dmg_name"
public_manifest="$DIST_DIR/$manifest_name"
public_checksums="$DIST_DIR/$checksums_name"
for public_path in "$public_dmg" "$public_manifest" "$public_checksums"; do
  [[ ! -e "$public_path" && ! -L "$public_path" ]] || \
    fail "refusing to overwrite public artifact: $public_path"
done

upload_dmg="$DMG_EVIDENCE_DIR/notary-upload.dmg"
upload_digest_file="$DMG_EVIDENCE_DIR/notary-upload.sha256"
submit_result="$DMG_EVIDENCE_DIR/notary-submit.json"
wait_result="$DMG_EVIDENCE_DIR/notary-wait.json"
notary_log="$DMG_EVIDENCE_DIR/notary-log.json"
dmg_metadata="$DMG_EVIDENCE_DIR/notarization-metadata.json"
pending_metadata="$DMG_EVIDENCE_DIR/notarization-metadata.pending.json"
[[ ! -e "$dmg_metadata" && ! -L "$dmg_metadata" ]] || fail "DMG notarization already has accepted metadata"

working_dirs=()
published_paths=()
package_complete=false
operation_lock="$DMG_EVIDENCE_DIR/.notarization-operation.lock"
operation_lock_acquired=false
notary_temporary_dir=""
cleanup() {
  for working_dir in "${working_dirs[@]}"; do
    [[ -n "$working_dir" && -d "$working_dir" ]] && /bin/rm -rf -- "$working_dir"
  done
  if [[ "$package_complete" != true ]]; then
    for published_path in "${published_paths[@]}"; do
      [[ -n "$published_path" ]] && /bin/rm -f -- "$published_path"
    done
  fi
  if [[ "$operation_lock_acquired" == true ]]; then
    /bin/rmdir "$operation_lock" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

sensitive_notary_values=(
  "$notary_keychain_profile"
  "$notary_api_key_path"
  "$notary_api_key_id"
  "$notary_api_issuer_id"
)

ensure_notary_temporary_dir() {
  if [[ -z "$notary_temporary_dir" ]]; then
    notary_temporary_dir="$(/usr/bin/mktemp -d /tmp/estrobo-dmg-notary-output.XXXXXX)" || \
      fail "could not create private DMG notarytool output staging"
    /bin/chmod 700 "$notary_temporary_dir"
    working_dirs+=("$notary_temporary_dir")
  fi
}

sanitize_notary_output() {
  local source_path="$1"
  local destination_path="$2"
  local sanitized_content=""
  local sensitive_value
  [[ -f "$source_path" && ! -L "$source_path" ]] || \
    fail "notarytool did not produce a safe regular output file"
  sanitized_content="$(<"$source_path")"
  for sensitive_value in "${sensitive_notary_values[@]}"; do
    [[ -z "$sensitive_value" ]] || \
      sanitized_content="${sanitized_content//${(b)sensitive_value}/[REDACTED]}"
  done
  print -rn -- "$sanitized_content" >"$destination_path"
  /bin/chmod 600 "$destination_path"
  unset sanitized_content
}

run_notarytool_json() {
  local destination_path="$1"
  shift
  local command_status=0
  local raw_stdout
  local raw_stderr
  ensure_notary_temporary_dir
  raw_stdout="$(/usr/bin/mktemp "$notary_temporary_dir/stdout.XXXXXX")"
  raw_stderr="$(/usr/bin/mktemp "$notary_temporary_dir/stderr.XXXXXX")"
  "$xcrun_command" "$@" >"$raw_stdout" 2>"$raw_stderr" || command_status=$?
  sanitize_notary_output "$raw_stdout" "$destination_path"
  /bin/rm -f -- "$raw_stdout" "$raw_stderr"
  return "$command_status"
}

run_notarytool_log() {
  local destination_path="$1"
  local requested_submission_id="$2"
  shift 2
  local command_status=0
  local raw_log
  local raw_stdout
  local raw_stderr
  ensure_notary_temporary_dir
  raw_log="$(/usr/bin/mktemp "$notary_temporary_dir/log.XXXXXX")"
  raw_stdout="$(/usr/bin/mktemp "$notary_temporary_dir/stdout.XXXXXX")"
  raw_stderr="$(/usr/bin/mktemp "$notary_temporary_dir/stderr.XXXXXX")"
  "$xcrun_command" notarytool log \
    "$requested_submission_id" \
    "$raw_log" \
    "$@" >"$raw_stdout" 2>"$raw_stderr" || command_status=$?
  sanitize_notary_output "$raw_log" "$destination_path"
  /bin/rm -f -- "$raw_log" "$raw_stdout" "$raw_stderr"
  return "$command_status"
}

acquire_operation_lock() {
  /bin/mkdir "$operation_lock" 2>/dev/null || \
    fail "another DMG operation is active or a stale operation lock requires inspection"
  operation_lock_acquired=true
}

preserve_output() {
  local output_path="$1"
  [[ -e "$output_path" ]] || return 0
  local preserved_path="${output_path}.previous"
  local suffix=1
  while [[ -e "$preserved_path" ]]; do
    preserved_path="${output_path}.previous.${suffix}"
    (( suffix += 1 ))
  done
  /bin/mv -- "$output_path" "$preserved_path"
}

verify_upload_image() {
  "$hdiutil_command" verify "$upload_dmg"
  local verification_dir
  verification_dir="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/estrobo-dmg-upload-verify.XXXXXX")"
  working_dirs+=("$verification_dir")
  local image_info="$verification_dir/image-info.plist"
  "$hdiutil_command" imageinfo -plist "$upload_dmg" >"$image_info"
  [[ "$(/usr/bin/plutil -extract Format raw -o - "$image_info")" == UDZO ]] || fail "notary upload is not UDZO"
  [[ "$(/usr/bin/plutil -extract Properties.Compressed raw -o - "$image_info")" == true ]] || fail "notary upload is not compressed"
  [[ "$(/usr/bin/plutil -extract Properties.Encrypted raw -o - "$image_info")" == false ]] || fail "notary upload is encrypted"

  "$codesign_command" --verify --strict --verbose=4 "$upload_dmg"
  local signature_details
  signature_details="$("$codesign_command" -dvvv "$upload_dmg" 2>&1)"
  print -r -- "$signature_details"
  print -r -- "$signature_details" | /usr/bin/grep -Fqx 'Format=disk image' || fail "notary upload is not signed as a disk image"
  print -r -- "$signature_details" | /usr/bin/grep -Fqx "Identifier=$dmg_identifier" || fail "notary upload signing identifier mismatch"
  print -r -- "$signature_details" | /usr/bin/grep -Eq '^Authority=Developer ID Application:' || fail "notary upload authority is not Developer ID Application"
  print -r -- "$signature_details" | /usr/bin/grep -Fqx "TeamIdentifier=$DEVELOPER_ID_TEAM_ID" || fail "notary upload TeamIdentifier mismatch"
  print -r -- "$signature_details" | /usr/bin/grep -Eq '^Timestamp=' || fail "notary upload secure timestamp is missing"

  local certificate_prefix="$verification_dir/signing-certificate"
  "$codesign_command" -d --extract-certificates="$certificate_prefix" "$upload_dmg" >/dev/null 2>&1 || \
    fail "could not extract the notary upload signing certificate"
  [[ -r "${certificate_prefix}0" ]] || fail "notary upload does not contain a leaf certificate"
  local expected_certificate_digest
  local signed_certificate_digest
  expected_certificate_digest="$(/usr/bin/awk 'NF { print tolower($1); exit }' "$DEVELOPER_ID_CERTIFICATE_SHA256")"
  signed_certificate_digest="$(/usr/bin/shasum -a 256 "${certificate_prefix}0" | /usr/bin/awk '{ print tolower($1) }')"
  [[ "$signed_certificate_digest" == "$expected_certificate_digest" ]] || fail "notary upload certificate digest mismatch"
  /usr/bin/cmp -s "$DEVELOPER_ID_CERTIFICATE" "${certificate_prefix}0" || fail "notary upload certificate bytes mismatch"
}

verify_private_resume_file() {
  local path="$1"
  [[ "$(/usr/bin/stat -f '%u' "$path")" == "$(/usr/bin/id -u)" ]] || \
    fail "preserved evidence file is not owned by the current user: ${path:t}"
  [[ "$(/usr/bin/stat -f '%Lp' "$path")" == 600 ]] || \
    fail "preserved evidence file must already use mode 0600: ${path:t}"
}

if [[ -n "$dmg_submission_id_requested" ]]; then
  [[ -d "$DMG_EVIDENCE_DIR" && ! -L "$DMG_EVIDENCE_DIR" ]] || fail "cannot resume without the original evidence directory"
  [[ -f "$upload_dmg" && ! -L "$upload_dmg" && -r "$upload_dmg" ]] || \
    fail "cannot resume without the exact submitted DMG"
  [[ -f "$upload_digest_file" && ! -L "$upload_digest_file" && -r "$upload_digest_file" ]] || \
    fail "cannot resume without the submitted DMG checksum"
  [[ -f "$submit_result" && ! -L "$submit_result" && -r "$submit_result" ]] || \
    fail "cannot resume without the original submit result"
  [[ "$(/usr/bin/stat -f '%u' "$DMG_EVIDENCE_DIR")" == "$(/usr/bin/id -u)" ]] || \
    fail "DMG evidence directory is not owned by the current user"
  [[ "$(/usr/bin/stat -f '%Lp' "$DMG_EVIDENCE_DIR")" == 700 ]] || \
    fail "DMG evidence directory must already use mode 0700 before resume"
  verify_private_resume_file "$upload_dmg"
  verify_private_resume_file "$upload_digest_file"
  verify_private_resume_file "$submit_result"
  submission_id_raw="$(/usr/bin/plutil -extract id raw -o - "$submit_result" 2>/dev/null)" || \
    fail "original submit result does not contain an ID"
  [[ "$submission_id_raw" =~ '^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$' ]] || \
    fail "original submit result contains an invalid ID"
  submission_id="${submission_id_raw:l}"
  [[ "${dmg_submission_id_requested:l}" == "$submission_id" ]] || \
    fail "DMG_NOTARY_SUBMISSION_ID does not match the preserved submit result"
  recorded_upload_digest="$(/usr/bin/awk 'NF { print tolower($1); exit }' "$upload_digest_file")"
  actual_upload_digest="$(/usr/bin/shasum -a 256 "$upload_dmg" | /usr/bin/awk '{ print tolower($1) }')"
  [[ "$recorded_upload_digest" =~ '^[0-9a-f]{64}$' ]] || fail "preserved upload checksum is invalid"
  [[ "$actual_upload_digest" == "$recorded_upload_digest" ]] || fail "preserved upload DMG digest mismatch"
  acquire_operation_lock
  verify_upload_image
  preserve_output "$wait_result"
  preserve_output "$notary_log"
  print "Resuming DMG notarization submission without submit: $submission_id"
else
  [[ ! -e "$DMG_EVIDENCE_DIR" && ! -L "$DMG_EVIDENCE_DIR" ]] || \
    fail "DMG evidence directory already exists; use a new directory or resume its preserved submission"
  /bin/mkdir -p "${DMG_EVIDENCE_DIR:h}"
  /bin/mkdir "$DMG_EVIDENCE_DIR" || fail "could not atomically claim the DMG evidence directory"
  /bin/chmod 700 "$DMG_EVIDENCE_DIR"
  acquire_operation_lock

  source_stage="$(/usr/bin/mktemp -d "$DMG_EVIDENCE_DIR/.dmg-root.XXXXXX")"
  working_dirs+=("$source_stage")
  "$ditto_command" "$APP_BUNDLE" "$source_stage/estrobo.app"
  /bin/ln -s /Applications "$source_stage/Applications"
  source_entries="$(
    /usr/bin/find "$source_stage" -mindepth 1 -maxdepth 1 -exec /usr/bin/basename {} \; | LC_ALL=C /usr/bin/sort
  )"
  [[ "$source_entries" == $'Applications\nestrobo.app' ]] || fail "DMG source root is not the exact two-entry contract"
  [[ -L "$source_stage/Applications" && "$(/usr/bin/readlink "$source_stage/Applications")" == /Applications ]] || \
    fail "DMG source Applications link is invalid"

  "$hdiutil_command" create \
    -fs HFS+ \
    -volname "$dmg_volume_name" \
    -srcfolder "$source_stage" \
    -format UDZO \
    -imagekey zlib-level=9 \
    "$upload_dmg"
  /bin/chmod 600 "$upload_dmg"

  signing_args=(--force --sign "$DEVELOPER_ID_SIGNING_IDENTITY")
  if [[ -n "$developer_id_signing_keychain" ]]; then
    signing_args+=(--keychain "$developer_id_signing_keychain")
  fi
  signing_args+=(--identifier "$dmg_identifier" --timestamp "$upload_dmg")
  "$codesign_command" "${signing_args[@]}"
  verify_upload_image

  actual_upload_digest="$(/usr/bin/shasum -a 256 "$upload_dmg" | /usr/bin/awk '{ print tolower($1) }')"
  [[ "$actual_upload_digest" =~ '^[0-9a-f]{64}$' ]] || fail "could not calculate submitted DMG digest"
  print -r -- "$actual_upload_digest  ${upload_dmg:t}" >"$upload_digest_file"
  /bin/chmod 600 "$upload_digest_file"

  submit_status=0
  run_notarytool_json "$submit_result" notarytool submit \
    "$upload_dmg" \
    "${auth_args[@]}" \
    --no-wait \
    --output-format json || submit_status=$?
  [[ "$submit_status" -eq 0 ]] || \
    fail "notarytool submit failed; exact DMG evidence was preserved and no retry was attempted"
  submission_id_raw="$(/usr/bin/plutil -extract id raw -o - "$submit_result" 2>/dev/null)" || \
    fail "notarytool submit did not return an ID"
  [[ "$submission_id_raw" =~ '^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$' ]] || \
    fail "notarytool returned an invalid submission ID"
  submission_id="${submission_id_raw:l}"
  print "DMG notarization submitted once: $submission_id"
fi

[[ "$submission_id" != "$app_submission_id" ]] || fail "DMG and app notarization submissions must be distinct"

wait_status=0
run_notarytool_json "$wait_result" notarytool wait \
  "$submission_id_raw" \
  "${auth_args[@]}" \
  --timeout "$notary_timeout" \
  --output-format json || wait_status=$?

log_status=0
run_notarytool_log "$notary_log" \
  "$submission_id_raw" \
  "${auth_args[@]}" || log_status=$?

[[ "$wait_status" -eq 0 ]] || \
  fail "notarytool wait failed or timed out for $submission_id; resume this ID and never submit again"
[[ "$log_status" -eq 0 ]] || fail "could not download the DMG notarization log"

wait_id_raw="$(/usr/bin/plutil -extract id raw -o - "$wait_result" 2>/dev/null)" || fail "wait result lacks an ID"
wait_status_text="$(/usr/bin/plutil -extract status raw -o - "$wait_result" 2>/dev/null)" || fail "wait result lacks a status"
log_id_raw="$(/usr/bin/plutil -extract jobId raw -o - "$notary_log" 2>/dev/null)" || fail "notary log lacks jobId"
log_status_text="$(/usr/bin/plutil -extract status raw -o - "$notary_log" 2>/dev/null)" || fail "notary log lacks status"
logged_upload_digest="$(/usr/bin/plutil -extract sha256 raw -o - "$notary_log" 2>/dev/null | /usr/bin/tr '[:upper:]' '[:lower:]')" || \
  fail "notary log lacks upload digest"
[[ "${wait_id_raw:l}" == "$submission_id" ]] || fail "submit and wait IDs differ"
[[ "${log_id_raw:l}" == "$submission_id" ]] || fail "submit and log IDs differ"
[[ "$wait_status_text" == Accepted && "$log_status_text" == Accepted ]] || fail "Apple did not accept the DMG"
[[ "$logged_upload_digest" == "$actual_upload_digest" ]] || fail "Apple log digest does not match the exact submitted DMG"
issues_type="$(/usr/bin/plutil -type issues "$notary_log" 2>/dev/null)" || fail "notary log lacks issues"
case "$issues_type" in
  '(any)')
    ;;
  array)
    issues_count="$(/usr/bin/plutil -extract issues raw -o - "$notary_log")"
    [[ "$issues_count" == 0 ]] || fail "notary log contains $issues_count issue(s)"
    ;;
  *)
    fail "notary log issues field has unexpected type '$issues_type'"
    ;;
esac

/bin/mkdir -p "$DIST_DIR"
publish_stage="$(/usr/bin/mktemp -d "$DIST_DIR/.developer-id-dmg.XXXXXX")"
working_dirs+=("$publish_stage")
staged_dmg="$publish_stage/$dmg_name"
staged_manifest="$publish_stage/$manifest_name"
staged_checksums="$publish_stage/$checksums_name"
"$ditto_command" "$upload_dmg" "$staged_dmg"
[[ "$(/usr/bin/shasum -a 256 "$staged_dmg" | /usr/bin/awk '{ print tolower($1) }')" == "$actual_upload_digest" ]] || \
  fail "staged DMG changed before stapling"

"$xcrun_command" stapler staple -v "$staged_dmg"
"$xcrun_command" stapler validate -v "$staged_dmg"
[[ "$(/usr/bin/shasum -a 256 "$upload_dmg" | /usr/bin/awk '{ print tolower($1) }')" == "$actual_upload_digest" ]] || \
  fail "exact submitted DMG changed after notarization"

final_digest="$(/usr/bin/shasum -a 256 "$staged_dmg" | /usr/bin/awk '{ print tolower($1) }')"
final_size="$(/usr/bin/stat -f '%z' "$staged_dmg")"
log_digest="$(/usr/bin/shasum -a 256 "$notary_log" | /usr/bin/awk '{ print tolower($1) }')"
certificate_digest="$(/usr/bin/awk 'NF { print tolower($1); exit }' "$DEVELOPER_ID_CERTIFICATE_SHA256")"
[[ "$final_digest" =~ '^[0-9a-f]{64}$' && "$log_digest" =~ '^[0-9a-f]{64}$' && "$certificate_digest" =~ '^[0-9a-f]{64}$' ]] || \
  fail "could not calculate release evidence digests"

/usr/bin/plutil -create xml1 "$staged_manifest"
/usr/bin/plutil -insert schemaVersion -integer 3 "$staged_manifest"
/usr/bin/plutil -insert releaseKind -string developer-id-notarized-dmg "$staged_manifest"
/usr/bin/plutil -insert product -dictionary "$staged_manifest"
/usr/bin/plutil -insert product.name -string estrobo "$staged_manifest"
/usr/bin/plutil -insert product.bundleIdentifier -string "$BUNDLE_IDENTIFIER" "$staged_manifest"
/usr/bin/plutil -insert product.version -string "$VERSION" "$staged_manifest"
/usr/bin/plutil -insert product.build -string "$BUILD_NUMBER" "$staged_manifest"
/usr/bin/plutil -insert product.architectures -json '["arm64","x86_64"]' "$staged_manifest"
/usr/bin/plutil -insert product.minimumMacOSVersion -string "$MACOSX_DEPLOYMENT_TARGET" "$staged_manifest"
/usr/bin/plutil -insert source -dictionary "$staged_manifest"
/usr/bin/plutil -insert source.repository -string "$repository_url" "$staged_manifest"
/usr/bin/plutil -insert source.tag -string "$TAG" "$staged_manifest"
/usr/bin/plutil -insert source.commit -string "$COMMIT" "$staged_manifest"
/usr/bin/plutil -insert source.provenance -string manual-exact-asset-promotion "$staged_manifest"
/usr/bin/plutil -insert artifact -dictionary "$staged_manifest"
/usr/bin/plutil -insert artifact.filename -string "$dmg_name" "$staged_manifest"
/usr/bin/plutil -insert artifact.format -string UDIF-UDZO "$staged_manifest"
/usr/bin/plutil -insert artifact.sha256 -string "$final_digest" "$staged_manifest"
/usr/bin/plutil -insert artifact.sizeBytes -integer "$final_size" "$staged_manifest"
/usr/bin/plutil -insert artifact.contents -json '["estrobo.app","Applications -> /Applications"]' "$staged_manifest"
/usr/bin/plutil -insert signing -dictionary "$staged_manifest"
/usr/bin/plutil -insert signing.type -string developer-id "$staged_manifest"
/usr/bin/plutil -insert signing.teamIdentifier -string "$DEVELOPER_ID_TEAM_ID" "$staged_manifest"
/usr/bin/plutil -insert signing.certificateSHA256 -string "$certificate_digest" "$staged_manifest"
/usr/bin/plutil -insert signing.diskImageIdentifier -string "$dmg_identifier" "$staged_manifest"
/usr/bin/plutil -insert signing.hardenedRuntime -bool true "$staged_manifest"
/usr/bin/plutil -insert signing.secureTimestamp -bool true "$staged_manifest"
/usr/bin/plutil -insert notarization -dictionary "$staged_manifest"
/usr/bin/plutil -insert notarization.application -dictionary "$staged_manifest"
/usr/bin/plutil -insert notarization.application.submissionId -string "$app_submission_id" "$staged_manifest"
/usr/bin/plutil -insert notarization.application.status -string Accepted "$staged_manifest"
/usr/bin/plutil -insert notarization.application.uploadSHA256 -string "$app_upload_digest" "$staged_manifest"
/usr/bin/plutil -insert notarization.application.codeDirectoryHash -string "$app_metadata_code_directory_hash" "$staged_manifest"
/usr/bin/plutil -insert notarization.application.ticketStapled -bool true "$staged_manifest"
/usr/bin/plutil -insert notarization.diskImage -dictionary "$staged_manifest"
/usr/bin/plutil -insert notarization.diskImage.submissionId -string "$submission_id" "$staged_manifest"
/usr/bin/plutil -insert notarization.diskImage.status -string Accepted "$staged_manifest"
/usr/bin/plutil -insert notarization.diskImage.uploadSHA256 -string "$actual_upload_digest" "$staged_manifest"
/usr/bin/plutil -insert notarization.diskImage.finalSHA256 -string "$final_digest" "$staged_manifest"
/usr/bin/plutil -insert notarization.diskImage.ticketStapled -bool true "$staged_manifest"
/usr/bin/plutil -insert verification -dictionary "$staged_manifest"
/usr/bin/plutil -insert verification.gatekeeperSource -string 'Notarized Developer ID' "$staged_manifest"
/usr/bin/plutil -insert verification.githubBuildProvenanceAttestation -bool false "$staged_manifest"
/usr/bin/plutil -insert verification.physicalSmoke -string pending "$staged_manifest"
/usr/bin/plutil -convert json -r "$staged_manifest"

(
  cd "$publish_stage"
  /usr/bin/shasum -a 256 "$dmg_name" "$manifest_name" >"$checksums_name"
  /usr/bin/shasum -a 256 -c "$checksums_name"
)
/bin/chmod 644 "$staged_dmg" "$staged_manifest" "$staged_checksums"

preserve_output "$pending_metadata"
/usr/bin/plutil -create xml1 "$pending_metadata"
/usr/bin/plutil -insert schemaVersion -integer 1 "$pending_metadata"
/usr/bin/plutil -insert artifactKind -string disk-image "$pending_metadata"
/usr/bin/plutil -insert artifact -string "$dmg_name" "$pending_metadata"
/usr/bin/plutil -insert appBundle -string "${APP_BUNDLE:t}" "$pending_metadata"
/usr/bin/plutil -insert teamIdentifier -string "$DEVELOPER_ID_TEAM_ID" "$pending_metadata"
/usr/bin/plutil -insert signingIdentifier -string "$dmg_identifier" "$pending_metadata"
/usr/bin/plutil -insert appSubmissionId -string "$app_submission_id" "$pending_metadata"
/usr/bin/plutil -insert submissionId -string "$submission_id" "$pending_metadata"
/usr/bin/plutil -insert status -string Accepted "$pending_metadata"
/usr/bin/plutil -insert uploadSHA256 -string "$actual_upload_digest" "$pending_metadata"
/usr/bin/plutil -insert logSHA256 -string "$log_digest" "$pending_metadata"
/usr/bin/plutil -insert finalSHA256 -string "$final_digest" "$pending_metadata"
/usr/bin/plutil -insert ticketStapled -bool true "$pending_metadata"
/usr/bin/plutil -insert format -string UDZO "$pending_metadata"
/usr/bin/plutil -insert volumeName -string "$dmg_volume_name" "$pending_metadata"
/usr/bin/plutil -insert tag -string "$TAG" "$pending_metadata"
/usr/bin/plutil -insert commit -string "$COMMIT" "$pending_metadata"
/usr/bin/plutil -convert json -r "$pending_metadata"
/bin/chmod 600 "$pending_metadata"

DMG="$staged_dmg" \
MANIFEST="$staged_manifest" \
CHECKSUMS="$staged_checksums" \
VERSION="$VERSION" \
BUILD_NUMBER="$BUILD_NUMBER" \
TAG="$TAG" \
COMMIT="$COMMIT" \
MACOSX_DEPLOYMENT_TARGET="$MACOSX_DEPLOYMENT_TARGET" \
BUNDLE_IDENTIFIER="$BUNDLE_IDENTIFIER" \
DEVELOPER_ID_TEAM_ID="$DEVELOPER_ID_TEAM_ID" \
DEVELOPER_ID_CERTIFICATE="$DEVELOPER_ID_CERTIFICATE" \
DEVELOPER_ID_CERTIFICATE_SHA256="$DEVELOPER_ID_CERTIFICATE_SHA256" \
APP_VERIFY_SCRIPT="$APP_VERIFY_SCRIPT" \
DMG_IDENTIFIER="$dmg_identifier" \
DMG_VOLUME_NAME="$dmg_volume_name" \
REPOSITORY_URL="$repository_url" \
HDIUTIL_COMMAND="$hdiutil_command" \
CODESIGN_COMMAND="$codesign_command" \
SPCTL_COMMAND="$spctl_command" \
DISKUTIL_COMMAND="$diskutil_command" \
XCRUN_COMMAND="$xcrun_command" \
  "$DMG_VERIFY_SCRIPT"

publish_file_atomically() {
  local staged_path="$1"
  local destination_path="$2"
  /bin/ln "$staged_path" "$destination_path" 2>/dev/null || \
    fail "refusing to overwrite concurrently created output: $destination_path"
  published_paths+=("$destination_path")
  /bin/rm -f -- "$staged_path"
}

publish_file_atomically "$staged_manifest" "$public_manifest"
publish_file_atomically "$staged_checksums" "$public_checksums"
publish_file_atomically "$staged_dmg" "$public_dmg"
/bin/ln "$pending_metadata" "$dmg_metadata" 2>/dev/null || \
  fail "refusing to overwrite accepted DMG metadata"
published_paths+=("$dmg_metadata")
/bin/rm -f -- "$pending_metadata"
package_complete=true

print "Developer ID DMG packaged and verified: $public_dmg"
print "SHA-256: $final_digest"
print "Manifest: $public_manifest"
print "Checksums: $public_checksums"
print "Private evidence: $DMG_EVIDENCE_DIR"
