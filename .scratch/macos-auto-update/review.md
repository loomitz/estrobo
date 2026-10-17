# Revisión de la rama de integración

Fixed point: `68ea6fcc82bda027d044106a5c43004c4458f192` (origin/main verificado).
Reviewed HEAD: `c7e6c0a94136166fb9b889de4897b93441a3eb67`.
Diff: `git diff 68ea6fc...HEAD`.
Commits: c7e6c0a, f7a29e7, bb7c849, 1aecd3c, b6080ef, 338d749, 218e9ea.
Fuentes: CONTRIBUTING.md, PRODUCT.md, DESIGN.md, release/signing/README.md y spec.md. Revisiones independientes por agentes Standards y Spec.

## Standards

P2: `prototype/MacUpdaterConsentSpike/run.py` ejecutaba terminate/wait antes de borrar claves efímeras y escribir evidencia. Una excepción/timeout durante cleanup podía abortar finally y violar la garantía de borrado del README. Proteger operaciones de limpieza independientemente y conservar evidencia de fallo.

Sin otros incumplimientos documentados ni smells accionables. Sin cambios de producto/publicación. Corregido en `f893d88`, integrado en `711c9a8`. Revisión focalizada independiente: P2 resuelto, sin nuevo defecto bloqueante. Cuatro regresiones de fallos de limpieza pasan; un diagnóstico real de redirect vuelve a reproducir el impedimento con `cleanup_errors: []`. No se repitió la matriz completa porque no cambió el mecanismo.

## Spec

Sin defectos inesperados ni scope creep. La rama es una investigación de mecanismo bloqueada, no un actualizador implementado.

- Decisión 2: cancelación interactiva durante terminateLater sigue sin demostrar; callbacks programados prueban control público del instalador, no un botón operable.
- Decisión 15: Sparkle contacta el origen de feed prohibido. No hay API pública identificada para el veto de redirecciones de su sesión privada; preflight deja una carrera, URLProtocol global/cache no la interceptan. La condición de detener integración de decisiones 2/22 aplica.
- Coordinador/adaptador/UI, preferencias/programación, seguridad de radio, canales, empaquetado/catálogo, conservación de datos/documentación y actualización Developer ID/notarizada/multiplataforma permanecen sin implementar o validar. Tickets 11-15 abiertos. No declarar cumplimiento completo.

La evidencia está acotada: framework/instalador reales, feed/DMG firmados, reemplazo/relanzamiento desde cache exacta, rechazo de bytes alterados y control negativo. Fixtures ad hoc sin sandbox en Apple Silicon no sustituyen los gates de distribución.

Resumen inicial: Standards 1 hallazgo P2; Spec 0 defectos inesperados y 3 grupos de requisitos pendientes reconocidos. El impedimento más importante en Spec es el veto efectivo de destinos del feed.

## Cierre

Standards: 1 hallazgo corregido, 0 abierto. Spec: 0 defectos inesperados; cancelación interactiva, política de destinos y producto/distribución permanecen pendientes. Especificación bloqueada, sin autorización de integración o distribución inferida de los tests del prototipo.
