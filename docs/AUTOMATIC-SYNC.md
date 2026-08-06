# Sincronización automática

La palabra **Sync** en Estrobo significa **aplicar el estado local al transmisor**, no leer ni importar lo que ya tenga el radio.

> [!WARNING]
> Después de `PWOK` y el Sync técnico, Estrobo escribe deliberadamente A0 y los A1 de todos los grupos de trabajo configurados. Conectar equivale a aceptar esa sobrescritura. No hay confirmación adicional por conexión porque este comportamiento es parte del contrato del producto.

## Qué ocurre al conectar

1. Estrobo valida localmente `PWOK`.
2. Entrega el Sync técnico por `FFF1`.
3. Espera 500 ms.
4. Escribe la instantánea global A0 y espera su acuse GATT.
5. Recorre los grupos configurados en orden; para cada A1 espera acuse GATT + `FEC8` antes de seguir.
6. Sólo muestra **Listo** cuando termina la secuencia completa.

Los grupos de trabajo ocultos también se escriben. Los grupos fuera del espacio de trabajo no reciben A1, aunque A0 sigue afectando el estado global del radio.

Pulsar **Sync** después repite exactamente esa secuencia A0 → A1, incluso si no hay cambios pendientes. Es una acción de sobrescritura forzada.

## Automático y Con botón

| Modo | Cuándo transmite | Cómo cancelar |
| --- | --- | --- |
| **Automático** (predeterminado) | 700 ms después del último cambio discreto o después de soltar el último control continuo | **Descartar** mientras el plazo esté esperando |
| **Con botón** | Al pulsar **Enviar ahora** | **Descartar** antes del envío |

Cambiar de vista, abrir Configuración u ocultar grupos no transmite por sí mismo. Cargar un preset con **Cargar en Estrobo** sólo reemplaza borradores locales; **Cargar y sincronizar** sí inicia la secuencia de envío.

## Controles continuos

Un slider inicia una transacción interactiva al presionar y recibe un token propio. Mientras exista al menos un token:

- los borradores y la UI se actualizan en vivo;
- ningún deadline automático puede armarse ni ejecutarse;
- se muestran **Ajustando…** y **Suelta para iniciar el envío automático**;
- Apply/Enviar ahora, Sync, Test y cualquier acción que sustituya o transmita el borrador quedan bloqueados, incluso desde otra ventana;
- **Desconectar** permanece disponible.

Al soltar, el token termina de forma idempotente. Sólo el final del último token concurrente puede armar una vez el plazo de 700 ms. Se transmite únicamente el valor final. Si vuelves al baseline antes de soltar, no hay nada que enviar.

Esto se aplica al slider global de potencia, `VerticalDiscretePowerControl`, `DiscretePowerSlider` y `VerticalFixedIntensityControl`. Si una vista desaparece, el control se deshabilita o la sesión se cancela, el token se libera para no dejar la app atascada.

## Cambios discretos

Botones, toggles, teclado y VoiceOver no simulan un arrastre: cada acción válida es un cambio discreto normal. En Automático reinicia el debounce de 700 ms; en Con botón deja el borrador pendiente.

Un clic simple en un control continuo sigue siendo válido. El valor cambia al soltar y Automático lo envía 700 ms después.

## Una sola tanda serial

Los grupos pendientes se capturan como snapshots A1 completos y forman una tanda ordenada. Nunca se solapan writes A1. Cada grupo debe completar GATT + `FEC8` antes del siguiente.

Beep usa una secuencia A0 master + A1 subordinados y no se ejecuta si podría arrastrar otros borradores A1. Standby es A0-only y conserva los A1. Test es una acción global explícita y sólo se habilita sin borradores, recuperación, edición interactiva ni escritura en curso.

## Descartar

**Descartar** reutiliza el último baseline local confirmado:

- cancela el plazo automático pendiente;
- restaura los borradores todavía no enviados;
- no manda A0, A1 ni Test;
- no revierte una escritura que ya empezó.

Si el resultado ya es incierto, Descartar no puede afirmar qué ocurrió en el radio; debe usarse la recuperación.

## Resultado incierto

Un fallo de write, timeout, cierre o desconexión durante A1 detiene la cola. Estrobo guarda antes del write el UUID, grupo y snapshot seguro anterior, sin Código del radio. Para continuar:

1. No asumas que el cambio se aplicó ni intentes compensarlo desde otra app.
2. Reconecta el mismo transmisor, identificado por UUID.
3. Usa el flujo de recuperación para reaplicar el snapshot seguro.
4. Espera su GATT + `FEC8` antes de volver a sincronizar.

`FEC8` no dice qué grupo respondió ni demuestra el resultado óptico. La serialización y la recuperación fail-closed son las únicas garantías que Estrobo puede construir sobre esa señal limitada.

## Ejemplos

- **Arrastre largo:** mantener el mouse presionado dos segundos produce cero payloads. Al soltar se arma un solo plazo y se envía el valor final.
- **Pausa durante el arrastre:** aunque la pausa supere 700 ms, no se transmite un valor intermedio.
- **Dos controles activos:** terminar uno no arma el plazo; hay que terminar el último token.
- **Regreso al baseline:** mover y volver al valor inicial antes de soltar no envía nada.
- **Teclado:** una flecha que cambie un paso arma normalmente los 700 ms.
