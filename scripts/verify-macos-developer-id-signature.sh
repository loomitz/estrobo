#!/bin/zsh

set -euo pipefail

fail() {
  print -u2 "Developer ID signature verification failed: $*"
  exit 1
}

require_value() {
  local name="$1"
  [[ -n "${(P)name:-}" ]] || fail "missing environment variable ${name}"
}

for required_name in \
  APP_BUNDLE \
  VERSION \
  BUILD_NUMBER \
  BUNDLE_IDENTIFIER \
  MACOSX_DEPLOYMENT_TARGET \
  DEVELOPER_ID_TEAM_ID \
  DEVELOPER_ID_CERTIFICATE \
  DEVELOPER_ID_CERTIFICATE_SHA256; do
  require_value "$required_name"
done

[[ "$DEVELOPER_ID_TEAM_ID" =~ '^[A-Z0-9]{10}$' ]] || \
  fail "DEVELOPER_ID_TEAM_ID must contain exactly 10 uppercase letters or digits"
[[ -d "$APP_BUNDLE" ]] || fail "app bundle not found: $APP_BUNDLE"
[[ -r "$DEVELOPER_ID_CERTIFICATE" ]] || \
  fail "Developer ID certificate not found: $DEVELOPER_ID_CERTIFICATE"
[[ -r "$DEVELOPER_ID_CERTIFICATE_SHA256" ]] || \
  fail "Developer ID certificate fingerprint not found: $DEVELOPER_ID_CERTIFICATE_SHA256"

binary="$APP_BUNDLE/Contents/MacOS/estrobo"
plist="$APP_BUNDLE/Contents/Info.plist"
[[ -x "$binary" ]] || fail "main executable not found: $binary"
[[ -r "$plist" ]] || fail "Info.plist not found: $plist"

temporary_dir="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/estrobo-developer-id-signature.XXXXXX")"
trap '/bin/rm -rf -- "$temporary_dir"' EXIT

plist_value() {
  /usr/bin/plutil -extract "$1" raw -o - "$plist"
}

expect_plist_value() {
  local key="$1"
  local expected="$2"
  local actual
  actual="$(plist_value "$key")" || fail "missing plist key $key"
  [[ "$actual" == "$expected" ]] || fail "$key is '$actual', expected '$expected'"
}

/usr/bin/plutil -lint "$plist" >/dev/null
expect_plist_value CFBundleIdentifier "$BUNDLE_IDENTIFIER"
expect_plist_value CFBundleDisplayName estrobo
expect_plist_value CFBundleShortVersionString "$VERSION"
expect_plist_value CFBundleVersion "$BUILD_NUMBER"
expect_plist_value LSMinimumSystemVersion "$MACOSX_DEPLOYMENT_TARGET"
"${0:A:h}/verify-macos-bundle-contents.sh" "$APP_BUNDLE"

/usr/bin/lipo "$binary" -verify_arch arm64 x86_64
for arch in arm64 x86_64; do
  minos="$(/usr/bin/xcrun vtool -show-build -arch "$arch" "$binary" | /usr/bin/awk '$1 == "minos" { print $2; exit }')"
  [[ -n "$minos" ]] || fail "could not read the minimum macOS version for $arch"
  [[ "$minos" == "$MACOSX_DEPLOYMENT_TARGET" ]] || \
    fail "$arch slice has minimum macOS $minos, expected $MACOSX_DEPLOYMENT_TARGET"
done

/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
signature_details="$(/usr/bin/codesign -dvvv "$APP_BUNDLE" 2>&1)"
print -r -- "$signature_details"
print -r -- "$signature_details" | /usr/bin/grep -Eq 'flags=.*\(.*runtime.*\)' || \
  fail "Hardened Runtime is not active"
print -r -- "$signature_details" | /usr/bin/grep -Fq 'Signature=adhoc' && \
  fail "the release bundle is signed ad hoc"
print -r -- "$signature_details" | /usr/bin/grep -Eq '^Authority=Developer ID Application:' || \
  fail "leaf signing authority is not Developer ID Application"
print -r -- "$signature_details" | /usr/bin/grep -Fqx "TeamIdentifier=$DEVELOPER_ID_TEAM_ID" || \
  fail "TeamIdentifier does not match DEVELOPER_ID_TEAM_ID"
print -r -- "$signature_details" | /usr/bin/grep -Fqx "Identifier=$BUNDLE_IDENTIFIER" || \
  fail "signature identifier does not match the bundle identifier"
print -r -- "$signature_details" | /usr/bin/grep -Eq '^Timestamp=' || \
  fail "a secure Apple timestamp is missing"

entitlements_plist="$temporary_dir/entitlements.plist"
/usr/bin/codesign -d \
  --entitlements "$entitlements_plist" \
  --xml \
  "$APP_BUNDLE" 2>"$temporary_dir/entitlements.log"
/usr/bin/plutil -lint "$entitlements_plist" >/dev/null

entitlement_value() {
  /usr/libexec/PlistBuddy -c "Print :$1" "$entitlements_plist" 2>/dev/null
}

[[ "$(entitlement_value com.apple.security.app-sandbox)" == true ]] || \
  fail "App Sandbox entitlement is missing"
[[ "$(entitlement_value com.apple.security.device.bluetooth)" == true ]] || \
  fail "Bluetooth entitlement is missing"

actual_entitlement_keys="$(
  /usr/bin/plutil -convert xml1 -o - "$entitlements_plist" |
    /usr/bin/sed -n 's/.*<key>\([^<]*\)<\/key>.*/\1/p' |
    /usr/bin/sort
)"
expected_entitlement_keys=$'com.apple.security.app-sandbox\ncom.apple.security.device.bluetooth'
[[ "$actual_entitlement_keys" == "$expected_entitlement_keys" ]] || {
  print -u2 "Unexpected Developer ID entitlements:"
  print -u2 -r -- "$actual_entitlement_keys"
  fail "effective entitlements must match the App Sandbox + Bluetooth allowlist"
}

"${0:A:h}/verify-developer-id-certificate.sh" \
  "$DEVELOPER_ID_CERTIFICATE" \
  "$DEVELOPER_ID_CERTIFICATE_SHA256" \
  "$DEVELOPER_ID_TEAM_ID"

certificate_prefix="$temporary_dir/signing-certificate"
/usr/bin/codesign -d --extract-certificates="$certificate_prefix" "$APP_BUNDLE" >/dev/null 2>&1 || \
  fail "could not extract the signing certificate"
[[ -r "${certificate_prefix}0" ]] || fail "the signature does not contain a leaf certificate"
expected_certificate_digest="$(/usr/bin/awk 'NF { print toupper($1); exit }' "$DEVELOPER_ID_CERTIFICATE_SHA256")"
signed_certificate_digest="$(/usr/bin/shasum -a 256 "${certificate_prefix}0" | /usr/bin/awk '{ print toupper($1) }')"
[[ "$signed_certificate_digest" == "$expected_certificate_digest" ]] || \
  fail "the embedded signing certificate does not match the pinned Developer ID certificate"
/usr/bin/cmp -s "$DEVELOPER_ID_CERTIFICATE" "${certificate_prefix}0" || \
  fail "the embedded Developer ID certificate bytes differ from the pinned certificate"

print "Developer ID signature verification passed: $APP_BUNDLE"
