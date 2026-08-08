<p align="center">
  <img src="prototype/GodoxMacControlPrototype/Resources/Brand/EstroboMark1024.png" width="132" alt="Icono de la app Estrobo">
</p>

<h1 align="center">estrobo</h1>

<p align="center"><strong>Control local y nativo desde macOS para disparadores de flash Godox compatibles con Bluetooth.</strong></p>

<p align="center"><sub>macOS 13+ &nbsp;·&nbsp; Apple Silicon + Intel &nbsp;·&nbsp; Todo permanece local</sub></p>

<p align="center"><a href="README.md">English</a> &nbsp;·&nbsp; <strong>Español</strong></p>

Estrobo reúne los controles de disparadores de flash Godox compatibles en un espacio de trabajo enfocado para Mac. Organiza grupos y ajusta potencia, modo, luz de modelado y controles globales sin cuenta, backend, analítica ni telemetría.

> [!IMPORTANT]
> La beta pública `0.1.0-beta.3` está firmada con Apple Developer ID y notarizada por Apple. Gatekeeper acepta el DMG oficial, por lo que ya no se necesita el procedimiento **Abrir de todos modos** de las betas anteriores. macOS todavía puede mostrar la confirmación normal para una app descargada de Internet y solicitará permiso de Bluetooth en el primer uso.

![Vista Canales de Estrobo en modo simulado](prototype/GodoxMacControlPrototype/QA/channels-after-dark-final-es.png)

## Requisitos

- macOS 13.0 o posterior.
- Mac con Apple Silicon (`arm64`) o Intel (`x86_64`).
- Bluetooth disponible y permiso concedido a Estrobo.
- Un disparador de flash Godox compatible, con Bluetooth integrado y activado, que exponga el perfil BLE/GATT observado por Estrobo. La cobertura física todavía es limitada; consulta [Beta y compatibilidad](docs/BETA.md).
- Conexión exclusiva: cierra antes cualquier app móvil o de escritorio conectada al transmisor. El radio sólo admite una conexión Bluetooth a la vez.

## Estado de compatibilidad

Estrobo se conecta por Bluetooth a un disparador de flash Godox compatible. No se conecta directamente a los flashes ni a los receptores: esos dispositivos continúan comunicándose mediante el sistema de radio Godox del propio disparador y no necesitan Bluetooth.

El Bluetooth integrado debe estar activado, pero tener Bluetooth no garantiza por sí solo la compatibilidad. El disparador debe exponer el perfil BLE/GATT de Godox Flash compatible con Estrobo y el soporte puede variar según modelo y firmware. Un nombre Godox, anuncio BLE o UUID no demuestra compatibilidad.

### Configuración probada físicamente

| Conexión | Hardware probado |
| --- | --- |
| Mac ↔ disparador por Bluetooth | Godox X3Pro con Bluetooth activado |
| Disparador ↔ flashes | Godox AD400Pro II |

Esta es la única matriz de hardware utilizada en pruebas físicas hasta ahora; no se registraron la variante exacta de cámara ni las revisiones de firmware, y no todas las funciones se han validado ópticamente. Otros disparadores con Bluetooth que expongan el perfil BLE/GATT de Godox Flash compatible, y otros flashes del sistema Godox X controlados mediante el disparador, también podrían ser compatibles, pero Estrobo no declara soporte hasta verificar físicamente cada combinación de disparador, flash y firmware.

## Instalar esta beta

1. Descarga `estrobo-v0.1.0-beta.3-macos-universal.dmg`, `SHA256SUMS` y `estrobo-v0.1.0-beta.3-manifest.json` desde el [GitHub Release `0.1.0-beta.3`](https://github.com/loomitz/estrobo/releases/tag/v0.1.0-beta.3). Conserva los tres archivos juntos en Descargas y no uses builds publicados en issues ni enlaces de terceros.
2. Abre Terminal y verifica los archivos del release antes de montar la imagen:

   ```sh
   cd ~/Downloads
   shasum -a 256 -c SHA256SUMS
   ```

   Continúa únicamente si tanto el DMG como el manifiesto muestran `OK`.
3. Haz doble clic en el DMG. En la ventana que se abre, arrastra `estrobo.app` sobre la carpeta **Applications**.
4. Expulsa la imagen de disco de Estrobo y abre la app desde Aplicaciones. Confirma el aviso normal de macOS para una app descargada si aparece y concede acceso a Bluetooth cuando se solicite.

Tanto el DMG oficial como la app que contiene están firmados y notarizados. Si macOS indica que no puede verificar al desarrollador, no eludas Gatekeeper: elimina esa copia, verifica `SHA256SUMS` y vuelve a descargar el asset desde este repositorio.

> **Beta pública actual:** `0.1.0-beta.3` incluye la biblioteca de transmisores guardados y Multi global experimental descritos abajo.

## Inicio rápido

1. Enciende el transmisor y cierra cualquier otra app conectada a él.
2. Abre Estrobo y configura la compatibilidad de grupos, los grupos de trabajo y al menos un modelo de flash por grupo.
3. Pulsa **Buscar**. Elige el radio usando nombre, RSSI y el sufijo de UUID; nombre y UUID ayudan a distinguirlo, pero no lo autentican criptográficamente.
4. Introduce el **Código del radio** de seis dígitos. Es el PIN local de compatibilidad y proximidad del transmisor, no una credencial fuerte ni un secreto de alto valor. No reutilices un PIN personal.
5. La opción para recordarlo comienza apagada. Si la activas, Estrobo añade ese transmisor a su biblioteca local de transmisores guardados sólo después de completar `PWOK` y la sincronización; su código permanece sin cifrar en este Mac y nunca se envía a Internet. **Olvidar** elimina únicamente ese transmisor y código guardados.
6. El handshake BLE sigue siendo obligatorio. Una vez completado, Estrobo actúa como fuente de verdad y sobrescribe deliberadamente el estado global A0 y los A1 de todos los grupos configurados. No importa el estado previo del transmisor.
7. En **Automático**, un cambio se envía 700 ms después del último ajuste. Un arrastre no transmite valores intermedios: el plazo comienza al soltar. También puedes elegir **Con botón** y usar **Enviar ahora** o **Descartar**.
8. En Beta 3, pulsa **MULTI**, junto a Beep, para activar o desactivar Multi global; no abre ningún menú. Al activarlo se muestra la consola inline y todos los grupos activos compatibles pasan juntos a Multi. Los grupos que no participan quedan Off y aparecen desactivados mediante un overlay; desde ahí o desde la consola puedes volver a añadir los compatibles. El último participante sólo se puede cerrar con el botón global. Al desactivar **MULTI**, todos los grupos del workspace —incluidos los que antes estaban Off o en TTL— quedan activos en Manual; no se restaura la escena M/TTL/Off anterior. Los grupos fuera del workspace no reciben A1. Multi excluye HSS; usa **Test** sólo después de revisar los grupos activos y el límite de modelo mostrado, y considera el resultado óptico no validado hasta que la matriz exacta de hardware supere el smoke físico.

Lee [Sincronización automática](docs/AUTOMATIC-SYNC.md) antes de conectar hardware.

## Modo simulado

Para explorar la interfaz sin crear una sesión Bluetooth ni enviar comandos físicos:

```sh
/usr/bin/open -n /Applications/estrobo.app --args --mock-radio
```

Desde un checkout de desarrollo:

```sh
make mac-prototype-build
/usr/bin/open -n prototype/GodoxMacControlPrototype/Build/estrobo.app --args --mock-radio
```

La app muestra **Radio simulado** de forma explícita. Nunca activa este modo como fallback silencioso.

## Qué incluye

- Grupos `0–9` y `A–F` según la compatibilidad seleccionada; potencia Manual en pasos Godox de 1/3 EV y rango común seguro por modelos asignados.
- M, Auto/TTL y Off por grupo; el botón **MULTI** junto a Beep es la única vía para encender o apagar Multi global y muestra su consola inline mientras está activo. Ofrece potencia en pasos completos hasta `1/4`, controles de destellos/frecuencia y participación de grupos `A–E`. Al iniciar, todos los grupos activos compatibles entran juntos; los no participantes quedan Off y aparecen desactivados. Al apagar, todos los grupos de trabajo vuelven activos en Manual. Los grupos fuera del workspace no reciben A1.
- A0 lleva la potencia Multi efectiva, el conteo y los Hz. Un A1 Multi conserva la potencia Manual guardada si el grupo venía de M, o usa `0x32` si venía de TTL; ninguno de esos valores A1 sustituye la potencia Multi global. La exposición mínima estimada es `destellos ÷ Hz`, redondeada siempre hacia arriba a `0.001 s`.
- El dominio editable base de Multi es `1–100` destellos y `1–100 Hz`, pero su máximo efectivo de destellos puede ser menor. Cuando hay un AD400Pro II asignado, Estrobo aplica las filas publicadas por el fabricante de potencia × frecuencia y normaliza el conteo si cambiar la potencia o los Hz reduce ese techo. Como el manual salta de `20–50 Hz` a `60–100 Hz`, Estrobo aplica de forma conservadora este último techo en `51–59 Hz` y marca ese tramo como no publicado, no como verificado. Los demás modelos nunca heredan la tabla del AD400Pro II: la consola marca su límite como no verificado, o parcialmente verificado cuando participan modelos verificados y no verificados. HSS queda excluido.
- Modelado apagado/proporcional/fijo, Beep global, Standby global y Test explícito.
- Ajuste de potencia global con relación entre grupos conservada.
- Biblioteca local de transmisores guardados con reconexión por UUID y olvido individual. El único transmisor recordado por `beta.2` migra automáticamente; cada entrada nueva todavía exige opt-in explícito seguido de autenticación + Sync.
- Vistas Canales, Inspector y Matriz; presets locales; español e inglés; apariencia clara y oscura.
- Entrega automática con debounce de 700 ms o modo **Con botón**.
- Recuperación fail-closed con journal atómico de la escena: conserva A0 y todos los A1 afectados, los reenvía en orden y no borra el lote hasta que cada grupo confirma GATT + `FEC8`.

<details>
<summary><strong>Ver configuración del espacio de trabajo</strong></summary>

![Biblioteca de transmisores guardados en estado vacío](prototype/GodoxMacControlPrototype/QA/saved-transmitters-empty-dark-es.png)

</details>

## Límites importantes

- No existe lectura completa radio → app. **Sync no importa valores: los sobrescribe.**
- `FEC8` no identifica el grupo, no devuelve los valores y no demuestra el resultado óptico.
- Test confirma como máximo la entrega a CoreBluetooth; la persona debe observar el destello o la secuencia Multi. Bluetooth no confirma cuántos destellos ocurrieron.
- El techo de software del AD400Pro II está verificado contra las filas publicadas por el fabricante de potencia × frecuencia; `51–59 Hz` permanece marcado como una inferencia conservadora porque ese intervalo no aparece en la tabla. Ninguno de esos estados demuestra por sí solo el resultado óptico. Multi sigue sin validación óptica hasta que una persona observe la secuencia solicitada. Los límites de cualquier otro modelo quedan explícitamente como no verificados, y el resultado real también puede depender del reciclado, la temperatura y el tiempo de obturación. HSS no es compatible con este flujo.
- No están disponibles el cambio de canal, la compensación TTL no neutra, el cambio de código, firmware u OAD.
- La compatibilidad física varía por transmisor, flash y firmware. Un nombre BLE o UUID no demuestra el modelo ni la autenticidad del radio.

## Planeado

La cobertura de compatibilidad crecerá conforme se validen físicamente Multi y más combinaciones de disparador, flash y firmware.

## Documentación y comunidad

- [Cómo funciona](docs/HOW-IT-WORKS.md)
- [Conexión Bluetooth](docs/BLUETOOTH-CONNECTION.md)
- [Sincronización automática](docs/AUTOMATIC-SYNC.md)
- [Beta, instalación y riesgos](docs/BETA.md)
- [Solución de problemas](docs/TROUBLESHOOTING.md)
- [Privacidad](PRIVACY.md)
- [Seguridad](SECURITY.md)
- [Soporte](SUPPORT.md)
- [Apoya Estrobo en Ko-fi](https://ko-fi.com/loomitz68613)
- [Contribuir](CONTRIBUTING.md)
- [Historial de cambios](CHANGELOG.md)
- [Avisos de terceros](THIRD-PARTY-NOTICES.md)

Estrobo es un proyecto independiente. No está afiliado, patrocinado, aprobado ni mantenido oficialmente por Godox. Godox y los nombres de sus productos pertenecen a sus respectivos titulares.

Este repositorio no incluye una licencia open-source. La ausencia de licencia es intencional por ahora.
