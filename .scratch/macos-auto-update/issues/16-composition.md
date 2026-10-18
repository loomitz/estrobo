# Composición productiva y recorrido integrado de actualizaciones

Parent: ../spec.md
Type: task
Status: open
Assignee: none
Blocked by: 12, 13

## Acceptance

Decisiones 1, 4, 5, 7-10, 21 y secuencia de 22. Integrar el adaptador real de 12 y los componentes de 13 en EstroboApp, AppDelegate, factory y bridge AppKit mediante una única instancia de coordinador/servicio compartida por ventana, menú y Ajustes.

Conectar búsqueda manual, preferencias y programación, invitación no modal, descarga/progreso/cancelación, notas localizadas y confirmación por oferta. Conservar el gate normal de cierre y la restauración de ventana; el bridge validado reevalúa seguridad antes de preparar y comprometer, cancela antes de consumir aprobación ante veto o salida ordinaria y conserva la suspensión de comandos hasta el acknowledgement real. La UI no manipula continuaciones Sparkle ni duplica lógica del instalador.

Revalidar el recorrido real de menú y Ajustes, consentimiento, cancelación, veto/reintento, conservación de datos y relanzamiento desconectado. La composición usa el estado de configuración honesto cuando falta la clave pública de distribución; no sustituye firmas ni habilita un feed no verificado. La evidencia local y los gates de distribución pendientes permanecen diferenciados y pasan a la validación final 15.

## Test seams

Seams autorizados por Testing Decisions de spec.md: coordinador mediante puerto único; adaptador Sparkle real y fixture aislado; AppKit/UI y sesión existente con transporte simulado. Reutilizar las pruebas de 10-13 y añadir la evidencia que comprueba su composición productiva, sin duplicar otra implementación del gate. Sin publicación ni radio físico.

## Graph refinement

2026-10-18: composición extraída de 13 después de estabilizar el puerto 11. Se conserva el comportamiento final original; 13 puede implementar presentación y pruebas mientras 12 implementa el adaptador. 16 depende de ambos y 15 requiere 14 y 16.
