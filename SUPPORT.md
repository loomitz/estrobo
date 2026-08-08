# Soporte

<p align="center"><strong>Español</strong> &nbsp;·&nbsp; <a href="SUPPORT.en.md">English</a></p>

Estrobo es un beta público limitado y su canal de soporte es **GitHub Issues**. No existe un email de soporte publicado.

## Antes de abrir un issue

1. Lee [Solución de problemas](docs/TROUBLESHOOTING.md).
2. Confirma que usas el beta público más reciente y macOS 13 o posterior.
3. Cierra cualquier otra app conectada al transmisor.
4. Intenta reproducir con `--mock-radio` si el problema es de UI, interacción, presets o estado de sesión.
5. Busca un issue existente para evitar duplicados.

[Abre un issue en este repositorio](../../issues/new) sólo para información no sensible.

## Información útil

- versión y build de Estrobo;
- versión de macOS y arquitectura Intel/Apple Silicon;
- fase visible de la sesión y mensaje exacto;
- pasos esperados y observados;
- si ocurre también en modo simulado;
- para compatibilidad, modelo del transmisor, flash y firmware si los conoces;
- captura redactada o video corto cuando ayude.

No necesitamos un Código del radio para diagnosticar. Usa valores sintéticos en cualquier ejemplo.

## Nunca publiques en Issues

- Código del radio real;
- payload `Psub`, respuesta `PWOK` o token temporal;
- UUID completo, nombre de estación o información personal;
- claves, certificados privados, P12, API keys `.p8`, credenciales de notarización, passwords o GitHub Secrets;
- DMG sospechoso o binarios de terceros;
- detalles de una vulnerabilidad explotable.

Para vulnerabilidades usa [GitHub Private Vulnerability Reporting](SECURITY.md).

## Qué esperar

La compatibilidad se amplía sólo con evidencia física reversible por modelo/firmware. Un nombre BLE, RSSI, UUID o acuse `FEC8` no basta para declarar soporte. Puede pedirse una reproducción en modo simulado o un gate físico coordinado; no se prometerá una fecha ni un SLA.

El handshake `Psub`/`PWOK` es obligatorio; el Código del radio es el PIN local del transmisor, no una credencial fuerte. La beta oficial usa Developer ID y notarización: si Gatekeeper no la identifica como `Notarized Developer ID`, verifica el checksum y vuelve a descargar antes de abrir un issue.

## Proyecto independiente

Este repositorio no es un canal de soporte de Godox. Estrobo no está afiliado, patrocinado ni mantenido oficialmente por Godox.
