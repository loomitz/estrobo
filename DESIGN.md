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
- Segura y accesible: Dynamic Type, VoiceOver, targets táctiles y gates visibles para Test, Beep, Modelado, Multi y Standby; las acciones son directas y sus efectos permanecen explícitos sin confirmaciones modales.

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

- **Display** (`largeTitle`, bold): títulos principales como Estrobo, Presets y Ajustes cuando la raíz necesita nombrarse. Grupos omite el título grande porque la tab activa, el estado de sesión y el contenido ya fijan el contexto.
- **Headline** (`headline`): nombres de grupo, valores centrales y títulos de filas relevantes.
- **Title** (`title3`, bold): potencia inline en Grupos y valores operativos de primer nivel.
- **Body** (`body`): copy funcional, valores de listas, botones y controles.
- **Subheadline** (`subheadline`, con bold sólo para estado): datos secundarios y estados compactos.
- **Caption** (`caption`, con bold sólo para confirmación): evidencia de entrega, UUID abreviado y notas operativas.

### Named Rules

**The Semantic Type Rule.** Usa estilos de texto de SwiftUI, no tamaños fijos; todo texto debe crecer con Dynamic Type y recomponer la interfaz antes de truncarse.

**The Numeric Stability Rule.** Potencia, conteos, frecuencia y sufijos UUID usan dígitos monoespaciados sin convertir el resto de la interfaz en tipografía técnica.

## Layout

La estructura sigue safe areas y navegación del sistema. En iPhone, un `TabView` contiene exactamente tres secciones superiores —Grupos, Presets y Ajustes— y cada una mantiene su propio `NavigationStack`. Conexión aparece como tarea contextual desde la barra de sesión; Control global vive dentro de Grupos y no constituye una pestaña adicional.

En iPad con ancho regular, un `NavigationSplitView` presenta sidebar y workspace. Sólo Grupos abre una tercera columna de inspector: la lista de grupos ocupa el contenido y el detalle seleccionado ocupa el inspector. Conexión, Presets, Transmisores guardados, Ajustes y DemoLab usan sidebar más un único workspace; no existe un destino Global separado. Cuando iPad entra en ancho compacto, adopta las tres secciones de iPhone en lugar de comprimir tres columnas.

Las pantallas operativas usan `List` o `Form`, secciones del sistema y el ritmo de 4, 8, 12, 16 y 20 pt ya presente. Las acciones táctiles tienen al menos 44 × 44 pt. Grupos conserva una barra contextual anclada al borde inferior mediante safe-area inset: en Automática aparece de forma sutil sólo mientras existe un debounce o I/O real y desaparece inmediatamente al volver a reposo, sin un estado fugaz de “Actualizado”; en Con botón muestra pendientes y ofrece Descartar/Aplicar cuando corresponde. La barra se recompone en dos filas cuando Dynamic Type entra en tamaños de accesibilidad y nunca contiene el selector del modo de entrega.

**The Inspector Scope Rule.** El inspector de iPad pertenece exclusivamente a Grupos; las demás secciones no dejan una columna vacía ni inventan un panel lateral.

**The Compact Collapse Rule.** Un iPad compacto usa el patrón completo de iPhone; el cambio responde a size class, no a un breakpoint fijo en píxeles.

## Elevation & Depth

No hay sombras personalizadas. La profundidad proviene de fondos tonales, barras con material del sistema, separación de listas, navegación y hojas nativas. Las sheets de Conexión, edición y borrado conservan la elevación, los detents y las transiciones de iOS; el contenido no simula vidrio ni apila tarjetas flotantes.

### Named Rules

**The System Depth Rule.** Deja que barras, listas, sheets y split views comuniquen jerarquía; no añadas sombras o blur decorativo a superficies en reposo.

## Shapes

La forma es principalmente la que proporciona iOS: filas, secciones, botones prominentes, segmented controls, toggles, steppers, menús y sheets mantienen sus contornos adaptativos. La firma propia es la insignia de grupo: cuadrado de 36 pt con esquinas continuas de 10 pt y una letra centrada. El banner Demo es una franja de borde a borde; no es una tarjeta.

**The Native Control Shape Rule.** No congeles radios para imitar capturas; conserva la geometría y los estados que SwiftUI adapta por plataforma, tamaño de texto y contexto.

## Components

### Navigation

- **iPhone:** exactamente tres tabs —Grupos, Presets y Ajustes— con SF Symbols, etiqueta visible y `NavigationStack` independiente; los destinos jerárquicos usan push y conservan el gesto de regreso.
- **iPad:** sidebar con SF Symbols y estado seleccionado textual/semántico; Grupos usa sidebar, lista y detalle, mientras el resto usa sidebar y workspace. Global no aparece como destino independiente.
- **Titles:** el workspace de Grupos no repite un título de pantalla ni headers `Control global`/`Grupos de trabajo`; el bloque comienza con `Control Global` dentro de la propia superficie. El detalle de grupo conserva título inline.
- **Sheets:** Conexión, edición enfocada y acciones destructivas son tareas autocontenidas con Cancelar/Cerrar y detents del sistema. Test, Multi y Standby no abren una sheet.

### Demo Banner

- **Style:** franja ámbar de borde a borde, navy profundo, icono waveform, copy en mayúsculas y dispositivo al extremo opuesto.
- **Behavior:** permanece visible durante toda la sesión simulada, tanto en onboarding como en iPhone e iPad.
- **Meaning:** siempre declara que no hay comandos físicos; Demo nunca se disfraza de sesión real.

### Group Badges and Rows

- **Badge:** letra o número visible, color estable por grupo, contraste de primer plano definido por identidad y nombre accesible “Grupo X”.
- **Row:** es la superficie de ajuste frecuente. Presenta insignia, modo, potencia monoespaciada, confirmación textual (`PENDIENTE`, `WRITE OK`, `FEC8`, `ERROR` o raya sin lectura), botones `−`/`+` de al menos 44 pt y un slider discreto de 1/3 EV con marcas de regla.
- **Directional limits:** `−` y `+` se deshabilitan de forma independiente al alcanzar su límite físico; el slider y ambos botones se deshabilitan cuando el modo o los gates de sesión impiden editar potencia Manual.
- **Gesture:** el slider muestra cada paso discreto en vivo durante el drag. Los pasos transitorios no se persisten ni se entregan; al soltar, el borrador final se persiste una sola vez y queda disponible para la entrega configurada. Background, desconexión, pérdida de disponibilidad o desaparición de la fila cancelan el gesto sin envío tardío.
- **Navigation:** la fila no es un `NavigationLink` o botón envolvente. Una pulsación larga limitada a su cabecera abre el detalle, mientras el slider y `−`/`+` conservan sus propios gestos. Durante la presión la cabecera recibe un realce tonal; al reconocerse emite un impacto háptico y navega. Reduce Motion elimina la escala y conserva el realce. No hay botón `Detalles` visible; la cabecera expone un hint y una acción personalizada `Detalles` para VoiceOver.
- **Detail:** es avanzado y opcional. Conserva Modo mediante segmented control, añade un slider independiente para la potencia del flash y resume Modelado en tres opciones: Apagado, Proporcional y Manual. Manual revela un segundo slider de intensidad derivado de las capacidades, con mínimo 10%. Nunca es requisito para cambiar la potencia inline.

### Compact Global Control

- **Placement:** Control Global es una sección compacta dentro de Grupos en iPhone e iPad; nunca crea otra pestaña, destino de sidebar o workspace. Su título vive dentro del bloque de potencia y sustituye tanto al header externo como a `Ajuste relativo`.
- **Contents:** reúne potencia relativa y una rejilla 2×2 de tiles para Beep, Modelado, Standby y Multi sin duplicar esos controles en otras raíces de navegación. Cada tile activo usa relleno tonal, borde reforzado, símbolo, texto y trait seleccionado; el estado inactivo conserva superficie neutral, texto explícito y el mismo target mínimo. Dynamic Type accesible colapsa la rejilla a una columna.
- **Modelado:** es un maestro A0-only independiente de los modos A1 por grupo. Apagarlo no cambia Apagado/Proporcional/Manual ni la intensidad almacenada; encenderlo restaura esas elecciones. Un Apply de potencia no lo reactiva, pero una edición local deliberada de Modelado sí lo hace. Sólo el tile muestra `Aplicando…` durante I/O real y nunca una confirmación fugaz posterior.
- **Standby:** su tile mantiene selección inequívoca y, mientras está activo, cada tarjeta normal o participante Multi recibe un overlay de material adaptativo con identidad de grupo, icono `power` y `Apagado por Standby`. El contenido subyacente queda atenuado y deshabilitado; el overlay no borra ajustes ni impide abrir el detalle para consulta.
- **Relative power:** un slider centrado en 0 recorre `−3…+3 EV` en 19 posiciones de 1/3 EV. La regla y el valor firmado comunican el delta, no una potencia absoluta. Durante el drag sólo cambia la presentación; al soltar se aplica una única operación atómica a todos los grupos Manual elegibles, respetando el límite físico común y dejando intactos los grupos deshabilitados. Tras el commit, el slider vuelve visualmente a 0 mientras las potencias absolutas permanecen en sus nuevos valores.
- **Multi:** entra y sale con un toque directo. La consecuencia sobre los grupos permanece como hint accesible sin añadir texto explicativo redundante al bloque; al activarse aparecen participantes y controles rápidos en la misma sección. Mientras Multi está activo se ocultan las tarjetas normales; la identidad de cada participante abre el mismo detalle avanzado con pulsación larga y acción accesible, independiente de su toggle.

### Status and Delivery

- **Session:** el toolbar muestra estado textual como Sin conexión, Ready, Aplicando o Error, reforzado por un punto o color semántico.
- **Context Bar:** se adapta a la preferencia vigente y a la operación actual. En Automática muestra feedback sutil únicamente mientras el debounce está armado o existe I/O en curso; al terminar se oculta sin pasar por `Actualizado`, checkmark ni otro estado de completado fugaz. En Con botón presenta el conteo pendiente y las acciones Descartar/Aplicar sólo cuando son válidas; Beep/Modelado/Standby directos suprimen esa superficie durante toda su operación, mientras Multi conserva Apply cuando la entrega manual fue elegida.
- **Automatic / With Button:** el segmented control y su explicación persistente viven únicamente en Ajustes. Grupos refleja la elección, pero no permite cambiarla desde la lista, el detalle ni la barra contextual.

### Deliberate Test and Multi

- **Test:** el botón ámbar “Test” vive en Grupos y ejecuta directamente con un toque, sin alerta ni sheet de confirmación. Su label, hint y estado dejan claro que la acción es inmediata.
- **Test gates:** sólo se habilita en foreground y Ready, y cuando no hay edición interactiva, cambios pendientes, recuperación, Standby ni otra operación incompatible. Es single-flight: se deshabilita durante la entrega, nunca se encola y nunca se reintenta automáticamente.
- **Test feedback:** mientras entrega muestra `PENDIENTE`; al terminar distingue simulado, entregado o fallido mediante texto y símbolo. “Entregado” describe transporte Bluetooth, no confirmación óptica.
- **Beep, Modelado, Multi y Standby:** sus controles cambian directamente cuando los gates están abiertos, sin confirmación modal ni una celebración de éxito posterior. Multi nunca vive en el selector de modo de un grupo y su texto auxiliar enumera antes del toque qué grupos entran, permanecen, pasan a Off o vuelven a Manual. Los cuatro tiles reflejan su estado estable mediante selección, símbolo y texto; el único feedback transitorio compartido corresponde a debounce o I/O que todavía no termina.
- **Safety:** los textos explican el entorno ópticamente seguro y que Bluetooth no confirma el resultado visual.

### Forms and Controls

- **Style:** `List`, `Form`, `Section`, `Picker`, `Toggle`, `Stepper`, `TextField`, `Menu`, `LabeledContent`, `ContentUnavailableView` y botones del sistema.
- **Touch:** controles y acciones sostienen un mínimo de 44 × 44 pt.
- **Power sliders:** los sliders de grupo y global usan pasos discretos de 1/3 EV, rail y marcas de regla. El de grupo representa potencia absoluta y sigue cada paso en vivo; el global representa un delta `−3…+3 EV`, hace commit sólo al final y vuelve visualmente a 0. Los botones laterales del grupo ofrecen el mismo incremento y límites direccionales correctos.
- **Multi scrubbers:** Destellos usa sus enteros permitidos. Frecuencia usa 41 posiciones exactas: `1…20`, `25…50` cada 5, `60…190` cada 10 y `199`. Ambos muestran valor grande monoespaciado, rail, marcas de regla y extremos visibles, sin botones `−`/`+`. Un token de edición conserva los pasos intermedios sólo en presentación; persistencia y entrega se arman al soltar. La UI nunca inventa respaldo de fabricante para frecuencias fuera de la tabla disponible.
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
- **Do** identifica cada grupo con letra o número, color estable, texto de estado, nombre accesible y control de potencia inline.
- **Do** concentra potencia relativa, Beep, Modelado, Standby y Multi en Control global dentro de Grupos, sin otra raíz de navegación.
- **Do** presenta potencia global como un delta con regla, commit final-only y retorno visual a 0; abre Detalles mediante pulsación larga con respuesta visual/háptica y una acción accesible equivalente tanto en filas normales como entre participantes Multi.
- **Do** mantiene Test como acción directa gated y single-flight, y Beep, Modelado, Multi y Standby como controles globales directos; conserva copy de seguridad, consecuencia y resultado textual sin interrumpir con una confirmación.
- **Do** mantiene Automática/Con botón exclusivamente en Ajustes y deja que la barra contextual comunique su efecto en Grupos.
- **Do** valida cada cambio en español e inglés, claro y oscuro, iPhone e iPad, Dynamic Type y VoiceOver.
- **Do** deja el inspector de iPad sólo en Grupos y colapsa a la navegación de iPhone en ancho compacto.

### Don't:

- **Don't** sustituyas tabs, navigation stacks, split views, sheets, listas o formularios por navegación dibujada a mano.
- **Don't** uses color como única evidencia de pendiente, entrega, error, selección, simulación o conexión.
- **Don't** conviertas Demo en un estado silencioso ni mezcles sus stores, transporte o datos con el runtime real.
- **Don't** pongas Multi dentro del selector local de modo, añadas confirmaciones a Test/Beep/Multi/Standby ni ocultes las consecuencias globales de Multi.
- **Don't** añadas una pestaña o destino Global separado ni disperses sus controles fuera de la sección compacta de Grupos.
- **Don't** escondas el ajuste cotidiano de potencia únicamente dentro del detalle, hagas que el long press compita con sliders o `−`/`+`, ni muestres el selector Automática/Con botón fuera de Ajustes.
- **Don't** persistas o envíes cada paso transitorio del slider; sólo el borrador final se persiste una vez al terminar el gesto.
- **Don't** muestres `Actualizado` ni otro estado de completado fugaz después de Beep, Modelado, Standby o Multi; el indicador automático sólo existe durante debounce o I/O real.
- **Don't** habilites Test si alguno de sus gates está cerrado, permitas dos entregas simultáneas o añadas reintentos automáticos.
- **Don't** fijes tamaños de texto, breakpoints en píxeles o radios visuales que impidan las adaptaciones del sistema.
- **Don't** añadas sombras, glassmorphism, iconos web o tarjetas ornamentales a la superficie operativa.
