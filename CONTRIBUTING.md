# Contribuir

Gracias por ayudar a mejorar Estrobo. Durante el beta se priorizan fallos reproducibles, accesibilidad, pruebas deterministas, documentación y cambios pequeños que mantengan el contrato de seguridad operativa.

Este repositorio **no incluye una licencia open-source**. La ausencia es intencional por ahora; la visibilidad pública no debe interpretarse como una licencia. Si tu contribución depende de términos específicos, abre un issue antes de invertir trabajo. No añadas ni elijas una licencia en un pull request sin una decisión explícita de los mantenedores.

## Preparar el entorno

Necesitas macOS 13 o posterior y las herramientas de línea de comandos de Xcode.

```sh
make mac-prototype-check
make mac-prototype-test
make mac-prototype-build
```

Para revisar la UI sin hardware:

```sh
/usr/bin/open -n prototype/GodoxMacControlPrototype/Build/estrobo.app --args --mock-radio
```

El modo simulado debe identificarse como **Radio simulado**. Nunca debe activarse como fallback de una sesión real.

## Flujo recomendado

1. Abre o comenta un issue para cambios de protocolo, compatibilidad o comportamiento de producto.
2. Mantén el cambio acotado y no reviertas trabajo no relacionado.
3. Añade pruebas para el caso feliz, cancelación, timeout y recuperación cuando corresponda.
4. Ejecuta check/test/build en la arquitectura disponible.
5. Actualiza documentación pública y `CHANGELOG.md` si cambia el comportamiento observable.
6. Revisa el diff completo en busca de binarios, secretos, datos personales y artefactos generados.
7. Explica en el pull request qué validaste y qué gate físico sigue pendiente.

Los builds universales firmados y paquetes públicos pertenecen al workflow de release. Una contribución normal no necesita acceso al P12, su password ni otros secrets.

## Contratos que deben conservarse

- El estado local de Estrobo es la fuente de verdad; conexión/Sync sobrescribe A0 + A1 configurados y no simula lectura radio → app.
- Automático sigue siendo predeterminado con debounce de 700 ms; **Con botón** continúa disponible.
- Durante un gesto continuo no se arma/ejecuta un deadline ni se transmiten valores intermedios. Sólo el último token al terminar puede programar el valor final.
- Apply/Enviar ahora, Sync, Test y acciones que reemplacen/transmitan borradores se bloquean durante edición; Desconectar permanece disponible.
- El Código del radio conserva `Psub`/`PWOK`, seis dígitos, `SecureField` y `privacySensitive`; recordar empieza apagado y nunca se filtra a logs/presets/diagnósticos/issues.
- A0 confirma por GATT; A1 por GATT + `FEC8`. `FEC8` no identifica grupo ni resultado óptico.
- Test es explícito, fail-fast y sin reintento automático.
- App Sandbox/Bluetooth permanecen activos y no se añade red, analítica o telemetría.
- No se omite el handshake `Psub`/`PWOK` ni se añade pairing obligatorio, criptografía casera, cambio de código, firmware u OAD por conjetura.

Si tu propuesta cambia alguno, primero abre una discusión y aporta evidencia suficiente para una decisión explícita.

## Pruebas y datos

- Usa sólo Códigos del radio sintéticos de seis dígitos.
- No inicialices Bluetooth real en tests automatizados.
- Para interacción continua usa el harness AppKit/SwiftUI con mouse-down, pausa, drag y mouse-up; una búsqueda de texto no sustituye el comportamiento.
- Comprueba teclado y VoiceOver, no sólo puntero.
- Cubre múltiples tokens, final idempotente, desaparición/deshabilitación de vistas y Descartar.
- Los tests de protocolo deben comparar payload y CRC byte por byte sin imprimir autenticación.

## Pruebas físicas

No se requiere hardware para contribuir. Si propones ampliar compatibilidad:

- coordina el gate antes de mandar comandos;
- identifica modelo/firmware sin publicar UUID o datos personales;
- parte de un baseline conocido y reversible;
- evita Test salvo que sea imprescindible y el entorno sea seguro;
- registra GATT/`FEC8` y observación física por separado;
- restaura el baseline y confirma reconexión;
- no publiques APKs, firmware, binarios de terceros ni Códigos del radio.

Un acuse o nombre BLE por sí solo no promueve compatibilidad.

## Estilo del pull request

Incluye:

- problema y alcance;
- decisión de diseño;
- pruebas ejecutadas con resultado;
- capturas apropiadas, preferentemente en modo simulado;
- riesgos y gates manuales pendientes;
- confirmación de que no se usaron datos o códigos reales.

No mezcles refactors amplios con una corrección funcional. No incluyas `Build/`, `Dist/`, `.DS_Store`, lockfiles de Affinity, ZIP/DMG, ejecutables, claves, `.p12` ni temporales de keychain.

## Seguridad

No abras un pull request público que revele una vulnerabilidad antes de coordinarla. Usa [Private Vulnerability Reporting](SECURITY.md).
