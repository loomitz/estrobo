# Sincronización automática

La palabra **Sync** en Estrobo significa **aplicar el estado local al transmisor**, no leer ni importar lo que ya tenga el radio.

> [!WARNING]
> Después de `PWOK` y el Sync técnico, Estrobo escribe deliberadamente A0 y los A1 de todos los grupos de trabajo configurados. Conectar equivale a aceptar esa sobrescritura. No hay confirmación adicional por conexión porque este comportamiento es parte del contrato del producto.

## Qué ocurre al conectar

1. Estrobo valida localmente `PWOK`.
2. Entrega el Sync técnico por `FFF1`.
3. Espera 500 ms.
4. Escribe la instantánea global A0 —incluidos los ajustes Multi— y espera su acuse GATT.
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

Esto se aplica al slider global de potencia, los sliders de destellos y Hz de Multi, `VerticalDiscretePowerControl`, `DiscretePowerSlider` y `VerticalFixedIntensityControl`. Si una vista desaparece, el control se deshabilita o la sesión se cancela, el token se libera para no dejar la app atascada.

## Cambios discretos

Botones, toggles, teclado y VoiceOver no simulan un arrastre: cada acción válida es un cambio discreto normal. En Automático reinicia el debounce de 700 ms; en Con botón deja el borrador pendiente.

Un clic simple en un control continuo sigue siendo válido. El valor cambia al soltar y Automático lo envía 700 ms después.

## Una sola tanda serial

Los grupos pendientes se capturan como snapshots A1 completos y forman una tanda ordenada. Si cambió el ajuste global Multi, su A0 se escribe y confirma antes del primer A1; si sólo cambió potencia, destellos o Hz, la tanda termina tras ese A0. A0 contiene la potencia Multi efectiva. El A1 de cada grupo conserva su potencia Manual si entró desde M o usa `0x32` si entró desde TTL; ese byte no sustituye la potencia global. Nunca se solapan writes A1. Cada grupo debe completar GATT + `FEC8` antes del siguiente.

Beep usa una secuencia A0 master + A1 subordinados y no se ejecuta si podría arrastrar otros borradores A1. Standby es A0-only y conserva los A1. El botón Multi junto a Beep es la única vía para cambiar el gate global. Al encenderlo convierte juntos todos los grupos de trabajo activos y compatibles a Multi, pone en Off a los no participantes y arma A0 Multi seguido de los A1 afectados. Mientras el gate siga activo, los controles de participación agregan o quitan grupos compatibles, pero no pueden quitar el último. Al apagar desde el botón, Estrobo arma A0 sin Multi y después A1 Manual para todos los grupos del workspace. Los grupos externos no reciben A1. Test es una acción global explícita y sólo se habilita sin borradores, recuperación, edición interactiva ni escritura en curso.

La exposición mínima mostrada es `destellos ÷ Hz`, redondeada hacia arriba a milésimas de segundo. Es una guía para elegir el tiempo de obturación, no una confirmación óptica ni una promesa del número real de destellos.

## Descartar

**Descartar** reutiliza el último baseline local confirmado:

- cancela el plazo automático pendiente;
- restaura los borradores todavía no enviados;
- no manda A0, A1 ni Test;
- no revierte una escritura que ya empezó.

Si el resultado ya es incierto, Descartar no puede afirmar qué ocurrió en el radio; debe usarse la recuperación.

## Resultado incierto

Un fallo de write, timeout, cierre o desconexión durante A0/A1 detiene la cola. Antes del primer write, Estrobo guarda un journal atómico con el UUID, el A0 anterior y todos los A1 originales de la tanda, sin Código del radio. Confirmar un grupo intermedio no reduce ni borra ese lote. Para continuar:

1. No asumas que el cambio se aplicó ni intentes compensarlo desde otra app.
2. Reconecta el mismo transmisor, identificado por UUID.
3. Usa el flujo de recuperación para reenviar A0 y espera su acuse GATT.
4. Reenvía después todos los A1 originales, en orden, y espera GATT + `FEC8` para cada uno.
5. Sólo al confirmar la escena completa se borra el journal y Estrobo vuelve a permitir edición, Sync, Test u otra operación normal.

`FEC8` no dice qué grupo respondió ni demuestra el resultado óptico. La serialización y la recuperación fail-closed son las únicas garantías que Estrobo puede construir sobre esa señal limitada.

## Ejemplos

- **Arrastre largo:** mantener el mouse presionado dos segundos produce cero payloads. Al soltar se arma un solo plazo y se envía el valor final.
- **Pausa durante el arrastre:** aunque la pausa supere 700 ms, no se transmite un valor intermedio.
- **Dos controles activos:** terminar uno no arma el plazo; hay que terminar el último token.
- **Regreso al baseline:** mover y volver al valor inicial antes de soltar no envía nada.
- **Teclado:** una flecha que cambie un paso arma normalmente los 700 ms.
- **Sólo Hz Multi:** cambiar la frecuencia sin cambiar grupos produce un único A0 después del debounce.
- **Entrar a Multi:** pulsar el botón global convierte atómicamente todos los grupos activos compatibles a Multi, pone en Off a los no participantes, confirma A0 con potencia/destellos/Hz y sólo después envía todos los A1 afectados.
- **Salir de Multi:** pulsar de nuevo el botón global desactiva el gate A0 y envía A1 Manual para todos los grupos de trabajo, incluidos los que antes estaban TTL u Off; no escribe grupos fuera del workspace.
- **Recuperar Multi:** Estrobo reenvía y confirma A0 antes de todos los A1 seguros de la escena; el journal completo permanece intacto hasta la última confirmación y ninguna operación normal se habilita entre medias.
