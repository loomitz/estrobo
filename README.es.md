# estrobo

[English](README.md) | **Español**

Control local de transmisores Godox desde macOS. Estrobo organiza grupos de trabajo y permite ajustar potencia, modo, luz de modelado y controles globales desde una app nativa, sin cuenta, backend, analítica ni telemetría.

> [!WARNING]
> Estrobo es un beta público limitado. No está firmado con Developer ID ni notarizado por Apple. Su firma autosignada sólo conserva una identidad consistente entre betas; macOS mostrará una advertencia de Gatekeeper.

![Vista Canales de Estrobo en modo simulado](prototype/GodoxMacControlPrototype/QA/channels-after-dark-final-es.png)

![Configuración local de grupos y modelos](prototype/GodoxMacControlPrototype/QA/workspace-configuration-unified-light-es.png)

## Requisitos

- macOS 13.0 o posterior.
- Mac con Apple Silicon (`arm64`) o Intel (`x86_64`).
- Bluetooth disponible y permiso concedido a Estrobo.
- Un transmisor BLE compatible con el protocolo observado. La cobertura física todavía es limitada; consulta [Beta y compatibilidad](docs/BETA.md).
- Conexión exclusiva: cierra antes cualquier app móvil o de escritorio conectada al transmisor. El radio sólo admite una conexión Bluetooth a la vez.

## Descargar e instalar

1. Descarga `estrobo-<tag>-macos-universal.zip` y `SHA256SUMS` de [GitHub Releases](../../releases). No descargues builds desde issues ni enlaces de terceros.
2. Calcula `shasum -a 256 nombre-del-archivo.zip` y comprueba que coincida con la línea correspondiente de `SHA256SUMS`.
3. Descomprime el ZIP y mueve `estrobo.app` a Aplicaciones.
4. Intenta abrir Estrobo una vez. macOS lo bloqueará porque Apple no ha firmado ni notarizado esta app.
5. Ve a **menú Apple → Configuración del Sistema → Privacidad y seguridad**, baja a **Seguridad**, pulsa **Abrir de todos modos**, autentícate y confirma **Abrir**. Apple mantiene ese botón disponible por un tiempo limitado después del primer intento. No desactives Gatekeeper ni retires la cuarentena del archivo. Consulta el [procedimiento oficial de Apple](https://support.apple.com/guide/mac-help/mh40617/mac).

La advertencia es esperada, pero no prueba que cualquier archivo sea seguro: verifica siempre el checksum y el origen del release.

## Inicio rápido

1. Enciende el transmisor y cierra cualquier otra app conectada a él.
2. Abre Estrobo y configura el perfil, los grupos de trabajo y al menos un modelo de flash por grupo.
3. Pulsa **Buscar**. Elige el radio usando nombre, RSSI y el sufijo de UUID; nombre y UUID ayudan a distinguirlo, pero no lo autentican criptográficamente.
4. Introduce el **Código del radio** de seis dígitos. Es el PIN local de compatibilidad y proximidad del transmisor, no una credencial fuerte ni un secreto de alto valor. No reutilices un PIN personal.
5. La opción para recordarlo comienza apagada. Si la activas, Estrobo lo guarda localmente y sin cifrar sólo después de completar `PWOK` y la sincronización; nunca lo envía a Internet. **Olvidar** elimina radio y código guardados.
6. El handshake BLE sigue siendo obligatorio. Una vez completado, Estrobo actúa como fuente de verdad y sobrescribe deliberadamente el estado global A0 y los A1 de todos los grupos configurados. No importa el estado previo del transmisor.
7. En **Automático**, un cambio se envía 700 ms después del último ajuste. Un arrastre no transmite valores intermedios: el plazo comienza al soltar. También puedes elegir **Con botón** y usar **Enviar ahora** o **Descartar**.

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

- Grupos `0–9` y `A–F` según el perfil; potencia Manual en pasos Godox de 1/3 EV y rango común seguro por modelos asignados.
- M y Auto/TTL, Off, modelado apagado/proporcional/fijo, Beep global, Standby global y Test explícito.
- Ajuste de potencia global con relación entre grupos conservada.
- Vistas Canales, Inspector y Matriz; presets locales; español e inglés; apariencia clara y oscura.
- Entrega automática con debounce de 700 ms o modo **Con botón**.
- Recuperación fail-closed cuando el resultado de una escritura queda incierto.

## Límites importantes

- No existe lectura completa radio → app. **Sync no importa valores: los sobrescribe.**
- `FEC8` no identifica el grupo, no devuelve los valores y no demuestra el resultado óptico.
- Test confirma como máximo la entrega a CoreBluetooth; la persona debe observar el destello.
- La edición de Multi, canal, compensación TTL no neutra, cambio de código, firmware y OAD no está disponible.
- La compatibilidad física varía por transmisor, flash y firmware. Un nombre BLE o UUID no demuestra el modelo ni la autenticidad del radio.

## Documentación y comunidad

- [Cómo funciona](docs/HOW-IT-WORKS.md)
- [Conexión Bluetooth](docs/BLUETOOTH-CONNECTION.md)
- [Sincronización automática](docs/AUTOMATIC-SYNC.md)
- [Beta, instalación y riesgos](docs/BETA.md)
- [Solución de problemas](docs/TROUBLESHOOTING.md)
- [Privacidad](PRIVACY.md)
- [Seguridad](SECURITY.md)
- [Soporte](SUPPORT.md)
- [Contribuir](CONTRIBUTING.md)
- [Historial de cambios](CHANGELOG.md)
- [Avisos de terceros](THIRD-PARTY-NOTICES.md)

Estrobo es un proyecto independiente. No está afiliado, patrocinado, aprobado ni mantenido oficialmente por Godox. Godox y los nombres de sus productos pertenecen a sus respectivos titulares.

Este repositorio no incluye una licencia open-source. La ausencia de licencia es intencional por ahora.
