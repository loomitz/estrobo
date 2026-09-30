# Privacidad

<p align="center"><strong>Español</strong> &nbsp;·&nbsp; <a href="PRIVACY.en.md">English</a></p>

Estrobo controla un transmisor por Bluetooth de forma local. La aplicación no crea cuentas, no tiene backend, no solicita acceso de red, no incorpora analítica ni telemetría y no envía datos a Internet.

Esta política describe `0.1.x` beta en macOS, iOS y iPadOS. El navegador, GitHub, el sistema operativo de Apple y cualquier otra app que uses para descargar, reportar o diagnosticar tienen sus propias prácticas; no forman parte del tráfico de Estrobo.

## Datos que Estrobo guarda localmente

Dentro del contenedor sandbox de la app pueden conservarse:

- idioma, apariencia, vista y modo de entrega de cambios;
- perfil de compatibilidad, grupos de trabajo/visibles y modelos asignados;
- snapshots A0/A1 deseados y últimos baselines locales confirmados;
- presets con nombre;
- identidad visual de los grupos;
- puntos de recuperación con UUID del radio, grupo y snapshot A1 anterior;
- si tú lo eliges, nombre, UUID CoreBluetooth y Código del radio recordado.

Los presets y puntos de recuperación no incluyen el Código del radio. La actividad de sesión evita payloads de autenticación y códigos.

## Código del radio

El Código del radio es un parámetro local de compatibilidad/proximidad de seis dígitos, no una contraseña de cuenta ni una credencial fuerte. El protocolo Godox lo transmite por BLE dentro del reto `Psub` y no ofrece autenticación fuerte.

- **Recordarlo es opt-in y empieza apagado.**
- Si lo activas, sólo se guarda después de completar `PWOK` y Sync.
- Se guarda en el Keychain local como un elemento exclusivo del dispositivo que sólo está disponible mientras el dispositivo está desbloqueado. La sincronización de Keychain está desactivada.
- El nombre recordado y el UUID CoreBluetooth pueden guardarse en las preferencias de la app, pero el Código del radio no forma parte de ese registro de metadatos.
- Si Estrobo encuentra un registro plaintext compatible de un beta anterior, migra cada código a Keychain y verifica el resultado antes de eliminar el registro anterior. Una migración incompleta falla cerrado y queda disponible para reintentarse.
- Nunca se envía a Internet porque Estrobo no tiene flujo de red.
- No reutilices un PIN personal.
- **Olvidar** elimina el nombre, UUID y código guardados y limpia el valor visible.
- Cancelar, fallar o desconectar limpia el código de la sesión en memoria según el flujo correspondiente.

Cada bundle de la app tiene su propio contenedor local e identidad de acceso a Keychain. Un build de desarrollo, prototipo, TestFlight o App Store con otra identidad de bundle no hereda automáticamente los datos guardados por otro build.

## Bluetooth

La app solicita permiso Bluetooth para escanear, mostrar nombre/RSSI/UUID, conectar y escribir al transmisor elegido mediante CoreBluetooth. Nombre, RSSI y UUID ayudan a reducir una selección equivocada, pero no autentican criptográficamente el radio.

Los comandos viajan directamente entre el iPhone, iPad o Mac y el transmisor. Estrobo no sube inventarios de dispositivos, UUID, valores ni resultados a un servicio remoto.

## Red, analítica y telemetría

La app no tiene flujo de red cliente o servidor. Su código no incorpora un SDK de analítica, anuncios, crash reporting remoto ni telemetría.

Al abrir enlaces de documentación, GitHub Releases, Issues o Private Vulnerability Reporting, la acción ocurre fuera de Estrobo en tu navegador/GitHub.

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
