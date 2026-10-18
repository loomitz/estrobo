# Soporte

<p align="center"><strong>Español</strong> &nbsp;·&nbsp; <a href="SUPPORT.en.md">English</a></p>

Estrobo es un beta limitado y su canal de soporte es **GitHub Issues**. No existe un email de soporte publicado.

La distribución pública vigente es la beta macOS `0.1.0-beta.4`. iOS y iPadOS permanecen como candidatos locales; sus requisitos declarados y resultados de Simulator no constituyen una distribución disponible ni compatibilidad física validada. Antes de TestFlight o App Store falta publicar un contacto de soporte que cumpla sus requisitos.

## Actualizaciones macOS: versión pública y candidato

La beta pública `0.1.0-beta.4` no incluye actualizador. La primera release que lo incorpore se instalará manualmente desde su release oficial, verificando DMG, manifiesto y `SHA256SUMS` del mismo tag. Todavía no se ha publicado esa release ni un catálogo de producción aprobado. El actualizador no forma parte de iOS/iPadOS.

En la nueva implementación macOS, **Buscar actualizaciones…** en el menú Estrobo y **Actualizaciones** en Ajustes comparten el mismo estado. La búsqueda manual no activa automatismos; buscar y descargar en segundo plano empiezan apagados y requieren tu elección. Las notas están disponibles en español/inglés dentro de la oferta. La búsqueda y descarga pueden continuar durante una sesión Bluetooth; instalar exige desconectar el transmisor y resolver operaciones, edición, borradores o recuperación que bloqueen el cierre. Estrobo no desconecta, aplica ni descarta por ti.

**Instalar y reiniciar** confirma una oferta concreta y vuelve a comprobar su vigencia, archivo firmado y seguridad antes de instalar. **Más tarde**, **Cancelar descarga** o **Cancelar instalación** permiten aplazar o cancelar según la etapa; una cancelación o un cambio de oferta exige confirmar otra vez. Descargar, cerrar Estrobo o reiniciar el Mac nunca autoriza instalar. Al relanzar, el espacio de trabajo se recupera sin conectar al transmisor ni enviarle valores automáticamente por la actualización.

Si la actualización falla:

- **No configurada:** el candidato sin raíz pública de producción permanece sin actualizaciones disponibles; no añadas una clave de pruebas ni eludas la verificación. Conserva tu copia y consulta soporte.
- **Red/servidor:** el control local sigue disponible; vuelve a buscar cuando haya conexión. Un error no significa «estás actualizado». Tras fallos, los intentos automáticos esperan al menos 24 horas y respetan plazos de servidor conocidos más largos; reiniciar no adelanta ese plazo. La búsqueda manual sigue disponible.
- **Firma, archivo u oferta inválida/retirada:** no se instala. Vuelve a buscar y descarga la oferta vigente; una descarga previa no evita comprobar de nuevo la elegibilidad.
- **Instalación bloqueada:** resuelve el motivo visible en el espacio de trabajo y desconecta el transmisor. No borres recuperación ni fuerces el cierre.
- **DMG, permisos o espacio:** abre la copia instalada en Aplicaciones, comprueba espacio disponible y vuelve a intentar la autorización del sistema cuando decidas instalar.

Para recuperación manual utiliza sólo una release oficial apropiada para tus datos y verifica sus archivos. Preferimos una corrección con build superior: volver a una versión anterior no garantiza compatibilidad de preferencias o Keychain. No borres tus datos para hacer pasar una instalación. Los gates de actualización entre builds Developer ID/notarizados, Intel/macOS mínimo y publicación/retirada públicas siguen pendientes; los tests locales no los sustituyen. Consulta [Privacidad](PRIVACY.md) para las conexiones y datos técnicos de proveedores.

## Antes de abrir un issue

1. Lee [Solución de problemas](docs/TROUBLESHOOTING.md).
2. Confirma que usas el build más reciente disponible para ti en macOS 13 o posterior, iOS 18 o posterior, o iPadOS 18 o posterior.
3. Cierra cualquier otra app conectada al transmisor.
4. Si el problema es de UI, interacción, presets o estado de sesión, intenta reproducirlo en modo Demo de iPhone/iPad o con `--mock-radio` en Mac.
5. Busca un issue existente para evitar duplicados.

[Abre un issue en este repositorio](https://github.com/loomitz/estrobo/issues/new) sólo para información no sensible.

## Información útil

- versión y build de Estrobo;
- plataforma, versión del sistema operativo y modelo de iPhone/iPad o arquitectura de Mac;
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

El handshake `Psub`/`PWOK` es obligatorio; el Código del radio es el PIN local del transmisor, no una credencial fuerte. En macOS, la beta oficial usa Developer ID y notarización: si Gatekeeper no la identifica como `Notarized Developer ID`, verifica el checksum y vuelve a descargar antes de abrir un issue. En iOS y iPadOS usa únicamente el build de TestFlight o App Store publicado por Estrobo cuando exista; Estrobo nunca requiere un perfil de configuración ni un instalador de terceros.

## Proyecto independiente

Este repositorio no es un canal de soporte de Godox. Estrobo no está afiliado, patrocinado ni mantenido oficialmente por Godox.
