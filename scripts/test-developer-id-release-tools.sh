#!/bin/zsh

set -euo pipefail

fail() {
  print -u2 "Developer ID tooling test failed: $*"
  exit 1
}

script_dir="${0:A:h}"
repository_root="${script_dir:h}"
unset NOTARY_KEYCHAIN_PROFILE NOTARY_API_KEY_PATH NOTARY_API_KEY_ID NOTARY_API_ISSUER_ID

for script in \
  "$script_dir/verify-developer-id-certificate.sh" \
  "$script_dir/verify-macos-bundle-contents.sh" \
  "$script_dir/verify-macos-developer-id-signature.sh" \
  "$script_dir/notarize-macos-developer-id.sh" \
  "$script_dir/verify-macos-developer-id-release.sh" \
  "$script_dir/package-macos-developer-id-candidate.sh"; do
  /bin/zsh -n "$script"
done

candidate_workflow="$repository_root/.github/workflows/developer-id-candidate.yml"
prototype_makefile="$repository_root/prototype/EstroboMac/Makefile"
[[ -r "$candidate_workflow" ]] || fail "Developer ID candidate workflow is missing"
/usr/bin/grep -Fq \
  'export NOTARY_KEYCHAIN_PROFILE NOTARY_API_KEY_PATH NOTARY_API_KEY_ID NOTARY_API_ISSUER_ID' \
  "$prototype_makefile" || fail "prototype Makefile does not export notarization authentication privately"
if /usr/bin/grep -Fq 'NOTARY_KEYCHAIN_PROFILE="$(NOTARY_KEYCHAIN_PROFILE)"' "$prototype_makefile"; then
  fail "prototype Makefile interpolates the keychain profile into recipe output"
fi
/usr/bin/grep -Fq 'workflow_dispatch:' "$candidate_workflow" || fail "candidate workflow is not manual-only"
/usr/bin/grep -Eq '^[[:space:]]+contents:[[:space:]]+read$' "$candidate_workflow" || \
  fail "candidate workflow does not declare read-only repository permissions"
if /usr/bin/grep -Eq 'contents:[[:space:]]+write|gh[[:space:]]+release|release[[:space:]]+(create|edit|upload)' "$candidate_workflow"; then
  fail "candidate workflow contains release mutation authority"
fi
/usr/bin/grep -Fq 'name: developer-id-signing' "$candidate_workflow" || \
  fail "candidate workflow does not use the protected signing environment"
/usr/bin/grep -Fq 'name: developer-id-verification' "$candidate_workflow" || \
  fail "candidate workflow does not isolate clean-host verification"
/usr/bin/grep -Fq 'ESTROBO_CANDIDATE_ARTIFACT_PASSWORD' "$candidate_workflow" || \
  fail "candidate workflow does not encrypt public-repository artifacts"
if /usr/bin/grep -Fq 'NOTARY_KEYCHAIN_PROFILE' "$candidate_workflow"; then
  fail "candidate workflow must remain API-key-only"
fi
legacy_workflow="$repository_root/.github/workflows/release-beta.yml"
/usr/bin/ruby -ryaml - "$candidate_workflow" "$legacy_workflow" <<'RUBY' || \
  fail "candidate workflow uploads an unencrypted Actions artifact"
workflow = YAML.safe_load(File.read(ARGV.fetch(0)), aliases: true)
jobs = workflow.fetch("jobs")
if YAML.dump(jobs).include?("prototype/GodoxMacControlPrototype/")
  raise "current candidate workflow still uses the pre-rename prototype path"
end

legacy_workflow = YAML.safe_load(File.read(ARGV.fetch(1)), aliases: true)
legacy_events = legacy_workflow["on"] || legacy_workflow[true]
raise "legacy workflow is not manual-only" unless legacy_events.keys == ["workflow_dispatch"]
legacy_jobs = legacy_workflow.fetch("jobs")
legacy_source = YAML.dump(legacy_jobs)
if legacy_source.include?("prototype/EstroboMac/")
  raise "historical rebuilds must use paths from the immutable beta 1/2 tag trees"
end
legacy_validation = legacy_jobs.fetch("validate").fetch("steps").find { |step| step["id"] == "release" }.fetch("run")
unless legacy_validation.include?("v0.1.0-beta.1|v0.1.0-beta.2)") &&
    legacy_validation.include?('plist="prototype/GodoxMacControlPrototype/Info.plist"')
  raise "legacy workflow lost the historical tag or source-path restriction"
end
%w[
  prototype/GodoxMacControlPrototype/Build/estrobo.app/Contents/MacOS/estrobo
  prototype/GodoxMacControlPrototype/Build/Universal/estrobo.app
  prototype/GodoxMacControlPrototype/Build/Universal
].each do |historical_path|
  raise "historical build path is missing: #{historical_path}" unless legacy_source.include?(historical_path)
end
unless jobs.fetch("sign-and-notarize").fetch("if").include?("github.run_attempt == 1")
  raise "signing job reruns can create duplicate notarization submissions"
end
jobs.each_value do |job|
  if job.fetch("env", {}).key?("CANDIDATE_ARTIFACT_PASSWORD")
    raise "artifact password is exposed to an entire job"
  end
end

verification_job = YAML.dump(jobs.fetch("verify-and-package"))
%w[
  ESTROBO_DEVELOPER_ID_P12_BASE64
  ESTROBO_DEVELOPER_ID_P12_PASSWORD
  ESTROBO_NOTARY_API_KEY_P8_BASE64
  ESTROBO_NOTARY_API_KEY_ID
  ESTROBO_NOTARY_API_ISSUER_ID
].each do |apple_secret|
  raise "Apple credential leaked into clean-host verification" if verification_job.include?(apple_secret)
end

sign_steps = jobs.fetch("sign-and-notarize").fetch("steps")
step_named = ->(steps, name) { steps.find { |step| step["name"] == name } or raise "missing step: #{name}" }
encryption_preflight = sign_steps.index(step_named.call(sign_steps, "Validate candidate artifact encryption before signing"))
notary_submit = sign_steps.index(step_named.call(sign_steps, "Submit, wait, staple, and validate"))
raise "artifact encryption is validated after notarization" unless encryption_preflight < notary_submit

transfer_upload = step_named.call(sign_steps, "Upload encrypted stapled app for clean-host verification")
transfer_download = step_named.call(
  jobs.fetch("verify-and-package").fetch("steps"),
  "Download encrypted stapled app"
)
raise "transfer upload/download names differ" unless \
  transfer_upload.fetch("with").fetch("name") == transfer_download.fetch("with").fetch("name")
raise "transfer artifact cannot survive a failed-job rerun" unless \
  transfer_upload.fetch("with").fetch("overwrite") == true
raise "transfer retention is shorter than environment approval" unless \
  transfer_upload.fetch("with").fetch("retention-days").to_i >= 31

recovery_upload = step_named.call(sign_steps, "Upload encrypted recovery evidence")
raise "recovery attempts can overwrite each other" if recovery_upload.fetch("with").fetch("overwrite", false)
raise "recovery artifact does not distinguish run attempts" unless \
  recovery_upload.fetch("with").fetch("name").include?("github.run_attempt")
recovery_encryption = step_named.call(sign_steps, "Encrypt failure diagnostics and exact recovery app")
unless recovery_encryption.fetch("run").include?("notary-upload.zip.sha256")
  raise "encrypted recovery evidence omits the checksum required to resume the exact notarization upload"
end

uploads = jobs.values.flat_map { |job| job.fetch("steps", []) }.select do |step|
  step.fetch("uses", "").include?("actions/upload-artifact@")
end
raise "expected encrypted diagnostics, transfer, and candidate uploads" unless uploads.length == 3

uploads.each do |step|
  paths = step.fetch("with").fetch("path").to_s.lines.map(&:strip).reject(&:empty?)
  raise "upload without explicit files" if paths.empty?
  invalid = paths.reject { |path| path.end_with?(".enc", ".sha256") }
  raise "unencrypted upload path: #{invalid.join(', ')}" unless invalid.empty?
end
RUBY

temporary_dir="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/estrobo-developer-id-tools-test.XXXXXX")"
trap '/bin/rm -rf -- "$temporary_dir"' EXIT

crypto_dir="$temporary_dir/crypto"
/bin/mkdir -p "$crypto_dir"
plain_artifact="$crypto_dir/plain-candidate.tar.gz"
encrypted_artifact="$plain_artifact.enc"
decrypted_artifact="$crypto_dir/decrypted-candidate.tar.gz"
encryption_password='synthetic-test-password-with-more-than-32-characters'
print -n -r -- 'synthetic Developer ID candidate bytes' >"$plain_artifact"
CANDIDATE_ARTIFACT_PASSWORD="$encryption_password" \
  /usr/bin/openssl enc -aes-256-cbc -salt -pbkdf2 -iter 200000 -md sha256 \
    -pass env:CANDIDATE_ARTIFACT_PASSWORD \
    -in "$plain_artifact" \
    -out "$encrypted_artifact"
(
  cd "$crypto_dir"
  /usr/bin/shasum -a 256 "${encrypted_artifact:t}" >"${encrypted_artifact:t}.sha256"
  /usr/bin/shasum -a 256 -c "${encrypted_artifact:t}.sha256"
)
CANDIDATE_ARTIFACT_PASSWORD="$encryption_password" \
  /usr/bin/openssl enc -d -aes-256-cbc -pbkdf2 -iter 200000 -md sha256 \
    -pass env:CANDIDATE_ARTIFACT_PASSWORD \
    -in "$encrypted_artifact" \
    -out "$decrypted_artifact"
/usr/bin/cmp -s "$plain_artifact" "$decrypted_artifact" || \
  fail "candidate artifact encryption did not round-trip"

app_bundle="$temporary_dir/estrobo.app"
/bin/mkdir -p "$app_bundle/Contents/MacOS"
/usr/bin/touch "$app_bundle/Contents/MacOS/estrobo"
/bin/chmod 755 "$app_bundle/Contents/MacOS/estrobo"

bundle_content_verifier="$script_dir/verify-macos-bundle-contents.sh"
"$bundle_content_verifier" "$app_bundle" >/dev/null
/bin/mkdir -p "$app_bundle/Contents/Resources"
print -r -- 'SYNTHETIC_TEST_VALUE=not-a-secret' >"$app_bundle/Contents/Resources/.env"
if "$bundle_content_verifier" "$app_bundle" >/dev/null 2>&1; then
  fail "bundle content verifier accepted a copied .env file"
fi
/bin/rm -- "$app_bundle/Contents/Resources/.env"

api_key="$temporary_dir/AuthKey_TESTKEY123.p8"
print -r -- 'synthetic test key; never a credential' >"$api_key"
/bin/chmod 600 "$api_key"

fake_state_dir="$temporary_dir/fake-notary-state"
/bin/mkdir -p "$fake_state_dir"
fake_xcrun="$temporary_dir/fake-xcrun"
cat >"$fake_xcrun" <<'FAKE_XCRUN'
#!/bin/zsh
set -euo pipefail

[[ "${1:-}" == notarytool || "${1:-}" == stapler ]] || exit 64

if [[ "$1" == notarytool && "$2" == submit ]]; then
  print -rl -- "$@" >"$FAKE_STATE_DIR/submit.args"
  submit_count=0
  if [[ -f "$FAKE_STATE_DIR/submit.count" ]]; then
    submit_count="$(<"$FAKE_STATE_DIR/submit.count")"
  fi
  print -r -- "$((submit_count + 1))" >"$FAKE_STATE_DIR/submit.count"
  submit_exit_code="${FAKE_SUBMIT_EXIT_CODE:-0}"
  if [[ "$submit_exit_code" -ne 0 ]]; then
    print -u2 "Synthetic submit failure"
    exit "$submit_exit_code"
  fi
  /usr/bin/shasum -a 256 "$3" | /usr/bin/awk '{ print tolower($1) }' >"$FAKE_STATE_DIR/upload.sha256"
  submit_id="${FAKE_SUBMIT_ID_OVERRIDE:-abcdefab-cdef-abcd-efab-cdefabcdefab}"
  [[ -z "${FAKE_LEAK_VALUE:-}" ]] || print -u2 -- "profile=${FAKE_LEAK_VALUE}"
  print -r -- "{\"id\":\"$submit_id\",\"message\":\"Successfully uploaded file ${FAKE_LEAK_VALUE:-}\",\"status\":\"In Progress\"}"
  exit 0
fi

if [[ "$1" == notarytool && "$2" == wait ]]; then
  print -rl -- "$@" >"$FAKE_STATE_DIR/wait.args"
  if [[ -n "${FAKE_WAIT_BLOCK_MARKER:-}" ]]; then
    /usr/bin/touch "$FAKE_WAIT_BLOCK_MARKER"
    while [[ ! -e "${FAKE_WAIT_BLOCK_RELEASE:?}" ]]; do
      /bin/sleep 0.02
    done
  fi
  wait_exit_code="${FAKE_WAIT_EXIT_CODE:-0}"
  if [[ "$wait_exit_code" -ne 0 ]]; then
    print -u2 "Synthetic wait timeout"
    exit "$wait_exit_code"
  fi
  wait_id="${FAKE_WAIT_ID_OVERRIDE:-$3}"
  if [[ "${FAKE_WAIT_UPPERCASE_ID:-0}" == 1 ]]; then
    wait_id="$(print -r -- "$wait_id" | /usr/bin/tr '[:lower:]' '[:upper:]')"
  fi
  [[ -z "${FAKE_LEAK_VALUE:-}" ]] || print -u2 -- "profile=${FAKE_LEAK_VALUE}"
  print -r -- "{\"id\":\"$wait_id\",\"message\":\"Processing complete ${FAKE_LEAK_VALUE:-}\",\"status\":\"${FAKE_NOTARY_STATUS:-Accepted}\"}"
  exit 0
fi

if [[ "$1" == notarytool && "$2" == log ]]; then
  print -rl -- "$@" >"$FAKE_STATE_DIR/log.args"
  submission_id="$3"
  output_path="$4"
  log_exit_code="${FAKE_LOG_EXIT_CODE:-0}"
  if [[ "$log_exit_code" -ne 0 ]]; then
    print -u2 "Synthetic log failure"
    exit "$log_exit_code"
  fi
  log_id="${FAKE_LOG_ID_OVERRIDE:-$submission_id}"
  if [[ "${FAKE_LOG_UPPERCASE_ID:-0}" == 1 ]]; then
    log_id="$(print -r -- "$log_id" | /usr/bin/tr '[:lower:]' '[:upper:]')"
  fi
  upload_digest="$(<"$FAKE_STATE_DIR/upload.sha256")"
  log_digest="${FAKE_LOG_DIGEST_OVERRIDE:-$upload_digest}"
  issues_json="${FAKE_NOTARY_ISSUES_JSON:-null}"
  [[ -z "${FAKE_LEAK_VALUE:-}" ]] || print -u2 -- "profile=${FAKE_LEAK_VALUE}"
  print -r -- "{\"jobId\":\"$log_id\",\"status\":\"${FAKE_NOTARY_STATUS:-Accepted}\",\"statusSummary\":\"Synthetic test ${FAKE_LEAK_VALUE:-}\",\"statusCode\":0,\"sha256\":\"$log_digest\",\"issues\":$issues_json}" >"$output_path"
  exit 0
fi

if [[ "$1" == stapler && "$2" == staple ]]; then
  app="${@: -1}"
  /usr/bin/touch "$app/Contents/.synthetic-stapled-ticket"
  print "Synthetic staple succeeded"
  exit 0
fi

if [[ "$1" == stapler && "$2" == validate ]]; then
  app="${@: -1}"
  [[ -f "$app/Contents/.synthetic-stapled-ticket" ]]
  print "Synthetic staple validation succeeded"
  exit 0
fi

exit 64
FAKE_XCRUN
/bin/chmod 755 "$fake_xcrun"

fake_codesign="$temporary_dir/fake-codesign"
cat >"$fake_codesign" <<'FAKE_CODESIGN'
#!/bin/zsh
set -euo pipefail
[[ "${1:-}" == -dvvv && -d "${2:-}" ]] || exit 64
print -u2 'Identifier=mx.loo.estrobo'
print -u2 'CDHash=1111111111111111111111111111111111111111'
print -u2 'TeamIdentifier=ABCDE12345'
FAKE_CODESIGN
/bin/chmod 755 "$fake_codesign"
export CODESIGN_COMMAND="$fake_codesign"

evidence_dir="$temporary_dir/evidence-accepted"
FAKE_STATE_DIR="$fake_state_dir" \
FAKE_NOTARY_STATUS=Accepted \
FAKE_WAIT_UPPERCASE_ID=1 \
FAKE_LOG_UPPERCASE_ID=1 \
XCRUN_COMMAND="$fake_xcrun" \
APP_BUNDLE="$app_bundle" \
DEVELOPER_ID_TEAM_ID=ABCDE12345 \
NOTARY_API_KEY_PATH="$api_key" \
NOTARY_API_KEY_ID=TESTKEY123 \
NOTARY_API_ISSUER_ID=aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee \
NOTARIZATION_UPLOAD_ARCHIVE="$evidence_dir/notary-upload.zip" \
NOTARIZATION_SUBMIT_RESULT="$evidence_dir/notary-submit.json" \
NOTARIZATION_WAIT_RESULT="$evidence_dir/notary-wait.json" \
NOTARIZATION_LOG="$evidence_dir/notary-log.json" \
NOTARIZATION_METADATA="$evidence_dir/notarization-metadata.json" \
  "$script_dir/notarize-macos-developer-id.sh"

[[ "$(/usr/bin/plutil -extract status raw -o - "$evidence_dir/notarization-metadata.json")" == Accepted ]] || \
  fail "accepted notarization metadata was not produced"
[[ "$(/usr/bin/plutil -extract ticketStapled raw -o - "$evidence_dir/notarization-metadata.json")" == true ]] || \
  fail "accepted notarization metadata does not record stapling"
[[ "$(/usr/bin/plutil -extract submissionId raw -o - "$evidence_dir/notarization-metadata.json")" == \
  abcdefab-cdef-abcd-efab-cdefabcdefab ]] || \
  fail "accepted notarization metadata did not canonicalize the submission ID"
[[ "$(/usr/bin/plutil -extract bundleIdentifier raw -o - "$evidence_dir/notarization-metadata.json")" == \
  mx.loo.estrobo ]] || fail "accepted notarization metadata omitted the signed bundle identifier"
[[ "$(/usr/bin/plutil -extract codeDirectoryHash raw -o - "$evidence_dir/notarization-metadata.json")" == \
  1111111111111111111111111111111111111111 ]] || \
  fail "accepted notarization metadata omitted the signed app CodeDirectory hash"
[[ "$(<"$fake_state_dir/submit.count")" == 1 ]] || \
  fail "accepted notarization submitted more than once"
[[ ! -e "$evidence_dir/notary-upload.zip" ]] || \
  fail "accepted notarization retained its temporary upload archive"
for auth_operation in submit wait log; do
  auth_args_file="$fake_state_dir/${auth_operation}.args"
  for required_api_arg in --key --key-id --issuer; do
    /usr/bin/grep -Fxq -- "$required_api_arg" "$auth_args_file" || \
      fail "API-key notarization omitted $required_api_arg for $auth_operation"
  done
  if /usr/bin/grep -Fxq -- '--keychain-profile' "$auth_args_file"; then
    fail "API-key notarization mixed keychain-profile authentication for $auth_operation"
  fi
done

profile_app="$temporary_dir/profile-auth/estrobo.app"
profile_evidence_dir="$temporary_dir/evidence-profile-auth"
profile_state_dir="$temporary_dir/state-profile-auth"
profile_output="$temporary_dir/profile-auth-output.log"
/bin/mkdir -p "$profile_app/Contents/MacOS" "$profile_state_dir"
/usr/bin/touch "$profile_app/Contents/MacOS/estrobo"
/bin/chmod 755 "$profile_app/Contents/MacOS/estrobo"
FAKE_STATE_DIR="$profile_state_dir" \
XCRUN_COMMAND="$fake_xcrun" \
APP_BUNDLE="$profile_app" \
DEVELOPER_ID_TEAM_ID=ABCDE12345 \
NOTARY_KEYCHAIN_PROFILE=synthetic-notary-profile \
FAKE_LEAK_VALUE=synthetic-notary-profile \
NOTARIZATION_UPLOAD_ARCHIVE="$profile_evidence_dir/notary-upload.zip" \
NOTARIZATION_SUBMIT_RESULT="$profile_evidence_dir/notary-submit.json" \
NOTARIZATION_WAIT_RESULT="$profile_evidence_dir/notary-wait.json" \
NOTARIZATION_LOG="$profile_evidence_dir/notary-log.json" \
NOTARIZATION_METADATA="$profile_evidence_dir/notarization-metadata.json" \
  /bin/zsh -x "$script_dir/notarize-macos-developer-id.sh" >"$profile_output" 2>&1

[[ "$(<"$profile_state_dir/submit.count")" == 1 ]] || \
  fail "keychain-profile notarization did not submit exactly once"
for auth_operation in submit wait log; do
  auth_args_file="$profile_state_dir/${auth_operation}.args"
  /usr/bin/grep -Fxq -- '--keychain-profile' "$auth_args_file" || \
    fail "keychain-profile notarization did not select profile authentication for $auth_operation"
  /usr/bin/grep -Fxq -- 'synthetic-notary-profile' "$auth_args_file" || \
    fail "keychain-profile notarization omitted its profile name for $auth_operation"
  for forbidden_api_arg in --key --key-id --issuer; do
    if /usr/bin/grep -Fxq -- "$forbidden_api_arg" "$auth_args_file"; then
      fail "keychain-profile notarization mixed API key authentication for $auth_operation"
    fi
  done
done
[[ -f "$profile_evidence_dir/notarization-metadata.json" ]] || \
  fail "keychain-profile notarization did not produce accepted metadata"
[[ "$(/usr/bin/stat -f '%Lp' "$profile_evidence_dir")" == 700 ]] || \
  fail "keychain-profile evidence directory is not owner-only"
for private_evidence_file in \
  "$profile_evidence_dir/notary-submit.json" \
  "$profile_evidence_dir/notary-wait.json" \
  "$profile_evidence_dir/notary-log.json" \
  "$profile_evidence_dir/notary-upload.zip.sha256" \
  "$profile_evidence_dir/notarization-metadata.json"; do
  [[ "$(/usr/bin/stat -f '%Lp' "$private_evidence_file")" == 600 ]] || \
    fail "keychain-profile evidence file is not owner-only: ${private_evidence_file:t}"
done
if /usr/bin/grep -RFq -- 'synthetic-notary-profile' "$profile_evidence_dir" "$profile_output"; then
  fail "keychain profile name leaked into notarization evidence or script output"
fi

# TERM after submit keeps the exact resumable upload, releases private state, and never resubmits.
cancel_app="$temporary_dir/cancel-after-submit/estrobo.app"
cancel_evidence_dir="$temporary_dir/evidence-cancel-after-submit"
cancel_state_dir="$temporary_dir/state-cancel-after-submit"
cancel_output="$temporary_dir/cancel-after-submit.log"
cancel_marker="$temporary_dir/cancel-after-submit.blocked"
cancel_release="$temporary_dir/cancel-after-submit.release"
/bin/mkdir -p "$cancel_app/Contents/MacOS" "$cancel_state_dir"
/usr/bin/touch "$cancel_app/Contents/MacOS/estrobo"
/bin/chmod 755 "$cancel_app/Contents/MacOS/estrobo"
notary_temp_before="$(/usr/bin/find /private/tmp -maxdepth 1 -type d \
  -name 'estrobo-notary-output.*' -print | LC_ALL=C /usr/bin/sort)"
/usr/bin/env \
  "FAKE_STATE_DIR=$cancel_state_dir" \
  "FAKE_WAIT_BLOCK_MARKER=$cancel_marker" \
  "FAKE_WAIT_BLOCK_RELEASE=$cancel_release" \
  "XCRUN_COMMAND=$fake_xcrun" \
  "APP_BUNDLE=$cancel_app" \
  DEVELOPER_ID_TEAM_ID=ABCDE12345 \
  NOTARY_KEYCHAIN_PROFILE=synthetic-notary-profile \
  "NOTARIZATION_UPLOAD_ARCHIVE=$cancel_evidence_dir/notary-upload.zip" \
  "NOTARIZATION_SUBMIT_RESULT=$cancel_evidence_dir/notary-submit.json" \
  "NOTARIZATION_WAIT_RESULT=$cancel_evidence_dir/notary-wait.json" \
  "NOTARIZATION_LOG=$cancel_evidence_dir/notary-log.json" \
  "NOTARIZATION_METADATA=$cancel_evidence_dir/notarization-metadata.json" \
  "$script_dir/notarize-macos-developer-id.sh" >"$cancel_output" 2>&1 &
cancel_pid=$!
cancel_ready=false
for attempt in {1..500}; do
  if [[ -e "$cancel_marker" ]]; then
    cancel_ready=true
    break
  fi
  /bin/kill -0 "$cancel_pid" >/dev/null 2>&1 || break
  /bin/sleep 0.02
done
if [[ "$cancel_ready" != true ]]; then
  /bin/kill -TERM "$cancel_pid" >/dev/null 2>&1 || true
  /usr/bin/touch "$cancel_release"
  wait "$cancel_pid" >/dev/null 2>&1 || true
  /bin/cat "$cancel_output" >&2
  fail "app notarizer did not reach the cancellable post-submit wait"
fi
/bin/kill -TERM "$cancel_pid"
/usr/bin/touch "$cancel_release"
cancel_status=0
wait "$cancel_pid" || cancel_status=$?
[[ "$cancel_status" -ne 0 ]] || fail "TERM cancellation unexpectedly completed app notarization"
[[ "$(<"$cancel_state_dir/submit.count")" == 1 ]] || \
  fail "TERM cancellation changed the app submit count"
[[ -f "$cancel_evidence_dir/notary-upload.zip" && \
   -f "$cancel_evidence_dir/notary-upload.zip.sha256" && \
   -f "$cancel_evidence_dir/notary-submit.json" ]] || \
  fail "TERM cancellation lost resumable app evidence"
[[ ! -e "$cancel_evidence_dir/.notarization-operation.lock" ]] || \
  fail "TERM cancellation left the app notarization lock"
[[ ! -e "$cancel_evidence_dir/notarization-metadata.json" ]] || \
  fail "TERM cancellation committed accepted app metadata"
notary_temp_after="$(/usr/bin/find /private/tmp -maxdepth 1 -type d \
  -name 'estrobo-notary-output.*' -print | LC_ALL=C /usr/bin/sort)"
[[ "$notary_temp_after" == "$notary_temp_before" ]] || \
  fail "TERM cancellation left private notarytool output staging"
cancel_submission_id="$(/usr/bin/plutil -extract id raw -o - \
  "$cancel_evidence_dir/notary-submit.json")"
FAKE_STATE_DIR="$cancel_state_dir" \
XCRUN_COMMAND="$fake_xcrun" \
APP_BUNDLE="$cancel_app" \
DEVELOPER_ID_TEAM_ID=ABCDE12345 \
NOTARY_KEYCHAIN_PROFILE=synthetic-notary-profile \
NOTARY_SUBMISSION_ID="$cancel_submission_id" \
NOTARIZATION_UPLOAD_ARCHIVE="$cancel_evidence_dir/notary-upload.zip" \
NOTARIZATION_SUBMIT_RESULT="$cancel_evidence_dir/notary-submit.json" \
NOTARIZATION_WAIT_RESULT="$cancel_evidence_dir/notary-wait.json" \
NOTARIZATION_LOG="$cancel_evidence_dir/notary-log.json" \
NOTARIZATION_METADATA="$cancel_evidence_dir/notarization-metadata.json" \
  "$script_dir/notarize-macos-developer-id.sh" >>"$cancel_output" 2>&1
[[ "$(<"$cancel_state_dir/submit.count")" == 1 ]] || \
  fail "resume after TERM resubmitted the app"
[[ -f "$cancel_evidence_dir/notarization-metadata.json" ]] || \
  fail "resume after TERM did not complete app notarization"

if FAKE_STATE_DIR="$profile_state_dir" \
  XCRUN_COMMAND="$fake_xcrun" \
  APP_BUNDLE="$profile_app" \
  DEVELOPER_ID_TEAM_ID=ABCDE12345 \
  NOTARY_KEYCHAIN_PROFILE=synthetic-notary-profile \
  NOTARIZATION_UPLOAD_ARCHIVE="$profile_evidence_dir/notary-upload.zip" \
  NOTARIZATION_SUBMIT_RESULT="$profile_evidence_dir/notary-submit.json" \
  NOTARIZATION_WAIT_RESULT="$profile_evidence_dir/notary-wait.json" \
  NOTARIZATION_LOG="$profile_evidence_dir/notary-log.json" \
  NOTARIZATION_METADATA="$profile_evidence_dir/notarization-metadata.json" \
    "$script_dir/notarize-macos-developer-id.sh" >/dev/null 2>&1; then
  fail "a second fresh invocation reused an existing evidence directory"
fi
[[ "$(<"$profile_state_dir/submit.count")" == 1 ]] || \
  fail "a second fresh invocation performed a duplicate submit"

expect_auth_failure() {
  local case_name="$1"
  shift
  local case_app="$temporary_dir/auth-$case_name/estrobo.app"
  local case_evidence_dir="$temporary_dir/evidence-auth-$case_name"
  local case_state_dir="$temporary_dir/state-auth-$case_name"
  /bin/mkdir -p "$case_app/Contents/MacOS" "$case_state_dir"
  /usr/bin/touch "$case_app/Contents/MacOS/estrobo"
  /bin/chmod 755 "$case_app/Contents/MacOS/estrobo"

  if /usr/bin/env \
    FAKE_STATE_DIR="$case_state_dir" \
    XCRUN_COMMAND="$fake_xcrun" \
    APP_BUNDLE="$case_app" \
    DEVELOPER_ID_TEAM_ID=ABCDE12345 \
    NOTARIZATION_UPLOAD_ARCHIVE="$case_evidence_dir/notary-upload.zip" \
    NOTARIZATION_SUBMIT_RESULT="$case_evidence_dir/notary-submit.json" \
    NOTARIZATION_WAIT_RESULT="$case_evidence_dir/notary-wait.json" \
    NOTARIZATION_LOG="$case_evidence_dir/notary-log.json" \
    NOTARIZATION_METADATA="$case_evidence_dir/notarization-metadata.json" \
    "$@" \
      "$script_dir/notarize-macos-developer-id.sh" >/dev/null 2>&1; then
    fail "unsafe authentication case '$case_name' was accepted"
  fi
  [[ ! -e "$case_state_dir/submit.count" ]] || \
    fail "unsafe authentication case '$case_name' reached notarytool submit"
  [[ ! -e "$case_evidence_dir/notary-upload.zip" ]] || \
    fail "unsafe authentication case '$case_name' created an upload archive"
}

expect_auth_failure missing-auth
expect_auth_failure partial-api \
  NOTARY_API_KEY_PATH="$api_key"
expect_auth_failure mixed-auth \
  NOTARY_KEYCHAIN_PROFILE=synthetic-notary-profile \
  NOTARY_API_KEY_PATH="$api_key" \
  NOTARY_API_KEY_ID=TESTKEY123 \
  NOTARY_API_ISSUER_ID=aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee
expect_auth_failure invalid-profile \
  NOTARY_KEYCHAIN_PROFILE=../synthetic-notary-profile

expect_evidence_layout_failure() {
  local case_name="$1"
  shift
  local case_app="$temporary_dir/layout-$case_name/estrobo.app"
  local case_evidence_dir="$temporary_dir/evidence-layout-$case_name"
  local case_state_dir="$temporary_dir/state-layout-$case_name"
  /bin/mkdir -p "$case_app/Contents/MacOS" "$case_state_dir"
  /usr/bin/touch "$case_app/Contents/MacOS/estrobo"
  /bin/chmod 755 "$case_app/Contents/MacOS/estrobo"

  if /usr/bin/env \
    FAKE_STATE_DIR="$case_state_dir" \
    XCRUN_COMMAND="$fake_xcrun" \
    APP_BUNDLE="$case_app" \
    DEVELOPER_ID_TEAM_ID=ABCDE12345 \
    NOTARY_KEYCHAIN_PROFILE=synthetic-notary-profile \
    NOTARIZATION_UPLOAD_ARCHIVE="$case_evidence_dir/notary-upload.zip" \
    NOTARIZATION_SUBMIT_RESULT="$case_evidence_dir/notary-submit.json" \
    NOTARIZATION_WAIT_RESULT="$case_evidence_dir/notary-wait.json" \
    NOTARIZATION_LOG="$case_evidence_dir/notary-log.json" \
    NOTARIZATION_METADATA="$case_evidence_dir/notarization-metadata.json" \
    "$@" \
      "$script_dir/notarize-macos-developer-id.sh" >/dev/null 2>&1; then
    fail "unsafe evidence layout '$case_name' was accepted"
  fi
  [[ ! -e "$case_state_dir/submit.count" ]] || \
    fail "unsafe evidence layout '$case_name' reached notarytool submit"
}

expect_evidence_layout_failure duplicate-path \
  NOTARIZATION_SUBMIT_RESULT="$temporary_dir/evidence-layout-duplicate-path/notary-upload.zip"
expect_evidence_layout_failure split-directory \
  NOTARIZATION_LOG="$temporary_dir/evidence-layout-split-directory-other/notary-log.json"
inside_app_evidence="$temporary_dir/layout-inside-app/estrobo.app/private-evidence"
expect_evidence_layout_failure inside-app \
  NOTARIZATION_UPLOAD_ARCHIVE="$inside_app_evidence/notary-upload.zip" \
  NOTARIZATION_SUBMIT_RESULT="$inside_app_evidence/notary-submit.json" \
  NOTARIZATION_WAIT_RESULT="$inside_app_evidence/notary-wait.json" \
  NOTARIZATION_LOG="$inside_app_evidence/notary-log.json" \
  NOTARIZATION_METADATA="$inside_app_evidence/notarization-metadata.json"
inside_repository_evidence="$repository_root/.synthetic-local-notary-evidence"
expect_evidence_layout_failure local-profile-inside-repository \
  NOTARIZATION_UPLOAD_ARCHIVE="$inside_repository_evidence/notary-upload.zip" \
  NOTARIZATION_SUBMIT_RESULT="$inside_repository_evidence/notary-submit.json" \
  NOTARIZATION_WAIT_RESULT="$inside_repository_evidence/notary-wait.json" \
  NOTARIZATION_LOG="$inside_repository_evidence/notary-log.json" \
  NOTARIZATION_METADATA="$inside_repository_evidence/notarization-metadata.json"

expect_notarization_failure() {
  local case_name="$1"
  shift
  local case_app="$temporary_dir/$case_name/estrobo.app"
  local case_evidence_dir="$temporary_dir/evidence-$case_name"
  local case_state_dir="$temporary_dir/state-$case_name"
  /bin/mkdir -p "$case_app/Contents/MacOS" "$case_state_dir"
  /usr/bin/touch "$case_app/Contents/MacOS/estrobo"
  /bin/chmod 755 "$case_app/Contents/MacOS/estrobo"

  if /usr/bin/env \
    FAKE_STATE_DIR="$case_state_dir" \
    XCRUN_COMMAND="$fake_xcrun" \
    APP_BUNDLE="$case_app" \
    DEVELOPER_ID_TEAM_ID=ABCDE12345 \
    NOTARY_API_KEY_PATH="$api_key" \
    NOTARY_API_KEY_ID=TESTKEY123 \
    NOTARY_API_ISSUER_ID=aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee \
    NOTARIZATION_UPLOAD_ARCHIVE="$case_evidence_dir/notary-upload.zip" \
    NOTARIZATION_SUBMIT_RESULT="$case_evidence_dir/notary-submit.json" \
    NOTARIZATION_WAIT_RESULT="$case_evidence_dir/notary-wait.json" \
    NOTARIZATION_LOG="$case_evidence_dir/notary-log.json" \
    NOTARIZATION_METADATA="$case_evidence_dir/notarization-metadata.json" \
    "$@" \
      "$script_dir/notarize-macos-developer-id.sh" >/dev/null 2>&1; then
    fail "unsafe notarization case '$case_name' was accepted"
  fi
  [[ ! -e "$case_app/Contents/.synthetic-stapled-ticket" ]] || \
    fail "unsafe notarization case '$case_name' was stapled"
  [[ ! -e "$case_evidence_dir/notarization-metadata.json" ]] || \
    fail "unsafe notarization case '$case_name' produced accepted metadata"
  [[ -f "$case_evidence_dir/notary-upload.zip" ]] || \
    fail "unsafe notarization case '$case_name' lost its exact upload archive"
  [[ -f "$case_state_dir/submit.count" ]] || \
    fail "unsafe notarization case '$case_name' did not attempt one submission"
  [[ "$(<"$case_state_dir/submit.count")" == 1 ]] || \
    fail "unsafe notarization case '$case_name' submitted more than once"
}

expect_notarization_failure invalid-status \
  FAKE_NOTARY_STATUS=Invalid
expect_notarization_failure submit-failure \
  FAKE_SUBMIT_EXIT_CODE=69
expect_notarization_failure mismatched-wait-id \
  FAKE_WAIT_ID_OVERRIDE=01234567-89ab-cdef-0123-456789abcdef
expect_notarization_failure mismatched-log-id \
  FAKE_LOG_ID_OVERRIDE=01234567-89ab-cdef-0123-456789abcdef
expect_notarization_failure mismatched-upload-digest \
  FAKE_LOG_DIGEST_OVERRIDE=0000000000000000000000000000000000000000000000000000000000000000
expect_notarization_failure accepted-with-issues \
  'FAKE_NOTARY_ISSUES_JSON=[{"severity":"warning","message":"Synthetic warning"}]'

resume_app="$temporary_dir/resume-timeout/estrobo.app"
resume_evidence_dir="$temporary_dir/evidence-resume-timeout"
resume_state_dir="$temporary_dir/state-resume-timeout"
/bin/mkdir -p "$resume_app/Contents/MacOS" "$resume_state_dir"
/usr/bin/touch "$resume_app/Contents/MacOS/estrobo"
/bin/chmod 755 "$resume_app/Contents/MacOS/estrobo"
if FAKE_STATE_DIR="$resume_state_dir" \
  FAKE_WAIT_EXIT_CODE=124 \
  XCRUN_COMMAND="$fake_xcrun" \
  APP_BUNDLE="$resume_app" \
  DEVELOPER_ID_TEAM_ID=ABCDE12345 \
  NOTARY_KEYCHAIN_PROFILE=synthetic-notary-profile \
  NOTARIZATION_UPLOAD_ARCHIVE="$resume_evidence_dir/notary-upload.zip" \
  NOTARIZATION_SUBMIT_RESULT="$resume_evidence_dir/notary-submit.json" \
  NOTARIZATION_WAIT_RESULT="$resume_evidence_dir/notary-wait.json" \
  NOTARIZATION_LOG="$resume_evidence_dir/notary-log.json" \
  NOTARIZATION_METADATA="$resume_evidence_dir/notarization-metadata.json" \
    "$script_dir/notarize-macos-developer-id.sh" >/dev/null 2>&1; then
  fail "notarization wait timeout was accepted"
fi
[[ -f "$resume_evidence_dir/notary-upload.zip" ]] || \
  fail "notarization wait timeout lost the exact upload archive"
[[ -f "$resume_evidence_dir/notary-upload.zip.sha256" ]] || \
  fail "notarization wait timeout lost the upload checksum"
[[ "$(<"$resume_state_dir/submit.count")" == 1 ]] || \
  fail "notarization timeout submitted more than once"
resume_submission_id="$(/usr/bin/plutil -extract id raw -o - "$resume_evidence_dir/notary-submit.json")"

/bin/cp "$resume_evidence_dir/notary-upload.zip" "$temporary_dir/resume-upload-original.zip"
print -n -r -- tampered >>"$resume_evidence_dir/notary-upload.zip"
if FAKE_STATE_DIR="$resume_state_dir" \
  XCRUN_COMMAND="$fake_xcrun" \
  APP_BUNDLE="$resume_app" \
  DEVELOPER_ID_TEAM_ID=ABCDE12345 \
  NOTARY_KEYCHAIN_PROFILE=synthetic-notary-profile \
  NOTARY_SUBMISSION_ID="$resume_submission_id" \
  NOTARIZATION_UPLOAD_ARCHIVE="$resume_evidence_dir/notary-upload.zip" \
  NOTARIZATION_SUBMIT_RESULT="$resume_evidence_dir/notary-submit.json" \
  NOTARIZATION_WAIT_RESULT="$resume_evidence_dir/notary-wait.json" \
  NOTARIZATION_LOG="$resume_evidence_dir/notary-log.json" \
  NOTARIZATION_METADATA="$resume_evidence_dir/notarization-metadata.json" \
    "$script_dir/notarize-macos-developer-id.sh" >/dev/null 2>&1; then
  fail "resume accepted a notarization upload whose bytes no longer matched its checksum"
fi
[[ ! -e "$resume_evidence_dir/notary-wait.json.previous" ]] || \
  fail "tampered-upload resume archived evidence before validating the upload checksum"
[[ "$(<"$resume_state_dir/submit.count")" == 1 ]] || \
  fail "tampered-upload resume performed another submit"
/bin/mv "$temporary_dir/resume-upload-original.zip" "$resume_evidence_dir/notary-upload.zip"
/bin/chmod 600 "$resume_evidence_dir/notary-upload.zip"

if FAKE_STATE_DIR="$resume_state_dir" \
  XCRUN_COMMAND="$fake_xcrun" \
  APP_BUNDLE="$resume_app" \
  DEVELOPER_ID_TEAM_ID=ABCDE12345 \
  NOTARY_KEYCHAIN_PROFILE=synthetic-notary-profile \
  NOTARIZATION_UPLOAD_ARCHIVE="$resume_evidence_dir/notary-upload.zip" \
  NOTARIZATION_SUBMIT_RESULT="$resume_evidence_dir/notary-submit.json" \
  NOTARIZATION_WAIT_RESULT="$resume_evidence_dir/notary-wait.json" \
  NOTARIZATION_LOG="$resume_evidence_dir/notary-log.json" \
  NOTARIZATION_METADATA="$resume_evidence_dir/notarization-metadata.json" \
    "$script_dir/notarize-macos-developer-id.sh" >/dev/null 2>&1; then
  fail "fresh retry after timeout reused an existing evidence directory"
fi
[[ "$(<"$resume_state_dir/submit.count")" == 1 ]] || \
  fail "fresh retry after timeout performed a duplicate submit"

/bin/chmod 755 "$resume_evidence_dir"

if FAKE_STATE_DIR="$resume_state_dir" \
  XCRUN_COMMAND="$fake_xcrun" \
  APP_BUNDLE="$resume_app" \
  DEVELOPER_ID_TEAM_ID=ABCDE12345 \
  NOTARY_KEYCHAIN_PROFILE=synthetic-notary-profile \
  NOTARY_SUBMISSION_ID=01234567-89ab-cdef-0123-456789abcdef \
  NOTARIZATION_UPLOAD_ARCHIVE="$resume_evidence_dir/notary-upload.zip" \
  NOTARIZATION_SUBMIT_RESULT="$resume_evidence_dir/notary-submit.json" \
  NOTARIZATION_WAIT_RESULT="$resume_evidence_dir/notary-wait.json" \
  NOTARIZATION_LOG="$resume_evidence_dir/notary-log.json" \
  NOTARIZATION_METADATA="$resume_evidence_dir/notarization-metadata.json" \
    "$script_dir/notarize-macos-developer-id.sh" >/dev/null 2>&1; then
  fail "resume accepted a submission ID that did not match preserved evidence"
fi
[[ -e "$resume_evidence_dir/notary-wait.json" && -e "$resume_evidence_dir/notary-log.json" ]] || \
  fail "mismatched resume modified preserved evidence"
[[ ! -e "$resume_evidence_dir/notary-wait.json.previous" ]] || \
  fail "mismatched resume archived evidence before validating its submission ID"
[[ "$(/usr/bin/stat -f '%Lp' "$resume_evidence_dir")" == 755 ]] || \
  fail "mismatched resume mutated evidence directory permissions"
[[ "$(<"$resume_state_dir/submit.count")" == 1 ]] || \
  fail "mismatched resume performed another submit"

if FAKE_STATE_DIR="$resume_state_dir" \
  XCRUN_COMMAND="$fake_xcrun" \
  APP_BUNDLE="$resume_app" \
  DEVELOPER_ID_TEAM_ID=ABCDE12345 \
  NOTARY_KEYCHAIN_PROFILE=synthetic-notary-profile \
  NOTARY_SUBMISSION_ID="$resume_submission_id" \
  NOTARIZATION_UPLOAD_ARCHIVE="$resume_evidence_dir/notary-upload.zip" \
  NOTARIZATION_SUBMIT_RESULT="$resume_evidence_dir/notary-submit.json" \
  NOTARIZATION_WAIT_RESULT="$resume_evidence_dir/notary-wait.json" \
  NOTARIZATION_LOG="$resume_evidence_dir/notary-log.json" \
  NOTARIZATION_METADATA="$resume_evidence_dir/notarization-metadata.json" \
    "$script_dir/notarize-macos-developer-id.sh" >/dev/null 2>&1; then
  fail "resume accepted an evidence directory that was not mode 0700"
fi
[[ ! -e "$resume_evidence_dir/notary-wait.json.previous" ]] || \
  fail "unsafe-mode resume archived evidence"
/bin/chmod 700 "$resume_evidence_dir"

/bin/mkdir "$resume_evidence_dir/.notarization-operation.lock"
if FAKE_STATE_DIR="$resume_state_dir" \
  XCRUN_COMMAND="$fake_xcrun" \
  APP_BUNDLE="$resume_app" \
  DEVELOPER_ID_TEAM_ID=ABCDE12345 \
  NOTARY_KEYCHAIN_PROFILE=synthetic-notary-profile \
  NOTARY_SUBMISSION_ID="$resume_submission_id" \
  NOTARIZATION_UPLOAD_ARCHIVE="$resume_evidence_dir/notary-upload.zip" \
  NOTARIZATION_SUBMIT_RESULT="$resume_evidence_dir/notary-submit.json" \
  NOTARIZATION_WAIT_RESULT="$resume_evidence_dir/notary-wait.json" \
  NOTARIZATION_LOG="$resume_evidence_dir/notary-log.json" \
  NOTARIZATION_METADATA="$resume_evidence_dir/notarization-metadata.json" \
    "$script_dir/notarize-macos-developer-id.sh" >/dev/null 2>&1; then
  fail "resume ignored an active or stale operation lock"
fi
[[ ! -e "$resume_evidence_dir/notary-wait.json.previous" ]] || \
  fail "locked resume archived evidence"
/bin/rmdir "$resume_evidence_dir/.notarization-operation.lock"

FAKE_STATE_DIR="$resume_state_dir" \
FAKE_WAIT_UPPERCASE_ID=1 \
FAKE_LOG_UPPERCASE_ID=1 \
XCRUN_COMMAND="$fake_xcrun" \
APP_BUNDLE="$resume_app" \
DEVELOPER_ID_TEAM_ID=ABCDE12345 \
NOTARY_KEYCHAIN_PROFILE=synthetic-notary-profile \
NOTARY_SUBMISSION_ID="$resume_submission_id" \
NOTARIZATION_UPLOAD_ARCHIVE="$resume_evidence_dir/notary-upload.zip" \
NOTARIZATION_SUBMIT_RESULT="$resume_evidence_dir/notary-submit.json" \
NOTARIZATION_WAIT_RESULT="$resume_evidence_dir/notary-wait.json" \
NOTARIZATION_LOG="$resume_evidence_dir/notary-log.json" \
NOTARIZATION_METADATA="$resume_evidence_dir/notarization-metadata.json" \
  "$script_dir/notarize-macos-developer-id.sh"

[[ "$(<"$resume_state_dir/submit.count")" == 1 ]] || \
  fail "resuming a timed-out submission performed a second submit"
[[ -f "$resume_app/Contents/.synthetic-stapled-ticket" ]] || \
  fail "resumed notarization did not staple the recovered app"
[[ -f "$resume_evidence_dir/notarization-metadata.json" ]] || \
  fail "resumed notarization did not produce accepted metadata"
[[ ! -e "$resume_evidence_dir/notary-upload.zip" ]] || \
  fail "resumed notarization retained its temporary upload archive"
[[ -f "$resume_evidence_dir/notary-wait.json.previous" ]] || \
  fail "resumed notarization did not preserve the previous wait result"
[[ -f "$resume_evidence_dir/notary-log.json.previous" ]] || \
  fail "resumed notarization did not preserve the previous log"

api_resume_app="$temporary_dir/api-resume-timeout/estrobo.app"
api_resume_evidence_dir="$temporary_dir/evidence-api-resume-timeout"
api_resume_state_dir="$temporary_dir/state-api-resume-timeout"
/bin/mkdir -p "$api_resume_app/Contents/MacOS" "$api_resume_state_dir"
/usr/bin/touch "$api_resume_app/Contents/MacOS/estrobo"
/bin/chmod 755 "$api_resume_app/Contents/MacOS/estrobo"
if FAKE_STATE_DIR="$api_resume_state_dir" \
  FAKE_WAIT_EXIT_CODE=124 \
  XCRUN_COMMAND="$fake_xcrun" \
  APP_BUNDLE="$api_resume_app" \
  DEVELOPER_ID_TEAM_ID=ABCDE12345 \
  NOTARY_API_KEY_PATH="$api_key" \
  NOTARY_API_KEY_ID=TESTKEY123 \
  NOTARY_API_ISSUER_ID=aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee \
  NOTARIZATION_UPLOAD_ARCHIVE="$api_resume_evidence_dir/notary-upload.zip" \
  NOTARIZATION_SUBMIT_RESULT="$api_resume_evidence_dir/notary-submit.json" \
  NOTARIZATION_WAIT_RESULT="$api_resume_evidence_dir/notary-wait.json" \
  NOTARIZATION_LOG="$api_resume_evidence_dir/notary-log.json" \
  NOTARIZATION_METADATA="$api_resume_evidence_dir/notarization-metadata.json" \
    "$script_dir/notarize-macos-developer-id.sh" >/dev/null 2>&1; then
  fail "API-key notarization wait timeout was accepted"
fi
api_resume_submission_id="$(/usr/bin/plutil -extract id raw -o - "$api_resume_evidence_dir/notary-submit.json")"
FAKE_STATE_DIR="$api_resume_state_dir" \
XCRUN_COMMAND="$fake_xcrun" \
APP_BUNDLE="$api_resume_app" \
DEVELOPER_ID_TEAM_ID=ABCDE12345 \
NOTARY_API_KEY_PATH="$api_key" \
NOTARY_API_KEY_ID=TESTKEY123 \
NOTARY_API_ISSUER_ID=aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee \
NOTARY_SUBMISSION_ID="$api_resume_submission_id" \
NOTARIZATION_UPLOAD_ARCHIVE="$api_resume_evidence_dir/notary-upload.zip" \
NOTARIZATION_SUBMIT_RESULT="$api_resume_evidence_dir/notary-submit.json" \
NOTARIZATION_WAIT_RESULT="$api_resume_evidence_dir/notary-wait.json" \
NOTARIZATION_LOG="$api_resume_evidence_dir/notary-log.json" \
NOTARIZATION_METADATA="$api_resume_evidence_dir/notarization-metadata.json" \
  "$script_dir/notarize-macos-developer-id.sh"
[[ "$(<"$api_resume_state_dir/submit.count")" == 1 ]] || \
  fail "API-key resume performed a second submit"
[[ -f "$api_resume_evidence_dir/notarization-metadata.json" ]] || \
  fail "API-key resume did not produce accepted metadata"

fake_verify_calls="$temporary_dir/fake-verify-calls"
fake_verifier="$temporary_dir/fake-release-verifier"
cat >"$fake_verifier" <<'FAKE_VERIFIER'
#!/bin/zsh
set -euo pipefail
[[ -d "$APP_BUNDLE" ]]
print -r -- "$APP_BUNDLE" >>"$FAKE_VERIFY_CALLS"
FAKE_VERIFIER
/bin/chmod 755 "$fake_verifier"

fake_certificate="$temporary_dir/developer-id.cer"
fake_certificate_digest="$temporary_dir/developer-id.sha256"
print -n -r -- 'synthetic public certificate bytes' >"$fake_certificate"
/usr/bin/shasum -a 256 "$fake_certificate" >"$fake_certificate_digest"

dist_dir="$temporary_dir/DistDeveloperID"
FAKE_VERIFY_CALLS="$fake_verify_calls" \
APP_BUNDLE="$app_bundle" \
DIST_DIR="$dist_dir" \
VERSION=0.1.0 \
BUILD_NUMBER=3 \
CANDIDATE_TAG=v0.1.0-beta.3 \
COMMIT=0123456789abcdef0123456789abcdef01234567 \
MACOSX_DEPLOYMENT_TARGET=13.0 \
BUNDLE_IDENTIFIER=mx.loo.estrobo \
DEVELOPER_ID_TEAM_ID=ABCDE12345 \
DEVELOPER_ID_CERTIFICATE="$fake_certificate" \
DEVELOPER_ID_CERTIFICATE_SHA256="$fake_certificate_digest" \
NOTARIZATION_SUBMIT_RESULT="$evidence_dir/notary-submit.json" \
NOTARIZATION_WAIT_RESULT="$evidence_dir/notary-wait.json" \
NOTARIZATION_LOG="$evidence_dir/notary-log.json" \
NOTARIZATION_METADATA="$evidence_dir/notarization-metadata.json" \
VERIFY_SCRIPT="$fake_verifier" \
  "$script_dir/package-macos-developer-id-candidate.sh"

[[ "$(/usr/bin/wc -l <"$fake_verify_calls" | /usr/bin/tr -d ' ')" == 2 ]] || \
  fail "candidate verifier did not run before and after packaging"
manifest="$(/usr/bin/find "$dist_dir" -name '*-manifest.json' -type f -print -quit)"
checksums="$(/usr/bin/find "$dist_dir" -name '*-SHA256SUMS' -type f -print -quit)"
[[ -n "$manifest" && -n "$checksums" ]] || fail "candidate outputs are incomplete"
[[ "$(/usr/bin/plutil -extract schemaVersion raw -o - "$manifest")" == 2 ]] || fail "candidate manifest schema is not v2"
[[ "$(/usr/bin/plutil -extract releaseKind raw -o - "$manifest")" == developer-id-candidate ]] || \
  fail "candidate manifest does not identify its non-release status"
[[ "$(/usr/bin/plutil -extract notarization.status raw -o - "$manifest")" == Accepted ]] || \
  fail "candidate manifest does not record Accepted notarization"
(
  cd "$dist_dir"
  /usr/bin/shasum -a 256 -c "${checksums:t}"
)
[[ -d "$dist_dir/notarization-evidence" ]] || \
  fail "candidate package omitted notarization evidence"
[[ "$(/usr/bin/wc -l <"$checksums" | /usr/bin/tr -d ' ')" == 6 ]] || \
  fail "candidate checksums do not cover all notarization evidence"

mismatched_tag_dist="$temporary_dir/DistMismatchedTag"
if FAKE_VERIFY_CALLS="$fake_verify_calls" \
  APP_BUNDLE="$app_bundle" \
  DIST_DIR="$mismatched_tag_dist" \
  VERSION=0.1.0 \
  BUILD_NUMBER=3 \
  CANDIDATE_TAG=v0.1.0-beta.4 \
  COMMIT=0123456789abcdef0123456789abcdef01234567 \
  MACOSX_DEPLOYMENT_TARGET=13.0 \
  BUNDLE_IDENTIFIER=mx.loo.estrobo \
  DEVELOPER_ID_TEAM_ID=ABCDE12345 \
  DEVELOPER_ID_CERTIFICATE="$fake_certificate" \
  DEVELOPER_ID_CERTIFICATE_SHA256="$fake_certificate_digest" \
  NOTARIZATION_SUBMIT_RESULT="$evidence_dir/notary-submit.json" \
  NOTARIZATION_WAIT_RESULT="$evidence_dir/notary-wait.json" \
  NOTARIZATION_LOG="$evidence_dir/notary-log.json" \
  NOTARIZATION_METADATA="$evidence_dir/notarization-metadata.json" \
  VERIFY_SCRIPT="$fake_verifier" \
    "$script_dir/package-macos-developer-id-candidate.sh" >/dev/null 2>&1; then
  fail "candidate packager accepted a tag inconsistent with version/build"
fi
[[ "$(/usr/bin/wc -l <"$fake_verify_calls" | /usr/bin/tr -d ' ')" == 2 ]] || \
  fail "tag mismatch reached the candidate verifier"

print -r -- 'tampered evidence' >>"$dist_dir/notarization-evidence/notary-wait.json"
if (
  cd "$dist_dir"
  /usr/bin/shasum -a 256 -c "${checksums:t}" >/dev/null 2>&1
); then
  fail "candidate checksums did not detect tampered notarization evidence"
fi

if "$script_dir/verify-developer-id-certificate.sh" \
  "$repository_root/release/signing/estrobo-beta-signing.cer" \
  "$repository_root/release/signing/estrobo-beta-signing.sha256" \
  ABCDE12345 >/dev/null 2>&1; then
  fail "the legacy self-signed certificate passed Developer ID validation"
fi

print "Developer ID release tooling tests passed"
