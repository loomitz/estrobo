# Empaquetado, firma y catálogo aprobado

Parent: ../spec.md
Type: task
Status: resolved
Assignee: packaging
Blocked by: 10

## Acceptance

Decisiones 12-14 y 17-20. Universal, helpers, verificadores precisos, publicación candidato/promoción separada, sin publicar releases automáticamente.

## Test seams

Seams autorizados por Testing Decisions de spec.md: coordinador mediante puerto único; prototipo Sparkle real; artefactos/scripts públicos; AppKit/UI y sesión existente. El usuario delegó expresamente todas las decisiones mientras está AFK.

## Graph refinement

2026-10-17: el empaquetado y sus verificadores dependen del mecanismo/dependencia aprobados en 10, no de la implementación del coordinador/adaptador. Puede avanzar en paralelo con 11; la validación integrada final sigue dependiendo de todos.

## Result — 2026-10-18

Code/build plumbing resolved. Official Sparkle 2.10.0 is pinned by archive SHA-256 and verified content even for overrides, linked only to the macOS shell and embedded with preserved versioned symlinks. Downloader XPC and development headers/modules are removed. Exact framework layout, unexpected binaries/symlinks, universal slices, self-contained dependencies, inside-out Hardened Runtime signatures, component identities and exact entitlements are verified. Distribution requires an external approved public root before signing; development contains no fixture root.

Build 5 (`0.1.0`, beta, `v0.1.0-beta.5`) was allocated above the maximum assigned product build 4, including current refs and draft releases. Global assignment ledger and explicit bundle channel/tag separate version, channel and build. Stable `vVERSION+build.BUILD` supports corrective builds with unchanged marketing version; conventional `vVERSION` is also supported when explicitly allocated. Historical beta 4 and earlier verifiers remain valid.

Local signed catalog prepare/withdraw/approve operations reuse the existing exact-source, notarization, final-DMG/checksum and maintainer approval contract; they never publish. Website builds copy only exact approved signed bytes, enforce matching catalog/withdrawal digests and revalidate public monotonic revision/withdrawal history (including rejecting rollback through an unconfigured checkout). Route-specific appcast/state headers require revalidation. Notes are inline signed English/Spanish fields, without remote resources. Canonical source remains unconfigured and the website still advertises beta 4 manually.

Validation: six public artifact CLI cases plus three approved-catalog/site cases PASS; pinned dependency tampering, missing release root, unexpected/disguised binaries, stable same-version builds, actual ad hoc inside-out signatures/universal helper slices and signature tampering are covered. Native build, macOS typecheck/module boundaries, universal build, actual universal bundle/component verification and workspace UI regression PASS. Existing Developer ID source/candidate/approval suites and 32 isolated DMG cases PASS. Website install/build PASS using Node 24 + pnpm 11.16.0, including the real public-state 404 bootstrap check with an honest verifier User-Agent; no feed is generated for the unconfigured source. Missing production key is confirmed to fail Developer ID preflight before signing.

Local logs: `/private/tmp/estrobo-updater-packaging-focused-tests.log`, `...-all-tools-final.log`, `...-build.log`, `...-universal.log`, `...-verify.log`, `...-check.log`, `...-ui-regression.log`, `...-website-build.log`, and `/private/tmp/estrobo-updater-missing-public-root.log`. These are local implementation evidence, not distribution acceptance.

Operational gates remain pending: production EdDSA root and recoverable offline backup; signed/notarized exact two-build replacement and data preservation; Intel/minimum macOS runtime; authorization/translocation/interrupted-replacement recovery; real public feed/assets/cache/promotion/withdrawal/traffic verification. No production key was created/exported, no real Developer ID/notary credentials were used, and no release, feed or infrastructure was published. Ticket 15 records final integrated acceptance separately.
