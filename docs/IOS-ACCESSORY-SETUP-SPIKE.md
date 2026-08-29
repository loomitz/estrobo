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
- UUID local de CoreBluetooth.

No conserva ni registra payloads publicitarios, códigos del radio ni material de autenticación. Los metadatos se copian a `docs/IOS-PHYSICAL-TEST-MATRIX.md` después de varias muestras.

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

Sólo se habilita si la Fase A encuentra un Service UUID anunciado o Company ID estable. La integración usa APIs de iOS 18:

- `ASAccessorySession`;
- `ASDiscoveryDescriptor`;
- `ASPickerDisplayItem`;
- `showPicker(for:)`;
- `ASAccessory.bluetoothIdentifier`.

El descriptor incluye únicamente valores comprobados y declarados también en Info.plist. El nombre puede refinar una ancla real, pero no sustituirla.

El identificador autorizado se transforma a `RadioCandidate` y CoreBluetooth resuelve el periférico mediante `retrievePeripherals(withIdentifiers:)` antes de continuar con GATT.

### Módulo compilable, todavía no habilitado

`EstroboAccessorySetupSpike` importa `AccessorySetupKit` y expone una sola
fábrica de `ASDiscoveryDescriptor`. La fábrica requiere un
`VerifiedAdvertisementIdentity` con al menos uno de estos valores obtenidos en
la Fase A:

- Service UUID anunciado verificado;
- Bluetooth Company ID verificado.

Un substring de nombre es opcional y sólo refina uno de esos anclajes. El
módulo no contiene UUIDs, Company IDs ni prefijos de nombre de Godox.

```sh
make ios-accessory-spike-check
# Compila el módulo y la sonda y valida que ASK siga deshabilitado:
make ios-accessory-setup-check
```

Este framework no está enlazado a `EstroboIOS` y compilarlo no autoriza a
presentar el picker.

## Límite de plataforma

El spike importa `AccessorySetupKit` directamente y vive en un target separado,
exclusivo de iOS, con deployment target 18.0 y Catalyst deshabilitado. El target
no está enlazado a `EstroboIOS`; si el SDK seleccionado no contiene
AccessorySetupKit, su compilación debe fallar en vez de producir un módulo vacío.

No usar APIs que eleven el mínimo por encima de iOS 18, incluidos custom filtering de iOS 26.1 o presentation settings de iOS 26.

## Stop rules

- Sin Service UUID anunciado ni Company ID: no crear descriptor.
- No añadir `NSAccessorySetupKitSupports`, enlazar el spike a la app principal
  ni mostrar un picker hasta documentar evidencia física estable de Service
  UUID o Company ID en varias muestras y tras reiniciar accesorio y app.
- Si el picker confunde accesorios o cambia entre reinicios: no adoptar AccessorySetupKit.
- Si Info.plist y descriptor divergen: fallar el build/test de configuración.
- Si AccessorySetupKit no es estable: mantener CoreBluetooth foreground-only y reportar evidencia.

La validación final requiere iPhone o iPad físico; Simulator sólo verifica compilación y UI simulada.
