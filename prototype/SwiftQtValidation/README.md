# Swift detrás de Qt: experimento desechable

Baseline inmutable: `bf98e82637b562fff732ca82d7a92a66fe984d66`. Este experimento no modifica fuentes Apple ni conecta hardware. IPC/QProcess es una hipótesis de validación, no la decisión del puente de producción.

## Ejecutar

En un checkout que contiene el baseline, con Swift **6.1.3**, CMake >=3.21, Ninja, compilador C++17 y Python >=3.12:

```text
python prototype/SwiftQtValidation/run.py
```

Windows requiere entorno MSVC x64 activo y SDK de Swift. Linux se dirige a Ubuntu 24.04 x86_64. El driver descarga QtBase 6.8.3 únicamente del archivo oficial Qt, verifica su SHA256, construye QtCore y ejecuta la prueba. OpenCombine se fija al commit de 0.14.0 `8576f0d579b27020beccbccc3ea6844f3ddfc2c2`. La construcción puede tardar; el driver fija límites por comando y CI limita cada job a 45 minutos.

`workflow.yml` preserva la definición de CI. Sólo se activa si se copia a `.github/workflows/research-swift-qt-validation.yml` en la rama desechable autorizada. No copiar a main. No requiere secretos ni permisos de escritura del job.

## Qué se compila y qué cambia

- `stage.py` lee todas las fuentes Core mediante `git show BASELINE:ruta`, incluido el controlador real. No toma archivos modificados del worktree.
- En copias staged sustituye únicamente el import Combine por import condicional OpenCombine. En el simulador añade la misma guarda de módulo que ya usa el controlador para compilar en Core.
- Mantiene los cuerpos completos de los dos archivos existentes de tests Core: sin filtros, exclusiones o alteraciones. Un fallo de descubrimiento XCTest también queda como fallo; no se presume aprobado.
- Extrae las implementaciones de repositorios en memoria del final del suite actual y hace internos sus tipos auxiliares privados sólo para usarlos dentro del target experimental. No sustituye el controlador. Agrega `ExperimentRuntime` como fachada del experimento.
- Usa modo de lenguaje Swift 5 con compilador Swift 6.1.3. No acredita strict-concurrency de modo Swift 6.
- Guarda hashes original/staged, parche exacto y logs en `_stage` y `_results`; ambas carpetas se excluyen de Git y el script se niega a sobrescribir una ejecución previa.

## Qué verifica

El suite existente comprueba PWOK/Sync, orden A0→A1, acuses, plazos, fallos y recuperación mediante su transporte de registro. Luego QtCore inicia el host con el transporte simulado real y envía start/adjust/unknown/shutdown. Qt verifica fase ready, Apply real, rechazo de comando inválido y salida limpia. Un QTimer avanza durante la sesión; no se usan waits síncronos QProcess. Otra instancia del mismo motor se mata durante una conexión pendiente: Qt invalida su petición, rechaza trabajo posterior sobre ese proceso y no la reintenta.

El escenario de kill sólo comprueba el contrato y cierre de proceso: **no** demuestra recuperación durable tras caída, porque sus repositorios son en memoria. Tampoco prueba BLE nativo, FFI, UI, accesibilidad, actualizador, instalación ni paridad completa.

## Fuentes de dependencias

- Swift y requisitos Windows: https://www.swift.org/install/windows/manual/
- Dependencias y URL Linux de Swift 6.1.3: https://github.com/swiftlang/swift-docker/blob/main/6.1/ubuntu/24.04/Dockerfile
- Qt desde fuentes: https://doc.qt.io/qt-6.8/windows-building.html y https://doc.qt.io/qt-6.8/linux-building.html
- Qt 6.8.3 y hash: https://download.qt.io/archive/qt/6.8/6.8.3/submodules/qtbase-everywhere-src-6.8.3.tar.xz.sha256
- QProcess: https://doc.qt.io/qt-6.8/qprocess.html
- OpenCombine: https://github.com/OpenCombine/OpenCombine/tree/8576f0d579b27020beccbccc3ea6844f3ddfc2c2
