# Estrobo · aplicación macOS

Este directorio contiene la aplicación SwiftUI/AppKit, su transporte CoreBluetooth, recursos y pruebas. La guía de instalación y uso está en el [README principal](../../README.md).

## Desarrollo local

Desde la raíz del repositorio:

```sh
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
make mac-prototype-check
make mac-prototype-test
make mac-prototype-build
```

La ejecución normal usa Bluetooth real. Cierra cualquier otra app conectada al transmisor antes de buscarlo.

Para trabajar sin hardware:

```sh
/usr/bin/open -n prototype/EstroboMac/Build/estrobo.app --args --mock-radio
```

`--mock-radio` muestra un radio sintético de forma explícita, no crea un central CoreBluetooth y no envía comandos físicos. Nunca se activa como fallback silencioso.

## Contratos importantes

- El estado local es la fuente de verdad. Después de `PWOK` y Sync técnico, conectar escribe deliberadamente A0 y todos los A1 configurados; no importa el estado del radio.
- Automático sigue siendo predeterminado y usa 700 ms. Un gesto continuo no arma el plazo hasta soltar y sólo transmite el valor final.
- A0 confirma por GATT. Cada A1 confirma por GATT + `FEC8`; `FEC8` no identifica grupo ni demuestra el resultado óptico.
- Recordar el **Código del radio** comienza apagado. Si se elige, se guarda después de `PWOK` + Sync en el Keychain local con accesibilidad `WhenUnlockedThisDeviceOnly`; no se sincroniza entre dispositivos ni se envía a Internet.
- App Sandbox y Bluetooth permanecen activos. Sólo el shell macOS nuevo añade cliente de red para actualizaciones; no añade HTTP al núcleo compartido, analítica ni telemetría. Beta 4 e iOS/iPadOS conservan su comportamiento sin red de la app.
- Las pruebas automatizadas usan transporte falso y códigos sintéticos; no sustituyen los gates físicos de release.

## Actualizador macOS en desarrollo

La nueva implementación utiliza Sparkle 2.10.0 fijado/verificado; check/build descargan la distribución oficial a `.build/Sparkle/2.10.0`, ignorada por Git. Requiere Python 3.12+ y Xcode completo. La firma ad hoc local omite Hardened Runtime para permitir cargar el framework sin Team ID; la distribución Developer ID conserva Hardened Runtime y timestamp obligatorios. Las [guías de firma](../../release/signing/README.md) y [catálogo](../../release/macos-updates/README.md) describen el SHA-256, overrides offline verificados, helpers y entitlements precisos. No se añade Sparkle a SwiftPM compartido ni a iOS.

La raíz pública se recibe externamente mediante `SPARKLE_PUBLIC_ED_KEY`; no hay una raíz de producción suministrada. Una copia de desarrollo sin ella muestra configuración no disponible y la distribución falla antes de firmar. No sustituirla por una raíz de fixture. La comprobación/descarga automáticas empiezan apagadas y buscar manualmente no las activa. La oferta presenta notas firmadas en español/inglés, progreso, cancelación y errores.

Instalar y reiniciar requiere confirmar la oferta exacta y que el transmisor esté desconectado, sin escaneo/conexión ni trabajo que bloquee el cierre. El actualizador reutiliza el criterio de seguridad/persistencia y no aplica, descarta o desconecta por su cuenta. Una salida normal o descarga terminada no autoriza instalar. Al relanzar conserva la identidad `mx.loo.estrobo` y vuelve al espacio de trabajo sin conexión/escritura automática al radio por la actualización.

```sh
make mac-prototype-updater-tools-test
make -C prototype/EstroboMac test-updates
make -C prototype/EstroboMac test-updater-adapter
make -C prototype/EstroboMac test-update-presentation
make -C prototype/EstroboMac test-update-error-recovery
make mac-prototype-universal
```

La aceptación integrada final pertenece al ticket 17. Los gates de raíz/backup, upgrade entre builds Developer ID/notarizados, Intel/macOS mínimo, autorización/recuperación y tráfico/promoción/retirada públicos siguen pendientes. La beta pública vigente sigue siendo `0.1.0-beta.4`, sin actualizador; la primera release que lo incorpore requerirá instalación manual verificada. Consulta [Soporte](../../SUPPORT.md), [Privacy (English)](../../PRIVACY.en.md) y [mantenimiento en español](../../docs/ACTUALIZACIONES-MACOS.md).

## Documentación

- [Cómo funciona](../../docs/HOW-IT-WORKS.md)
- [Conexión Bluetooth](../../docs/BLUETOOTH-CONNECTION.md)
- [Sincronización automática](../../docs/AUTOMATIC-SYNC.md)
- [Checklist de release](../../docs/RELEASE-CHECKLIST.md)
- [Investigación y evidencia histórica](../../docs/research/godox-macos-feasibility.md)
- [Contribuir](../../CONTRIBUTING.md)

No publiques builds, Códigos del radio, payloads de autenticación, APKs, claves, certificados privados ni datos personales.

## Project naming

The macOS application lives in `prototype/EstroboMac`; the Bluetooth proof of concept lives in `prototype/EstroboBLEPoC`. The local repository directory is `estrobo`. Godox names in protocol, device discovery, and capability code identify the supported hardware manufacturer.

Persisted preference keys retain the historical `GodoxMacControlPrototype.*` namespace so existing transmitter libraries, presets, language settings, and pending restorations remain available. The application bundle identifier remains `mx.loo.estrobo`.
