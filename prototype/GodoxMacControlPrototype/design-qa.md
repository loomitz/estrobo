# Design QA — Configuración unificada del espacio de trabajo

## Objetivo

- Reunir perfil del transmisor, grupos de trabajo y modelos de flash en un solo editor.
- Retirar `Vista inicial` de este flujo; permanece únicamente en Configuración.
- Añadir grupos desde el catálogo mediante un modal con selección múltiple.
- Permitir administrar perfiles incluidos: elegir el predeterminado, ocultar los no usados y restaurarlos.

## Verdad visual

Las referencias conceptuales se conservan dentro de las comparaciones públicas
de `QA/`; no dependen de rutas privadas ni de archivos externos al repositorio.

Implementación:

- Código principal: `Sources/PrototypeViews.swift`
- Preferencias de perfiles: `Sources/TransmitterProfilePreferences.swift`
- Bundle evaluado: build local reproducible de `estrobo.app`

## Estado y dimensiones

- Estado: onboarding, español, tema claro, perfil GDBH predeterminado, grupos B/C, B seleccionado y un modelo asignado.
- Ventana evaluada: 1180 × 820 pt en pantalla Retina.
- Vista unificada: 2496 × 1776 px, incluida la sombra nativa de la ventana.
- Modal Añadir grupos: 2360 × 1640 px.
- Modal Administrar perfiles inicial: 2496 × 1776 px.
- Referencias ImageGen: 1586 × 992 px para editor y grupos; 1503 × 1047 px para perfiles.

## Evidencia conjunta

Las comparaciones colocan a la izquierda la referencia ImageGen y a la derecha el bundle SwiftUI, conservando cada vista completa:

- Editor: `QA/workspace-configuration-comparison.png`
- Añadir grupos con D/E seleccionados: `QA/workspace-configuration-add-groups-comparison.png`
- Administrar perfiles: `QA/workspace-configuration-manage-profiles-comparison.png`

Capturas individuales finales:

- `QA/workspace-configuration-unified-light-es.png`
- `QA/workspace-configuration-add-groups-light-es.png`
- `QA/workspace-configuration-add-groups-selected-light-es.png`
- `QA/workspace-configuration-manage-profiles-light-es.png`
- `QA/workspace-configuration-manage-profiles-default-switched-light-es.png`

## Comparación visual

### Tipografía

- Se conserva la tipografía de sistema de macOS y la jerarquía de Estrobo: título principal, subtítulo, etiquetas en versales y texto secundario.
- No hay textos cortados ni superpuestos en 1180 × 820 pt.

### Espaciado y estructura

- El perfil funciona como barra superior del mismo panel; grupos y modelos comparten un cuerpo maestro–detalle.
- Los modales mantienen encabezado, contenido y pie fijos, con márgenes y radios coherentes con el diseño existente.
- La implementación añade el encabezado global de marca, idioma y apariencia porque forma parte del shell real de Estrobo.

### Color y componentes

- Azul marino para acciones primarias, naranja para selección y verde para estados válidos.
- Se preserva la paleta canónica de cada grupo, aunque varíe respecto a los colores exploratorios de ImageGen.
- Las filas, bordes, divisores, fondo atenuado y estados deshabilitados mantienen contraste y jerarquía correctos.

### Iconos

- Se usan SF Symbols y los recursos reales de marca del proyecto; no hay dibujos aproximados ni placeholders.
- En perfiles, el símbolo de radio sustituye deliberadamente la ilustración conceptual del dispositivo para integrarse con el lenguaje nativo actual.

### Contenido

- `Vista inicial` no aparece en la configuración del espacio de trabajo.
- El editor muestra perfil, estado predeterminado, grupos, conteos, rango seguro, búsqueda, modelos y eliminación del grupo activo.
- El modal de grupos expresa correctamente `0 grupos seleccionados`, el singular y el plural; la acción refleja el conteo.
- El administrador diferencia `En uso` de `Predeterminado` y explica por qué no se puede quitar el perfil activo.
- `Quitar` oculta el perfil sólo en este Mac y `Restaurar perfiles incluidos` revierte esa decisión.

## Validación de interacción

- `Añadir grupo` abre el modal.
- Con cero selecciones, el CTA permanece deshabilitado.
- Seleccionar D y E muestra ambos checks, actualiza el contador a 2 y habilita `Añadir 2 grupos`.
- Escape cierra el modal sin alterar los grupos del editor.
- `Administrar perfiles…` abre el administrador.
- GDBH aparece `En uso` y inicialmente `Predeterminado`; no puede quitarse mientras lo use el espacio actual.
- Godox ofrece `Usar como predeterminado` y `Quitar`.
- Al elegir Godox como predeterminado, el badge cambia de fila correctamente sin cambiar el perfil activo.
- La acción para restaurar perfiles incluidos permanece disponible.

## Correcciones durante QA

1. El CTA final del editor y los CTA de ambos modales se alinearon con el azul marino de las referencias.
2. El resumen del modal cambió de conteo genérico de grupos de trabajo a selección explícita con formas `0/1/N`.
3. Se verificó que la vista inicial sólo quede en Configuración y no vuelva a aparecer en este flujo.

## Comprobaciones técnicas

- `make mac-prototype-check`: aprobado con warnings tratados como errores.
- `make mac-prototype-test`: aprobado; incluye preferencias de perfiles, recuperación de sesión sin Bluetooth real, persistencia, localización ES/EN y recursos de marca.
- No se usaron credenciales, Bluetooth real ni `UserDefaults` reales durante las pruebas de transporte simulado.

No quedan diferencias P0, P1 o P2 respecto al objetivo funcional y visual. Las diferencias visibles restantes corresponden al shell real de Estrobo, a sus colores de grupo y a controles nativos deliberados.

final result: passed
