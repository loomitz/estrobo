# Validación integrada y reporte final de actualizaciones

Parent: ../spec.md
Type: task
Status: resolved
Assignee: acceptance
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

## Resolution — 2026-10-18

[Aceptación local integrada](../../../docs/research/macos-updater-acceptance-2026-10-18.md) consolida 10–16, fuentes productivas inspeccionadas, commits/hashes/toolchains/artefactos, matriz PASS/PENDING y regresiones. Reutiliza 12/12 controles reales de consentimiento, 26/26 del adaptador real, 14 recorridos del coordinador, 40 capturas EN/ES/AX, escenas/delegate/runtime productivos, build/universal, shared/iOS, CLI/catálogo y documentos/website. Conserva honestamente el aggregate inicial fallido por firma ad hoc y la continuación corregida verde.

Se incorporaron textos/evidencia durable de ATS externo (HTTP y HTTPS→HTTP rechazados con -1022), parser real de notas bilingües y revisión visual independiente inicial/final `ship`. Se declara sustitución del rol finish por reviewer genérico independiente y límite de render nativo directo sin captura de compositor. [Informe de transporte/notas](../../../docs/research/macos-updater-transport-notes-2026-10-18.md).

Verificación de este ticket documental: enlaces, JSON/resultados, identidad de fuentes frente a commits probados, hashes de evidencia y `git diff --check`; sin nuevos tests espejo ni repetición de suites verdes sin cambios de comportamiento. Spec/tracker reflejan implementación y validación local completas, conservando diagnóstico histórico fechado. **La revisión final `code-review` queda explícitamente pendiente para el coordinador después de este merge**; sus hallazgos deben resolverse antes del cierre del workflow.

Sin distribución GO: raíz/custodia/backup productivos, dos builds Developer ID/notarizados/sandboxed, Intel/macOS13, autorización/recuperación/preservación de datos durante reemplazo y feed/activos/promoción/retirada/tráfico públicos siguen pendientes. Las pruebas ad hoc ARM/no sandbox, compilación universal y simulación no sustituyen esos gates. No se generaron/exportaron claves, usaron credenciales notariales, operó radio físico, publicó/pusheó/desplegó ni alteró WIP ajeno.
