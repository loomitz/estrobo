# Preparación para Developer ID y notarización de Estrobo

Fecha de investigación: 2026-08-07
Alcance: distribución directa de una app macOS fuera de Mac App Store, con fuentes primarias oficiales de Apple vigentes al momento de la revisión. No se crearon cuentas, certificados, identificadores, perfiles ni credenciales.

Estado de implementación: el carril manual Developer ID descrito aquí ya quedó preparado en el repositorio, separado del workflow autosignado y sin autoridad de publicación. Sus artefactos de Actions se cifran porque el repositorio es público. La firma y notarización reales siguen bloqueadas hasta contar con membresía, certificado y credenciales Apple.

## Conclusión ejecutiva

Estrobo ya tiene una base adecuada para dar el salto: usa el identificador estable `mx.loo.estrobo`, activa Hardened Runtime, conserva App Sandbox y declara únicamente acceso Bluetooth. La membresía pagada desbloqueará la pieza que no se puede simular: un certificado **Developer ID Application** emitido por Apple y el acceso efectivo al servicio de notarización.

El trabajo no consiste sólo en reemplazar una identidad de firma. El pipeline actual firma la beta autosignada con `--timestamp=none`, comprueba que no sea Developer ID y exige que Gatekeeper la rechace. La vía Developer ID debe ser un contrato distinto:

1. firmar la app con `Developer ID Application`, Hardened Runtime y sello de tiempo seguro;
2. verificar firma, identidad, sello y entitlements;
3. crear un ZIP temporal de la app firmada y enviarlo con `notarytool`;
4. exigir estado `Accepted` y revisar el log;
5. adjuntar y validar el ticket sobre la `.app`;
6. crear desde esa app el ZIP público final;
7. calcular checksums y probar Gatekeeper sobre el artefacto final en Macs limpios.

Apple admite ZIP, DMG UDIF y paquetes Installer planos como entradas de notarización. Un ZIP se puede enviar, pero **no se puede staplear directamente**: Apple indica staplear el elemento que contiene y reconstruir después el ZIP. Fuentes: [Signing Mac Software with Developer ID](https://developer.apple.com/developer-id/), [Notarizing macOS software before distribution](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution) y [Customizing the notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow).

## 1. Inscripción en Apple Developer Program

### Requisitos previos

La inscripción requiere una Apple Account con autenticación de dos factores y que la persona tenga la mayoría de edad legal de su región. La membresía cuesta **99 USD al año**, en moneda local donde Apple la ofrece; el precio puede variar por región. Apple permite iniciar la inscripción desde la app Apple Developer o desde la web. Fuente: [Program enrollment](https://developer.apple.com/help/account/membership/program-enrollment/).

Hay que elegir correctamente el tipo de membresía antes de emitir activos de producción:

- **Individual o negocio de una sola persona:** Apple pide el nombre legal personal. No requiere D-U-N-S.
- **Organización:** debe ser una entidad legal, no un nombre comercial o DBA; Apple pide D-U-N-S, autoridad legal para vincular a la organización, correo del dominio laboral y un sitio web público y funcional. El D-U-N-S puede tardar hasta cinco días hábiles en emitirse y Apple puede tardar hasta dos días hábiles adicionales en recibir la actualización.

Fuentes: [Program enrollment](https://developer.apple.com/help/account/membership/program-enrollment/) y [D-U-N-S Number](https://developer.apple.com/help/account/membership/D-U-N-S/).

Después de que Apple verifica la información, se aceptan los acuerdos y se compra la membresía. La activación se confirma por correo; Apple indica contactar soporte si la confirmación no llega dentro de 24 horas después de procesarse la compra. Fuente: [Program enrollment](https://developer.apple.com/help/account/membership/program-enrollment/).

### Qué depende de la membresía pagada

- Apple exige membresía para solicitar, descargar y usar certificados de firma emitidos por Apple. Fuente: [Certificates](https://developer.apple.com/support/certificates/).
- El certificado Developer ID para una app sólo puede crearlo el **Account Holder**; Apple permite hasta cinco certificados Developer ID Application y cinco Developer ID Installer. Fuente: [Developer ID certificates](https://developer.apple.com/help/account/certificates/create-developer-id-certificates/).
- La notarización exige que el software esté firmado con un certificado Developer ID válido; una firma ad hoc, de desarrollo o autosignada no es aceptable. Por tanto, la notarización real también queda bloqueada hasta contar con membresía y certificado. Fuente: [Notarizing macOS software before distribution](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).
- El acceso inicial a App Store Connect API debe solicitarlo el Account Holder y Apple lo aprueba caso por caso; después, un Account Holder o Admin puede generar una API key de equipo. Fuente: [App Store Connect API](https://developer.apple.com/help/app-store-connect/get-started/app-store-connect-api).

Si la membresía vence, las apps ya firmadas con Developer ID pueden seguir descargándose, instalándose y ejecutándose. Sin embargo, cuando caduque el certificado será necesaria una membresía activa para obtener uno nuevo y firmar actualizaciones. Fuente: [Developer ID certificates](https://developer.apple.com/help/account/certificates/create-developer-id-certificates/).

## 2. Identidad de la app: bundle ID, App ID y perfiles

`mx.loo.estrobo` cumple la sintaxis que Apple prescribe para un bundle ID: formato reverse-DNS con caracteres alfanuméricos, guiones o puntos. El bundle ID identifica de forma única a la app en el sistema y ya es la identidad compartida por Beta 2 y Beta 3. Fuentes: [bundle ID](https://developer.apple.com/help/glossary/bundle-id/) y [Preparing your app for distribution](https://developer.apple.com/documentation/xcode/preparing-your-app-for-distribution).

La disponibilidad de `mx.loo.estrobo` en el equipo de Apple sólo podrá confirmarse cuando el portal permita registrarlo. Si se registra, debe ser un **Explicit App ID** y coincidir exactamente con `CFBundleIdentifier`. Apple describe el App ID como la identidad usada por un provisioning profile y como la lista permitida de capacidades de la app. Fuente: [Register an App ID](https://developer.apple.com/help/account/identifiers/register-an-app-id/).

Para la distribución directa actual no hace falta crear un registro de app en App Store Connect: ese registro pertenece a la distribución por TestFlight o App Store. Developer ID es precisamente la ruta de software descargado fuera de Mac App Store. Fuentes: [Preparing your app for distribution](https://developer.apple.com/documentation/xcode/preparing-your-app-for-distribution) y [Developer ID certificates](https://developer.apple.com/help/account/certificates/create-developer-id-certificates/).

Apple establece que una app macOS sin entitlements restringidos no necesita provisioning profile, incluso bajo Developer ID. Estrobo sólo declara actualmente `com.apple.security.app-sandbox` y `com.apple.security.device.bluetooth`, y Apple documenta Bluetooth como un permiso ordinario de App Sandbox. La lectura inicial es, por tanto, que **Estrobo no necesita un Developer ID provisioning profile en su alcance actual**. Esto debe confirmarse con el primer bundle firmado por Apple; si en el futuro se añade una capacidad restringida —por ejemplo, una que Apple autorice mediante perfil— habrá que registrar el App ID, habilitar la capacidad e insertar el perfil en `Contents/embedded.provisionprofile`. Fuentes: [TN3125: Inside Code Signing: Provisioning Profiles](https://developer.apple.com/documentation/technotes/tn3125-inside-code-signing-provisioning-profiles), [Configuring the macOS App Sandbox](https://developer.apple.com/documentation/xcode/configuring-the-macos-app-sandbox) y [Bluetooth entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.device.bluetooth).

## 3. Certificado y firma Developer ID

Para el ZIP actual se necesita **Developer ID Application**, que firma apps, ejecutables, bundles y otros componentes de código. **Developer ID Installer** sólo será necesario si más adelante se distribuye un paquete Installer plano `.pkg`; no es necesario para una `.app` dentro de un ZIP. Fuente: [Developer ID certificates](https://developer.apple.com/help/account/certificates/create-developer-id-certificates/) y [Resolving common notarization issues](https://developer.apple.com/documentation/security/resolving-common-notarization-issues).

El flujo manual apropiado para el build basado en `make` es:

1. el Account Holder genera una solicitud CSR y conserva la clave privada en un llavero controlado;
2. crea y descarga el certificado Developer ID Application desde Certificates, Identifiers & Profiles;
3. instala el `.cer` en el mismo llavero que contiene la clave privada;
4. firma primero cualquier código anidado y al final la app exterior;
5. usa la identidad exacta o su hash para evitar ambigüedad si hay más de una;
6. exporta una copia PKCS#12 protegida únicamente si el runner de CI realmente debe firmar.

Apple pide proteger tanto las credenciales como certificados y claves, y no compartirlos fuera de la organización. Fuentes: [Developer ID certificates](https://developer.apple.com/help/account/certificates/create-developer-id-certificates/), [Certificates](https://developer.apple.com/support/certificates/) y [Creating distribution-signed code for macOS](https://developer.apple.com/documentation/xcode/creating-distribution-signed-code-for-the-mac).

La firma manual de producción debe incorporar al menos estos elementos conceptuales:

```sh
codesign --force \
  --sign "$DEVELOPER_ID_IDENTITY" \
  --options runtime \
  --timestamp \
  --entitlements "$ENTITLEMENTS" \
  "$APP"
```

Los nombres anteriores son marcadores, no valores ni credenciales. Apple requiere `--timestamp` para Developer ID y `--options runtime` para el ejecutable principal. El sello de tiempo seguro permite demostrar que el certificado era válido al firmar; `Signed Time` local no lo sustituye. Fuentes: [Creating distribution-signed code for macOS](https://developer.apple.com/documentation/xcode/creating-distribution-signed-code-for-the-mac), [TN3161: Inside Code Signing: Certificates](https://developer.apple.com/documentation/technotes/tn3161-inside-code-signing-certificates) y [Resolving common notarization issues](https://developer.apple.com/documentation/security/resolving-common-notarization-issues).

### Hardened Runtime y entitlements

Apple sólo notariza apps macOS que tienen Hardened Runtime. Las excepciones de runtime debilitan protecciones concretas y deben limitarse a las estrictamente necesarias. Estrobo ya activa Hardened Runtime mediante `--options runtime` y no declara excepciones como JIT, memoria ejecutable sin firma, variables DYLD, desactivación de library validation o `get-task-allow`. Fuente: [Configuring the hardened runtime](https://developer.apple.com/documentation/xcode/configuring-the-hardened-runtime).

App Sandbox es opcional para una app distribuida fuera de Mac App Store, pero puede conservarse. Como Estrobo se comunica con un dispositivo Bluetooth, el entitlement `com.apple.security.device.bluetooth` es el permiso específico correcto dentro del sandbox, y el acceso sigue sujeto al consentimiento de macOS. Fuentes: [Preparing your app for distribution](https://developer.apple.com/documentation/xcode/preparing-your-app-for-distribution), [App Sandbox](https://developer.apple.com/documentation/security/app-sandbox) y [Bluetooth entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.device.bluetooth).

## 4. Credenciales admitidas por `notarytool`

`notarytool` admite dos rutas relevantes para este proyecto. `altool` dejó de ser aceptado para notarización el 1 de noviembre de 2023 y no debe formar parte del diseño nuevo. Fuente: [TN3147: Migrating to the latest notarization tool](https://developer.apple.com/documentation/technotes/tn3147-migrating-to-the-latest-notarization-tool).

### Opción A: Apple Account y contraseña específica de app

Se usan tres datos: Apple Account, Team ID y una contraseña específica de app. La Apple Account debe tener autenticación de dos factores para poder generar esa contraseña. Es preferible usar `notarytool store-credentials` para guardarla en un perfil de llavero y referenciar el perfil, en vez de escribir el secreto en scripts o argumentos persistentes. Fuentes: [Customizing the notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow), [TN3147](https://developer.apple.com/documentation/technotes/tn3147-migrating-to-the-latest-notarization-tool) y [Sign in with app-specific passwords](https://support.apple.com/en-us/102654).

Esquema sin valores reales:

```sh
xcrun notarytool store-credentials "$PROFILE" \
  --apple-id "$APPLE_ACCOUNT" \
  --team-id "$TEAM_ID"
```

Al omitir `--password`, la herramienta puede solicitarlo de forma segura en una sesión interactiva. En CI debe inyectarse desde el almacén de secretos del runner y nunca imprimirse.

### Opción B: App Store Connect API key de equipo

Se usan el archivo privado `.p8`, su Key ID y el Issuer ID. Apple permite descargar la parte privada una sola vez y exige almacenarla de forma segura; no debe entrar al repositorio, al cache, a logs ni a artefactos. La API key **de equipo** se genera en App Store Connect después de que el Account Holder solicita y obtiene acceso a la API. Fuentes: [App Store Connect API](https://developer.apple.com/help/app-store-connect/get-started/app-store-connect-api), [Creating API Keys for App Store Connect API](https://developer.apple.com/documentation/appstoreconnectapi/creating-api-keys-for-app-store-connect-api) y [TN3147](https://developer.apple.com/documentation/technotes/tn3147-migrating-to-the-latest-notarization-tool).

Esquema sin valores reales:

```sh
xcrun notarytool store-credentials "$PROFILE" \
  --key "$ASC_PRIVATE_KEY_PATH" \
  --key-id "$ASC_KEY_ID" \
  --issuer "$ASC_ISSUER_ID"
```

La documentación vigente de App Store Connect indica expresamente que una **Individual API Key no puede usar `notaryTool`**. Para automatización se debe usar una Team API Key, no una clave individual. Fuente: [Creating API Keys for App Store Connect API](https://developer.apple.com/documentation/appstoreconnectapi/creating-api-keys-for-app-store-connect-api).

### Elección recomendada

- Para la primera prueba manual: perfil de llavero con Apple Account + contraseña específica de app, porque no depende de que Apple apruebe antes el acceso a App Store Connect API.
- Para el workflow estable de GitHub Actions: Team API Key dedicada a notarización, descargada una sola vez, guardada en secretos protegidos y materializada sólo en el runner efímero. La contraseña específica de app queda como ruta manual de recuperación.

La clave privada del certificado Developer ID y la API key `.p8` son secretos diferentes y deben tener ciclos de vida, permisos y revocación separados.

## 5. Flujo exacto de notarización y stapling

Una vez disponible la membresía, el flujo de referencia debe ser:

```sh
# 1. Verificar la app ya firmada con Developer ID.
codesign --verify --deep --strict --verbose=2 "$APP"
codesign -dvv "$APP"
codesign -d --entitlements :- "$APP"

# 2. Crear un contenedor temporal aceptado por notarytool.
ditto -c -k --sequesterRsrc --keepParent "$APP" "$UPLOAD_ZIP"

# 3. Enviar y esperar el resultado.
xcrun notarytool submit "$UPLOAD_ZIP" \
  --keychain-profile "$PROFILE" \
  --wait

# 4. Descargar y conservar el log asociado al Submission ID.
xcrun notarytool log "$SUBMISSION_ID" \
  --keychain-profile "$PROFILE" \
  "$NOTARY_LOG"

# 5. Adjuntar y validar el ticket sobre la app, no sobre el ZIP.
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"

# 6. Crear desde la app stapled el ZIP público definitivo.
ditto -c -k --sequesterRsrc --keepParent "$APP" "$FINAL_ZIP"

# 7. Volver a verificar el producto que se publicará.
codesign --verify --deep --strict --verbose=2 "$APP"
spctl --assess --type execute --verbose=4 "$APP"
```

Todos los valores son marcadores. El pipeline debe capturar el Submission ID y detenerse salvo que el estado sea `Accepted`. Apple recomienda revisar el log incluso cuando la solicitud sea aceptada, porque puede contener advertencias corregibles. El ticket debe staplearse para que Gatekeeper pueda comprobar la notarización incluso sin conexión. Fuentes: [Customizing the notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow) y [Resolving common notarization issues](https://developer.apple.com/documentation/security/resolving-common-notarization-issues).

Los checksums, manifiesto y attestation deben generarse **después** del stapling y del ZIP final, ya que adjuntar el ticket modifica el producto. La comprobación de Gatekeeper esperada cambia de `rejected` a `accepted`, con procedencia de Developer ID notarizado. Apple documenta `codesign --verify --deep --strict` para la integridad y `spctl --assess --type exec` para evaluar la política del sistema. Fuente: [Resolving common notarization issues](https://developer.apple.com/documentation/security/resolving-common-notarization-issues).

## 6. Estado actual del repositorio

| Área | Estado actual | Lectura para Developer ID |
| --- | --- | --- |
| Bundle ID | `mx.loo.estrobo` en `Info.plist` y Makefile | Conservar; comprobar disponibilidad y registrarlo como Explicit App ID al activar la cuenta. |
| Versión | `0.1.0`, build `3` | Apta para Beta 3 si tag, notas y manifiesto coinciden. |
| Arquitecturas | `arm64` + `x86_64` | Ya existe build universal y gate por slice. |
| Hardened Runtime | `--options runtime` | Correcto; debe seguir presente en la firma Developer ID. |
| Timestamp | `--timestamp=none` en release autosignado; `--timestamp` en el carril Developer ID | Los contratos quedan separados sin cambiar los betas históricos. |
| Entitlements | App Sandbox + Bluetooth, sin red | Alcance mínimo adecuado; no añadir excepciones de runtime. |
| Privacidad Bluetooth | `NSBluetoothAlwaysUsageDescription` presente | Conservar y verificar en ambos idiomas durante smoke. |
| Firma | Identidad autosignada estable | No es aceptada por la notarización; sustituir sólo en la nueva ruta. |
| Verificador | Rechaza Developer ID en el carril autosignado; existe un verificador Developer ID separado | El nuevo carril exige identidad Apple, timestamp, ticket y aceptación. |
| Paquete | ZIP antes de publicación | Mantener ZIP, pero generar el definitivo después de staplear la app. |
| CI | Keychains efímeros separados, limpieza de P12/`.p8` y transferencia cifrada | Listo para recibir secretos protegidos cuando existan. |
| `.gitignore` | Excluye P12, `.p8`, claves PEM, provisioning profiles y keychains | Preparado para evitar material privado accidental. |

Este inventario proviene de `prototype/EstroboMac/Makefile`, `prototype/EstroboMac/Info.plist`, `prototype/EstroboMac/EstroboMac.entitlements`, `scripts/verify-macos-release.sh`, `scripts/package-macos-release.sh`, `.github/workflows/release-beta.yml`, `.gitignore` y `docs/RELEASE-CHECKLIST.md` tal como estaban el 2026-08-07.

## 7. Qué puede avanzarse antes de pagar

### Puede quedar listo sin membresía

1. **Decidir Individual frente a Organización.** Si será organización, comprobar o solicitar D-U-N-S, alinear nombre legal, correo de dominio, autoridad y sitio web.
2. **Preparar la Apple Account.** Activar 2FA, revisar dispositivos y teléfonos confiables y aceptar el Apple Developer Agreement gratuito. Esto no habilita distribución, pero evita fricción al inscribirse.
3. **Congelar la identidad técnica.** Mantener `mx.loo.estrobo`; documentar que un cambio posterior rompería continuidad de preferencias y permisos. Su disponibilidad en el portal sigue pendiente.
4. **Implementar el modo de release Developer ID sin secretos.** Parametrizar `--timestamp`, validación de Authority/TeamIdentifier/Timestamp, notary submit, log, staple, validación y repaquetado final. Todo debe fallar de forma cerrada cuando falte una credencial.
5. **Separar los contratos.** Conservar la ruta autosignada para artefactos históricos de Beta 3 y crear una ruta Developer ID explícita; no hacer que un mismo verificador acepte silenciosamente ambos estados.
6. **Preparar seguridad de CI.** Añadir `*.p8` a `.gitignore`, definir nombres de secretos sin valores, usar environments protegidos, limitar secretos al job efímero que firma/notariza y comprobar la eliminación de P12, `.p8`, keychain y archivos temporales antes de transferir la app.
7. **Preparar gates sin red Apple.** Tests del orden de operaciones, estados simulados `Accepted`/`Invalid`, extracción del Submission ID, fallo ante warnings definidos como bloqueantes, certeza de que checksum/manifest se calculan después del stapling y verificación del ZIP reextraído.
8. **Preparar dos smokes limpios.** Apple Silicon e Intel, conservando cuarentena, sin usar “Abrir de todos modos” como camino esperado para la versión notarizada.

La Apple Account y una contraseña específica de app se pueden preparar con 2FA antes de pagar, pero no conviene crear el secreto antes de necesitarlo: no sustituye la membresía, el Team ID ni el certificado Developer ID. Fuente: [Sign in with app-specific passwords](https://support.apple.com/en-us/102654).

### No puede cerrarse antes de la activación

- confirmar que Apple acepta `mx.loo.estrobo` para el equipo;
- crear el certificado Developer ID Application y comprobar su cadena real;
- conocer el Team ID definitivo dentro del pipeline;
- enviar una notarización real y obtener un Submission ID aceptado;
- staplear un ticket real;
- demostrar que Gatekeeper acepta el ZIP descargado como Developer ID notarizado;
- habilitar una Team API Key hasta que el Account Holder solicite y Apple apruebe el acceso correspondiente.

## 8. Runbook posterior a la activación

1. Confirmar membresía `Active`, acuerdos aceptados y Team ID.
2. Registrar `mx.loo.estrobo` como Explicit App ID si está disponible. Si no lo está, detener el release y decidir la migración de identidad antes de firmar públicamente.
3. Crear con el Account Holder un certificado **Developer ID Application** mediante CSR; no crear Developer ID Installer mientras el formato siga siendo ZIP.
4. Instalar certificado y clave privada; comprobar que `security find-identity -p codesigning -v` presenta una identidad válida.
5. Ejecutar una firma manual de prueba con Hardened Runtime y timestamp, manteniendo los dos entitlements actuales.
6. Verificar firma, TeamIdentifier, timestamp, entitlements, arquitecturas, versión y contenido del bundle.
7. Crear un perfil local de `notarytool` con Apple Account + contraseña específica de app y validar las credenciales sin registrarlas en el repositorio.
8. Enviar un artefacto de prueba, exigir `Accepted`, descargar el log, staple y validar.
9. Ejecutar `spctl` y un smoke descargado con cuarentena en una Mac limpia.
10. Solicitar acceso a App Store Connect API; una vez aprobado, crear una Team API Key dedicada y migrar CI a esa credencial.
11. Ejecutar la release completa en draft; descargar de nuevo el asset, repetir firma, ticket, Gatekeeper, slices, plist, checksum y smoke físico antes de publicar.

## 9. Gates de aceptación

La versión firmada no debe publicarse hasta que se cumpla todo lo siguiente:

- `codesign --verify --deep --strict` pasa sobre la app y sobre la copia extraída del ZIP final;
- `codesign -dvv` muestra `Developer ID Application`, TeamIdentifier esperado, Hardened Runtime y `Timestamp`, no sólo `Signed Time`;
- los entitlements efectivos son exactamente App Sandbox + Bluetooth y no contienen `get-task-allow` ni permisos de red;
- `notarytool` termina con `Accepted` y su log se archiva sin secretos;
- `stapler validate` pasa sobre la `.app` final;
- `spctl --assess --type execute` acepta el producto;
- el ZIP final fue construido después del stapling y sus checksums corresponden al asset publicado;
- los smokes con cuarentena pasan en Apple Silicon e Intel y macOS mínimo soportado;
- no quedan P12, `.p8`, contraseña, perfil de llavero temporal ni logs sensibles en workspace, cache o artefactos;
- Beta 2 → Beta 3 conserva preferencias y migra la biblioteca de transmisores con la misma identidad `mx.loo.estrobo`.

## Fuentes oficiales principales

- [Apple Developer Program enrollment](https://developer.apple.com/help/account/membership/program-enrollment/)
- [Developer ID certificates](https://developer.apple.com/help/account/certificates/create-developer-id-certificates/)
- [Signing Mac Software with Developer ID](https://developer.apple.com/developer-id/)
- [Creating distribution-signed code for macOS](https://developer.apple.com/documentation/xcode/creating-distribution-signed-code-for-the-mac)
- [Notarizing macOS software before distribution](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)
- [Customizing the notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow)
- [Resolving common notarization issues](https://developer.apple.com/documentation/security/resolving-common-notarization-issues)
- [TN3147: Migrating to the latest notarization tool](https://developer.apple.com/documentation/technotes/tn3147-migrating-to-the-latest-notarization-tool)
- [App Store Connect API](https://developer.apple.com/help/app-store-connect/get-started/app-store-connect-api)
- [Creating API Keys for App Store Connect API](https://developer.apple.com/documentation/appstoreconnectapi/creating-api-keys-for-app-store-connect-api)
- [TN3125: Inside Code Signing: Provisioning Profiles](https://developer.apple.com/documentation/technotes/tn3125-inside-code-signing-provisioning-profiles)
- [Configuring the hardened runtime](https://developer.apple.com/documentation/xcode/configuring-the-hardened-runtime)
