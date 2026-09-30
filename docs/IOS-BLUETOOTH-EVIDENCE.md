# Estrobo iOS — evidencia Bluetooth sanitizada

## Corrida 2026-08-29 — Godox X3ProS

**Estado:** publicidad Bluetooth y validación ASK completadas. En la app
principal se reportó una conexión física operativa. La validación de potencia
ha producido tres resultados `STOPPED`: primero los botones parecían no
responder, después `+` y `−` actualizaron pero el drag no, y en el build
posterior el slider cambió el valor pero el modo automático permaneció en
`Sincronizando…` indefinidamente. No hay evidencia suficiente para atribuir el
último valor a un write GATT, un acuse o un cambio físico. La causa del tercer
resultado quedó reproducida y la cuarta remediación se instaló, pero no llegó
a retest físico. Esa instalación está **SUPERSEDED** por un diff local posterior
que todavía **NO está instalado ni validado físicamente**. Test y Multi no se
ejecutaron.

Esta bitácora conserva únicamente metadatos publicitarios. No contiene código
del radio, Psub, PWOK, payloads de autenticación, bytes de Manufacturer Data,
valores de Service Data, Team ID ni identificadores completos del dispositivo.

## Entorno

| Campo | Valor sanitizado |
| --- | --- |
| Fuente de la última instalación física | `0bbc4a485f92ed066f61a7717a71c33348752202` + diff local vigente de slider global, reglas, composición Multi y acciones directas |
| Diff local posterior | Ninguno en código de la app; sólo el registro documental de la instalación |
| iPhone | iPhone 13 Pro (`iPhone14,2`) |
| iOS | 26.6.1 (`23G83`) |
| UDID físico | `0000…801E` |
| Developer Mode / trust | Habilitado / emparejamiento operativo por cable |
| Xcode | 27.0 beta (`27A5228h`) |
| SDK | iPhoneOS 27.0 (`24A5390e`) |
| Sonda | `mx.loo.estrobo.advertisement-probe`, Apple Development local |
| Provisioning | Perfil local existente; sin `-allowProvisioningUpdates` ni registro externo |
| Transmisor | Godox X3ProS, firmware V1.03 |
| Flash | Godox AD400 PRO II, firmware V1.21 |
| Grupos previstos | B y C |
| Potencia mínima común corregida | 1/512 |

La sonda se compiló, firmó, verificó e instaló antes de la corrida. Permaneció
foreground-only, sin AccessorySetupKit, conexiones GATT ni writes. La app
principal `EstroboIOS` se compiló nuevamente después del cierre de seguridad,
se verificó su firma, se instaló como `mx.loo.estrobo.dev` y se lanzó hasta su
UI inicial. En ese punto todavía no se había conectado al transmisor; el
intento físico posterior se registra a continuación.

El build físico inicial de esta bitácora todavía usaba una confirmación
separada después de PWOK + Sync. El diff local de esa etapa sustituyó ese flujo por
la sincronización directa que ya usa macOS: tras el settle técnico programa A0
y después la secuencia A1 configurada, sin un botón adicional. El heartbeat
permanece diferido por fase hasta Ready. Cancelar, background y desconexión
siguen vaciando tareas y colas; una sesión Ready estable puede conservarse al
cambiar de app, y una pérdida real sólo intenta reconectar en foreground al
identificador exacto. El build entonces vigente quedó instalado, pero estos
comportamientos aún no constituyen evidencia física.

## Intento de smoke de la app principal

**Resultado: STOPPED.** El operador confirmó que la conexión física con el
X3ProS funciona. Al intentar ajustar la potencia, los botones `+` y `−`
parecieron no responder correctamente; el control de potencia se considera no
confiable y la corrida se detuvo antes de continuar.

No se recibió atestación sobre el preview, el orden de writes, el estado Ready
ni la observación física u óptica. Test y Multi no se ejecutaron.

## Remediación local posterior al STOPPED

Después de detener la corrida se rediseñó localmente la superficie de Grupos:
la potencia quedó inline mediante `−`, un slider discreto y `+`; los límites
direccionales se reflejan en el estado habilitado de cada botón; y el selector
Automática/Con botón quedó únicamente en Ajustes. Test pasó a ser una acción
directa de un toque en Grupos, pero conserva sus gates, single-flight, ausencia
de cola y ausencia de reintento automático.

La remediación pasó la evidencia local/simulada y el build físico resultante
`mx.loo.estrobo.dev` 0.1.0 (1) quedó firmado, verificado, instalado sobre la app
existente y abierto en el iPhone. Todavía no existe evidencia funcional u
óptica del rediseño. No se ejecutó Test ni Multi y no se modifica el resultado
`STOPPED` de la corrida anterior.

## Retest del build remediado

**Resultado: STOPPED.** En el iPhone físico, los botones `+` y `−` sí
actualizaron el valor visible. Durante el drag, el slider no actualizó ese
valor. La corrida se detuvo para corregir la interacción antes de continuar.

Esta observación sólo valida la respuesta visible de los controles. No se
atribuye entrega GATT, acuse ni cambio físico al transmisor o al flash. Test y
Multi no se ejecutaron.

## Segunda remediación local posterior al retest

El drag ahora conserva un índice transitorio local que actualiza de inmediato
el valor visible y accesible en cada paso. Mientras existe una edición
interactiva, el controller no persiste toda la biblioteca por tick: conserva el
borrador y realiza una sola persistencia final cuando termina o se cancela el
último gesto. La entrega automática continúa bloqueada durante el drag y sólo
puede programar el valor final después de soltar.

Antes de implementar la nueva composición se generó y revisó una referencia
visual con ImageGen. Potencia relativa, Beep, Standby y Multi quedaron dentro
de una sección compacta Control global en Grupos; desapareció el destino
Global independiente. iPhone conserva sólo Grupos, Presets y Ajustes. El aviso
automático pasó en esa etapa a un microestado `Sincronizando…` / `Actualizado`
que desaparecía sin mostrar una barra de aplicación manual. El diff local
posterior elimina también ese estado fugaz de `Actualizado`.

Evidencia local/simulada posterior: build Generic Simulator con warnings como
errores PASS; 16 core + 2 Bluetooth + 3 persistence PASS; unitarias iOS 18/18
en iPhone y 18/18 en iPad; UI 16/16 en iPhone y 8 PASS + 8 skips intencionales
en iPad. El mismo diff quedó firmado, verificado, instalado como
`mx.loo.estrobo.dev` 0.1.0 (1) sobre la app existente y abierto en
`0000…801E`. La instalación no sustituye el segundo retest funcional ni cambia
por sí sola el resultado físico anterior `STOPPED`. Test y Multi no se
ejecutaron.

## Tercer retest físico y cuarta remediación local

**Resultado físico: STOPPED.** Al cambiar la potencia mediante el slider, el
valor visible se actualizó pero el aviso automático quedó en
`Sincronizando…` de forma indefinida. No se atribuye un write, acuse ni cambio
físico a esa interacción. Test y Multi no se ejecutaron.

La investigación local aisló una cancelación táctil producida por el arbitraje
entre el slider y el scroll de la lista. El control trataba esa cancelación
como abandono total después de haber recibido un valor: conservaba el borrador
pero cancelaba la programación automática. La presentación, a su vez,
interpretaba cualquier borrador pendiente como sincronización activa. La
corrección considera terminado un gesto cancelado que ya produjo un valor,
mantiene la cancelación dura para teardown, background y pérdida de sesión, y
distingue `Cambio pendiente` de una sincronización realmente programada o en
I/O.

La misma iteración, precedida por referencias visuales de ImageGen, integra
Multi dentro de Grupos con entrada/salida directa y scrubbers discretos para
destellos y Hz; Standby también es directo. La sincronización inicial pasa a
ser automática después de conectar y la recuperación foreground conserva una
sesión Ready o busca una sola vez el identificador exacto si el enlace se
perdió. Todo lo descrito en este apartado es evidencia local/simulada hasta
repetir la corrida física.

Validación local de la cuarta remediación entonces vigente: 43/43 pruebas
Swift, 28/28 unitarias iOS en cada idiom, build con warnings Swift como
errores, UI 20/20 en iPhone
Simulator y 8 PASS + 12 omisiones intencionales en iPad Simulator. La revisión
independiente no dejó hallazgos P1/P2 abiertos. Estos resultados no sustituyen
el retest con el X3ProS y el flash; Test y Multi no se ejecutaron físicamente.

## Instalación física de la cuarta remediación

**Resultado: PASS de instalación.** Se construyó el diff entonces vigente para
arm64 con warnings Swift como errores y firma Apple Development local. Se verificaron la
firma, el bundle `mx.loo.estrobo.dev`, la versión 0.1.0 (1), la arquitectura y
la inclusión de `0000…801E` en el perfil existente. La instalación in-place
terminó correctamente sin `-allowProvisioningUpdates`, registro externo,
commit ni publicación.

La app quedó cerrada. Abrirla podría iniciar conexión y Sync directo si existe
una preferencia automática guardada; esa operación corresponde al siguiente
retest y no formó parte de esta autorización de instalación. No hubo conexión
al radio, writes físicos, Test ni Multi.

## Diff local posterior a la última instalación — 2026-08-30

**Estado al iniciar esta sección: NO instalado y NO validado físicamente.** La
build que conservaba el PASS de instalación anterior quedó superada como
candidata de prueba por este WIP local. La instalación posterior se registra
por separado abajo y no convierte estas afirmaciones en validación funcional.

El diff posterior añade un slider global relativo con regla y rango visual
`−3…+3 EV` en pasos de 1/3 EV. El drag conserva sólo presentación; al soltar
realiza un commit final-only y atómico sobre los grupos Manual elegibles,
respeta el clamp común, deja intactos los grupos deshabilitados y vuelve
visualmente a 0 sin deshacer las nuevas potencias absolutas. Los sliders de
grupo y los scrubbers Multi también presentan marcas de regla.

El endurecimiento posterior hace que `touchCancel` vuelva a cancelar sin commit
ni programación automática. El slider global abre un token interactivo propio,
y conserva un ancla estable desde el inicio; los sliders de grupo y los
scrubbers Multi sólo actualizan su presentación durante el gesto antes de
entregar el valor final al soltar. Así no se persiste ni se programa un estado
intermedio y una cancelación no deja un borrador silencioso etiquetado como
sincronización.

`Detalles` permanece como acción textual visible. Durante Multi se oculta la
sección redundante `Grupos de trabajo`, pero cada participante conserva arriba
su acceso al mismo detalle. Beep, Standby y Multi son acciones directas: no
abren confirmación ni presentan un estado fugaz de completado. El feedback
sutil sólo existe mientras hay un debounce realmente armado o I/O activo y se
oculta al volver a reposo.

La presentación ya no deduce Test desde la última actividad genérica: consume
un resultado correlacionado con su intento y lo limpia al cancelar o resetear
la sesión. Beep y Standby publican además una procedencia directa durante toda
su secuencia, incluida la continuación A1 de Beep; así no aparece la barra
Aplicar ni en Automática ni en Con botón. Multi mantiene Apply sólo cuando la
preferencia Con botón lo exige deliberadamente.

Evidencia local final del diff: 44 Core + 6 persistence + 3 Bluetooth, 53/53;
`ios-check` PASS; unitarias iOS 29/29 en iPhone Simulator y 29/29 en iPad
Simulator; UI 23/23 en iPhone y 8 PASS + 15 omisiones intencionales en iPad;
`git diff --check` limpio. Estas pruebas no sustituyen una instalación ni una
validación física.

## Instalación física del diff vigente — 2026-08-30

**Resultado: PASS de instalación; validación funcional pendiente.** El diff
vigente se construyó para arm64 con warnings Swift como errores y Xcode beta.
Se verificaron firma Apple Development, entitlements, bundle
`mx.loo.estrobo.dev`, versión 0.1.0 (1) y perfil local que incluye
`0000…801E`, sin `-allowProvisioningUpdates` ni registro externo.

La instalación in-place terminó correctamente y la consulta posterior confirmó
el bundle y versión esperados. Estrobo estaba cerrada antes y no se invocó
`process launch`. La comprobación inmediata seguía sin proceso principal, pero
una comprobación tardía detectó el proceso; se terminó de forma explícita una
vez y otra comprobación volvió a encontrarlo. No se volvió a terminar para no
interferir con una posible apertura del usuario. El iPhone se desconectó después,
por lo que el estado final del proceso dejó de ser observable.

Test y Multi no se ejecutaron y no se recibió observación óptica. No existe
captura que permita atribuir o descartar conexión, Sync o GATT durante esa breve
ventana de proceso; por tanto no se afirma su ausencia. Este PASS sólo elimina
el gate de instalación: la validación de sliders, composición y feedback
continúa pendiente en hardware.

## Procedimiento

Cada muestra fue una corrida independiente:

1. detener y relanzar `EstroboAdvertisementProbe`;
2. apagar el X3ProS durante 5 segundos;
3. encenderlo en modo emparejamiento;
4. limpiar la lista, escanear, detener y abrir la observación;
5. registrar sólo los campos sanitizados de la UI.

El contador `Samples` representa advertisements duplicados recibidos durante
cada corrida; no sustituye las tres corridas independientes.

## Muestras

| Dato | Muestra 1 | Muestra 2 | Muestra 3 | Evaluación |
| --- | --- | --- | --- | --- |
| Nombre de periférico | `GDBH-A681` | `GDBH-A681` | `GDBH-A681` | Estable 3/3 |
| Nombre local OTA | `GDBH-A681` | `GDBH-A681` | `GDBH-A681` | Estable 3/3 |
| Service UUIDs anunciados | `FFC0` | `FFC0` | `FFC0` | Estable 3/3; ancla publicitaria válida |
| Overflow Service UUIDs | Ninguno | Ninguno | Ninguno | Ausencia estable 3/3 |
| Solicited Service UUIDs | Ninguno | Ninguno | Ninguno | Ausencia estable 3/3 |
| Company ID | Ninguno | Ninguno | Ninguno | No disponible como ancla |
| Longitud de Manufacturer Data | Ninguna | Ninguna | Ninguna | Manufacturer Data ausente |
| Service Data, claves + longitudes | Ninguno | Ninguno | Ninguno | Service Data ausente |
| Connectable | `true` | `true` | `true` | Estable 3/3 |
| RSSI | -38 dBm | -40 dBm | -49 dBm | Sólo contexto; no identidad |
| UUID local redactado | `CB-REDACTED-3364` | `CB-REDACTED-3364` | `CB-REDACTED-3364` | Igual en esta instalación; no extrapolar |
| Advertisements duplicados | 473 | 1447 | 2534 | Sólo contexto de recepción |

## Capturas sanitizadas

- [Muestra 1 — resumen](screenshots/ios/physical-2026-08-29-x3pros-advertisement-01-overview.png)
- [Muestra 1 — metadatos inferiores](screenshots/ios/physical-2026-08-29-x3pros-advertisement-01-metadata.png)
- [Muestra 2 — resumen](screenshots/ios/physical-2026-08-29-x3pros-advertisement-02-overview.png)
- [Muestra 3 — resumen](screenshots/ios/physical-2026-08-29-x3pros-advertisement-03-overview.png)

## Decisión AccessorySetupKit

**GO limitado para el experimento diagnóstico separado.** `FFC0` apareció
como Service UUID anunciado en 3/3 corridas independientes y puede anclar un
`ASDiscoveryDescriptor`; el nombre exacto observado `GDBH-A681` puede usarse
sólo como refinamiento de ese ancla.

Este GO no autoriza integrar AccessorySetupKit en `EstroboIOS`, declarar
background Bluetooth ni prometer restauración. El diagnóstico ya activó la
sesión, encontró una autorización persistente y resolvió su
`bluetoothIdentifier` con CoreBluetooth. Después revocó y verificó esa
autorización en una sesión nueva; el picker fresco mostró exactamente un
candidato `GDBH-A681`; después de `Set Up`, una activación nueva encontró la
autorización y resolvió el mismo identificador exactamente una vez, sin
conectar. El relaunch completo del proceso, background/foreground, reboot y
update in-place pasaron; la reinstalación quedó caracterizada: borrar la app
elimina su autorización ASK. La cancelación del picker también pasó. El permiso
Bluetooth denegado pertenece al smoke posterior de `EstroboIOS`; integrar ASK
en la app principal sigue fuera del alcance de esta corrida.

`FFC0` es evidencia publicitaria directa. Los servicios o características que
pudieran descubrirse sólo después de conectar no forman parte de esta decisión.

## Corrida AccessorySetupKit diagnóstica

**Estado actual:** app construida, firmada, verificada, instalada y lanzada;
activación, autorización persistente, resolución CoreBluetooth, revocación
verificada y picker fresco con un solo candidato observados en el iPhone
físico. `Set Up` creó una autorización nueva que persistió y volvió a resolverse
sin conexión.

El experimento vive sólo en `mx.loo.estrobo.accessory-setup-spike`, con mínimo
iOS 26.1. El plist permite exactamente Bluetooth, `FFC0` y `GDBH-A681`, sin
Company ID, background modes ni restauración. La app filtra manualmente
`ASDiscoveredAccessory` exigiendo igualdad del nombre local y presencia de
`FFC0` antes de mostrar un único candidato.

Seleccionar el candidato autoriza el accesorio de forma persistente para esta
app diagnóstica. Después de autorización, el único uso de CoreBluetooth es una
llamada a `retrievePeripherals(withIdentifiers:)`; no hay scan directo,
conexión, discovery GATT, lectura, escritura ni notify. La inspección del
binario firmado original encontró únicamente el selector de
`retrievePeripherals`. Después de autorizar explícitamente la revocación para
repetir el picker, el diagnóstico añadió una sola llamada confirmada por el
usuario a `removeAccessory`; el binario actualizado contiene únicamente esos
dos selectores ASK/CoreBluetooth permitidos.

La toolchain local Xcode 27.0 beta usa `NSAccessorySetupKitSupports`, aunque la
documentación web de Apple mostraba otro nombre de clave durante esta corrida.
Antes de cualquier adopción con Xcode estable se debe repetir esa validación de
plist/SDK.

### Resultado físico observado

| Señal | Resultado |
| --- | --- |
| Identidad declarada | `GDBH-A681` + `FFC0` |
| Sesión ASK | `Activated` |
| Picker | `Skipped: existing authorization` |
| Autorización | `Authorized` |
| Resolución CoreBluetooth | Exactamente una vez; sin conexión |
| UUID local redactado | `CB-REDACTED-3364`, igual al observado por la sonda en esta instalación |
| GATT, reads, writes o destellos | Ninguno |

[Captura sanitizada — autorización persistente y resolución](screenshots/ios/physical-2026-08-29-x3pros-ask-persisted-resolution-01.png)

### Resultado físico tras revocación

| Señal | Resultado |
| --- | --- |
| Autorización | `Not authorized` |
| Revocación en sesión nueva | `Verified removed` |
| Picker fresco | Un candidato visible |
| Candidato visible | `Godox X3ProS diagnostic` / `GDBH-A681` |
| Selección nueva | Ejecutada con `Set Up` después de capturar el picker |
| CoreBluetooth, GATT, writes o destellos | No ejecutados |

[Captura sanitizada — revocación verificada y picker fresco exclusivo](screenshots/ios/physical-2026-08-29-x3pros-ask-fresh-picker-exclusive-01.png)

Esta captura prueba exclusividad visual en la corrida controlada: el picker
fresco mostró un solo candidato después de verificar que no quedaba una
autorización.

### Resultado físico después de `Set Up`

| Señal | Resultado |
| --- | --- |
| Sesión ASK | `Activated` |
| Picker en activación posterior | `Skipped: existing authorization` |
| Autorización nueva | `Authorized` |
| Resolución CoreBluetooth | Exactamente una vez; sin conexión |
| UUID local redactado | `CB-REDACTED-3364`, igual a la evidencia anterior de esta instalación |
| GATT, reads, writes o destellos | Ninguno |

[Captura sanitizada — autorización fresca persistida y resolución](screenshots/ios/physical-2026-08-29-x3pros-ask-fresh-authorization-resolution-01.png)

La secuencia completa prueba picker fresco con un candidato, selección
deliberada, persistencia en una activación posterior y resolución local del
mismo identificador. No prueba conexión GATT ni autenticación del radio.

### Resultado tras relaunch del proceso

Codex terminó y relanzó únicamente `EstroboAccessorySetupSpike`; después, el
usuario activó una sesión ASK nueva.

| Señal | Resultado |
| --- | --- |
| Proceso terminado y relanzado | PASS |
| Autorización tras relaunch | `Authorized` |
| Picker | `Skipped: existing authorization` |
| Resolución CoreBluetooth | Exactamente una vez; sin conexión |
| UUID local redactado | `CB-REDACTED-3364` |
| GATT, reads, writes o destellos | Ninguno |

[Captura sanitizada — persistencia tras relaunch del proceso](screenshots/ios/physical-2026-08-29-x3pros-ask-process-relaunch-persistence-01.png)

### Resultado background/foreground

El usuario cambió a otra app durante al menos 5 segundos y volvió al
diagnóstico sin pulsar controles. Confirmó el resultado esperado:

- sesión detenida en background;
- ninguna reactivación automática;
- ninguna resolución CoreBluetooth automática;
- ningún GATT, read, write o destello.

**Resultado:** PASS por atestación del operador; no se solicitó captura porque
el usuario confirmó explícitamente que no era necesaria.

### Resultado tras reboot del iPhone

El usuario reinició y desbloqueó el iPhone, abrió el diagnóstico y confirmó el
resultado esperado tras activar una sesión nueva:

- autorización existente disponible;
- mismo identificador local redactado;
- resolución exactamente una vez, sin conexión;
- ningún GATT, read, write o destello.

**Resultado:** PASS por atestación del operador; no se recibió captura.

### Resultado tras update in-place

Codex compiló, firmó e instaló sobre la app existente un build diagnóstico con
`CFBundleVersion` incrementado de 1 a 2 mediante override local de build, sin
cambiar el bundle ID ni borrar la app. Después del launch, el usuario activó la
sesión y confirmó:

- autorización existente disponible;
- mismo identificador local redactado;
- resolución exactamente una vez, sin conexión;
- ningún GATT, read, write o destello.

**Resultado:** PASS por atestación del operador; no se recibió captura. El
override de build 2 fue sólo para esta instalación física y no modifica la
versión declarada en el source tree.

### Resultado tras reinstall

Con autorización explícita del usuario, Codex verificó el bundle exacto,
desinstaló únicamente `ASK Diagnostic` build 2, comprobó su ausencia,
reinstaló el mismo build firmado y lo abrió. El sandbox diagnóstico anterior
fue eliminado.

Tras activar la sesión, el usuario confirmó que la autorización ASK ya no
existía.

**Resultado:** PASS por atestación del operador. La autorización persiste tras
relaunch, reboot y update in-place, pero se elimina al borrar la app. No se
recibió captura y no hubo GATT, read, write o destello.

### Resultado de cancelación del picker

Después de la reinstalación sin autorización, el usuario presentó el picker y
pulsó `Cancel` en lugar de `Set Up`. Confirmó el estado esperado:

- picker descartado;
- ninguna autorización creada;
- CoreBluetooth no intentado;
- identificador ausente;
- ningún GATT, read, write o destello.

**Resultado:** PASS por atestación del operador; no se recibió captura.

Una auditoría local posterior encontró dos carreras de presentación que no se
manifestaron físicamente: un completion tardío de `updatePicker` podía
sobrescribir `Dismissed`, y una revocación pendiente podía conservar textos
anteriores `Authorized`/`Resolved`. El diff local ahora invalida la generación
del picker y limpia el descubrimiento al descartarlo; la verificación de
revocación publica un estado desconocido coherente y conserva sólo el target
redactado. Los checks/builds locales posteriores pasaron. Este hardening no fue
reinstalado ni repetido físicamente y se registra separado del PASS observado.

## Decisión ASK de la corrida

**GO limitado:** la identidad `FFC0` + `GDBH-A681` soportó un picker exclusivo,
autorización, resolución local, revocación, cancelación, relaunch,
background/foreground, reboot, update in-place y reinstall caracterizado.

**NO-GO para integración en `EstroboIOS`:** el experimento permanece aislado;
esta corrida no autoriza background BLE, conexión GATT ni adopción de ASK en la
app principal.
