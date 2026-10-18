# Prueba del adaptador real

Este fixture compila los mismos `UpdateService.swift`, `UpdateHTTPClient.swift`, `UpdateInstallationLifecycle.swift` y `SparkleUpdateService.swift` del producto. Usa Sparkle 2.10.0 oficial, catálogo y DMG firmados con una raíz efímera, ventanas AppKit y eventos `NSEvent` reales para botones, Cmd-Q y cierre de última ventana. No usa `URLProtocol`, servicio falso ni callbacks de instalador simulados.

Desde la raíz del repo, con Xcode completo y escritorio macOS iniciado:

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
  make -C prototype/EstroboMac test-updater-adapter
```

Para una distribución oficial ya descargada y verificada:

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
  python3 prototype/MacUpdaterAdapterCheck/run.py \
  --sparkle /ruta/Sparkle \
  --sparkle-archive /ruta/Sparkle-2.10.0.tar.xz \
  --output /tmp/estrobo-real-adapter-evidence
```

El runner vuelve a verificar archivo y árbol extraído con `scripts/macos-updater-artifacts.py`. Crea una identidad única y una app propia en un directorio temporal, construye cuatro bundles y tres DMG, hace una instalación real build 1 → 2 y termina exclusivamente sus procesos/servidores/montajes identificados. La clave privada efímera queda fuera del directorio servido y se elimina mediante el propietario de recursos compartido con `MacUpdaterConsentSpike`. No accede a Keychain, apps del usuario ni radio. Los builds 1/2/4/5 son números de fixture, sin reservar releases.

`results.json`, `requests.json`, `events.log`, `artifact.json` y los snapshots JSON de controles conservan el resultado y la identidad de los bytes compilados. El host intenta también `NSView.cacheDisplay`; en macOS27 esa captura puede ser negra. No usar esos PNG como evidencia visual sin inspeccionarlos. El reporte durable excluye los PNG vacíos observados; los eventos y decisiones de AppKit acreditan comportamiento, no apariencia, VoiceOver ni contraste de la UI final.

`ESTROBO_UPDATER_TESTING` habilita sólo la factory loopback y pausas del host en puntos reales de cierre. El binario normal no tiene factory loopback, override de feed, pausas ni excepciones ATS. El fixture ad hoc no tiene App Sandbox y no acredita distribución Developer ID/notarizada, helper sandboxed, Intel o runtime macOS13. Esos gates y el feed público se validan por separado antes de distribuir.
