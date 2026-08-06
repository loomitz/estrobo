# Política de seguridad

## Versiones con soporte

| Versión | Soporte de seguridad |
| --- | --- |
| `0.1.x` beta más reciente | Sí |
| Betas anteriores | Sólo para confirmar si el problema sigue presente |
| Builds de prototipo o locales | No como distribución pública |

Durante el beta, actualiza a la versión más reciente antes de reportar. Un release draft no cuenta como versión publicada.

## Reportar una vulnerabilidad

Usa exclusivamente **GitHub Private Vulnerability Reporting**:

1. Abre la pestaña **Security** de este repositorio.
2. Entra en **Advisories**.
3. Pulsa **Report a vulnerability** y envía el reporte privado.

GitHub documenta este canal en [Privately reporting a security vulnerability](https://docs.github.com/en/code-security/how-tos/report-and-fix-vulnerabilities/report-privately).

No abras un issue público para una vulnerabilidad. Si el botón privado no aparece, abre como máximo un issue de soporte que diga que el canal privado no está disponible, sin incluir detalles de la vulnerabilidad, y espera a que se habilite. No existe un email de seguridad publicado.

Incluye de forma privada:

- versión/build de Estrobo, macOS y arquitectura;
- impacto y condiciones necesarias;
- pasos mínimos de reproducción, preferentemente con `--mock-radio`;
- si aplica, modelo/firmware sin UUID completo ni información personal;
- evidencia redactada y una propuesta de mitigación si la tienes.

Nunca incluyas un Código del radio real, payload `Psub`/`PWOK`, token, private key, P12, password de secret, certificado privado, datos personales o un comando que pueda disparar equipo sin advertencia.

## Modelo de seguridad

Estrobo reduce su superficie al enlace local:

- App Sandbox activo;
- entitlement Bluetooth;
- sin entitlement de red, cuenta, backend, analítica o telemetría;
- snapshots, preferencias y recuperación dentro del contenedor local;
- Test sólo mediante acción explícita y sin reintento automático;
- writes A1 seriales con recuperación fail-closed.

Estas propiedades no convierten el protocolo BLE en un canal autenticado de forma fuerte.

## Riesgos aceptados y límites

### Código del radio

El Código del radio es un parámetro de compatibilidad/proximidad. Viaja en el protocolo Godox y no protege una cuenta o servicio. Si se recuerda, se guarda localmente y sin cifrar sólo por opt-in. No debe reutilizarse un PIN personal.

Estrobo no añade criptografía casera, pairing obligatorio ni soporte de código vacío sin evidencia física. `PWOK`, `Psub` y el protocolo BLE observado se conservan compatibles.

### Identidad del dispositivo

Nombre, RSSI y UUID reducen errores, pero no prueban criptográficamente que un periférico sea legítimo. Los nombres duplicados requieren selección humana y el UUID guardado sólo es una preferencia estable de CoreBluetooth.

### Acuses y resultado físico

GATT confirma transporte, no el efecto óptico. `FEC8` no identifica grupo ni devuelve el estado aplicado. Un resultado incierto exige reconectar el mismo UUID y recuperar; no se trata como éxito.

### Distribución

El beta no usa Developer ID ni notarización. El certificado autosignado estable ayuda a detectar cambios de identidad entre betas, pero no establece confianza Apple y no elimina Gatekeeper. Nunca instales ni confíes manualmente en ese certificado.

Verifica siempre:

```sh
shasum -a 256 nombre-del-archivo.zip
codesign --verify --deep --strict --verbose=2 /ruta/a/estrobo.app
lipo /ruta/a/estrobo.app/Contents/MacOS/estrobo -verify_arch arm64 x86_64
```

Compara el digest con `SHA256SUMS` del mismo GitHub Release y la identidad con `release/signing/estrobo-beta-signing.cer` y `release/signing/estrobo-beta-signing.sha256`. El digest versionado corresponde a los bytes X.509 DER del `.cer`. Una advertencia de Gatekeeper sigue siendo esperada; un fallo de checksum o `codesign` no lo es.

## Alcance útil de reportes

- Exposición del Código del radio, payloads de autenticación o datos locales.
- Ejecución de Apply/Sync/Test durante una edición que debería bloquearlos.
- Selección automática insegura con nombres duplicados.
- Bypass del gate de UUID o recuperación ante write incierto.
- Escrituras inesperadas, reintento de Test o comandos durante conexión/cancelación.
- Entitlements de red, telemetría o salida de sandbox no documentados.
- Manipulación de ZIP, checksum, manifiesto, attestation, certificado o workflow de release.
- Comportamiento que permita publicar sin una slice, CI o aprobación requerida.

Errores normales de compatibilidad o UX sin impacto de seguridad pertenecen a [Soporte](SUPPORT.md).

## Proceso de respuesta

Los mantenedores confirmarán el reporte dentro del propio advisory privado, investigarán con datos sintéticos cuando sea posible y coordinarán corrección/divulgación. No se promete un SLA ni recompensa. No publiques detalles antes de acordar una divulgación coordinada.
