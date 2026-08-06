# Beta pública limitada

Estrobo `0.1.0-beta.2` es una prueba pública acotada para validar instalación, actualización, interfaz y compatibilidad física en una matriz pequeña de Macs, transmisores, flashes y firmware. No es una afirmación de compatibilidad general con la línea Godox.

## Antes de participar

- Necesitas macOS 13.0 o posterior en Apple Silicon o Intel.
- Necesitas un disparador de flash Godox compatible con Bluetooth integrado y activado. Estrobo se conecta al disparador, no directamente a flashes o receptores.
- Debes poder identificar y restaurar manualmente la configuración de tu transmisor.
- Cierra cualquier otra app conectada: el enlace Bluetooth del radio es exclusivo.
- Conectar significa sobrescribir A0 y los A1 de los grupos configurados con el estado local de Estrobo. No existe importación completa del estado anterior.
- Test puede disparar los grupos que estén activos en el transmisor. Úsalo sólo cuando el entorno físico sea seguro.
- No uses un PIN personal como Código del radio. El protocolo lo transmite por BLE y no ofrece autenticación fuerte.

Si necesitas una herramienta con firma Developer ID, notarización Apple o compatibilidad comercial garantizada, este beta no cumple esos requisitos.

## Descarga e integridad

Usa únicamente los assets del prerelease en GitHub Releases:

- `estrobo-<tag>-macos-universal.zip`;
- `SHA256SUMS`;
- `estrobo-<tag>-manifest.json` con versión/procedencia;
- attestation del artefacto cuando GitHub la muestre.

Calcula el digest local y compáralo antes de extraer:

```sh
shasum -a 256 nombre-del-archivo.zip
```

El resultado debe coincidir exactamente con la línea del ZIP en `SHA256SUMS`. GitHub también permite verificar attestations con `gh attestation verify`; sigue la [documentación oficial de GitHub](https://docs.github.com/actions/how-tos/secure-your-work/use-artifact-attestations/use-artifact-attestations) y especifica este repositorio como origen.

La firma del bundle es autosignada y estable, independiente de Apple. El certificado público DER está en `release/signing/estrobo-beta-signing.cer` y el SHA-256 de esos bytes en `release/signing/estrobo-beta-signing.sha256`. Sirve para detectar un cambio de identidad entre betas y probar la actualización N→N+1, pero no crea confianza de Gatekeeper, no sustituye Developer ID y no implica revisión de Apple. Nadie debe instalar ni marcar como confiable manualmente el certificado autosignado.

## Abrir de todos modos

La advertencia de Gatekeeper es esperada:

1. Intenta abrir `estrobo.app` desde Aplicaciones.
2. Tras el bloqueo, abre **menú Apple → Configuración del Sistema → Privacidad y seguridad**.
3. Baja a **Seguridad** y pulsa **Abrir de todos modos**.
4. Autentícate y confirma **Abrir**.

Apple indica que la opción aparece durante un tiempo limitado después del primer intento. Consulta [Abrir una app anulando la configuración de seguridad](https://support.apple.com/guide/mac-help/mh40617/mac). No desactives Gatekeeper de forma global, no retires la cuarentena y no confíes manualmente en el certificado.

## Primer inicio limpio

El beta usa el identificador `mx.loo.estrobo`, versión `0.1.0` y build `2`. El identificador anterior pertenecía al prototipo. El cambio crea una identidad limpia de preferencias y contenedor antes de incorporar participantes públicos; no se migran automáticamente radios, códigos, espacios de trabajo ni presets del prototipo.

La primera vez configura:

1. perfil del transmisor;
2. grupos de trabajo;
3. al menos un modelo de flash por grupo;
4. valores deseados que Estrobo enviará al conectar.

Los grupos nuevos comienzan en Off. Aun así, su A1 completo forma parte de la sincronización para conservarlos apagados.

## Cobertura conocida

La investigación y las pruebas locales confirman el codec, CRC, máquina de estados y la secuencia BLE observada. Históricamente, un enlace físico permitió completar `PWOK`, Sync y cambios reversibles A1 de potencia y modelado fijo al 25% con acuse GATT + `FEC8` en un transmisor `GDBH-*` cuyo modelo comercial y firmware exactos no quedaron registrados. Esa evidencia no identifica ni garantiza todas las combinaciones de transmisor, flash o firmware.

El Bluetooth integrado y activado es obligatorio, pero no suficiente: el disparador también debe exponer el perfil BLE/GATT de Godox Flash compatible con Estrobo. Los flashes y receptores siguen comunicándose por el sistema de radio del disparador y no necesitan Bluetooth.

Pendientes de ampliar mediante pruebas físicas controladas:

- Auto/TTL y su resultado óptico por familia/firmware;
- Beep audible y Standby;
- intensidad fija fuera del punto observado;
- todos los grupos `0–9`/`A–F` que la UI puede configurar;
- reconexión y actualización entre betas en Macs limpios Intel y Apple Silicon.

No están disponibles: edición Multi, canal global, compensación TTL no neutra, cambio de Código del radio, firmware u OAD.

## Qué probar

Sin hardware puedes usar `--mock-radio` para revisar onboarding, las tres vistas, entrega Automática/Con botón, interacción, presets, idioma, apariencia y recuperación simulada.

Con hardware, sigue únicamente el gate manual coordinado del [Checklist de release](RELEASE-CHECKLIST.md): registra modelo/firmware sin datos personales, empieza con valores reversibles, observa el efecto físico, restaura el baseline y confirma que otra app pueda reconectar. No publiques Códigos del radio, payloads `Psub`/`PWOK`, UUID completos ni capturas con información personal.

## Estado del release

El workflow crea primero un release **draft**. Debe quedarse así si falta CI, una arquitectura, verificación de firma/checksum/attestation, aprobación del environment `public-beta`, un Mac limpio o cualquier smoke físico requerido. La variable protegida `PUBLIC_BETA_SMOKE_APPROVED_TAG` debe coincidir exactamente con el tag que se intenta publicar; una aprobación de otro tag no sirve. Sólo después puede publicarse como **prerelease**.

Las notas canónicas en inglés están en [releases/v0.1.0-beta.2.md](releases/v0.1.0-beta.2.md) y su traducción en [releases/v0.1.0-beta.2.es.md](releases/v0.1.0-beta.2.es.md).

## Comentarios y reportes

- Problemas de uso no sensibles: [Soporte](../SUPPORT.md).
- Vulnerabilidades o bypass de las protecciones: [Seguridad](../SECURITY.md).
- Antes de reportar una conexión fallida: [Solución de problemas](TROUBLESHOOTING.md).

Estrobo es un proyecto independiente y no está afiliado oficialmente con Godox.
