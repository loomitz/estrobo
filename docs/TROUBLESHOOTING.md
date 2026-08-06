# Solución de problemas

Empieza por anotar la versión/build de Estrobo, versión de macOS, arquitectura del Mac, fase visible de la sesión y mensaje exacto. Nunca copies el Código del radio, un payload `Psub`/`PWOK`, tokens, UUID completos ni información personal.

## macOS no abre la app

Es esperado: el beta no tiene Developer ID ni notarización Apple.

1. Verifica primero el SHA-256 del ZIP contra `SHA256SUMS` del mismo GitHub Release.
2. Intenta abrir Estrobo una vez.
3. Ve a **Configuración del Sistema → Privacidad y seguridad → Seguridad → Abrir de todos modos**.
4. Autentícate y confirma **Abrir**.

El botón aparece durante un tiempo limitado después del intento. Sigue la [guía oficial de Apple](https://support.apple.com/guide/mac-help/mh40617/mac). No desactives Gatekeeper, no borres la cuarentena y no instales/confíes manualmente en el certificado autosignado.

Si `codesign --verify --deep --strict` o el checksum fallan, no abras la app: elimina esa copia y vuelve a descargar el asset oficial.

## No aparece el transmisor

- Enciende Bluetooth y concede permiso a Estrobo en Privacidad y seguridad.
- Cierra Godox Flash u otra app móvil/de escritorio que esté conectada. El transmisor sólo admite un central Bluetooth a la vez.
- Acerca el transmisor al Mac y vuelve a pulsar **Buscar**. El escaneo termina a los 10 segundos.
- Si acabas de cancelar o desconectar, espera a que el radio vuelva a anunciar y busca de nuevo.
- Confirma que el transmisor use el perfil BLE observado; un dispositivo Godox no es compatible sólo por la marca.

## Aparecen nombres duplicados

Estrobo no debe auto-seleccionar arbitrariamente dos radios con el mismo nombre. Compara RSSI y el sufijo corto del UUID. El UUID guardado se prioriza cuando reaparece.

Nombre, RSSI y UUID no son autenticación criptográfica. Si no puedes distinguir los equipos de forma segura, apaga temporalmente los radios ajenos y vuelve a buscar.

## La conexión se detiene en preparación

Conexión, descubrimiento de `FFF0`/`FEC0`, características y suscripciones tienen un plazo conjunto de 12 segundos.

- Asegúrate de que ninguna otra app conserve el enlace.
- Cancela, espera la desconexión y busca de nuevo.
- Si Estrobo informa un reset local de CoreBluetooth, la selección anterior ya no es válida: vuelve a buscar y a introducir el código.
- Un transmisor que no exponga `FFF1`, `FFF4`, `FEC7` y `FEC8` no puede completar este flujo.

## `PWOK` falla o expira

- El Código del radio debe contener exactamente seis dígitos; vacío, letras o longitud distinta se rechazan.
- No pruebes un código real en logs, tests, issues o capturas.
- El handshake espera 10 segundos y valida un token temporal; revisa que fecha y hora del Mac sean correctas.
- Un nombre/UUID coincidente no demuestra que el código sea correcto.
- Cancelar, fallar o desconectar limpia el código en memoria. Introdúcelo de nuevo.

El handshake `Psub`/`PWOK` siempre es obligatorio y utiliza el Código del radio. Ese código es el PIN local del transmisor, no una credencial fuerte ni un secreto de alto valor.

## Conecté y cambió el estado del radio

Es el comportamiento intencional. Tras `PWOK` y el Sync técnico, Estrobo usa su estado local como fuente de verdad y escribe A0 + A1 de los grupos configurados. No lee ni importa el estado previo.

Antes de reconectar, corrige el espacio de trabajo y los valores locales. Pulsar **Sync** vuelve a sobrescribir deliberadamente el radio aunque no haya borradores.

## Un cambio no se envía

- En Automático, espera 700 ms desde el último cambio.
- Mientras mantienes presionado un slider, el plazo no corre. Debe mostrarse **Ajustando…**; suelta para iniciar el envío.
- Si hay más de un control continuo activo, el plazo espera al último.
- Volver al baseline antes de soltar deja cero cambios que enviar.
- En **Con botón**, pulsa **Enviar ahora**.
- Si la sesión no está **Lista**, hay una recuperación o una tanda en curso, el envío permanece bloqueado.

En Automático puedes pulsar **Descartar** mientras el plazo está pendiente. Eso cancela el deadline y restaura el borrador, sin transmitir.

## Enviar ahora, Sync o Test están bloqueados

Es normal durante una edición interactiva, otra escritura, sincronización, recuperación o cuando existen borradores incompatibles con la acción global. Termina o cancela el gesto actual y espera el cierre de la tanda.

Desconectar debe seguir disponible. Si cerraste o cambiaste una vista durante un arrastre y **Ajustando…** no desaparece, reproduce el caso en modo simulado y abre un issue: no fuerces una escritura real.

## `FEC8` expiró o el resultado es incierto

No asumas que el grupo cambió ni que quedó igual. `FEC8` no identifica grupo, no devuelve los valores y no demuestra el resultado óptico.

1. No envíes cambios compensatorios desde otra app.
2. Reconecta el mismo radio/UUID.
3. Usa la recuperación para reaplicar el snapshot anterior.
4. Espera acuse GATT + `FEC8`.
5. Sólo entonces continúa o sincroniza.

Si el UUID es distinto, Estrobo debe bloquear la restauración.

## Test fue entregado pero no hubo destello

FFF1 usa write-without-response para Test. Estrobo sólo puede decir que entregó la orden a CoreBluetooth, no que el flash destelló.

- Revisa visualmente que el entorno sea seguro y los grupos correctos estén activos.
- Confirma canal/configuración del sistema Godox desde el propio equipo.
- No repitas automáticamente la acción ni la uses como prueba de conectividad.
- Registra modelo y firmware al reportar, pero nunca el Código del radio.

## El radio/código se recuerda o no se recuerda

La opción empieza apagada. Sólo si la activas, Estrobo guarda nombre, UUID y Código del radio localmente y sin cifrar después de completar `PWOK` + Sync. **Olvidar** elimina los tres datos y limpia el código visible.

El cambio de bundle identifier a `mx.loo.estrobo` crea preferencias limpias; datos del prototipo anterior no se migran automáticamente.

## Probar sin Bluetooth

Ejecuta el modo simulado explícito:

```sh
/usr/bin/open -n /Applications/estrobo.app --args --mock-radio
```

Debe aparecer **Radio simulado**. Este modo no inicia CoreBluetooth ni envía comandos físicos. Si el problema también ocurre ahí, incluye ese dato en el issue.

## Pedir ayuda

Sigue [Soporte](../SUPPORT.md) para un issue reproducible. Usa [Private Vulnerability Reporting](../SECURITY.md) si el fallo puede exponer datos, saltarse la selección del radio, ejecutar una acción bloqueada o comprometer la cadena de release.
