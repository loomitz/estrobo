# Godox BLE PoC — PROTOTIPO DESECHABLE

## Pregunta que responde

¿Puede este Mac descubrir el transmisor Godox `GDBH-*`, completar directamente su handshake BLE local —sin cuenta ni backend Godox— y enviar una orden A1 de potencia que después pueda restaurarse de forma determinista?

Este código es deliberadamente un prototipo de lógica, no la aplicación final. La TUI expone todo el estado de sesión y mantiene el Código del radio únicamente en memoria. No incluye persistencia, analytics, red, actualización de firmware ni disparo de prueba.

## Seguridad de la prueba

- El Código del radio se captura sin eco y nunca se imprime.
- El prototipo sólo usa los servicios de autenticación `FFF0` y control `FEC0`.
- Los UUID de actualización/OAD quedan fuera del código de escritura.
- No existe ninguna acción que envíe `Test`, `Take` o cambie el Código del radio.
- La prueba de potencia usa grupo B y ofrece una restauración explícita al valor base conocido.

## Ejecutar

Desde la raíz del proyecto:

```sh
make poc
```

La primera ejecución puede provocar el diálogo de permiso Bluetooth de macOS. El Android debe dejar libre la conexión BLE antes de que el Mac pueda ver o conectar el transmisor.

## Criterio de éxito

El concepto queda probado cuando la TUI llega a `ready`, una escritura A1 recibe confirmación y la orden de restauración también se confirma, sin que la app use Internet ni una cuenta Godox.

## Resultado real — 2026-08-04

**GO: el concepto quedó probado contra el transmisor físico conectado.**

- macOS descubrió el radio `GDBH-*` mediante CoreBluetooth después de liberar su única conexión BLE desde Android.
- El radio aceptó el reto local, respondió `PWOK`, la respuesta se validó localmente y la sesión llegó a `ready` después de sincronizar el reloj.
- El PoC envió al grupo B una variación de un paso. La escritura con respuesta fue aceptada y llegó una notificación por `FEC8`.
- El PoC restauró inmediatamente B a `1/256 +0.0`. La segunda escritura también fue aceptada y produjo otra notificación `FEC8`; la TUI terminó con dos writes confirmados y ninguna restauración pendiente.
- Al cerrar el PoC, macOS se desconectó limpiamente. Godox Flash volvió a abrirse en Android, recuperó la conexión GATT y mostró el grupo B en `1/256 +0.0`.
- No se usaron cuenta, backend ni Internet. No se envió disparo de prueba, cambio de Código del radio ni comando de firmware/OAD.

La confirmación primaria de cada orden es el acuse de escritura de CoreBluetooth más la notificación del radio. La pantalla posterior de Android confirma que el estado visible volvió al valor base; todavía falta estudiar si cada familia Godox permite leer todo su estado desde el transmisor o si parte de esa pantalla es una copia local.
