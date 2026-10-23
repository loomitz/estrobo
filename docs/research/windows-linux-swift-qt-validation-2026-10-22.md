# Validación experimental de Swift detrás de Qt

Fecha: 2026-10-22. Baseline macOS: [bf98e82637b562fff732ca82d7a92a66fe984d66](https://github.com/loomitz/estrobo/tree/bf98e82637b562fff732ca82d7a92a66fe984d66). Ruta elegida por Edo: conservar motor Swift con Qt/C++, condicionada a validación Windows/Linux antes del port.

## Estado de esta revisión

**Primer intento ejecutado: núcleo y host reales compilaron en Linux; el suite y Qt no han pasado.** No hay resultado que permita aprobar la arquitectura. La preparación local de copias inmutables y la sintaxis de los scripts Python se verificaron; no equivalen a compilar Swift/Qt.

El experimento vive en [prototype/SwiftQtValidation](../../prototype/SwiftQtValidation/README.md), separado de fuentes Apple. Rama prevista: [research/windows-linux-swift-qt-validation-2026-10-22](https://github.com/loomitz/estrobo/tree/research/windows-linux-swift-qt-validation-2026-10-22). La definición [workflow.yml](../../prototype/SwiftQtValidation/workflow.yml) se publica como workflow activo únicamente en esa rama. El estado de ejecución y los impedimentos reales se registrarán aquí tras intentar su publicación.

## Diseño verificable y límites

| Nivel | Implementación experimental | Estado |
| --- | --- | --- |
| Núcleo real | Todas las 11 fuentes Core del baseline, incluido GodoxSessionController; se leen con git show y se registran hashes. | Staging local correcto; compilación pendiente. |
| Observación | Import condicional Combine/OpenCombine en copias staged; OpenCombine 0.14.0 fijado a commit 8576f0d579b27020beccbccc3ea6844f3ddfc2c2. | No probado en runtime. |
| Sesión y recuperación | Los dos archivos existentes de tests Core completos, sin cambiar cuerpos, filtrar ni excluir tests. Incluyen PWOK/Sync, orden A0/A1, acuses, plazos, fallos y recuperación. | Pendiente; no representa todo el suite del repositorio. |
| Puente experimental | QtCore/QProcess inicia el ejecutable Swift; comandos JSON con ID y eventos observados del controlador; Start, Apply, error y cierre. | Sin compilar/ejecutar. IPC sigue siendo candidato, no decisión frente FFI. |
| Bucle Qt | QTimer continúa mientras la sesión real llega a ready; QProcess usa señales, sin waits síncronos. | Pendiente. |
| Caída | Segunda instancia con conexión pendiente; Qt mata el proceso, invalida la petición y rechaza trabajo posterior sin reintento automático. | Pendiente; no acredita journal durable. |

El host usa el **SimulatedRadioTransport existente**, no un controlador inventado. Los repositorios en memoria se extraen de los auxiliares del suite existente; la fachada sólo traduce comandos y resultados.

Diferencias explícitas: compilador Swift **6.4.1** (intentos iniciales con 6.1.3) y modo de lenguaje **Swift 6**. El primer intento usó modo 5 y falló al compilar defaults @MainActor de fixtures (SE-0411); el segundo conserva el modo 6 del paquete productivo. OpenCombine conserva el modo de su propio manifest. Se adaptan imports en copias y visibilidad de tipos auxiliares de fixtures; no se modifica la lógica del controlador ni las fuentes originales.

## Reproducción y dependencias

El [README](../../prototype/SwiftQtValidation/README.md) y [run.py](../../prototype/SwiftQtValidation/run.py) contienen los comandos. El driver se niega a sobrescribir una ejecución previa, limita comandos, conserva logs y resultados JSON, y verifica el SHA256 de Qt. CI usa Windows-2025 y Ubuntu-24.04 x86_64, fail-fast false, timeout de 45 minutos y permisos contents read. No usa secretos, hardware, releases ni cambios a main.

- [Swift Windows manual](https://www.swift.org/install/windows/manual/) documenta MSVC/SDK y distribución oficial; el workflow fija el instalador 6.4.1 de download.swift.org.
- [Dockerfile oficial Swift 6.4 para Ubuntu 24.04](https://github.com/swiftlang/swift-docker/blob/main/6.4/ubuntu/24.04/Dockerfile) fija Swift 6.4.1 y documenta dependencias/URL Linux.
- [OpenCombine 0.14.0](https://github.com/OpenCombine/OpenCombine/tree/8576f0d579b27020beccbccc3ea6844f3ddfc2c2) declara soporte Linux/Windows; su compatibilidad concreta con este motor se pone a prueba.
- [Qt Windows](https://doc.qt.io/qt-6.8/windows-building.html) y [Qt Linux](https://doc.qt.io/qt-6.8/linux-building.html) documentan construcción desde fuentes. Se fija QtBase 6.8.3 desde el [archivo oficial y SHA256](https://download.qt.io/archive/qt/6.8/6.8.3/submodules/qtbase-everywhere-src-6.8.3.tar.xz.sha256), construyendo sólo módulos base necesarios para QtCore.
- [QProcess](https://doc.qt.io/qt-6.8/qprocess.html) documenta inicio, señales y terminación de procesos; no demuestra por sí mismo el contrato de Estrobo.

## Criterios para interpretar resultados

Compilación, suite Core y puente deben ejecutarse satisfactoriamente en **ambos sistemas del mismo commit** antes de declarar aprobada esta prueba de integración. Cada fallo de preparación, compilación, XCTest o runtime conserva su identidad; un workflow sin ejecutar no es una prueba.

Incluso con ambos jobs verdes quedan fuera: persistencia segura nativa y journal durable ante caídas, BLE/GATT físico e identidad local, accesibilidad, UI completa, actualizador, empaquetado e instalación en máquinas limpias. El port conserva la exigencia de paridad completa con el macOS fijado.

## Primera ejecución y corrección del harness

[Run 39907126812](https://github.com/loomitz/estrobo/actions/runs/39907126812), commit 7cffabf070c9e77747de5885c524c0b1d565a738:

- Linux: Swift 6.1.3 compiló todas las fuentes Core, controlador, OpenCombine y simulador, y enlazó el host. El suite no compiló por defaults @MainActor de fixtures en modo Swift 5: call to main actor-isolated initializer in a synchronous nonisolated context. Se cambia sólo el manifest experimental a modo 6, acorde al baseline. [SE-0411](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0411-isolated-default-values.md).
- Windows: instalador y swift --version correctos; tras activar VsDevShell, python resolvió al alias Microsoft Store y terminó con exit 9009. Se fija Python 3.12 mediante setup-python oficial y se invoca por pythonLocation.
- Qt no se llegó a construir en este intento. Ningún test de sesión se considera aprobado.

## Evidencia local

- Python: py_compile de stage.py y run.py terminó con exit 0.
- stage.py: exit 0, 11 fuentes Core leídas desde el baseline y cuerpos de tests sin alterar.
- Se generaron adaptation.patch y source-manifest.json bajo _stage, ignorado por Git.
- No se instalaron toolchains ni se compiló Swift/Qt en la máquina del usuario.

## Segundo intento y selección de toolchain actual

[Run 39907441459](https://github.com/loomitz/estrobo/actions/runs/39907441459), commit 339543074e15ba21585546377b00e6677d79ea08:

- Windows ejecutó Python y comenzó la compilación, pero el STL del runner Windows-2025 con VS2026 rechazó Clang del Swift 6.1.3: **STL1000: Unexpected compiler version, expected Clang 20 or newer**. No se desactiva la comprobación.
- Linux ya pasó instalación y sigue en el driver de construcción/pruebas; se conserva el run para recoger evidencia.
- El siguiente intento fija **Swift estable 6.4.1 en ambos sistemas**, según Swift.org y Dockerfile oficial actual. El código baseline sólo exige tools-version >=6.0; no fija compilador6.1.3. Se registran toolset/SDK/clang reales del runner y se acota setup a10min, con apt no interactivo. Aún no se presupone compatibilidad de6.4.1.

## Evidencia Linux con Swift 6.1.3 y modo 6

El segundo run terminó: los **58 tests de Core pasaron** (53 de GodoxSessionController y5 smoke), en23.446s, sin cambiar sus cuerpos. Compilaron QtCore6.8.3 y el harness C++; el puente recibió fases autenticating/synchronizing/ready, Apply con pending0 y error por comando desconocido. El cierre **falló**: recibió resultado shutdown pero el lector stdin siguió abierto hasta el deadline40s. El nuevo parche del harness cierra el canal de entrada tras ese resultado y espera explícitamente al lector; falta ejecutar y comprobar esa corrección. El escenario de kill no se alcanzó. [Job Linux](https://github.com/loomitz/estrobo/actions/runs/39907441459/job/120262521691).

## Primer resultado Windows con Swift 6.4.1

[Job Windows del run39908125449](https://github.com/loomitz/estrobo/actions/runs/39908125449/job/120264670699), commit87ddfcc90c2571312b984cf62ac65521e31a6f1f: **58 tests pasan**, con53 de sesión, en25.077s. Toolset real: VisualStudio2026, MSVC14.51.36231; Swift6.4.1 corrige el rechazoSTL anterior. El job falló después al imprimir el log con PythonCP1252 (UnicodeEncodeError por U+2009). El log completo se conservó previamente en [artifact12482031392](https://github.com/loomitz/estrobo/actions/runs/39908125449/artifacts/12482031392) y se inspeccionó localmente. Se fija stdout/stderr del driver aUTF8; QtWindows sigue pendiente en este intento. Ningún fallo del logger se transforma en fallo del motor.
