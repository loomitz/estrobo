# Conexión Bluetooth

Estrobo se comunica localmente con el transmisor mediante BLE/GATT y CoreBluetooth. No hay cuenta, backend ni Internet en este flujo. La conexión es exclusiva: cierra primero cualquier otra app conectada al transmisor.

> [!CAUTION]
> Conectar y sincronizar sobrescribe intencionalmente el estado global A0 y los A1 de los grupos configurados con el estado local de Estrobo. No existe una lectura completa radio → app y Sync no importa la configuración previa.

## Secuencia

```mermaid
sequenceDiagram
    autonumber
    actor U as Persona
    participant E as Estrobo
    participant C as CoreBluetooth
    participant R as Transmisor BLE
    Note over E,R: Flujo local; sin cuenta, backend ni Internet
    U->>E: Buscar y seleccionar por nombre, RSSI y sufijo UUID
    E->>C: Escanear y conectar al periférico elegido
    C->>R: Conexión BLE
    E->>C: Descubrir servicios FFF0 y FEC0
    C->>R: Descubrir características FFF1, FFF4, FEC7 y FEC8
    E->>C: Suscribir FFF4; pausa; suscribir FEC8
    E->>R: FFF1 sin respuesta: reto local Psub con código sintético
    R-->>E: FFF4: PWOK con token temporal
    E->>R: FFF1 sin respuesta: Sync técnico
    Note over E,R: Estrobo no lee el estado completo; empieza la sobrescritura deliberada
    E->>R: FEC7 con respuesta: snapshot global A0
    R-->>E: Acuse GATT de A0
    loop Un A1 serial por cada grupo configurado
        E->>R: FEC7 con respuesta: snapshot A1 completo
        R-->>E: Acuse GATT de A1
        R-->>E: FEC8 con prefijo F0 A1
    end
    opt Heartbeat FEC8 de seis bytes con F0 E0
        R-->>E: Heartbeat
        E->>R: FEC7 con respuesta: F0 E0
    end
    alt Timeout o resultado incierto
        E->>E: Detener cola y conservar punto local de recuperación
        E-->>U: Reconectar el mismo UUID y restaurar antes de continuar
    end
```

Los textos del diagrama son marcadores descriptivos, no payloads para copiar. Ningún ejemplo de esta documentación contiene un Código del radio real.

## Paso a paso

1. **Escaneo y selección.** Estrobo escanea periféricos compatibles y muestra nombre, RSSI y sufijo corto del UUID.
2. **Conexión CoreBluetooth.** La app solicita una conexión central → periférico al radio elegido.
3. **Servicios.** Descubre el servicio de autenticación/prueba `FFF0` y el servicio de control `FEC0`.
4. **Características.** Localiza escritura `FFF1`, respuesta `FFF4`, escritura `FEC7` y respuesta `FEC8`.
5. **Suscripciones.** Activa `FFF4` y, tras una pausa aproximada de 500 ms, `FEC8`. CoreBluetooth abstrae notification/indication mediante la misma suscripción.
6. **Reto local.** Envía por `FFF1` sin respuesta un mensaje ASCII con nonce, `Psub` y el Código del radio. Acepta sólo una respuesta `PWOK` cuyo token temporal valide dentro de ±20 segundos.
7. **Sync técnico.** Después de `PWOK`, entrega por `FFF1` un timestamp local desde 2017 acompañado de `Sync` y espera aproximadamente 500 ms.
8. **Sobrescritura deliberada.** Construye el A0 completo y, después, un A1 completo por cada grupo de trabajo configurado.
9. **Confirmación A0.** A0 se escribe en `FEC7` con respuesta y termina con acuse GATT. Un posible eco A0 en `FEC8` es informativo.
10. **Confirmación A1.** Cada A1 se escribe en `FEC7`, espera acuse GATT y sólo entonces acepta un `FEC8` con prefijo `F0 A1`. La cola avanza de un grupo al siguiente de forma serial.
11. **Heartbeat y plazos.** Un heartbeat `F0 E0` de seis bytes recibe respuesta `F0 E0` por `FEC7`; si su write no confirma en cinco segundos, la sesión se invalida.
12. **Resultado incierto.** Un write A1 fallido, una desconexión o la ausencia de `FEC8` detienen la tanda. Estrobo conserva un punto local previo y exige reconectar el mismo UUID para recuperarlo.

## Qué demuestran los acuses

| Señal | Qué sí demuestra | Qué no demuestra |
| --- | --- | --- |
| Acuse GATT de A0 | CoreBluetooth confirmó el write global | Resultado óptico o lectura posterior del estado |
| Acuse GATT de A1 | El write A1 fue aceptado por la capa GATT | Que el grupo o flash haya aplicado el cambio |
| `FEC8` con `F0 A1` | Llegó la respuesta limitada que permite avanzar la cola | Grupo, valores, CRC del estado aplicado o resultado óptico |
| Entrega de Test a CoreBluetooth | La orden explícita no quedó en cola local | Que un flash haya destellado |

`FEC8` no identifica grupo. Estrobo sólo lo correlaciona con la única escritura serial que ya recibió acuse GATT; una notificación anticipada se ignora.

## Plazos de recuperación

| Fase | Plazo |
| --- | ---: |
| Escaneo | 10 s |
| Conexión + descubrimiento + suscripciones | 12 s |
| Espera de `PWOK` | 10 s |
| Pausa antes de A0/A1 | 500 ms |
| Acuse GATT A0/A1 | 5 s |
| `FEC8` posterior a A1 | 2 s |
| Acuse de heartbeat | 5 s |
| Entrega de Test | 3 s |
| Callback de desconexión antes de reset local | 3 s |

Cancelar o agotar un plazo limpia el código en memoria y no debe iniciar A0/A1. Si CoreBluetooth no confirma la desconexión, Estrobo reconstruye su transporte local; después hay que buscar y seleccionar de nuevo.

## Selección e identidad del radio

- El UUID guardado se prioriza en búsquedas posteriores.
- Nombre, RSSI y UUID reducen errores de selección, pero ninguno autentica criptográficamente al transmisor.
- Si aparecen nombres duplicados, Estrobo no auto-selecciona arbitrariamente y muestra una advertencia ligera. Compara el sufijo UUID y la proximidad antes de continuar.
- El RSSI varía con distancia, orientación e interferencia; no es una identidad estable.

## Código del radio y riesgo aceptado

El Código del radio es un parámetro local de compatibilidad/proximidad de seis dígitos. El protocolo Godox lo transmite dentro del reto BLE y no ofrece autenticación fuerte. No protege cuentas, pagos, datos personales ni servicios remotos.

La opción de recordarlo empieza apagada. Si la persona la activa, Estrobo lo conserva localmente y sin cifrar junto con nombre y UUID después de `PWOK` + Sync; nunca lo manda a Internet. No reutilices un PIN personal. **Olvidar** elimina esa copia.

No se admite código vacío ni se añade pairing obligatorio. Radios que presuntamente trabajan sin código requieren observar primero su handshake físico; no se relaja el protocolo por conjetura.

## Sin lectura radio → app

El transmisor no entrega una instantánea completa y correlacionada que permita importar A0/A1. Por eso:

- los valores mostrados son el estado local deseado y el último trabajo confirmado por esta app;
- conectar siempre inicia A0 + A1 desde Estrobo;
- pulsar **Sync** repite deliberadamente la misma sobrescritura aunque no existan borradores;
- un acuse no convierte a Estrobo en lector del estado físico.

Consulta [Sincronización automática](AUTOMATIC-SYNC.md) y [Solución de problemas](TROUBLESHOOTING.md).
