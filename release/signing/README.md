# Release signing contract

Public beta bundles use one stable, self-signed code-signing identity that is independent of Apple. This signature provides continuity between beta builds; it is not Developer ID, notarization, or a way to suppress Gatekeeper.

Before the first release, provision these two public files:

- `estrobo-beta-signing.cer`: the leaf X.509 certificate in DER format.
- `estrobo-beta-signing.sha256`: the uppercase or lowercase SHA-256 digest of the exact DER bytes, optionally followed by the filename.

The private key must never enter this repository. Export the certificate and private key as a password-protected PKCS#12 file using OpenSSL's legacy-compatible encoding (`openssl pkcs12 -export -legacy`) and store its base64 representation and password in GitHub Secrets named `ESTROBO_SIGNING_P12_BASE64` and `ESTROBO_SIGNING_P12_PASSWORD`. Store the certificate common name in `ESTROBO_SIGNING_IDENTITY`.

The release workflow imports the PKCS#12 file into an ephemeral keychain, grants the public certificate temporary code-signing trust on the ephemeral build host, hashes the imported leaf certificate, and compares it with both public files before building. An `always()` cleanup step removes that temporary trust, the keychain, and the PKCS#12 file. A missing file, secret, identity, or mismatch stops the release.

Participants must not be asked to install or trust this certificate. Gatekeeper rejection remains expected, and `codesign --verify` must succeed before that rejection is accepted as a release gate.
