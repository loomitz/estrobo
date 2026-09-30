# Spike de AccessorySetupKit para Godox X3Pro

## Resultado que debe producir

El spike responde una sola pregunta: ¿puede iOS identificar y autorizar de forma estable al X3Pro usando únicamente datos realmente anunciados por el accesorio?

No sustituye CoreBluetooth para GATT y no promete restauración en background.

## Fase A — sonda de advertisement

La sonda se compila en un target de diagnóstico separado que **no** declara `NSAccessorySetupKitSupports`. Usa CoreBluetooth foreground-only y `scanForPeripherals(withServices: nil)` para observar únicamente:

- `peripheral.name` y nombre local;
- Service UUIDs anunciados;
- Overflow y Solicited Service UUIDs anunciados;
- Company ID y longitud de Manufacturer Data, nunca sus bytes;
- claves y longitudes de Service Data, nunca sus valores;
- indicador connectable;
- RSSI;
- UUID local de CoreBluetooth siempre redactado como `CB-REDACTED-XXXX`.

No conserva ni registra payloads publicitarios, códigos del radio ni material de autenticación. La corrida física del 29 de agosto de 2026 produjo tres muestras independientes con `GDBH-A681` + `FFC0`; la evidencia sanitizada está en `IOS-BLUETOOTH-EVIDENCE.md` y `IOS-PHYSICAL-TEST-MATRIX.md`.

FFF0/FEC0/FFF1/FEC7/FEC8 descubiertos tras conectar no demuestran que esos servicios o características se anuncien.

### Implementación diagnóstica

`EstroboAdvertisementProbe` es una app separada de `EstroboIOS`. Su Info.plist
declara únicamente el permiso Bluetooth de foreground y omite
`NSAccessorySetupKitSupports`. La sonda llama
`scanForPeripherals(withServices: nil)` y conserva sólo:

- `peripheral.name` y local name;
- Service UUIDs anunciados;
- Overflow y Solicited Service UUIDs anunciados;
- Company ID extraído de los primeros dos bytes de Manufacturer Data y la
  longitud total, nunca los bytes;
- claves y longitudes de Service Data, nunca sus valores;
- connectable, UUID local de CoreBluetooth, RSSI y número de muestras.

El mismo resumen seguro aparece en la UI y en Console bajo el subsystem
`mx.loo.estrobo.advertisement-probe`.

Compilación reproducible con Xcode beta:

```sh
make ios-advertisement-probe-check
```

Captura física:

1. Ejecutar `make ios-project`.
2. Abrir `ios/EstroboIOS.xcodeproj` en Xcode beta.
3. Seleccionar el scheme `EstroboAdvertisementProbe` y un iPhone o iPad físico.
4. Ejecutar la app, tocar **Scan** y repetir la muestra después de apagar y
   encender el accesorio y después de reiniciar la app.
5. Registrar únicamente los campos mostrados por la sonda en
   `docs/IOS-PHYSICAL-TEST-MATRIX.md`.

## Fase B — picker de AccessorySetupKit

Sólo se habilita si la Fase A encuentra un Service UUID anunciado o Company ID estable. La evidencia física encontró `FFC0` como Service UUID anunciado en 3/3 corridas, por lo que la Fase B está habilitada únicamente en el target diagnóstico.

### App diagnóstica ejecutable

`EstroboAccessorySetupSpike` es una app separada, con deployment target iOS 26.1. No está enlazada a `EstroboIOS` y su Info.plist declara exactamente:

- `NSAccessorySetupKitSupports = [Bluetooth]`;
- `NSAccessorySetupBluetoothServices = [FFC0]`;
- `NSAccessorySetupBluetoothNames = [GDBH-A681]`;
- `NSBluetoothAlwaysUsageDescription`;
- sin Company ID, `UIBackgroundModes` ni restoration identifier.

La documentación web de Apple y el Xcode 27 beta usado en esta corrida no coinciden en el nombre de la primera clave. El template y los binarios del SDK local validan `NSAccessorySetupKitSupports`; esa es la autoridad de ejecución para esta corrida beta. La discrepancia debe revisarse de nuevo antes de mover el experimento a un Xcode estable.

La app usa:

- `ASAccessorySession`;
- `ASDiscoveryDescriptor`;
- `ASPickerDisplayItem`;
- `showPicker(for:)` y discovery administrado por el sistema;
- `filterDiscoveryResults`, `ASDiscoveredAccessory` y `updatePicker(showing:)`, disponibles desde iOS 26.1;
- `ASAccessory.bluetoothIdentifier`.

El descriptor combina el Service UUID verificado `FFC0` con el nombre observado `GDBH-A681`. Como `bluetoothNameSubstring` no garantiza igualdad, cada `accessoryDiscovered` se filtra además en memoria exigiendo nombre local exactamente igual y presencia de `FFC0`. Sólo una coincidencia exacta puede llegar al picker; una segunda coincidencia detiene la sesión.

La selección del picker crea una autorización persistente de AccessorySetupKit para esta app. No se declara pairing, rename, bridging ni confirm authorization. Al reactivar la sesión se consulta `session.accessories`: cero autorizaciones permiten mostrar el picker, una autorización se valida y resuelve, y más de una detiene el experimento.

Después de un evento autorizado, y sólo entonces, la app crea `CBCentralManager`, espera `.poweredOn` y llama una única vez a `retrievePeripherals(withIdentifiers:)`. Verifica exactamente un resultado con el mismo UUID. No implementa fallback a scan ni contiene rutas de connect, GATT discovery, read, write o notify.

El UUID completo existe sólo en memoria para correlación y resolución. UI y OSLog muestran únicamente `CB-REDACTED-XXXX`; los errores se reducen a domain + code. Al entrar en background la sesión se invalida, se libera CoreBluetooth y se descartan callbacks tardíos mediante generaciones de sesión y picker.

### Gates reproducibles

```sh
make ios-accessory-spike-check
# Compila también la sonda y valida la separación/configuración de ambos targets:
make ios-accessory-setup-check
```

El gate exige que main y probe sigan sin ASK, que el plist del diagnóstico
coincida exactamente con la evidencia y que el código no contenga APIs de scan
CoreBluetooth, conexión, GATT, lectura, escritura, notify, pairing,
actualización de autorización, rename o restauración. El binario firmado se
inspecciona además para aceptar únicamente
`retrievePeripheralsWithIdentifiers:` y una llamada explícita a
`removeAccessory:completionHandler:`.

Estado de la corrida actual:

- build unsigned Swift 6 strict concurrency: PASS;
- build Apple Development local, perfil embebido y allowlist: PASS;
- instalación y launch en iPhone 13 Pro con iOS 26.6.1: PASS;
- activación de `ASAccessorySession`: PASS;
- autorización persistente: PASS; iOS omitió el picker porque ya existía;
- resolución CoreBluetooth: PASS exactamente una vez, con el mismo UUID local
  redactado observado por la sonda y sin conexión;
- control de revocación explícito: PASS de código, revisión, build firmado,
  instalación, launch y ejecución física;
- verificación en sesión nueva: PASS; cero autorizaciones persistidas;
- picker de autorización nueva y exclusividad visual: PASS en esta corrida; un
  candidato `GDBH-A681`, seleccionado deliberadamente;
- autorización después de `Set Up`: PASS y disponible en una activación
  posterior;
- resolución después de `Set Up`: PASS exactamente una vez, mismo UUID local
  redactado y sin conexión;
- persistencia después de terminar y relanzar el proceso: PASS; autorización
  exacta disponible y resolución repetida exactamente una vez, sin conexión;
- background/foreground: PASS por atestación del usuario; la sesión se detuvo
  y no hubo reactivación ni resolución automática al regresar;
- reboot del iPhone: PASS por atestación del usuario; autorización disponible,
  mismo UUID local redactado y resolución única sin conexión;
- update in-place: PASS por atestación del usuario; build diagnóstico 1 → 2,
  autorización disponible, mismo UUID local redactado y resolución única sin
  conexión;
- reinstall: PASS por atestación del usuario; borrar únicamente la app
  diagnóstica eliminó su autorización ASK y la reinstalación quedó sin una
  autorización persistida;
- cancelación del picker: PASS por atestación del usuario; no creó autorización
  ni inició CoreBluetooth;
- hardening posterior a la corrida: PASS local; `pickerDidDismiss` invalida la
  generación y limpia toda coincidencia, y la verificación de revocación ya no
  puede coexistir con textos anteriores `Authorized`/`Resolved`; este diff no
  se reinstaló ni se repitió físicamente;
- GATT, reads, writes y destellos: ninguno.

La evidencia UI sanitizada incluye la
[ruta persistida](screenshots/ios/physical-2026-08-29-x3pros-ask-persisted-resolution-01.png)
y la [revocación verificada con picker fresco](screenshots/ios/physical-2026-08-29-x3pros-ask-fresh-picker-exclusive-01.png),
seguida por la [autorización fresca persistida y resuelta](screenshots/ios/physical-2026-08-29-x3pros-ask-fresh-authorization-resolution-01.png)
y la [persistencia tras relaunch del proceso](screenshots/ios/physical-2026-08-29-x3pros-ask-process-relaunch-persistence-01.png).
Revocar esa autorización es un cambio deliberado de estado: sólo se permite
tras resolución exacta, requiere una confirmación destructiva en la UI y
después invalida la sesión. Una activación nueva debe comprobar cero
autorizaciones antes de habilitar el picker; error, background, UUID distinto o
múltiples autorizaciones conservan el latch fail-closed.

## Límite de plataforma

El diagnóstico usa deliberadamente iOS 26.1 para poder verificar igualdad exacta antes de mostrar un candidato. Ese mínimo no cambia el deployment target iOS 18 de `EstroboIOS`. El target diagnóstico es exclusivo de iOS, Catalyst está deshabilitado y un SDK sin AccessorySetupKit debe fallar de forma explícita.

## Stop rules

- No enlazar el spike a la app principal ni añadir declaraciones ASK a main o probe.
- No mostrar el picker si la app no está activa, existe otra app/CoreBluetooth manager compitiendo o hay más de una coincidencia exacta.
- No aceptar estados awaiting/unauthorized, descriptor distinto, UUID ausente, cambio de UUID ni resolución cero/múltiple.
- Pairing, bridging, rename, confirm/finish/fail authorization y remove automático son STOP.
- Background invalida la sesión; volver a foreground nunca reutiliza una sesión invalidada.
- Si el picker confunde accesorios o cambia entre reinicios: no adoptar AccessorySetupKit.
- Si Info.plist y descriptor divergen: fallar el build/test de configuración.
- Si AccessorySetupKit no es estable: mantener CoreBluetooth foreground-only y reportar evidencia.

La validación física de este diagnóstico no autoriza GATT, Sync, Test ni Multi.
La viabilidad del spike recibe GO limitado con la matriz diagnóstica ejecutada.
La adopción en `EstroboIOS` permanece NO-GO dentro de esta corrida: requiere una
decisión de producto separada sobre reautorización tras reinstall y no autoriza
background BLE, GATT ni cambios en la app principal.
