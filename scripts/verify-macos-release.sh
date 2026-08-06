#!/bin/zsh

set -euo pipefail

fail() {
  print -u2 "release verification failed: $*"
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
  SIGNING_CERTIFICATE \
  SIGNING_CERTIFICATE_SHA256; do
  require_value "$required_name"
done

[[ -d "$APP_BUNDLE" ]] || fail "app bundle not found: $APP_BUNDLE"
[[ -r "$SIGNING_CERTIFICATE" ]] || fail "public signing certificate not found: $SIGNING_CERTIFICATE"
[[ -r "$SIGNING_CERTIFICATE_SHA256" ]] || fail "certificate fingerprint not found: $SIGNING_CERTIFICATE_SHA256"

binary="$APP_BUNDLE/Contents/MacOS/estrobo"
plist="$APP_BUNDLE/Contents/Info.plist"
[[ -x "$binary" ]] || fail "main executable not found: $binary"
[[ -r "$plist" ]] || fail "Info.plist not found: $plist"

temporary_dir="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/estrobo-release-verify.XXXXXX")"
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

# Integrity must pass before the expected Gatekeeper rejection is evaluated.
/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
signature_details="$(/usr/bin/codesign -dvv "$APP_BUNDLE" 2>&1)"
print -r -- "$signature_details"
print -r -- "$signature_details" | /usr/bin/grep -Eq 'flags=.*\(.*runtime.*\)' || \
  fail "Hardened Runtime is not active"
print -r -- "$signature_details" | /usr/bin/grep -Fq 'Signature=adhoc' && \
  fail "the release bundle is signed ad hoc"
print -r -- "$signature_details" | /usr/bin/grep -Fq 'Authority=Developer ID Application:' && \
  fail "the beta contract expects the independent self-signed identity, not Developer ID"

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
/usr/bin/grep -Fq '<key>com.apple.security.network.' "$entitlements_plist" && \
  fail "a network entitlement is present"

expected_certificate_digest="$(/usr/bin/awk 'NF { print $1; exit }' "$SIGNING_CERTIFICATE_SHA256" | /usr/bin/tr '[:lower:]' '[:upper:]')"
"${0:A:h}/verify-signing-certificate.sh" \
  "$SIGNING_CERTIFICATE" \
  "$SIGNING_CERTIFICATE_SHA256"

certificate_prefix="$temporary_dir/signing-certificate"
/usr/bin/codesign -d --extract-certificates="$certificate_prefix" "$APP_BUNDLE" >/dev/null 2>&1 || \
  fail "could not extract the signing certificate"
[[ -r "${certificate_prefix}0" ]] || fail "the signature does not contain a leaf certificate"
signed_certificate_digest="$(/usr/bin/shasum -a 256 "${certificate_prefix}0" | /usr/bin/awk '{ print toupper($1) }')"
[[ "$signed_certificate_digest" == "$expected_certificate_digest" ]] || \
  fail "the signing certificate does not match the versioned fingerprint"

spctl_log="$temporary_dir/spctl.log"
if /usr/sbin/spctl --assess --type execute --verbose=4 "$APP_BUNDLE" >"$spctl_log" 2>&1; then
  /bin/cat "$spctl_log"
  fail "Gatekeeper accepted a bundle without Developer ID"
fi
/usr/bin/grep -Eiq '(^|:|[[:space:]])rejected([[:space:]]|$)' "$spctl_log" || {
  /bin/cat "$spctl_log"
  fail "spctl failed without reporting an explicit Gatekeeper rejection"
}
print "Gatekeeper rejection expected and observed:"
/bin/cat "$spctl_log"

print "Release verification passed: $APP_BUNDLE"
