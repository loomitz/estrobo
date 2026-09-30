# Estrobo · aplicación macOS

Este directorio contiene la aplicación SwiftUI/AppKit, su transporte CoreBluetooth, recursos y pruebas. La guía de instalación y uso está en el [README principal](../../README.md).

## Desarrollo local

Desde la raíz del repositorio:

```sh
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
- Recordar el **Código del radio** comienza apagado. Si se elige, se guarda localmente y sin cifrar después de `PWOK` + Sync; nunca se envía a Internet.
- App Sandbox y Bluetooth permanecen activos, sin red, analítica ni telemetría.
- Las pruebas automatizadas usan transporte falso y códigos sintéticos; no sustituyen los gates físicos de release.

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
