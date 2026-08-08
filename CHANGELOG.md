# Historial de cambios

Todos los cambios relevantes de Estrobo se documentan aquí. Mientras el proyecto esté en beta, las interfaces y la matriz de compatibilidad pueden cambiar entre prereleases.

## Sin publicar

No hay cambios acumulados después de `0.1.0-beta.3`.

## 0.1.0-beta.3 — 2026-08-08

### Añadido

- Modo Multi global para grupos `A–E`, con potencia en pasos completos hasta `1/4`, `1–100` destellos, `1–100 Hz` y exposición mínima estimada redondeada hacia arriba a milésimas.
- Persistencia retrocompatible de Multi en espacios de trabajo y presets.
- Secuencia segura A0 → A1, cambios Multi A0-only y restauración fail-closed mediante un journal atómico de A0 + todos los A1 afectados, cubiertos por pruebas deterministas.
- Biblioteca local de transmisores guardados con reconexión por UUID, olvido individual y migración automática del único radio recordado por `beta.2`; los transmisores nuevos sólo se conservan mediante opt-in después de autenticación + Sync.

### Cambiado

- El botón Multi junto a Beep activa o desactiva el sistema y muestra u oculta la consola inline; no abre menú. Canales, Inspector y Matriz eliminan Multi del selector por grupo: los participantes muestran **MULTI · GLOBAL** y los no participantes aparecen desactivados mediante un overlay.
- Multi usa A0 global y una escena A1 exclusiva limitada al workspace: al entrar convierte juntos todos los grupos activos compatibles y mantiene Off a los no participantes. Al salir, todos los grupos del workspace quedan activos en Manual; no se restaura la escena M/TTL/Off previa ni se envía A1 fuera del workspace.
- A0 conserva la potencia Multi efectiva; cada A1 mantiene la potencia Manual de origen o usa `0x32` si venía de TTL.
- Una tanda ya no elimina la recuperación al confirmar un grupo intermedio: conserva la escena completa hasta el último GATT + `FEC8` y puede restaurarla íntegra después de reiniciar.
- Test identifica una secuencia Multi sin presentar la entrega Bluetooth como confirmación óptica.

### Distribución

- Versión `0.1.0`, build `3`, tag `v0.1.0-beta.3`.
- App universal `arm64` + `x86_64` firmada con Apple Developer ID, Hardened Runtime y sello de tiempo seguro; notarización aceptada y ticket adjunto.
- Distribución principal mediante DMG firmado con instalación de arrastrar a Aplicaciones. Gatekeeper acepta tanto el DMG como la app sin **Abrir de todos modos**.
- Certificado público Developer ID y su digest versionados sin incluir P12, claves privadas ni credenciales Apple.
- El carril autosignado queda restringido a reconstrucciones manuales de las betas 1 y 2; no puede procesar beta 3 ni tags posteriores.
- La publicación conserva el release como draft hasta completar CI, verificación del asset exacto, smokes de Macs limpios/hardware y autorización humana.

Consulta las [notas en inglés](docs/releases/v0.1.0-beta.3.md) o la [traducción al español](docs/releases/v0.1.0-beta.3.es.md).

## 0.1.0-beta.2 — 2026-08-06

Primer candidato destinado a publicación pública. `beta.1` permaneció como draft interno y su tag no se movió para conservar procedencia.

### Cambiado

- README canónico en inglés con traducción completa al español y selector recíproco de idioma.
- Portada del README renovada con el icono de Estrobo, descripción más clara e instrucciones seguras para instalar la beta no firmada con Apple Developer ID.
- Compatibilidad aclarada: Estrobo se conecta a disparadores de flash Godox compatibles con Bluetooth integrado y activado, no directamente a flashes o receptores.
- Matriz física documentada: Godox X3Pro con flashes Godox AD400Pro II; otras combinaciones candidatas siguen pendientes de verificación física.
- El modo Multi queda documentado como una función planeada para una versión futura.
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
