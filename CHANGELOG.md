# Historial de cambios

Todos los cambios relevantes de Estrobo se documentan aquí. Mientras el proyecto esté en beta, las interfaces y la matriz de compatibilidad pueden cambiar entre prereleases.

## Sin publicar

- Ningún cambio registrado después de `0.1.0-beta.2`.

## 0.1.0-beta.2 — 2026-08-06

Primer candidato destinado a publicación pública. `beta.1` permaneció como draft interno y su tag no se movió para conservar procedencia.

### Cambiado

- README canónico en inglés con traducción completa al español y selector recíproco de idioma.
- Compatibilidad aclarada: Estrobo se conecta a disparadores de flash Godox compatibles con Bluetooth integrado y activado, no directamente a flashes o receptores.
- El handshake `Psub`/`PWOK` sigue siendo obligatorio; el Código del radio se documenta como PIN local de bajo valor.
- Secuencia Mermaid de Bluetooth corregida para renderizar en GitHub.
- Limpieza del workflow de firma reforzada para retirar del runner la confianza temporal del certificado incluso al fallar o cancelar.

### Distribución

- Versión `0.1.0`, build `2`, tag previsto `v0.1.0-beta.2`.
- Artefacto universal `arm64` + `x86_64`, firma autosignada estable, checksums, manifiesto y attestation generados por el workflow protegido.

Consulta las [notas en inglés](docs/releases/v0.1.0-beta.2.md) o la [traducción al español](docs/releases/v0.1.0-beta.2.es.md).

## 0.1.0-beta.1 — 2026-08-06

Primer candidato de beta pública limitada.

### Añadido

- App macOS local en español e inglés con vistas Canales, Inspector y Matriz.
- Configuración de perfiles, grupos, modelos, visibilidad y presets dentro del sandbox.
- Potencia Manual en pasos de 1/3 EV, M/Auto TTL/Off, modelado, ajuste global, Beep, Standby y Test explícito.
- Modo Automático predeterminado con 700 ms y alternativa **Con botón**.
- Transacciones con token para sliders, bloqueo entre ventanas y envío exclusivo del valor final al soltar.
- **Descartar** durante el plazo de entrega automática.
- Selección de radio con nombre, RSSI y sufijo UUID; protección ante nombres duplicados.
- Modo `--mock-radio` explícito y harness AppKit/SwiftUI de interacción.
- Build universal arm64/x86_64, verificación de release, ZIP, checksums, manifiesto y proceso de attestation.
- CI nativo por arquitectura y workflow de beta draft con aprobación humana.
- Documentación pública de uso, Bluetooth, sincronización, privacidad, seguridad, soporte y release.

### Cambiado

- Bundle identifier definitivo `mx.loo.estrobo`, versión `0.1.0`, build `1`, mínimo macOS 13.0. La nueva identidad no migra preferencias del prototipo.
- Recordar el Código del radio ahora comienza apagado y sólo persiste por opt-in después de `PWOK` + Sync.
- Terminología pública actualizada a **Código del radio** / **Radio code**.
- Conexión inicial completa ahora escribe A0 y todos los A1 configurados antes de mostrar **Listo**.

### Seguridad

- App Sandbox y Bluetooth conservados sin entitlements de red, analítica o telemetría.
- El Código del radio se trata como parámetro local débil: no se registra ni incluye en presets/diagnósticos y no debe reutilizar un PIN personal.
- Escrituras A1 seriales con acuse GATT + `FEC8` y recuperación fail-closed.
- Firma autosignada estable verificada por huella para distribución beta; no es Developer ID ni notarización y no elimina Gatekeeper.

### Limitaciones conocidas

- Sin lectura completa radio → app: conexión y Sync sobrescriben A0/A1 desde el estado local.
- `FEC8` no identifica grupo ni demuestra resultado óptico.
- Compatibilidad física todavía limitada por modelo y firmware.
- Sin edición Multi, canal, compensación TTL no neutra, Código del radio, firmware u OAD.

Consulta las [notas completas](docs/releases/v0.1.0-beta.1.md).
