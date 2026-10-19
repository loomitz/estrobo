# Privacidad

<p align="center"><strong>Español</strong> &nbsp;·&nbsp; <a href="PRIVACY.en.md">English</a></p>

Estrobo controla el transmisor por Bluetooth de forma local, sin cuentas, backend de usuarios, anuncios, analítica ni telemetría. La beta pública macOS `0.1.0-beta.4` y los candidatos iOS/iPadOS no tienen un actualizador ni flujo de red de la app. La nueva implementación macOS añade conexiones exclusivamente para comprobar y descargar actualizaciones; todavía no se ha publicado una release que las incorpore.

Esta política describe el candidato de desarrollo compartido para macOS, iOS y iPadOS. La beta pública macOS `0.1.0-beta.4` conserva el Código del radio sin cifrar en preferencias sólo por opt-in; la migración a Keychain descrita aquí pertenece al candidato y aún no es una nueva release pública. No hay una distribución pública iOS o iPadOS. La raíz de firma de producción, el catálogo público y los gates de distribución del actualizador siguen pendientes. El navegador, GitHub y el sistema operativo de Apple tienen sus propias prácticas; abrir un enlace o una validación propia de macOS es distinto de una solicitud del actualizador.

## Datos que Estrobo guarda localmente

Dentro del contenedor sandbox de la app pueden conservarse:

- idioma, apariencia, vista y modo de entrega de cambios;
- perfil de compatibilidad, grupos de trabajo/visibles y modelos asignados;
- snapshots A0/A1 deseados y últimos baselines locales confirmados;
- presets con nombre;
- identidad visual de los grupos;
- en la nueva implementación macOS, preferencias de búsqueda/descarga de actualizaciones, última comprobación exitosa, próximo intento automático y cache del DMG con la identidad de su oferta; la confirmación de instalación no se guarda como autorización permanente;
- puntos de recuperación con UUID del radio, grupo y snapshot A1 anterior;
- si tú lo eliges, nombre y UUID CoreBluetooth del radio recordado; su Código del radio se conserva por separado en Keychain.

Los presets y puntos de recuperación no incluyen el Código del radio. La actividad de sesión evita payloads de autenticación y códigos.

## Código del radio

El Código del radio es un parámetro local de compatibilidad/proximidad de seis dígitos, no una contraseña de cuenta ni una credencial fuerte. El protocolo Godox lo transmite por BLE dentro del reto `Psub` y no ofrece autenticación fuerte.

- **Recordarlo es opt-in y empieza apagado.**
- Si lo activas, sólo se guarda después de completar `PWOK` y Sync.
- Se guarda en el Keychain local como un elemento exclusivo del dispositivo que sólo está disponible mientras el dispositivo está desbloqueado. La sincronización de Keychain está desactivada.
- El nombre recordado y el UUID CoreBluetooth pueden guardarse en las preferencias de la app, pero el Código del radio no forma parte de ese registro de metadatos.
- Si Estrobo encuentra un registro plaintext compatible de un beta anterior, migra cada código a Keychain y verifica el resultado antes de eliminar el registro anterior. Una migración incompleta falla cerrado y queda disponible para reintentarse.
- Nunca se envía a Internet: las solicitudes de actualización excluyen el Código del radio y los datos de sesión, aunque la nueva app macOS tenga acceso de red.
- No reutilices un PIN personal.
- **Olvidar** elimina el nombre, UUID y código guardados y limpia el valor visible.
- Cancelar, fallar o desconectar limpia el código de la sesión en memoria según el flujo correspondiente.

Cada bundle de la app tiene su propio contenedor local e identidad de acceso a Keychain. Un build de desarrollo, prototipo, TestFlight o App Store con otra identidad de bundle no hereda automáticamente los datos guardados por otro build.

## Bluetooth

La app solicita permiso Bluetooth para escanear, mostrar nombre/RSSI/UUID, conectar y escribir al transmisor elegido mediante CoreBluetooth. Nombre, RSSI y UUID ayudan a reducir una selección equivocada, pero no autentican criptográficamente el radio.

Los comandos viajan directamente entre el iPhone, iPad o Mac y el transmisor. Estrobo no sube inventarios de dispositivos, UUID, valores ni resultados a un servicio remoto.

## Red, analítica y telemetría

El control Bluetooth no necesita Internet. La beta pública macOS `0.1.0-beta.4` y los candidatos iOS/iPadOS conservan su comportamiento sin red de la app. El actualizador pertenece sólo a la nueva implementación macOS; no actualiza iOS/iPadOS ni añade HTTP al núcleo del radio.

En una futura release macOS configurada para actualizar, la búsqueda y descarga automáticas empiezan apagadas. Puedes activarlas por separado en Actualizaciones; descargar automáticamente requiere buscar automáticamente. Una búsqueda manual contacta los servicios aunque no hayas activado automatismos y no cambia tus preferencias. Desactivar la búsqueda detiene las tareas automáticas pendientes; el control local sigue disponible sin Internet.

Las comprobaciones contactan `estrobo.app`; los DMG se obtienen de releases exactas de GitHub. Esos servicios y sus proveedores reciben datos técnicos normales, como IP, User-Agent y datos de la conexión HTTPS, y pueden conservar logs conforme a sus propias prácticas. El feed utiliza las redirecciones HTTPS estándar de Sparkle: no hay una allowlist de dominios que vete cada origen del feed antes de contactarlo. Se mantienen HTTPS/ATS y la verificación obligatoria del catálogo y archivo firmados; el tráfico público real sigue siendo un gate de distribución pendiente.

Las solicitudes no incluyen Código del radio, payloads de autenticación, UUID, nombres de transmisores, presets, snapshots, perfiles ni identificadores del estudio. El perfilado de Sparkle está desactivado. No hay analítica, anuncios, crash reporting remoto ni telemetría. Las notas se incluyen como texto firmado en español/inglés, sin descarga automática de páginas, imágenes, scripts o recursos externos.

Instalar y reiniciar siempre requiere confirmar una oferta concreta con el transmisor desconectado y el trabajo local en un estado seguro. Descargar, cerrar la app o reiniciar el Mac no concede ese permiso. La actualización conserva la identidad de la app y utiliza la persistencia/migración existente; nunca borra recuperación para facilitar una instalación ni conecta al radio por haber actualizado. Su validación real entre builds firmados/notarizados permanece pendiente.

Al abrir enlaces de documentación, descarga manual, Issues o Private Vulnerability Reporting, la acción ocurre explícitamente en tu navegador/GitHub y sigue las prácticas de esos servicios.

## Logs, diagnósticos y reportes

La actividad visible se limita a estados y errores operativos. No debe incluir:

- Código del radio;
- payload completo `Psub` o respuesta `PWOK`;
- tokens, claves o certificados privados;
- contenido de presets como sustituto de diagnósticos;
- información personal.

Los issues de GitHub son públicos. Redacta UUID completos, nombres personales y datos del estudio. Las vulnerabilidades se reportan mediante [Private Vulnerability Reporting](SECURITY.md), no mediante Issues.

## Eliminar datos

- Usa **Olvidar** para quitar los metadatos del radio guardado y su Código del radio del Keychain.
- Elimina presets o modifica el espacio de trabajo desde las opciones de la app disponibles para esos elementos.
- Los sistemas operativos de Apple pueden conservar elementos de Keychain después de eliminar una app. Usa **Olvidar** antes de desinstalar. Eliminar el contenedor de la app limpia sus preferencias y diario de recuperación; en macOS también puedes retirar desde Acceso a Llaveros las entradas del servicio `mx.loo.estrobo.radio-code`. Haz una copia de cualquier preset que quieras conservar antes de borrar el contenedor.

Un punto de recuperación puede mantenerse deliberadamente después de un write incierto para impedir nuevas escrituras inseguras. Se elimina cuando la recuperación confirmada termina o al retirar por completo los datos del contenedor.

## Datos de menores, pagos y cuentas

Estrobo no ofrece cuentas, pagos, perfiles remotos ni funciones sociales y no solicita edad, nombre, email o ubicación. El Código del radio no protege ninguna de esas categorías.

## Cambios

Los cambios materiales a esta política se documentarán en el repositorio y en [CHANGELOG.md](CHANGELOG.md). Para preguntas no sensibles usa [Soporte](SUPPORT.md); no existe una dirección de email de soporte publicada.
