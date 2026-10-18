# Demostrar consentimiento con Sparkle real

Parent: ../spec.md
Type: task
Status: open
Assignee: none
Blocked by: none

## Acceptance

API pública, descarga sin preparación, quit/cierre/reinicio, confirmación, veto/cancelación/reintento; cache e identidad del archivo. Si no existe solución mantenible, detener integración y documentar diagnóstico reproducible. Decisiones 2 y 22.

## Test seams

Seams autorizados por Testing Decisions de spec.md: coordinador mediante puerto único; prototipo Sparkle real; artefactos/scripts públicos; AppKit/UI y sesión existente. El usuario delegó expresamente todas las decisiones mientras está AFK.

## Result — 2026-10-17

Prototipo real y evidencia: [gate report](../../../docs/research/macos-updater-consent-gate.md).

- 11 casos mecánicos con Sparkle 2.10.0, feed firmado y DMG firmado pasan, incluido cache-only por API pública, veto previo, cancelación pública, reemplazo y relanzamiento reales sin una segunda descarga.
- El cierre AppKit diferido suspende entrada/polling normal: cancelar mediante acción pública programada acredita control del instalador, no interacción visible. Cancelación interactiva pendiente.
- Diagnóstico real de feed sigue un redirect a origen prohibido. Sparkle usa sesión privada sin seam público para el guard obligatorio de decisión 15; URLProtocol global no intercepta esa sesión. Gate de red falla.
- No se habilita integración de producto ni se desbloquean sus tickets dependientes. Decisiones 2 y 22 exigen detenerla; conservar requisitos. Distribución Developer ID/notarizada/sandbox/multiplataforma permanece pendiente.

## Reopened — 2026-10-18

Contrato revisado autorizado en spec.md decisión 15: redirecciones HTTPS del catálogo gestionadas por Sparkle, sin garantía de veto previo de dominio. Resolver interacción visible real (confirmación, cancelación, veto y reintento) usando APIs públicas; no acreditar temporizadores como clicks del usuario. Las firmas y la garantía de no instalar al cerrar sin confirmar se conservan.
