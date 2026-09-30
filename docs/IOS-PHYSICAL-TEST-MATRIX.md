# Estrobo iOS — matriz de pruebas físicas

Esta matriz prepara la validación en iPhone y iPad. Un build o una prueba en Simulator no valida CoreBluetooth, AccessorySetupKit, el enlace de radio ni el resultado óptico.

## Identificación de la corrida

| Campo | Valor |
| --- | --- |
| Fecha y responsable | 2026-08-30; instalación física del diff vigente asistida por Codex |
| Última build física instalada | `0bbc4a485f92ed066f61a7717a71c33348752202` + el diff vigente, incluidos tiles claros para Beep/Modelado/Standby/Multi, master global de modelado A0-only, feedback visual/háptico de pulsación larga y overlays de Standby. **Instalada sin que este flujo invocara launch y no validada funcionalmente; una consulta posterior encontró el proceso activo** |
| Diff de app posterior a esa instalación | Ninguno dentro del alcance de esta corrida; la instalación se hizo después de la validación local y de la recaptura visual final |
| Modelo de iPhone/iPad | iPhone 13 Pro (`iPhone14,2`); UDID `0000…801E` |
| iOS/iPadOS y build | iOS 26.6.1 (`23G83`) |
| Developer Mode / trust | Habilitado / emparejamiento operativo por cable |
| Xcode y SDK | Xcode 27.0 beta (`27A5228h`); iPhoneOS 27.0 (`24A5390e`) |
| Modelo de transmisor | Godox X3ProS |
| Firmware del transmisor | V1.03 |
| Flashes y firmware | Godox AD400 PRO II, firmware V1.21 |
| Grupos previstos | B y C |
| Bundle ID de desarrollo | Probe: `mx.loo.estrobo.advertisement-probe`; ASK: `mx.loo.estrobo.accessory-setup-spike`; app principal: `mx.loo.estrobo.dev` 0.1.0 (1), build vigente instalada in-place. Se cerró la instancia anterior y se confirmaron 0 procesos Estrobo inmediatamente después de instalar; este flujo no invocó launch. Una consulta posterior encontró la app activa, por lo que no se infiere ausencia de conexión o GATT durante ese intervalo |
| Tipo de firma | Apple Development local; perfil existente; sin upload ni registro externo |

## Gate de seguridad para Test y Multi

No ejecutar un destello físico hasta que la persona responsable confirme por escrito en la corrida:

- X3Pro y flashes preparados;
- ninguna otra app conectada;
- entorno ópticamente seguro;
- potencia común mínima seleccionada;
- Multi comienza con 2 destellos y 2 Hz.

| Confirmación | Responsable | Hora |
| --- | --- | --- |
| Equipo preparado | Confirmado por el usuario | Antes de la corrida publicitaria |
| Radio exclusivo | Confirmado: sin otras conexiones | Antes de la corrida publicitaria |
| Entorno seguro | Confirmado por el usuario | Antes de la corrida publicitaria |
| Potencia mínima | Corregida y confirmada por el usuario: 1/512 | Antes del smoke de la app principal |
| Multi 2 × 2 Hz | No autorizado todavía | Pendiente |

## Gates locales y de instalación

| Gate | Estado | Evidencia |
| --- | --- | --- |
| Git, rama y divergencia | PASS | `codex/ios-app`, HEAD esperado, 0 detrás/5 delante de `origin/main`, sin upstream |
| Generación del proyecto | PASS | XcodeGen 2.46.0 |
| Pruebas Swift de la cuarta remediación | PASS histórico | 34 Core + 3 Bluetooth + 6 persistence = 43/43; 0 fallos. Este conteo precede al diff posterior y no lo valida |
| Check y build iOS de la cuarta remediación | PASS histórico | Generic iOS + iPhone/iPad Simulator, sin firma; no se reutiliza como gate del diff posterior |
| Build de AdvertisementProbe | PASS | Generic iOS sin firma y build físico firmado |
| Build del spike AccessorySetupKit | PASS | App diagnóstica iOS 26.1 separada; Swift 6 strict concurrency; unsigned + Apple Development local |
| Configuración ASK | PASS | Allowlist exacta Bluetooth + `FFC0` + `GDBH-A681`; sin Company ID/background/restoration |
| Seguridad binaria ASK | PASS | Sólo `retrievePeripheralsWithIdentifiers:` y un `removeAccessory` explícito; sin scan directo, connect, GATT, read/write/notify, pairing, rename ni actualización de autorización |
| Instalación y launch ASK | PASS | Bundle diagnóstico verificado y proceso vivo en iPhone físico |
| Activación y resolución ASK | PASS | Sesión activada; autorización persistente detectada; mismo UUID redactado resuelto exactamente una vez, sin conexión |
| Revocación, reinstall y cancelación ASK | PASS | Revocación verificada en sesión nueva; borrar la app eliminó la autorización; `Cancel` no creó autorización ni intentó CoreBluetooth |
| Hardening ASK posterior | PASS local | Cancel invalida callbacks tardíos; verificación de revocación limpia estados obsoletos; build/check pasaron, sin reinstalación física posterior |
| Firma de la sonda | PASS | Apple Development, entitlements y perfil embebido verificados |
| Instalación y launch de la sonda | PASS | iPhone físico; sonda ejecutada sin conexión GATT ni writes |
| Privacidad de la sonda | PASS | UUID redactado en UI/OSLog; sin payloads, GATT ni writes |
| Privacidad de la app principal | PASS local | Identificador CoreBluetooth completo eliminado de avisos y accessibility IDs; 28/28 pruebas unitarias iOS pasaron en iPhone Simulator y 28/28 en iPad Simulator |
| Sincronización inicial directa | PASS local | El runtime live espera el settle técnico después de PWOK + Sync y programa A0 → A1 sin un segundo botón. El heartbeat queda diferido por fase hasta Ready; Cancel, background y desconexión eliminan tareas/colas. Pruebas focales PASS; físico pendiente |
| Staging de B → C | PASS local | Onboarding inicial sólo con B conserva 1/512; al incorporar C después queda OFF, modelado apagado y 1/512 antes de reconectar |
| Build, instalación y launch de la app principal | PASS | El build remediado `mx.loo.estrobo.dev` 0.1.0 (1), con potencia inline y Test directo, quedó firmado, verificado, instalado sobre la app existente y abierto en el iPhone físico. Esto no constituye todavía validación funcional ni óptica |
| Smoke de la app principal | STOPPED | Conexión física con el X3ProS reportada como operativa; corrida detenida porque los botones `+` y `−` de potencia parecían no responder correctamente. Control de potencia no confiable. Sin validar preview, orden de writes, Ready ni resultado óptico; Test y Multi no ejecutados |
| Retest del build remediado | STOPPED | Los botones `+` y `−` sí actualizan el valor visible. Durante el drag, el slider no actualiza el valor visible; la corrida se detuvo sin atribuir entrega GATT ni resultado físico. Test y Multi no ejecutados |
| Segunda remediación local | PASS local | El slider conserva un valor transitorio visible por paso y difiere la persistencia hasta terminar/cancelar el gesto; Control global vive dentro de Grupos; iPhone queda con Grupos/Presets/Ajustes y el feedback automático es compacto. Build Generic Simulator PASS; unitarias 18/18 por idiom; UI 16/16 iPhone y 8 PASS + 8 skips intencionales iPad |
| Build físico de la segunda remediación | PASS de instalación | `mx.loo.estrobo.dev` 0.1.0 (1) quedó firmado, verificado, instalado sobre la app existente y abierto en `0000…801E`. La interacción todavía no se ha repetido; el último resultado funcional continúa `STOPPED` |
| Última validación local anterior al diff posterior | PASS local histórico | 43/43 Swift; 28/28 unitarias iOS en cada idiom; UI 20/20 en iPhone y 8 PASS + 12 skips intencionales en iPad, sin fallos; build con warnings Swift como errores PASS. No se reutiliza como validación del diff posterior |
| Última build física | PASS de instalación; VIGENTE | Arm64, firma Apple Development, entitlements y bundle verificados; perfil local existente incluye `0000…801E`; instalación in-place de `mx.loo.estrobo.dev` 0.1.0 (1) completada sin provisioning remoto. Se cerró el proceso anterior y la comprobación inmediata mostró 0 procesos Estrobo; este flujo no invocó launch. Una consulta posterior encontró la app activa; el origen y cualquier actividad física durante ese intervalo no se atribuyen |
| Retención y conexión recordada actuales | PASS local | Al abrir, el último radio guardado genera una oferta; la opción por radio inicia búsqueda automática por UUID exacto. Una sesión Ready sin operación en vuelo conserva el enlace al cambiar de app y vuelve sin PWOK, Sync, A0 o A1; una pérdida física activa una búsqueda foreground única por el identificador exacto y conserva el objetivo incluso tras un segundo background. Pruebas focales PASS; físico pendiente |
| Tercera remediación del slider | SUPERSEDED tras STOPPED físico | `UISlider` modeló `touchDown`, cambio, fin y cancelación, pero un `touchCancel` después de cambiar valor conservó el borrador sin programar entrega. El retest físico mostró `Sincronizando…` indefinido. Test y Multi no ejecutados |
| Cuarta remediación del slider | PASS local + instalación; SUPERSEDED | Un `touchCancel` que ya produjo un valor cierra el gesto y arma sólo el valor final; teardown, background, deshabilitado y pérdida de sesión siguen cancelando sin envío tardío. La UI muestra `Cambio pendiente` si no hay debounce ni I/O, reservando `Sincronizando…` para trabajo real. Fue la última build instalada; el retest físico quedó pendiente y los cambios posteriores no están instalados |
| Slider global relativo y reglas | INSTALADO; PENDING físico | Delta visual `−3…+3 EV` en pasos de 1/3 EV; sliders con regla; commit atómico final-only; clamp común; grupos deshabilitados intactos; retorno visual a 0. Sin validación funcional física |
| Composición Multi y acceso a detalle | INSTALADO; PENDING físico | `Grupos de trabajo` se oculta durante Multi y la identidad de cada participante conserva la misma pulsación larga para abrir el detalle. No existe un botón `Detalles` visible. Multi físico no autorizado ni ejecutado |
| Beep, Standby y Multi directos | INSTALADO; PENDING físico | Actúan sin sheet ni estado de completado fugaz. Beep/Standby no muestran barra transitoria en Automática ni en Con botón; Multi conserva Apply únicamente cuando Con botón exige una entrega manual. Test y Multi físicos no ejecutados |
| Endurecimiento del diff posterior | INSTALADO; PENDING físico | `touchCancel` cancela sin commit ni entrega automática; los sliders sólo mutan presentación durante el drag y entregan el valor final al soltar; el slider global usa token y ancla estable; Test publica resultado correlacionado propio; las acciones globales directas tienen procedencia explícita. Sin validación funcional física |
| Validación local de la última build instalada | PASS local; INSTALADO | 51 Core + 6 persistence + 3 Bluetooth = 60/60; `ios-check` PASS; unitarias iOS 30/30 en iPhone y 30/30 en iPad; screenshot UI 1/1 por idiom y 14 referencias exportadas; suite UI iPad 8 PASS + 16 omisiones intencionales. La corrida completa de UI en iPhone obtuvo 23/24: el único fallo fue un arrastre sintético interceptado por la barra fija. Tras sustituir exclusivamente ese gesto del arnés por el ajuste semántico nativo, la repetición focal pasó 1/1 y confirmó el mínimo manual exacto de 10%. Estos resultados no constituyen evidencia física |
| Instalación física de la última build | PASS de instalación; VIGENTE | Build arm64 con warnings Swift como errores; firma Apple Development, entitlements, bundle y perfil para `0000…801E` verificados. Instalación in-place confirmada como 0.1.0 (1). Se terminó únicamente el proceso Estrobo previo; este flujo no invocó launch y la comprobación inmediata mostró 0 procesos. Una consulta posterior encontró la app activa; este flujo no ejecutó Test ni Multi y no se atribuye evidencia de conexión, GATT, óptica ni háptica |
| Tiles globales Beep/Modelado/Standby/Multi | INSTALADO; PENDING físico | El build instalado hace evidente el estado estable de cada acción mediante texto, símbolo, check, borde y relleno, sin depender sólo del color. El indicador transitorio se reserva para trabajo pendiente real; screenshots iPhone/iPad y UI automatizada PASS, pero no se ha evaluado percepción en hardware |
| Master global de modelado | INSTALADO; PENDING físico | El control instalado cambia el master de modelado mediante una operación A0-only y conserva los modos e intensidades A1 configurados por grupo. No se ha comprobado entrega GATT ni efecto físico de las luces de modelado |
| Feedback de pulsación larga | INSTALADO; PENDING físico | La cabecera muestra feedback visual durante el gesto y prepara feedback háptico al reconocer la pulsación antes de abrir el detalle. El gesto sigue separado del slider y de `−`/`+`; el feedback háptico no ha sido percibido ni validado en iPhone físico |
| Overlays de Standby en grupos | INSTALADO; PENDING físico | Al activar Standby, el build instalado cubre las tarjetas con un estado textual explícito de apagado y bloquea sus controles; al reanudar, los overlays desaparecen. Existe evidencia UI automatizada y visual local, pero no prueba entrega GATT ni que las lámparas se hayan apagado físicamente |

## Evidencia de publicidad Bluetooth

Capturar varias muestras después de apagar y encender el X3Pro. No registrar Código del radio ni payloads de autenticación.

| Dato | Muestra 1 | Muestra 2 | Muestra 3 | Estable |
| --- | --- | --- | --- | --- |
| Nombre local OTA | `GDBH-A681` | `GDBH-A681` | `GDBH-A681` | Sí, 3/3 |
| Service UUIDs anunciados | `FFC0` | `FFC0` | `FFC0` | Sí, 3/3; ancla válida |
| Overflow/Solicited UUIDs | Ninguno / ninguno | Ninguno / ninguno | Ninguno / ninguno | Ausencia estable 3/3 |
| Company ID | Ninguno | Ninguno | Ninguno | No disponible como ancla |
| Company ID + longitud de Manufacturer Data | Ninguno / ninguna | Ninguno / ninguna | Ninguno / ninguna | Manufacturer Data ausente 3/3 |
| Claves + longitudes de Service Data | Ninguno | Ninguno | Ninguno | Service Data ausente 3/3 |
| Connectable | `true` | `true` | `true` | Sí, 3/3 |
| RSSI, sólo contexto | -38 dBm | -40 dBm | -49 dBm | No usar como identidad |
| UUID local de CoreBluetooth redactado | `CB-REDACTED-3364` | `CB-REDACTED-3364` | `CB-REDACTED-3364` | Igual en esta instalación; no extrapolar |
| Advertisements duplicados | 473 | 1447 | 2534 | Sólo contexto; no son corridas independientes |

Las tres corridas incluyeron relaunch de la sonda y power-cycle del X3ProS.
La bitácora y capturas sanitizadas están en
[`IOS-BLUETOOTH-EVIDENCE.md`](IOS-BLUETOOTH-EVIDENCE.md).

No crear un descriptor AccessorySetupKit hasta confirmar al menos un Service UUID anunciado o Company ID estable. FFF0 y FEC0 descubiertos después de conectar no cuentan como evidencia de advertisement. En esta corrida `FFC0` sí fue anunciado directamente y resultó estable 3/3.

## Matriz de comportamiento

Para cada fila registrar por separado:

1. entrega GATT;
2. confirmación FEC8 cuando corresponde;
3. observación física/óptica.

| Escenario | Estado | Pasos | Resultado esperado | GATT | FEC8 | Físico | Evidencia |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Permiso concedido | PENDING | Explicar permiso, conceder, buscar | Scan y conexión disponibles | N/A | N/A | N/A | Probe concedido; app principal pendiente |
| Permiso denegado | PENDING | Denegar desde prompt/Ajustes | Explicación y recuperación; sin scan | N/A | N/A | N/A | Clasificación local `unauthorized`/`unsupported` y escenario UI PASS; prompt/Ajustes real pendiente |
| Bluetooth apagado/encendido | PENDING | Apagar y reactivar Bluetooth | Estado explícito, sin write diferido | N/A | N/A | Ningún destello | Pausa/rearme del timeout y estados temporales PASS local; toggle físico pendiente |
| Conexión, PWOK y Sync inicial | PENDING | Configurar sólo B, buscar, elegir identificador y autenticar | Después de PWOK + Sync y el settle técnico, A0 y sólo un A1 de B se programan directamente; Ready llega tras los acuses | Pendiente | Pendiente | B permanece a potencia mínima | Conexión física reportada como operativa; el flujo directo actual sólo tiene evidencia local |
| Cancelación durante conexión/Sync | PENDING | Pulsar Cancelar antes de que comience la secuencia de control | Cero control writes y ningún comando diferido | Ausente | N/A | Ausente | Prueba core PASS; físico pendiente |
| Potencia inline `−`/slider/`+` | INSTALADO / PENDING físico | Ajustar desde la fila de B, incluida cada frontera | La regla y el valor muestran cada paso; al soltar se programa sólo el valor final; `−` y `+` reflejan sus límites | Pendiente | Pendiente | Pendiente | El tercer retest quedó `STOPPED` por `Sincronizando…` indefinido; el candidato corregido ya está instalado pero permanece sin retest |
| Potencia global relativa | INSTALADO / PENDING físico | Arrastrar desde 0 hacia ambos extremos y soltar una vez | Delta `−3…+3 EV` en tercios; cero writes intermedios; un commit común con clamp; grupos OFF intactos; el control vuelve visualmente a 0 | Pendiente | Pendiente | Pendiente | Regresión de dominio y presentación local; candidato instalado sin evidencia funcional física |
| Acceso al detalle por pulsación larga | INSTALADO / PENDING | Mantener presionada la cabecera de una tarjeta normal y la identidad de un participante Multi; comprobar también que un toque breve no navega | Mismo detalle en push/inspector; no existe botón `Detalles` visible y el gesto no compite con slider, `−`/`+` ni toggle | N/A | N/A | Sin cambio | Candidato instalado; recorrido físico pendiente |
| A0 antes de A1 | PENDING | Cambiar control global dependiente | Orden A0 → A1 serial | Pendiente | Pendiente | Confirmar | Pendiente |
| Gesto continuo | PENDING físico | Arrastrar potencia y soltar | Cero writes intermedios y uno final con el valor visible al soltar | PASS simulado | PASS simulado | Un cambio final | Core, ciclo `UISlider` y UI manual/automática PASS local; GATT/FEC8 físicos pendientes |
| Test bloqueado por gates | BLOCKED | Observar el botón sin pulsarlo cuando exista un bloqueo | Test deshabilitado; cero writes y cero destellos | Ausente | N/A | Ausente | Requiere una corrida nueva; no autoriza ejecutar Test |
| Test directo | BLOCKED | Pulsar una vez, sin confirmación intermedia | Un Test single-flight; sin cola ni retry automático | Pendiente | N/A | Un destello | No autorizado ópticamente; no ejecutar |
| Multi mínimo | BLOCKED | No ejecutar sin nueva autorización óptica escrita | Entrada/salida directa; `Grupos de trabajo` oculto; la identidad de cada participante conserva la pulsación larga para abrir el detalle; scrubbers con regla; sin estado de completado fugaz | Pendiente | Pendiente | No observado | Candidato instalado; Multi físico no autorizado ni ejecutado |
| Acciones directas Beep/Standby/Multi | INSTALADO / PENDING | Repetir primero sin destello; no ejecutar Multi físico sin autorización nueva | Acción directa; indicador sólo durante debounce o I/O real y desaparición inmediata al reposo, sin `Actualizado` | N/A local | N/A local | No observado | Evidencia local y PASS de instalación; no afirma ejecución física de Test ni Multi |
| Tiles claros Beep/Modelado/Standby/Multi | INSTALADO; PENDING físico | Cambiar cada estado permitido y observar reposo, transición y deshabilitado | Cada tile distingue de forma redundante activo/inactivo mediante texto, símbolo, check y tratamiento visual; sólo una operación pendiente real muestra feedback transitorio | Pendiente | Pendiente cuando corresponda | No observado | Build instalado; screenshots y UI automatizada PASS, sin validación física |
| Master global de luces de modelado | INSTALADO; PENDING físico | Configurar modelado por grupo, apagar y encender el master global, y comprobar que los ajustes por grupo permanecen intactos | Sólo cambia el campo global A0 de modelado; no sobrescribe modo ni intensidad A1 por grupo | Pendiente | Pendiente cuando corresponda | No observado | Build instalado; no se atribuye entrega GATT ni efecto óptico |
| Feedback de acceso por pulsación larga | INSTALADO; PENDING físico | Mantener la cabecera hasta abrir el detalle y cancelar otro intento antes del umbral | Feedback visual durante el gesto; feedback háptico únicamente al reconocerlo; cancelar no navega ni confirma | N/A | N/A | Háptico no observado | Build instalado; la respuesta háptica requiere interacción física y no está validada |
| Overlay global de Standby | INSTALADO; PENDING físico | Activar Standby sin disparar, revisar todas las tarjetas y después reanudar | Cada tarjeta queda cubierta por un mensaje explícito de apagado y sus controles no son interactivos; al reanudar recupera la presentación normal sin perder ajustes | Pendiente | N/A esperado | No observado | Build instalado; evidencia UI automatizada local, pero el overlay no demuestra que el transmisor o las lámparas hayan obedecido Standby |
| Pérdida de alcance | PENDING | Alejar durante idle y durante write | Desconexión; journal si write incierto | Pendiente | Pendiente | Registrar | Pendiente |
| Radio ocupado | PENDING | Conectar Estrobo Mac/u otra app primero | Error accionable; no interferencia | N/A | N/A | Ausente | Pendiente |
| Pantalla bloqueada | PENDING | Bloquear con debounce/gesto pendiente | Sin Test, Multi ni write diferido | Ausente | Ausente | Ausente | Pendiente |
| Apertura con último radio | PENDING físico | Conectar y guardar un radio, cerrar el proceso y abrir de nuevo con conexión automática apagada | Ofrece buscar el radio por nombre; no escanea hasta aceptar | N/A | N/A | Sin cambio | 2 unitarias iOS + 1 UI focal PASS; Core registra el último UUID guardado; relaunch físico pendiente |
| Conexión automática | PENDING físico | Activarla en el radio guardado, cerrar el proceso, encender el radio y abrir Estrobo | Escanea por el identificador exacto y conecta una sola vez al encontrarlo; si no aparece, termina la búsqueda sin conectar otro radio del mismo nombre | Pendiente | N/A | Sin cambio antes de iniciar A0/A1 | Identificador exacto/una conexión, objetivo previo a discovery síncrono, preferencia exclusiva/persistente, Bluetooth no disponible y toggle UI PASS local. El vencimiento real cuando no aparece y Bluetooth físico siguen pendientes |
| Cambio de app con Ready estable | PENDING físico | Desde Ready ir a Home por 5, 30 y 120 s y regresar | Conserva la sesión si proceso y enlace sobreviven; vuelve Ready sin otro PWOK, Sync, A0 o A1 y sin write tardío | Ausente | Ausente | Sin cambio | Core 1/1 + ScenePhase unit 2/2 + UI Simulator Home → activate 1/1 PASS; duraciones y captura GATT físicas pendientes |
| Cambio de app durante conexión/write | PENDING | Ir a background durante Sync, antes de 700 ms y durante una entrega incierta | Cancela scan/debounce; falla cerrado, preserva journal cuando aplica y exige reconexión/recuperación | Ausente o registrar write ya iniciado | Ausente | Ausente | Pruebas Core de lifecycle y journal PASS; físico pendiente |
| Pérdida del enlace mientras está inactiva | PENDING físico | Desde Ready ir a Home, apagar el radio y volver | No presenta Ready falso; exige reconectar o recuperar según el journal | N/A | N/A | Sin cambio | Core 3/3 PASS: pérdida durante inactive, callback idle después del regreso y failure después del regreso; físico pendiente |
| Interrupción | PENDING | Recibir llamada/overlay del sistema | Igual que inactive; sin write silencioso | Ausente | Ausente | Ausente | Pendiente |
| Terminación por memoria | PENDING | Terminar proceso con journal preparado | Recuperación obligatoria al abrir | Pendiente | Pendiente | Registrar | Pendiente |
| Force quit | PENDING | Forzar cierre en distintos estados | No depende de callback de terminación | Pendiente | Pendiente | Registrar | Pendiente |
| UUID distinto | PENDING | Intentar recuperar con otro radio | Recuperación bloqueada | Ausente | Ausente | Ausente | Pendiente |
| Reconexión correcta | PENDING | Conectar UUID original | Permite preparar y recuperar | Pendiente | Pendiente | Confirmar | Pendiente |
| Actualización | PENDING | Instalar build nuevo encima | Preserva/migra catálogo, vault y journal | N/A | N/A | N/A | Pendiente |
| Reinstalación | PENDING | Borrar e instalar de nuevo | Documentar qué persiste en Keychain | N/A | N/A | N/A | Pendiente |

## AccessorySetupKit

| Comprobación | Resultado |
| --- | --- |
| Import y compilación de AccessorySetupKit en app iOS 26.1 | PASS; target diagnóstico separado, unsigned y firmado |
| Plist ASK según Xcode 27 beta local | PASS; `NSAccessorySetupKitSupports`, Bluetooth, `FFC0`, `GDBH-A681` |
| Descriptor basado sólo en datos observados | GO limitado: Service UUID `FFC0`; `GDBH-A681` sólo como refinamiento |
| Filtro exacto antes de mostrar candidato | PASS; igualdad de nombre + presencia de `FFC0`; picker físico mostró un único candidato |
| Instalación y launch del diagnóstico | PASS; iPhone físico |
| Sesión ASK activada | PASS; UI muestra `Activated` |
| Picker encuentra exclusivamente el X3Pro | PASS en esta corrida controlada; un candidato `GDBH-A681`, seleccionado deliberadamente |
| Selección/cancelación del picker | Selección nueva: PASS; cancelación: PASS por atestación, sin autorización ni resolución |
| `bluetoothIdentifier` resuelve con CoreBluetooth | PASS antes y después de la selección nueva; exactamente una vez, mismo `CB-REDACTED-3364`, sin conexión |
| Autorización persistente disponible al activar | PASS antes y después de la selección nueva; `session.accessories` devolvió una autorización exacta |
| Revocación explícita y verificación en sesión nueva | PASS; UI muestra `Verified removed` y habilitó el picker fresco |
| Persistencia tras terminar y relanzar el proceso | PASS; autorización exacta disponible y mismo identificador resuelto una vez sin conexión |
| Background/foreground del diagnóstico | PASS por atestación del usuario; sesión detenida, sin reactivación ni resolución automática; sin captura por decisión explícita |
| Persistencia tras reboot del iPhone | PASS por atestación del usuario; autorización, mismo UUID redactado y resolución única sin conexión |
| Persistencia tras update in-place | PASS por atestación del usuario; build 1 → 2, autorización y mismo UUID redactado disponibles, resolución única sin conexión |
| Reinstall de la app diagnóstica | PASS por atestación del usuario; desinstalar build 2 eliminó la autorización ASK; reinstalación limpia quedó sin autorización |
| Evidencia UI sanitizada | [Autorización inicial](screenshots/ios/physical-2026-08-29-x3pros-ask-persisted-resolution-01.png); [revocación + picker fresco](screenshots/ios/physical-2026-08-29-x3pros-ask-fresh-picker-exclusive-01.png); [autorización fresca + resolución](screenshots/ios/physical-2026-08-29-x3pros-ask-fresh-authorization-resolution-01.png); [persistencia tras relaunch](screenshots/ios/physical-2026-08-29-x3pros-ask-process-relaunch-persistence-01.png) |
| Decisión actual | GO limitado de viabilidad ASK; matriz diagnóstica completada; NO-GO para integración en `EstroboIOS`, background o GATT dentro de esta corrida |

Si el descriptor no identifica al X3Pro de forma estable, conservar CoreBluetooth foreground-only y documentar AccessorySetupKit como no adoptado.

## Cierre de una corrida

- Adjuntar logs redactados y capturas.
- Confirmar que ningún log contiene Código del radio ni payload de autenticación.
- Registrar versiones exactas y sólo el UUID local redactado, sin afirmar equivalencia Mac/iOS.
- Marcar por separado los escenarios no ejecutados y su razón.
- No concluir “Bluetooth validado” sin hardware ni “listo para TestFlight” sin repetir gates con Xcode estable.
