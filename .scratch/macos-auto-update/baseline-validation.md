# Baseline de implementación

Fecha: 2026-10-17. Base origin/main `68ea6fc` (árbol igual al baseline de spec `91eeeb9`). Arquitectura arm64; macOS 27.0.1 (26A434); Xcode 27.0 (27A5228h), Swift 6.4 (swiftlang-6.4.0.27.1).

Todos los comandos siguientes usan `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer`:

- `swift test --parallel`: PASS, 67 tests XCTest compartidos. Logs locales `/private/tmp/estrobo-updater-baseline-swift-xcode.log`.
- `make -C prototype/EstroboMac test-session-recovery test-workspace-chrome test-interactive-editing test-localization test-secure-persistence`: PASS. Log `/private/tmp/estrobo-updater-baseline-macos-xcode.log`.
- `make mac-prototype-developer-id-tools-test`: PASS, incluye 32 casos DMG aislados, candidate/source/approval. Log `/private/tmp/estrobo-updater-baseline-release-tools.log`. Son fixtures, no firma/notarización real.

El primer intento con xcode-select predeterminado (Command Line Tools) falló por ausencia de XCTest y plugin SwiftUIMacros; entorno corregido usando Xcode completo, sin cambiar xcode-select global ni código del producto.

Sin radio físico ni datos del usuario. Estos resultados son baseline de regresión, no evidencia de instalación de Sparkle, firma/notarización o publicación.

Exploración de integración: `/private/tmp/estrobo-updater-implementation-notes.md` (notas fuera del repositorio). Primer gate sigue siendo el ticket 10.
