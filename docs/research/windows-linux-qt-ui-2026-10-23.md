# Qt Widgets frente a Qt Quick/QML para Estrobo

Consulta: 23 de octubre de 2026. Referencia de paridad: `bf98e82637b562fff732ca82d7a92a66fe984d66`. Destinos aprobados: Windows 11 x64 y Ubuntu 24.04 LTS x64 con GNOME Wayland/X11. Se conservan las apps Apple; Qt controla el proceso Swift que conserva la política de sesión y recuperación.

**La elección de Qt/C++ no elige automáticamente Widgets.** Qt Quick usa QML, un lenguaje declarativo de interfaz, y admite integración y modelos C++; puede coexistir con ese host sin trasladar el motor Swift a JavaScript. Ambas alternativas requieren reconstruir las vistas SwiftUI. Esta investigación usa documentación **Qt 6.8**, la familia ya probada para QtCore; **no fija la versión productiva ni acredita una UI ensayada**. [Tecnologías de UI Qt](https://doc.qt.io/qt-6.8/topics-ui.html), [Qt Quick y API C++](https://doc.qt.io/qt-6.8/qtquick-index.html)

## Comparación aplicada

Las ventajas de productividad siguientes son inferencias de adecuación, no resultados de un prototipo Estrobo.

| Aspecto | Qt Widgets | Qt Quick + Quick Controls |
| --- | --- | --- |
| **Canales, Inspector y Matriz** | Enfoque maduro para escritorio complejo, formularios y model/view. Es una base directa para divisores, inspector y edición tabular; una presentación muy personalizada exige estilos/delegados propios. | Listas, tablas, layouts y delegados permiten componer tarjetas y matriz con más control visual declarativo. La documentación compara su model/view con el más completo de Widgets; no debe suponerse que una tabla personalizada ya tenga toda la navegación/edición requerida. [Comparación Qt](https://doc.qt.io/qt-6.8/topics-ui.html) |
| **Sliders, modelado y Multi** | Controles estándar y señales C++; encaja con formularios y ajustes discretos. Los controles visuales especiales necesitan composición o pintura propia. | Bindings y componentes QML favorecen controles adaptables y estados visuales próximos al lenguaje de SwiftUI. Esto es semejanza conceptual, sin compartir código de vistas. Quick Controls aporta los controles comunes. [UI Qt](https://doc.qt.io/qt-6.8/topics-ui.html) |
| **Estilo y apariencia** | Estilos del toolkit y personalización; puede priorizar convenciones de escritorio. “Aspecto nativo” no implica que cada control sea un objeto nativo del sistema. | Estilos seleccionables y componentes personalizables. FluentWinUI3 existe desde 6.8 y puede ejecutarse en Linux, pero no es nativo y varios controles usan fallback Fusion; no debe convertirse en promesa de paridad visual automática. [Estilos Quick](https://doc.qt.io/qt-6.8/qtquickcontrols-styles.html), [FluentWinUI3](https://doc.qt.io/qt-6.8/qtquickcontrols-fluentwinui3.html) |
| **Diálogos** | Dialogs/widgets y composición C++; deben comprobarse orden de botones, foco, Enter/Esc, retorno a la vista y cierre seguro. | Quick Controls y Qt Quick Dialogs permiten diálogos. La implementación nativa o Qt depende del diálogo y plataforma; no garantiza apariencia/comportamiento idénticos Windows/GNOME. [Qt Quick Dialogs](https://doc.qt.io/qt-6.8/qtquickdialogs-index.html) |
| **Arquitectura y mantenimiento** | Presentación C++ y herramientas de Widgets; menos tecnologías de UI para aprender. | C++ conserva integración/modelos; QML añade componentes declarativos y herramientas propias. No obliga a implementar dominio o IPC en QML. [Modelos C++ en Quick](https://doc.qt.io/qt-6.8/qtquick-modelviewsdata-cppmodels.html) |

Para ambos, cambios procedentes del motor sólo actualizan presentación: **no deben volver a disparar comandos físicos**. Sliders necesitan distinguir edición local, commit/cancelación y confirmación; Multi y límites por modelo permanecen gobernados por Swift. Las tres vistas y el panel deben compartir el mismo modelo de presentación y sesión.

## Teclado, accesibilidad e idiomas

Qt proporciona interfaces accesibles para **Widgets y Quick Controls** estándar; personalizar controles exige conservar o ampliar sus metadatos y acciones. Quick ofrece `Accessible.name`, `description`, `role` y acciones accesibles. El soporte de toolkit no demuestra que Estrobo funcione correctamente con lectores de pantalla en ambos sistemas. [Widgets accesibles](https://doc.qt.io/qt-6.8/accessible-qwidget.html), [Quick accesible](https://doc.qt.io/qt-6.8/accessible-qtquick.html)

Widgets permite definir explícitamente el orden Tab/Shift+Tab; Quick Controls ya incorpora comportamiento de teclado en controles comunes, pero las composiciones personalizadas deben preservar foco y navegación. Hay que validar sliders discretos, valores como fracciones/EV, etiquetas, estados deshabilitados y acciones de Test/Multi sin activaciones duplicadas. [Orden de foco Widgets](https://doc.qt.io/qt-6.8/designer-tab-order.html), [teclado Quick](https://doc.qt.io/qt-6.8/accessible-qtquick.html)

**EN/ES es viable en ambas**, usando las herramientas de internacionalización Qt; hay que traducir también nombres accesibles, errores y diálogos, comprobar expansión de texto y formatos numéricos. El catálogo Swift actual no se importa automáticamente por elegir Qt. Se deben conservar las preferencias de apariencia y reducción de movimiento acordadas. [Internacionalización Qt](https://doc.qt.io/qt-6.8/internationalization.html)

## Panel de bandeja y Wayland

**Ninguna alternativa resuelve por sí sola el panel funcional aprobado.** `QSystemTrayIcon` ofrece icono/menú y detección de disponibilidad, con limitaciones de activación en GNOME sin extensiones; tooltips/eventos de rueda específicos de X11 no son una base portable. Se requiere un panel propio con los controles, foco y sesión compartida de la referencia macOS. [QSystemTrayIcon](https://doc.qt.io/qt-6.8/qsystemtrayicon.html)

Qt admite clientes Wayland y X11, pero eso no certifica posicionamiento junto al icono, activación, clic exterior, Escape o foco. Qt advierte que algunos sistemas no permiten fijar/consultar posiciones globales de ventanas. Deben comprobarse esas interacciones en GNOME estándar para ambas sesiones. Cerrar la última ventana sigue solicitando salida mediante el gate acordado; elegir una tecnología visual no cambia esa política. [Qt/Wayland](https://doc.qt.io/qt-6.8/wayland-and-qt.html), [posición de ventanas](https://doc.qt.io/qt-6.8/qwindow.html#position)

## Gráficos, despliegue y pruebas

- **Widgets:** Qt describe sus interfaces habituales como renderizadas por software. Simplifica la dependencia gráfica de una UI tradicional; no elimina plugins de plataforma, escalado ni pruebas reales. [Comparación Qt](https://doc.qt.io/qt-6.8/topics-ui.html)
- **Quick:** el renderer usa RHI y normalmente Direct3D 11 en Windows/OpenGL en Linux. Existe backend software, pero no renderiza ShaderEffect ni partículas; con escala fraccional pierde la optimización de actualizaciones parciales. No diseñar información o controles esenciales que desaparezcan en fallback. [Renderer](https://doc.qt.io/qt-6.8/qtquick-visualcanvas-scenegraph-renderer.html), [limitaciones software](https://doc.qt.io/qt-6.8/qtquick-visualcanvas-adaptations-software.html)
- **Distribución:** ambas requieren Qt, plugins, traducciones y el proceso/runtime Swift. Quick añade motor/módulos QML y sus recursos; un binario QtCore validado no prueba que estén desplegados. [Despliegue QML](https://doc.qt.io/qt-6.8/qtquick-deployment.html)
- **Pruebas:** Qt Test sirve a pruebas C++; Quick Test permite tests QML. La existencia de herramientas no prueba accesibilidad, bandeja, compositor ni equivalencia funcional. La matriz debe incluir teclado, lector de pantalla, EN/ES, claro/oscuro, escala, diálogos, panel y caída/cierre del motor en los destinos aprobados. [Qt Test](https://doc.qt.io/qt-6.8/qttest-index.html), [Quick Test](https://doc.qt.io/qt-6.8/qtquicktest-index.html)

Mezclar ambas es posible mediante `QQuickWidget`, pero añade un render pass y desactiva el render loop con hilo en Qt 6.8. No es una combinación gratuita ni necesaria para conservar C++. [QQuickWidget](https://doc.qt.io/qt-6.8/qquickwidget.html)

## Decisión pendiente

**Widgets** merece preferencia si Edo prioriza escritorio tradicional, edición densa y menor diversidad de tecnologías de presentación. **Quick/QML** merece preferencia si prioriza composición declarativa, personalización visual y adaptación de tarjetas/panel, aceptando validar despliegue QML, foco y fallback gráfico. Ambas pueden aspirar a la paridad requerida; **ninguna la tiene demostrada**. La decisión humana debe fijar qué coste de presentación se quiere asumir, sin alterar el motor Swift ni reducir la referencia macOS.
