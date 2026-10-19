# Composición productiva y recorrido integrado de actualizaciones

Parent: ../spec.md
Type: task
Status: resolved
Assignee: update_ui
Blocked by: 12, 13

## Acceptance

Decisiones 1, 4, 5, 7-10, 21 y secuencia de 22. Integrar el adaptador real de 12 y los componentes de 13 en EstroboApp, AppDelegate, factory y bridge AppKit mediante una única instancia de coordinador/servicio compartida por ventana, menú y Ajustes.

Conectar búsqueda manual, preferencias y programación, invitación no modal, descarga/progreso/cancelación, notas localizadas y confirmación por oferta. Conservar el gate normal de cierre y la restauración de ventana; el bridge validado reevalúa seguridad antes de preparar y comprometer, cancela antes de consumir aprobación ante veto o salida ordinaria y conserva la suspensión de comandos hasta el acknowledgement real. La UI no manipula continuaciones Sparkle ni duplica lógica del instalador.

Revalidar el recorrido real de menú y Ajustes, consentimiento, cancelación, veto/reintento, conservación de datos y relanzamiento desconectado. La composición usa el estado de configuración honesto cuando falta la clave pública de distribución; no sustituye firmas ni habilita un feed no verificado. La evidencia local y los gates de distribución pendientes permanecen diferenciados y pasan a la validación final 15.

## Test seams

Seams autorizados por Testing Decisions de spec.md: coordinador mediante puerto único; adaptador Sparkle real y fixture aislado; AppKit/UI y sesión existente con transporte simulado. Reutilizar las pruebas de 10-13 y añadir la evidencia que comprueba su composición productiva, sin duplicar otra implementación del gate. Sin publicación ni radio físico.

## Graph refinement

2026-10-18: composición extraída de 13 después de estabilizar el puerto 11. Se conserva el comportamiento final original; 13 puede implementar presentación y pruebas mientras 12 implementa el adaptador. 16 depende de ambos y 15 requiere 14 y 16.

## Resolution

2026-10-18: Composición productiva integrada con un único coordinador, servicio y lifecycle compartidos por AppDelegate, menú, ventana y Ajustes. Constructor y escenas nativas verifican preferencias, deduplicación, veto/reapertura, cancelación con acknowledgement y estado desconectado. Factory real sin clave devuelve configuración no disponible. Build/check/universal y todos los targets del aggregate quedaron verdes en dos segmentos documentados tras corregir la firma ad hoc de desarrollo; distribución conserva Hardened Runtime y verificación estricta. Informe y límites: [macos-updater-composition-2026-10-18.md](../../../docs/research/macos-updater-composition-2026-10-18.md). Aceptación integrada y gates pendientes continúan en 17; sin publicación ni credenciales.
