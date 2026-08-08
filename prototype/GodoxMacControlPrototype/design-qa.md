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
