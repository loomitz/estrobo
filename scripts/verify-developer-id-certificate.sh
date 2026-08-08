#!/bin/zsh

set -euo pipefail

fail() {
  print -u2 "Developer ID certificate verification failed: $*"
  exit 1
}

[[ $# -eq 3 ]] || \
  fail "usage: $0 CERTIFICATE_DER SHA256_FILE TEAM_ID"

certificate="$1"
fingerprint_file="$2"
team_id="$3"

[[ -r "$certificate" ]] || fail "certificate not found: $certificate"
[[ -r "$fingerprint_file" ]] || fail "fingerprint not found: $fingerprint_file"
[[ "$team_id" =~ '^[A-Z0-9]{10}$' ]] || fail "TEAM_ID must contain exactly 10 uppercase letters or digits"

expected_digest="$(/usr/bin/awk 'NF { print $1; exit }' "$fingerprint_file" | /usr/bin/tr '[:lower:]' '[:upper:]')"
[[ "$expected_digest" =~ '^[0-9A-F]{64}$' ]] || \
  fail "fingerprint is not a 64-character SHA-256 digest"
actual_digest="$(/usr/bin/shasum -a 256 "$certificate" | /usr/bin/awk '{ print toupper($1) }')"
[[ "$actual_digest" == "$expected_digest" ]] || \
  fail "certificate bytes do not match the versioned fingerprint"

temporary_dir="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/estrobo-developer-id-certificate.XXXXXX")"
trap '/bin/rm -rf -- "$temporary_dir"' EXIT
certificate_text="$temporary_dir/certificate.txt"

/usr/bin/openssl x509 \
  -inform DER \
  -in "$certificate" \
  -noout \
  -text >"$certificate_text" || fail "certificate must be a DER-encoded X.509 certificate"

/usr/bin/openssl x509 -inform DER -in "$certificate" -noout -checkend 0 >/dev/null || \
  fail "certificate is expired or not currently valid"

certificate_subject="$(/usr/bin/openssl x509 -inform DER -in "$certificate" -noout -subject -nameopt RFC2253 | /usr/bin/sed 's/^subject=//')"
certificate_issuer="$(/usr/bin/openssl x509 -inform DER -in "$certificate" -noout -issuer -nameopt RFC2253 | /usr/bin/sed 's/^issuer=//')"

[[ "$certificate_subject" != "$certificate_issuer" ]] || fail "certificate must not be self-signed"
print -r -- "$certificate_subject" | /usr/bin/grep -Eq '(^|,)CN=Developer ID Application:' || \
  fail "certificate subject is not Developer ID Application"
print -r -- "$certificate_subject" | /usr/bin/grep -Eq "(^|,)OU=${team_id}(,|$)" || \
  fail "certificate organizational unit does not match TEAM_ID"
print -r -- "$certificate_subject" | /usr/bin/grep -Fq "(${team_id})" || \
  fail "certificate common name does not include TEAM_ID"
print -r -- "$certificate_issuer" | /usr/bin/grep -Fq 'CN=Developer ID Certification Authority' || \
  fail "certificate issuer is not the Apple Developer ID certification authority"

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

/usr/bin/security verify-cert -c "$certificate" -p codeSign >/dev/null || \
  fail "certificate does not validate against the Apple code-signing trust chain"

print "Developer ID certificate verified: Team $team_id, SHA-256 $actual_digest"
