# Avisos de terceros

## Inventario de la beta pública 4

Estrobo `0.1.0-beta.4` no declara dependencias mediante Swift Package Manager, CocoaPods o Carthage y no incluye frameworks, bibliotecas, APKs o firmware de terceros versionados dentro del bundle distribuido.

El código usa frameworks del sistema proporcionados por macOS/Xcode:

- AppKit
- SwiftUI
- Combine
- CoreBluetooth
- Foundation
- Darwin

Esos frameworks no se redistribuyen en este repositorio como copias de terceros y su uso está sujeto a los términos aplicables de Apple y de las herramientas de desarrollo instaladas por cada persona.

El repositorio contiene documentación de investigación con referencias a documentación pública de Apple, Godox y GitHub. Las referencias y nombres no incorporan sus páginas, aplicaciones, firmware ni binarios al proyecto.

## Candidato macOS con actualizaciones asistidas

El candidato posterior a beta 4 incorpora [Sparkle 2.10.0](https://github.com/sparkle-project/Sparkle/releases/tag/2.10.0), obtenido del archivo oficial `Sparkle-2.10.0.tar.xz` con SHA-256 `c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c`. Se incluye el framework y únicamente sus auxiliares Installer XPC, Autoupdate y Updater.app. No se incorpora Sparkle a iOS/iPadOS ni a los módulos compartidos.

Su licencia permite redistribución bajo los avisos exigidos. El bundle macOS incluye en `Contents/Resources/Sparkle-LICENSE.txt` una copia exacta del `LICENSE` oficial completo: licencia de Sparkle y avisos de bsdiff/bspatch, sais-lite, Ed25519 y SUSignatureVerifier. El empaquetado copia ese texto desde la dependencia verificada y el verificador exige su digest SHA-256 `389a4e4e9a32f059775b13a06e25a591445ba229d2838d26dd3e7c0c45127cfe`. Estos términos corresponden a Sparkle y sus componentes; no conceden una licencia sobre Estrobo.

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
