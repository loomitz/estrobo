# Design QA — Menú compacto con encendido integrado

## Verdad visual

- Referencia seleccionada: panel izquierdo de
  `QA/menu-bar-integrated-power-comparison.png`; la imagen exploratoria original
  no forma parte del repositorio.
- Implementación renderizada: `QA/menu-bar-integrated-power-dark-es.png`.
- Comparación conjunta, referencia a la izquierda e implementación a la derecha:
  `QA/menu-bar-integrated-power-comparison.png`.
- Estado: tema oscuro, español, sesión sintética conectada, B/C encendidos,
  modo M y potencias `1/512 +0.0` / `1/256 +0.7`.
- La implementación se capturó a 2× (720 × 466 px). La comparación mide
  1440 × 466 px y contiene dos mitades de 720 × 466 px para comparar densidad
  y proporciones iguales.
- Los tres PNG de esta revisión están normalizados a sRGB de 8 bits y no
  conservan perfiles ICC ni metadatos específicos de la estación de trabajo.

## Evidencia de comparación

- Vista completa: la jerarquía, los dos grupos, los botones de paso, las
  lecturas centradas, el estado de conexión y las opciones del pie permanecen
  visibles sin recortes ni desbordamientos.
- No fue necesario un recorte adicional: tipografía, iconos, espaciado y estados
  son legibles en la comparación completa a 2×.
- La captura omite el marco redondeado del `MenuBarExtra` porque registra sólo
  el contenido del componente; macOS aporta ese marco al desplegable real.
- El distintivo **SIMULACIÓN** existe sólo en la sesión sintética usada para QA
  y no aparece con un radio físico.

## Superficies de fidelidad

- Tipografía: fuente de sistema de macOS; las potencias conservan diseño
  monoespaciado, dígitos tabulares, peso semibold y una jerarquía equivalente a
  la referencia. No hay texto truncado ni saltos inesperados.
- Ritmo y espaciado: encabezado de 42 pt, filas de 72 pt, controles de grupo de
  44 pt y panel de 360 pt. Las lecturas permanecen centradas entre menos y más.
- Colores: fondo y divisores usan los tokens existentes de Estrobo. B/C mantienen
  su identidad verde/azul y el estado apagado reduce contraste sin perder la
  identificación del grupo.
- Iconos y activos: todos los controles usan SF Symbols nativos; no hay logos,
  imágenes aproximadas, placeholders ni activos raster faltantes.
- Copia: `Conectado`, `Abrir Estrobo`, `Salir`, B/C, M y las potencias coinciden
  con el estado de producto. Las etiquetas y ayudas de VoiceOver cambian entre
  **Encender** y **Apagar** según corresponda.

## Comparación e iteraciones

- Primera comparación: P2, el separador entre grupos comenzaba después del
  bloque de grupo y el pie no separaba visualmente **Salir**.
- Corrección: el separador ahora usa el margen horizontal completo del panel y
  el pie incluye un divisor vertical antes de **Salir**.
- Evidencia posterior: `QA/menu-bar-integrated-power-comparison.png`; no quedan
  diferencias P0, P1 o P2. El texto oscuro de B es una decisión intencional del
  token existente para mantener contraste sobre verde claro.

## Interacción

- La vista nativa se probó con `MockGodoxSessionTransport`; no se inicializó
  Bluetooth ni se enviaron órdenes a hardware.
- Pulsar el bloque B cambió su valor accesible de **Encendido** a **Apagado**,
  mostró OFF y deshabilitó menos, selector y más. La evidencia del estado está
  en `QA/menu-bar-integrated-power-off-dark-es.png`.
- Pulsar nuevamente el mismo bloque restauró B a **Encendido** y reactivó sus
  controles. C permaneció independiente y encendido.
- El árbol nativo de accesibilidad expuso estado, encendido/apagado, potencia,
  botones de paso, abrir y salir como roles `Button`/`MenuButton`, con etiquetas,
  valores, ayudas y estado deshabilitado localizados.
- La acción AX/VoiceOver **Increment** cambió B de `1/512 +0.0` a
  `1/512 +0.3`; **Decrement** restauró el valor. El selector de potencia se abrió
  y eligió el siguiente paso mediante flechas + Return, sin puntero.
- `make test-menu-bar-accessibility` y `make test-launch-responsiveness`
  terminaron correctamente en modo simulado. El primero conserva sin TCC el
  contrato compartido de descriptores, acciones, render y modificadores; el
  smoke AX sobre una app aislada valida por separado la superficie publicada
  por macOS. La suite completa se vuelve a ejecutar como gate del candidato.

## Hallazgos finales

No quedan diferencias P0, P1 o P2 respecto a la opción 1 seleccionada. Como P3
opcional, el bloque B podría usar glifo blanco para copiar literalmente el mock,
pero el color oscuro actual ofrece mejor contraste y respeta el sistema visual
existente.

final result: passed

---

# Design QA — Inicio, compatibilidad y transmisores guardados

## Objetivo

- Hacer que una instalación nueva empiece con cero grupos y cero modelos
  elegidos, con una acción clara para iniciar la configuración.
- Separar la definición técnica de grupos/capacidades de la identidad de un transmisor físico.
- Presentar la primera como **Compatibilidad de grupos**, sin llamarla perfil guardado.
- Ofrecer una biblioteca plural de **Transmisores guardados** con estado, UUID abreviado y olvido individual.
- Conservar el Código del radio fuera de la lista y pedir confirmación antes de eliminarlo.

## Verdad visual

Las capturas actuales provienen del bundle SwiftUI build 3 ejecutado con
`--mock-radio`; no inicializan Bluetooth ni envían comandos físicos.

- Configuración en inglés, tema oscuro, 760 × 600 px:
  `QA/saved-transmitters-settings-dark-en.png`
- Biblioteca vacía en español, tema oscuro, 720 × 540 px:
  `QA/saved-transmitters-empty-dark-es.png`

El estado vacío es intencional: evita incluir UUID o Códigos del radio reales
en evidencia pública. Los estados con varios dispositivos se validan con datos
sintéticos en las pruebas automatizadas.

## Comparación visual

### Jerarquía y contenido

- Configuración muestra **Compatibilidad de grupos** y explica que no representa
  un transmisor guardado.
- **Transmisores guardados** tiene su propio conteo y acción de entrada.
- La biblioteca explica que un transmisor aparece sólo si **Recordar** estaba
  activo y autenticación + Sync terminaron correctamente.
- La lista nunca muestra el Código del radio; una entrada real sólo presenta
  nombre, sufijo de UUID y estado conectado, encontrado en la última búsqueda
  o guardado en este Mac.

### Espaciado, color e iconos

- Encabezado, scroll y pie permanecen fijos y usan la paleta nativa de Estrobo.
- El estado vacío conserva un foco central claro y suficiente separación del
  aviso de privacidad del pie.
- Se usan SF Symbols para biblioteca, descubrimiento, conexión y eliminación;
  no hay placeholders ni ilustraciones aproximadas.
- No hay texto cortado o superpuesto en las dimensiones evaluadas.

## Validación de interacción

- El primer inicio muestra **0 grupos de trabajo**, explica que Estrobo no elige
  grupos por la persona y mantiene **Guardar y continuar** deshabilitado.
- **Elegir grupos** abre la selección con todos los grupos desmarcados; cambiar
  la compatibilidad tampoco inserta B/C ni el primer grupo automáticamente.
- Una configuración guardada sí restaura sus grupos y modelos, incluso si la app
  se cerró mientras esa configuración se estaba revisando.
- El engrane abre Configuración y expone por separado compatibilidad y biblioteca.
- **Transmisores guardados…** abre la hoja plural y **Listo** regresa a Configuración.
- El flujo principal resume 1/N transmisores y abre la misma biblioteca; ya no
  elige ni olvida un registro singleton ocultando los demás.
- **Olvidar** se deshabilita durante escaneo, autenticación, Sync, writes, Test o
  recuperación. Al habilitarse, muestra una confirmación destructiva y opera por
  UUID sin borrar las otras entradas.
- VoiceOver recibe etiqueta por transmisor para la acción **Olvidar**; el vacío
  combina título e instrucción en un solo elemento legible.

## Comprobaciones técnicas

- `make mac-prototype-check`: aprobado con warnings tratados como errores.
- `make mac-prototype-test`: aprobado; cubre persistencia plural, migración v1,
  upsert por UUID, primera apertura vacía, reanudación del onboarding, selección
  y código correctos, bloqueo durante escaneo, olvido individual, localización
  ES/EN y contratos de UI.
- `make mac-prototype-universal`: aprobado para `arm64` y `x86_64`.
- La migración falla cerrado ante bytes inválidos y reintenta retirar el registro
  legado antes de permitir un borrado total, evitando que un código olvidado
  reaparezca.
- No se usaron credenciales, Bluetooth real ni transmisores personales durante QA.

No quedan diferencias P0, P1 o P2 respecto al objetivo funcional y visual.

final result: passed
