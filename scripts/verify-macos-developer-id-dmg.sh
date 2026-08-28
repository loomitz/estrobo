#!/bin/zsh

set -euo pipefail
umask 077

fail() {
  print -u2 "Developer ID DMG verification failed: $*"
  exit 1
}

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
  APP_VERIFY_SCRIPT; do
  require_value "$required_name"
done

dmg_identifier="${DMG_IDENTIFIER:-mx.loo.estrobo.dmg}"
dmg_volume_name="${DMG_VOLUME_NAME:-Estrobo}"
repository_url="${REPOSITORY_URL:-https://github.com/loomitz/estrobo}"
hdiutil_command="${HDIUTIL_COMMAND:-/usr/bin/hdiutil}"
codesign_command="${CODESIGN_COMMAND:-/usr/bin/codesign}"
spctl_command="${SPCTL_COMMAND:-/usr/sbin/spctl}"
diskutil_command="${DISKUTIL_COMMAND:-/usr/sbin/diskutil}"
xcrun_command="${XCRUN_COMMAND:-/usr/bin/xcrun}"

for command_path in \
  "$hdiutil_command" \
  "$codesign_command" \
  "$spctl_command" \
  "$diskutil_command" \
  "$xcrun_command" \
  "$APP_VERIFY_SCRIPT"; do
  [[ -x "$command_path" ]] || fail "required command is not executable: $command_path"
done

DMG="${DMG:A}"
MANIFEST="${MANIFEST:A}"
CHECKSUMS="${CHECKSUMS:A}"
DEVELOPER_ID_CERTIFICATE="${DEVELOPER_ID_CERTIFICATE:A}"
DEVELOPER_ID_CERTIFICATE_SHA256="${DEVELOPER_ID_CERTIFICATE_SHA256:A}"

[[ -f "$DMG" && -r "$DMG" ]] || fail "DMG not found: $DMG"
[[ -f "$MANIFEST" && -r "$MANIFEST" ]] || fail "manifest not found: $MANIFEST"
[[ -f "$CHECKSUMS" && -r "$CHECKSUMS" ]] || fail "checksums not found: $CHECKSUMS"
[[ -r "$DEVELOPER_ID_CERTIFICATE" ]] || fail "Developer ID certificate not found"
[[ -r "$DEVELOPER_ID_CERTIFICATE_SHA256" ]] || fail "Developer ID certificate digest not found"
[[ "${DMG:h}" == "${MANIFEST:h}" && "${DMG:h}" == "${CHECKSUMS:h}" ]] || \
  fail "DMG, manifest, and checksums must share one directory"
[[ "$TAG" =~ '^v[0-9]+\.[0-9]+\.[0-9]+-beta\.[0-9]+$' ]] || fail "invalid release tag: $TAG"
[[ "$TAG" == "v${VERSION}-beta.${BUILD_NUMBER}" ]] || \
  fail "tag '$TAG' does not match version/build 'v${VERSION}-beta.${BUILD_NUMBER}'"
[[ "$COMMIT" =~ '^[0-9a-f]{40}$' ]] || fail "COMMIT must be a full lowercase Git commit SHA"
[[ "$DEVELOPER_ID_TEAM_ID" =~ '^[A-Z0-9]{10}$' ]] || fail "invalid Developer ID Team ID"
[[ "$dmg_identifier" == mx.loo.estrobo.dmg ]] || fail "unexpected DMG signing identifier"
[[ "$dmg_volume_name" == Estrobo ]] || fail "unexpected DMG volume name"

dmg_name="${DMG:t}"
manifest_name="${MANIFEST:t}"
expected_dmg_name="estrobo-${TAG}-macos-universal.dmg"
expected_manifest_name="estrobo-${TAG}-manifest.json"
[[ "$dmg_name" == "$expected_dmg_name" ]] || fail "unexpected DMG filename: $dmg_name"
[[ "$manifest_name" == "$expected_manifest_name" ]] || fail "unexpected manifest filename: $manifest_name"
[[ "${CHECKSUMS:t}" == SHA256SUMS ]] || fail "checksums file must be named SHA256SUMS"

checksum_entries="$({
  /usr/bin/awk '
    NF {
      if (NF != 2 || $1 !~ /^[0-9A-Fa-f]{64}$/) exit 2
      print $2
    }
  ' "$CHECKSUMS"
} 2>/dev/null)" || fail "SHA256SUMS has an invalid entry"
expected_checksum_entries="$(print -rl -- "$dmg_name" "$manifest_name" | LC_ALL=C /usr/bin/sort)"
actual_checksum_entries="$(print -r -- "$checksum_entries" | LC_ALL=C /usr/bin/sort)"
[[ "$actual_checksum_entries" == "$expected_checksum_entries" ]] || \
  fail "SHA256SUMS must cover exactly the DMG and manifest"
(
  cd "${DMG:h}"
  /usr/bin/shasum -a 256 -c "${CHECKSUMS:t}"
)

manifest_value() {
  /usr/bin/plutil -extract "$1" raw -o - "$MANIFEST" 2>/dev/null
}

expect_manifest_value() {
  local key="$1"
  local expected="$2"
  local actual
  actual="$(manifest_value "$key")" || fail "manifest is missing $key"
  [[ "$actual" == "$expected" ]] || fail "manifest $key is '$actual', expected '$expected'"
}

manifest_json_value() {
  /usr/bin/plutil -extract "$1" json -o - "$MANIFEST" 2>/dev/null | /usr/bin/tr -d '[:space:]'
}

expect_manifest_value schemaVersion 3
expect_manifest_value releaseKind developer-id-notarized-dmg
expect_manifest_value product.name estrobo
expect_manifest_value product.bundleIdentifier "$BUNDLE_IDENTIFIER"
expect_manifest_value product.version "$VERSION"
expect_manifest_value product.build "$BUILD_NUMBER"
expect_manifest_value product.minimumMacOSVersion "$MACOSX_DEPLOYMENT_TARGET"
[[ "$(manifest_json_value product.architectures)" == '["arm64","x86_64"]' ]] || \
  fail "manifest architectures must be exactly arm64 and x86_64"
expect_manifest_value source.repository "$repository_url"
expect_manifest_value source.tag "$TAG"
expect_manifest_value source.commit "$COMMIT"
expect_manifest_value source.provenance manual-exact-asset-promotion
expect_manifest_value artifact.filename "$dmg_name"
expect_manifest_value artifact.format UDIF-UDZO
expect_manifest_value artifact.contents.0 estrobo.app
expect_manifest_value artifact.contents.1 'Applications -> /Applications'
[[ "$(manifest_value artifact.contents 2>/dev/null)" == 2 ]] || \
  fail "manifest DMG contents are not the exact two-entry contract"
expect_manifest_value signing.type developer-id
expect_manifest_value signing.teamIdentifier "$DEVELOPER_ID_TEAM_ID"
expect_manifest_value signing.diskImageIdentifier "$dmg_identifier"
expect_manifest_value signing.hardenedRuntime true
expect_manifest_value signing.secureTimestamp true
expect_manifest_value notarization.application.status Accepted
expect_manifest_value notarization.application.ticketStapled true
expect_manifest_value notarization.diskImage.status Accepted
expect_manifest_value notarization.diskImage.ticketStapled true
expect_manifest_value verification.gatekeeperSource 'Notarized Developer ID'
expect_manifest_value verification.githubBuildProvenanceAttestation false

certificate_digest="$(/usr/bin/awk 'NF { print tolower($1); exit }' "$DEVELOPER_ID_CERTIFICATE_SHA256")"
[[ "$certificate_digest" =~ '^[0-9a-f]{64}$' ]] || fail "invalid pinned certificate digest"
expect_manifest_value signing.certificateSHA256 "$certificate_digest"

actual_dmg_digest="$(/usr/bin/shasum -a 256 "$DMG" | /usr/bin/awk '{ print tolower($1) }')"
actual_dmg_size="$(/usr/bin/stat -f '%z' "$DMG")"
expect_manifest_value artifact.sha256 "$actual_dmg_digest"
expect_manifest_value artifact.sizeBytes "$actual_dmg_size"
expect_manifest_value notarization.diskImage.finalSHA256 "$actual_dmg_digest"

app_submission_id="$(manifest_value notarization.application.submissionId)" || \
  fail "manifest is missing the application submission ID"
dmg_submission_id="$(manifest_value notarization.diskImage.submissionId)" || \
  fail "manifest is missing the disk image submission ID"
for submission_id in "$app_submission_id" "$dmg_submission_id"; do
  [[ "$submission_id" =~ '^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$' ]] || \
    fail "manifest contains an invalid notarization submission ID"
done
[[ "${app_submission_id:l}" != "${dmg_submission_id:l}" ]] || \
  fail "application and DMG must use distinct notarization submissions"
for digest_key in \
  notarization.application.uploadSHA256 \
  notarization.diskImage.uploadSHA256; do
  digest_value="$(manifest_value "$digest_key")" || fail "manifest is missing $digest_key"
  [[ "$digest_value" =~ '^[0-9a-f]{64}$' ]] || fail "manifest $digest_key is not a SHA-256 digest"
done
manifest_app_code_directory_hash="$(manifest_value notarization.application.codeDirectoryHash 2>/dev/null || true)"
if (( 10#$BUILD_NUMBER >= 4 )); then
  [[ "$manifest_app_code_directory_hash" =~ '^[0-9a-f]{40}$' ]] || \
    fail "manifest lacks the notarized app CodeDirectory hash"
elif [[ -n "$manifest_app_code_directory_hash" && \
        ! "$manifest_app_code_directory_hash" =~ '^[0-9a-f]{40}$' ]]; then
  fail "manifest app CodeDirectory hash is invalid"
fi

temporary_dir="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/estrobo-developer-id-dmg-verify.XXXXXX")"
mount_dir="$temporary_dir/mount"
/bin/mkdir "$mount_dir"
attached=false
cleanup() {
  if [[ "$attached" == true ]]; then
    "$hdiutil_command" detach "$mount_dir" >/dev/null 2>&1 || true
  fi
  /bin/rm -rf -- "$temporary_dir"
}
trap cleanup EXIT

"$hdiutil_command" verify "$DMG"
image_info="$temporary_dir/image-info.plist"
"$hdiutil_command" imageinfo -plist "$DMG" >"$image_info"
/usr/bin/plutil -lint "$image_info" >/dev/null || fail "hdiutil returned invalid image metadata"
[[ "$(/usr/bin/plutil -extract Format raw -o - "$image_info")" == UDZO ]] || fail "DMG format is not UDZO"
[[ "$(/usr/bin/plutil -extract Properties.Compressed raw -o - "$image_info")" == true ]] || \
  fail "DMG is not compressed"
[[ "$(/usr/bin/plutil -extract Properties.Encrypted raw -o - "$image_info")" == false ]] || \
  fail "public DMG must not be encrypted"

"$codesign_command" --verify --strict --verbose=4 "$DMG"
signature_details="$("$codesign_command" -dvvv "$DMG" 2>&1)"
print -r -- "$signature_details"
print -r -- "$signature_details" | /usr/bin/grep -Fqx 'Format=disk image' || fail "signed artifact is not a disk image"
print -r -- "$signature_details" | /usr/bin/grep -Fqx "Identifier=$dmg_identifier" || fail "DMG signing identifier mismatch"
print -r -- "$signature_details" | /usr/bin/grep -Eq '^Authority=Developer ID Application:' || \
  fail "DMG leaf authority is not Developer ID Application"
print -r -- "$signature_details" | /usr/bin/grep -Fqx "TeamIdentifier=$DEVELOPER_ID_TEAM_ID" || \
  fail "DMG TeamIdentifier mismatch"
print -r -- "$signature_details" | /usr/bin/grep -Eq '^Timestamp=' || fail "DMG secure timestamp is missing"

certificate_prefix="$temporary_dir/dmg-signing-certificate"
"$codesign_command" -d --extract-certificates="$certificate_prefix" "$DMG" >/dev/null 2>&1 || \
  fail "could not extract the DMG signing certificate"
[[ -r "${certificate_prefix}0" ]] || fail "DMG signature does not contain a leaf certificate"
signed_certificate_digest="$(/usr/bin/shasum -a 256 "${certificate_prefix}0" | /usr/bin/awk '{ print tolower($1) }')"
[[ "$signed_certificate_digest" == "$certificate_digest" ]] || fail "DMG signing certificate digest mismatch"
/usr/bin/cmp -s "$DEVELOPER_ID_CERTIFICATE" "${certificate_prefix}0" || \
  fail "DMG signing certificate bytes differ from the pinned certificate"

stapler_log="$temporary_dir/stapler.log"
if ! "$xcrun_command" stapler validate -v "$DMG" >"$stapler_log" 2>&1; then
  /bin/cat "$stapler_log"
  fail "DMG does not contain a valid stapled ticket"
fi
/bin/cat "$stapler_log"

spctl_log="$temporary_dir/spctl.log"
if ! "$spctl_command" --assess --type open --context context:primary-signature --verbose=4 "$DMG" \
  >"$spctl_log" 2>&1; then
  /bin/cat "$spctl_log"
  fail "Gatekeeper rejected the DMG"
fi
/bin/cat "$spctl_log"
/usr/bin/grep -Eiq '(^|:|[[:space:]])accepted([[:space:]]|$)' "$spctl_log" || \
  fail "Gatekeeper exited successfully without reporting acceptance"
/usr/bin/grep -Fq 'source=Notarized Developer ID' "$spctl_log" || \
  fail "Gatekeeper did not identify the DMG as Notarized Developer ID"

"$hdiutil_command" attach -readonly -nobrowse -noautoopen -mountpoint "$mount_dir" "$DMG" >/dev/null
attached=true
volume_info="$temporary_dir/volume-info.plist"
"$diskutil_command" info -plist "$mount_dir" >"$volume_info"
/usr/bin/plutil -lint "$volume_info" >/dev/null || fail "diskutil returned invalid volume metadata"
[[ "$(/usr/bin/plutil -extract FilesystemName raw -o - "$volume_info")" == 'HFS+' ]] || fail "DMG filesystem is not HFS+"
[[ "$(/usr/bin/plutil -extract VolumeName raw -o - "$volume_info")" == "$dmg_volume_name" ]] || \
  fail "DMG volume name mismatch"
[[ "$(/usr/bin/plutil -extract Writable raw -o - "$volume_info")" == false ]] || fail "DMG mounted writable"

root_entries="$(
  /usr/bin/find "$mount_dir" -mindepth 1 -maxdepth 1 -exec /usr/bin/basename {} \; | LC_ALL=C /usr/bin/sort
)"
[[ "$root_entries" == $'Applications\nestrobo.app' ]] || fail "DMG root does not contain exactly estrobo.app and Applications"
[[ -d "$mount_dir/estrobo.app" && ! -L "$mount_dir/estrobo.app" ]] || fail "estrobo.app is missing or is not a bundle directory"
[[ -L "$mount_dir/Applications" ]] || fail "Applications entry is not a symbolic link"
[[ "$(/usr/bin/readlink "$mount_dir/Applications")" == /Applications ]] || fail "Applications link has the wrong target"

APP_BUNDLE="$mount_dir/estrobo.app" \
VERSION="$VERSION" \
BUILD_NUMBER="$BUILD_NUMBER" \
SOURCE_COMMIT="$COMMIT" \
BUNDLE_IDENTIFIER="$BUNDLE_IDENTIFIER" \
MACOSX_DEPLOYMENT_TARGET="$MACOSX_DEPLOYMENT_TARGET" \
DEVELOPER_ID_TEAM_ID="$DEVELOPER_ID_TEAM_ID" \
DEVELOPER_ID_CERTIFICATE="$DEVELOPER_ID_CERTIFICATE" \
DEVELOPER_ID_CERTIFICATE_SHA256="$DEVELOPER_ID_CERTIFICATE_SHA256" \
  "$APP_VERIFY_SCRIPT"

if [[ -n "$manifest_app_code_directory_hash" ]]; then
  mounted_app_signature_details="$("$codesign_command" -dvvv "$mount_dir/estrobo.app" 2>&1)" || \
    fail "could not inspect the mounted app CodeDirectory"
  mounted_app_code_directory_hash="$(
    print -r -- "$mounted_app_signature_details" | \
      /usr/bin/awk -F= '$1 == "CDHash" { print tolower(substr($0, index($0, "=") + 1)); exit }'
  )"
  [[ "$mounted_app_code_directory_hash" == "$manifest_app_code_directory_hash" ]] || \
    fail "mounted app does not match its notarization CodeDirectory hash"
fi

"$hdiutil_command" detach "$mount_dir" >/dev/null
attached=false

print "Notarized Developer ID DMG verification passed: $DMG"
print "SHA-256: $actual_dmg_digest"
