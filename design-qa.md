# Design QA — Multi global

Fecha: 2026-08-06

## Evidencia

- Verdad visual: referencia conceptual incluida a la izquierda en la comparación versionada.
- Build revisado: `prototype/GodoxMacControlPrototype/Build/estrobo.app --mock-radio`
- Captura final: [`prototype/GodoxMacControlPrototype/QA/multi-global-final.jpeg`](prototype/GodoxMacControlPrototype/QA/multi-global-final.jpeg)
- Comparación lado a lado: [`prototype/GodoxMacControlPrototype/QA/multi-global-comparison.png`](prototype/GodoxMacControlPrototype/QA/multi-global-comparison.png)
- Referencia: 1487 × 1058 px.
- Implementación: ventana nativa macOS de 967 × 768 px, captura a la densidad entregada por el sistema.
- Normalización: ambas imágenes se ajustaron sin recorte dentro de áreas de 1080 × 720 px y se centraron sobre el mismo fondo; comparación final de 2160 × 720 px.
- Estado final: tema oscuro, español, radio simulado conectado, Multi activo, grupo B incluido y grupo C desactivado con overlay.

## Comparación de vista completa

- La composición conserva el patrón elegido: botón MULTI junto a Beep, consola global horizontal y grupos debajo.
- La consola contiene potencia, destellos, frecuencia, obturación mínima y participantes sin dropdown, popover, recortes ni solapamientos.
- La diferencia respecto a la referencia en los controles de modo por grupo es intencional y responde a la revisión posterior: Multi ya no aparece como opción local.
- El grupo excluido mantiene su lugar en la cuadrícula, queda visualmente atenuado y recibe una tarjeta central con icono, explicación y acción para añadirlo a Multi.

## Comparación enfocada

No fue necesaria una segunda imagen recortada: en la comparación normalizada se leen con claridad el botón MULTI, la consola, `MULTI · GLOBAL`, el overlay `GRUPO C DESACTIVADO` y su acción. La jerarquía, los estados y los controles críticos ocupan más de la mitad superior de cada panel.

## Superficies de fidelidad

- Tipografía: conserva la jerarquía monoespaciada/técnica del producto, pesos legibles y etiquetas compactas sin truncamiento relevante.
- Espaciado y ritmo: la consola sigue la cuadrícula del encabezado y el overlay queda centrado sin empujar ni cambiar el tamaño de la tarjeta del grupo.
- Colores y tokens: el ámbar sigue identificando Multi; el grupo excluido usa opacidad y una superficie oscura de contraste suficiente sin confundirse con un error.
- Imágenes e iconos: se reutilizan los assets de marca y símbolos nativos existentes; no hay placeholders ni sustitutos dibujados a mano.
- Copy: la vista explica que el grupo está fuera de la secuencia y que el botón MULTI es la salida global; la app quedó alineada al idioma español de la referencia.
- Accesibilidad: el overlay expone `GRUPO C DESACTIVADO` y `Activar grupo C en Multi`; el último participante queda deshabilitado y comunica que debe apagarse Multi desde el botón global.

## Interacciones verificadas

- Estado inicial: panel oculto, botón `Activar Multi`, B y C activos en Manual.
- Se apagó C y se activó Multi desde el botón global: B pasó a Multi y C apareció con overlay desactivado.
- Se añadió C desde el overlay y ambos grupos quedaron en Multi.
- Se retiró B desde la consola: B recibió el overlay y C quedó como último participante no removible.
- Se desactivó Multi desde el botón global: el panel desapareció y B y C volvieron activos en Manual.
- Se reactivó Multi y se dejó B incluido/C excluido para la captura final.

## Historial de comparación

1. Primera captura: la implementación estaba en inglés mientras la referencia estaba en español. Hallazgo P2 de fidelidad de estado/copy.
2. Corrección: se cambió la preferencia local a español y se recapturó el mismo estado y ventana.
3. Comparación posterior: no quedan hallazgos P0, P1 o P2. La densidad menor de la implementación proviene del viewport nativo más estrecho y conserva la jerarquía sin pérdida funcional.

## Hallazgos

No quedan diferencias visuales o funcionales P0, P1 o P2. No se observaron recortes, controles inaccesibles, texto roto, contraste insuficiente ni recursos visuales faltantes.

## Seguimiento opcional

- P3: en una ventana mucho más ancha podría aumentarse ligeramente la separación entre controles de la consola, sin cambiar el comportamiento ni la jerarquía actual.

final result: passed
