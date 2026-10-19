# Composición macOS del actualizador — 2026-10-18

Ticket: [16](../../.scratch/macos-auto-update/issues/16-composition.md). Base de implementación: `7c002efa3e9077996d695c120ca0b71780f0bc2e`. Xcode completo mediante `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer`; host ARM64, macOS 27.0.1. Dependencia Sparkle oficial 2.10.0 verificada por el tooling existente.

## Resultado productivo

`EstroboApp` crea una instancia de `UpdateCoordinator` con los metadatos instalados del bundle, preferencias `.standard`, reloj productivo y factory real. `MacUpdateRuntime` conecta esa instancia con la sesión existente y el `UpdateInstallationLifecycle` retenido por el AppDelegate. La callback de salida ordinaria captura débilmente al coordinador. No hay un segundo puerto de actualizaciones ni un instalador en la UI.

`MacAppScenes` contiene el grafo utilizado tanto por producto como por el fixture nativo: ventana principal, única ventana `updates`, comandos localizados y Menu Bar. La misma instancia llega a Ajustes. La invitación y el indicador se insertan dentro del contenido flexible de la ventana principal, sin un wrapper que aumente su altura mínima. La comprobación automática conserva presentación pasiva; la orden manual abre Actualizaciones. El delegate pasa toda terminación al lifecycle real y conserva la reapertura de la ventana principal.

Se corrigió un defecto de localización demostrado en el fixture: con UI española y sistema `en_MX`, el formatter anterior mostraba «Zero KB». Los dos conteos de progreso usan ahora `ByteCountFormatStyle` con `language.locale` explícito y cero sin deletrear. La prueba nativa exige «0 bytes» y ausencia de «Zero».

## Pruebas integradas

`test-update-composition` usa el constructor productivo, `PrototypeAppDelegate` y lifecycle reales. Sólo sustituye el puerto existente de servicio y el reloj; usa sesión simulada y preferencias aisladas. Comprueba identidad de sesión, opt-out inicial, persistencia independiente al reconstruir el runtime, metadatos instalados y estado desconectado. Comprueba también el veto por edición, restauración de ventana, preflight por `NSApp.terminate`, bloqueo de comandos durante preparación, salida ordinaria que invalida aprobación, cancelación pendiente sin desbloquear, acknowledgement que permite un único reintento de salida y recuperación de comandos. Un recorder externo intercepta únicamente el resultado `terminateNow` para mantener vivo el proceso de prueba; las decisiones provienen del delegate productivo.

La misma prueba construye el servicio real con el bundle productivo `mx.loo.estrobo`, que carece de `SUPublicEDKey`. Una búsqueda manual produce error tipado de configuración y conserva sesión desconectada y opt-out. No se introduce una raíz de confianza de fixture en producto.

`test-update-scenes` aloja el mismo `MacAppScenes` en una app SwiftUI de identidad propia y defaults UUID. Ejecuta el menú AppKit real dos veces, comprueba una única búsqueda retenida y una única ventana Actualizaciones, y comprueba que el comando sigue presente con esa ventana activa. Acciones AX reales abren Ajustes, modifican la preferencia del mismo coordinador sin habilitar descargas, cierran Ajustes, inician descarga, inspeccionan progreso cero y cancelan. La sesión termina desconectada. Los defaults de la suite se eliminan al finalizar o fallar.

La captura nativa directa [main-invitation-es-light.png](evidence/macos-updater-2026-10-18/composition/main-invitation-es-light.png) muestra la invitación dentro de la ventana habitual configurada a 1180 × 820; el área de contenido medida es 1180 × 792. La revisión del coordinador de implementación confirmó que controles de conexión y footer permanecen visibles, sin overlay. No se repitió el rediseño ni la revisión visual completa de 13. [Resultados medidos](evidence/macos-updater-2026-10-18/composition/scenes-results.json): idioma `es`, sistema `en_MX`, una búsqueda, una ventana, progreso localizado y sesión desconectada.

## Firma local y smoke del producto

La primera ejecución del aggregate descubrió un defecto real de firma local: tanto host como Sparkle tenían firma ad hoc con Hardened Runtime y ningún Team ID. dyld rechazó cargar Sparkle por library validation. El helper productivo firma ahora los cinco componentes aprobados dentro-fuera con `--options 0` **sólo para identidad `-`**. Esto también elimina flags heredados de la firma del proveedor. El host mantiene sus cuatro entitlements exactos; los componentes embebidos mantienen diccionarios vacíos. [Inspección de la app construida](evidence/macos-updater-2026-10-18/composition/development-product-signatures.json) verifica firmas estrictas, ausencia de runtime en los cinco componentes, permisos y hash del ejecutable real.

Las identidades de distribución siguen solicitando Hardened Runtime y timestamp. `verify-signatures --distribution` sigue exigiendo runtime, allowlist exacta, certificado fijado, Team ID, autoridad y timestamp Developer ID. No se añadió `disable-library-validation` ni una excepción de permisos. La regresión CLI firma realmente una app universal de fixture en modo ad hoc, verifica sus componentes, rechaza esa app bajo distribución por falta de runtime, y captura los argumentos de la frontera externa codesign para la rama Developer ID sin usar credenciales. También conserva la prueba de firma alterada. Suite completa: seis pruebas, verdes.

`test-launch-responsiveness` clona la app productiva real, cambia sólo la identidad aislada del harness, vuelve a firmar el outer ad hoc sin Sandbox/runtime, usa `CFFIXED_USER_HOME` temporal y `--mock-radio`, y verifica activación AppleEvent sin crear un contenedor persistente. Los componentes internos conservan las firmas de desarrollo recién verificadas. Esto prueba arranque del ejecutable productivo y carga de Sparkle en desarrollo; no es evidencia de arranque sandboxed ni de distribución Developer ID.

## Comandos y resultados

`check build universal` pasó, incluyendo módulos Core/Bluetooth/Persistence independientes, typecheck nativo y compilación de ambas slices `arm64`/`x86_64` con deployment target macOS 13. El universal queda sin firmar. [Log](evidence/macos-updater-2026-10-18/composition/check-build-universal.log).

`make mac-prototype-test BUILD_DIR=prototype/EstroboMac/Build` pasó protocolo, recuperación de sesión, librería, localización, puntero de modelado, chrome/reapertura, marca, edición interactiva y accesibilidad del menú. Falló después en el smoke por el defecto de firma descrito. Se conserva el [log inicial](evidence/macos-updater-2026-10-18/composition/aggregate-initial.log); no se presenta esa ejecución como verde.

Después de corregir la firma se ejecutaron únicamente el target fallido y los targets restantes, todos verdes:

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
make -C prototype/EstroboMac \
  test-launch-responsiveness test-radio-transport-adapter \
  test-simulated-radio-transport test-secure-persistence test-updates \
  test-update-presentation test-update-composition test-update-scenes \
  SPARKLE_DIR=/Users/loomitz/Dev/estrobo-macos-auto-update/.build/Sparkle/2.10.0
```

[Log de continuación](evidence/macos-updater-2026-10-18/composition/aggregate-continuation.log). El aggregate normal incluye ahora coordinador, presentación, composición y escenas, que requieren la misma sesión gráfica ya exigida por las pruebas de accesibilidad/arranque. El fixture de adaptador real de 26 casos permanece explícitamente opt-in mediante `test-updater-adapter`; su evidencia de 12 no se repitió por un cambio de wiring.

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
SPARKLE_ARCHIVE=/Users/loomitz/Dev/estrobo-macos-auto-update/.build/Sparkle/Sparkle-2.10.0.tar.xz \
python3 scripts/tests/test_macos_updater_artifacts.py
```

[Suite de artifacts](evidence/macos-updater-2026-10-18/composition/artifacts-suite.log). Evidencia RED/GREEN focal también preservada para constructor, escenas, progreso cero y firma local.

## Límites

Esta composición no instala un build productivo ni demuestra conservación de datos/Keychain a través de un reemplazo real. No acredita radio físico, Installer XPC sandboxed, Developer ID/notarización, autorización, espacio real insuficiente, interrupción de reemplazo, runtime Intel/macOS 13 ni disponibilidad anónima del feed/CDN/assets. El universal demuestra compilación, no ejecución Intel. La prueba de factory sin clave y el smoke aislado tienen identidades y alcances distintos, documentados arriba. Esos gates pendientes y la revisión final siguen en 17; 16 no habilita publicación ni genera credenciales.
