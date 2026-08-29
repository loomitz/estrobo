# Estrobo iOS — matriz de pruebas físicas

Esta matriz prepara la validación en iPhone y iPad. Un build o una prueba en Simulator no valida CoreBluetooth, AccessorySetupKit, el enlace de radio ni el resultado óptico.

## Identificación de la corrida

| Campo | Valor |
| --- | --- |
| Fecha y responsable | Pendiente |
| Commit o diff probado | Pendiente |
| Modelo de iPhone/iPad | Pendiente |
| iOS/iPadOS y build | Pendiente |
| Modelo de transmisor | Godox X3Pro; confirmar variante exacta |
| Firmware del transmisor | Pendiente |
| Flashes y firmware | Pendiente |
| Bundle ID de desarrollo | Pendiente |
| Tipo de firma | Desarrollo local; sin upload |

## Gate de seguridad para Test y Multi

No ejecutar un destello físico hasta que la persona responsable confirme por escrito en la corrida:

- X3Pro y flashes preparados;
- ninguna otra app conectada;
- entorno ópticamente seguro;
- potencia común mínima seleccionada;
- Multi comienza con 2 destellos y 2 Hz.

| Confirmación | Responsable | Hora |
| --- | --- | --- |
| Equipo preparado | Pendiente | Pendiente |
| Radio exclusivo | Pendiente | Pendiente |
| Entorno seguro | Pendiente | Pendiente |
| Potencia mínima | Pendiente | Pendiente |
| Multi 2 × 2 Hz | Pendiente | Pendiente |

## Evidencia de publicidad Bluetooth

Capturar varias muestras después de apagar y encender el X3Pro. No registrar Código del radio ni payloads de autenticación.

| Dato | Muestra 1 | Muestra 2 | Muestra 3 | Estable |
| --- | --- | --- | --- | --- |
| Nombre local OTA | Pendiente | Pendiente | Pendiente | Pendiente |
| Service UUIDs anunciados | Pendiente | Pendiente | Pendiente | Pendiente |
| Overflow/Solicited UUIDs | Pendiente | Pendiente | Pendiente | Pendiente |
| Company ID | Pendiente | Pendiente | Pendiente | Pendiente |
| Company ID + longitud de Manufacturer Data | Pendiente | Pendiente | Pendiente | Pendiente |
| Claves + longitudes de Service Data | Pendiente | Pendiente | Pendiente | Pendiente |
| Connectable | Pendiente | Pendiente | Pendiente | Pendiente |
| UUID local de CoreBluetooth | Pendiente | Pendiente | Pendiente | No se supone estable entre plataformas |

No crear un descriptor AccessorySetupKit hasta confirmar al menos un Service UUID anunciado o Company ID estable. FFF0 y FEC0 descubiertos después de conectar no cuentan como evidencia de advertisement.

## Matriz de comportamiento

Para cada fila registrar por separado:

1. entrega GATT;
2. confirmación FEC8 cuando corresponde;
3. observación física/óptica.

| Escenario | Pasos | Resultado esperado | GATT | FEC8 | Físico | Evidencia |
| --- | --- | --- | --- | --- | --- | --- |
| Permiso concedido | Explicar permiso, conceder, buscar | Scan y conexión disponibles | N/A | N/A | N/A | Pendiente |
| Permiso denegado | Denegar desde prompt/Ajustes | Explicación y recuperación; sin scan | N/A | N/A | N/A | Pendiente |
| Bluetooth apagado/encendido | Apagar y reactivar Bluetooth | Estado explícito, sin write diferido | N/A | N/A | Ningún destello | Pendiente |
| Conexión y PWOK | Buscar, elegir UUID, autenticar | Ready sólo tras PWOK + Sync | Pendiente | N/A | Ningún destello inesperado | Pendiente |
| Sync | Conectar y sincronizar | Estrobo sobrescribe estado local | Pendiente | Según A1 | Confirmar escena | Pendiente |
| A0 antes de A1 | Cambiar control global dependiente | Orden A0 → A1 serial | Pendiente | Pendiente | Confirmar | Pendiente |
| Gesto continuo | Arrastrar potencia y soltar | Cero writes intermedios y uno final | Pendiente | Pendiente | Un cambio final | Pendiente |
| Test cancelado | Abrir confirmación y cancelar | Cero writes y cero destellos | Ausente | N/A | Ausente | Pendiente |
| Test confirmado | Confirmar una vez | Un Test; sin retry automático | Pendiente | N/A | Un destello | Pendiente |
| Multi mínimo | 2 destellos, 2 Hz, potencia mínima | Secuencia única y deliberada | Pendiente | Pendiente | 2 destellos | Pendiente |
| Pérdida de alcance | Alejar durante idle y durante write | Desconexión; journal si write incierto | Pendiente | Pendiente | Registrar | Pendiente |
| Radio ocupado | Conectar Estrobo Mac/u otra app primero | Error accionable; no interferencia | N/A | N/A | Ausente | Pendiente |
| Pantalla bloqueada | Bloquear con debounce/gesto pendiente | Sin Test, Multi ni write diferido | Ausente | Ausente | Ausente | Pendiente |
| Cambio de app | Ir a background antes de 700 ms | Cancela scan/debounce; exige reconexión | Ausente | Ausente | Ausente | Pendiente |
| Interrupción | Recibir llamada/overlay del sistema | Igual que inactive; sin write silencioso | Ausente | Ausente | Ausente | Pendiente |
| Terminación por memoria | Terminar proceso con journal preparado | Recuperación obligatoria al abrir | Pendiente | Pendiente | Registrar | Pendiente |
| Force quit | Forzar cierre en distintos estados | No depende de callback de terminación | Pendiente | Pendiente | Registrar | Pendiente |
| UUID distinto | Intentar recuperar con otro radio | Recuperación bloqueada | Ausente | Ausente | Ausente | Pendiente |
| Reconexión correcta | Conectar UUID original | Permite preparar y recuperar | Pendiente | Pendiente | Confirmar | Pendiente |
| Actualización | Instalar build nuevo encima | Preserva/migra catálogo, vault y journal | N/A | N/A | N/A | Pendiente |
| Reinstalación | Borrar e instalar de nuevo | Documentar qué persiste en Keychain | N/A | N/A | N/A | Pendiente |

## AccessorySetupKit

| Comprobación | Resultado |
| --- | --- |
| Import y compilación de AccessorySetupKit en target iOS 18+ | PASS local con `make ios-accessory-setup-check`; sólo compilación generic iOS, sin hardware |
| Descriptor basado sólo en datos observados | Bloqueado por evidencia física |
| Picker encuentra exclusivamente el X3Pro | Pendiente, dispositivo físico |
| Permiso concedido/denegado | Pendiente, dispositivo físico |
| `bluetoothIdentifier` resuelve con CoreBluetooth | Pendiente, dispositivo físico |
| UUID estable tras reboot/update/reinstall | Pendiente; no asumir |

Si el descriptor no identifica al X3Pro de forma estable, conservar CoreBluetooth foreground-only y documentar AccessorySetupKit como no adoptado.

## Cierre de una corrida

- Adjuntar logs redactados y capturas.
- Confirmar que ningún log contiene Código del radio ni payload de autenticación.
- Registrar versiones exactas y el UUID local usado, sin afirmar equivalencia Mac/iOS.
- Marcar por separado los escenarios no ejecutados y su razón.
- No concluir “Bluetooth validado” sin hardware ni “listo para TestFlight” sin repetir gates con Xcode estable.
