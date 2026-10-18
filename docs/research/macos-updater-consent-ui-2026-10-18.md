# Actualizador macOS: consentimiento visible acreditado — 2026-10-18

**Gate técnico de consentimiento aprobado bajo la especificación revisada.** Doce recorridos con controles visibles, eventos nativos de AppKit y Sparkle 2.10.0 real pasan. Cancelar, vetar el cierre o salir normalmente conserva el build anterior; una nueva confirmación explícita instala el DMG firmado desde cache y relanza el build nuevo. Esto permite retomar los tickets de integración; no acredita distribución de Estrobo ni sus gates Developer ID/notarización/sandbox/plataformas/radio.

La revisión autorizada de [spec.md, decisión 15](../../.scratch/macos-auto-update/spec.md) acepta las redirecciones HTTPS del catálogo gestionadas por Sparkle sin veto previo de dominios. El [diagnóstico de 2026-10-17](macos-updater-consent-gate.md) sigue siendo evidencia histórica de esa limitación aceptada. No se han relajado firma, identidad del archivo, consentimiento por oferta ni seguridad del cierre.

## Prueba y frontera pública

Ejecutar:

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer python3 prototype/MacUpdaterConsentSpike/run.py --ui-events --output /tmp/estrobo-consent-ui
python3 prototype/MacUpdaterConsentSpike/test_cleanup.py
```

El runner compila una aplicación AppKit aislada con `NSButton` visibles, identificadores de accesibilidad y menú Cmd-Q. La automatización publica eventos `NSEvent` de mouse down/up en la cola pública de `NSApplication`; AppKit realiza hit-testing, tracking del botón y entrega su acción. Cmd-Q es un evento de teclado y el cierre de última ventana utiliza el botón estándar de la ventana. No se usa `performClick`, AXPress, callbacks del instalador simulados ni temporizadores que ejecuten Cancelar en sustitución de esos eventos. El archivo de comandos sólo inyecta los eventos; el log distingue evento encolado de acción efectivamente recibida.

Los snapshots JSON contienen títulos/identificadores/estado habilitado y texto visible. Los PNG son capturas renderizadas del contenido AppKit, en apariencia clara fija para esta fixture; no son fotografías del escritorio ni prueba de VoiceOver. La aplicación y ventana reales están abiertas durante cada recorrido. El modo `--ui-events` es el mecanismo actual; los modos mecánicos anteriores se conservan como regresión histórica.

Se conservan [eventos completos](evidence/macos-updater-2026-10-18/native-ui/events.log), [solicitudes](evidence/macos-updater-2026-10-18/native-ui/requests.json), [resultados](evidence/macos-updater-2026-10-18/native-ui/results.json), [artefacto/toolchain](evidence/macos-updater-2026-10-18/native-ui/artifact.json) y [snapshots públicos](evidence/macos-updater-2026-10-18/native-ui/ui/). `passed: true`, doce casos y `cleanup_errors: []` describen esta ejecución real.

## Cambio mínimo que elimina el bloqueo de interacción

1. Descargar mantiene sólo el DMG en disco. No se prepara ningún instalador ni se persiste autorización.
2. El botón visible «Install and restart» confirma la oferta exacta. Se ejecuta un preflight real de AppKit: el delegado evalúa el gate y devuelve `.terminateCancel` para conservar la aplicación y su event loop normal mientras se revalida el feed firmado y se prepara la oferta aprobada.
3. El callback público de Sparkle `showReadyToInstallAndRelaunch` se retiene **sin consumirlo**. Cancelar, nuevo trabajo inseguro o una salida normal invalidan el consentimiento y responden `.skip`, una sola vez. El cierre normal espera la finalización pública del ciclo cancelado antes de volver a pedir terminar.
4. Para comprometer la instalación, se vuelve a pedir terminar mediante AppKit. Su veto ocurre **antes** de responder `.install`. Si veta, se cancela el instalador preparado mediante el reply todavía no consumido y se restaura la ventana. Si acepta, se bloquean nuevas acciones y sólo entonces se entra brevemente en `.terminateLater`, se responde `.install` y se permite terminar cuando el instalador real informa su fase de instalación.
5. Un callback que llega desde la cola principal de Sparkle agenda la solicitud final mediante el run loop público de AppKit; no entra de forma anidada en terminación desde un bloque de GCD que impediría procesar los siguientes callbacks. No se usa ningún nombre privado de modo del run loop.

El checkpoint visible «Install and restart (pause)» detiene la fixture en preparación completada para hacer reproducibles los clicks de cancelar/vetar/nuevo trabajo. Ya recibió consentimiento explícito; no prepara una oferta sin esa confirmación. El botón normal realiza el mismo protocolo y continúa al compromiso automáticamente. El checkpoint es instrumentación de esta prueba, no una propuesta de añadir una segunda confirmación al producto.

## Red → green y resultados observables

La primera prueba nativa se ejecutó sobre el camino anterior: Descargar y Confirmar recibieron acciones reales; al entrar demasiado pronto en `.terminateLater`, los eventos del botón Cancelar se encolaron pero su acción **no se entregó**. La prueba falló por timeout de ocho segundos. La misma interacción pasa al dejar la preparación fuera de terminación pendiente. Se conserva el [fallo inicial](evidence/macos-updater-2026-10-18/red-modal/results.json) y su [log de eventos](evidence/macos-updater-2026-10-18/red-modal/events.log).

| Recorrido con eventos visibles | Resultado real |
| --- | --- |
| Descargar y Cmd-Q sin confirmar | Build 1, sin preparación de Sparkle |
| Nuevo proceso con cache y botón estándar de cerrar ventana | Build 1 |
| Cancelar transferencia real y volver a descargar | Archivo incompleto ausente; reintento produce bytes exactos; build 1 |
| Cancelar con el instalador real ya preparado | Acción del botón entregada; `.skip`; Cmd-Q posterior deja build 1 |
| Veto AppKit antes de preparar | Aplicación abierta, sin preparación; resolver y salir deja build 1 |
| Veto AppKit final, después de preparar | Se cancela antes de `.install`; ventana restaurada; salida posterior deja build 1 |
| Cmd-Q con instalador preparado | Invalida consentimiento, cancela y espera fin del ciclo; build 1 |
| Nuevo trabajo inseguro mediante control visible | Cancela la oferta preparada; resolver y salir deja build 1 |
| Feed recién firmado cambia build ofrecido | Rechazo previo a copiar archivo; build 1 |
| Cache evictada después de primarla | Fallo cerrado, cero solicitudes adicionales del DMG; build 1 |
| Cache adulterada con igual longitud | Sparkle rechaza la firma antes de descomprimir; build 1 |
| Cancelar, confirmar de nuevo y continuar normalmente | Reemplazo real a build 2 y ventana del proceso relanzado; cero nuevas solicitudes del DMG |

La identidad y firma EdDSA del DMG constan en el manifiesto de evidencia. La copia persistida tiene el mismo SHA-256 que el DMG servido; Sparkle la consume mediante el request público con `.returnCacheDataDontLoad`, vuelve a verificarla y realiza el reemplazo. El reintento exitoso no hizo una segunda descarga de archivo. El feed firmado sí se obtuvo de nuevo en cada intento. Las cinco regresiones de limpieza también pasan, incluyendo terminación fallida, proceso que ignora SIGTERM, preparación parcial y relanzamiento cuyo ejecutable usa un alias de ruta; no quedan claves privadas ni procesos de la fixture.

## Alcance que sigue pendiente

El framework oficial es el mismo Sparkle 2.10.0 sin modificar, con firmas de feed/archivo y verificación antes de extracción; las claves efímeras se generan fuera del HTTP fixture y se borran. Los bundles externos son ad hoc, sin sandbox ni notarización, en un directorio temporal propio. La ejecución fue Apple Silicon, macOS 27.0.1, Xcode beta. Los avisos `sandbox_extension_issue_file_to_process ... Operation not permitted` se conservan en stderr y no se confunden con validación del sandbox.

No se ejecutó Estrobo del usuario, no se operó Bluetooth ni se emitieron flashes, no se accedió a sus claves, no se modificó una release o infraestructura. Siguen pendientes integración con el controlador de sesión real/simulado, UI de producto localizada/accesible, ATS/HTTPS y tráfico del candidato, Developer ID/notarización, autorización del sistema, macOS mínimo, Intel y el gate de distribución entre builds firmados. Un reinicio de proceso no acredita un reinicio completo del Mac. El gate que se cierra aquí es la viabilidad del consentimiento y su interacción visible, no la totalidad de la especificación.
