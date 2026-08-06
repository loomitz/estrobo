#!/bin/zsh

set -euo pipefail

fail() {
  print -u2 "release packaging failed: $*"
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
  TAG \
  COMMIT \
  MACOSX_DEPLOYMENT_TARGET \
  BUNDLE_IDENTIFIER \
  SIGNING_CERTIFICATE \
  SIGNING_CERTIFICATE_SHA256 \
  VERIFY_SCRIPT; do
  require_value "$required_name"
done

[[ -d "$APP_BUNDLE" ]] || fail "app bundle not found: $APP_BUNDLE"
[[ -x "$VERIFY_SCRIPT" ]] || fail "release verifier is not executable: $VERIFY_SCRIPT"
[[ "$TAG" =~ '^v[0-9]+\.[0-9]+\.[0-9]+-beta\.[0-9]+$' ]] || fail "invalid beta tag: $TAG"

/bin/mkdir -p "$DIST_DIR"
archive_name="estrobo-${TAG}-macos-universal.zip"
manifest_name="estrobo-${TAG}-manifest.json"
archive="$DIST_DIR/$archive_name"
manifest="$DIST_DIR/$manifest_name"
checksums="$DIST_DIR/SHA256SUMS"
certificate_digest="$(/usr/bin/awk 'NF { print tolower($1); exit }' "$SIGNING_CERTIFICATE_SHA256")"

/bin/rm -f -- "$archive" "$manifest" "$checksums"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$archive"
archive_digest="$(/usr/bin/shasum -a 256 "$archive" | /usr/bin/awk '{ print $1 }')"

/usr/bin/plutil -create xml1 "$manifest"
/usr/bin/plutil -insert schemaVersion -integer 1 "$manifest"
/usr/bin/plutil -insert application -string estrobo "$manifest"
/usr/bin/plutil -insert bundleIdentifier -string "$BUNDLE_IDENTIFIER" "$manifest"
/usr/bin/plutil -insert version -string "$VERSION" "$manifest"
/usr/bin/plutil -insert build -string "$BUILD_NUMBER" "$manifest"
/usr/bin/plutil -insert tag -string "$TAG" "$manifest"
/usr/bin/plutil -insert commit -string "$COMMIT" "$manifest"
/usr/bin/plutil -insert architectures -json '["arm64","x86_64"]' "$manifest"
/usr/bin/plutil -insert minimumMacOSVersion -string "$MACOSX_DEPLOYMENT_TARGET" "$manifest"
/usr/bin/plutil -insert signingCertificateSHA256 -string "$certificate_digest" "$manifest"
/usr/bin/plutil -insert artifact -string "$archive_name" "$manifest"
/usr/bin/plutil -insert sha256 -string "$archive_digest" "$manifest"
/usr/bin/plutil -convert json -r "$manifest"

(
  cd "$DIST_DIR"
  /usr/bin/shasum -a 256 \
    "$archive_name" \
    "$manifest_name" >SHA256SUMS
  /usr/bin/shasum -a 256 -c SHA256SUMS
)

temporary_dir="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/estrobo-release-package.XXXXXX")"
trap '/bin/rm -rf -- "$temporary_dir"' EXIT
/usr/bin/ditto -x -k "$archive" "$temporary_dir"
extracted_app="$temporary_dir/${APP_BUNDLE:t}"
[[ -d "$extracted_app" ]] || fail "the archive does not contain ${APP_BUNDLE:t} at its root"

APP_BUNDLE="$extracted_app" \
VERSION="$VERSION" \
BUILD_NUMBER="$BUILD_NUMBER" \
BUNDLE_IDENTIFIER="$BUNDLE_IDENTIFIER" \
MACOSX_DEPLOYMENT_TARGET="$MACOSX_DEPLOYMENT_TARGET" \
SIGNING_CERTIFICATE="$SIGNING_CERTIFICATE" \
SIGNING_CERTIFICATE_SHA256="$SIGNING_CERTIFICATE_SHA256" \
  "$VERIFY_SCRIPT"

print "Packaged: $archive"
print "SHA-256: $archive_digest"
print "Manifest: $manifest"
print "Checksums: $checksums"
