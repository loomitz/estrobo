#!/bin/zsh

set -euo pipefail
umask 077

fail() {
  print -u2 "Developer ID DMG tooling test failed: $*"
  exit 1
}

script_dir="${0:A:h}"
package_script="$script_dir/package-macos-developer-id-dmg.sh"
verify_script="$script_dir/verify-macos-developer-id-dmg.sh"

for required_script in "$package_script" "$verify_script"; do
  [[ -x "$required_script" ]] || fail "required script is not executable: $required_script"
  /bin/zsh -n "$required_script"
done

unset \
  NOTARY_KEYCHAIN_PROFILE \
  NOTARY_API_KEY_PATH \
  NOTARY_API_KEY_ID \
  NOTARY_API_ISSUER_ID \
  DMG_NOTARY_SUBMISSION_ID \
  FAKE_SUBMIT_EXIT_CODE \
  FAKE_WAIT_EXIT_CODE \
  FAKE_LOG_EXIT_CODE \
  FAKE_NOTARY_STATUS \
  FAKE_SUBMIT_ID_OVERRIDE \
  FAKE_WAIT_ID_OVERRIDE \
  FAKE_LOG_ID_OVERRIDE \
  FAKE_LOG_DIGEST_OVERRIDE \
  FAKE_NOTARY_ISSUES_JSON \
  FAKE_DMG_VERIFY_EXIT_CODE \
  FAKE_CONCURRENT_DMG_CONTENT \
  FAKE_LEAK_VALUE 2>/dev/null || true

temporary_dir="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/estrobo-dmg-tools-test.XXXXXX")"
trap '/bin/rm -rf -- "$temporary_dir"' EXIT

fake_dir="$temporary_dir/fakes"
/bin/mkdir -p "$fake_dir"

fake_hdiutil="$fake_dir/hdiutil"
cat >"$fake_hdiutil" <<'FAKE_HDIUTIL'
#!/bin/zsh
set -euo pipefail

state_dir="${FAKE_STATE_DIR:?}"

increment() {
  local name="$1"
  local counter="$state_dir/${name}.count"
  local value=0
  [[ -r "$counter" ]] && value="$(<"$counter")"
  print -r -- "$((value + 1))" >"$counter"
}

subcommand="${1:-}"
[[ -n "$subcommand" ]] || exit 64
increment "hdiutil.${subcommand}"
print -rl -- "$@" >"$state_dir/hdiutil.${subcommand}.args"

case "$subcommand" in
  create)
    output_path="${argv[-1]}"
    print -r -- 'synthetic UDZO HFS+ disk image' >"$output_path"
    ;;
  verify)
    [[ -f "${argv[-1]}" ]]
    ;;
  imageinfo)
    cat <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Format</key>
  <string>UDZO</string>
  <key>Properties</key>
  <dict>
    <key>Compressed</key>
    <true/>
    <key>Encrypted</key>
    <false/>
  </dict>
</dict>
</plist>
PLIST
    ;;
  attach)
    mount_point=''
    index=1
    while (( index <= $# )); do
      if [[ "${argv[index]}" == -mountpoint ]]; then
        (( index += 1 ))
        mount_point="${argv[index]}"
        break
      fi
      (( index += 1 ))
    done
    [[ -n "$mount_point" && -d "$mount_point" ]]
    /usr/bin/ditto "$FAKE_MOUNT_APP" "$mount_point/estrobo.app"
    /bin/ln -s /Applications "$mount_point/Applications"
    ;;
  detach)
    [[ -d "${argv[-1]}" ]]
    ;;
  *)
    exit 64
    ;;
esac
FAKE_HDIUTIL

fake_codesign="$fake_dir/codesign"
cat >"$fake_codesign" <<'FAKE_CODESIGN'
#!/bin/zsh
set -euo pipefail

state_dir="${FAKE_STATE_DIR:?}"

increment() {
  local name="$1"
  local counter="$state_dir/${name}.count"
  local value=0
  [[ -r "$counter" ]] && value="$(<"$counter")"
  print -r -- "$((value + 1))" >"$counter"
}

is_sign=false
extract_prefix=''
for argument in "$@"; do
  [[ "$argument" == --force ]] && is_sign=true
  [[ "$argument" == --extract-certificates=* ]] && extract_prefix="${argument#*=}"
done

if [[ "$is_sign" == true ]]; then
  increment codesign.sign
  print -rl -- "$@" >"$state_dir/codesign.sign.args"
  print -r -- 'synthetic Developer ID disk-image signature' >>"${argv[-1]}"
  exit 0
fi

if [[ "${1:-}" == --verify ]]; then
  increment codesign.verify
  print -rl -- "$@" >"$state_dir/codesign.verify.args"
  [[ -f "${argv[-1]}" ]]
  exit 0
fi

if [[ "${1:-}" == -dvvv ]]; then
  increment codesign.details
  print -rl -- "$@" >"$state_dir/codesign.details.args"
  target="${argv[-1]}"
  if [[ -d "$target" ]]; then
    app_cdhash="${FAKE_APP_CDHASH_OVERRIDE:-0123456789abcdef0123456789abcdef01234567}"
    cat <<DETAILS
Identifier=mx.loo.estrobo
Format=app bundle with Mach-O universal (arm64 x86_64)
CDHash=$app_cdhash
Authority=Developer ID Application: Synthetic Developer (ABCDE12345)
Authority=Developer ID Certification Authority
Authority=Apple Root CA
Timestamp=Aug 28, 2026 at 12:00:00 PM
TeamIdentifier=ABCDE12345
DETAILS
    exit 0
  fi
  cat <<'DETAILS'
Identifier=mx.loo.estrobo.dmg
Format=disk image
Authority=Developer ID Application: Synthetic Developer (ABCDE12345)
Authority=Developer ID Certification Authority
Authority=Apple Root CA
Timestamp=Aug 28, 2026 at 12:00:00 PM
TeamIdentifier=ABCDE12345
DETAILS
  exit 0
fi

if [[ -n "$extract_prefix" ]]; then
  increment codesign.extract
  print -rl -- "$@" >"$state_dir/codesign.extract.args"
  /bin/cp "$FAKE_CERTIFICATE" "${extract_prefix}0"
  exit 0
fi

exit 64
FAKE_CODESIGN

fake_xcrun="$fake_dir/xcrun"
cat >"$fake_xcrun" <<'FAKE_XCRUN'
#!/bin/zsh
set -euo pipefail

state_dir="${FAKE_STATE_DIR:?}"
default_submission_id='aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'

increment() {
  local name="$1"
  local counter="$state_dir/${name}.count"
  local value=0
  [[ -r "$counter" ]] && value="$(<"$counter")"
  print -r -- "$((value + 1))" >"$counter"
}

[[ "${1:-}" == notarytool || "${1:-}" == stapler ]] || exit 64

if [[ "$1" == notarytool && "${2:-}" == submit ]]; then
  increment notary.submit
  print -rl -- "$@" >"$state_dir/notary.submit.args"
  submit_exit_code="${FAKE_SUBMIT_EXIT_CODE:-0}"
  if [[ "$submit_exit_code" -ne 0 ]]; then
    print -u2 'Synthetic submit failure'
    exit "$submit_exit_code"
  fi
  /usr/bin/shasum -a 256 "$3" | /usr/bin/awk '{ print tolower($1) }' >"$state_dir/upload.sha256"
  submit_id="${FAKE_SUBMIT_ID_OVERRIDE:-$default_submission_id}"
  [[ -z "${FAKE_LEAK_VALUE:-}" ]] || print -u2 -- "profile=${FAKE_LEAK_VALUE}"
  print -r -- "{\"id\":\"$submit_id\",\"message\":\"Successfully uploaded file ${FAKE_LEAK_VALUE:-}\",\"status\":\"In Progress\"}"
  exit 0
fi

if [[ "$1" == notarytool && "${2:-}" == wait ]]; then
  increment notary.wait
  print -rl -- "$@" >"$state_dir/notary.wait.args"
  if [[ -n "${FAKE_WAIT_BLOCK_MARKER:-}" ]]; then
    /usr/bin/touch "$FAKE_WAIT_BLOCK_MARKER"
    while [[ ! -e "${FAKE_WAIT_BLOCK_RELEASE:?}" ]]; do
      /bin/sleep 0.02
    done
  fi
  wait_exit_code="${FAKE_WAIT_EXIT_CODE:-0}"
  if [[ "$wait_exit_code" -ne 0 ]]; then
    print -u2 'Synthetic wait timeout'
    exit "$wait_exit_code"
  fi
  wait_id="${FAKE_WAIT_ID_OVERRIDE:-$3}"
  [[ -z "${FAKE_LEAK_VALUE:-}" ]] || print -u2 -- "profile=${FAKE_LEAK_VALUE}"
  print -r -- "{\"id\":\"$wait_id\",\"message\":\"Processing complete ${FAKE_LEAK_VALUE:-}\",\"status\":\"${FAKE_NOTARY_STATUS:-Accepted}\"}"
  exit 0
fi

if [[ "$1" == notarytool && "${2:-}" == log ]]; then
  increment notary.log
  print -rl -- "$@" >"$state_dir/notary.log.args"
  log_exit_code="${FAKE_LOG_EXIT_CODE:-0}"
  if [[ "$log_exit_code" -ne 0 ]]; then
    print -u2 'Synthetic log failure'
    exit "$log_exit_code"
  fi
  submission_id="$3"
  output_path="$4"
  log_id="${FAKE_LOG_ID_OVERRIDE:-$submission_id}"
  upload_digest="$(<"$state_dir/upload.sha256")"
  log_digest="${FAKE_LOG_DIGEST_OVERRIDE:-$upload_digest}"
  issues_json="${FAKE_NOTARY_ISSUES_JSON:-null}"
  [[ -z "${FAKE_LEAK_VALUE:-}" ]] || print -u2 -- "profile=${FAKE_LEAK_VALUE}"
  print -r -- "{\"jobId\":\"$log_id\",\"status\":\"${FAKE_NOTARY_STATUS:-Accepted}\",\"statusSummary\":\"Synthetic test ${FAKE_LEAK_VALUE:-}\",\"statusCode\":0,\"sha256\":\"$log_digest\",\"issues\":$issues_json}" >"$output_path"
  exit 0
fi

if [[ "$1" == stapler && "${2:-}" == staple ]]; then
  increment stapler.staple
  print -rl -- "$@" >"$state_dir/stapler.staple.args"
  target="${argv[-1]}"
  print -r -- 'synthetic stapled ticket' >>"$target"
  print 'Synthetic staple succeeded'
  exit 0
fi

if [[ "$1" == stapler && "${2:-}" == validate ]]; then
  increment stapler.validate
  print -rl -- "$@" >"$state_dir/stapler.validate.args"
  target="${argv[-1]}"
  /usr/bin/grep -Fq 'synthetic stapled ticket' "$target"
  print 'Synthetic staple validation succeeded'
  exit 0
fi

exit 64
FAKE_XCRUN

fake_spctl="$fake_dir/spctl"
cat >"$fake_spctl" <<'FAKE_SPCTL'
#!/bin/zsh
set -euo pipefail

counter="$FAKE_STATE_DIR/spctl.assess.count"
value=0
[[ -r "$counter" ]] && value="$(<"$counter")"
print -r -- "$((value + 1))" >"$counter"
print -rl -- "$@" >"$FAKE_STATE_DIR/spctl.assess.args"
print -r -- "${argv[-1]}: accepted"
print -r -- 'source=Notarized Developer ID'
FAKE_SPCTL

fake_diskutil="$fake_dir/diskutil"
cat >"$fake_diskutil" <<'FAKE_DISKUTIL'
#!/bin/zsh
set -euo pipefail

counter="$FAKE_STATE_DIR/diskutil.info.count"
value=0
[[ -r "$counter" ]] && value="$(<"$counter")"
print -r -- "$((value + 1))" >"$counter"
print -rl -- "$@" >"$FAKE_STATE_DIR/diskutil.info.args"
cat <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>FilesystemName</key>
  <string>HFS+</string>
  <key>VolumeName</key>
  <string>Estrobo</string>
  <key>Writable</key>
  <false/>
</dict>
</plist>
PLIST
FAKE_DISKUTIL

fake_ditto="$fake_dir/ditto"
cat >"$fake_ditto" <<'FAKE_DITTO'
#!/bin/zsh
set -euo pipefail

counter="$FAKE_STATE_DIR/ditto.count"
value=0
[[ -r "$counter" ]] && value="$(<"$counter")"
print -r -- "$((value + 1))" >"$counter"
print -rl -- "$@" >"$FAKE_STATE_DIR/ditto.args"
/usr/bin/ditto "$@"
FAKE_DITTO

fake_app_verifier="$fake_dir/verify-app"
cat >"$fake_app_verifier" <<'FAKE_APP_VERIFIER'
#!/bin/zsh
set -euo pipefail

counter="$FAKE_STATE_DIR/app.verify.count"
value=0
[[ -r "$counter" ]] && value="$(<"$counter")"
print -r -- "$((value + 1))" >"$counter"
print -r -- "$APP_BUNDLE" >"$FAKE_STATE_DIR/app.verify.last-bundle"
[[ -d "$APP_BUNDLE" && "${APP_BUNDLE:t}" == estrobo.app ]]
[[ "$VERSION" == 0.1.0 && "$BUILD_NUMBER" == 4 ]]
[[ "$SOURCE_COMMIT" == "$COMMIT" ]]
[[ "$BUNDLE_IDENTIFIER" == mx.loo.estrobo ]]
[[ "$MACOSX_DEPLOYMENT_TARGET" == 13.0 ]]
[[ "$DEVELOPER_ID_TEAM_ID" == ABCDE12345 ]]
FAKE_APP_VERIFIER

fake_dmg_verifier="$fake_dir/verify-dmg"
cat >"$fake_dmg_verifier" <<'FAKE_DMG_VERIFIER'
#!/bin/zsh
set -euo pipefail

counter="$FAKE_STATE_DIR/dmg.verify.count"
value=0
[[ -r "$counter" ]] && value="$(<"$counter")"
print -r -- "$((value + 1))" >"$counter"
print -rl -- "$DMG" "$MANIFEST" "$CHECKSUMS" >"$FAKE_STATE_DIR/dmg.verify.paths"
[[ -f "$DMG" && -f "$MANIFEST" && -f "$CHECKSUMS" ]]
[[ "$(/usr/bin/plutil -extract schemaVersion raw -o - "$MANIFEST")" == 3 ]]
(
  cd "${DMG:h}"
  /usr/bin/shasum -a 256 -c "${CHECKSUMS:t}" >/dev/null
)

verify_exit_code="${FAKE_DMG_VERIFY_EXIT_CODE:-0}"
[[ "$verify_exit_code" -eq 0 ]] || exit "$verify_exit_code"

if [[ -n "${FAKE_CONCURRENT_DMG_CONTENT:-}" ]]; then
  public_dmg="${DMG:h:h}/${DMG:t}"
  [[ ! -e "$public_dmg" && ! -L "$public_dmg" ]]
  print -n -r -- "$FAKE_CONCURRENT_DMG_CONTENT" >"$public_dmg"
  /bin/chmod 644 "$public_dmg"
fi
FAKE_DMG_VERIFIER

/bin/chmod 755 \
  "$fake_hdiutil" \
  "$fake_codesign" \
  "$fake_xcrun" \
  "$fake_spctl" \
  "$fake_diskutil" \
  "$fake_ditto" \
  "$fake_app_verifier" \
  "$fake_dmg_verifier"

fixture_dir="$temporary_dir/fixture"
app_bundle="$fixture_dir/estrobo.app"
/bin/mkdir -p "$app_bundle/Contents/MacOS"
print -r -- 'synthetic universal executable' >"$app_bundle/Contents/MacOS/estrobo"
/bin/chmod 755 "$app_bundle/Contents/MacOS/estrobo"

certificate="$fixture_dir/DeveloperIDApplication.cer"
print -r -- 'synthetic Developer ID leaf certificate bytes' >"$certificate"
certificate_digest="$(/usr/bin/shasum -a 256 "$certificate" | /usr/bin/awk '{ print tolower($1) }')"
certificate_digest_file="$fixture_dir/DeveloperIDApplication.cer.sha256"
print -r -- "$certificate_digest  ${certificate:t}" >"$certificate_digest_file"

app_submission_id='11111111-2222-3333-4444-555555555555'
default_dmg_submission_id='aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'
other_submission_id='99999999-8888-7777-6666-555555555555'
app_upload_digest='aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
app_code_directory_hash='0123456789abcdef0123456789abcdef01234567'
app_metadata="$fixture_dir/app-notarization-metadata.json"
/usr/bin/plutil -create xml1 "$app_metadata"
/usr/bin/plutil -insert schemaVersion -integer 1 "$app_metadata"
/usr/bin/plutil -insert appBundle -string estrobo.app "$app_metadata"
/usr/bin/plutil -insert bundleIdentifier -string mx.loo.estrobo "$app_metadata"
/usr/bin/plutil -insert codeDirectoryHash -string "$app_code_directory_hash" "$app_metadata"
/usr/bin/plutil -insert teamIdentifier -string ABCDE12345 "$app_metadata"
/usr/bin/plutil -insert status -string Accepted "$app_metadata"
/usr/bin/plutil -insert ticketStapled -bool true "$app_metadata"
/usr/bin/plutil -insert submissionId -string "$app_submission_id" "$app_metadata"
/usr/bin/plutil -insert uploadSHA256 -string "$app_upload_digest" "$app_metadata"
/usr/bin/plutil -convert json -r "$app_metadata"

api_key="$fixture_dir/AuthKey_TESTKEY1234.p8"
print -r -- 'synthetic API key; never a credential' >"$api_key"
/bin/chmod 600 "$api_key"
api_key="${api_key:A}"
api_key_id='TESTKEY1234'
api_issuer_id='12345678-1234-1234-1234-123456789abc'
profile_name='synthetic-notary-profile'
tag='v0.1.0-beta.4'
commit='0123456789abcdef0123456789abcdef01234567'

count_value() {
  local state_dir="$1"
  local name="$2"
  local counter="$state_dir/${name}.count"
  if [[ -r "$counter" ]]; then
    print -r -- "$(<"$counter")"
  else
    print 0
  fi
}

assert_count() {
  local state_dir="$1"
  local name="$2"
  local expected="$3"
  local actual
  actual="$(count_value "$state_dir" "$name")"
  [[ "$actual" == "$expected" ]] || fail "$name count is $actual, expected $expected"
}

assert_mode() {
  local path="$1"
  local expected="$2"
  local actual
  actual="$(/usr/bin/stat -f '%Lp' "$path")"
  [[ "$actual" == "$expected" ]] || fail "mode for $path is $actual, expected $expected"
}

assert_arg() {
  local args_file="$1"
  local expected="$2"
  /usr/bin/grep -Fxq -- "$expected" "$args_file" || \
    fail "missing argument '$expected' in $args_file"
}

assert_no_arg() {
  local args_file="$1"
  local forbidden="$2"
  if /usr/bin/grep -Fxq -- "$forbidden" "$args_file"; then
    fail "forbidden argument '$forbidden' appears in $args_file"
  fi
}

evidence_fingerprint() {
  local directory="$1"
  (
    cd "$directory"
    /usr/bin/find . -mindepth 1 -print | LC_ALL=C /usr/bin/sort | while IFS= read -r entry; do
      if [[ -L "$entry" ]]; then
        print -r -- "$entry|link|$(/usr/bin/stat -f '%Lp' "$entry")|$(/usr/bin/readlink "$entry")"
      elif [[ -d "$entry" ]]; then
        print -r -- "$entry|directory|$(/usr/bin/stat -f '%Lp' "$entry")"
      elif [[ -f "$entry" ]]; then
        print -r -- "$entry|file|$(/usr/bin/stat -f '%Lp' "$entry")|$(/usr/bin/shasum -a 256 "$entry" | /usr/bin/awk '{ print $1 }')"
      else
        print -r -- "$entry|other|$(/usr/bin/stat -f '%Lp' "$entry")"
      fi
    done
  ) | /usr/bin/shasum -a 256 | /usr/bin/awk '{ print $1 }'
}

assert_evidence_unchanged() {
  local before="$1"
  local directory="$2"
  local label="$3"
  local after
  after="$(evidence_fingerprint "$directory")"
  [[ "$after" == "$before" ]] || fail "$label mutated preserved evidence"
}

typeset -ga common_env
typeset -g case_root case_state case_evidence case_dist case_output
typeset -g public_dmg public_manifest public_checksums
case_count=0

prepare_case() {
  local name="$1"
  (( case_count += 1 ))
  case_root="$temporary_dir/cases/$name"
  case_state="$case_root/state"
  case_evidence="$case_root/evidence"
  case_dist="$case_root/dist"
  case_output="$case_root/output.log"
  /bin/mkdir -p "$case_state"
  public_dmg="$case_dist/estrobo-${tag}-macos-universal.dmg"
  public_manifest="$case_dist/estrobo-${tag}-manifest.json"
  public_checksums="$case_dist/SHA256SUMS"
  common_env=(
    "FAKE_STATE_DIR=$case_state"
    "FAKE_CERTIFICATE=$certificate"
    "FAKE_MOUNT_APP=$app_bundle"
    "APP_BUNDLE=$app_bundle"
    "APP_NOTARIZATION_METADATA=$app_metadata"
    "DIST_DIR=$case_dist"
    "DMG_EVIDENCE_DIR=$case_evidence"
    'VERSION=0.1.0'
    'BUILD_NUMBER=4'
    "TAG=$tag"
    "COMMIT=$commit"
    'MACOSX_DEPLOYMENT_TARGET=13.0'
    'BUNDLE_IDENTIFIER=mx.loo.estrobo'
    'DEVELOPER_ID_TEAM_ID=ABCDE12345'
    'DEVELOPER_ID_SIGNING_IDENTITY=Developer ID Application: Synthetic Developer (ABCDE12345)'
    "DEVELOPER_ID_CERTIFICATE=$certificate"
    "DEVELOPER_ID_CERTIFICATE_SHA256=$certificate_digest_file"
    "APP_VERIFY_SCRIPT=$fake_app_verifier"
    "DMG_VERIFY_SCRIPT=$fake_dmg_verifier"
    "HDIUTIL_COMMAND=$fake_hdiutil"
    "CODESIGN_COMMAND=$fake_codesign"
    "SPCTL_COMMAND=$fake_spctl"
    "DISKUTIL_COMMAND=$fake_diskutil"
    "XCRUN_COMMAND=$fake_xcrun"
    "DITTO_COMMAND=$fake_ditto"
    'NOTARY_TIMEOUT=3s'
    'REPOSITORY_URL=https://github.com/loomitz/estrobo'
  )
}

run_profile() {
  /usr/bin/env \
    "${common_env[@]}" \
    "NOTARY_KEYCHAIN_PROFILE=$profile_name" \
    "$@" \
    "$package_script"
}

run_api() {
  /usr/bin/env \
    "${common_env[@]}" \
    "NOTARY_API_KEY_PATH=$api_key" \
    "NOTARY_API_KEY_ID=$api_key_id" \
    "NOTARY_API_ISSUER_ID=$api_issuer_id" \
    "$@" \
    "$package_script"
}

run_no_auth() {
  /usr/bin/env \
    "${common_env[@]}" \
    "$@" \
    "$package_script"
}

run_real_verifier() {
  /usr/bin/env \
    "FAKE_STATE_DIR=$case_state" \
    "FAKE_CERTIFICATE=$certificate" \
    "FAKE_MOUNT_APP=$app_bundle" \
    "DMG=$public_dmg" \
    "MANIFEST=$public_manifest" \
    "CHECKSUMS=$public_checksums" \
    'VERSION=0.1.0' \
    'BUILD_NUMBER=4' \
    "TAG=$tag" \
    "COMMIT=$commit" \
    'MACOSX_DEPLOYMENT_TARGET=13.0' \
    'BUNDLE_IDENTIFIER=mx.loo.estrobo' \
    'DEVELOPER_ID_TEAM_ID=ABCDE12345' \
    "DEVELOPER_ID_CERTIFICATE=$certificate" \
    "DEVELOPER_ID_CERTIFICATE_SHA256=$certificate_digest_file" \
    "APP_VERIFY_SCRIPT=$fake_app_verifier" \
    "HDIUTIL_COMMAND=$fake_hdiutil" \
    "CODESIGN_COMMAND=$fake_codesign" \
    "SPCTL_COMMAND=$fake_spctl" \
    "DISKUTIL_COMMAND=$fake_diskutil" \
    "XCRUN_COMMAND=$fake_xcrun" \
    'REPOSITORY_URL=https://github.com/loomitz/estrobo' \
    "$verify_script"
}

assert_public_absent() {
  local path
  for path in "$public_dmg" "$public_manifest" "$public_checksums"; do
    [[ ! -e "$path" && ! -L "$path" ]] || fail "unexpected public artifact after failure: $path"
  done
}

assert_exact_upload_retained() {
  local upload="$case_evidence/notary-upload.dmg"
  local checksum="$case_evidence/notary-upload.sha256"
  [[ -f "$upload" && -f "$checksum" ]] || fail "submitted upload evidence was not retained"
  local expected actual
  expected="$(/usr/bin/awk 'NF { print tolower($1); exit }' "$checksum")"
  actual="$(/usr/bin/shasum -a 256 "$upload" | /usr/bin/awk '{ print tolower($1) }')"
  [[ "$actual" == "$expected" ]] || fail "retained upload does not match its preserved checksum"
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

expect_auth_failure() {
  local name="$1"
  local auth_mode="$2"
  shift 2
  prepare_case "$name"
  if [[ "$auth_mode" == profile ]]; then
    if run_profile "$@" >"$case_output" 2>&1; then
      fail "unsafe authentication case '$name' succeeded"
    fi
  else
    if run_no_auth "$@" >"$case_output" 2>&1; then
      fail "unsafe authentication case '$name' succeeded"
    fi
  fi
  assert_count "$case_state" notary.submit 0
  assert_count "$case_state" hdiutil.create 0
  [[ ! -e "$case_evidence" && ! -L "$case_evidence" ]] || \
    fail "unsafe authentication case '$name' claimed an evidence directory"
  assert_public_absent
}

expect_submitted_failure() {
  local name="$1"
  local expected_wait="$2"
  local expected_log="$3"
  shift 3
  prepare_case "$name"
  if run_profile "$@" >"$case_output" 2>&1; then
    fail "failure case '$name' unexpectedly succeeded"
  fi
  assert_count "$case_state" notary.submit 1
  assert_count "$case_state" notary.wait "$expected_wait"
  assert_count "$case_state" notary.log "$expected_log"
  assert_exact_upload_retained
  assert_public_absent
}

clone_timeout_case() {
  local name="$1"
  prepare_case "$name"
  /usr/bin/ditto "$timeout_state" "$case_state"
  /usr/bin/ditto "$timeout_evidence" "$case_evidence"
  assert_mode "$case_evidence" 700
  assert_count "$case_state" notary.submit 1
  assert_count "$case_state" hdiutil.create 1
  assert_count "$case_state" codesign.sign 1
}

# Fresh keychain-profile success, private evidence, schema 3, and the full verifier.
prepare_case profile-success
run_profile "FAKE_LEAK_VALUE=$profile_name" >"$case_output" 2>&1

for public_path in "$public_dmg" "$public_manifest" "$public_checksums"; do
  [[ -f "$public_path" && ! -L "$public_path" ]] || fail "missing public artifact: $public_path"
  assert_mode "$public_path" 644
done
[[ "$(/usr/bin/plutil -extract schemaVersion raw -o - "$public_manifest")" == 3 ]] || \
  fail "public manifest is not schema 3"
[[ "$(/usr/bin/plutil -extract releaseKind raw -o - "$public_manifest")" == developer-id-notarized-dmg ]] || \
  fail "public manifest has the wrong release kind"
[[ "$(/usr/bin/plutil -extract verification.physicalSmoke raw -o - "$public_manifest")" == pending ]] || \
  fail "initial public manifest does not keep physical smoke pending"
[[ "$(/usr/bin/plutil -extract notarization.application.codeDirectoryHash raw -o - "$public_manifest")" == \
  "$app_code_directory_hash" ]] || fail "public manifest omitted the notarized app CodeDirectory hash"
manifest_app_id="$(/usr/bin/plutil -extract notarization.application.submissionId raw -o - "$public_manifest")"
manifest_dmg_id="$(/usr/bin/plutil -extract notarization.diskImage.submissionId raw -o - "$public_manifest")"
[[ "$manifest_app_id" == "$app_submission_id" ]] || fail "manifest lost the app notarization ID"
[[ "$manifest_dmg_id" == "$default_dmg_submission_id" ]] || fail "manifest lost the DMG notarization ID"
[[ "$manifest_app_id" != "$manifest_dmg_id" ]] || fail "app and DMG notarization IDs are not distinct"
(
  cd "$case_dist"
  [[ "$(/usr/bin/awk 'NF { count += 1 } END { print count + 0 }' SHA256SUMS)" == 2 ]]
  /usr/bin/shasum -a 256 -c SHA256SUMS >/dev/null
) || fail "public SHA256SUMS is incomplete or invalid"

assert_mode "$case_evidence" 700
for private_file in \
  "$case_evidence/notary-upload.dmg" \
  "$case_evidence/notary-upload.sha256" \
  "$case_evidence/notary-submit.json" \
  "$case_evidence/notary-wait.json" \
  "$case_evidence/notary-log.json" \
  "$case_evidence/notarization-metadata.json"; do
  [[ -f "$private_file" && ! -L "$private_file" ]] || fail "missing private evidence: $private_file"
  assert_mode "$private_file" 600
done
[[ ! -e "$case_evidence/notarization-metadata.pending.json" ]] || fail "accepted run retained pending metadata"
assert_count "$case_state" hdiutil.create 1
assert_count "$case_state" codesign.sign 1
assert_count "$case_state" notary.submit 1
assert_count "$case_state" dmg.verify 1
for operation in submit wait log; do
  args_file="$case_state/notary.${operation}.args"
  assert_arg "$args_file" --keychain-profile
  assert_arg "$args_file" "$profile_name"
  assert_no_arg "$args_file" --key
  assert_no_arg "$args_file" --key-id
  assert_no_arg "$args_file" --issuer
done
if /usr/bin/grep -RFq -- "$profile_name" "$case_evidence" "$case_output"; then
  fail "keychain profile name leaked into evidence or command output"
fi

run_real_verifier >>"$case_output" 2>&1
assert_count "$case_state" app.verify 2
assert_count "$case_state" spctl.assess 1
assert_count "$case_state" diskutil.info 1
assert_count "$case_state" hdiutil.attach 1
assert_count "$case_state" hdiutil.detach 1
assert_count "$case_state" stapler.validate 2

# API authentication must be forwarded consistently to submit, wait, and log.
prepare_case api-success
run_api >"$case_output" 2>&1
assert_count "$case_state" notary.submit 1
for operation in submit wait log; do
  args_file="$case_state/notary.${operation}.args"
  assert_arg "$args_file" --key
  assert_arg "$args_file" "$api_key"
  assert_arg "$args_file" --key-id
  assert_arg "$args_file" "$api_key_id"
  assert_arg "$args_file" --issuer
  assert_arg "$args_file" "$api_issuer_id"
  assert_no_arg "$args_file" --keychain-profile
done

# Missing, partial, and mixed authentication must fail before any claim or submit.
expect_auth_failure auth-missing none
expect_auth_failure auth-partial-key none \
  "NOTARY_API_KEY_PATH=$api_key"
expect_auth_failure auth-partial-no-issuer none \
  "NOTARY_API_KEY_PATH=$api_key" \
  "NOTARY_API_KEY_ID=$api_key_id"
expect_auth_failure auth-partial-no-key-id none \
  "NOTARY_API_KEY_PATH=$api_key" \
  "NOTARY_API_ISSUER_ID=$api_issuer_id"
expect_auth_failure auth-partial-no-key none \
  "NOTARY_API_KEY_ID=$api_key_id" \
  "NOTARY_API_ISSUER_ID=$api_issuer_id"
expect_auth_failure auth-mixed profile \
  "NOTARY_API_KEY_PATH=$api_key" \
  "NOTARY_API_KEY_ID=$api_key_id" \
  "NOTARY_API_ISSUER_ID=$api_issuer_id"

# App notarization evidence is bound to both bundle identifier and exact CDHash.
prepare_case app-cdhash-mismatch
if run_profile \
  'FAKE_APP_CDHASH_OVERRIDE=ffffffffffffffffffffffffffffffffffffffff' >"$case_output" 2>&1; then
  fail "package accepted app evidence for a different CodeDirectory hash"
fi
assert_count "$case_state" notary.submit 0
assert_count "$case_state" hdiutil.create 0
[[ ! -e "$case_evidence" && ! -L "$case_evidence" ]] || fail "CDHash mismatch claimed evidence"
assert_public_absent

prepare_case app-bundle-id-mismatch
wrong_bundle_metadata="$case_root/wrong-bundle-metadata.json"
/usr/bin/ditto "$app_metadata" "$wrong_bundle_metadata"
/usr/bin/plutil -replace bundleIdentifier -string mx.loo.different "$wrong_bundle_metadata"
if run_profile "APP_NOTARIZATION_METADATA=$wrong_bundle_metadata" >"$case_output" 2>&1; then
  fail "package accepted app evidence for a different bundle identifier"
fi
assert_count "$case_state" notary.submit 0
assert_count "$case_state" hdiutil.create 0
[[ ! -e "$case_evidence" && ! -L "$case_evidence" ]] || fail "bundle-ID mismatch claimed evidence"
assert_public_absent

# Fresh mode atomically claims a brand-new evidence directory.
prepare_case fresh-existing-evidence
/bin/mkdir "$case_evidence"
/bin/chmod 700 "$case_evidence"
print -n -r -- 'preserve-me' >"$case_evidence/sentinel"
existing_fingerprint="$(evidence_fingerprint "$case_evidence")"
if run_profile >"$case_output" 2>&1; then
  fail "fresh mode reused an existing evidence directory"
fi
assert_evidence_unchanged "$existing_fingerprint" "$case_evidence" 'fresh existing-directory guard'
assert_count "$case_state" notary.submit 0
assert_count "$case_state" hdiutil.create 0
assert_public_absent

# Every failure after submit retains the exact upload and performs one submit only.
expect_submitted_failure submit-failure 0 0 \
  FAKE_SUBMIT_EXIT_CODE=69
expect_submitted_failure invalid-submit-id 0 0 \
  FAKE_SUBMIT_ID_OVERRIDE=not-a-uuid
expect_submitted_failure invalid-status 1 1 \
  FAKE_NOTARY_STATUS=Invalid
expect_submitted_failure notary-issues 1 1 \
  'FAKE_NOTARY_ISSUES_JSON=[{"severity":"error","message":"synthetic issue"}]'
expect_submitted_failure wait-id-mismatch 1 1 \
  "FAKE_WAIT_ID_OVERRIDE=$other_submission_id"
expect_submitted_failure log-id-mismatch 1 1 \
  "FAKE_LOG_ID_OVERRIDE=$other_submission_id"
expect_submitted_failure log-digest-mismatch 1 1 \
  'FAKE_LOG_DIGEST_OVERRIDE=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
expect_submitted_failure app-dmg-id-collision 0 0 \
  "FAKE_SUBMIT_ID_OVERRIDE=$app_submission_id"

# A timeout fixture drives all retry and resume invariants.
prepare_case timeout-fixture
if run_profile FAKE_WAIT_EXIT_CODE=124 >"$case_output" 2>&1; then
  fail "synthetic notary timeout unexpectedly succeeded"
fi
assert_count "$case_state" notary.submit 1
assert_count "$case_state" notary.wait 1
assert_count "$case_state" notary.log 1
assert_count "$case_state" hdiutil.create 1
assert_count "$case_state" codesign.sign 1
assert_exact_upload_retained
assert_public_absent
timeout_state="$case_state"
timeout_evidence="$case_evidence"
timeout_fingerprint="$(evidence_fingerprint "$timeout_evidence")"

# TERM after submit retains exact resumable evidence, cleans the lock, and never resubmits.
prepare_case term-after-submit
term_marker="$case_root/notary-wait.blocked"
term_release="$case_root/notary-wait.release"
/usr/bin/env \
  "${common_env[@]}" \
  "NOTARY_KEYCHAIN_PROFILE=$profile_name" \
  "FAKE_WAIT_BLOCK_MARKER=$term_marker" \
  "FAKE_WAIT_BLOCK_RELEASE=$term_release" \
  "$package_script" >"$case_output" 2>&1 &
term_pid=$!
wait_for_marker "$term_marker" "$term_pid" || {
  /bin/kill -TERM "$term_pid" >/dev/null 2>&1 || true
  /usr/bin/touch "$term_release"
  wait "$term_pid" >/dev/null 2>&1 || true
  /bin/cat "$case_output" >&2
  fail "DMG packager did not reach the cancellable post-submit wait"
}
/bin/kill -TERM "$term_pid"
/usr/bin/touch "$term_release"
term_status=0
wait "$term_pid" || term_status=$?
[[ "$term_status" -ne 0 ]] || fail "TERM cancellation unexpectedly published a DMG"
assert_count "$case_state" notary.submit 1
assert_exact_upload_retained
assert_public_absent
[[ ! -e "$case_evidence/.notarization-operation.lock" ]] || \
  fail "TERM cancellation left an operation lock"
if /usr/bin/find "$case_evidence" -maxdepth 1 -type d -name '.dmg-root.*' -print -quit | \
  /usr/bin/grep -q .; then
  fail "TERM cancellation left private DMG staging"
fi
[[ ! -e "$case_evidence/notarization-metadata.json" ]] || \
  fail "TERM cancellation committed accepted metadata"
run_profile "DMG_NOTARY_SUBMISSION_ID=$default_dmg_submission_id" >>"$case_output" 2>&1
assert_count "$case_state" notary.submit 1
for public_path in "$public_dmg" "$public_manifest" "$public_checksums"; do
  [[ -f "$public_path" && ! -L "$public_path" ]] || \
    fail "resume after TERM did not publish the verified tuple"
done

# A mistaken fresh retry after timeout cannot submit or mutate evidence.
if run_profile >"$case_root/fresh-retry.log" 2>&1; then
  fail "fresh retry reused timed-out evidence"
fi
assert_evidence_unchanged "$timeout_fingerprint" "$timeout_evidence" 'fresh retry after timeout'
assert_count "$timeout_state" notary.submit 1
assert_count "$timeout_state" hdiutil.create 1
assert_count "$timeout_state" codesign.sign 1

# Resume with a different ID fails before mutation.
clone_timeout_case resume-wrong-id
resume_fingerprint="$(evidence_fingerprint "$case_evidence")"
if run_profile "DMG_NOTARY_SUBMISSION_ID=$other_submission_id" >"$case_output" 2>&1; then
  fail "resume accepted a submission ID different from the submit result"
fi
assert_evidence_unchanged "$resume_fingerprint" "$case_evidence" 'wrong-ID resume'
assert_count "$case_state" notary.submit 1
assert_public_absent

# Resume rejects a changed upload before archiving or replacing any output.
clone_timeout_case resume-tampered-upload
print -r -- 'tamper' >>"$case_evidence/notary-upload.dmg"
resume_fingerprint="$(evidence_fingerprint "$case_evidence")"
if run_profile "DMG_NOTARY_SUBMISSION_ID=$default_dmg_submission_id" >"$case_output" 2>&1; then
  fail "resume accepted a changed submitted DMG"
fi
assert_evidence_unchanged "$resume_fingerprint" "$case_evidence" 'tampered-upload resume'
assert_count "$case_state" notary.submit 1
assert_public_absent

# Resume requires owner-only directory mode before it can acquire a lock.
clone_timeout_case resume-unsafe-mode
/bin/chmod 755 "$case_evidence"
resume_fingerprint="$(evidence_fingerprint "$case_evidence")"
if run_profile "DMG_NOTARY_SUBMISSION_ID=$default_dmg_submission_id" >"$case_output" 2>&1; then
  fail "resume accepted unsafe evidence-directory permissions"
fi
assert_evidence_unchanged "$resume_fingerprint" "$case_evidence" 'unsafe-mode resume'
assert_count "$case_state" notary.submit 1
assert_public_absent

# Resume also requires each preserved private input to remain owner-only.
clone_timeout_case resume-unsafe-file-mode
/bin/chmod 644 "$case_evidence/notary-upload.sha256"
resume_fingerprint="$(evidence_fingerprint "$case_evidence")"
if run_profile "DMG_NOTARY_SUBMISSION_ID=$default_dmg_submission_id" >"$case_output" 2>&1; then
  fail "resume accepted unsafe evidence-file permissions"
fi
assert_evidence_unchanged "$resume_fingerprint" "$case_evidence" 'unsafe-file-mode resume'
assert_count "$case_state" notary.submit 1
assert_public_absent

# Authentication validation also precedes any resume mutation.
clone_timeout_case resume-mixed-auth
resume_fingerprint="$(evidence_fingerprint "$case_evidence")"
if run_profile \
  "DMG_NOTARY_SUBMISSION_ID=$default_dmg_submission_id" \
  "NOTARY_API_KEY_PATH=$api_key" \
  "NOTARY_API_KEY_ID=$api_key_id" \
  "NOTARY_API_ISSUER_ID=$api_issuer_id" >"$case_output" 2>&1; then
  fail "resume accepted mixed authentication"
fi
assert_evidence_unchanged "$resume_fingerprint" "$case_evidence" 'mixed-auth resume'
assert_count "$case_state" notary.submit 1
assert_public_absent

# An operation lock is fail-closed and must remain untouched for inspection.
clone_timeout_case resume-operation-lock
/bin/mkdir "$case_evidence/.notarization-operation.lock"
/bin/chmod 700 "$case_evidence/.notarization-operation.lock"
resume_fingerprint="$(evidence_fingerprint "$case_evidence")"
if run_profile "DMG_NOTARY_SUBMISSION_ID=$default_dmg_submission_id" >"$case_output" 2>&1; then
  fail "resume ignored an existing operation lock"
fi
assert_evidence_unchanged "$resume_fingerprint" "$case_evidence" 'operation-lock resume'
assert_count "$case_state" notary.submit 1
assert_public_absent

# Accepted metadata is a permanent completion lock, even if resume is requested.
clone_timeout_case resume-accepted-lock
print -n -r -- 'accepted-lock-sentinel' >"$case_evidence/notarization-metadata.json"
/bin/chmod 600 "$case_evidence/notarization-metadata.json"
resume_fingerprint="$(evidence_fingerprint "$case_evidence")"
if run_profile "DMG_NOTARY_SUBMISSION_ID=$default_dmg_submission_id" >"$case_output" 2>&1; then
  fail "resume ignored accepted notarization metadata"
fi
assert_evidence_unchanged "$resume_fingerprint" "$case_evidence" 'accepted-metadata resume lock'
assert_count "$case_state" notary.submit 1
assert_public_absent

# Valid resume may wait/log/staple/package, but never create, sign, or submit.
clone_timeout_case resume-valid
before_create="$(count_value "$case_state" hdiutil.create)"
before_sign="$(count_value "$case_state" codesign.sign)"
before_submit="$(count_value "$case_state" notary.submit)"
before_upload_digest="$(/usr/bin/shasum -a 256 "$case_evidence/notary-upload.dmg" | /usr/bin/awk '{ print $1 }')"
run_profile "DMG_NOTARY_SUBMISSION_ID=$default_dmg_submission_id" >"$case_output" 2>&1
[[ "$(count_value "$case_state" hdiutil.create)" == "$before_create" ]] || fail "valid resume recreated the DMG"
[[ "$(count_value "$case_state" codesign.sign)" == "$before_sign" ]] || fail "valid resume resigned the DMG"
[[ "$(count_value "$case_state" notary.submit)" == "$before_submit" ]] || fail "valid resume submitted again"
assert_count "$case_state" notary.wait 2
assert_count "$case_state" notary.log 2
[[ -f "$case_evidence/notary-wait.json.previous" ]] || fail "valid resume did not archive the prior wait output"
[[ -f "$case_evidence/notary-log.json.previous" ]] || fail "valid resume did not archive the prior log output"
after_upload_digest="$(/usr/bin/shasum -a 256 "$case_evidence/notary-upload.dmg" | /usr/bin/awk '{ print $1 }')"
[[ "$after_upload_digest" == "$before_upload_digest" ]] || fail "valid resume changed the exact submitted DMG"
[[ -f "$case_evidence/notarization-metadata.json" ]] || fail "valid resume did not commit accepted metadata"
[[ "$(/usr/bin/plutil -extract submissionId raw -o - "$case_evidence/notarization-metadata.json")" == "$default_dmg_submission_id" ]] || \
  fail "valid resume committed the wrong submission ID"
[[ "$(/usr/bin/plutil -extract notarization.application.submissionId raw -o - "$public_manifest")" == "$app_submission_id" ]] || \
  fail "resumed manifest has the wrong app submission ID"
[[ "$(/usr/bin/plutil -extract notarization.diskImage.submissionId raw -o - "$public_manifest")" == "$default_dmg_submission_id" ]] || \
  fail "resumed manifest has the wrong DMG submission ID"
assert_mode "$case_evidence" 700
while IFS= read -r private_file; do
  assert_mode "$private_file" 600
done < <(/usr/bin/find "$case_evidence" -type f -maxdepth 1 -print | LC_ALL=C /usr/bin/sort)

# A verifier failure occurs before publication and leaves no partial public triple.
prepare_case verifier-failure-atomic
if run_profile FAKE_DMG_VERIFY_EXIT_CODE=88 >"$case_output" 2>&1; then
  fail "package succeeded after its final verifier failed"
fi
assert_count "$case_state" notary.submit 1
assert_count "$case_state" dmg.verify 1
assert_public_absent
[[ -f "$case_evidence/notarization-metadata.pending.json" ]] || \
  fail "verifier failure did not retain private pending metadata"
[[ ! -e "$case_evidence/notarization-metadata.json" ]] || \
  fail "verifier failure committed accepted metadata"

# A concurrent claimant for the final DMG cannot be overwritten; earlier links roll back.
prepare_case concurrent-publication-claim
concurrent_content='synthetic concurrent claimant'
if run_profile "FAKE_CONCURRENT_DMG_CONTENT=$concurrent_content" >"$case_output" 2>&1; then
  fail "package overwrote a concurrently created public DMG"
fi
assert_count "$case_state" notary.submit 1
[[ -f "$public_dmg" && "$(<"$public_dmg")" == "$concurrent_content" ]] || \
  fail "concurrent public DMG was overwritten or removed"
[[ ! -e "$public_manifest" && ! -L "$public_manifest" ]] || \
  fail "manifest was not rolled back after concurrent publication failure"
[[ ! -e "$public_checksums" && ! -L "$public_checksums" ]] || \
  fail "checksums were not rolled back after concurrent publication failure"
[[ ! -e "$case_evidence/notarization-metadata.json" ]] || \
  fail "concurrent publication failure committed accepted metadata"

# A preexisting public path is never overwritten and blocks work before evidence creation.
prepare_case preexisting-public-output
/bin/mkdir "$case_dist"
preexisting_content='preexisting checksum sentinel'
print -n -r -- "$preexisting_content" >"$public_checksums"
/bin/chmod 644 "$public_checksums"
if run_profile >"$case_output" 2>&1; then
  fail "package overwrote a preexisting public artifact"
fi
[[ "$(<"$public_checksums")" == "$preexisting_content" ]] || fail "preexisting public artifact changed"
[[ ! -e "$public_dmg" && ! -L "$public_dmg" ]] || fail "preexisting-output guard created a DMG"
[[ ! -e "$public_manifest" && ! -L "$public_manifest" ]] || fail "preexisting-output guard created a manifest"
[[ ! -e "$case_evidence" && ! -L "$case_evidence" ]] || fail "preexisting-output guard claimed evidence"
assert_count "$case_state" notary.submit 0
assert_count "$case_state" hdiutil.create 0

print "Developer ID DMG tooling tests passed (${case_count} isolated cases)"
