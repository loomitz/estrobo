#!/bin/zsh

set -euo pipefail

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
  NOTARY_API_KEY_PATH \
  NOTARY_API_KEY_ID \
  NOTARY_API_ISSUER_ID \
  NOTARIZATION_UPLOAD_ARCHIVE \
  NOTARIZATION_SUBMIT_RESULT \
  NOTARIZATION_WAIT_RESULT \
  NOTARIZATION_LOG \
  NOTARIZATION_METADATA; do
  require_value "$required_name"
done

notary_timeout="${NOTARY_TIMEOUT:-30m}"
resume_submission_id_raw="${NOTARY_SUBMISSION_ID:-}"
xcrun_command="${XCRUN_COMMAND:-/usr/bin/xcrun}"
ditto_command="${DITTO_COMMAND:-/usr/bin/ditto}"

[[ -d "$APP_BUNDLE" ]] || fail "app bundle not found: $APP_BUNDLE"
[[ -r "$NOTARY_API_KEY_PATH" ]] || fail "notary API private key not found: $NOTARY_API_KEY_PATH"
[[ "$DEVELOPER_ID_TEAM_ID" =~ '^[A-Z0-9]{10}$' ]] || \
  fail "DEVELOPER_ID_TEAM_ID must contain exactly 10 uppercase letters or digits"
[[ "$NOTARY_API_KEY_ID" =~ '^[A-Za-z0-9]{10,}$' ]] || \
  fail "NOTARY_API_KEY_ID must contain at least 10 letters or digits"
[[ "$NOTARY_API_ISSUER_ID" =~ '^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$' ]] || \
  fail "NOTARY_API_ISSUER_ID must use UUID format"
[[ "$notary_timeout" =~ '^[1-9][0-9]*([smh])?$' ]] || \
  fail "NOTARY_TIMEOUT must be a positive duration such as 30m"
if [[ -n "$resume_submission_id_raw" ]]; then
  [[ "$resume_submission_id_raw" =~ '^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$' ]] || \
    fail "NOTARY_SUBMISSION_ID must use UUID format"
fi
[[ -x "$xcrun_command" ]] || fail "xcrun command is not executable: $xcrun_command"
[[ -x "$ditto_command" ]] || fail "ditto command is not executable: $ditto_command"
[[ "${NOTARIZATION_UPLOAD_ARCHIVE:h}" == "${NOTARIZATION_METADATA:h}" ]] || \
  fail "the notarization upload archive and metadata must share one evidence directory"

for output_path in \
  "$NOTARIZATION_WAIT_RESULT" \
  "$NOTARIZATION_LOG" \
  "$NOTARIZATION_METADATA"; do
  /bin/mkdir -p "${output_path:h}"
  /bin/rm -f -- "$output_path"
done

auth_args=(
  --key "$NOTARY_API_KEY_PATH"
  --key-id "$NOTARY_API_KEY_ID"
  --issuer "$NOTARY_API_ISSUER_ID"
)

if [[ -n "$resume_submission_id_raw" ]]; then
  [[ -r "$NOTARIZATION_UPLOAD_ARCHIVE" ]] || \
    fail "cannot resume without the exact notarization upload archive"
  [[ -r "$NOTARIZATION_SUBMIT_RESULT" ]] || \
    fail "cannot resume without the original submit result"
  submission_id_raw="$(/usr/bin/plutil -extract id raw -o - "$NOTARIZATION_SUBMIT_RESULT" 2>/dev/null)" || \
    fail "the original submit result does not contain a submission ID"
else
  /bin/mkdir -p "${NOTARIZATION_SUBMIT_RESULT:h}" "${NOTARIZATION_UPLOAD_ARCHIVE:h}"
  /bin/rm -f -- "$NOTARIZATION_SUBMIT_RESULT" "$NOTARIZATION_UPLOAD_ARCHIVE"
  "$ditto_command" -c -k --sequesterRsrc --keepParent \
    "$APP_BUNDLE" \
    "$NOTARIZATION_UPLOAD_ARCHIVE"

  submit_status=0
  "$xcrun_command" notarytool submit \
    "$NOTARIZATION_UPLOAD_ARCHIVE" \
    "${auth_args[@]}" \
    --no-wait \
    --output-format json >"$NOTARIZATION_SUBMIT_RESULT" || submit_status=$?
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
fi

upload_digest="$(/usr/bin/shasum -a 256 "$NOTARIZATION_UPLOAD_ARCHIVE" | /usr/bin/awk '{ print tolower($1) }')"
[[ "$upload_digest" =~ '^[0-9a-f]{64}$' ]] || fail "could not calculate the notarization upload digest"
if [[ -n "$resume_submission_id_raw" ]]; then
  print "Resuming Developer ID notarization submission: $submission_id"
else
  print "Developer ID notarization submitted once: $submission_id"
fi

wait_status=0
"$xcrun_command" notarytool wait \
  "$submission_id_raw" \
  "${auth_args[@]}" \
  --timeout "$notary_timeout" \
  --output-format json >"$NOTARIZATION_WAIT_RESULT" || wait_status=$?

log_status=0
"$xcrun_command" notarytool log \
  "$submission_id_raw" \
  "$NOTARIZATION_LOG" \
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
/usr/bin/plutil -convert json -r "$NOTARIZATION_METADATA"
/bin/rm -f -- "$NOTARIZATION_UPLOAD_ARCHIVE"

print "Developer ID notarization accepted and stapled: $submission_id"
print "Evidence: $NOTARIZATION_METADATA"
