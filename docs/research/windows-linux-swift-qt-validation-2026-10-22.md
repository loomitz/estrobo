# Swift detrás de Qt: validación real en Windows y Linux

Investigación iniciada el 22 de octubre de 2026. Baseline macOS: [bf98e82637b562fff732ca82d7a92a66fe984d66](https://github.com/loomitz/estrobo/tree/bf98e82637b562fff732ca82d7a92a66fe984d66).

## Resultado

**La prueba de integración sintética pasó en ambos sistemas, en el mismo commit.** El controlador Swift real compila y ejecuta su suite de sesión, y Qt/C++ puede manejarlo mediante un proceso local con eventos, cierre e interrupción. Esto permite continuar la ruta elegida por Edo; **no acredita paridad completa ni selecciona IPC como puente productivo frente a FFI**.

Commit realmente probado: [594d759d3a6521b046fb80175f7866e9d845a55d](https://github.com/loomitz/estrobo/tree/594d759d3a6521b046fb80175f7866e9d845a55d). [Run completo aprobado](https://github.com/loomitz/estrobo/actions/runs/39908642182). La rama puede incorporar después únicamente notas de resultados: ese HEAD documental no debe confundirse con el commit ejecutado.

## Evidencia por plataforma

| Plataforma del job | Compiladores y herramientas observados | Tests existentes | Qt ↔ motor y cierre |
| --- | --- | --- | --- |
| [Windows-2025, x86_64](https://github.com/loomitz/estrobo/actions/runs/39908642182/job/120266272534) | Swift 6.4.1, modo Swift 6; VS2026/MSVC 19.51.36260.0; clang visible en PATH 21.1.6; CMake 3.29.2 | 58/58, cero fallos, 24.861 s | PASS: cierre normal con 177 ticks de Qt; fin con 192 ticks, una petición invalidada y cero reintentos automáticos |
| [Ubuntu-24.04, x86_64](https://github.com/loomitz/estrobo/actions/runs/39908642182/job/120266272684) | Swift 6.4.1, modo Swift 6; GCC 13.3.0; CMake 3.31.6 | 58/58, cero fallos, 23.220 s | PASS: cierre normal con 153 ticks; fin con 164 ticks, una petición invalidada y cero reintentos automáticos |

Los 58 tests son **53 de GodoxSessionController y cinco smoke de Core**, sin filtros, exclusiones ni cambios en sus cuerpos. No son todo el suite del repositorio. Incluyen PWOK/Sync, A0 antes de A1 serial, requisitos de acuse, heartbeat diferido, timeout, fallo del journal, resultado incierto, Test sin reintento y reconexión exacta. [Tests del baseline](https://github.com/loomitz/estrobo/blob/bf98e82637b562fff732ca82d7a92a66fe984d66/Tests/EstroboCoreTests/GodoxSessionControllerTests.swift).

Los artifacts conservan logs por comando, resultados JSON, Package.resolved, hashes de fuente y parche staged: [Windows](https://github.com/loomitz/estrobo/actions/runs/39908642182/artifacts/12481818382), [Linux](https://github.com/loomitz/estrobo/actions/runs/39908642182/artifacts/12481647849). Retención configurada: 14 días. Los extractos permanentes relevantes son:

```text
Windows: Executed 58 tests, with 0 failures ... 24.861 seconds
Linux:   Executed 58 tests, with 0 failures ... 23.22 seconds
Windows: QT_SWIFT_BRIDGE_PASS, invalidatedPending=1, automaticRetries=0, qtTicks=192
Linux:   QT_SWIFT_BRIDGE_PASS, invalidatedPending=1, automaticRetries=0, qtTicks=164
```

## Qué ejecutó el experimento

El [scaffold reproducible](https://github.com/loomitz/estrobo/tree/594d759d3a6521b046fb80175f7866e9d845a55d/prototype/SwiftQtValidation) lee mediante git show las **11 fuentes Core completas**, incluido GodoxSessionController, desde el baseline. Agrega el SimulatedRadioTransport existente y repositorios en memoria extraídos de los auxiliares de tests. No reemplaza el motor por un fake.

Adaptaciones explícitas, sólo en copias generadas:

1. Import condicional Combine/OpenCombine; OpenCombine 0.14.0 fijado a [8576f0d579b27020beccbccc3ea6844f3ddfc2c2](https://github.com/OpenCombine/OpenCombine/tree/8576f0d579b27020beccbccc3ea6844f3ddfc2c2).
2. Guarda de import del simulador para compilarlo dentro del módulo experimental Core.
3. Visibilidad interna de tipos auxiliares de fixtures extraídos; cuerpos de tests y lógica del controlador intactos.
4. Fachada experimental que observa $phase y traduce comandos/resultados JSON. El controlador conserva estado, reglas y secuenciación.

El motor y los tests usan **modo de lenguaje Swift 6**. OpenCombine conserva el modo de su propio manifest; no se rebaja el núcleo a Swift 5.

QtCore 6.8.3 inicia el ejecutable Swift directamente mediante QProcess, recibe fases authenticating/synchronizing/ready y comprueba Start, cambio de potencia/Apply, error por comando desconocido y shutdown. Un QTimer avanza durante el trabajo; el harness usa señales de QProcess y no espera síncronamente al motor. El cierre normal exige EOF de stdin tras confirmar shutdown y esperar al lector. Luego otra instancia se mata con una conexión pendiente: Qt invalida esa petición, rechaza trabajo sobre el proceso muerto y no la repite. [Host y harness probados](https://github.com/loomitz/estrobo/tree/594d759d3a6521b046fb80175f7866e9d845a55d/prototype/SwiftQtValidation).

En Windows QProcess arrancó el EXE Swift fuera de SwiftPM, heredando el entorno instalado y anteponiendo Qt/bin; **no hubo copias manuales de DLL ni desactivación de controles del compilador**. No equivale a probar una instalación limpia para usuarios.

## Obstáculos descubiertos y resueltos

- El primer intento con modo Swift 5 no compiló defaults @MainActor de fixtures; se conservó modo 6, acorde al paquete productivo. [SE-0411](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0411-isolated-default-values.md).
- VsDevShell/PATH llevó Python al alias Store; se fijó Python 3.12 por acción oficial y ruta explícita.
- Swift 6.1.3 fue incompatible con el STL de VS2026: STL1000 exigía Clang >=20. Se actualizó a Swift estable 6.4.1 en ambos sistemas, manteniendo el chequeo.
- La salida CP1252 del logger Windows falló al imprimir Unicode después de aprobar los tests; el driver fija UTF-8.
- El primer puente Linux confirmó shutdown pero dejó el lector abierto y venció el plazo. El contrato EOF y la espera del lector corrigieron el fallo; la pareja final verifica cierre y kill.

Estos fallos están preservados en [primer run](https://github.com/loomitz/estrobo/actions/runs/39907126812), [modo 6](https://github.com/loomitz/estrobo/actions/runs/39907441459), [toolchain actualizado](https://github.com/loomitz/estrobo/actions/runs/39908125449) y [corrección EOF](https://github.com/loomitz/estrobo/actions/runs/39908363996).

## Dependencias, reproducción y límites

El [README probado](https://github.com/loomitz/estrobo/blob/594d759d3a6521b046fb80175f7866e9d845a55d/prototype/SwiftQtValidation/README.md) contiene el comando y requisitos. CI tiene contents read, sin secretos propios, timeout global de 45 minutos y comandos acotados. Qt se construye desde el [archivo oficial 6.8.3 con SHA256 verificado](https://download.qt.io/archive/qt/6.8/6.8.3/submodules/qtbase-everywhere-src-6.8.3.tar.xz.sha256). Swift procede de download.swift.org, siguiendo [Windows](https://www.swift.org/install/windows/manual/) y [Dockerfile oficial Linux 6.4.1](https://github.com/swiftlang/swift-docker/blob/main/6.4/ubuntu/24.04/Dockerfile). QProcess tiene [documentación oficial](https://doc.qt.io/qt-6.8/qprocess.html).

**Pendiente antes de un port con paridad:** almacenamiento seguro y journal durable nativos; BLE físico/GATT e identidad local; UI y accesibilidad; ciclo de vida; actualizador; empaquetado e instalación limpia. La prueba usa repositorios en memoria y transporte simulado. El kill se hace durante conexión, no demuestra recuperación durable tras interrumpir una escritura física. El cierre normal se prueba tras completar operaciones; cancelación grácil intermedia y contrato productivo del puente quedan por definir.

Se publicaron sólo archivos nuevos de experimento, workflow e informe en rama desechable. No se cambió main, ninguna fuente Apple productiva ni el checkout local; no se abrió PR.
