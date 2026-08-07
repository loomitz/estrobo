# Checklist de release beta

Este checklist es un gate, no una guía opcional. Un release permanece **draft** mientras cualquier punto aplicable esté pendiente. Nunca se publica con CI fallando, una slice ausente o sin smoke físico/limpio requerido.

## 1. Preparación de versión

- [ ] `main` está limpia y sincronizada con `origin/main`; no hay WIP ajeno incluido.
- [ ] El tag propuesto tiene formato `vX.Y.Z-beta.N`, será anotado y apunta a un commit contenido en `main`.
- [ ] `CFBundleDisplayName` es `estrobo`.
- [ ] `CFBundleIdentifier` es `mx.loo.estrobo`.
- [ ] `CFBundleShortVersionString`, `CFBundleVersion`, tag, `VERSION` y `BUILD_NUMBER` coinciden.
- [ ] `LSMinimumSystemVersion` y ambas slices declaran macOS 13.0 o posterior.
- [ ] Existe `docs/releases/<tag>.md` sin secretos, códigos reales, PII ni compatibilidad no demostrada.
- [ ] `CHANGELOG.md`, `README.md`, `PRIVACY.md`, `SECURITY.md` y limitaciones están actualizados.
- [ ] Se documenta que el bundle identifier nuevo crea una identidad limpia y no migra preferencias del prototipo.

## 2. Higiene del repositorio

- [ ] `.gitignore` cubre `.DS_Store`, `Build/`, `Dist/`, `.swiftpm/`, `DerivedData/`, `*.af~lock~`, ZIP/DMG/ejecutables, `.p12`, `.key` y temporales de keychain.
- [ ] Lo staged no contiene builds, ejecutables, PoC/tests compilados, lockfiles, APKs o artefactos de terceros no publicables.
- [ ] No hay nombres de estación, PII, claves, certificados privados, contraseñas, tokens ni Códigos del radio.
- [ ] Sólo `release/signing/estrobo-beta-signing.cer` (X.509 DER) y `release/signing/estrobo-beta-signing.sha256` están versionados; nunca `.p12`, private key o password.
- [ ] `git diff --cached --check` pasa.
- [ ] `THIRD-PARTY-NOTICES.md` refleja cualquier dependencia o asset nuevo.

## 3. Pruebas locales sin hardware

```sh
make mac-prototype-check
make mac-prototype-test
make mac-prototype-universal
make mac-prototype-release-verify
make mac-prototype-package
```

- [ ] Todos los comandos terminan con código 0.
- [ ] Las pruebas usan códigos sintéticos y no inicializan Bluetooth real.
- [ ] El harness AppKit/SwiftUI cubre mouse-down, pausa mayor a 700 ms, drag y mouse-up.
- [ ] No se envían valores intermedios; mouse-up arma un solo deadline y sólo sale el valor final.
- [ ] Tokens concurrentes, final idempotente, regreso a baseline, Descartar, Manual, teclado/VoiceOver y cierre/cambio de vista pasan.
- [ ] Opt-in de recordar radio apagado, persistencia sólo tras `PWOK` + Sync, Olvidar, validación y payload `Psub` compatible pasan.
- [ ] Selección con nombre/RSSI/sufijo UUID y nombres duplicados queda cubierta.
- [ ] El botón Multi junto a Beep es la única vía de activación/desactivación, no abre dropdown ni popover y muestra la consola inline únicamente mientras Multi está activo.
- [ ] Activar Multi convierte juntos los grupos activos compatibles; los no participantes quedan Off y aparecen desactivados mediante overlay sin aceptar edición de potencia/modelado.
- [ ] Los controles de participación agregan o quitan grupos compatibles, pero no pueden quitar el último; apagar desde el botón devuelve todos los grupos del workspace activos en Manual, sin restaurar TTL u Off previos.
- [ ] Multi cubre el dominio base `1–100`, potencia en pasos completos hasta `1/4`, persistencia retrocompatible, A0-only, orden A0 → A1 y alcance limitado al workspace.
- [ ] Las filas publicadas de la tabla potencia × frecuencia del AD400Pro II limitan y normalizan el conteo (incluidos `1/512` + `1 Hz` → `100`, `1/4` + `1 Hz` → `7` y `1/4` + `100 Hz` → `2`); `51–59 Hz` usa conservadoramente la fila `60–100 Hz` y aparece como tramo no publicado. Los demás modelos permanecen explícitamente no verificados y un conjunto mixto se marca como verificación parcial.
- [ ] La interfaz y el dominio de Multi excluyen HSS.

## 4. Build universal y firma

Define rutas explícitas a la identidad de release y un directorio limpio. No uses firma ad hoc para el artefacto público.

```sh
lipo "$BIN" -verify_arch arm64 x86_64
codesign --verify --deep --strict --verbose=2 "$APP"
codesign -dvv "$APP"
(
  cd Dist
  shasum -a 256 -c SHA256SUMS
)
```

- [ ] `arm64` se compiló en runner/host arm64 y `x86_64` en runner/host Intel según el flujo autorizado.
- [ ] Sólo los ejecutables se combinaron con `lipo -create`; recursos y plist se ensamblaron una vez.
- [ ] El bundle universal final se firmó exactamente una vez con la identidad autosignada estable.
- [ ] `codesign -dvv` muestra Hardened Runtime (`runtime`).
- [ ] La huella SHA-256 del certificado de firma coincide exactamente con `release/signing/estrobo-beta-signing.sha256`, calculado sobre los bytes DER de `release/signing/estrobo-beta-signing.cer`.
- [ ] Los entitlements efectivos contienen App Sandbox y Bluetooth.
- [ ] No hay entitlement de cliente o servidor de red.
- [ ] Ambas slices declaran macOS mínimo 13.0.
- [ ] Arquitecturas, bundle ID, versión y build son correctos.
- [ ] `spctl` rechaza el bundle por no tener Developer ID; este resultado sólo se acepta después de que `codesign --verify` pase.
- [ ] Nadie instaló ni marcó como confiable manualmente el certificado autosignado.

## 5. Paquete y procedencia

- [ ] `Dist/estrobo-${TAG}-macos-universal.zip` se creó con `ditto --sequesterRsrc --keepParent`.
- [ ] `SHA256SUMS` valida el ZIP/artefactos declarados.
- [ ] `Dist/estrobo-${TAG}-manifest.json` contiene versión, tag, commit, `arm64` + `x86_64`, macOS mínimo y digest correctos.
- [ ] El ZIP extraído conserva firma, ambas slices, plist y entitlements.
- [ ] El bundle extraído no contiene tests, fuentes, PoC, claves, lockfiles, `.DS_Store` ni builds viejos.
- [ ] La attestation de GitHub corresponde al asset y commit esperados.
- [ ] El checksum publicado se calculó sobre el asset exacto del release, no sobre una copia local diferente.

## 6. CI por arquitectura

- [ ] Job `macos-15` confirma `uname -m = arm64`.
- [ ] Job `macos-15-intel` confirma `uname -m = x86_64`.
- [ ] Cada job ejecuta check, test, build y `lipo "$BIN" -verify_arch "$EXPECTED_ARCH"`.
- [ ] CI normal usa `permissions: contents: read` y sólo acciones oficiales fijadas a SHA completo.
- [ ] Ambos checks obligatorios están verdes en el commit del tag.
- [ ] `origin/main` coincide con el commit local esperado.

## 7. Workflow de release

- [ ] El tag es anotado; versión y archivo de release coinciden; el commit pertenece a `main`.
- [ ] El P12, su password y la identidad sólo existen en `ESTROBO_SIGNING_P12_BASE64`, `ESTROBO_SIGNING_P12_PASSWORD` y `ESTROBO_SIGNING_IDENTITY`.
- [ ] La identidad se importa a un keychain temporal y su huella se compara antes de construir.
- [ ] El certificado recibe confianza `codeSign` sólo temporalmente en el runner; esa confianza se retira antes de verificar/empaquetar el bundle ya firmado y el cleanup elimina keychain, trust y P12 incluso en error o cancelación.
- [ ] Se construyen/verifican ambas slices y el bundle universal.
- [ ] El release se crea primero como **draft**.
- [ ] Los assets reales del draft se descargan y verifican de nuevo.
- [ ] El environment protegido `public-beta` exige aprobación humana.
- [ ] La variable protegida `PUBLIC_BETA_SMOKE_APPROVED_TAG` coincide exactamente con el tag actual; no se reutiliza una aprobación anterior.
- [ ] Release immutability está habilitada antes de publicar el primer prerelease.
- [ ] Falta de aprobación o smoke deja el draft intacto; el workflow no publica parcialmente.

## 8. Smoke en Macs limpios

Conserva la cuarentena original del ZIP descargado.

- [ ] Apple Silicon: checksum, extracción, Gatekeeper, **Abrir de todos modos**, launch, versión y permiso Bluetooth.
- [ ] Intel: checksum, extracción, Gatekeeper, **Abrir de todos modos**, launch, versión y permiso Bluetooth.
- [ ] macOS mínimo 13.0 probado; un sistema anterior se rechaza como corresponde.
- [ ] La app muestra la advertencia esperada y no requiere confiar/instalar el certificado.
- [ ] `--mock-radio` funciona sin Bluetooth ni comandos físicos en ambas arquitecturas.
- [ ] Actualización N→N+1 conserva preferencias y la identidad del contenedor. Para beta.1, se registra un baseline reproducible que permita cerrar este gate con la siguiente beta; no se afirma aún el resultado N→N+1.

## 9. Smoke físico manual

Realízalo únicamente con una persona responsable del equipo y un baseline reversible conocido.

- [ ] Otra app libera primero la conexión exclusiva.
- [ ] Nombre, RSSI y sufijo UUID permiten seleccionar el radio correcto; duplicados no se auto-seleccionan.
- [ ] Código sintético/de prueba autorizado completa `PWOK`; el valor no aparece en logs, capturas ni reportes.
- [ ] La app deja claro antes de conectar que A0/A1 se sobrescribirán.
- [ ] Sync inicial confirma A0 por GATT y todos los A1 configurados por GATT + `FEC8` antes de **Listo**.
- [ ] Un cambio reversible de potencia se observa y se restaura.
- [ ] Modelado, Beep, Standby, Auto/TTL o Test sólo se marcan compatibles si el efecto físico se observó para ese modelo/firmware.
- [ ] Multi se prueba primero con la potencia común más baja, 2 destellos y 2 Hz, en un entorno ópticamente seguro y con tiempo de exposición suficiente.
- [ ] Con AD400Pro II, el máximo mostrado cambia de acuerdo con las filas publicadas de potencia × frecuencia y nunca permite un conteo superior; `51–59 Hz` aparece como «conservador · no publicado». Cambiar la matriz de modelos normaliza el conteo, impide descartar hacia un baseline incompatible y mantiene Test bloqueado hasta aplicar el ajuste seguro. Con cualquier otro modelo aparece el estado «no verificado»; una mezcla con AD400Pro II aparece como «verificado parcial».
- [ ] Multi no ofrece HSS y la consola indica «sin HSS» durante la prueba.
- [ ] La ráfaga Multi observada coincide con el conteo/frecuencia solicitados; después el botón global apaga Multi, todos los grupos de trabajo quedan activos en Manual y se verifica que ningún grupo externo al workspace recibió A1. Si no puede observarse, Multi permanece «no validado» para esa matriz.
- [ ] Mantener un slider más de 700 ms no genera payloads; sólo sale el valor final después de soltar.
- [ ] Desconexión y reconexión al mismo radio funcionan; otra app puede recuperar después el enlace.
- [ ] Un escenario de resultado incierto recupera el snapshot seguro antes de permitir nuevas escrituras.
- [ ] No se amplía la matriz de compatibilidad por nombre BLE, UUID o suposición.

## 10. Configuración del repositorio público

- [ ] Repositorio público correcto, Issues habilitados y `main` como default.
- [ ] Protección de `main`: checks arm64/Intel obligatorios y force-push prohibido.
- [ ] Private Vulnerability Reporting habilitado y probado desde **Security → Advisories**.
- [ ] Environment protegido `public-beta` configurado con revisores.
- [ ] Release immutability configurada.
- [ ] No existe otro repositorio remoto que vaya a sobrescribirse.

## 11. Publicación y verificación final

- [ ] Todos los gates anteriores aplicables están cerrados con evidencia enlazada.
- [ ] El draft contiene ZIP, `SHA256SUMS`, manifiesto y attestation correctos.
- [ ] La aprobación humana de `public-beta` se otorgó después del smoke, no antes.
- [ ] `PUBLIC_BETA_SMOKE_APPROVED_TAG` sigue siendo idéntico al tag que va a publicarse.
- [ ] El draft se publica como **prerelease**, nunca como release estable.
- [ ] La página publicada muestra las notas de `docs/releases/<tag>.md`.
- [ ] Se vuelve a descargar el asset publicado y se repiten checksum, firma, slices, plist y entitlements.
- [ ] Se registran URL, tag/commit, jobs por arquitectura, digest, certificado, Macs/radios probados y gates pendientes.
- [ ] Se confirma si se usó hardware; una ejecución sólo local/CI nunca se presenta como prueba Bluetooth.

Si cualquier verificación posterior difiere, retira el anuncio y conserva evidencia para investigar; no reemplaces assets de un release inmutable.
