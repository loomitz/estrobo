# Beta pública limitada

Estrobo `0.1.0-beta.4` es la beta pública vigente para una prueba acotada de instalación, actualización, interfaz, controles de barra de menús, Multi global y compatibilidad física en una matriz pequeña de Macs, transmisores, flashes y firmware. No es una afirmación de compatibilidad general con la línea Godox.

## Antes de participar

- Necesitas macOS 13.0 o posterior en Apple Silicon o Intel.
- Necesitas un disparador de flash Godox compatible con Bluetooth integrado y activado. Estrobo se conecta al disparador, no directamente a flashes o receptores.
- Debes poder identificar y restaurar manualmente la configuración de tu transmisor.
- Cierra cualquier otra app conectada: el enlace Bluetooth del radio es exclusivo.
- Conectar significa sobrescribir A0 y los A1 de los grupos configurados con el estado local de Estrobo. No existe importación completa del estado anterior.
- Test puede disparar los grupos que estén activos en el transmisor. Úsalo sólo cuando el entorno físico sea seguro.
- No uses un PIN personal como Código del radio. El protocolo lo transmite por BLE y no ofrece autenticación fuerte.

El DMG público exacto y la app incluida están firmados con Apple Developer ID, notarizados y engrapados por Apple, y aceptados por Gatekeeper. Eso permite verificar su procedencia e integridad, pero no convierte la matriz limitada de hardware en compatibilidad comercial garantizada.

## Descarga e integridad

Usa únicamente estos assets del [prerelease oficial `v0.1.0-beta.4`](https://github.com/loomitz/estrobo/releases/tag/v0.1.0-beta.4):

- `estrobo-v0.1.0-beta.4-macos-universal.dmg`;
- `SHA256SUMS`;
- `estrobo-v0.1.0-beta.4-manifest.json` con versión, firma, notarización y procedencia.

Conserva los tres archivos juntos en Descargas y compruébalos antes de montar el DMG:

```sh
cd ~/Downloads
shasum -a 256 -c SHA256SUMS
```

El DMG y el manifiesto deben mostrar `OK`. Si alguno falla, no abras la app.

El release usa el certificado **Developer ID Application** del equipo `XG96FAV89U`, Hardened Runtime y un sello de tiempo seguro. El certificado público DER está en `release/signing/estrobo-developer-id-application.cer` y el SHA-256 de esos bytes en `release/signing/estrobo-developer-id-application.sha256`. Apple aceptó la notarización y el ticket está adjunto tanto a la app como al DMG para verificación incluso sin conexión. Los archivos `estrobo-beta-signing.*` se conservan sólo como identidad histórica de `beta.1` y `beta.2`.

## Instalar y abrir

1. Abre el DMG verificado.
2. Arrastra `estrobo.app` sobre la carpeta **Applications** que aparece a su lado.
3. Expulsa la imagen de disco y abre Estrobo desde Aplicaciones.
4. Confirma el aviso normal de app descargada si macOS lo presenta y concede acceso a Bluetooth cuando se solicite.

Gatekeeper debe aceptar el DMG de beta 4 y la app como `Notarized Developer ID`; **Abrir de todos modos** no forma parte de esta instalación. Si macOS dice que no puede verificar al desarrollador, no retires la cuarentena ni desactives Gatekeeper: elimina esa copia y vuelve a descargar el asset oficial.

## Identidad local y actualización

Beta 4 usa el identificador `mx.loo.estrobo`, versión `0.1.0` y build `4`. Conserva el mismo bundle identifier de beta 3 y está diseñada para preservar preferencias, biblioteca de transmisores, workspace y presets, pero cada instalación debe confirmar esos valores después de actualizar. El identificador anterior al de las betas públicas pertenecía al prototipo, por lo que no se migran automáticamente radios, códigos, espacios de trabajo ni presets de aquella identidad.

La biblioteca local de transmisores guardados introducida en beta 3 continúa en beta 4. El registro histórico único de `beta.2` migra automáticamente y cada transmisor puede olvidarse por separado. Los transmisores nuevos sólo entran a la biblioteca cuando la persona activa el opt-in y termina autenticación + Sync; nombre, UUID y Código del radio permanecen locales en este Mac.

En una instalación limpia configura:

1. compatibilidad de grupos del transmisor;
2. grupos de trabajo;
3. al menos un modelo de flash por grupo;
4. valores deseados que Estrobo enviará al conectar.

Estrobo no preselecciona grupos ni modelos en el primer inicio y no permite continuar hasta que cada grupo elegido tenga al menos un modelo de flash asignado.

Los grupos nuevos comienzan en Off. Aun así, su A1 completo forma parte de la sincronización para conservarlos apagados.

## Cobertura conocida

La configuración probada físicamente hasta ahora usa un disparador Godox X3Pro con Bluetooth activado y flashes Godox AD400Pro II. Estrobo se conecta al X3Pro; los AD400Pro II se comunican mediante el sistema de radio Godox del propio disparador. No se registraron la variante exacta de cámara ni las revisiones de firmware. Esta evidencia cubre esa combinación concreta y no garantiza otras variantes, flashes o versiones de firmware.

Otros disparadores con Bluetooth que expongan el perfil BLE/GATT de Godox Flash compatible con Estrobo, así como otros flashes del sistema Godox X controlados mediante el disparador, podrían ser compatibles. Estrobo no declara soporte hasta verificar físicamente cada combinación de disparador, flash y firmware. El asset exacto de cada release sigue necesitando el smoke manual definido en el checklist antes de publicarse.

El Bluetooth integrado y activado es obligatorio, pero no suficiente: el disparador también debe exponer el perfil BLE/GATT de Godox Flash compatible con Estrobo. Los flashes y receptores siguen comunicándose por el sistema de radio del disparador y no necesitan Bluetooth.

Pendientes de ampliar mediante pruebas físicas controladas:

- Auto/TTL y su resultado óptico por familia/firmware;
- Beep audible y Standby;
- intensidad fija fuera del punto observado;
- todos los grupos `0–9`/`A–F` que la UI puede configurar;
- reconexión y actualización entre betas en Macs limpios Intel y Apple Silicon.

Beta 4 conserva Multi global como función experimental para grupos compatibles `A–E`: un único botón junto a Beep activa o desactiva la escena, muestra una consola inline y edita potencia en pasos completos hasta `1/4`, conteo y frecuencia. También añade controles compactos opcionales en la barra de menús para los grupos visibles del workspace; comparten el mismo controlador, borradores, modo de envío y sesión Bluetooth que la app completa. El panel presenta un único estado global discreto al actualizar ajustes e incluye Test global con los mismos bloqueos de seguridad de la app completa. Los límites de software, la persistencia y la recuperación tienen pruebas automatizadas, pero Multi continúa **sin validación óptica** hasta observar la secuencia solicitada con el asset exacto y la combinación concreta de transmisor, flashes y firmware. HSS no está disponible en Multi. Tampoco están disponibles el canal global, la compensación TTL no neutra, el cambio de Código del radio, firmware u OAD.

## Qué probar

Sin hardware puedes usar `--mock-radio` para revisar onboarding, biblioteca de transmisores guardados, las tres vistas, entrega Automática/Con botón, interacción, presets, idioma, apariencia, Multi global y recuperación simulada.

Con hardware, sigue únicamente el gate manual coordinado del [Checklist de release](RELEASE-CHECKLIST.md): registra modelo/firmware sin datos personales, empieza con valores reversibles, observa el efecto físico, restaura el baseline y confirma que otra app pueda reconectar. No publiques Códigos del radio, payloads `Psub`/`PWOK`, UUID completos ni capturas con información personal.

## Estado del release

Beta 4 es un **prerelease** público e inmutable. Antes de publicarlo se cerraron
los gates de distribución del artefacto exacto: CI por arquitectura, checksums,
firma, notarización, verificación en Macs limpios y autorización del tag. Las
capacidades que no alcanzaron validación física u óptica continúan identificadas
como tales arriba; el estado del release no amplía esa matriz. Sus assets nunca
deben sustituirse: cualquier corrección requiere una versión nueva.

Las notas canónicas del release en inglés están en [releases/v0.1.0-beta.4.md](releases/v0.1.0-beta.4.md) y su traducción en [releases/v0.1.0-beta.4.es.md](releases/v0.1.0-beta.4.es.md).

## Comentarios y reportes

- Problemas de uso no sensibles: [Soporte](../SUPPORT.md).
- Vulnerabilidades o bypass de las protecciones: [Seguridad](../SECURITY.md).
- Antes de reportar una conexión fallida: [Solución de problemas](TROUBLESHOOTING.md).

Estrobo es un proyecto independiente y no está afiliado oficialmente con Godox.
