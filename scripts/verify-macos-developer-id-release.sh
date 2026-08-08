#!/bin/zsh

set -euo pipefail

fail() {
  print -u2 "notarized Developer ID release verification failed: $*"
  exit 1
}

require_value() {
  local name="$1"
  [[ -n "${(P)name:-}" ]] || fail "missing environment variable ${name}"
}

require_value APP_BUNDLE

signature_verifier="${DEVELOPER_ID_SIGNATURE_VERIFY_SCRIPT:-${0:A:h}/verify-macos-developer-id-signature.sh}"
[[ -x "$signature_verifier" ]] || fail "signature verifier is not executable: $signature_verifier"

"$signature_verifier"

temporary_dir="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/estrobo-developer-id-release.XXXXXX")"
trap '/bin/rm -rf -- "$temporary_dir"' EXIT

stapler_log="$temporary_dir/stapler.log"
if ! /usr/bin/xcrun stapler validate -v "$APP_BUNDLE" >"$stapler_log" 2>&1; then
  /bin/cat "$stapler_log"
  fail "the app does not contain a valid stapled notarization ticket"
fi
/bin/cat "$stapler_log"

spctl_log="$temporary_dir/spctl.log"
if ! /usr/sbin/spctl --assess --type execute --verbose=4 "$APP_BUNDLE" >"$spctl_log" 2>&1; then
  /bin/cat "$spctl_log"
  fail "Gatekeeper rejected the Developer ID candidate"
fi
/bin/cat "$spctl_log"
/usr/bin/grep -Eiq '(^|:|[[:space:]])accepted([[:space:]]|$)' "$spctl_log" || \
  fail "spctl exited successfully without reporting acceptance"
/usr/bin/grep -Fq 'source=Notarized Developer ID' "$spctl_log" || \
  fail "Gatekeeper did not identify the source as Notarized Developer ID"

print "Notarized Developer ID release verification passed: $APP_BUNDLE"
