# Validación experimental de Swift detrás de Qt

Fecha: 2026-10-22. Baseline macOS: [bf98e82637b562fff732ca82d7a92a66fe984d66](https://github.com/loomitz/estrobo/tree/bf98e82637b562fff732ca82d7a92a66fe984d66). Ruta elegida por Edo: conservar motor Swift con Qt/C++, condicionada a validación Windows/Linux antes del port.

## Estado de esta revisión

**Scaffold preparado; Windows y Linux todavía sin ejecutar.** No hay resultado que permita aprobar la arquitectura. La preparación local de copias inmutables y la sintaxis de los scripts Python se verificaron; no equivalen a compilar Swift/Qt.

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

Diferencias explícitas: compilador Swift **6.1.3**, pero modo de lenguaje **Swift 5** para aislar compatibilidad de OpenCombine. El paquete productivo declara tools-version 6.0 sin esta reducción. Un éxito no demostraría compatibilidad plena con modo Swift 6 ni strict-concurrency. Se adaptan imports en copias y visibilidad de tipos auxiliares de fixtures; no se modifica la lógica del controlador ni las fuentes originales.

## Reproducción y dependencias

El [README](../../prototype/SwiftQtValidation/README.md) y [run.py](../../prototype/SwiftQtValidation/run.py) contienen los comandos. El driver se niega a sobrescribir una ejecución previa, limita comandos, conserva logs y resultados JSON, y verifica el SHA256 de Qt. CI usa Windows-2025 y Ubuntu-24.04 x86_64, fail-fast false, timeout de 45 minutos y permisos contents read. No usa secretos, hardware, releases ni cambios a main.

- [Swift Windows manual](https://www.swift.org/install/windows/manual/) documenta MSVC/SDK y distribución oficial; el workflow fija el instalador 6.1.3 de download.swift.org.
- [Dockerfile oficial Swift 6.1 para Ubuntu 24.04](https://github.com/swiftlang/swift-docker/blob/main/6.1/ubuntu/24.04/Dockerfile) fija Swift 6.1.3 y documenta dependencias/URL Linux.
- [OpenCombine 0.14.0](https://github.com/OpenCombine/OpenCombine/tree/8576f0d579b27020beccbccc3ea6844f3ddfc2c2) declara soporte Linux/Windows; su compatibilidad concreta con este motor se pone a prueba.
- [Qt Windows](https://doc.qt.io/qt-6.8/windows-building.html) y [Qt Linux](https://doc.qt.io/qt-6.8/linux-building.html) documentan construcción desde fuentes. Se fija QtBase 6.8.3 desde el [archivo oficial y SHA256](https://download.qt.io/archive/qt/6.8/6.8.3/submodules/qtbase-everywhere-src-6.8.3.tar.xz.sha256), construyendo sólo módulos base necesarios para QtCore.
- [QProcess](https://doc.qt.io/qt-6.8/qprocess.html) documenta inicio, señales y terminación de procesos; no demuestra por sí mismo el contrato de Estrobo.

## Criterios para interpretar resultados

Compilación, suite Core y puente deben ejecutarse satisfactoriamente en **ambos sistemas del mismo commit** antes de declarar aprobada esta prueba de integración. Cada fallo de preparación, compilación, XCTest o runtime conserva su identidad; un workflow sin ejecutar no es una prueba.

Incluso con ambos jobs verdes quedan fuera: persistencia segura nativa y journal durable ante caídas, BLE/GATT físico e identidad local, accesibilidad, UI completa, actualizador, empaquetado e instalación en máquinas limpias. El port conserva la exigencia de paridad completa con el macOS fijado.

## Evidencia local

- Python: py_compile de stage.py y run.py terminó con exit 0.
- stage.py: exit 0, 11 fuentes Core leídas desde el baseline y cuerpos de tests sin alterar.
- Se generaron adaptation.patch y source-manifest.json bajo _stage, ignorado por Git.
- No se instalaron toolchains ni se compiló Swift/Qt en la máquina del usuario.
