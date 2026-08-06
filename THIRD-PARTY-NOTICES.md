# Avisos de terceros

## Inventario de esta versión

La aplicación Estrobo `0.1.0-beta.1` no declara dependencias mediante Swift Package Manager, CocoaPods o Carthage y no incluye frameworks, bibliotecas, APKs o firmware de terceros versionados dentro de su bundle público.

El código usa frameworks del sistema proporcionados por macOS/Xcode:

- AppKit
- SwiftUI
- Combine
- CoreBluetooth
- Foundation
- Darwin

Esos frameworks no se redistribuyen en este repositorio como copias de terceros y su uso está sujeto a los términos aplicables de Apple y de las herramientas de desarrollo instaladas por cada persona.

El repositorio contiene documentación de investigación con referencias a documentación pública de Apple, Godox y GitHub. Las referencias y nombres no incorporan sus páginas, aplicaciones, firmware ni binarios al proyecto.

## Marcas

Godox y los nombres de productos Godox pertenecen a sus respectivos titulares. Estrobo es un proyecto independiente y no está afiliado, patrocinado, aprobado ni mantenido oficialmente por Godox.

Apple, macOS, Xcode, AppKit, SwiftUI y CoreBluetooth pertenecen a sus respectivos titulares. La mención de una plataforma o API no implica afiliación.

## Licencia del repositorio

Este archivo no concede una licencia sobre Estrobo. El repositorio no incluye una licencia open-source; la ausencia es intencional por ahora.

## Al añadir componentes

Cualquier contribución que incorpore código, assets, fuentes, binarios o herramientas de terceros debe:

1. identificar claramente origen y versión;
2. demostrar que puede redistribuirse;
3. incluir el texto de aviso/licencia exigido;
4. actualizar este archivo;
5. evitar dependencias o artefactos no necesarios dentro del bundle.

No añadas APKs, firmware, certificados privados, claves o binarios de investigación al repositorio público.
