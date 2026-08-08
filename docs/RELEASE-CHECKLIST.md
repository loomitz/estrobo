# Checklist de release beta

Este checklist es un gate, no una guía opcional. Un release permanece **draft** mientras cualquier punto aplicable esté pendiente. Nunca se publica con CI fallando, una slice ausente o sin smoke físico/limpio requerido. Desde `beta.3`, el contrato público es Developer ID + notarización + DMG; el carril autosignado queda congelado para las betas 1 y 2 históricas. El workflow Developer ID de Actions produce candidatos cifrados, no publica por sí mismo.

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

- [ ] `.gitignore` cubre `.DS_Store`, `Build/`, `Dist/`, `.swiftpm/`, `DerivedData/`, `*.af~lock~`, ZIP/DMG/ejecutables, `.p12`, `.p8`, `.key`, provisioning profiles y temporales de keychain.
- [ ] Lo staged no contiene builds, ejecutables, PoC/tests compilados, lockfiles, APKs o artefactos de terceros no publicables.
- [ ] No hay nombres de estación, PII, claves, certificados privados, contraseñas, tokens ni Códigos del radio.
- [ ] Las identidades públicas versionadas contienen sólo `estrobo-beta-signing.cer` + digest para betas 1/2 y `estrobo-developer-id-application.cer` + digest para beta 3+; nunca `.p12`, `.p8`, private key o password.
- [ ] `git diff --cached --check` pasa.
- [ ] `THIRD-PARTY-NOTICES.md` refleja cualquier dependencia o asset nuevo.

## 3. Pruebas locales sin hardware

```sh
make mac-prototype-check
make mac-prototype-test
make mac-prototype-universal
make mac-prototype-release-verify
make mac-prototype-package
make mac-prototype-developer-id-tools-test
```

- [ ] Todos los comandos terminan con código 0.
- [ ] Las pruebas usan códigos sintéticos y no inicializan Bluetooth real.
- [ ] El harness AppKit/SwiftUI cubre mouse-down, pausa mayor a 700 ms, drag y mouse-up.
- [ ] No se envían valores intermedios; mouse-up arma un solo deadline y sólo sale el valor final.
- [ ] Tokens concurrentes, final idempotente, regreso a baseline, Descartar, Manual, teclado/VoiceOver y cierre/cambio de vista pasan.
- [ ] Opt-in de recordar transmisor apagado, persistencia sólo tras `PWOK` + Sync, biblioteca plural, reconexión por UUID, migración del registro único de `beta.2`, olvido individual, validación y payload `Psub` compatible pasan.
- [ ] Selección con nombre/RSSI/sufijo UUID y nombres duplicados queda cubierta.
- [ ] La biblioteca conserva varios transmisores, migra el registro singleton de `beta.2`, actualiza por UUID sin duplicar, carga el Código del radio correcto y permite olvidar uno sin borrar los demás.
- [ ] El botón Multi junto a Beep es la única vía de activación/desactivación, no abre dropdown ni popover y muestra la consola inline únicamente mientras Multi está activo.
- [ ] Activar Multi convierte juntos los grupos activos compatibles; los no participantes quedan Off y aparecen desactivados mediante overlay sin aceptar edición de potencia/modelado.
- [ ] Los controles de participación agregan o quitan grupos compatibles, pero no pueden quitar el último; apagar desde el botón devuelve todos los grupos del workspace activos en Manual, sin restaurar TTL u Off previos.
- [ ] Multi cubre el dominio base `1–100`, potencia en pasos completos hasta `1/4`, persistencia retrocompatible, A0-only, orden A0 → A1 y alcance limitado al workspace.
- [ ] Las filas publicadas de la tabla potencia × frecuencia del AD400Pro II limitan y normalizan el conteo (incluidos `1/512` + `1 Hz` → `100`, `1/4` + `1 Hz` → `7` y `1/4` + `100 Hz` → `2`); `51–59 Hz` usa conservadoramente la fila `60–100 Hz` y aparece como tramo no publicado. Los demás modelos permanecen explícitamente no verificados y un conjunto mixto se marca como verificación parcial.
- [ ] La interfaz y el dominio de Multi excluyen HSS.

## 4A. Build autosignado histórico, sólo beta 1/2

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

## 4B. Build Developer ID vigente

Un candidato aprobado aquí sigue sin ser un release hasta completar el DMG, los smokes y la autorización de publicación.

- [ ] El workflow manual parte de un commit contenido en `origin/main`, sin crear ni requerir un tag.
- [ ] El certificado público Apple y su digest están versionados bajo nombres nuevos; los archivos históricos autosignados no cambiaron.
- [ ] El certificado encadena a Apple, su `OU` coincide con `ESTROBO_APPLE_TEAM_ID` y su digest coincide también con la variable protegida.
- [ ] El bundle se firma como `Developer ID Application` con Hardened Runtime y `Timestamp=` seguro; `Signed Time` por sí solo no satisface el gate.
- [ ] `TeamIdentifier`, certificado leaf, bundle ID, versión, build, ambas slices y macOS mínimo coinciden exactamente.
- [ ] Los entitlements efectivos son exclusivamente App Sandbox + Bluetooth; no contienen red, `get-task-allow` ni excepciones de Hardened Runtime.
- [ ] El ZIP temporal de notarización se envía una sola vez; se conserva el Submission ID y un timeout nunca dispara un reenvío automático.
- [ ] Un timeout conserva cifrados el ZIP exacto enviado y el submit result; el target de recuperación reanuda el mismo Submission ID sin ejecutar otro `submit`.
- [ ] El job de firma sólo acepta `github.run_attempt == 1`; un fallo posterior a submit se recupera por Submission ID, nunca mediante rerun del job ni un nuevo dispatch a ciegas.
- [ ] Submit, wait y log tienen el mismo Submission ID; Apple devuelve `Accepted` y el digest del log coincide con el ZIP enviado.
- [ ] El ticket se adjunta a la `.app`, `stapler validate` pasa y `spctl` reporta `Notarized Developer ID`.
- [ ] P12, `.p8` y keychain privado se eliminan y se comprueba su ausencia antes de cifrar o subir cualquier artefacto.
- [ ] La transferencia al host limpio y el candidato final se cifran con AES-256 y PBKDF2; Actions sólo recibe ciphertext y su checksum, nunca la app, ZIP, evidencia o directorio de distribución en claro.
- [ ] El ZIP de transferencia/candidato se crea desde la app stapled en un host limpio; nunca se publica el ZIP temporal enviado a Apple.

## 5. Paquete y procedencia

- [ ] El DMG público contiene únicamente `estrobo.app` y `Applications -> /Applications`, y usa un formato UDIF comprimido de sólo lectura.
- [ ] El DMG se firma con Developer ID, timestamp seguro e identificador `mx.loo.estrobo.dmg`; Apple acepta una solicitud de notarización distinta a la de la app y el ticket queda adjunto.
- [ ] `hdiutil verify`, `codesign`, `stapler`, Gatekeeper y un montaje read-only validan el DMG final y la app contenida.
- [ ] `SHA256SUMS` valida el DMG y los artefactos declarados después del stapling.
- [ ] `Dist/estrobo-${TAG}-manifest.json` contiene versión, tag, commit, `arm64` + `x86_64`, macOS mínimo y digest correctos.
- [ ] El manifiesto público registra Team ID, certificado, Submission IDs de app/DMG, estado `Accepted`, tickets adjuntos y digest final del DMG.
- [ ] Un manifiesto de candidato Developer ID usa schema v2, se identifica como `developer-id-candidate` y registra Team ID, certificado, Submission ID, digest de upload/log y ticket stapled.
- [ ] El `SHA256SUMS` del candidato cubre también submit, wait, log y metadata dentro de `notarization-evidence`.
- [ ] La app copiada desde el DMG conserva firma, ambas slices, plist y entitlements.
- [ ] El bundle extraído no contiene tests, fuentes, PoC, claves, lockfiles, `.DS_Store` ni builds viejos.
- [ ] Sólo se documenta una attestation de GitHub si existe realmente para el DMG exacto; una promoción manual no finge procedencia de tag.
- [ ] El checksum publicado se calculó sobre el asset exacto del release, no sobre una copia local diferente.

## 6. CI por arquitectura

- [ ] Job `macos-15` confirma `uname -m = arm64`.
- [ ] Job `macos-15-intel` confirma `uname -m = x86_64`.
- [ ] Cada job ejecuta check, test, build y `lipo "$BIN" -verify_arch "$EXPECTED_ARCH"`.
- [ ] CI normal usa `permissions: contents: read` y sólo acciones oficiales fijadas a SHA completo.
- [ ] Ambos checks obligatorios están verdes en el commit del tag.
- [ ] `origin/main` coincide con el commit local esperado.

## 7. Workflow de release

### Carril autosignado histórico

- [ ] `.github/workflows/release-beta.yml` es manual-only y acepta exclusivamente `v0.1.0-beta.1` o `v0.1.0-beta.2`; nunca escucha tags nuevos.
- [ ] El tag histórico es anotado; versión y archivo de release coinciden; el commit pertenece a `main`.
- [ ] Los únicos secrets de identidad privada usados son `ESTROBO_SIGNING_P12_BASE64` y `ESTROBO_SIGNING_P12_PASSWORD`; `SIGNING_IDENTITY` se deriva del certificado público versionado y cualquier secret legado `ESTROBO_SIGNING_IDENTITY` se eliminó de la configuración.
- [ ] La identidad se importa a un keychain temporal y su huella se compara antes de construir.
- [ ] El certificado recibe confianza `codeSign` sólo en el runner efímero de firma alojado por GitHub. El step `always()` elimina y comprueba la ausencia de P12, copias importadas y keychain con la clave privada; si el cleanup falla o no completa, ningún artefacto continúa hacia el release y cualquier residuo queda confinado a la VM efímera que destruye GitHub. El bundle ya firmado se verifica y empaqueta en un host limpio separado.
- [ ] Se construyen/verifican ambas slices y el bundle universal.
- [ ] El release se crea primero como **draft**.
- [ ] Los assets reales del draft se descargan y verifican de nuevo.
- [ ] El environment protegido `public-beta` exige aprobación humana.
- [ ] La variable protegida `PUBLIC_BETA_SMOKE_APPROVED_TAG` coincide exactamente con el tag actual; no se reutiliza una aprobación anterior.
- [ ] Release immutability está habilitada antes de publicar el primer prerelease.
- [ ] Falta de aprobación o smoke deja el draft intacto; el workflow no publica parcialmente.

### Carril Developer ID preparado

- [ ] `.github/workflows/developer-id-candidate.yml` sólo permite `workflow_dispatch`, usa `permissions: contents: read` y no contiene `gh release`, attestations ni un job de publicación.
- [ ] `developer-id-signing` y `developer-id-verification` limitan deployment a `main` protegida, exigen reviewer, impiden self-review y deshabilitan bypass administrativo cuando el plan lo permite; no se carga ningún secret antes de cerrar estas reglas.
- [ ] `ESTROBO_APPLE_TEAM_ID` y `ESTROBO_DEVELOPER_ID_CERT_SHA256` son variables de repositorio revisadas.
- [ ] P12/password y API key `.p8`/Key ID/Issuer ID sólo existen como secrets del environment protegido `developer-id-signing`.
- [ ] `ESTROBO_CANDIDATE_ARTIFACT_PASSWORD` contiene al menos 32 caracteres aleatorios y tiene el mismo valor en `developer-id-signing` y `developer-id-verification`; el segundo environment no recibe credenciales Apple.
- [ ] La API key es de equipo; no se configura una Individual API Key para `notarytool`.
- [ ] Firma, notarización y stapling ocurren en el runner efímero con secretos; el host limpio sólo descifra la app stapled y evidencia sanitizada, sin recibir P12 ni `.p8`.
- [ ] Diagnósticos de error sólo se cifran y suben después de que el cleanup privado pasó; ningún path de transferencia contiene `.p12`, `.p8`, key, PEM o keychain.
- [ ] Cada `upload-artifact` de este carril apunta exclusivamente a archivos `.enc` y `.sha256`; no existe subida de un path en claro.
- [ ] El resultado final es un artefacto cifrado y temporal de Actions; no crea draft, tag o release y no puede publicar.

### Promoción pública Developer ID

- [ ] El tag anotado apunta a un commit de `main` con CI arm64/Intel verde y no dispara el carril autosignado histórico.
- [ ] El draft contiene el DMG exacto ya firmado, notarizado y probado, su manifiesto y `SHA256SUMS`; no contiene ZIP temporal de notarización ni evidencia privada.
- [ ] Los assets del draft se descargan y sus digests coinciden antes de publicar.
- [ ] La autorización humana corresponde al tag y DMG exactos que pasaron los smokes.

## 8. Smoke en Macs limpios

Conserva la cuarentena original del DMG descargado.

- [ ] Apple Silicon: checksum, extracción, resultado de Gatekeeper correspondiente al carril, launch, versión y permiso Bluetooth.
- [ ] Intel: checksum, extracción, resultado de Gatekeeper correspondiente al carril, launch, versión y permiso Bluetooth.
- [ ] macOS mínimo 13.0 probado; un sistema anterior se rechaza como corresponde.
- [ ] Para el carril autosignado, Gatekeeper muestra la advertencia esperada, rechaza y se usa **Abrir de todos modos** sin confiar ni instalar el certificado.
- [ ] Para Developer ID, Gatekeeper acepta el DMG y la app con fuente `Notarized Developer ID`; **Abrir de todos modos** no forma parte del camino esperado.
- [ ] `--mock-radio` funciona sin Bluetooth ni comandos físicos en ambas arquitecturas.
- [ ] La actualización `beta.2` → `beta.3` conserva preferencias y la identidad del contenedor, y migra el único transmisor recordado a la biblioteca plural; se registra el baseline y el resultado real en Macs limpios, sin asumirlo a partir del bundle identifier.

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
- [ ] El draft contiene DMG, `SHA256SUMS` y manifiesto correctos; sólo incluye attestation si fue generada para ese DMG exacto.
- [ ] La aprobación humana de `public-beta` se otorgó después del smoke, no antes.
- [ ] `PUBLIC_BETA_SMOKE_APPROVED_TAG` sigue siendo idéntico al tag que va a publicarse.
- [ ] El draft se publica como **prerelease**, nunca como release estable.
- [ ] La página publicada muestra las notas de `docs/releases/<tag>.md`.
- [ ] Se vuelve a descargar el asset publicado y se repiten checksum, firma, slices, plist y entitlements.
- [ ] Se registran URL, tag/commit, jobs por arquitectura, digest, certificado, Macs/radios probados y gates pendientes.
- [ ] Se confirma si se usó hardware; una ejecución sólo local/CI nunca se presenta como prueba Bluetooth.

Si cualquier verificación posterior difiere, retira el anuncio y conserva evidencia para investigar; no reemplaces assets de un release inmutable.
