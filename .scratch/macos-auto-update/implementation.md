# Implementación de actualizaciones macOS

Tracker: Local Markdown
Status: active
Integration branch: codex/macos-auto-update
Base: origin/main 68ea6fc (mismo árbol que spec baseline 91eeeb9)
Spec: spec.md

Los tickets 01-09 del checkout original son historial del mapa superseded. Tickets activos 10-15; dependencias en cada archivo. La autoridad AFK del usuario permite decidir las fronteras de prueba ya propuestas en spec.md sin otra entrevista. No autoriza publicación irreversible de releases.

## Tickets

- [Demostrar consentimiento con Sparkle real](issues/10-consent-gate.md)
- [Coordinador, preferencias, programación y seguridad](issues/11-coordinator.md)
- [Adaptador Sparkle y política de red/confianza](issues/12-sparkle-adapter.md)
- [Menú y Ajustes localizados y accesibles](issues/13-ui.md)
- [Empaquetado, firma y catálogo aprobado](issues/14-packaging.md)
- [Documentación, validación y revisión final](issues/15-acceptance.md)

## Disposición de implementación

2026-10-17: integración del producto detenida por incompatibilidad del contrato de red (spec, decisión 15) con las APIs públicas de Sparkle 2.10.0 evaluadas. La descarga desde cache y el consentimiento tienen evidencia real parcial favorable; no se confunden con cumplimiento del actualizador completo. Sparkle sigue redirecciones del catálogo hacia orígenes excluidos y no expone la sesión/delegado necesarios para vetarlas. Los controles independientes de Foundation confirman que registerClass afecta la sesión compartida, pero no la sesión privada de Sparkle; la carga del feed ignora la cache local.

Se conserva el mecanismo y sus requisitos, sin introducir fork/APIs privadas, servidor HTTP local, raíces TLS, permisos extra ni un enlace al navegador como sustituto. No se implementan coordinador/UI/empaquetado de un producto que no podría cumplir la política obligatoria. Tickets 11-15 permanecen abiertos y bloqueados; no se declara la especificación implementada ni lista para distribución. El prototipo, evidencia y revisión final quedan en esta rama de integración.

## Reanudación — 2026-10-18

Usuario aprobó revisar decisión 15 y continuar. El veto previo de dominios de redirecciones HTTPS del catálogo deja de ser requisito. Ticket 10 se reabre para cerrar interacción visible; después se retoman 11 y 14 en paralelo. Mantener autenticidad, HTTPS/ATS, consentimiento y seguridad de sesión. El diagnóstico histórico permanece como evidencia de la limitación aceptada.

Decisión técnica de reintentos: el puerto conserva Retry-After/status cuando están disponibles. Sparkle omite esos metadatos en algunos errores del feed; fallback conservador 24h y persistencia del plazo conocido, sin interpretar strings ni simular headers. Se registra en decisión 6 bajo la delegación de implementación existente.
