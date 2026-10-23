# Portabilidad del motor Swift de Estrobo a Windows y Linux

Fecha: 2026-10-22. Baseline: [bf98e826](https://github.com/loomitz/estrobo/tree/bf98e82637b562fff732ca82d7a92a66fe984d66). Alcance: conservar las interfaces Apple, compartir Windows/Linux y exigir paridad completa con macOS desde el primer lanzamiento. Investigación documental y lectura estática; **sin compilación, instalación de toolchains ni pruebas Bluetooth**.

## Resultado

Swift es una alternativa técnicamente plausible para compartir el motor; el paquete actual necesita adaptación. No hay evidencia para prometer que el motor completo compile o se comporte igual en Windows/Linux. Separar motor y presentación es independiente de elegir monorepo o varios repositorios. Las alternativas siguientes dejan esa decisión abierta.

## Lo que existe y lo que impide reutilizarlo directamente

| Pieza del baseline | Evidencia e implicación |
| --- | --- |
| Modelos, capacidades, protocolo y puertos | Los archivos de Core salvo el controlador importan Foundation; contienen codecs A0/A1, validaciones y contratos de transporte/persistencia. Son candidatos a reutilización de fuente, pendiente de compilar y comparar resultados. [Core](https://github.com/loomitz/estrobo/tree/bf98e82637b562fff732ca82d7a92a66fe984d66/Sources/EstroboCore), [protocolo](https://github.com/loomitz/estrobo/blob/bf98e82637b562fff732ca82d7a92a66fe984d66/Sources/EstroboCore/SafeGodoxProtocol.swift). |
| Controlador de sesión | Es `internal`, hereda de `NSObject` y usa `ObservableObject/@Published` de Combine; sus operaciones también son internas. iOS incluye el archivo en su propio target y macOS compila fuentes compartidas. Exportar la librería existente no proporciona una API pública de sesión. Haría falta una fachada pública o reorganizar compilación y observación. [Controlador, líneas 1–110](https://github.com/loomitz/estrobo/blob/bf98e82637b562fff732ca82d7a92a66fe984d66/Sources/EstroboCore/GodoxSessionController.swift#L1-L110), [iOS, línea 87](https://github.com/loomitz/estrobo/blob/bf98e82637b562fff732ca82d7a92a66fe984d66/ios/project.yml#L87), [Makefile](https://github.com/loomitz/estrobo/blob/bf98e82637b562fff732ca82d7a92a66fe984d66/prototype/EstroboMac/Makefile#L103-L112), [visibilidad Swift](https://github.com/swiftlang/swift-book/blob/main/TSPL.docc/LanguageGuide/AccessControl.md). |
| Bluetooth | `RadioTransport` es público, con eventos y métodos explícitos; la fábrica pública `live()` instancia directamente CoreBluetooth. La abstracción permite otro adaptador, pero ese adaptador no existe aquí. [Puerto](https://github.com/loomitz/estrobo/blob/bf98e82637b562fff732ca82d7a92a66fe984d66/Sources/EstroboCore/RadioTransport.swift#L118-L150), [fábrica](https://github.com/loomitz/estrobo/blob/bf98e82637b562fff732ca82d7a92a66fe984d66/Sources/EstroboBluetooth/RadioTransportFactory.swift). |
| Persistencia | Hay puertos públicos y fábrica live/in-memory. La fábrica live usa Keychain para códigos, UserDefaults para metadatos y un journal que importa Darwin y ejecuta `F_FULLFSYNC`, permisos POSIX y sincronización de directorio. Cambiar imports no demuestra equivalencia de seguridad o durabilidad. [Puertos](https://github.com/loomitz/estrobo/blob/bf98e82637b562fff732ca82d7a92a66fe984d66/Sources/EstroboCore/PersistencePorts.swift), [fábrica](https://github.com/loomitz/estrobo/blob/bf98e82637b562fff732ca82d7a92a66fe984d66/Sources/EstroboPersistence/PersistenceServicesFactory.swift), [vault](https://github.com/loomitz/estrobo/blob/bf98e82637b562fff732ca82d7a92a66fe984d66/Sources/EstroboPersistence/RadioCodeVault.swift), [journal](https://github.com/loomitz/estrobo/blob/bf98e82637b562fff732ca82d7a92a66fe984d66/Sources/EstroboPersistence/RestorationJournal.swift). |
| Paquete | Las dependencias enlazan CoreBluetooth y Security sin condiciones. Los targets/adaptadores Apple deben aislarse de la construcción portable; declarar macOS/iOS en `platforms` no es por sí solo una demostración de incompatibilidad con Linux. [Manifest](https://github.com/loomitz/estrobo/blob/bf98e82637b562fff732ca82d7a92a66fe984d66/Package.swift). |

## Soporte documentado, con límites

Swift.org documenta desarrollo y despliegue en Windows y varias distribuciones Linux, con SwiftPM. La instalación de desarrollo Windows requiere componentes de Visual Studio/SDK y ofrece toolchains x86_64 y arm64; esto no establece los requisitos del instalador final de Estrobo. [Plataformas](https://www.swift.org/platform-support/), [Windows](https://www.swift.org/install/windows/).

Foundation comparte implementaciones de tipos como Data, URL y JSONDecoder; Corelibs aporta compatibilidad, incluido NSObject, de mejor esfuerzo. Por tanto, NSObject no es automáticamente un bloqueo, pero tampoco debe asumirse igualdad de todas las APIs. UserDefaults tiene implementación Corelibs: podría conservarse para preferencias tras verificar rutas, persistencia y migración, sin confundirlo con el journal durable o el almacén de secretos. [Foundation](https://github.com/swiftlang/swift-foundation#readme), [UserDefaults](https://github.com/swiftlang/swift-corelibs-foundation/blob/main/Sources/Foundation/UserDefaults.swift).

La disponibilidad de Swift/Foundation no aporta automáticamente Combine. Las bibliotecas multiplataforma oficiales enumeradas incluyen Foundation, libdispatch y XCTest; OpenCombine se presenta como implementación alternativa para Linux/Windows. Adoptarla exige comprobar compatibilidad del subconjunto usado y mantenimiento; otra posibilidad es separar las notificaciones de UI del motor y mantener un adaptador Combine para Apple. **Ninguna fue probada aquí.** [Bibliotecas Swift](https://www.swift.org/documentation/core-libraries/), [OpenCombine](https://github.com/OpenCombine/OpenCombine#readme).

## Motor enlazado o proceso local

**Enlazado en el proceso de UI.** Swift 6.3 formalizó `@c`: permite funciones globales y enums compatibles con C, con encabezado generado. No exporta directamente structs Swift ni protocolos existenciales; los modelos y `any RadioTransport` actuales necesitan traducción, handles o buffers. El paquete declara tools-version 6.0: usar `@c` requeriría acordar un compilador compatible. [SE-0495](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0495-cdecl.md).

Inferencia de diseño: una fachada pequeña de comandos/eventos limita el acoplamiento. Tiene que definir propiedad de memoria, liberación, errores, cancelación y entrega ordenada. El controlador y los puertos son `@MainActor`; callbacks externos necesitan entrar correctamente en ese aislamiento y validar su integración con el bucle de la UI. [Concurrencia Swift](https://github.com/swiftlang/swift-book/blob/main/TSPL.docc/LanguageGuide/Concurrency.md), [puerto actual](https://github.com/loomitz/estrobo/blob/bf98e82637b562fff732ca82d7a92a66fe984d66/Sources/EstroboCore/RadioTransport.swift#L132-L150).

C++ interop también está soportado en los destinos Swift, pero exporta solamente APIs públicas representables, exige compiladores compatibles con sus extensiones y documenta restricciones de biblioteca estándar/Windows. No equivale a conectar cualquier UI C++ sin adaptación. [Guía](https://www.swift.org/documentation/cxx-interop/), [restricciones](https://www.swift.org/documentation/cxx-interop/status/).

**Proceso auxiliar local.** Inferencia de arquitectura: un ejecutable Swift puede intercambiar comandos/eventos versionados con la UI mediante pipes/IPC, sin exponer layouts Swift. A cambio incorpora serialización, supervisión, cancelación, contrapresión y actualización coordinada de dos binarios. El proyecto oficial Subprocess documenta procesos y flujos stdin/stdout; no prueba esta integración de Estrobo. [Subprocess](https://github.com/swiftlang/swift-subprocess#readme). Debe definirse qué ocurre si muere la UI durante una operación física: reiniciar el proceso nunca autoriza repetir escrituras inciertas. Ambos modelos requieren resolver Combine, Bluetooth, persistencia y distribución del runtime; el proceso no convierte APIs Apple en portables.

## Tres rutas abiertas

Las siguientes son opciones de diseño derivadas del código anterior, no resultados medidos:

| Ruta | Qué comparte | Coste y riesgo principal |
| --- | --- | --- |
| Adaptar el motor Swift | Protocolo, modelos y estado/secuenciación entre Apple y escritorio; UI Apple conservada | Extraer fachada, desacoplar Combine o probar alternativa, adaptar almacenamiento/transporte y empaquetar Swift junto al escritorio. Menos lógica duplicada; más integración entre lenguajes. |
| Motor portable común a largo plazo | Trasladar gradualmente dominio/protocolo/sesión a otro núcleo, por ejemplo Rust/C++, consumido también por Apple | Reescritura y migración de Apple, bindings y pruebas. Puede unificar comportamiento, pero aumenta el alcance inicial; conservar UI Apple sigue siendo posible. |
| Motor de escritorio separado | Windows/Linux comparten motor y UI; Apple mantiene Swift | Reduce cambios iniciales en Apple; duplica lógica. Requiere contrato versionado y conformidad continua para evitar divergencia. Compartir sólo bytes A0/A1 no cubre recuperación ni secuenciación. |

## Evidencia necesaria antes de elegir

- Compilación y pruebas deterministas del núcleo aislado en ambos sistemas, incluyendo observación/concurrencia e instalador en máquina limpia.
- Conformidad de comandos, transiciones, plazos, recuperación e incertidumbre usando escenarios del [suite actual](https://github.com/loomitz/estrobo/blob/bf98e82637b562fff732ca82d7a92a66fe984d66/Tests/EstroboCoreTests/GodoxSessionControllerTests.swift), sin convertir sus salidas automáticamente en especificación.
- Pruebas físicas BLE y fallos de almacenamiento por plataforma. Son necesarias incluso con el mismo motor.
- Fijar qué versión/funciones macOS constituyen paridad completa; el motor compartido no demuestra paridad de UI, accesibilidad, bandeja, actualizador o ciclo de vida.

No se eligió arquitectura ni se modificó implementación. Las alternativas son viables como hipótesis; ninguna tiene aún portabilidad o paridad demostradas.
