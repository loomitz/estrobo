# Documentación pública y de mantenimiento de actualizaciones

Parent: ../spec.md
Type: task
Status: open
Assignee: none
Blocked by: 14, 12, 13

## Acceptance

Decisiones 10, 16, 18-21. Actualizar documentación pública y de mantenimiento en español/inglés a partir del adaptador, presentación y empaquetado ya resueltos, sin depender del wiring productivo de 16.

Describir búsqueda/descarga con opt-in, confirmación por oferta, momento seguro, notas locales y recuperación. Distinguir el nuevo candidato macOS de beta 4 e iOS/iPadOS; conservar la ruta manual a la primera versión con actualizador y los enlaces de la versión realmente publicada. Explicar tráfico técnico de proveedores, ausencia de datos del radio/analítica, redirecciones HTTPS del feed aceptadas y límites observables de backoff. Documentar custodia/recuperación de claves, flujo candidato/promoción/retirada y corrección hacia delante, sin crear claves ni publicar contenido.

Privacidad, soporte, README, website y guías de mantenimiento deben separar implementación local de gates operativos/plataformas/credenciales pendientes. La validación integrada y el reporte final completos de la aceptación original se conservan en 17, dependiente de 15 y 16. No publicar ni operar radio físico.

## Test seams

Seams autorizados por Testing Decisions de spec.md: coordinador mediante puerto único; prototipo Sparkle real; artefactos/scripts públicos; AppKit/UI y sesión existente. El usuario delegó expresamente todas las decisiones mientras está AFK.

## Graph refinement

2026-10-18: documentación extraída de la aceptación final para avanzar en paralelo con 16. Contratos de 12-14 ya estables; 17 reúne documentación y composición antes del reporte y la revisión final.
