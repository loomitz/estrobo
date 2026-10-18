# Adaptador Sparkle y política de red/confianza

Parent: ../spec.md
Type: task
Status: resolved
Assignee: sparkle_adapter
Blocked by: 10, 11

## Acceptance

Decisiones 3, 13-16 y 19. APIs públicas, firma del feed y archivo, redirects, revalidación fresca y cancelación.

## Test seams

Seams autorizados por Testing Decisions de spec.md: coordinador mediante puerto único; prototipo Sparkle real; artefactos/scripts públicos; AppKit/UI y sesión existente. El usuario delegó expresamente todas las decisiones mientras está AFK.

## Implementación y validación

La [revisión final posterior](../review-final.md) añade constantes públicas y recuperación determinista para translocación/copia/autenticación, probadas con 13 callbacks/resultados del servicio. Los 26 casos reales de abajo corresponden al baseline `fd4cc73`; HTTP/lifecycle no cambian y ese delta posterior no se atribuye a la ejecución anterior. Los mismos reviewers confirmaron las correcciones en `3acb7cc`, sin hallazgos abiertos; el reporte enlazado conserva ambos dictámenes y sus alcances.

Servicio real app-local, descarga propia limitada y persistida, bridge AppKit compartido por producto/fixture, catálogo firmado y elegibilidad fresca, cache-only handoff, cancelación acreditada por ciclo terminado, notas EN/ES firmadas y errores públicos tipados. Factory/bridge listos para composición de 16; no se modificaron EstroboApp/AppDelegate en este ticket.

26 casos reales pasaron: incluye DMG firmado instalado build1→2, relanzamiento estable, cero refetch, checks/cancelación demorada, veto/cancel/quit, retirada y adulteración, selección de canal/compatibilidad, Retry-After y retención de cache. Después de integrar 292366d pasaron check completo, coordinador y presentación nativa. Interacción de edición/ventana y cinco pruebas de limpieza también verdes.

Reporte y evidencia: [adaptador real](../../../docs/research/macos-updater-adapter-2026-10-18.md). Las limitaciones de Developer ID/notarización, sandbox/XPC, Intel/macOS13 runtime y promoción pública quedan explícitas para 15; su ausencia no se presenta como distribución validada. No se generaron claves de producción ni se publicó contenido. Los PNG negros del fixture se excluyeron de evidencia visual.
