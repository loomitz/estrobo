# Coordinador, preferencias, programación y seguridad

Parent: ../spec.md
Type: task
Status: resolved
Assignee: coordinator
Blocked by: 10

## Acceptance

Decisiones 1, 4-6, 8-12 y 16. Pruebas de comportamiento en el coordinador con sesión y transporte simulado existentes.

## Test seams

Seams autorizados por Testing Decisions de spec.md: coordinador mediante puerto único; prototipo Sparkle real; artefactos/scripts públicos; AppKit/UI y sesión existente. El usuario delegó expresamente todas las decisiones mientras está AFK.

## Result — 2026-10-18

Coordinador, snapshot/domain, puerto único, preferencias persistibles y reloj del shell macOS implementados. Contrato y cobertura: [coordinator report](../../../docs/research/macos-updater-coordinator-2026-10-18.md).

`test-updates` pasa 14 recorridos de comportamiento, incluyendo estados reales de sesión/transporte simulado, backoff persistido en UserDefaults, consentimiento por identidad, cancelación con acknowledgement demorado y excepción de Multi persistido. Pasan `test-session-recovery`, `test-interactive-editing`, `test-workspace-chrome`, `swift test` (67 tests) y `make check` con Xcode completo.

Los tests del servicio controlado acreditan política, no una instalación real. Adaptador Sparkle/AppKit, composición/UI y distribución continúan en 12–15. No se introduce red ni dependencia Sparkle en módulos compartidos/iOS; sólo un gate genérico de suspensión de comandos, con seguridad de cierre independiente y observación de transporte conservada.
