---
name: "Estrobo iOS"
description: "Control local de transmisores compatibles en una interfaz nativa para iPhone y iPad."
colors:
  amber: "#FFAB17"
  accent-light: "#9A5500"
  accent-dark: "#FFAB17"
  deep-navy: "#09223F"
  ivory-light: "#F7F4EE"
  ivory-dark: "#0E161F"
  surface-light: "#FFFEF9"
  surface-dark: "#15202B"
  ink-dark: "#F2F5F9"
  group-a: "#D92D20"
  group-b: "#32D74B"
  group-c: "#2F3AE0"
  group-d: "#21D4D8"
  group-e: "#C61BCC"
  group-f: "#E6E600"
  group-0: "#E85D0F"
  group-1: "#19B977"
  group-2: "#7424D8"
  group-3: "#D81768"
  group-4: "#C9A8EA"
  group-5: "#24D6BC"
  group-6: "#168FDB"
  group-7: "#B9EC98"
  group-8: "#EE777B"
  group-9: "#F3B373"
typography:
  display:
    fontFamily: "SF Pro Display, -apple-system, BlinkMacSystemFont, sans-serif"
    fontSize: "34pt"
    fontWeight: 700
  headline:
    fontFamily: "SF Pro Text, -apple-system, BlinkMacSystemFont, sans-serif"
    fontSize: "17pt"
    fontWeight: 600
  body:
    fontFamily: "SF Pro Text, -apple-system, BlinkMacSystemFont, sans-serif"
    fontSize: "17pt"
    fontWeight: 400
  subheadline:
    fontFamily: "SF Pro Text, -apple-system, BlinkMacSystemFont, sans-serif"
    fontSize: "15pt"
    fontWeight: 400
  caption:
    fontFamily: "SF Pro Text, -apple-system, BlinkMacSystemFont, sans-serif"
    fontSize: "12pt"
    fontWeight: 400
rounded:
  group-badge: "10pt"
spacing:
  compact: "4pt"
  small: "8pt"
  medium: "12pt"
  standard: "16pt"
  wide: "20pt"
components:
  screen-background-light:
    backgroundColor: "{colors.ivory-light}"
    textColor: "{colors.deep-navy}"
  screen-background-dark:
    backgroundColor: "{colors.ivory-dark}"
    textColor: "{colors.ink-dark}"
  demo-banner:
    backgroundColor: "{colors.amber}"
    textColor: "{colors.deep-navy}"
    typography: "{typography.subheadline}"
    height: "36pt"
    padding: "0 16pt"
  group-badge:
    typography: "{typography.headline}"
    rounded: "{rounded.group-badge}"
    size: "36pt"
  deliberate-action:
    backgroundColor: "{colors.amber}"
    textColor: "{colors.deep-navy}"
    typography: "{typography.body}"
    height: "44pt"
---

# Design System: Estrobo iOS

## Overview

**Creative North Star: "La mesa de luz nativa"**

Estrobo se siente como una herramienta iOS de trabajo: directa, legible y gobernada por los componentes que una persona ya reconoce en iPhone y iPad. El ámbar, el navy profundo y las superficies marfil aportan identidad sin competir con la navegación, los controles ni los estados operativos.

La interfaz no intenta copiar la aplicación de macOS ni convertir el control físico en un tablero web. SwiftUI, las barras del sistema, las listas agrupadas, los formularios, las hojas y SF Symbols forman la estructura; la marca aparece en el tinte adaptativo, el banner Demo, los botones deliberados y las letras coloreadas de grupo.

**Key Characteristics:**

- Nativa y funcional, con navegación, controles y materiales del sistema.
- Cálida en claro y profunda en oscuro, con ámbar reservado para identidad y acción deliberada.
- Adaptable entre iPhone compacto e iPad regular sin perder jerarquía ni contexto.
- Explícita por texto: conexión, entrega, simulación, confirmación y error nunca dependen sólo del color.
- Segura y accesible: Dynamic Type, VoiceOver, targets táctiles y confirmaciones antes de Test o Multi.

## Colors

La paleta combina el ámbar de Estrobo con navy profundo y fondos marfil; cada apariencia conserva la misma jerarquía, pero usa valores adaptativos para contraste y legibilidad.

### Primary

- **Ámbar Estrobo:** identifica Demo, Test y momentos deliberados que deben llamar la atención sin parecer destructivos.
- **Acento adaptativo:** usa ámbar bruñido en claro y el ámbar de marca en oscuro para tintes, selección, enlaces y acciones estándar del sistema.

### Neutral

- **Navy profundo:** texto de marca sobre ámbar y tinta principal de la apariencia clara.
- **Marfil adaptativo:** fondo continuo de listas y workspaces; es cálido en claro y casi navy en oscuro.
- **Superficie adaptativa:** eleva secciones, formularios y filas por contraste tonal, sin añadir tarjetas decorativas.
- **Tinta clara de oscuro:** mantiene titulares, valores y etiquetas legibles sobre las superficies profundas.

### Group Identity

Cada grupo conserva una identidad de color estable —A–F y 0–9— dentro de una insignia de 36 × 36 pt. La letra visible y el nombre accesible son siempre la fuente primaria de identidad; el color sólo acelera el reconocimiento. Las identidades normativas viven en los tokens `group-a` a `group-f` y `group-0` a `group-9`.

### Named Rules

**The Amber Intent Rule.** El ámbar se reserva para marca, simulación y acciones físicas deliberadas; no colorea indiscriminadamente toda la interfaz.

**The Text Before Color Rule.** Todo estado operativo conserva una etiqueta textual o un símbolo con nombre accesible; verde, naranja, azul y rojo sólo refuerzan esa lectura.

## Typography

**Display Font:** SF Pro Display, mediante estilos semánticos de SwiftUI

**Body Font:** SF Pro Text, mediante estilos semánticos de SwiftUI

**Character:** La tipografía es la del sistema: compacta, familiar y sin una capa ornamental. Jerarquía, peso y escala siguen Dynamic Type; las cifras de potencia, frecuencia, conteo y UUID usan dígitos monoespaciados cuando la comparación visual importa.

### Hierarchy

- **Display** (`largeTitle`, bold): títulos principales como Estrobo, Grupos y Global en la raíz de navegación.
- **Headline** (`headline`): nombres de grupo, valores centrales y títulos de filas relevantes.
- **Title** (`title3`, bold): potencia en el detalle de grupo y valores operativos de primer nivel.
- **Body** (`body`): copy funcional, valores de listas, botones y controles.
- **Subheadline** (`subheadline`, con bold sólo para estado): datos secundarios y estados compactos.
- **Caption** (`caption`, con bold sólo para confirmación): evidencia de entrega, UUID abreviado y notas operativas.

### Named Rules

**The Semantic Type Rule.** Usa estilos de texto de SwiftUI, no tamaños fijos; todo texto debe crecer con Dynamic Type y recomponer la interfaz antes de truncarse.

**The Numeric Stability Rule.** Potencia, conteos, frecuencia y sufijos UUID usan dígitos monoespaciados sin convertir el resto de la interfaz en tipografía técnica.

## Layout

La estructura sigue safe areas y navegación del sistema. En iPhone, un `TabView` contiene cuatro secciones superiores —Grupos, Global, Presets y Ajustes— y cada una mantiene su propio `NavigationStack`. Conexión aparece como tarea contextual desde la barra de sesión, no como una quinta pestaña.

En iPad con ancho regular, un `NavigationSplitView` presenta sidebar y workspace. Sólo Grupos abre una tercera columna de inspector: la lista de grupos ocupa el contenido y el detalle seleccionado ocupa el inspector. Conexión, Global y Multi, Presets, Transmisores guardados, Ajustes y DemoLab usan sidebar más un único workspace. Cuando iPad entra en ancho compacto, adopta la estructura de iPhone en lugar de comprimir tres columnas.

Las pantallas operativas usan `List` o `Form`, secciones del sistema y el ritmo de 4, 8, 12, 16 y 20 pt ya presente. Las acciones táctiles tienen al menos 44 × 44 pt. La barra Aplicar/Descartar queda anclada al borde inferior mediante safe-area inset y se recompone en dos filas cuando Dynamic Type entra en tamaños de accesibilidad.

**The Inspector Scope Rule.** El inspector de iPad pertenece exclusivamente a Grupos; las demás secciones no dejan una columna vacía ni inventan un panel lateral.

**The Compact Collapse Rule.** Un iPad compacto usa el patrón completo de iPhone; el cambio responde a size class, no a un breakpoint fijo en píxeles.

## Elevation & Depth

No hay sombras personalizadas. La profundidad proviene de fondos tonales, barras con material del sistema, separación de listas, navegación y hojas nativas. Las sheets de Conexión, confirmación, edición y borrado conservan la elevación, los detents y las transiciones de iOS; el contenido no simula vidrio ni apila tarjetas flotantes.

### Named Rules

**The System Depth Rule.** Deja que barras, listas, sheets y split views comuniquen jerarquía; no añadas sombras o blur decorativo a superficies en reposo.

## Shapes

La forma es principalmente la que proporciona iOS: filas, secciones, botones prominentes, segmented controls, toggles, steppers, menús y sheets mantienen sus contornos adaptativos. La firma propia es la insignia de grupo: cuadrado de 36 pt con esquinas continuas de 10 pt y una letra centrada. El banner Demo es una franja de borde a borde; no es una tarjeta.

**The Native Control Shape Rule.** No congeles radios para imitar capturas; conserva la geometría y los estados que SwiftUI adapta por plataforma, tamaño de texto y contexto.

## Components

### Navigation

- **iPhone:** cuatro tabs con SF Symbols, etiqueta visible y `NavigationStack` independiente; los destinos jerárquicos usan push y conservan el gesto de regreso.
- **iPad:** sidebar con SF Symbols y estado seleccionado textual/semántico; Grupos usa sidebar, lista y detalle, mientras el resto usa sidebar y workspace.
- **Titles:** títulos grandes en raíces y título inline en el detalle de grupo.
- **Sheets:** Conexión y confirmaciones son tareas autocontenidas con Cancelar/Cerrar y detents del sistema.

### Demo Banner

- **Style:** franja ámbar de borde a borde, navy profundo, icono waveform, copy en mayúsculas y dispositivo al extremo opuesto.
- **Behavior:** permanece visible durante toda la sesión simulada, tanto en onboarding como en iPhone e iPad.
- **Meaning:** siempre declara que no hay comandos físicos; Demo nunca se disfraza de sesión real.

### Group Badges and Rows

- **Badge:** letra o número visible, color estable por grupo, contraste de primer plano definido por identidad y nombre accesible “Grupo X”.
- **Row:** insignia, modo y potencia, más confirmación textual (`PENDIENTE`, `WRITE OK`, `FEC8`, `ERROR` o raya sin lectura).
- **Detail:** modo mediante segmented control, potencia con botones de 44 pt y valor central, modelado mediante picker del sistema.

### Status and Delivery

- **Session:** el toolbar muestra estado textual como Sin conexión, Ready, Aplicando o Error, reforzado por un punto o color semántico.
- **Apply Bar:** estado pendiente a la izquierda y Descartar/Aplicar a la derecha; en Dynamic Type de accesibilidad, el estado sube a su propia fila.
- **Automatic / With Button:** segmented control con explicación persistente de debounce o acumulación manual.

### Deliberate Test and Multi

- **Test:** el botón ámbar “Preparar Test” abre una sheet de confirmación; una segunda acción “Enviar Test” es necesaria antes de operar equipo. Mientras entrega, muestra `PENDIENTE`; al terminar, distingue simulado, entregado o fallido mediante texto y símbolo.
- **Multi:** se activa globalmente y nunca desde el selector de modo de un grupo. La confirmación enumera qué grupos entran, permanecen, pasan a Off o vuelven a Manual antes de aplicar.
- **Safety:** los textos explican el entorno ópticamente seguro y que Bluetooth no confirma el resultado visual.

### Forms and Controls

- **Style:** `List`, `Form`, `Section`, `Picker`, `Toggle`, `Stepper`, `TextField`, `Menu`, `LabeledContent`, `ContentUnavailableView` y botones del sistema.
- **Touch:** controles y acciones sostienen un mínimo de 44 × 44 pt.
- **Icons:** sólo SF Symbols, alineados por el sistema y ocultos a VoiceOver cuando son redundantes.
- **States:** disabled, focus, destructive y selection conservan semántica nativa; las explicaciones permanecen visibles en headers, footers o texto secundario.

### Localization and Accessibility

- **Languages:** español e inglés tienen el mismo inventario de claves y son idiomas de primera clase.
- **Appearance:** Sistema, Claro y Oscuro se pueden elegir sin cambiar la estructura ni perder estado.
- **VoiceOver:** labels, values, selected traits e identificadores describen grupos, controles, conexión y resultados físicos.
- **Dynamic Type:** estilos semánticos y recomposición explícita de la barra inferior evitan depender de una escala fija.

## Do's and Don'ts

### Do:

- **Do** usa componentes SwiftUI, SF Symbols, safe areas y transiciones del sistema como base de cada pantalla.
- **Do** conserva el banner Demo durante toda sesión simulada y declara explícitamente que no envía comandos físicos.
- **Do** identifica cada grupo con letra o número, color estable, texto de estado y nombre accesible.
- **Do** mantiene Test y Multi como acciones deliberadas con confirmación, copy de seguridad y resultado textual.
- **Do** valida cada cambio en español e inglés, claro y oscuro, iPhone e iPad, Dynamic Type y VoiceOver.
- **Do** deja el inspector de iPad sólo en Grupos y colapsa a la navegación de iPhone en ancho compacto.

### Don't:

- **Don't** sustituyas tabs, navigation stacks, split views, sheets, listas o formularios por navegación dibujada a mano.
- **Don't** uses color como única evidencia de pendiente, entrega, error, selección, simulación o conexión.
- **Don't** conviertas Demo en un estado silencioso ni mezcles sus stores, transporte o datos con el runtime real.
- **Don't** pongas Multi dentro del selector local de modo ni permitas Test con un solo tap desde la pantalla principal.
- **Don't** fijes tamaños de texto, breakpoints en píxeles o radios visuales que impidan las adaptaciones del sistema.
- **Don't** añadas sombras, glassmorphism, iconos web o tarjetas ornamentales a la superficie operativa.
