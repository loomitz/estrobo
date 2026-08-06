# Cómo funciona Estrobo

Estrobo es una aplicación SwiftUI/AppKit que actúa como central BLE mediante CoreBluetooth. La app conserva el estado deseado, construye tramas del protocolo observado y las entrega directamente al transmisor. No existe cuenta, backend, acceso a Internet, analítica ni telemetría.

## Modelo mental

```mermaid
flowchart LR
    P["Persona"] -->|"configura y ajusta"| UI["Interfaz Estrobo"]
    UI --> L["Estado local y borradores"]
    L --> C["Controlador de sesión"]
    C -->|"CoreBluetooth BLE/GATT"| R["Transmisor"]
    R -->|"acuse GATT y FEC8 limitado"| C
    L --> S["Preferencias del sandbox"]
    X["Sin cuenta, backend ni Internet"] -.-> UI
```

El transmisor no ofrece una lectura completa que permita reconstruir su estado. Por eso la flecha importante va de Estrobo al radio: el estado local es la fuente de verdad.

## Ciclo de una sesión

1. **Preparar el espacio de trabajo.** Se elige un perfil, los grupos de trabajo y uno o más modelos de flash por grupo. El rango manual disponible es la intersección segura de esos modelos.
2. **Buscar y seleccionar.** Estrobo muestra nombre BLE, RSSI y un sufijo corto del UUID. Prioriza el UUID recordado. Si hay nombres duplicados no elige uno arbitrariamente.
3. **Preparar BLE.** CoreBluetooth conecta, descubre `FFF0`/`FEC0`, localiza `FFF1`, `FFF4`, `FEC7` y `FEC8`, y activa notificaciones o indicaciones.
4. **Validar el Código del radio.** Un reto local `Psub` viaja por BLE y la app valida temporalmente una respuesta `PWOK`. No interviene una cuenta ni un servicio remoto. El código no constituye autenticación fuerte.
5. **Sincronizar.** Estrobo envía el Sync técnico y después sobrescribe A0 y cada A1 configurado. La secuencia no lee ni importa el estado previo.
6. **Editar.** Las tres vistas comparten los mismos borradores. Un cambio discreto se programa para envío o queda pendiente según el modo elegido.
7. **Confirmar o recuperar.** A0 requiere acuse GATT; cada A1 requiere acuse GATT y después una respuesta `FEC8`. Un resultado incierto bloquea nuevas escrituras hasta reconectar el mismo radio y recuperar el estado seguro guardado.

El detalle del enlace está en [Conexión Bluetooth](BLUETOOTH-CONNECTION.md) y la semántica de sobrescritura en [Sincronización automática](AUTOMATIC-SYNC.md).

## Estado global A0 y grupos A1

- **A0** es una instantánea global. Estrobo la usa para valores como Beep master y Standby, preservando también los campos globales que aún no tienen un control visual.
- **A1** es una instantánea completa por grupo: modo, potencia manual de referencia, intensidad de modelado, Beep subordinado, modo de modelado y compensación.
- En una sincronización completa se escribe **A0 primero** y después un **A1 por cada grupo de trabajo**, en orden y sin solapar escrituras.
- Los grupos ocultos siguen siendo parte del espacio de trabajo y de la sincronización; ocultar sólo cambia la presentación.
- Los grupos que no pertenecen al espacio de trabajo no reciben A1. A0 sigue siendo global por definición.

Una confirmación de transporte no equivale a una medición física. En particular, `FEC8` sólo contiene un prefijo A1 utilizable para avanzar la cola; no identifica grupo, no devuelve el cuerpo aplicado y no confirma luz o destello.

## Entrega de cambios

**Automático** es el valor predeterminado. Espera 700 ms desde el último cambio y reúne los grupos pendientes en una sola tanda serial. **Con botón** conserva los borradores hasta pulsar **Enviar ahora**. Ambos modos usan el mismo validador y la misma cola A1.

Los controles continuos abren una transacción interactiva con token. Mientras el puntero sigue presionado:

- la UI y los borradores cambian en vivo;
- no se arma ni ejecuta el plazo automático;
- Apply/Enviar ahora, Sync, Test y acciones que sustituyen o transmiten el borrador quedan bloqueados en todas las ventanas;
- Desconectar permanece disponible.

Al finalizar el último token se arma una sola vez el debounce de 700 ms y sólo puede transmitirse el valor final. Teclado, VoiceOver, botones y toggles siguen siendo cambios discretos normales. Si el control desaparece, se deshabilita o la sesión se cancela, la vista libera su token.

## Controles disponibles

- Potencia Manual en pasos de 1/3 EV (`.0`, `.3`, `.7`) dentro del rango común de los flashes asignados.
- M, Auto/TTL y Off. Multi puede decodificarse, pero no se edita.
- Luz de modelado apagada, proporcional o fija entre 10% y 100%; la cobertura óptica fuera de los puntos observados sigue siendo limitada.
- Ajuste global relativo de potencia hasta ±3 EV sin romper la relación entre grupos.
- Beep como una sola decisión A0 + A1; Standby como cambio A0-only.
- Test explícito por `FFF1`; nunca se dispara durante conexión, Sync, restauración o carga de preset.
- Presets nombrados que guardan valores, no UUID ni Código del radio.

## Datos locales

La app guarda dentro de su sandbox el espacio de trabajo, presets y preferencias de interfaz/entrega. Un punto de recuperación contiene UUID, grupo y snapshot A1 anterior, nunca el Código del radio. Recordar el radio es opt-in: sólo entonces se guardan localmente y sin cifrar nombre, UUID y código. Consulta [Privacidad](../PRIVACY.md).

El bundle público usa `mx.loo.estrobo`. El cambio desde el identificador de prototipo crea una identidad limpia de preferencias antes de incorporar participantes públicos; la app no migra automáticamente los datos del prototipo.

## Modo simulado y pruebas

`--mock-radio` inyecta un transporte determinista dentro del proceso. No crea un central CoreBluetooth ni habla con hardware. El mismo controlador recorre búsqueda, `PWOK`, Sync, A0/A1, cambios y fallos simulados.

Las pruebas verifican bytes/CRC, cola serial, timeouts, recuperación, persistencia y comportamiento de interacción. El harness AppKit/SwiftUI genera mouse-down, pausa, drag y mouse-up para comprobar que mantener presionado más de 700 ms no transmite valores intermedios. Las pruebas deterministas no sustituyen los gates manuales de transmisor y Macs físicos descritos en [Checklist de release](RELEASE-CHECKLIST.md).

## Límites de diseño intencionales

- Sin lectura completa radio → app.
- Sin cuenta o backend.
- Sin cambio de Código del radio, omisión del handshake `Psub`/`PWOK`, criptografía casera, edición de firmware u OAD.
- Sin reintento automático de Test.
- Sin afirmaciones de autenticidad basadas sólo en nombre BLE, RSSI o UUID.
