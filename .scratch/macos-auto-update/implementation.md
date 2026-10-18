# Implementación de actualizaciones macOS

Tracker: Local Markdown
Status: implementation-complete
Final code-review: passed (Standards 5 resolved / 0 open; Spec 2 resolved / 0 open; reviewed 3acb7cc)
Integration branch: codex/macos-auto-update
Base: origin/main 68ea6fc (mismo árbol que spec baseline 91eeeb9)
Spec: spec.md

Los tickets 01-09 del checkout original son historial del mapa superseded. Tickets activos 10-17; dependencias en cada archivo. La autoridad AFK del usuario permite decidir las fronteras de prueba ya propuestas en spec.md sin otra entrevista. No autoriza publicación irreversible de releases.

## Tickets

- [Demostrar consentimiento con Sparkle real](issues/10-consent-gate.md)
- [Coordinador, preferencias, programación y seguridad](issues/11-coordinator.md)
- [Adaptador Sparkle y política de red/confianza](issues/12-sparkle-adapter.md)
- [Menú y Ajustes localizados y accesibles](issues/13-ui.md)
- [Empaquetado, firma y catálogo aprobado](issues/14-packaging.md)
- [Documentación pública y de mantenimiento](issues/15-acceptance.md)
- [Composición productiva y recorrido integrado](issues/16-composition.md)
- [Validación integrada y reporte final](issues/17-acceptance.md)

## Resultado actual — 2026-10-18

Tickets activos 10–17 resueltos: código y validación local integrados completos bajo la decisión 15 revisada. [Aceptación final](../../docs/research/macos-updater-acceptance-2026-10-18.md) reúne evidencia real de consentimiento/adaptador, composición nativa, regresiones, builds/CLI y documentos, con identidades de fuente y límites. El bloque del 17 de octubre se conserva como historia, no como estado vigente.

Revisión final ejecutada en `dda8798`: 4 incumplimientos Standards + 1 smell de criterio y 2 defectos Spec. [Reporte separado por eje](review-final.md), con reportes originales y correcciones por un único implementer. Raíz de fixtures, avisos oficiales, límites de catálogo, guías públicas y recuperación local ya tienen corrección/prueba focal; **confirmación independiente completa sobre `3acb7cc4f4aa5b2eb3e7207066c92f095b8753b7`: [Standards 5/5](../../docs/research/evidence/macos-updater-2026-10-18/final-fixes/standards-verification.md) y [Spec 2/2](../../docs/research/evidence/macos-updater-2026-10-18/final-fixes/spec-verification.md), cero abiertos, sin regresiones identificadas en su alcance**. El baseline real de 26 casos conserva su fuente original y el delta determinista actual de clasificación tiene 13 pruebas públicas posteriores. El gate independiente final está cerrado; este cierre documental no cambia las fuentes probadas y espera el merge separado de la entrega a integración. Siguen pendientes los gates operativos Developer ID/notarización/sandbox/dos builds, claves/backup, Intel/macOS13, autorización/recuperación/datos de producto y feed/promoción/retirada/tráfico públicos. Implementación local completa no habilita distribución ni publicación.

## Disposición histórica de implementación — 2026-10-17

2026-10-17: integración del producto detenida por incompatibilidad del contrato de red (spec, decisión 15) con las APIs públicas de Sparkle 2.10.0 evaluadas. La descarga desde cache y el consentimiento tienen evidencia real parcial favorable; no se confunden con cumplimiento del actualizador completo. Sparkle sigue redirecciones del catálogo hacia orígenes excluidos y no expone la sesión/delegado necesarios para vetarlas. Los controles independientes de Foundation confirman que registerClass afecta la sesión compartida, pero no la sesión privada de Sparkle; la carga del feed ignora la cache local.

Se conserva el mecanismo y sus requisitos, sin introducir fork/APIs privadas, servidor HTTP local, raíces TLS, permisos extra ni un enlace al navegador como sustituto. No se implementan coordinador/UI/empaquetado de un producto que no podría cumplir la política obligatoria. Tickets 11-15 permanecen abiertos y bloqueados; no se declara la especificación implementada ni lista para distribución. El prototipo, evidencia y revisión final quedan en esta rama de integración.

## Reanudación — 2026-10-18

Usuario aprobó revisar decisión 15 y continuar. El veto previo de dominios de redirecciones HTTPS del catálogo deja de ser requisito. Ticket 10 se reabre para cerrar interacción visible; después se retoman 11 y 14 en paralelo. Mantener autenticidad, HTTPS/ATS, consentimiento y seguridad de sesión. El diagnóstico histórico permanece como evidencia de la limitación aceptada.

Decisión técnica de reintentos: el puerto conserva Retry-After/status cuando están disponibles. Sparkle omite esos metadatos en algunos errores del feed; fallback conservador 24h y persistencia del plazo conocido, sin interpretar strings ni simular headers. Se registra en decisión 6 bajo la delegación de implementación existente.

## Partición por puerto estable — 2026-10-18

Tickets 10 y 11 resueltos estabilizan el mecanismo y el puerto del coordinador. 13 implementa componentes/presentación nativa, localización y pruebas de menú/Ajustes sobre ese puerto; depende de 11 y puede avanzar en paralelo con 12. La composición productiva de EstroboApp, AppDelegate, factory y bridge se extrae a 16, dependiente de 12 y 13. 15 depende ahora de 14 y 16. Esta partición conserva una sola instancia y el recorrido final original; evita acoplar el trabajo de presentación a detalles todavía en implementación del adaptador y mantiene toda la validación integrada al final.

## Partición de documentación y aceptación — 2026-10-18

Con 12, 13 y 14 resueltos, 15 pasa a documentación pública/de mantenimiento ES/EN y depende de esos contratos estables. Puede avanzar mientras 16 termina la composición productiva. La validación integrada y el reporte final se extraen a 17, dependiente de 15 y 16, conservando toda la aceptación original y los gates pendientes explícitos. Después de resolver todos los tickets se ejecuta el skill code-review de la rama de integración y se corrigen sus hallazgos, como requiere implement-spec; esta partición no adelanta ni elimina esa revisión final.
