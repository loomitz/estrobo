# Documentación pública y de mantenimiento de actualizaciones

Parent: ../spec.md
Type: task
Status: resolved
Assignee: documentation
Blocked by: 14, 12, 13

## Acceptance

Decisiones 10, 16, 18-21. Actualizar documentación pública y de mantenimiento en español/inglés a partir del adaptador, presentación y empaquetado ya resueltos, sin depender del wiring productivo de 16.

Describir búsqueda/descarga con opt-in, confirmación por oferta, momento seguro, notas locales y recuperación. Distinguir el nuevo candidato macOS de beta 4 e iOS/iPadOS; conservar la ruta manual a la primera versión con actualizador y los enlaces de la versión realmente publicada. Explicar tráfico técnico de proveedores, ausencia de datos del radio/analítica, redirecciones HTTPS del feed aceptadas y límites observables de backoff. Documentar custodia/recuperación de claves, flujo candidato/promoción/retirada y corrección hacia delante, sin crear claves ni publicar contenido.

Privacidad, soporte, README, website y guías de mantenimiento deben separar implementación local de gates operativos/plataformas/credenciales pendientes. La validación integrada y el reporte final completos de la aceptación original se conservan en 17, dependiente de 15 y 16. No publicar ni operar radio físico.

## Test seams

Seams autorizados por Testing Decisions de spec.md: coordinador mediante puerto único; prototipo Sparkle real; artefactos/scripts públicos; AppKit/UI y sesión existente. El usuario delegó expresamente todas las decisiones mientras está AFK.

## Graph refinement

2026-10-18: documentación extraída de la aceptación final para avanzar en paralelo con 16. Contratos de 12-14 ya estables; 17 reúne documentación y composición antes del reporte y la revisión final.

## Resolution — 2026-10-18

Public documentation updated in Spanish/English: Privacy, Support, READMEs, unreleased changelog and incumbent website copy distinguish public beta 4 (manual installation, no updater), iOS/iPadOS (no updater/app network flow) and the unreleased macOS implementation. They describe opt-in/manual checks, safe disconnected explicit installation, cancellation/errors, fresh eligibility, forward recovery, provider IP/User-Agent/logs and excluded radio/profile/telemetry data. `website/src/config/release.ts` and all public beta-4 artifact links remain unchanged; no future release/feed is advertised as available.

Maintainer guides link the existing exact-source/CI/sign/notary/final-DMG approval contract and document real catalog CLI options, manual global ledger allocation, external public root/existing Keychain private account and pending recoverable backup, prepare before tag publication, separate release/catalog/deploy authority, immutable assets, monotonic source/state, fresh serialized deployments without infrastructure CAS, public verification and lost-key/manual recovery. Spanish overview: `docs/ACTUALIZACIONES-MACOS.md`. CONTRIBUTING now scopes its former blanket no-network rule to beta 4/iOS while admitting only the accepted macOS updater HTTPS/client/helper contract, without analytics/telemetry or HTTP in shared Core. The local ad hoc development versus mandatory Developer ID Hardened Runtime distinction is documented for 16's launch fix; final verification belongs to 17.

Validation (Node v24.22.0, pnpm11.16.0, Python3.14.3):

- `npm exec --yes --package=node@24 --package=pnpm@11.16.0 -- pnpm --dir website install --frozen-lockfile`: PASS, lockfile unchanged.
- Same toolchain `pnpm --dir website build`: PASS, Astro reports 0 errors/warnings/hints; includes live public-state validation before building. Fresh anonymous revalidated GET of `https://estrobo.app/updates/macos/state.json` with honest `EstroboCatalogVerifier/1.0` reports404, consistent with initial unconfigured bootstrap.
- Local documentation integrity: 101 Markdown file/anchor links PASS. Generated website: 80 local HTML links/anchors PASS; reciprocal EN/ES hreflang pairs and disclosure structure match, all download URLs remain exact `v0.1.0-beta.4`, and unconfigured output contains no appcast.
- 31 documented shell blocks parse via `bash -n` without executing their commands. The outside-repo validator was corrected to respect indented Markdown fences; no command or product failure was involved.
- `git diff --check`: PASS. No new tests that mirror prose, Swift/product/tooling mutations, keys, signing, notarization, physical radio, Git publication or deployment.

Local validation logs: `/private/tmp/estrobo-updater-docs-website-install.log`, `/private/tmp/estrobo-updater-docs-website-build.log`, `/private/tmp/estrobo-updater-docs-links.log`, `/private/tmp/estrobo-updater-docs-html.log`, `/private/tmp/estrobo-updater-docs-shell-syntax.log`, `/private/tmp/estrobo-updater-docs-public-state.log` and corresponding headers/body. Temporary QA scripts remain outside the repo. Final integrated acceptance, fixtures of maintainer operations and the final code-review workflow remain in17; this closure makes no operational distribution GO claim.

Concrete producer/consumer limit mismatch was reported to root for the final single fixer: catalog14 currently admits unbounded notes/archive sizes while adapter12 rejects notes above16,384 UTF-8 bytes per language and DMGs above64MiB. Maintainer docs state the consumer limits without claiming the producer already enforces them. No tooling was changed in this documentation ticket.
