# Compatibilidad de actualizaciones asistidas en Estrobo para macOS

Fecha: 2026-10-14. Investigación AFK para «Determinar qué mecanismos de actualización encajan con Estrobo».
Base local: `91eeeb9f02ca8268dfb1908c4dcd85994c738be4`; rama de investigación `research/estrobo-macos-updater-compatibility`.
Este informe aporta hechos y condiciones para decidir; no selecciona el mecanismo ni implementa el actualizador.

## Resultado para la decisión

**Sparkle 2 es un candidato mantenido y compatible con el sistema operativo y la arquitectura de Estrobo; su configuración automática estándar no cumple el consentimiento por instalación acordado.**
La release estable observada es **2.10.0**, publicada el **2026-09-13T23:54:06Z**, sin marca prerelease; eleva el mínimo a macOS 12.0, por debajo del mínimo 13.0 de Estrobo. [S1], [S2], [L1]

Activar `SUAutomaticallyUpdate` descarga y prepara la instalación silenciosa al salir; `willInstallUpdateOnQuit:immediateInstallationBlock:` **no permite vetar esa instalación**. Su contrato dice: “In either case Sparkle will always attempt to install the update when the app terminates.” [S3], [S4]

**Inferencia:** comprobar que Bluetooth y borradores permiten cerrar no equivale a obtener consentimiento para instalar. Un cierre normal seguro, incluido cerrar la última ventana, podría instalar una actualización preparada sin esa confirmación. El gate actual no implementa consentimiento de actualización. [L2], [L3], [S4]

Recomendación técnica para la siguiente decisión: evaluar Sparkle primero por su instalación, validación y soporte sandbox, pero conservar como condición abierta la separación real entre descarga automática e instalación autorizada. Un `SPUUserDriver` personalizado, por sí solo, **no demuestra** esa separación. [S5], [S6]

## Método y límites

- **Verificado:** documentación y código oficiales de Sparkle, incluyendo el tag `2.10.0`; documentación Apple; lectura de los archivos locales citados en la base indicada.
- **Inferencia:** estimaciones de mantenimiento, diseño de la adaptación al Makefile y consecuencias del contrato actual. Se identifican expresamente.
- **Pendiente de prototipo:** compatibilidad del binario concreto, permisos reales, salida cancelada, recuperación y consentimiento en todos los caminos.
- No se descargó el framework binario ni el DMG de Estrobo, no se compiló, no se firmó, no se accedió a credenciales, no se ejecutó la app y no se operaron radios.
- La evidencia es temporal: verificar de nuevo la versión estable y los avisos de seguridad antes de fijar una dependencia o distribuirla.

## Comparación de mecanismos

| Mecanismo | Detectar y descargar | Instalar desde la app | Adecuación y coste inferido |
| --- | --- | --- | --- |
| Sparkle 2.10.0 estándar | Sí; comprobación manual, programada y descarga automática | Sí; auxiliares, permisos y validaciones propios | Menor superficie propia de instalación; incumple consentimiento por instalación con automatización estándar. [S2], [S3], [S4] |
| Sparkle con coordinación específica de consentimiento | Capacidades presentes; separación exacta pendiente | Sí, condicionada al diseño y su prueba | Candidato; un user driver controla presentación/respuestas, pero no basta con retener el botón de reinicio. [S5], [S6] |
| Actualizador propio completo | Factible usando APIs de red y lógica propia | Exige resolver reemplazo, auxiliares, firma, permisos y reinicio | Mayor coste y riesgo inferidos: se asume responsabilidad sobre seguridad y recuperación que Sparkle ya implementa. [S2], [A1], [A2] |
| Comprobación y enlace a DMG manual | Sí para detectar; descarga por navegador | No: el usuario reemplaza la app | Fallback útil, coste menor inferido; satisface aviso, pero no el destino de actualización desde la app. [L4] |

La comparativa no acredita una implementación propia ni promete estimaciones de plazo. La decisión humana sigue abierta.

## Compatibilidad e integración con el Makefile

Sparkle 2.10.0 requiere macOS 12.0. Su configuración conserva arquitecturas estándar y contempla explícitamente `x86_64`; Estrobo construye `arm64` y `x86_64` por separado y combina el ejecutable con `lipo`. **Inferencia:** no hay conflicto de plataforma declarado; no se han verificado las slices del framework distribuido. [S1], [S7], [L1]

Sparkle documenta inicialización programática en SwiftUI y sistemas externos: enlazar `Sparkle.framework`, proporcionar búsqueda del framework y runtime, copiarlo a `Contents/Frameworks/` preservando enlaces simbólicos y declarar feed/clave/versiones. No exige migrar la app a un proyecto Xcode. [S8], [A2]

**Inferencia de adaptación, no código aprobado:** añadir `-F` y `-framework Sparkle` en typecheck y compilación de ambas slices; traducir el rpath al formato aceptado por `swiftc` y comprobar la ruta relativa desde `Contents/MacOS`; copiar una única distribución universal del framework antes de firmar. Validar referencias con `otool`; no copiar literalmente flags de clang a Swift. [S8], [L1]

El Makefile actual firma el bundle externo y no contiene una fase de copia/firma de Sparkle y auxiliares. Incorporarlo exige firma de componentes de dentro hacia fuera y después del bundle principal, antes de notarizar. `codesign --deep` utilizado para **verificar** no sustituye la firma explícita de componentes. [L1], [A4], [A1]

Hay dos bloqueos locales concretos de validación:

1. `verify-macos-bundle-contents.sh` prohíbe headers, `.app` anidadas y cualquier ejecutable adicional al principal. Un framework con auxiliares no pasa esa política. [L5]
2. `verify-macos-developer-id-signature.sh` exige exactamente App Sandbox y Bluetooth; las excepciones Mach de Sparkle, y opcionalmente red, serían rechazadas. [L6], [S9]

**Inferencia:** habrá que diseñar allowlists acotadas para el framework/auxiliares y sus entitlements, preservando los controles de contenido y firma. Desactivar globalmente esas verificaciones no es una integración equivalente.

## Sandbox, red y auxiliares

Para una app sandboxed, Sparkle requiere `Installer.xpc`, `SUEnableInstallerLauncherService=YES` y excepciones `mach-lookup.global-name` para `<bundle-id>-spks` y `<bundle-id>-spki`. El Makefile no tiene la sustitución automática de Xcode: los valores efectivos serían `mx.loo.estrobo-spks` y `mx.loo.estrobo-spki`, que deben comprobarse tras firmar. [S9], [L1], [L7]

Dos alternativas documentadas para red:

- Conceder `com.apple.security.network.client` a Estrobo y no habilitar `Downloader.xpc`.
- Conservar la app principal sin ese entitlement y habilitar `SUEnableDownloaderService=YES`. El downloader distribuido no está sandboxed desde 2.6; aislarlo con sandbox requiere construir Sparkle desde fuente con identificador propio. [S9]

El downloader separado tiene limitaciones de notas: utiliza `WebView` legado, no adapta notas por versión instalada y puede tener problemas con contenido externo. **Inferencia:** texto integrado sin recursos remotos reduce superficie y peticiones, pero la elección de red/auxiliar sigue abierta. [S9], [S10]

Fuera de Archive/Export, firmar servicios, `Autoupdate`, `Updater.app` y framework explícitamente, preservando entitlements propios del downloader; evitar `--deep` para firmar. [S9]

Apple exige firmas válidas para todos los ejecutables distribuidos, Developer ID, Hardened Runtime, timestamp seguro y ausencia de `get-task-allow=true` para la notarización. El nuevo bundle con sus auxiliares necesita evidencia propia; la notarización de beta 4 no lo valida. [A1], [L4]

## Consentimiento, descarga e instalación

Sparkle separa comprobar de descargar mediante `automaticallyChecksForUpdates` y `automaticallyDownloadsUpdates`, y ofrece `checkForUpdates` manual. Los valores se persisten; no se deben sobreescribir en cada arranque. La segunda propiedad activa el camino de actualización automática, no una caché de descarga aislada de instalación. [S11], [S3]

El permiso estándar se presenta en el segundo lanzamiento si no se define `SUEnableAutomaticChecks`; definirlo evita la pregunta. El prompt puede ofrecer descarga **e instalación** automática. **Inferencia:** la explicación y las preferencias de Estrobo requieren copy y controles que reflejen su contrato, sin activar accidentalmente esa opción conjunta. [S3], [S11]

La evidencia del tag 2.10.0 permite acotar el problema:

- `SPUAutomaticUpdateDriver` descarga automáticamente y, una vez preparado, llama al callback de instalación al salir; no utiliza el user driver para pedir una decisión en cada descarga. [S12]
- `SPUCoreBasedUpdateDriver.downloadDriverDidDownloadUpdate:` continúa con extracción; no hay un callback público de aprobación de extracción en ese punto mostrado por este flujo. [S13]
- `SPUUserDriver.showReadyToInstallAndRelaunch:` documenta que, si la app termina por su cuenta, Sparkle intentará instalar. Responder `Dismiss` tampoco cancela necesariamente la instalación; `Skip` en esa fase cancela el intento. [S5]
- `shouldPostponeRelaunchForUpdate:untilInvokingBlock:` sirve para posponer un reinicio solicitado, pero no se llama en todos los caminos; el contrato excluye casos sin relaunch y ciertas reanudaciones. [S4]

**Consecuencia verificada:** activar la descarga automática estándar y añadir una confirmación sólo al reiniciar no satisface el requisito confirmado.

**Límite de la conclusión:** no se ha probado que sea imposible construir la experiencia con Sparkle. Sí se ha comprobado que los interruptores estándar y el callback de relaunch no garantizan esa experiencia. Tampoco debe prometerse que un user driver personalizado por sí solo lo resuelva. El mantenedor advierte contra forzar descarga automática mediante respuestas del user driver. [S14]

**Preguntas concretas para prototipo/diseño:** ¿se autoriza una instalación específica antes de preparar su instalador? ¿puede una coordinación propia mantener sólo una descarga validada sin armar install-on-quit y después entregarla a un camino soportado de Sparkle? Si no existe una integración pública mantenible, decidir explícitamente entre cambiar el momento de descarga o asumir más código propio; no relajar silenciosamente el consentimiento.

## Protección del cierre y operaciones Bluetooth

AppKit permite cancelar o diferir terminación en `applicationShouldTerminate(_:)`. Estrobo devuelve `.terminateCancel` cuando su controlador indica sincronización, aplicación, Test pendiente, edición interactiva, debounce, recuperación o borradores resolubles; la última ventana también pide terminar la app. [A3], [L2], [L3]

Sparkle documenta envío de un evento de quit y que la app puede retrasarlo o cancelarlo; su user driver puede volver a intentar la terminación. El callback de aplazamiento ofrece una segunda oportunidad de coordinar el reinicio. **Inferencia:** mantener el delegado existente y consultar el mismo gate antes de confirmar instalación es una integración plausible; requiere demostrarla. [S6], [S4]

No se encontró evidencia de que Sparkle tenga que saltarse el veto AppKit. El riesgo señalado aquí es distinto: **cuando el gate permite salir, el instalador preparado puede actuar sin un consentimiento de instalación específico**. No presentar ese riesgo como bypass demostrado de la seguridad Bluetooth. [L2], [L3], [S4], [S5]

El consentimiento debe invalidarse o revalidarse si aparece nuevo trabajo antes de la salida. La prueba necesita cubrir doble click, cancelar terminación, reintentar y cierre normal posterior, sin descartar borradores ni interrumpir una orden física. Esto es un criterio de diseño inferido de las preferencias y el gate, no conducta ya implementada.

## Datos transmitidos y desactivación

El `User-Agent` predeterminado incluye nombre/versión visible de la app y versión de Sparkle; puede personalizarse. `httpHeaders` se aplica a feed, notas y archivo; `feedParametersForUpdater:sendingSystemProfile:` puede añadir parámetros propios independientemente del perfil. [S11], [S18]

El perfil opcional incluye versión de macOS, CPU, modelo, cores, velocidad, RAM, nombre/versión de app e idioma; viaja como query GET, como máximo semanalmente. `SUEnableSystemProfiling` está desactivado por defecto. [S15], [S3]

Para el contrato «sin analítica/telemetría», propuesta técnica pendiente de decisión: mantener `SUEnableSystemProfiling=NO`, `sendsSystemProfile=false`, no ofrecer habilitar perfil, no añadir parámetros identificadores y devolver una lista vacía de claves de perfil como defensa adicional. El prompt estándar sólo ofrece perfil si la clave plist lo habilita. [S11], [S16], [S18]

**Inferencia:** desactivar el perfil no oculta al proveedor la IP, URLs, fecha, tráfico y cabeceras normales. Feed, notas, archivo y sus redirecciones pueden tener proveedores distintos. Deben inventariarse con el hosting elegido; aquí no se capturó tráfico ni se verificó retención de proveedores. [S17]

Notas integradas, JavaScript deshabilitado y ausencia de recursos remotos son candidatos para minimizar peticiones. No se acredita «cero red» con un actualizador habilitado. Desactivar comprobaciones automáticas debe persistir y no impedir la acción manual explícita. [S3], [S11], [S10]

## Canales y orden de versiones

`allowedChannelsForUpdater:` admite un conjunto vacío para sólo el canal por defecto; incluir `beta` agrega ese canal y conserva el defecto siempre. Por tanto, feed con estables sin etiqueta y betas con `sparkle:channel=beta` expresa las preferencias acordadas. [S18]

Sparkle compara `CFBundleVersion`, no el tag de GitHub ni la marca prerelease de una release. Estrobo declara `0.1.0`/`4` y su Makefile genera `v$(VERSION)-beta.$(BUILD_NUMBER)` por separado. **Inferencia:** hace falta un orden de builds creciente que abarque canales y deje a una estable posterior superar sus betas. [S10], [L1], [L7]

El comparador personalizado está deprecated y el comparador estándar puede seguir usándose al instalar para impedir downgrades. Evitar depender de un comparador propio para «volver a estable». Cambiar canales no obliga a instalar una versión más antigua. [S4]

La decisión de numeración, política beta→estable, feed y rollback vive en otros tickets. Este informe sólo acredita las capacidades y su límite; no fija esos contratos.

## Criterios para el prototipo y la validación posterior

Los puntos 1–2 orientan el prototipo de diseño y la investigación de API: estados, consentimiento y gate de cierre. Una simulación puede validar interacción, pero no demuestra el comportamiento del instalador real. Los puntos 3–6 son gates de una implementación futura con artefactos reales; este mapa no autoriza compilar, notarizar, instalar ni publicar.

1. Demostrar una descarga automática terminada seguida de cierre normal, cierre de última ventana y relanzamiento, **sin instalar si no hubo confirmación para esa actualización**. Repetir después de cancelar la confirmación y después de reiniciar el sistema.
2. Demostrar instalación autorizada con veto del gate por cada estado bloqueante; mantener la app abierta y permitir reintento tras resolverlo, sin cerrar por fuerza.
3. Probar instalación en `/Applications` del usuario, propiedad/permisos que requieran autorización, ejecución desde DMG sólo lectura, app translocada y errores de red/firmas. Sparkle advierte que no siempre avisa automáticamente de imposibilidad de actualizar. [S10]
4. Comprobar arm64 e Intel, dependencias autocontenidas, entitlements efectivos y firma/notarización de todos los auxiliares de dos builds de prueba. La inspección documental no sustituye esas evidencias.
5. Capturar destinos y datos de red con perfil desactivado; desactivar automáticos, relanzar y comprobar que sólo una acción manual provoca comprobación.
6. Probar canales y comparación sobre builds reales; mantener un bootstrap manual para instalaciones beta 4 que no incluyen actualizador. [L4]

## Fuentes primarias

Las referencias Sparkle de código fijan el tag investigado; las páginas de documentación pueden evolucionar.

[S1]: https://github.com/sparkle-project/Sparkle/releases/tag/2.10.0
[S2]: https://github.com/sparkle-project/Sparkle/blob/2.10.0/README.markdown
[S3]: https://sparkle-project.org/documentation/customization/
[S4]: https://github.com/sparkle-project/Sparkle/blob/2.10.0/Sparkle/SPUUpdaterDelegate.h
[S5]: https://github.com/sparkle-project/Sparkle/blob/2.10.0/Sparkle/SPUUserDriver.h
[S6]: https://sparkle-project.org/documentation/api-reference/Protocols/SPUUserDriver.html
[S7]: https://github.com/sparkle-project/Sparkle/blob/2.10.0/Configurations/ConfigCommon.xcconfig
[S8]: https://sparkle-project.org/documentation/programmatic-setup/
[S9]: https://sparkle-project.org/documentation/sandboxing/
[S10]: https://sparkle-project.org/documentation/
[S11]: https://github.com/sparkle-project/Sparkle/blob/2.10.0/Sparkle/SPUUpdater.h
[S12]: https://github.com/sparkle-project/Sparkle/blob/2.10.0/Sparkle/SPUAutomaticUpdateDriver.m
[S13]: https://github.com/sparkle-project/Sparkle/blob/2.10.0/Sparkle/SPUCoreBasedUpdateDriver.m
[S14]: https://github.com/sparkle-project/Sparkle/discussions/2452
[S15]: https://sparkle-project.org/documentation/system-profiling/
[S16]: https://github.com/sparkle-project/Sparkle/blob/2.10.0/Sparkle/SUUpdatePermissionPrompt.m
[S17]: https://github.com/sparkle-project/Sparkle/blob/2.10.0/Sparkle/SPUDownloadDriver.m
[S18]: https://sparkle-project.org/documentation/api-reference/Protocols/SPUUpdaterDelegate.html
[A1]: https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution
[A2]: https://developer.apple.com/documentation/bundleresources/placing-content-in-a-bundle
[A3]: https://developer.apple.com/documentation/appkit/nsapplicationdelegate/applicationshouldterminate(_:)
[A4]: https://developer.apple.com/library/archive/technotes/tn2206/
[L1]: https://github.com/loomitz/estrobo/blob/91eeeb9f02ca8268dfb1908c4dcd85994c738be4/prototype/EstroboMac/Makefile
[L2]: https://github.com/loomitz/estrobo/blob/91eeeb9f02ca8268dfb1908c4dcd85994c738be4/prototype/EstroboMac/Sources/AppTerminationSafety.swift
[L3]: https://github.com/loomitz/estrobo/blob/91eeeb9f02ca8268dfb1908c4dcd85994c738be4/prototype/EstroboMac/Sources/PrototypeAppDelegate.swift
[L4]: https://github.com/loomitz/estrobo/blob/91eeeb9f02ca8268dfb1908c4dcd85994c738be4/README.md
[L5]: https://github.com/loomitz/estrobo/blob/91eeeb9f02ca8268dfb1908c4dcd85994c738be4/scripts/verify-macos-bundle-contents.sh
[L6]: https://github.com/loomitz/estrobo/blob/91eeeb9f02ca8268dfb1908c4dcd85994c738be4/scripts/verify-macos-developer-id-signature.sh
[L7]: https://github.com/loomitz/estrobo/blob/91eeeb9f02ca8268dfb1908c4dcd85994c738be4/prototype/EstroboMac/Info.plist
