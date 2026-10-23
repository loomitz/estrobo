# Transporte BLE para Windows y Linux

Fecha: 2026-10-22. Baseline Estrobo: `bf98e82637b562fff732ca82d7a92a66fe984d66`. Investigación documental; sin instalar software, conectarse al transmisor ni modificar producción.

## Resultado

Windows/WinRT y Linux/BlueZ permiten expresar el contrato GATT de Estrobo. Bleak, btleplug y Qt Bluetooth son candidatos documentados; **ninguno demuestra todavía paridad con el transmisor real**. El riesgo decisivo es preservar los límites de entrega, acuses y recuperación, especialmente Test. La elección de lenguaje/UI sigue abierta; estas capacidades no requieren separar repositorios (inferencia de arquitectura).

## Contrato que debe conservarse

La [documentación del baseline][contrato] y el [adaptador CoreBluetooth][adapter] establecen:

- Descubrir FFF0/FEC0 y FFF1/FFF4/FEC7/FEC8. Suscribir FFF4, esperar unos 500 ms y suscribir FEC8; validar propiedades notify **o** indicate.
- Autenticación Psub/PWOK y Sync por FFF1 **sin respuesta**; no imponer pairing del sistema. Luego A0 y A1 por FEC7 **con respuesta**, serializados.
- A0 concluye con acuse GATT. A1 necesita primero acuse GATT y después FEC8/F0 A1. **FEC8 no identifica grupo**; una llegada anticipada se ignora. GATT y FEC8 no prueban resultado óptico ni permiten importar estado.
- Heartbeat por FEC7 comparte la serialización. Los plazos actuales son 12 s de preparación, 10 s de PWOK, 5 s de write, 2 s de FEC8, 3 s de entrega Test y 3 s de desconexión.
- El [coordinador][coordinator] permite diferir autenticación/Sync, pero **Test falla inmediatamente si hay contrapresión; nunca se conserva para después**. El [controlador de sesión][session] conserva recuperación local y exige el mismo identificador antes de restaurar.

## Comparación documental

| Opción | Capacidad documentada | Condición relevante |
| --- | --- | --- |
| WinRT nativo | CCCD Notify/Indicate y ValueChanged; writes con opción explícita y resultado GATT. [Microsoft][win][write] | FromIdAsync puede requerir consentimiento y debe llamarse desde UI. Liberar referencias permite desconexión, pero no garantiza corte inmediato; otras apps pueden conservarla. |
| BlueZ nativo | WriteValue distingue command/request; StartNotify recibe notifications/indications mediante cambios de Value. [GATT][bluegatt] | Connect y Pair son operaciones separadas. Esperar Connected y ServicesResolved; Disconnect termina perfiles y enlace ACL. [Device][bluedev] |
| Bleak/Python | Backend WinRT y BlueZ/D-Bus; response explícito, start_notify, callback de desconexión, pair=False predeterminado. [Cliente][bleak][bleaklinux] | Windows permite force_indicate si existen ambas propiedades. Un solo loop asyncio persistente; MTA, o STA con bucle Windows integrado correctamente. [Windows][bleakwin], [diagnóstico][bleaktrouble] |
| btleplug/Rust | Windows/Linux, WriteType, subscribe y stream de notification/indication; eventos de conexión/desconexión. [API][btapi], [soporte][btreadme] | El código WinRT inspeccionado prefiere Indicate cuando están ambas propiedades. [Implementación][btutils] Los ejemplos usan Tokio y streams; integrar esos eventos con un dueño serial de sesión es trabajo de Estrobo. [Ejemplo][btevents] |
| Qt Bluetooth/C++ | Central BLE en Windows/Linux; WriteWithResponse/WithoutResponse, characteristicWritten y characteristicChanged; CCCD configura suscripciones. [Plataformas][qt], [Servicio][qtservice] | Serializa solicitudes internamente; without-response no emite confirmación ni error y documenta límite de 20 bytes. No basta para afirmar entrega inmediata de Test. |

## Identidad, pairing y recuperación

El UUID de CoreBluetooth **no es una identidad intercambiable entre sistemas**: Bleak documenta UUID en Apple frente a dirección Bluetooth en los demás. Windows permite seleccionar con DeviceInformation.Id; BlueZ expone dirección, tipo public/random y objeto por adaptador. Con privacidad la dirección utilizada puede cambiar. No se ha probado si estos Godox usan direcciones estables. [Cliente][bleak], [Windows][win], [BlueZ][bluedev]

Propuesta: clave local opaca con namespace de backend/adaptador y metadatos de descubrimiento; conservar nombre/RSSI sólo para selección. No transformar el UUID Apple en MAC ni recuperar automáticamente por nombre. Si cambia la identidad observable, detener restauración y pedir selección explícita; definir una revinculación separada antes de reutilizar el punto de recuperación. Esto es una decisión propuesta, no una garantía de identificación criptográfica.

Windows moderno permite GATT sin emparejar; BlueZ separa Pair de Connect. Por tanto mantener Psub/PWOK sin añadir pairing obligatorio es viable documentalmente, sujeto a permisos/características reales. Un error de autorización debe presentarse como tal, sin confundir el Código Godox con el PIN del sistema. [FAQ Microsoft][winfaq], [BlueZ][bluedev]

Windows tiene caché GATT del sistema, compartida entre procesos: reconstruir el adaptador no la borra; Uncached consulta al dispositivo. BlueZ también puede devolver servicios antiguos; Bleak documenta retirar el dispositivo para redescubrir cambios. No convertir unpair/RemoveDevice en una reparación automática. [Caché Windows][cache], [Bleak][bleaktrouble]

Qt invalida servicios/características tras desconectar y exige recrearlos; sus QObject/eventos requieren respetar afinidad de hilo y bucle activo. [Controlador][qtcontroller], [Hilos][qtthreads] Propuesta común: estados, deadlines y eventos en un ejecutor serial, sesión con generación propia para ignorar callbacks antiguos, y redescubrimiento/resuscripción tras reconectar.

## Riesgos que la documentación no resuelve

1. **Orden real de eventos:** ni recibir indication ni esperar una Future demuestra que la aplicación observará acuse GATT antes de FEC8. Si el backend entrega FEC8 antes, conservar el comportamiento actual implica ignorarlo y posiblemente agotar el plazo. No inventar correlación por grupo.
2. **Test tardío:** Bleak BlueZ reintenta WriteValue cuando recibe InProgress, incluso sin respuesta; Qt documenta colas. Windows documenta operaciones GATT que pueden tardar segundos/minutos y conexión no cancelable. Un timeout local no prueba que el SO descartó una orden. Descartar una Future tampoco basta. [Código Bleak][bleaksource], [Qt][qtservice], [Windows][win]
3. **Reconexión:** no reintentar automáticamente A1 incierto ni Test. La reconexión debe crear otra sesión, autenticar y respetar recuperación. La capacidad BLE básica no sustituye esta política del [controlador actual][session].

## Pruebas necesarias antes de decidir viabilidad

Propuestas; no ejecutadas. Fijar versiones y registrar SO, adaptador, modelo/firmware y trazas con código del radio redactado.

- Con transmisor sin pairing: descubrir propiedades/CCCD, elegir notify/indicate y reproducir pausas, PWOK y Sync; comprobar payload/MTU.
- Capturar A0/A1 consecutivos y heartbeat: acuse, callback y FEC8 con tiempos; verificar grupo único pendiente, eventos duplicados/anticipados y ausencia de avance falso.
- Provocar contrapresión/desconexión durante Test; esperar más que todos los deadlines y reconectar. **Aprobación: ninguna orden expirada se dispara después y no hay reintentos ocultos**. Si el backend no permite garantizarlo, requiere adaptación o queda descartado para paridad.
- Probar caída durante A1, suspensión/reanudación, apagado Bluetooth y transmisor ausente: detener cola, ignorar callbacks viejos, preservar recuperación y nunca restaurar en otro radio.
- Dos transmisores homónimos, reinicios y cambio de adaptador: verificar identidad; firmware con GATT cambiado: redescubrir sin confundir caché con estado real.

[contrato]: https://github.com/loomitz/estrobo/blob/bf98e82637b562fff732ca82d7a92a66fe984d66/docs/BLUETOOTH-CONNECTION.md
[adapter]: https://github.com/loomitz/estrobo/blob/bf98e82637b562fff732ca82d7a92a66fe984d66/Sources/EstroboBluetooth/CoreBluetoothRadioTransport.swift
[coordinator]: https://github.com/loomitz/estrobo/blob/bf98e82637b562fff732ca82d7a92a66fe984d66/Sources/EstroboBluetooth/CoreBluetoothWriteCoordinator.swift
[session]: https://github.com/loomitz/estrobo/blob/bf98e82637b562fff732ca82d7a92a66fe984d66/Sources/EstroboCore/GodoxSessionController.swift
[win]: https://learn.microsoft.com/en-us/windows/apps/develop/devices-sensors/gatt-client
[write]: https://learn.microsoft.com/en-us/uwp/api/windows.devices.bluetooth.genericattributeprofile.gattcharacteristic.writevaluewithresultasync
[winfaq]: https://learn.microsoft.com/en-us/windows/apps/develop/devices-sensors/bluetooth-dev-faq
[cache]: https://learn.microsoft.com/en-us/uwp/api/windows.devices.bluetooth.bluetoothcachemode
[bluegatt]: https://bluez.readthedocs.io/en/latest/gatt-api/
[bluedev]: https://bluez.readthedocs.io/en/latest/device-api/
[bleak]: https://bleak.readthedocs.io/en/stable/api/client.html
[bleakwin]: https://bleak.readthedocs.io/en/stable/backends/windows.html
[bleaklinux]: https://bleak.readthedocs.io/en/stable/backends/linux.html
[bleaktrouble]: https://bleak.readthedocs.io/en/stable/troubleshooting.html
[bleaksource]: https://bleak.readthedocs.io/en/stable/_modules/bleak/backends/bluezdbus/client.html
[btapi]: https://docs.rs/btleplug/latest/btleplug/api/trait.Peripheral.html
[btreadme]: https://github.com/deviceplug/btleplug
[btutils]: https://github.com/deviceplug/btleplug/blob/master/src/winrtble/utils.rs
[btevents]: https://github.com/deviceplug/btleplug/blob/master/examples/event_driven_discovery.rs
[qt]: https://doc.qt.io/qt-6/qtbluetooth-index.html
[qtservice]: https://doc.qt.io/qt-6.8/qlowenergyservice.html
[qtcontroller]: https://doc.qt.io/qt-6.8/qlowenergycontroller.html
[qtthreads]: https://doc.qt.io/qt-6.8/threads-qobject.html
