#!/bin/zsh

set -euo pipefail

fail() {
  print -u2 "Developer ID candidate packaging failed: $*"
  exit 1
}

require_value() {
  local name="$1"
  [[ -n "${(P)name:-}" ]] || fail "missing environment variable ${name}"
}

for required_name in \
  APP_BUNDLE \
  DIST_DIR \
  VERSION \
  BUILD_NUMBER \
  CANDIDATE_TAG \
  COMMIT \
  MACOSX_DEPLOYMENT_TARGET \
  BUNDLE_IDENTIFIER \
  DEVELOPER_ID_TEAM_ID \
  DEVELOPER_ID_CERTIFICATE \
  DEVELOPER_ID_CERTIFICATE_SHA256 \
  NOTARIZATION_SUBMIT_RESULT \
  NOTARIZATION_WAIT_RESULT \
  NOTARIZATION_LOG \
  NOTARIZATION_METADATA \
  VERIFY_SCRIPT; do
  require_value "$required_name"
done

[[ -d "$APP_BUNDLE" ]] || fail "app bundle not found: $APP_BUNDLE"
[[ -x "$VERIFY_SCRIPT" ]] || fail "Developer ID release verifier is not executable: $VERIFY_SCRIPT"
[[ -r "$DEVELOPER_ID_CERTIFICATE" ]] || fail "Developer ID certificate not found"
[[ -r "$DEVELOPER_ID_CERTIFICATE_SHA256" ]] || fail "Developer ID certificate digest not found"
[[ -r "$NOTARIZATION_SUBMIT_RESULT" ]] || fail "notarization submit result not found: $NOTARIZATION_SUBMIT_RESULT"
[[ -r "$NOTARIZATION_WAIT_RESULT" ]] || fail "notarization wait result not found: $NOTARIZATION_WAIT_RESULT"
[[ -r "$NOTARIZATION_LOG" ]] || fail "notarization log not found: $NOTARIZATION_LOG"
[[ -r "$NOTARIZATION_METADATA" ]] || fail "notarization metadata not found: $NOTARIZATION_METADATA"
[[ "$CANDIDATE_TAG" =~ '^v[0-9]+\.[0-9]+\.[0-9]+-beta\.[0-9]+$' ]] || \
  fail "invalid candidate tag: $CANDIDATE_TAG"
expected_candidate_tag="v${VERSION}-beta.${BUILD_NUMBER}"
[[ "$CANDIDATE_TAG" == "$expected_candidate_tag" ]] || \
  fail "candidate tag '$CANDIDATE_TAG' does not match version/build '$expected_candidate_tag'"
[[ "$COMMIT" =~ '^[0-9a-f]{40}$' ]] || fail "COMMIT must be a full lowercase Git commit SHA"
[[ "$DEVELOPER_ID_TEAM_ID" =~ '^[A-Z0-9]{10}$' ]] || fail "invalid Developer ID Team ID"

metadata_schema="$(/usr/bin/plutil -extract schemaVersion raw -o - "$NOTARIZATION_METADATA" 2>/dev/null)" || \
  fail "notarization metadata is missing schemaVersion"
metadata_app_bundle="$(/usr/bin/plutil -extract appBundle raw -o - "$NOTARIZATION_METADATA" 2>/dev/null)" || \
  fail "notarization metadata is missing appBundle"
metadata_team_id="$(/usr/bin/plutil -extract teamIdentifier raw -o - "$NOTARIZATION_METADATA" 2>/dev/null)" || \
  fail "notarization metadata is missing teamIdentifier"
metadata_submission_id_raw="$(/usr/bin/plutil -extract submissionId raw -o - "$NOTARIZATION_METADATA" 2>/dev/null)" || \
  fail "notarization metadata is missing submissionId"
metadata_status="$(/usr/bin/plutil -extract status raw -o - "$NOTARIZATION_METADATA" 2>/dev/null)" || \
  fail "notarization metadata is missing status"
metadata_upload_digest="$(/usr/bin/plutil -extract uploadSHA256 raw -o - "$NOTARIZATION_METADATA" 2>/dev/null)" || \
  fail "notarization metadata is missing uploadSHA256"
metadata_log_digest="$(/usr/bin/plutil -extract logSHA256 raw -o - "$NOTARIZATION_METADATA" 2>/dev/null)" || \
  fail "notarization metadata is missing logSHA256"
metadata_ticket_stapled="$(/usr/bin/plutil -extract ticketStapled raw -o - "$NOTARIZATION_METADATA" 2>/dev/null)" || \
  fail "notarization metadata is missing ticketStapled"

[[ "$metadata_schema" == 1 ]] || fail "unsupported notarization metadata schema: $metadata_schema"
[[ "$metadata_app_bundle" == "${APP_BUNDLE:t}" ]] || fail "notarization metadata names a different app bundle"
[[ "$metadata_team_id" == "$DEVELOPER_ID_TEAM_ID" ]] || fail "notarization Team ID mismatch"
[[ "$metadata_submission_id_raw" =~ '^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$' ]] || \
  fail "invalid notarization submission ID"
metadata_submission_id="$(print -r -- "$metadata_submission_id_raw" | /usr/bin/tr '[:upper:]' '[:lower:]')"
[[ "$metadata_status" == Accepted ]] || fail "notarization metadata status is '$metadata_status'"
[[ "$metadata_upload_digest" =~ '^[0-9a-f]{64}$' ]] || fail "invalid notarization upload digest"
[[ "$metadata_log_digest" =~ '^[0-9a-f]{64}$' ]] || fail "invalid notarization log digest"
[[ "$metadata_ticket_stapled" == true ]] || fail "notarization metadata does not confirm stapling"

submit_submission_id_raw="$(/usr/bin/plutil -extract id raw -o - "$NOTARIZATION_SUBMIT_RESULT" 2>/dev/null)" || \
  fail "notarization submit result is missing id"
wait_submission_id_raw="$(/usr/bin/plutil -extract id raw -o - "$NOTARIZATION_WAIT_RESULT" 2>/dev/null)" || \
  fail "notarization wait result is missing id"
wait_status="$(/usr/bin/plutil -extract status raw -o - "$NOTARIZATION_WAIT_RESULT" 2>/dev/null)" || \
  fail "notarization wait result is missing status"
[[ "$submit_submission_id_raw" =~ '^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$' ]] || \
  fail "invalid notarization submit ID"
[[ "$wait_submission_id_raw" =~ '^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$' ]] || \
  fail "invalid notarization wait ID"
submit_submission_id="$(print -r -- "$submit_submission_id_raw" | /usr/bin/tr '[:upper:]' '[:lower:]')"
wait_submission_id="$(print -r -- "$wait_submission_id_raw" | /usr/bin/tr '[:upper:]' '[:lower:]')"
[[ "$submit_submission_id" == "$metadata_submission_id" ]] || fail "notarization submit ID mismatch"
[[ "$wait_submission_id" == "$metadata_submission_id" ]] || fail "notarization wait ID mismatch"
[[ "$wait_status" == Accepted ]] || fail "notarization wait status is '$wait_status'"

actual_log_digest="$(/usr/bin/shasum -a 256 "$NOTARIZATION_LOG" | /usr/bin/awk '{ print tolower($1) }')"
[[ "$actual_log_digest" == "$metadata_log_digest" ]] || fail "notarization log digest does not match its metadata"
log_submission_id_raw="$(/usr/bin/plutil -extract jobId raw -o - "$NOTARIZATION_LOG" 2>/dev/null)" || \
  fail "notarization log is missing jobId"
log_submission_id="$(print -r -- "$log_submission_id_raw" | /usr/bin/tr '[:upper:]' '[:lower:]')"
log_status="$(/usr/bin/plutil -extract status raw -o - "$NOTARIZATION_LOG" 2>/dev/null)" || \
  fail "notarization log is missing status"
log_upload_digest="$(/usr/bin/plutil -extract sha256 raw -o - "$NOTARIZATION_LOG" 2>/dev/null | /usr/bin/tr '[:upper:]' '[:lower:]')" || \
  fail "notarization log is missing sha256"
[[ "$log_submission_id" == "$metadata_submission_id" ]] || fail "notarization log submission ID mismatch"
[[ "$log_status" == Accepted ]] || fail "notarization log status is '$log_status'"
[[ "$log_upload_digest" == "$metadata_upload_digest" ]] || fail "notarization log upload digest mismatch"
issues_type="$(/usr/bin/plutil -type issues "$NOTARIZATION_LOG" 2>/dev/null)" || \
  fail "notarization log is missing issues"
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

APP_BUNDLE="$APP_BUNDLE" \
VERSION="$VERSION" \
BUILD_NUMBER="$BUILD_NUMBER" \
BUNDLE_IDENTIFIER="$BUNDLE_IDENTIFIER" \
MACOSX_DEPLOYMENT_TARGET="$MACOSX_DEPLOYMENT_TARGET" \
DEVELOPER_ID_TEAM_ID="$DEVELOPER_ID_TEAM_ID" \
DEVELOPER_ID_CERTIFICATE="$DEVELOPER_ID_CERTIFICATE" \
DEVELOPER_ID_CERTIFICATE_SHA256="$DEVELOPER_ID_CERTIFICATE_SHA256" \
  "$VERIFY_SCRIPT"

/bin/mkdir -p "$DIST_DIR"
short_commit="${COMMIT[1,12]}"
artifact_prefix="estrobo-${CANDIDATE_TAG}-developer-id-candidate-${short_commit}"
archive_name="${artifact_prefix}-macos-universal.zip"
manifest_name="${artifact_prefix}-manifest.json"
checksums_name="${artifact_prefix}-SHA256SUMS"
archive="$DIST_DIR/$archive_name"
manifest="$DIST_DIR/$manifest_name"
checksums="$DIST_DIR/$checksums_name"
evidence_dir="$DIST_DIR/notarization-evidence"

staging_dir="$(/usr/bin/mktemp -d "$DIST_DIR/.developer-id-candidate.XXXXXX")"
verification_dir="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/estrobo-developer-id-package.XXXXXX")"
publishing_started=false
package_complete=false
cleanup() {
  /bin/rm -rf -- "$staging_dir" "$verification_dir"
  if [[ "$publishing_started" == true && "$package_complete" != true ]]; then
    /bin/rm -f -- "$archive" "$manifest" "$checksums"
    /bin/rm -rf -- "$evidence_dir"
  fi
}
trap cleanup EXIT
staged_archive="$staging_dir/$archive_name"
staged_manifest="$staging_dir/$manifest_name"
staged_checksums="$staging_dir/$checksums_name"
staged_evidence_dir="$staging_dir/notarization-evidence"
/bin/mkdir -p "$staged_evidence_dir"
/bin/cp "$NOTARIZATION_SUBMIT_RESULT" "$staged_evidence_dir/notary-submit.json"
/bin/cp "$NOTARIZATION_WAIT_RESULT" "$staged_evidence_dir/notary-wait.json"
/bin/cp "$NOTARIZATION_LOG" "$staged_evidence_dir/notary-log.json"
/bin/cp "$NOTARIZATION_METADATA" "$staged_evidence_dir/notarization-metadata.json"

/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$staged_archive"
archive_digest="$(/usr/bin/shasum -a 256 "$staged_archive" | /usr/bin/awk '{ print tolower($1) }')"
certificate_digest="$(/usr/bin/awk 'NF { print tolower($1); exit }' "$DEVELOPER_ID_CERTIFICATE_SHA256")"

/usr/bin/plutil -create xml1 "$staged_manifest"
/usr/bin/plutil -insert schemaVersion -integer 2 "$staged_manifest"
/usr/bin/plutil -insert releaseKind -string developer-id-candidate "$staged_manifest"
/usr/bin/plutil -insert application -string estrobo "$staged_manifest"
/usr/bin/plutil -insert bundleIdentifier -string "$BUNDLE_IDENTIFIER" "$staged_manifest"
/usr/bin/plutil -insert version -string "$VERSION" "$staged_manifest"
/usr/bin/plutil -insert build -string "$BUILD_NUMBER" "$staged_manifest"
/usr/bin/plutil -insert candidateTag -string "$CANDIDATE_TAG" "$staged_manifest"
/usr/bin/plutil -insert commit -string "$COMMIT" "$staged_manifest"
/usr/bin/plutil -insert architectures -json '["arm64","x86_64"]' "$staged_manifest"
/usr/bin/plutil -insert minimumMacOSVersion -string "$MACOSX_DEPLOYMENT_TARGET" "$staged_manifest"
/usr/bin/plutil -insert signing -dictionary "$staged_manifest"
/usr/bin/plutil -insert signing.type -string developer-id "$staged_manifest"
/usr/bin/plutil -insert signing.teamIdentifier -string "$DEVELOPER_ID_TEAM_ID" "$staged_manifest"
/usr/bin/plutil -insert signing.certificateSHA256 -string "$certificate_digest" "$staged_manifest"
/usr/bin/plutil -insert notarization -dictionary "$staged_manifest"
/usr/bin/plutil -insert notarization.status -string Accepted "$staged_manifest"
/usr/bin/plutil -insert notarization.submissionId -string "$metadata_submission_id" "$staged_manifest"
/usr/bin/plutil -insert notarization.uploadSHA256 -string "$metadata_upload_digest" "$staged_manifest"
/usr/bin/plutil -insert notarization.logSHA256 -string "$metadata_log_digest" "$staged_manifest"
/usr/bin/plutil -insert notarization.ticketStapled -bool true "$staged_manifest"
/usr/bin/plutil -insert notarization.evidenceDirectory -string notarization-evidence "$staged_manifest"
/usr/bin/plutil -insert artifact -string "$archive_name" "$staged_manifest"
/usr/bin/plutil -insert sha256 -string "$archive_digest" "$staged_manifest"
/usr/bin/plutil -convert json -r "$staged_manifest"

(
  cd "$staging_dir"
  /usr/bin/shasum -a 256 \
    "$archive_name" \
    "$manifest_name" \
    notarization-evidence/notary-submit.json \
    notarization-evidence/notary-wait.json \
    notarization-evidence/notary-log.json \
    notarization-evidence/notarization-metadata.json \
    >"$checksums_name"
  /usr/bin/shasum -a 256 -c "$checksums_name"
)

/usr/bin/ditto -x -k "$staged_archive" "$verification_dir"
extracted_app="$verification_dir/${APP_BUNDLE:t}"
[[ -d "$extracted_app" ]] || fail "the archive does not contain ${APP_BUNDLE:t} at its root"

APP_BUNDLE="$extracted_app" \
VERSION="$VERSION" \
BUILD_NUMBER="$BUILD_NUMBER" \
BUNDLE_IDENTIFIER="$BUNDLE_IDENTIFIER" \
MACOSX_DEPLOYMENT_TARGET="$MACOSX_DEPLOYMENT_TARGET" \
DEVELOPER_ID_TEAM_ID="$DEVELOPER_ID_TEAM_ID" \
DEVELOPER_ID_CERTIFICATE="$DEVELOPER_ID_CERTIFICATE" \
DEVELOPER_ID_CERTIFICATE_SHA256="$DEVELOPER_ID_CERTIFICATE_SHA256" \
  "$VERIFY_SCRIPT"

publishing_started=true
/bin/rm -f -- "$archive" "$manifest" "$checksums"
/bin/rm -rf -- "$evidence_dir"
/bin/mv "$staged_archive" "$archive"
/bin/mv "$staged_manifest" "$manifest"
/bin/mv "$staged_checksums" "$checksums"
/bin/mv "$staged_evidence_dir" "$evidence_dir"
package_complete=true

print "Developer ID candidate packaged: $archive"
print "SHA-256: $archive_digest"
print "Manifest: $manifest"
print "Checksums: $checksums"
print "Notarization evidence: $evidence_dir"
