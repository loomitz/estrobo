# Product

<!-- impeccable:product-schema 1 -->

## Platform

ios

## Users

La persona principal opera un transmisor de flash Godox compatible desde un iPhone o iPad. Su trabajo es configurar los grupos y modelos de flash, seleccionar el radio correcto, completar autenticación y Sync, ajustar una escena, ejecutar Test o Multi deliberadamente y recuperar una transmisión cuyo resultado quedó incierto.

**Decisión abierta:** el brief no delimita un segmento profesional más específico —por ejemplo, fotógrafo, asistente o técnico de iluminación—, por lo que futuras superficies no deben inventarlo.

## Product Purpose

Estrobo lleva a iPhone y iPad el control local de transmisores Godox compatibles, reutilizando el motor de protocolo, sesión y seguridad de la app macOS dentro de una interfaz SwiftUI móvil propia.

El producto debe permitir completar de forma segura el flujo de configuración, conexión, autenticación, sobrescritura Sync, ajuste, entrega y recuperación. La app macOS y sus contratos existentes deben seguir funcionando sobre el mismo núcleo compartido.

## Positioning

**Inferencia de posicionamiento:** la diferencia defendible de Estrobo es arquitectónica, no una afirmación de mercado: control nativo y local, sin cuenta ni backend, donde la app conserva el estado deseado, aplica A0 antes de los A1 serializados y bloquea nuevas operaciones cuando no puede confirmar el resultado. iOS y macOS comparten ese comportamiento, pero cada plataforma conserva una interfaz apropiada.

Estrobo no es un lector del estado completo del transmisor, una conexión directa a los flashes ni un servicio remoto.

## Operating Context

- App universal para iPhone y iPad, con deployment target inicial iOS/iPadOS 18 o posterior y sin Mac Catalyst.
- Uso operativo foreground-only: al quedar inactiva o en background detiene el scan, cancela gestos y debounces y no arma writes nuevos. Si ya existe una sesión Ready estable y sin operación en vuelo, conserva el enlace BLE durante un cambio de app y vuelve a Ready sin repetir PWOK, Sync, A0 o A1; durante conexión, sincronización, entrega incierta o pérdida física sigue fallando cerrado y exige reconexión o recuperación.
- El enlace Bluetooth con el transmisor es exclusivo; otra app conectada debe cerrarse antes.
- Antes de conectar, la persona configura compatibilidad de grupos, grupos de trabajo y modelos de flash.
- Sync aplica deliberadamente el estado local al transmisor; no importa su configuración previa.
- Test y Multi operan equipo físico y requieren una acción táctil intencional, estado pendiente visible y un entorno ópticamente seguro. Test se ejecuta directamente con un toque cuando todas sus compuertas están abiertas; Multi entra y sale directamente desde su control global, con el efecto sobre los grupos explicado de forma persistente y no modal. Beep, Modelado y Standby también cambian directamente desde sus controles protegidos. Sus tiles mantienen selección, símbolo y texto de estado evidentes; no presentan un estado de completado fugaz y el feedback automático transitorio sólo permanece mientras existe debounce o I/O real.
- Grupos es la superficie operativa principal: cada grupo permite ajustar potencia inline en pasos discretos de 1/3 EV sin abrir el detalle. Los sliders muestran marcas de regla y una pulsación larga sobre la cabecera de la tarjeta abre los controles avanzados; no existe un botón `Detalles` visible. Mientras se sostiene, la cabecera responde visualmente y, al reconocer el gesto, emite feedback háptico antes de navegar. VoiceOver ofrece la misma entrada como acción accesible nombrada.
- iPhone tiene exactamente tres destinos superiores: Grupos, Presets y Ajustes. Conexión y los detalles se presentan de forma contextual; no existe una pestaña Global separada.
- iPad usa una estructura adaptable con sidebar, workspace e inspector, pero tampoco ofrece un destino Global separado. Potencia relativa, Beep, Modelado, Standby y Multi viven en una sección compacta Control global dentro de Grupos.
- Demo debe poder iniciarse desde el onboarding, permanecer identificado como simulado y usar transporte y stores aislados de los datos reales.

## Capabilities and Constraints

- Conserva las capacidades de Beta 4: perfiles de compatibilidad, grupos y modelos; búsqueda, selección, Código del radio, PWOK y Sync; M, TTL/Auto y Off; potencia Manual; modelado; Beep; Standby; Test; Multi global con participantes, potencia, conteo, Hz y límites por modelo; entrega Automática o Con botón; presets; transmisores guardados; recuperación; español/inglés y claro/oscuro.
- `EstroboCore` contiene dominio, codecs A0/A1, capacidades, Multi, sesión, entrega, seguridad y recuperación, sin AppKit, UIKit ni SwiftUI.
- `EstroboBluetooth` expone un `RadioTransport` pequeño con adaptadores CoreBluetooth y simulado, sin duplicar reglas o payloads.
- `EstroboPersistence` conserva workspace, presets, preferencias, transmisores guardados, un `RadioCodeVault` basado en Keychain y un `RestorationJournal` durable y atómico; los tests usan adaptadores en memoria.
- Hay un solo coordinador de sesión/Bluetooth a nivel de aplicación, gobernado por `scenePhase`.
- Después de PWOK + Sync exitosos contra un transmisor guardado, la app registra ese UUID local como el último conectado. Al abrir ofrece buscarlo y conectarlo; si ese transmisor tiene activada Conexión automática en Ajustes, prepara directamente una búsqueda por el UUID exacto y conecta sólo al encontrarlo. Si Bluetooth todavía no está disponible, conserva ese objetivo y empieza a contar el timeout cuando el scan realmente inicia. Sólo un transmisor guardado puede tener esa preferencia activa a la vez.
- A0 precede a cualquier A1 dependiente; los writes son seriales y se confirman mediante GATT y FEC8 según corresponda.
- El journal se escribe antes de transmitir y la recuperación sólo puede continuar contra el mismo UUID local observado por ese dispositivo iOS.
- Un UUID CoreBluetooth de macOS no se sincroniza ni se considera igual al observado por iPhone.
- Cada fila de Grupos presenta el valor de potencia, botones `−` y `+` con límites direccionales independientes y un slider discreto de 1/3 EV con marcas de regla. El control completo sólo está disponible cuando el grupo y la sesión permiten editar potencia Manual. La pulsación larga pertenece sólo a la cabecera de la tarjeta para no competir con el slider ni con `−`/`+`.
- El detalle de grupo no es un paso requerido para ajustar potencia. Se abre por pulsación larga y reúne Modo, un slider independiente de potencia de flash y Modelado. Modelado muestra exactamente Apagado, Proporcional y Manual; al elegir Manual aparece un slider de intensidad que respeta las capacidades del flash y nunca baja de 10%.
- Control Global es el único título visible del bloque compacto que reúne potencia relativa y una rejilla 2×2 para Beep, Modelado, Standby y Multi dentro de Grupos; no existe un título de pantalla, header de sección ni explicación redundante alrededor del bloque. Modelado es un maestro A0 independiente: apagarlo conserva los modos e intensidades A1 de cada grupo, encenderlo los recupera y un Apply no relacionado no debe reactivarlo. Una edición local deliberada de Modelado vuelve a encender el maestro. El slider de potencia representa un delta `−3…+3 EV` en pasos de 1/3 EV: durante el drag sólo actualiza la presentación, al soltar aplica una única operación relativa a todos los grupos Manual elegibles, respeta el clamp físico común y no modifica grupos deshabilitados. Después del commit vuelve visualmente a 0 sin revertir las potencias resultantes.
- Automática o Con botón se elige y explica únicamente en Ajustes. Grupos refleja la preferencia vigente mediante una barra inferior contextual, pero nunca duplica allí el selector.
- En Automática, la barra contextual ofrece feedback sutil únicamente mientras existe un debounce armado o I/O en curso, sin un botón Aplicar redundante y sin `Actualizado`, checkmark ni otro estado de completado fugaz al terminar. En Con botón, muestra los cambios pendientes y presenta Descartar/Aplicar cuando corresponde; las operaciones directas Beep/Modelado/Standby nunca hacen parpadear esa barra, mientras Multi sí conserva Apply si la entrega manual fue elegida deliberadamente.
- Test se envía directamente con un solo toque desde Grupos, sin alerta ni sheet de confirmación. Sus gates exigen foreground y Ready, además de ausencia de edición interactiva, cambios pendientes, recuperación, Standby u otra operación incompatible.
- Test es single-flight: mientras está pendiente se deshabilita, nunca queda en cola y nunca se reintenta automáticamente. Su resultado distingue envío simulado, entregado o fallido sin afirmar que Bluetooth confirmó el destello.
- Multi continúa como decisión global dentro de Control Global. Activarlo o desactivarlo es una acción directa, sin alerta ni sheet; los gates del controller siguen decidiendo si el toque está disponible y la interfaz anticipa por accesibilidad qué grupos entran a Multi, pasan a Off o vuelven a Manual. Mientras está activo, las tarjetas normales se ocultan y la identidad de cada participante conserva la misma pulsación larga y acción accesible para abrir su detalle, independiente del toggle. Si Standby está activo, tanto las tarjetas normales como los participantes Multi muestran un overlay persistente `Apagado por Standby` sin borrar sus ajustes.
- Destellos y Hz de Multi usan scrubbers discretos tipo regla, sin botones `−`/`+`, con valor grande y límites visibles. Hz ofrece exactamente `1…20`, después `25, 30, 35, 40, 45, 50`, luego `60…190` de diez en diez y finalmente `199`; el slider recorre esas 41 posiciones, no todos los enteros intermedios. Durante cualquier drag continuo, el control muestra cada paso en vivo y no persiste ni transmite valores intermedios: al soltar, persiste una sola vez el borrador final y la entrega automática espera 700 ms antes de enviarlo. Si el gesto se cancela, la app pasa a background o pierde la sesión, no arma un envío tardío. Los valores superiores a la tabla publicada de un modelo se identifican como no verificados y siguen requiriendo prueba física/óptica.
- Recordar un transmisor es opt-in y sólo ocurre después de PWOK + Sync. Olvidar uno no elimina los demás y limpia sus preferencias de último radio y conexión automática.
- “Compatibilidad de grupos” nombra capacidades técnicas; “Transmisores guardados” nombra dispositivos físicos persistidos.
- Logs y diagnósticos nunca muestran el Código del radio ni payloads de autenticación.
- No hay backend, analítica, anuncios ni telemetría. No se solicitan permisos de cámara, ubicación o red local.
- El MVP no declara `UIBackgroundModes`: conservar una sesión Ready durante un cambio de app es best-effort mientras sobrevivan el proceso y el enlace. No promete ejecución BLE continua, reconexión automática ya suspendida ni restauración después de terminación del proceso.
- Simulator y Demo no validan Bluetooth físico. Demo nunca crea `CBCentralManager` ni toca radios o journals reales.
- AccessorySetupKit es un spike sujeto a evidencia física. No se fijan descriptores ni filtros de servicios hasta observar lo que anuncia realmente el X3Pro; CoreBluetooth permanece como transporte GATT.
- Bluetooth confirma entrega, no resultado óptico. GATT, FEC8 y observación física se registran por separado.
- No se publica ni sube a TestFlight/App Store sin autorización nueva y repetición de gates con Xcode estable.
- `mx.loo.estrobo` es sólo candidato de producción.

**Decisiones abiertas:**

- Confirmar si iOS y un eventual Mac App Store compartirán identidad y universal purchase antes de registrar el bundle de producción.
- Determinar con un iPhone físico si AccessorySetupKit identifica establemente al X3Pro y qué datos anuncia realmente.
- Definir la matriz soportada de iPhone/iPad, iOS/iPadOS, transmisor, firmware y flashes sólo después de pruebas físicas registradas.

## Brand Commitments

- El nombre del producto es **Estrobo**.
- Conserva el carácter local y nativo comunicado por el producto existente.
- Mantiene español e inglés como idiomas de primera clase.
- Es un proyecto independiente: no está afiliado, patrocinado, aprobado ni mantenido oficialmente por Godox.
- Los nombres Godox y de sus productos pertenecen a sus respectivos titulares.
- El mark existente vive en `prototype/EstroboMac/Resources/Brand/EstroboMark1024.png`.
- No deben añadirse afirmaciones de compatibilidad, seguridad o validación física que excedan la evidencia registrada.

## Evidence on Hand

- `README.es.md`: propósito local, flujo de uso, capacidades Beta 4, límites y terminología pública.
- `docs/HOW-IT-WORKS.md`: modelo de sesión, A0/A1, entrega, recuperación, persistencia y transporte simulado.
- `docs/BLUETOOTH-CONNECTION.md`: secuencia BLE/GATT, señales de confirmación, timeouts y límites de identidad.
- `docs/AUTOMATIC-SYNC.md`: sobrescritura Sync, debounce, gestos continuos, serialización y recuperación fail-closed.
- `docs/BETA.md`: alcance acotado de compatibilidad y separación entre entrega Bluetooth y resultado óptico.
- `PRIVACY.md` y `SECURITY.md`: flujo local, datos persistidos, redacción de secretos y riesgos aceptados del protocolo.
- `Sources/EstroboCore`, `Sources/EstroboBluetooth` y `Sources/EstroboPersistence`: núcleo, transporte y persistencia compartidos por las apps nativas.
- `prototype/EstroboMac/Sources/` y `prototype/EstroboMac/Tests/`: interfaz macOS y cobertura de protocolo, recuperación, persistencia, localización e interacción.
- Evidencia física documentada hasta ahora: Mac ↔ Godox X3Pro por Bluetooth y X3Pro ↔ Godox AD400Pro II por radio. No se registraron las revisiones exactas de firmware y no todas las funciones tienen validación óptica.
- La Beta 4 macOS publicada conserva el Código del radio sin cifrar por opt-in. El árbol de desarrollo compartido ya migró macOS e iOS a `RadioCodeVault` con Keychain `WhenUnlockedThisDeviceOnly`; esa migración aún no constituye una nueva release macOS.
- Ya existe evidencia física iOS acotada para publicidad Bluetooth, autorización/resolución de AccessorySetupKit y una conexión reportada con el X3ProS. El rediseño iOS de agosto se instaló el 2026-08-30, pero su validación funcional quedó pendiente. El candidato consolidado del 2026-09-29 añade cambios de integración y no hereda ese PASS de instalación; todavía requiere instalación propia y prueba GATT, FEC8 y óptica. Un build o UI test en Simulator no sustituye esa validación.

## Product Principles

1. **Local por construcción.** El control del equipo y sus datos operativos permanecen en el dispositivo; ninguna función central depende de cuenta, backend o telemetría.
2. **El estado deseado es explícito.** Estrobo no finge leer el estado completo del radio; Sync comunica claramente que sobrescribe desde la app.
3. **Fallar cerrado antes que adivinar.** Una entrega incierta conserva evidencia durable, bloquea operaciones incompatibles y exige recuperación contra el mismo radio.
4. **Un motor, interfaces nativas.** Protocolo, sesión y seguridad se comparten; la interfaz iOS pone el ajuste frecuente de potencia en cada grupo y reserva el detalle para trabajo avanzado, en vez de comprimir o copiar la UI macOS.
5. **Compatibilidad demostrada, no supuesta.** Nombre BLE, UUID, Simulator o acuses de transporte no sustituyen la prueba física y óptica de una combinación concreta.

## Accessibility & Inclusion

- Compatibilidad con Dynamic Type y VoiceOver.
- Targets táctiles apropiados.
- La pulsación larga de las tarjetas tiene respuesta visual durante la presión, feedback háptico al reconocerse, hint y acción personalizada `Detalles` para que la navegación no dependa de descubrir el gesto; Reduce Motion elimina la escala y conserva el cambio tonal.
- Ningún estado depende únicamente del color.
- Test, Beep, Modelado, Multi y Standby comunican que el toque es directo y se protegen mediante disabled states y gates; Test además conserva single-flight. Los cuatro tiles globales exponen texto, símbolo y trait de selección persistentes; no añaden confirmación ni estado de éxito fugaz, y el feedback pendiente sólo existe durante debounce o I/O real. Standby añade un overlay textual a cada grupo para que el bloqueo no dependa del color.
- Soporte para portrait, landscape, tamaños compactos y regulares, ventanas redimensionables de iPad y teclado externo.
- Los textos largos deben funcionar en español e inglés, en apariencia clara y oscura.

**Decisión abierta:** no se ha fijado una norma formal de conformidad accesible adicional a estos requisitos funcionales.
