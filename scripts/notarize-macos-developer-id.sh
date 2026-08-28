#!/bin/zsh

set -euo pipefail
umask 077

fail() {
  print -u2 "Developer ID notarization failed: $*"
  exit 1
}

require_value() {
  local name="$1"
  [[ -n "${(P)name:-}" ]] || fail "missing environment variable ${name}"
}

for required_name in \
  APP_BUNDLE \
  DEVELOPER_ID_TEAM_ID \
  NOTARIZATION_UPLOAD_ARCHIVE \
  NOTARIZATION_SUBMIT_RESULT \
  NOTARIZATION_WAIT_RESULT \
  NOTARIZATION_LOG \
  NOTARIZATION_METADATA; do
  require_value "$required_name"
done

notary_timeout="${NOTARY_TIMEOUT:-30m}"
resume_submission_id_raw="${NOTARY_SUBMISSION_ID:-}"
notary_keychain_profile="${NOTARY_KEYCHAIN_PROFILE:-}"
notary_api_key_path="${NOTARY_API_KEY_PATH:-}"
notary_api_key_id="${NOTARY_API_KEY_ID:-}"
notary_api_issuer_id="${NOTARY_API_ISSUER_ID:-}"
xcrun_command="${XCRUN_COMMAND:-/usr/bin/xcrun}"
ditto_command="${DITTO_COMMAND:-/usr/bin/ditto}"
codesign_command="${CODESIGN_COMMAND:-/usr/bin/codesign}"

[[ -d "$APP_BUNDLE" ]] || fail "app bundle not found: $APP_BUNDLE"
[[ "$DEVELOPER_ID_TEAM_ID" =~ '^[A-Z0-9]{10}$' ]] || \
  fail "DEVELOPER_ID_TEAM_ID must contain exactly 10 uppercase letters or digits"
[[ "$notary_timeout" =~ '^[1-9][0-9]*([smh])?$' ]] || \
  fail "NOTARY_TIMEOUT must be a positive duration such as 30m"
if [[ -n "$resume_submission_id_raw" ]]; then
  [[ "$resume_submission_id_raw" =~ '^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$' ]] || \
    fail "NOTARY_SUBMISSION_ID must use UUID format"
fi
[[ -x "$xcrun_command" ]] || fail "xcrun command is not executable: $xcrun_command"
[[ -x "$ditto_command" ]] || fail "ditto command is not executable: $ditto_command"
[[ -x "$codesign_command" ]] || fail "codesign command is not executable: $codesign_command"
evidence_dir="${NOTARIZATION_UPLOAD_ARCHIVE:h}"
upload_digest_file="${NOTARIZATION_UPLOAD_ARCHIVE}.sha256"
app_bundle_absolute="${APP_BUNDLE:A}"
evidence_dir_absolute="${evidence_dir:A}"
repository_root="${0:A:h:h}"
[[ "$evidence_dir_absolute" != "$app_bundle_absolute" && \
   "$evidence_dir_absolute" != "$app_bundle_absolute/"* ]] || \
  fail "notarization evidence directory must not be inside the signed app bundle"
if [[ -n "$notary_keychain_profile" ]]; then
  [[ "$evidence_dir_absolute" != "$repository_root" && \
     "$evidence_dir_absolute" != "$repository_root/"* ]] || \
    fail "local keychain-profile evidence must be outside the repository"
fi
evidence_paths=(
  "$NOTARIZATION_UPLOAD_ARCHIVE"
  "$NOTARIZATION_SUBMIT_RESULT"
  "$NOTARIZATION_WAIT_RESULT"
  "$NOTARIZATION_LOG"
  "$NOTARIZATION_METADATA"
  "$upload_digest_file"
)
for evidence_path in "${evidence_paths[@]}"; do
  [[ "${evidence_path:h}" == "$evidence_dir" ]] || \
    fail "all notarization evidence must share one directory"
done
for (( first_index = 1; first_index <= ${#evidence_paths}; first_index += 1 )); do
  for (( second_index = first_index + 1; second_index <= ${#evidence_paths}; second_index += 1 )); do
    [[ "${evidence_paths[$first_index]}" != "${evidence_paths[$second_index]}" ]] || \
      fail "notarization evidence paths must be distinct"
  done
done

operation_lock="$evidence_dir/.notarization-operation.lock"
operation_lock_acquired=false
notary_temporary_dir=""
cleanup() {
  if [[ -n "$notary_temporary_dir" && \
        "$notary_temporary_dir" == /tmp/estrobo-notary-output.* && \
        -d "$notary_temporary_dir" && ! -L "$notary_temporary_dir" ]]; then
    /bin/rm -rf -- "$notary_temporary_dir"
  fi
  if [[ "$operation_lock_acquired" == true ]]; then
    /bin/rmdir "$operation_lock" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

acquire_operation_lock() {
  /bin/mkdir "$operation_lock" 2>/dev/null || \
    fail "another notarization operation is active or a stale operation lock requires inspection"
  operation_lock_acquired=true
}

auth_args=()
if [[ -n "$notary_keychain_profile" ]]; then
  [[ -z "${notary_api_key_path}${notary_api_key_id}${notary_api_issuer_id}" ]] || \
    fail "NOTARY_KEYCHAIN_PROFILE cannot be combined with notary API key credentials"
  [[ "$notary_keychain_profile" =~ '^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$' ]] || \
    fail "NOTARY_KEYCHAIN_PROFILE must contain 1-64 letters, digits, dots, underscores, or hyphens"
  auth_args=(--keychain-profile "$notary_keychain_profile")
else
  [[ -n "$notary_api_key_path" && -n "$notary_api_key_id" && -n "$notary_api_issuer_id" ]] || \
    fail "provide either NOTARY_KEYCHAIN_PROFILE or the complete notary API key credential set"
  [[ -r "$notary_api_key_path" ]] || fail "notary API private key not found: $notary_api_key_path"
  [[ "$notary_api_key_id" =~ '^[A-Za-z0-9]{10,}$' ]] || \
    fail "NOTARY_API_KEY_ID must contain at least 10 letters or digits"
  [[ "$notary_api_issuer_id" =~ '^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$' ]] || \
    fail "NOTARY_API_ISSUER_ID must use UUID format"
  auth_args=(
    --key "$notary_api_key_path"
    --key-id "$notary_api_key_id"
    --issuer "$notary_api_issuer_id"
  )
fi

sensitive_notary_values=(
  "$notary_keychain_profile"
  "$notary_api_key_path"
  "$notary_api_key_id"
  "$notary_api_issuer_id"
)

ensure_notary_temporary_dir() {
  if [[ -z "$notary_temporary_dir" ]]; then
    notary_temporary_dir="$(/usr/bin/mktemp -d /tmp/estrobo-notary-output.XXXXXX)" || \
      fail "could not create private notarytool output staging"
    /bin/chmod 700 "$notary_temporary_dir"
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

app_signature_details="$("$codesign_command" -dvvv "$APP_BUNDLE" 2>&1)" || \
  fail "could not inspect the signed app identity"
app_bundle_identifier="$(
  print -r -- "$app_signature_details" | /usr/bin/awk -F= '$1 == "Identifier" { print substr($0, index($0, "=") + 1); exit }'
)"
app_team_identifier="$(
  print -r -- "$app_signature_details" | /usr/bin/awk -F= '$1 == "TeamIdentifier" { print substr($0, index($0, "=") + 1); exit }'
)"
app_code_directory_hash="$(
  print -r -- "$app_signature_details" | /usr/bin/awk -F= '$1 == "CDHash" { print tolower(substr($0, index($0, "=") + 1)); exit }'
)"
[[ "$app_bundle_identifier" =~ '^[A-Za-z0-9][A-Za-z0-9.-]{2,254}$' ]] || \
  fail "signed app has an invalid bundle identifier"
[[ "$app_team_identifier" == "$DEVELOPER_ID_TEAM_ID" ]] || \
  fail "signed app TeamIdentifier does not match DEVELOPER_ID_TEAM_ID"
[[ "$app_code_directory_hash" =~ '^[0-9a-f]{40}$' ]] || \
  fail "signed app does not expose a valid CodeDirectory hash"

preserve_resume_output() {
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

if [[ -n "$resume_submission_id_raw" ]]; then
  [[ -d "$evidence_dir" && ! -L "$evidence_dir" ]] || \
    fail "cannot resume without the original non-symlink evidence directory"
  [[ ! -e "$NOTARIZATION_METADATA" ]] || \
    fail "cannot resume a notarization that already produced accepted metadata"
  [[ -f "$NOTARIZATION_UPLOAD_ARCHIVE" && ! -L "$NOTARIZATION_UPLOAD_ARCHIVE" && \
     -r "$NOTARIZATION_UPLOAD_ARCHIVE" ]] || \
    fail "cannot resume without the exact notarization upload archive"
  [[ -f "$NOTARIZATION_SUBMIT_RESULT" && ! -L "$NOTARIZATION_SUBMIT_RESULT" && \
     -r "$NOTARIZATION_SUBMIT_RESULT" ]] || \
    fail "cannot resume without the original submit result"
  [[ -f "$upload_digest_file" && ! -L "$upload_digest_file" && -r "$upload_digest_file" ]] || \
    fail "cannot resume without the preserved upload checksum"
  submission_id_raw="$(/usr/bin/plutil -extract id raw -o - "$NOTARIZATION_SUBMIT_RESULT" 2>/dev/null)" || \
    fail "the original submit result does not contain a submission ID"
else
  [[ ! -e "$evidence_dir" ]] || \
    fail "notarization evidence directory already exists; use a new directory or resume the preserved submission"
  /bin/mkdir -p "${evidence_dir:h}"
  /bin/mkdir "$evidence_dir" || \
    fail "could not atomically claim the notarization evidence directory"
  /bin/chmod 700 "$evidence_dir"
  acquire_operation_lock
  "$ditto_command" -c -k --sequesterRsrc --keepParent \
    "$APP_BUNDLE" \
    "$NOTARIZATION_UPLOAD_ARCHIVE"

  upload_digest="$(/usr/bin/shasum -a 256 "$NOTARIZATION_UPLOAD_ARCHIVE" | /usr/bin/awk '{ print tolower($1) }')"
  [[ "$upload_digest" =~ '^[0-9a-f]{64}$' ]] || fail "could not calculate the notarization upload digest"
  print -r -- "$upload_digest  ${NOTARIZATION_UPLOAD_ARCHIVE:t}" >"$upload_digest_file"
  /bin/chmod 600 "$upload_digest_file"

  submit_status=0
  run_notarytool_json "$NOTARIZATION_SUBMIT_RESULT" notarytool submit \
    "$NOTARIZATION_UPLOAD_ARCHIVE" \
    "${auth_args[@]}" \
    --no-wait \
    --output-format json || submit_status=$?
  [[ "$submit_status" -eq 0 ]] || \
    fail "notarytool submit failed; the exact upload archive was preserved and no automatic resubmission was attempted"
  submission_id_raw="$(/usr/bin/plutil -extract id raw -o - "$NOTARIZATION_SUBMIT_RESULT" 2>/dev/null)" || \
    fail "notarytool submit did not return a submission ID"
fi

[[ "$submission_id_raw" =~ '^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$' ]] || \
  fail "notarytool returned an invalid submission ID"
submission_id="$(print -r -- "$submission_id_raw" | /usr/bin/tr '[:upper:]' '[:lower:]')"
if [[ -n "$resume_submission_id_raw" ]]; then
  resume_submission_id="$(print -r -- "$resume_submission_id_raw" | /usr/bin/tr '[:upper:]' '[:lower:]')"
  [[ "$resume_submission_id" == "$submission_id" ]] || \
    fail "NOTARY_SUBMISSION_ID does not match the preserved submit result"
  [[ "$(/usr/bin/stat -f '%u' "$evidence_dir")" == "$(/usr/bin/id -u)" ]] || \
    fail "the notarization evidence directory is not owned by the current user"
  [[ "$(/usr/bin/stat -f '%Lp' "$evidence_dir")" == 700 ]] || \
    fail "the notarization evidence directory must already use mode 0700 before resume"
  for private_resume_file in \
    "$NOTARIZATION_UPLOAD_ARCHIVE" \
    "$NOTARIZATION_SUBMIT_RESULT" \
    "$upload_digest_file"; do
    [[ "$(/usr/bin/stat -f '%u' "$private_resume_file")" == "$(/usr/bin/id -u)" ]] || \
      fail "preserved evidence file is not owned by the current user: ${private_resume_file:t}"
    [[ "$(/usr/bin/stat -f '%Lp' "$private_resume_file")" == 600 ]] || \
      fail "preserved evidence file must already use mode 0600: ${private_resume_file:t}"
  done
  recorded_upload_digest="$(/usr/bin/awk 'NF { print tolower($1); exit }' "$upload_digest_file")"
  current_upload_digest="$(/usr/bin/shasum -a 256 "$NOTARIZATION_UPLOAD_ARCHIVE" | /usr/bin/awk '{ print tolower($1) }')"
  [[ "$recorded_upload_digest" =~ '^[0-9a-f]{64}$' ]] || \
    fail "preserved upload checksum is invalid"
  [[ "$current_upload_digest" == "$recorded_upload_digest" ]] || \
    fail "preserved notarization upload no longer matches its checksum"
  upload_digest="$current_upload_digest"
  acquire_operation_lock
  preserve_resume_output "$NOTARIZATION_WAIT_RESULT"
  preserve_resume_output "$NOTARIZATION_LOG"
fi

if [[ -n "$resume_submission_id_raw" ]]; then
  print "Resuming Developer ID notarization submission: $submission_id"
else
  print "Developer ID notarization submitted once: $submission_id"
fi

wait_status=0
run_notarytool_json "$NOTARIZATION_WAIT_RESULT" notarytool wait \
  "$submission_id_raw" \
  "${auth_args[@]}" \
  --timeout "$notary_timeout" \
  --output-format json || wait_status=$?

log_status=0
run_notarytool_log "$NOTARIZATION_LOG" \
  "$submission_id_raw" \
  "${auth_args[@]}" || log_status=$?

[[ "$wait_status" -eq 0 ]] || \
  fail "notarytool wait failed or timed out for $submission_id; inspect the saved evidence and do not resubmit blindly"
[[ "$log_status" -eq 0 ]] || fail "could not download the notarization log for $submission_id"

wait_submission_id_raw="$(/usr/bin/plutil -extract id raw -o - "$NOTARIZATION_WAIT_RESULT" 2>/dev/null)" || \
  fail "notarytool wait did not return a submission ID"
wait_submission_id="$(print -r -- "$wait_submission_id_raw" | /usr/bin/tr '[:upper:]' '[:lower:]')"
wait_status_text="$(/usr/bin/plutil -extract status raw -o - "$NOTARIZATION_WAIT_RESULT" 2>/dev/null)" || \
  fail "notarytool wait did not return a status"
[[ "$wait_submission_id" == "$submission_id" ]] || fail "submit and wait results refer to different submissions"
[[ "$wait_status_text" == Accepted ]] || fail "Apple returned notarization status '$wait_status_text'"

log_submission_id_raw="$(/usr/bin/plutil -extract jobId raw -o - "$NOTARIZATION_LOG" 2>/dev/null)" || \
  fail "notarization log does not contain jobId"
log_submission_id="$(print -r -- "$log_submission_id_raw" | /usr/bin/tr '[:upper:]' '[:lower:]')"
log_status_text="$(/usr/bin/plutil -extract status raw -o - "$NOTARIZATION_LOG" 2>/dev/null)" || \
  fail "notarization log does not contain status"
log_upload_digest="$(/usr/bin/plutil -extract sha256 raw -o - "$NOTARIZATION_LOG" 2>/dev/null | /usr/bin/tr '[:upper:]' '[:lower:]')" || \
  fail "notarization log does not contain the upload digest"
[[ "$log_submission_id" == "$submission_id" ]] || fail "notarization log refers to a different submission"
[[ "$log_status_text" == Accepted ]] || fail "notarization log status is '$log_status_text'"
[[ "$log_upload_digest" == "$upload_digest" ]] || fail "notarization log digest does not match the submitted ZIP"

issues_type="$(/usr/bin/plutil -type issues "$NOTARIZATION_LOG" 2>/dev/null)" || \
  fail "notarization log does not contain an issues field"
case "$issues_type" in
  '(any)')
    ;;
  array)
    issues_count="$(/usr/bin/plutil -extract issues raw -o - "$NOTARIZATION_LOG")"
    [[ "$issues_count" == 0 ]] || fail "notarization log contains $issues_count issue(s)"
    ;;
  *)
    fail "notarization log issues field has unexpected type '$issues_type'"
    ;;
esac

"$xcrun_command" stapler staple -v "$APP_BUNDLE"
"$xcrun_command" stapler validate -v "$APP_BUNDLE"

log_digest="$(/usr/bin/shasum -a 256 "$NOTARIZATION_LOG" | /usr/bin/awk '{ print tolower($1) }')"
/usr/bin/plutil -create xml1 "$NOTARIZATION_METADATA"
/usr/bin/plutil -insert schemaVersion -integer 1 "$NOTARIZATION_METADATA"
/usr/bin/plutil -insert teamIdentifier -string "$DEVELOPER_ID_TEAM_ID" "$NOTARIZATION_METADATA"
/usr/bin/plutil -insert submissionId -string "$submission_id" "$NOTARIZATION_METADATA"
/usr/bin/plutil -insert status -string Accepted "$NOTARIZATION_METADATA"
/usr/bin/plutil -insert uploadSHA256 -string "$upload_digest" "$NOTARIZATION_METADATA"
/usr/bin/plutil -insert logSHA256 -string "$log_digest" "$NOTARIZATION_METADATA"
/usr/bin/plutil -insert ticketStapled -bool true "$NOTARIZATION_METADATA"
/usr/bin/plutil -insert appBundle -string "${APP_BUNDLE:t}" "$NOTARIZATION_METADATA"
/usr/bin/plutil -insert bundleIdentifier -string "$app_bundle_identifier" "$NOTARIZATION_METADATA"
/usr/bin/plutil -insert codeDirectoryHash -string "$app_code_directory_hash" "$NOTARIZATION_METADATA"
/usr/bin/plutil -convert json -r "$NOTARIZATION_METADATA"
/bin/rm -f -- "$NOTARIZATION_UPLOAD_ARCHIVE"

print "Developer ID notarization accepted and stapled: $submission_id"
print "Evidence: $NOTARIZATION_METADATA"
