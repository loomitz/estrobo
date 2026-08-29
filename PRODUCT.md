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
- Uso foreground-only: al quedar inactiva o en background detiene el scan, cancela gestos y debounces, no arma writes nuevos y conserva cualquier journal incierto.
- El enlace Bluetooth con el transmisor es exclusivo; otra app conectada debe cerrarse antes.
- Antes de conectar, la persona configura compatibilidad de grupos, grupos de trabajo y modelos de flash.
- Sync aplica deliberadamente el estado local al transmisor; no importa su configuración previa.
- Test y Multi operan equipo físico y requieren una acción táctil intencional, estado pendiente visible y un entorno ópticamente seguro.
- iPhone usa navegación por onboarding, conexión, grupos, detalle, controles globales, presets, transmisores guardados y ajustes.
- iPad usa una estructura adaptable con sidebar, workspace e inspector; Matriz aparece sólo cuando el ancho lo permite.
- Demo debe poder iniciarse desde el onboarding, permanecer identificado como simulado y usar transporte y stores aislados de los datos reales.

## Capabilities and Constraints

- Conserva las capacidades de Beta 4: perfiles de compatibilidad, grupos y modelos; búsqueda, selección, Código del radio, PWOK y Sync; M, TTL/Auto y Off; potencia Manual; modelado; Beep; Standby; Test; Multi global con participantes, potencia, conteo, Hz y límites por modelo; entrega Automática o Con botón; presets; transmisores guardados; recuperación; español/inglés y claro/oscuro.
- `EstroboCore` contiene dominio, codecs A0/A1, capacidades, Multi, sesión, entrega, seguridad y recuperación, sin AppKit, UIKit ni SwiftUI.
- `EstroboBluetooth` expone un `RadioTransport` pequeño con adaptadores CoreBluetooth y simulado, sin duplicar reglas o payloads.
- `EstroboPersistence` conserva workspace, presets, preferencias, transmisores guardados, un `RadioCodeVault` basado en Keychain y un `RestorationJournal` durable y atómico; los tests usan adaptadores en memoria.
- Hay un solo coordinador de sesión/Bluetooth a nivel de aplicación, gobernado por `scenePhase`.
- A0 precede a cualquier A1 dependiente; los writes son seriales y se confirman mediante GATT y FEC8 según corresponda.
- El journal se escribe antes de transmitir y la recuperación sólo puede continuar contra el mismo UUID local observado por ese dispositivo iOS.
- Un UUID CoreBluetooth de macOS no se sincroniza ni se considera igual al observado por iPhone.
- Test nunca queda en cola ni se reintenta automáticamente.
- La entrega automática espera 700 ms después del último cambio. Un gesto continuo no transmite valores intermedios y sólo puede producir el valor final al terminar o cancelarse.
- Recordar un transmisor es opt-in y sólo ocurre después de PWOK + Sync. Olvidar uno no elimina los demás.
- “Compatibilidad de grupos” nombra capacidades técnicas; “Transmisores guardados” nombra dispositivos físicos persistidos.
- Logs y diagnósticos nunca muestran el Código del radio ni payloads de autenticación.
- No hay backend, analítica, anuncios ni telemetría. No se solicitan permisos de cámara, ubicación o red local.
- El MVP no declara `UIBackgroundModes` ni promete restauración Bluetooth en background.
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
- El mark existente vive en `prototype/GodoxMacControlPrototype/Resources/Brand/EstroboMark1024.png`.
- No deben añadirse afirmaciones de compatibilidad, seguridad o validación física que excedan la evidencia registrada.

## Evidence on Hand

- `README.es.md`: propósito local, flujo de uso, capacidades Beta 4, límites y terminología pública.
- `docs/HOW-IT-WORKS.md`: modelo de sesión, A0/A1, entrega, recuperación, persistencia y transporte simulado.
- `docs/BLUETOOTH-CONNECTION.md`: secuencia BLE/GATT, señales de confirmación, timeouts y límites de identidad.
- `docs/AUTOMATIC-SYNC.md`: sobrescritura Sync, debounce, gestos continuos, serialización y recuperación fail-closed.
- `docs/BETA.md`: alcance acotado de compatibilidad y separación entre entrega Bluetooth y resultado óptico.
- `PRIVACY.md` y `SECURITY.md`: flujo local, datos persistidos, redacción de secretos y riesgos aceptados del protocolo.
- `prototype/GodoxMacControlPrototype/Sources/`: implementación macOS existente que debe alimentar el núcleo compartido.
- `prototype/GodoxMacControlPrototype/Tests/`: cobertura existente de protocolo, recuperación, persistencia, localización e interacción.
- Evidencia física documentada hasta ahora: Mac ↔ Godox X3Pro por Bluetooth y X3Pro ↔ Godox AD400Pro II por radio. No se registraron las revisiones exactas de firmware y no todas las funciones tienen validación óptica.
- La Beta 4 macOS publicada conserva el Código del radio sin cifrar por opt-in. El árbol de desarrollo compartido ya migró macOS e iOS a `RadioCodeVault` con Keychain `WhenUnlockedThisDeviceOnly`; esa migración aún no constituye una nueva release macOS.
- No existe todavía evidencia física iOS para CoreBluetooth o AccessorySetupKit. Un build o UI test en Simulator no debe presentarse como esa validación.

## Product Principles

1. **Local por construcción.** El control del equipo y sus datos operativos permanecen en el dispositivo; ninguna función central depende de cuenta, backend o telemetría.
2. **El estado deseado es explícito.** Estrobo no finge leer el estado completo del radio; Sync comunica claramente que sobrescribe desde la app.
3. **Fallar cerrado antes que adivinar.** Una entrega incierta conserva evidencia durable, bloquea operaciones incompatibles y exige recuperación contra el mismo radio.
4. **Un motor, interfaces nativas.** Protocolo, sesión y seguridad se comparten; la interfaz iOS se diseña para interacción táctil y no como compresión de la UI macOS.
5. **Compatibilidad demostrada, no supuesta.** Nombre BLE, UUID, Simulator o acuses de transporte no sustituyen la prueba física y óptica de una combinación concreta.

## Accessibility & Inclusion

- Compatibilidad con Dynamic Type y VoiceOver.
- Targets táctiles apropiados.
- Ningún estado depende únicamente del color.
- Test y Multi incluyen protección contra taps accidentales y estados pendientes comprensibles.
- Soporte para portrait, landscape, tamaños compactos y regulares, ventanas redimensionables de iPad y teclado externo.
- Los textos largos deben funcionar en español e inglés, en apariencia clara y oscura.

**Decisión abierta:** no se ha fijado una norma formal de conformidad accesible adicional a estos requisitos funcionales.
