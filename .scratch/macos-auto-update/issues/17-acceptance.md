# Validación integrada y reporte final de actualizaciones

Parent: ../spec.md
Type: task
Status: open
Assignee: none
Blocked by: 15, 16

## Acceptance

Decisiones 10, 16, 20-22 y Testing Decisions completas. Distinguir evidencia local y gates operativos/plataformas/credenciales pendientes; no publicar ni operar radio físico.

Conservar toda la aceptación original de 15: comprobar el recorrido productivo integrado, seguridad de sesión/cierre, consentimiento e identidad, persistencia/relanzamiento, localización/accesibilidad, confianza/red, empaquetado y documentación. Reutilizar evidencia válida de 10-16 y ejecutar los checks integrados necesarios ante los cambios finales, sin convertir pruebas simuladas, compilación universal o fixtures ad hoc en distribución acreditada.

El reporte final debe identificar commits, artefactos, pruebas y resultados reales; distinguir fallos previos de regresiones y registrar expresamente los gates aún pendientes por plataformas, claves/credenciales, Developer ID/notarización, autorización/recuperación y disponibilidad pública. La ausencia de esos entornos no se presenta como éxito operativo ni como falta de implementación de código ya completado. No habilitar producción ni radio físico para completar el informe.

El cierre de implement-spec conserva la revisión final mediante el skill code-review sobre la rama de integración después de resolver todos los tickets. Corregir sus hallazgos y registrar el resultado; el reporte de este ticket no sustituye esa revisión ni autoriza publicación.

## Test seams

Seams autorizados por Testing Decisions de spec.md: coordinador mediante puerto único; adaptador/prototipo Sparkle real; artefactos/scripts públicos; AppKit/UI y sesión existente con transporte simulado. Reutilizar las fronteras acordadas y evidencia durable, sin crear otra implementación del instalador. El usuario delegó expresamente las decisiones mientras está AFK.

## Graph refinement

2026-10-18: validación integrada y reporte extraídos de 15 para permitir documentación independiente del wiring de 16. 17 depende de ambos y conserva la aceptación final original; la revisión final del workflow sigue después de todos los tickets.
