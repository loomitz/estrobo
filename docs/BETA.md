# Beta pública limitada

Estrobo `0.1.0-beta.3` es una prueba pública acotada para validar instalación, actualización, interfaz, Multi global y compatibilidad física en una matriz pequeña de Macs, transmisores, flashes y firmware. No es una afirmación de compatibilidad general con la línea Godox.

## Antes de participar

- Necesitas macOS 13.0 o posterior en Apple Silicon o Intel.
- Necesitas un disparador de flash Godox compatible con Bluetooth integrado y activado. Estrobo se conecta al disparador, no directamente a flashes o receptores.
- Debes poder identificar y restaurar manualmente la configuración de tu transmisor.
- Cierra cualquier otra app conectada: el enlace Bluetooth del radio es exclusivo.
- Conectar significa sobrescribir A0 y los A1 de los grupos configurados con el estado local de Estrobo. No existe importación completa del estado anterior.
- Test puede disparar los grupos que estén activos en el transmisor. Úsalo sólo cuando el entorno físico sea seguro.
- No uses un PIN personal como Código del radio. El protocolo lo transmite por BLE y no ofrece autenticación fuerte.

Esta beta está firmada con Apple Developer ID y notarizada. Eso permite que Gatekeeper verifique su procedencia e integridad, pero no convierte la matriz limitada de hardware en compatibilidad comercial garantizada.

## Descarga e integridad

Usa únicamente los assets del prerelease en GitHub Releases:

- `estrobo-v0.1.0-beta.3-macos-universal.dmg`;
- `SHA256SUMS`;
- `estrobo-v0.1.0-beta.3-manifest.json` con versión, firma, notarización y procedencia.

Conserva los tres archivos juntos en Descargas y compruébalos antes de extraer:

```sh
cd ~/Downloads
shasum -a 256 -c SHA256SUMS
```

El DMG y el manifiesto deben mostrar `OK`. Si alguno falla, no abras la app.

La app usa el certificado **Developer ID Application** del equipo `XG96FAV89U`, Hardened Runtime y un sello de tiempo seguro. El certificado público DER está en `release/signing/estrobo-developer-id-application.cer` y el SHA-256 de esos bytes en `release/signing/estrobo-developer-id-application.sha256`. Apple aceptó la notarización y el ticket está adjunto tanto a la app como al DMG para verificación incluso sin conexión. Los archivos `estrobo-beta-signing.*` se conservan sólo como identidad histórica de `beta.1` y `beta.2`.

## Instalar y abrir

1. Abre el DMG verificado.
2. Arrastra `estrobo.app` sobre la carpeta **Applications** que aparece a su lado.
3. Expulsa la imagen de disco y abre Estrobo desde Aplicaciones.
4. Confirma el aviso normal de app descargada si macOS lo presenta y concede acceso a Bluetooth cuando se solicite.

Gatekeeper debe aceptar el DMG y la app como `Notarized Developer ID`; **Abrir de todos modos** no forma parte de esta instalación. Si macOS dice que no puede verificar al desarrollador, no retires la cuarentena ni desactives Gatekeeper: elimina esa copia y vuelve a descargar el asset oficial.

## Identidad local y actualización

Beta 3 usa el identificador `mx.loo.estrobo`, versión `0.1.0` y build `3`. El identificador anterior pertenecía al prototipo, por lo que no se migran automáticamente radios, códigos, espacios de trabajo ni presets de aquella identidad. La actualización desde `beta.2` conserva el mismo bundle identifier y tiene pruebas automatizadas de migración, pero cada instalación debe confirmar su transmisor guardado y workspace después de actualizar.

Beta 3 sustituye el único radio recordado por una biblioteca local de transmisores guardados. El registro existente de `beta.2` migra automáticamente y cada transmisor puede olvidarse por separado. Los transmisores nuevos sólo entran a la biblioteca cuando la persona activa el opt-in y termina autenticación + Sync; nombre, UUID y Código del radio permanecen locales en este Mac.

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

Beta 3 incluye Multi global como función experimental para grupos compatibles `A–E`: un único botón junto a Beep activa o desactiva la escena, muestra una consola inline y edita potencia en pasos completos hasta `1/4`, conteo y frecuencia. Los límites de software, la persistencia y la recuperación tienen pruebas automatizadas, pero Multi continúa **sin validación óptica** hasta observar la secuencia solicitada con el asset exacto y la combinación concreta de transmisor, flashes y firmware. HSS no está disponible en Multi. Tampoco están disponibles el canal global, la compensación TTL no neutra, el cambio de Código del radio, firmware u OAD.

## Qué probar

Sin hardware puedes usar `--mock-radio` para revisar onboarding, biblioteca de transmisores guardados, las tres vistas, entrega Automática/Con botón, interacción, presets, idioma, apariencia, Multi global y recuperación simulada.

Con hardware, sigue únicamente el gate manual coordinado del [Checklist de release](RELEASE-CHECKLIST.md): registra modelo/firmware sin datos personales, empieza con valores reversibles, observa el efecto físico, restaura el baseline y confirma que otra app pueda reconectar. No publiques Códigos del radio, payloads `Psub`/`PWOK`, UUID completos ni capturas con información personal.

## Estado del release

El proceso de beta 3 prepara primero un release **draft** con el DMG exacto firmado y notarizado. Debe permanecer en draft hasta cerrar CI por arquitectura, checksums, firma, notarización, los smokes aplicables y la autorización humana del tag exacto. Sólo entonces puede publicarse como **prerelease** inmutable. Las versiones futuras deben repetir el mismo orden y nunca sustituir assets después de publicar.

Las notas canónicas en inglés están en [releases/v0.1.0-beta.3.md](releases/v0.1.0-beta.3.md) y su traducción en [releases/v0.1.0-beta.3.es.md](releases/v0.1.0-beta.3.es.md).

## Comentarios y reportes

- Problemas de uso no sensibles: [Soporte](../SUPPORT.md).
- Vulnerabilidades o bypass de las protecciones: [Seguridad](../SECURITY.md).
- Antes de reportar una conexión fallida: [Solución de problemas](TROUBLESHOOTING.md).

Estrobo es un proyecto independiente y no está afiliado oficialmente con Godox.
