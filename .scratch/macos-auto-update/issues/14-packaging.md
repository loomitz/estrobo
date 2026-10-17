# Empaquetado, firma y catálogo aprobado

Parent: ../spec.md
Type: task
Status: open
Assignee: none
Blocked by: 10

## Acceptance

Decisiones 12-14 y 17-20. Universal, helpers, verificadores precisos, publicación candidato/promoción separada, sin publicar releases automáticamente.

## Test seams

Seams autorizados por Testing Decisions de spec.md: coordinador mediante puerto único; prototipo Sparkle real; artefactos/scripts públicos; AppKit/UI y sesión existente. El usuario delegó expresamente todas las decisiones mientras está AFK.

## Graph refinement

2026-10-17: el empaquetado y sus verificadores dependen del mecanismo/dependencia aprobados en 10, no de la implementación del coordinador/adaptador. Puede avanzar en paralelo con 11; la validación integrada final sigue dependiendo de todos.
