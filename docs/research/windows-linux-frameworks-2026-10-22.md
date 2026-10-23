# Bases de escritorio para Estrobo: Windows y Linux

Fecha de consulta: 22 de octubre de 2026. Baseline: `bf98e82637b562fff732ca82d7a92a66fe984d66`. Investigación documental; no se instaló, compiló ni probó hardware.

## Alcance y resultado provisional

Se conservan las interfaces macOS/iOS. Windows debe ofrecer **paridad funcional completa con macOS desde su primera versión**, compartiendo aplicación con Linux. La versión y matriz exactas de paridad siguen abiertas: no se presupone copia visual píxel por píxel.

**Recomendación provisional:** usar **Qt/C++ como referencia principal**, y comparar **Avalonia/.NET** si C# resulta más mantenible para el equipo. Qt reúne UI de escritorio y BLE central oficial en ambos sistemas; Avalonia obliga a elegir y mantener el transporte por separado. **Tauri/Rust** es competitivo si se prefiere desarrollar UI web; **Flutter** y **PySide6** son opciones reales, condicionadas a experiencia del equipo y validación de dependencias. Esto prioriza candidatas; no fija tecnología ni autoriza reescribir el motor.

## Comparación

“Oficial” describe al responsable de cada capa, no una garantía de compatibilidad con Godox. Las valoraciones de productividad/mantenimiento son inferencias de esta investigación.

| Base compartida | UI y productividad | BLE central real Windows/Linux | Distribución y mantenimiento |
| --- | --- | --- | --- |
| **Qt/C++** | Widgets o Qt Quick permiten construir Canales, Inspector y Matriz; Widgets parece especialmente adecuado para escritorio denso. C++/QML implica aprendizaje si hoy sólo se mantiene Swift. | **Qt Bluetooth oficial** declara central en ambos; Linux requiere BlueZ. Evita depender de un plugin BLE de terceros. La instalación concreta puede llevar backend ficticio si Qt se construyó sin sus dependencias Linux. [Qt Bluetooth](https://doc.qt.io/qt-6/qtbluetooth-index.html) | Binarios, bibliotecas y plugins Qt por sistema; la distribución sigue procedimientos específicos de Windows/Linux. Inferencia: menos capas si el nuevo motor también fuera C++, pero conservar Swift añade otro runtime. [Despliegue Qt](https://doc.qt.io/qt-6/deployment.html) |
| **Qt/Python, PySide6** | Mismo toolkit; Python puede acelerar iteración. Hay que gestionar event loop, tareas y tipos para que la sesión no dependa de callbacks dispersos. | **Bindings oficiales** de Qt, incluidas `QLowEnergyController` y `QLowEnergyService`: misma familia de backends, no un transporte BLE independiente. Requiere probar la distribución elegida. [PySide QtBluetooth](https://doc.qt.io/qtforpython-6/PySide6/QtBluetooth/index.html) | `pyside6-deploy` usa Nuitka y produce directorio o ejecutable; siguen existiendo recursos y bibliotecas. Inferencia: Python + Qt + posible Swift aumentan combinaciones de empaquetado y diagnóstico. [pyside6-deploy](https://doc.qt.io/qtforpython-6/deployment/deployment-pyside6-deploy.html) |
| **Avalonia/.NET** | C#/AXAML, MVVM, controles dibujados con Skia y vistas compartidas; buen encaje conceptual para estado observable e inspectores. No reutiliza vistas SwiftUI. | Avalonia identifica Bluetooth como integración específica; **no aporta central GATT común**. `InTheHand.BluetoothLE`, externo a Avalonia, incluye Windows y Linux/BlueZ en su proyecto actual; su cobertura Godox debe auditarse. [Arquitectura Avalonia](https://docs.avaloniaui.net/docs/fundamentals/cross-platform-architecture), [backends InTheHand](https://github.com/inthehand/32feet/blob/main/InTheHand.BluetoothLE/InTheHand.BluetoothLE.csproj) | .NET permite publicación con runtime incluido y destinos por sistema/arquitectura; falta elegir instalador y actualizaciones. Inferencia: buena productividad si se domina C#, a cambio de mantener la capa BLE y sus diferencias. [Despliegue .NET](https://learn.microsoft.com/en-us/dotnet/core/deploying/) |
| **Tauri/Rust** | UI HTML/CSS/JS y núcleo Rust: productivo para experiencia web. Usa WebView2 en Windows y WebKitGTK en Linux; hay que revisar teclado, accesibilidad y renderizado en ambos. [Procesos Tauri](https://v2.tauri.app/concept/process-model/) | BLE en **Rust**, mediante `btleplug` comunitario o adaptadores nativos; no necesita Web Bluetooth. `btleplug` declara discovery, conexión, read/write y suscripciones en Windows/Linux. Tauri no convierte esa biblioteca en BLE oficial propio. [btleplug](https://github.com/deviceplug/btleplug) | Tauri documenta instaladores Windows y formatos Linux. Hay que mantener Rust, frontend y WebViews; incorporar Swift suma otro componente. [Distribución Tauri](https://v2.tauri.app/distribute/) |
| **Flutter/Dart** | Escritorio Windows/Linux soportado oficialmente; UI compartida y plugins extensibles. El diseño de escritorio y la integración de bandeja necesitan trabajo explícito. [Flutter desktop](https://docs.flutter.dev/platform-integration/desktop) | BLE depende de **plugins**, no del soporte desktop del framework. `universal_ble` declara ambos sistemas y operaciones centrales; por ejemplo, no ofrece lectura RSSI de dispositivo conectado en Windows/Linux. Esto no equivale a carecer de RSSI de anuncios. [universal_ble](https://pub.dev/packages/universal_ble) | Publica bundles con motor/recursos y dependencias; Windows admite MSIX o distribución propia y Linux requiere bibliotecas del sistema. Inferencia: Dart más plugins nativos aumenta puntos que verificar. [Windows](https://docs.flutter.dev/platform-integration/windows/building), [Linux](https://docs.flutter.dev/platform-integration/linux/building) |

**Dos confusiones que cambian la evaluación:**

- `flutter_blue_plus` actualmente declara Linux, pero remite Windows a `flutter_blue_plus_winrt`, mantenido por otra persona. No es una garantía uniforme para ambos escritorios. `flutter_reactive_ble` publicado como **5.6.0** declara Android/iOS; no demuestra soporte Windows/Linux. El README de desarrollo menciona macOS, lo que tampoco demuestra esos dos destinos. [FlutterBluePlus](https://github.com/chipweinberger/flutter_blue_plus), [paquete reactive BLE](https://pub.dev/packages/flutter_reactive_ble)
- **Avalonia no es .NET MAUI.** La lista oficial de MAUI no incluye escritorio Linux; tampoco debe suponerse que Maui.Essentials resuelva Bluetooth/Linux para Avalonia. [Plataformas MAUI](https://learn.microsoft.com/en-us/dotnet/maui/supported-platforms), [límites Avalonia](https://docs.avaloniaui.net/docs/fundamentals/cross-platform-architecture)

## Motor Swift: decisión separada de la UI

Las opciones de integración propuestas son hipótesis de arquitectura; este informe no demuestra que el motor actual compile fuera de Apple.

1. **Proceso Swift con IPC local:** UI, motor y adaptador BLE intercambian comandos/eventos por un contrato versionado. Puede conservar reglas existentes sin exponer objetos Swift, pero exige compilación portable, supervisión del proceso, cancelación, orden, cierre y distribución del runtime. Tauri documenta empaquetar un ejecutable externo por arquitectura; esa capacidad no vuelve portable el ejecutable Swift. [Sidecars Tauri](https://v2.tauri.app/develop/sidecar/)
2. **Biblioteca Swift con puente C:** evaluar FFI desde C++, P/Invoke de .NET o Dart FFI. Requiere una API explícita de handles, bytes, callbacks, memoria e hilos; no se presupone ABI interoperable de objetos Swift. Avalonia y Flutter documentan interoperabilidad C. [Interop Avalonia](https://docs.avaloniaui.net/docs/app-development/native-interop), [FFI Flutter/Linux](https://docs.flutter.dev/platform-integration/linux/building)
3. **Portar el motor a otro lenguaje:** facilita integración en su stack, pero crea coste de equivalencia y posible divergencia con Apple. La elección de UI no justifica por sí misma esta reescritura.

**Inferencia:** con paridad completa, conservar un motor reutilizable merece investigación antes de escoger lenguaje. Sea IPC o FFI, debe haber **un único dueño de sesión, cola y recuperación**; la UI no debe confirmar escrituras ni duplicar reglas del protocolo.

## Puertas de aceptación y descarte

La evidencia del repositorio exige mucho más que escanear y mover potencia: suscripciones FFF4/FEC8, FFF1 sin respuesta, PWOK/Sync, A0 previo a A1, write GATT con respuesta seguido por FEC8, heartbeat y recuperación durable. [Contrato de Estrobo en el baseline](https://github.com/loomitz/estrobo/blob/bf98e82637b562fff732ca82d7a92a66fe984d66/docs/BLUETOOTH-CONNECTION.md)

Antes de decidir, cada candidata final debe demostrar:

- **Transporte:** distinguir write con/sin respuesta, acuse GATT y notificación; preservar orden ante notificación temprana, timeout y desconexión. Repetir con transmisores/firmware y adaptadores reales Windows/Linux.
- **Paridad de producto:** Canales/Inspector/Matriz, Multi, presets, bandeja, reconexión, códigos guardados y journal; completar el inventario contra una versión macOS congelada.
- **Persistencia y ciclo de vida:** reiniciar durante entrega incierta, recuperar sólo el transmisor correcto y probar suspensión, Bluetooth apagado y cierre desde bandeja.
- **Distribución:** instalar en máquinas limpias; verificar BlueZ/D-Bus y permisos del formato Linux elegido, además de dependencias gráficas y WebView cuando aplique. `btleplug` advierte que BlueZ combina filtros de distintos clientes: hay que filtrar resultados también en la app. [Caveats btleplug](https://github.com/deviceplug/btleplug)
- **Mantenimiento:** aceptar versiones y propietarios de dependencias, diagnóstico y actualizaciones. Revisar licencias exactas de Qt/PySide, plugins BLE y empaquetadores antes de comprometer distribución; Qt Bluetooth ofrece alternativas LGPL/GPL/comercial. Esto queda como dependencia por resolver. [Licencias del módulo](https://doc.qt.io/qt-6/qtbluetooth-index.html)

Descartar una combinación si no permite demostrar estas condiciones o exige retirar funciones de la primera versión Windows. Ninguna prueba aislada de UI o BLE basta para afirmar paridad.
