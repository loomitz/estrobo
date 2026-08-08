# Privacidad

<p align="center"><strong>Español</strong> &nbsp;·&nbsp; <a href="PRIVACY.en.md">English</a></p>

Estrobo controla un transmisor por Bluetooth de forma local. La aplicación no crea cuentas, no tiene backend, no solicita acceso de red, no incorpora analítica ni telemetría y no envía datos a Internet.

Esta política describe `0.1.x` beta. El navegador, GitHub, macOS y cualquier otra app que uses para descargar, reportar o diagnosticar tienen sus propias prácticas; no forman parte del tráfico de Estrobo.

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
- Se guarda localmente y **sin cifrar** en las preferencias del sandbox; este beta no usa Keychain.
- Nunca se envía a Internet porque Estrobo no tiene flujo de red.
- No reutilices un PIN personal.
- **Olvidar** elimina el nombre, UUID y código guardados y limpia el valor visible.
- Cancelar, fallar o desconectar limpia el código de la sesión en memoria según el flujo correspondiente.

Estrobo conserva lectura compatible con registros locales válidos de radios ya recordados, pero el bundle público `mx.loo.estrobo` tiene una identidad de preferencias limpia respecto del bundle de prototipo. No migra automáticamente datos del prototipo.

## Bluetooth

La app solicita permiso Bluetooth para escanear, mostrar nombre/RSSI/UUID, conectar y escribir al transmisor elegido mediante CoreBluetooth. Nombre, RSSI y UUID ayudan a reducir una selección equivocada, pero no autentican criptográficamente el radio.

Los comandos viajan directamente Mac ↔ transmisor. Estrobo no sube inventarios de dispositivos, UUID, valores ni resultados a un servicio remoto.

## Red, analítica y telemetría

El bundle mantiene App Sandbox y Bluetooth y no declara entitlements de cliente o servidor de red. El código de la app no incorpora un SDK de analítica, anuncios, crash reporting remoto ni telemetría.

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

- Usa **Olvidar** para quitar el radio y Código del radio guardados.
- Elimina presets o modifica el espacio de trabajo desde las opciones de la app disponibles para esos elementos.
- Desinstalar la app no siempre elimina preferencias de macOS. Para una eliminación completa, cierra Estrobo y elimina también el contenedor de aplicación asociado con `mx.loo.estrobo` desde tu cuenta de usuario. Haz una copia de cualquier preset que quieras conservar antes de hacerlo.

Un punto de recuperación puede mantenerse deliberadamente después de un write incierto para impedir nuevas escrituras inseguras. Se elimina cuando la recuperación confirmada termina o al retirar por completo los datos del contenedor.

## Datos de menores, pagos y cuentas

Estrobo no ofrece cuentas, pagos, perfiles remotos ni funciones sociales y no solicita edad, nombre, email o ubicación. El Código del radio no protege ninguna de esas categorías.

## Cambios

Los cambios materiales a esta política se documentarán en el repositorio y en [CHANGELOG.md](CHANGELOG.md). Para preguntas no sensibles usa [Soporte](SUPPORT.md); no existe una dirección de email de soporte publicada.
