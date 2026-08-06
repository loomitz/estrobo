# Viabilidad de un controlador Godox Flash local para macOS

Fecha de investigación: 2026-08-04
Alcance: fuentes oficiales de Godox, Apple y Android; inspección estática de Godox Flash 1.3.3; inventario Bluetooth del Android conectado; y pruebas reversibles de potencia y luz de modelado contra el transmisor real. Se redactaron las credenciales y los identificadores completos. No se disparó ningún flash.

Actualización de implementación: 2026-08-06. Una nueva inspección estática de la misma APK precisó el flujo global A0, el beep master/subordinado, standby y Auto/TTL. Esos cuatro contratos ya están cubiertos por el prototipo y pruebas deterministas, pero no se ejecutaron contra el radio durante esta actualización.

## Conclusión ejecutiva

**Sí es técnicamente viable construir una app nativa y completamente local para macOS.** En el transmisor conectado ya se confirmó la ruta completa macOS → CoreBluetooth → BLE/GATT → radio Godox: el Mac lo descubrió, completó el handshake local, sincronizó la sesión y reprodujo variaciones reversibles de potencia y modelado fijo al 25%. Android se usó después para comprobar la reconexión y los valores locales restaurados.

La plataforma Mac no es el obstáculo. Apple permite descubrir, conectar y leer/escribir periféricos Bluetooth desde una app Mac. Si Godox usa BLE/GATT, la ruta es `CoreBluetooth`; si usa Bluetooth clásico con RFCOMM, macOS también expone esa ruta mediante `IOBluetooth`. Godox, por su parte, documenta control Bluetooth desde su app en transmisores X2T y XPro II, y en productos posteriores como X3Pro y FT433. El patrón es favorable: la app controla el transmisor por Bluetooth y el transmisor conserva la autoridad sobre los flashes mediante el sistema inalámbrico Godox X de 2.4 GHz —o el enlace de 433 MHz en FT433—.

Godox no publica un SDK, UUIDs GATT ni el formato de los mensajes en las páginas y manuales oficiales revisados, pero la APK contiene esa capa en Java/Kotlin y no la oculta detrás de una biblioteca nativa. La cuenta es una restricción de la app oficial: el código bloquea el escaneo y el envío si no hay sesión, mientras que el handshake del radio usa únicamente el Código del radio, un nonce y tiempo. No usa el token de Godox ni obtiene una clave del backend. Una implementación independiente puede omitir por completo cuenta, Internet y servicios cloud.

## Resultado en el equipo conectado

### Transporte y perfil confirmados

- Android: Xiaomi Mi 9T rooteado y autorizado por ADB.
- App: `com.linking.godoxflash`, Godox Flash 1.3.3, target Android 14; SHA-256 del APK base `12e89153154537746c4854bdc345332900b805610e30cff07b757819bb37f5bf`.
- Periférico: nombre `GDBH-…`; se omiten la dirección y el sufijo completos.
- Transporte: **Bluetooth Low Energy**, cliente GATT activo, sin bonding y con MTU 23.
- Servicio de control: `0000fec0-0000-1000-8000-00805f9b34fb`.
- Escritura de control: `0000fec7-0000-1000-8000-00805f9b34fb`.
- Respuesta/indicación: `0000fec8-0000-1000-8000-00805f9b34fb`.
- Servicio de autenticación/prueba: `0000fff0-0000-1000-8000-00805f9b34fb`, con escritura `FFF1` y notificación `FFF4`.
- El APK también contempla el perfil OAD `FFC0/FFC1/FFC2` para actualización; no es necesario para el MVP y conviene dejarlo fuera por seguridad.

CoreBluetooth expone exactamente las operaciones usadas aquí: escanear, conectar, descubrir `FEC0/FFF0`, activar indicaciones/notificaciones y escribir en `FEC7/FFF1`. No hace falta RFCOMM para este radio.

### Cuenta frente a autenticación local

La app oficial aplica un gate de login antes de ligar su servicio BLE, escanear o enviar comandos. Esa decisión está en `FlashMainActivity` y `HomePageFragment`, no en el firmware del transmisor.

El radio sí pide un código local. La app construye un reto ASCII con nonce, marca de tiempo y Código del radio, lo escribe en `FFF1`, y acepta la respuesta `PWOK` recibida en `FFF4` dentro de una ventana temporal. El algoritmo no consume el JWT de la cuenta ni hace una petición de red. En el beta público el código se pide al usuario y sólo se guarda localmente, sin cifrar, cuando éste activa el opt-in; no debe copiarse desde el teléfono ni aparecer en logs.

### Comando de control comprobado

La familia de frames comienza con `F0`, seguida del tipo, longitud, payload y CRC. El control por grupo usa:

```text
F0 A1 07 <grupo> <modo> <potencia-manual> <modelado> <beep>
         <modo-modelado> <compensacion-TTL> <crc>
```

El último byte es **CRC-8/MAXIM**: polinomio reflejado `0x8C`, valor inicial `0x00` y xor final `0x00`. Para potencia manual, la app codifica el byte como `100 - decimalPower`.

Se hizo una sola prueba sin disparo: grupo B pasó temporalmente de `1/256 +0.0` al siguiente paso y volvió al valor original. El teléfono escribió en `FEC7`:

```text
F0 A1 07 0B 01 4D 00 00 00 00 9F
F0 A1 07 0B 01 50 00 00 00 00 0F
```

La UI volvió a `1/256 +0.0`, de modo que el estado de potencia quedó restaurado. Esto demuestra el camino de datos real; no es sólo una conclusión obtenida del APK.

### Modelado: capacidad presente y UI oficial incompleta

El codec de Godox Flash 1.3.3 usa dos campos independientes en A1:

| Byte | Campo | Codificación observada |
| ---: | --- | --- |
| 6 | Intensidad de modelado | porcentaje decimal directo; `25% → 0x19`, `100% → 0x64` |
| 8 | Modo de modelado | `00` apagado, `01` proporcional, `02` fijo |

La APK contiene una sección `PROP / FREE` y un `SeekBar` de 0–100, pero el contenedor está declarado oculto y la actividad no lo vuelve visible. Hay además un desfase funcional: la UI guarda el slider en `progress`, mientras `BluetoothSendData.getSingleGroupData` nunca lee ese campo. En 1.3.3, `FREE 37%` termina codificado con intensidad `00` y modo fijo `02`. El encoder sólo conserva caminos legacy explícitos para los textos `25%` y `100%`.

El prototipo Mac corrige ese enlace y, para la primera prueba física, restringió el porcentaje a 25%. Con B en manual `1/512 +0.0`, modelado inicialmente apagado, beep apagado y compensación cero, envió:

```text
F0 A1 07 0B 01 5A 19 00 02 00 88  # fijo 25%
F0 A1 07 0B 01 5A 00 00 00 00 B2  # restauración off
```

Ambas escrituras recibieron acuse GATT y notificación `FEC8`; la potencia permaneció en `1/512 +0.0`. El Mac se desconectó y Android recuperó GATT con B conservado localmente en modelado apagado. Esta evidencia confirma transporte, aceptación y reversión del frame. La iluminación efectiva y el nivel exacto siguen requiriendo observación física: `FEC8` no mide la salida de la lámpara.

### Prueba nativa desde macOS — completada

Se construyó un cliente TUI desechable en Swift/CoreBluetooth y se ejecutó contra el mismo transmisor físico. Android se cerró temporalmente porque el periférico mantiene una sola conexión central; no fue necesario resetear, desvincular ni cambiar la configuración del radio.

El cliente Mac:

1. descubrió el periférico `GDBH-*` y conectó con APIs públicas de macOS;
2. encontró `FEC0/FFF0`, activó `FFF4/FEC8`, envió el reto local y validó la respuesta `PWOK` sin cuenta ni red;
3. sincronizó el reloj y alcanzó el estado `ready`;
4. envió exactamente el frame de subida mostrado arriba, recibió el acuse de escritura de CoreBluetooth y una notificación `FEC8`;
5. envió exactamente el frame de restauración, recibió un segundo acuse y otra notificación `FEC8`;
6. salió sin restauración pendiente y se desconectó limpiamente.

Después, Godox Flash recuperó automáticamente la conexión GATT desde Android y mostró B en `1/256 +0.0`. No se envió `Test`, no se disparó ningún flash y no se tocó el perfil OAD. El Código del radio sólo existió en memoria durante el proceso y no forma parte del repositorio ni de los logs del programa.

### Contrato mínimo para el PoC macOS

La secuencia clean-room recuperada es:

1. Escanear sin filtro de servicio y aceptar nombres con `-` cuyo prefijo sea `GD` o `Ami`; el equipo actual pertenece a la familia `GDBH`.
2. Conectar, descubrir `FEC0` y `FFF0`, y localizar `FEC7`, `FEC8`, `FFF1` y `FFF4`.
3. Activar primero `FFF4` y luego `FEC8`, dejando aproximadamente 500 ms entre suscripciones. En equipos `GD*`, FEC8 es indication; en `Ami-*`, notification. CoreBluetooth abstrae ambas con `setNotifyValue`.
4. Enviar por `FFF1` sin respuesta el ASCII `<nonce>,Psub,<codigo-radio-sintetico>`, donde:

   ```text
   t = floor(unixMillis / 1000) mod 10000
   r = entero aleatorio entre 1 y 98
   nonce = 1000000 - (r * 10000 + t)
   ```

5. Aceptar únicamente una notificación `PWOK,<token-temporal>` cuyo token pase la transformación local recuperada y quede dentro de ±20 segundos. No interviene ningún dato de cuenta.
6. Tras unos 500 ms, sincronizar por `FFF1` con `<milisegundos-desde-2017-01-01-00:00-local>,Sync`.
7. Escribir A0/A1 por `FEC7` con respuesta, en una cola serial y con unos 50 ms antes de cada write. Todos estos payloads caben en los 20 bytes disponibles con MTU 23; no necesitan fragmentación.
8. Si FEC8 entrega un heartbeat de seis bytes que empieza por `F0 E0`, responder `F0 E0` por FEC7.

La app Android contiene reintentos especiales a 300–350 ms, máximo tres, sólo para órdenes marcadas para esperar eco. La ruta A0 normal (`TCCommand`, sin reintento) termina cuando el write GATT devuelve status cero y el valor local de la característica coincide; no espera `FEC8`. En el prototipo, A0 usa por ello confirmación GATT-only, mientras cada A1 conserva la confirmación GATT + `FEC8`. El cliente debe registrar sólo estados y errores, nunca el Código del radio ni el payload de autenticación.

La trama global A0 tiene 14 bytes:

| Byte | Campo |
| ---: | --- |
| 0–2 | `F0 A0 0A` |
| 3 | `FF` fijo en Godox Flash 1.3.3; aunque la UI guarda canal, su transmisión debe validarse antes de prometer control de canal |
| 4 | Beep global 0/1 |
| 5 | Modelado global 0/1 |
| 6 | Ajuste relativo: ninguno, ±0.1, ±0.3 o ±1.0 |
| 7–10 | Multi: activo, número de destellos, Hz y potencia |
| 11 | Standby global |
| 12 | Contador de ajuste |
| 13 | CRC-8/MAXIM |

En A1, los grupos `0`–`9` y `A`–`F` se codifican como `00`–`0F`. Los modos observados son auto `00`, manual `01`, multi `02` y oculto/off `03`. Al enviar Auto/TTL, Godox Flash fuerza el byte 5 de potencia a `0x32` y la compensación del byte 9 a `0x00`; conserva la potencia Manual fuera de la trama para recuperarla al volver a M. La intensidad de modelado ocupa el byte 6 y el modo apagado/proporcional/fijo ocupa el byte 8; la compensación TTL usa el bit alto para valores negativos cuando se exponga edición distinta de la compensación neutra.

El disparo de prueba no es una trama A0/A1: usa `FFF1` sin respuesta con `<tiempo-desde-2017>,Test`. Se identificó estáticamente, pero deliberadamente no se ejecutó. La app de escritorio nunca debe disparar al conectar, restaurar una escena o reconectar.

## Un camino oficial limitado ya existe en Apple Silicon

La ficha mexicana de Godox Flash en App Store indica que la app está **diseñada para iPad, no verificada para macOS**, pero que puede instalarse en una Mac con macOS 11 o posterior y chip Apple M1 o posterior. No es un cliente Mac diseñado para trabajo tethered, no resuelve el requisito de operar sin cuenta y no ayuda en Mac Intel, pero sí ofrece una prueba inmediata de bajo costo para una Mac Apple Silicon: comprobar si la app iPad actual ve el transmisor desde macOS. Fuente: [Godox Flash en App Store México](https://apps.apple.com/mx/app/godox-flash/id1617017130).

La misma ficha anuncia control por grupos, espera con una acción, e importación y exportación de escenas. Son referencias útiles para definir paridad funcional, aunque no sustituyen un diseño de escritorio.

## Qué equipos documenta Godox

| Familia | Evidencia oficial de control con Godox Flash | Lectura para el proyecto |
| --- | --- | --- |
| X2 / X2T | El catálogo Godox 2023 declara compatibilidad de Godox Flash con las series X2 y XPro II. El manual X2T describe conexión Bluetooth al smartphone y control de modo, potencia, luz de modelado, beep y disparo desde la app. | Candidato fuerte. Hay que versionar por variante y firmware; Godox publica firmware específico para mantener compatibilidad con la app. |
| XPro II C/N/S/F/O/L | Godox afirma que incorpora Bluetooth para ajustar parámetros desde iPhone, Android o tablet mediante Godox Flash. | Candidato fuerte y el más claramente documentado para el flujo descrito. |
| X3Pro C/N/S/F/O | Godox documenta Bluetooth integrado y control completo desde Godox Flash: potencia, grupos y disparo remoto. | Candidato fuerte, posiblemente con un protocolo o versión de protocolo más reciente. |
| FT433 C/N/S | Godox documenta control Bluetooth con Godox Flash para modo, potencia, luz de modelado y beep. | Viable en principio, pero su enlace del transmisor a los flashes es una familia de 433 MHz distinta; debe tratarse como perfil separado. |
| X3 C/N/S/F/O/L, sin “Pro” | La página oficial revisada describe el sistema Godox X de 2.4 GHz, pero no anuncia Bluetooth ni Godox Flash. | **No asumir compatibilidad directa con la app.** La semejanza del nombre con X3Pro no basta. |

Fuentes Godox:

- [Catálogos oficiales Godox](https://www.godox.com/brochures-catalogues/) (la evidencia citada se revisó en la edición 2023)
- [XPro II, página oficial](https://www.godox.com/product-a/XPro-II.html)
- [X3Pro, página oficial](https://www.godox.com/product-e/X3Pro.html)
- [FT433, página oficial](https://www.godox.com/product-a/FT433.html)
- [X3, página oficial](https://godox.com/product-a/X3.html)
- [X2T, página oficial con su manual](https://godox.com/product-d/X2.html)
- [Firmware oficial del sistema de control](https://www.godox.com/firmware-control-system_5/)
- [Página oficial de aplicaciones Godox](https://www.godox.com/app/)

El modelo y firmware exactos del transmisor conectado siguen siendo necesarios para nombrar y versionar correctamente el perfil, aunque ya no bloquean el veredicto de viabilidad del equipo presente. `GDBH` es un identificador usado por más de una variante y no basta para adjudicar un modelo físico.

## Topología que debe replicar la app Mac

```text
App macOS
   │ Bluetooth local
   ▼
Transmisor Godox compatible
   │ Godox X 2.4 GHz (o 433 MHz en FT433)
   ▼
Grupos de flashes / receptores
```

Esto evita el problema más difícil de radiofrecuencia: la app Mac **no necesita implementar el protocolo Godox X ni emitir 2.4 GHz hacia cada flash**. Solo necesita hablar el mismo protocolo Bluetooth local que la app móvil usa con el transmisor. El transmisor sigue encargándose de canal, ID, grupos, TTL/M/Multi, potencia, modelado, beep y disparo según las capacidades de cada familia. La separación se desprende de la descripción oficial del [XPro II](https://www.godox.com/product-a/XPro-II.html) y del [FT433](https://www.godox.com/product-a/FT433.html).

## Compatibilidad técnica en macOS

### Si el transporte es BLE/GATT

Apple documenta que `CoreBluetooth` permite a una app Mac actuar como central, descubrir periféricos, conectarse, descubrir servicios y características, escribir valores y suscribirse a notificaciones. Es exactamente el conjunto de operaciones necesario para un controlador de este tipo:

- [Core Bluetooth Overview](https://developer.apple.com/library/archive/documentation/NetworkingInternetWeb/Conceptual/CoreBluetooth_concepts/CoreBluetoothOverview/CoreBluetoothOverview.html)
- [Performing Common Central Role Tasks](https://developer.apple.com/library/archive/documentation/NetworkingInternetWeb/Conceptual/CoreBluetooth_concepts/PerformingCommonCentralRoleTasks/PerformingCommonCentralRoleTasks.html)
- [`CBCentralManager`](https://developer.apple.com/documentation/corebluetooth/cbcentralmanager)

En Android, las señales inequívocas de esta ruta son llamadas a `connectGatt`, objetos `BluetoothGatt`, servicios/características y escrituras o notificaciones GATT. Android explica que el teléfono central se conecta al servidor GATT del periférico y transfiere datos mediante sus servicios y características:

- [Android: Bluetooth Low Energy overview](https://developer.android.com/develop/connectivity/bluetooth/ble/ble-overview)
- [Android: Connect to a GATT server](https://developer.android.com/develop/connectivity/bluetooth/ble/connect-gatt-server)
- [Android: `BluetoothGatt`](https://developer.android.com/reference/android/bluetooth/BluetoothGatt)

### Si el transporte es Bluetooth clásico/RFCOMM

La señal inequívoca en Android sería el uso de `BluetoothSocket` y un canal RFCOMM, en vez de `BluetoothGatt`. Android documenta esa conexión como un socket con flujos de entrada y salida: [Connect Bluetooth devices](https://developer.android.com/develop/connectivity/bluetooth/connect-bluetooth-devices).

macOS también tiene una ruta oficial para ese caso. `IOBluetoothRFCOMMChannel` representa un canal RFCOMM y permite leer y escribir datos: [`IOBluetoothRFCOMMChannel`](https://developer.apple.com/documentation/iobluetooth/iobluetoothrfcommchannel) y [Bluetooth Device Access Guide](https://developer.apple.com/library/archive/documentation/DeviceDrivers/Conceptual/Bluetooth/BT_Intro/BT_Intro.html).

Por tanto, **BLE frente a clásico cambia la implementación, pero no decide por sí solo la viabilidad**. Para el transmisor conectado la bifurcación ya está resuelta: usa BLE/GATT y debe implementarse con CoreBluetooth.

### Permisos de una app distribuible

Una app sandboxed debe declarar acceso Bluetooth con `com.apple.security.device.bluetooth`; Apple indica que se activa en App Sandbox > Hardware > Bluetooth. También debe presentar al usuario la explicación de uso de Bluetooth correspondiente. Fuentes: [Bluetooth entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.device.bluetooth), [Configuring the macOS App Sandbox](https://developer.apple.com/documentation/xcode/configuring-the-macos-app-sandbox) y [`NSBluetoothAlwaysUsageDescription`](https://developer.apple.com/documentation/bundleresources/information-property-list/nsbluetoothalwaysusagedescription).

Una versión estrictamente local no necesita cuenta ni conexión saliente. Los presets pueden guardarse en el contenedor local de la app. El beta trata el Código del radio como un parámetro proporcional de compatibilidad/proximidad: recordarlo empieza apagado y, si el usuario lo elige, se guarda localmente y sin cifrar; nunca aparece en logs ni presets.

## Lo que todavía hay que demostrar

1. **Modelo y revisión exactos.** Registrar únicamente modelo, variante, revisión y firmware; no hace falta conservar una dirección Bluetooth completa ni credenciales.
2. **Matriz de estado.** Ver si el transmisor expone lectura real de estado o si la app conserva una copia optimista. Esto decide cómo manejar cambios hechos físicamente en el radio.
3. **Cobertura restante y prueba física.** El codec ya cubre snapshots A0 completos, Off/M/Auto TTL, beep master A0 + subordinados A1 y standby A0-only. Falta completar edición Multi, canal y compensación TTL no neutra, y comprobar físicamente TTL, beep y standby; en modelado, ampliar la prueba desde 25% hacia el rango 1–100 y registrar capacidades por flash.
4. **Variantes de firmware.** Comprobar si X2T, XPro II, X3Pro y FT433 comparten codec o necesitan perfiles versionados.

No encontré un SDK ni una especificación oficial del protocolo en las secciones App, producto, manuales, firmware y soporte de Godox revisadas. Esta es una constatación de la búsqueda, no una afirmación de que Godox nunca haya compartido documentación privada con socios.

## Prueba de concepto recomendada y criterios de decisión

### Fase 0 — inventario técnico y recuperación del protocolo — completada

- Identificar la app, el transporte y el perfil del transmisor. El nombre comercial/revisión/firmware físicos quedan pendientes para etiquetar el perfil.
- Extraer una copia de la APK para análisis estático, sin cambiar ajustes del teléfono y sin exportar tokens, correo, identificadores completos ni datos de cuenta.
- Localizar las APIs Bluetooth usadas y el código que construye/valida paquetes.

**Salida obtenida:** transporte, UUIDs, handshake, formatos A0/A1 y CRC identificados; una transmisión reversible fue validada y restaurada sin disparo.

### Fase 1 — explorador Mac sin escrituras — completada

- Implementar un pequeño cliente Mac que escanee, identifique el transmisor por nombre/servicio no sensible y se conecte.
- Enumerar servicios/características GATT o SDP/RFCOMM.
- Suscribirse a notificaciones o lecturas disponibles sin cambiar parámetros.

**Go** si el Mac descubre y conecta al transmisor con APIs públicas.
**Revisar** si el transmisor solo anuncia mientras la app Android está desconectada o requiere un reset de vínculo; cualquier cambio de vínculo debe hacerse después con autorización explícita.

**Salida obtenida:** CoreBluetooth descubrió y conectó al radio con Android cerrado temporalmente. El radio volvió a anunciar sin reset ni cambio de vínculo.

### Fase 2 — handshake y una orden reversible desde macOS — completada

Con permiso explícito y fuera de una sesión crítica, portar el handshake ya recuperado y reproducir una sola operación de bajo riesgo —por ejemplo, variar un paso de potencia— desde macOS. Restaurar inmediatamente el estado y comparar la respuesta del radio y del grupo con la app oficial.

**Go** si CoreBluetooth completa el handshake local recuperado, el radio acepta el frame y la restauración es determinista.
**Revisar** si el periférico sólo admite un central a la vez, no vuelve a anunciar al soltar Android o la respuesta observada difiere de la APK; en ese caso se corrige la secuencia antes de ampliar el alcance.

**Salida obtenida — GO:** el handshake `PWOK` se validó, la sincronización terminó y las dos escrituras A1 —variación y restauración— recibieron acuse más notificación `FEC8`. Android volvió a conectar y mostró el valor base.

### Fase 3 — vertical funcional — en curso

Construir un cliente mínimo con:

- conexión/reconexión;
- selección de grupos;
- modos Off/M/TTL cuando el modelo los admita;
- potencia o compensación;
- modelado, beep global y standby general;
- disparo de prueba con una acción explícita;
- escenas guardadas localmente.

Solo después conviene añadir Multi, zoom, importación/exportación, atajos globales y soporte de varias familias.

### Corte visual SwiftUI — completado parcialmente

Se construyó una app macOS nativa con tres variantes evaluables —Canales, Inspector y Matriz—, sesión CoreBluetooth compartida, conexión visual, Código del radio protegido en UI y opt-in de persistencia local, sliders discretos de potencia, controles de modelado, borradores locales y **Aplicar** explícito. La UI conserva siempre el aviso de que el transmisor todavía no expone una lectura completa de estado.

La vertical se probó contra el radio real desde la propia GUI: `PWOK` y `Sync` llevaron la sesión a `ready`; B pasó de `1/256 +0.0` a `1/256 +0.3` y volvió al valor base. En una segunda sesión, B conservó `1/512 +0.0`, pasó de modelado apagado a fijo 25% y volvió a apagado. Las cuatro escrituras recibieron acuse GATT y notificación `FEC8`. Después de cada sesión el Mac se desconectó y Android recuperó el enlace GATT. No hubo disparo.

Ese fue el allowlist del corte físico anterior. La continuación lo sustituyó por validación basada en perfil y snapshot completo: B queda bloqueado mientras su baseline `1/512` contradiga el rango común `1/256`, y C sigue como candidato hasta completar su primera prueba reversible. La escala manual por modelo y modelado fijo `10...100` funcionan en un modo demo que no inicializa Bluetooth; ampliar las mutaciones reales sigue siendo gradual por comando, flash y firmware.

## Continuación de la vertical local — 2026-08-04

### Catálogo y escala recuperados de Godox Flash 1.3.3

El catálogo integrado `assets/lights_en.json` contiene 67 modelos: 1 con mínimo `1/512`, 34 con `1/256`, 23 con `1/128`, 1 con `1/64`, 5 con `1/32` y 3 con `1/16`. El estado técnico local añadió AD600Pro II con `minPower: 512`, ausente del catálogo integrado. El prototipo conserva los nombres y mínimos recuperados y añade entradas genéricas para configurar un modelo no listado sin inventar su identidad.

El catálogo actual del prototipo incorpora además **AD400Pro II** como una entrada independiente con mínimo `1/512`, respaldada por la [ficha oficial de Godox](https://www.godox.com/product-e/AD400ProII.html). Esta incorporación posterior no modifica el conteo histórico de 67 modelos recuperados de la APK.

La escala de tercio de EV que genera la APK es:

```text
10, 13, 17, 20, 23, 27, 30, 33, 37 … 90, 93, 97, 100
```

Los sufijos reales son `.0`, `.3` y `.7`. En Manual, `powerByte = 100 - decimalPower`; por ejemplo, `27` representa `1/256 +0.7` y se transmite como `0x49`. Auto/TTL es la excepción: A1 transmite siempre `powerByte = 0x32`, aunque la app conserve por separado la potencia Manual anterior.

El selector de flashes calcula el rango común inicializando el denominador en 512 y reteniendo el menor denominador numérico de los modelos seleccionados. Por tanto, AD600 (`256`) + AD600Pro II (`512`) debe limitarse a `1/256`. El `minPower: 512` persistido actualmente en B es stale: la actividad sólo recalcula al añadir o quitar un modelo. El prototipo usa la intersección segura y advierte cuando algún flash individual tiene un rango más extendido.

### Qué no contiene el catálogo

`LightData` sólo modela nombre, imagen, subtítulo, `minPower`, posición y selección. No describe capacidad, rango ni pasos de modelado, ni soporte de beep por modelo. Esas propiedades permanecen explícitamente sin verificar.

El layout oculto de modelado declara un slider entero `0...100`, pero el encoder sólo reconoce `PROP`, `25%` y `100%`; nunca lee `progress`. El prototipo enlaza correctamente fijo `10...100` con A1 byte 6 y conserva el modo en A1 byte 8. Los puntos distintos de 25% sólo están comprobados por codec/pruebas locales hasta completar observación física.

El beep usa dos niveles confirmados estáticamente. `getAllData` escribe el master `FlashData.voice` en `A0[4]`; `getSingleGroupData` convierte cada `FlashGroupData.voice` a `0/1` y lo escribe en `A1[7]`. El único toggle de sonido de Godox Flash asigna el mismo valor a todos los grupos, actualiza el master, persiste el conjunto y envía A0 antes de todos los A1. El prototipo replica esa decisión global: construye una instantánea A0 completa con los defaults observados para campos aún no editables, actualiza A0[4] y todos los A1[7], y confirma A0 por GATT antes de recorrer los A1 por GATT + FEC8.

Standby quedó localizado en `A0[11]`. El prototipo lo envía como cambio A0-only y preserva sin reescribir los snapshots A1 de todos los grupos, de modo que reanudar no inventa modos, potencias ni estados de modelado. Tanto el efecto audible del beep como el efecto físico de standby siguen pendientes de prueba con el radio real.

### Grupos y perfil del transmisor

La app crea 16 slots (`0–9`, `A–F`) y el codec A1 los mapea directamente a `00–0F`. El perfil GDBH cae en la familia que la APK marca como Flash+LED, pero el nombre BLE no identifica modelo, revisión ni firmware y la evidencia estática no demuestra que los 16 grupos sean físicamente operables. La UI puede configurarlos; la allowlist física continúa ampliándose uno por uno con restauración exacta.

El snapshot técnico local más reciente fue:

```text
B: F0 A1 07 0B 01 5A 00 00 00 00 B2
C: F0 A1 07 0C 01 49 00 00 01 00 F7
```

B contiene AD600 + AD600Pro II y está fuera de la intersección segura mientras siga en `1/512`; el prototipo bloquea una prueba reversible porque no podría restaurar ese valor sin violar el perfil común. C contiene AD400Pro y es el siguiente candidato: manual, `1/256 +0.7`, modelado proporcional, beep off y compensación cero. Su incorporación a la allowlist requiere todavía confirmar el equipo físico, hacer una variación de un paso, recibir GATT/FEC8 y restaurar exactamente el frame anterior.

La vertical implementa esa incorporación como un lease efímero ligado al UUID y a una sesión autenticada. Tras cinco confirmaciones de preflight, sólo permite reducir C de `decimalPower 27` a `23` durante 90 segundos, preservando modelado proporcional, beep apagado, modo manual y compensación cero. El candidato exacto es `F0 A1 07 0C 01 4D 00 00 01 00 E8`. Recibir transporte y restaurar no basta para promoverlo: también exige observación física y verificación posterior del baseline desde Android.

En la comprobación de sólo lectura de esta continuación, Godox Flash estaba abierta y escaneando, pero mostraba **Connect** y no tenía una sesión GATT activa. Este estado debe volver a comprobarse después de cualquier prueba.

### Garantías nuevas del prototipo

- La instantánea A1 conserva modo, potencia Manual, intensidad de modelado, beep subordinado, modo de modelado y compensación; ya no fuerza bytes desconocidos a cero. La instantánea A0 conserva beep, modelado global, ajuste relativo, Multi, standby y contador, con defaults completos recuperados de la APK para los campos sin control visual.
- Potencia, modelado y modo tienen indicadores de borrador separados. Beep es una sola decisión global A0+A1 y standby una decisión A0-only.
- M y Auto/TTL son editables. Auto transmite modo `0x00`, potencia `0x32` y compensación neutra, mientras la potencia Manual queda guardada localmente para restaurarla al volver a M. Active/off conserva el último modo activo M o Auto/TTL; Multi no se convierte ni se ofrece como modo editable.
- Cada write A1 físico conserva antes un punto durable de recuperación. Cuando llegan acuse GATT + FEC8, la app adopta el snapshot enviado como referencia actual, limpia ese punto y puede continuar con el siguiente grupo. Sólo un resultado incierto mantiene el gate global y obliga a reconectar el mismo radio para reaplicar el snapshot seguro registrado.
- La allowlist real queda ligada al UUID CoreBluetooth del radio concreto, al perfil, a la selección exacta de flashes y a tipos/valores concretos de cambio. Cambiar radio, perfil o modelos invalida la autorización y exige un snapshot fresco y una nueva validación; una restauración tampoco puede reenviarse a otro periférico.
- Para A1, una notificación FEC8 anterior al acuse GATT se ignora, en vez de adjudicarse al write encolado. Después del acuse se exige al menos el prefijo `F0 A1`: es exactamente lo máximo que valida `CommandPolicy` en la APK, que no compara grupo, cuerpo ni CRC. A0 no hereda esa espera: su ruta normal se completa sólo por GATT; cualquier eco A0 por FEC8 es informativo.
- El snapshot de recuperación se persiste antes del write con UUID, grupo y bytes A1, sin credenciales. En la primera sincronización app → radio no representa el estado físico anterior —que sigue siendo ilegible—, sino el valor deseado que puede reaplicarse de forma idempotente. La app bloquea el cierre normal y, tras reinicio, sólo permite reconectar al UUID original; un registro corrupto o un fallo al guardar/limpiar bloquea nuevas escrituras.
- Los grupos de trabajo delimitan qué A1 puede sincronizar la app. La visibilidad es un filtro local separado, compartido por las tres vistas, que nunca emite BLE, impide ocultar todos los grupos visibles y reubica la selección del Inspector.
- La aplicación incluye un transporte simulado explícito mediante `--mock-radio`; nunca se activa como fallback. Con Bluetooth real, el workspace sólo se habilita después de autenticar, entregar el Sync técnico, confirmar A0 por GATT y confirmar en serie los A1 de todos los grupos de trabajo por GATT + FEC8.
- `Test` se incorporó únicamente como acción global explícita por FFF1, sin reintento ni confirmación óptica. El builder A0 ya cubre beep y standby desde una instantánea completa; siguen ausentes `Pset`, edición Multi/canal, cambio de Código del radio, OAD y firmware.

La compilación y las pruebas byte a byte cubren perfiles `1/512`, `1/256` y `1/128`, límites e índices, modelado off/proporcional/fijo 10/25/50/75/100, A0 completo y round-trip, beep global A0+A1, standby A0-only, M/Auto TTL con potencia transmitida `0x32`, grupos A/B/C/0, CRC, sincronización forzada A0 → B → C antes de `ready`, presets nombrados y persistencia versionada del workspace mediante almacenamiento inyectable.

## Arquitectura propuesta

- **App:** SwiftUI/AppKit para una ventana compacta, siempre visible opcionalmente y cómoda junto al software tethered.
- **Transporte:** interfaz `DeviceTransport` con implementación `CoreBluetoothTransport`. No se necesita RFCOMM para el transmisor conectado; sólo tendría sentido como perfil futuro para otro hardware confirmado.
- **Codec:** módulo sin UI, versionado por familia/firmware, que convierte entre estado de dominio y frames binarios.
- **Sesión:** cola serial de comandos, timeout, retry acotado, reconexión y reconciliación de estado. No se deben mandar varias escrituras Bluetooth concurrentes sin conocer las reglas del firmware.
- **Modelo:** transmisor, canal/ID, 5 o 16 grupos, capacidades por grupo y límites de potencia propios del flash seleccionado.
- **Persistencia:** escenas locales; ningún requisito de cuenta. Identificadores sensibles truncados en diagnósticos.
- **Seguridad operativa:** el disparo nunca ocurre al conectar o cargar una escena; requiere acción deliberada. La app debe mostrar desconexión/estado incierto y evitar “confirmar” cambios que el radio no reconoció.

## Veredicto

| Dimensión | Evaluación | Motivo |
| --- | --- | --- |
| Hardware/API de macOS | **Alta viabilidad** | Apple ofrece APIs públicas para BLE/GATT y RFCOMM. |
| Ruta transmisor → flashes | **Alta viabilidad** | La conserva el radio Godox; no hay que reimplementar Godox X. |
| Compatibilidad del radio conectado | **Alta, confirmada nativamente desde macOS** | CoreBluetooth descubrió, autenticó y controló el radio; variación y restauración recibieron acuse más notificación. |
| Operación sin cuenta | **Confirmada en el protocolo** | La cuenta sólo desbloquea código de la app oficial; el handshake BLE no usa token ni backend. |
| Recuperación del protocolo | **Riesgo bajo-medio** | Transporte, UUIDs, autenticación, encuadre A0/A1 y CRC ya están recuperados; falta ampliar la matriz y probar variantes. |
| MVP útil para tethering | **Recomendado** | El conjunto inicial de grupos, potencia, modos, modelado, beep, test y presets es acotado. |

La decisión correcta es avanzar a la **vertical funcional de escritorio** sobre el transporte y codec ya probados. La incertidumbre restante está en la lectura/reconciliación de estado, la cobertura de comandos y las variantes de firmware; ya no existe una barrera demostrada de plataforma, cuenta, transporte o autenticación para el radio presente.
