# Soporte

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
- claves, certificados privados, P12, passwords o GitHub Secrets;
- ZIP sospechoso o binarios de terceros;
- detalles de una vulnerabilidad explotable.

Para vulnerabilidades usa [GitHub Private Vulnerability Reporting](SECURITY.md).

## Qué esperar

La compatibilidad se amplía sólo con evidencia física reversible por modelo/firmware. Un nombre BLE, RSSI, UUID o acuse `FEC8` no basta para declarar soporte. Puede pedirse una reproducción en modo simulado o un gate físico coordinado; no se prometerá una fecha ni un SLA.

No abras issues para pedir que se omita el Código del radio sin una captura física segura del handshake. Tampoco para eliminar Gatekeeper mediante firma ad hoc: el beta usa una identidad autosignada estable y la advertencia es intencional.

## Proyecto independiente

Este repositorio no es un canal de soporte de Godox. Estrobo no está afiliado, patrocinado ni mantenido oficialmente por Godox.
