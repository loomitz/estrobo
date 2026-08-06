#!/bin/zsh

set -euo pipefail

fail() {
  print -u2 "signing certificate verification failed: $*"
  exit 1
}

[[ $# -eq 2 ]] || fail "usage: $0 CERTIFICATE_DER SHA256_FILE"
certificate="$1"
fingerprint_file="$2"
[[ -r "$certificate" ]] || fail "certificate not found: $certificate"
[[ -r "$fingerprint_file" ]] || fail "fingerprint not found: $fingerprint_file"

expected_digest="$(/usr/bin/awk 'NF { print $1; exit }' "$fingerprint_file" | /usr/bin/tr '[:lower:]' '[:upper:]')"
[[ "$expected_digest" =~ '^[0-9A-F]{64}$' ]] || fail "fingerprint is not a 64-character SHA-256 digest"
actual_digest="$(/usr/bin/shasum -a 256 "$certificate" | /usr/bin/awk '{ print toupper($1) }')"
[[ "$actual_digest" == "$expected_digest" ]] || fail "certificate bytes do not match the versioned fingerprint"

temporary_dir="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/estrobo-certificate-verify.XXXXXX")"
trap '/bin/rm -rf -- "$temporary_dir"' EXIT
certificate_text="$temporary_dir/certificate.txt"
/usr/bin/openssl x509 -inform DER -in "$certificate" -noout -text >"$certificate_text" || \
  fail "certificate must be a DER-encoded X.509 certificate"

certificate_subject="$(/usr/bin/openssl x509 -inform DER -in "$certificate" -noout -subject -nameopt RFC2253 | /usr/bin/sed 's/^subject=//')"
certificate_issuer="$(/usr/bin/openssl x509 -inform DER -in "$certificate" -noout -issuer -nameopt RFC2253 | /usr/bin/sed 's/^issuer=//')"
[[ "$certificate_subject" == "$certificate_issuer" ]] || fail "certificate is not self-signed"

extension_contains() {
  local extension_header="$1"
  local required_pattern="$2"
  /usr/bin/awk -v header="$extension_header" -v required="$required_pattern" '
    index($0, header) { inside = 1; next }
    inside && /X509v3 [^:]+:/ { inside = 0 }
    inside && $0 ~ required { found = 1 }
    END { exit(found ? 0 : 1) }
  ' "$certificate_text"
}

extension_contains \
  'X509v3 Extended Key Usage:' \
  '(Code Signing|1[.]3[.]6[.]1[.]5[.]5[.]7[.]3[.]3)' || \
  fail "Extended Key Usage does not include Code Signing"
extension_contains 'X509v3 Key Usage:' 'Digital Signature' || \
  fail "Key Usage does not include Digital Signature"
extension_contains 'X509v3 Basic Constraints:' 'CA:FALSE' || \
  fail "Basic Constraints must declare CA:FALSE"

print "Signing certificate verified: SHA-256 $actual_digest"
