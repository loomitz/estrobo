# Transporte ATS y notas firmadas — 2026-10-18

Investigaciones locales previas, incorporadas a evidencia durable por [ticket 17](../../.scratch/macos-auto-update/issues/17-acceptance.md). Se inspeccionaron sus resultados y las fuentes finales del adaptador/empaquetado; no se repitieron solicitudes ni se modificó producto. Son experimentos separados: no atribuir el host de transporte o el spike Objective-C al adaptador Swift productivo.

## ATS externo con Sparkle real

El host Swift usa `SPUUpdater`/`SPUUserDriver` públicos y Sparkle oficial 2.10.0, sin mock de transporte, URLProtocol ni evaluación TLS propia. Su Info se derivó del Info productivo, cambiando identidad, versión, raíz pública efímera y feed de prueba. `NSAppTransportSecurity` está ausente. La ejecución fue arm64, macOS 27.0.1 (26A434), Swift 6.4 con Xcode completo, ad hoc sin App Sandbox.

| URL de feed probada | Resultado observado | Alcance |
| --- | --- | --- |
| `http://example.com/` | Sparkle 2001, error anidado `NSURLErrorDomain -1022` | Rechazo ATS de HTTP externo con DNS cualificado |
| `https://example.com/` | Sparkle 1000 → 3002, falta firma EdDSA | Control HTTPS llegó a validación obligatoria del feed; HTML no es una oferta válida |
| `https://httpbingo.org/redirect-to?url=http%3A%2F%2Fexample.com%2F` | Sparkle 2001, error anidado `NSURLErrorDomain -1022` | Rechazo del downgrade HTTPS → HTTP externo |

Un GET separado sin seguir redirecciones registró 302 y `Location: http://example.com/`. Los tres procesos terminaron con código 0 porque completaron el harness; la aceptación procede de los errores de dominio/código, no de considerar sus operaciones exitosas. No se inició descarga de DMG ni instalación. Los avisos `sandbox_extension_issue_file_to_process ... Operation not permitted` se conservan; no demuestran operación sandboxed.

Evidencia: [resultados completos](evidence/macos-updater-2026-10-18/ats/runtime-results.json), [respuesta 302](evidence/macos-updater-2026-10-18/ats/redirect-source-response.json), [entorno](evidence/macos-updater-2026-10-18/ats/environment.json), [host](evidence/macos-updater-2026-10-18/ats/ATSHost.swift) y [runner original](evidence/macos-updater-2026-10-18/ats/run.py). El runner archivado conserva las rutas temporales originales a framework y raíz **pública** de fixture; requiere regenerar esos insumos fuera del repo para reproducirlo. No se archivaron binarios ni claves privadas.

La investigación se apoyó en [ATS de Apple](https://developer.apple.com/documentation/bundleresources/information-property-list/nsapptransportsecurity), [NSAllowsArbitraryLoads](https://developer.apple.com/documentation/bundleresources/information-property-list/nsapptransportsecurity/nsallowsarbitraryloads) y el [transporte de Sparkle 2.10.0](https://github.com/sparkle-project/Sparkle/blob/2.10.0/Downloader/SPUDownloader.m). La evidencia ejecutada prueba los destinos externos nombrados en este runtime; no generaliza todos los dominios locales/IP, Intel ni macOS 13. El fixture HTTP loopback del adaptador tiene una frontera distinta y no acredita este rechazo externo.

En el árbol final, `SparkleUpdateService` exige ATS ausente/vacío y el tooling rechaza excepciones, fija HTTPS y firma obligatoria, desactiva Downloader XPC y lo retira del bundle. Esa inspección acredita configuración de producto; la ejecución anterior acredita el transporte SPU sin modificar. Quedan pendientes el candidato sandboxed/Developer ID, captura de tráfico real y plataformas de distribución. ATS tampoco añade el veto previo de dominios de redirecciones HTTPS del feed que la decisión 15 revisada aceptó omitir.

## Notas bilingües autocontenidas

Sparkle selecciona una sola descripción localizada usando preferencias de Bundle antes de construir `SUAppcastItem`. Para conservar el idioma explícito de Estrobo, el catálogo usa dos elementos distintos bajo `https://estrobo.app/xmlns/updates`: `estrobo:releaseNotesEn` y `estrobo:releaseNotesEs`, además de la descripción inglesa convencional. Son identificadores XML, no recursos descargados. El contrato procede de la [API pública de item](https://github.com/sparkle-project/Sparkle/blob/2.10.0/Sparkle/SUAppcastItem.h), la [selección y preservación de extensiones](https://github.com/sparkle-project/Sparkle/blob/2.10.0/Sparkle/SUAppcast.m) y el [tratamiento de confianza del item](https://github.com/sparkle-project/Sparkle/blob/2.10.0/Sparkle/SUAppcastItem.m).

El spike aislado firmó el feed completo con `sign_update` oficial y comprobó el status público de firma y ambos strings en `shouldProceedWithUpdate`. El parser real conservó inglés/español, saltos de línea y `&amp;` decodificado como `&`:

```text
inline-notes-status=1 en=English notes and & newline
second line es=Notas en español y & salto
segunda línea
```

Evidencia: [eventos](evidence/macos-updater-2026-10-18/inline-notes/events.log), [identidad de artefacto](evidence/macos-updater-2026-10-18/inline-notes/artifact.json), [resultados](evidence/macos-updater-2026-10-18/inline-notes/results.json) y [solicitudes](evidence/macos-updater-2026-10-18/inline-notes/requests.json). `cleanup_errors` está vacío e instalación permanece build 1. `network_gate_passed:false` pertenece al diagnóstico histórico de redirect reutilizado para llegar al callback; no describe un fallo del parser bilingüe ni incumplimiento del contrato HTTPS revisado.

La prueba posterior del [adaptador real](macos-updater-adapter-2026-10-18.md) comparte fuentes Swift de producto: exige firma de feed/item antes de mapear ambas extensiones y rechaza notas mayores de 16,384 bytes UTF-8 por idioma. La [presentación nativa](macos-updater-presentation-ui-2026-10-18.md) selecciona localmente el idioma de Estrobo y usa `Text(verbatim:)`. `shouldDownloadReleaseNotesForUpdate` devuelve siempre false; JavaScript/profiling están desactivados. No hay WebView ni solicitud automática de recursos de notas. Los límites del productor de catálogo todavía se someten a la revisión final; este informe no presume que toda validación de entrada coincida con los límites del consumidor.
