# Mantenimiento de actualizaciones macOS

[English signing contract](../release/signing/README.md) · [English catalog operations](../release/macos-updates/README.md) · [Soporte de usuario](../SUPPORT.md)

El actualizador pertenece sólo al shell macOS. La descarga pública sigue siendo `0.1.0-beta.4`, sin actualizador; iOS/iPadOS no incorporan este mecanismo. La primera release que lo incluya requerirá instalación manual verificada. La cualificación oficial utiliza la raíz EdDSA existente y los builds inmutables 5 y 6; su oferta temporal se retira mediante el catálogo vacío firmado de revisión 2. Los gates de v1 que esta prueba no acredita siguen pendientes. Este procedimiento documenta comandos disponibles; no concede permiso para firmar, notarizar, publicar o desplegar.

## Investigaciones y decisiones posteriores

Las investigaciones del 14 de octubre sobre [publicación y confianza](research/macos-update-distribution.md) y [compatibilidad y consentimiento](research/macos-updater-compatibility.md) se conservan como antecedentes históricos. Cada una incorpora un estado revisado el 24 de octubre, enlaza los contratos actuales y distingue decisiones resueltas, cualificación oficial acreditada y gates todavía pendientes. Sus alternativas originales no sustituyen esta guía, el [contrato funcional](../.scratch/macos-auto-update/spec.md) ni los contratos de [firma](../release/signing/README.md) y [catálogo](../release/macos-updates/README.md).

## Dependencia, builds y asignaciones

Sparkle 2.10.0 se obtiene del asset oficial exacto y se verifica contra SHA-256 `c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c`. La cache ignorada es `.build/Sparkle/2.10.0`; `SPARKLE_DIR` y `SPARKLE_ARCHIVE` permiten reutilización offline con la misma verificación de bytes/symlinks/permisos, sin aceptar una copia alterada por su número de versión. Requiere Python 3.12+ y Xcode completo.

```sh
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
export SPARKLE_DIR="$PWD/.build/Sparkle/2.10.0"
python3 scripts/macos-updater-artifacts.py dependency --directory "$SPARKLE_DIR"
make mac-prototype-check
make mac-prototype-updater-tools-test
make mac-prototype-build
make mac-prototype-universal
```

Estos checks locales y la compilación universal no acreditan firma/notarización, Intel/macOS mínimo en ejecución ni hardware Bluetooth. El [fixture del adaptador](../prototype/MacUpdaterAdapterCheck/README.md) ejecuta el servicio Swift real con una raíz efímera y explica sus límites; no usar esa raíz para distribución.

`release/macos-builds.json` es el ledger manual de asignaciones. Build **5**, versión `0.1.0`, canal `beta`, tag `v0.1.0-beta.5` conserva su draft original. Build **6** está publicado como prerelease inmutable de cualificación y queda retirado permanentemente del feed por la revisión 2. El próximo candidato debe usar un build superior. Antes de asignar otro, refrescar refs y revisar ledger/Info.plist/defaults/manifest de candidatos, incluyendo drafts y asignaciones no publicadas:

```sh
git status --porcelain=v1 --untracked-files=all
git worktree list --porcelain
git fetch --prune origin
git fetch --tags origin
gh api --paginate 'repos/loomitz/estrobo/releases?per_page=100' \
  --jq '.[] | [.tag_name, .draft, .prerelease, .target_commitish] | @tsv'
```

Elegir un entero superior al máximo global asignado, aun si un candidato no se publicó; no reciclarlo. Actualizar/revisar ledger, metadata del plist y defaults del Makefile, congelar el commit en main y obtener CI arm64/x86_64. No hay un comando `reserve`.

El marketing version conserva tres componentes numéricos; el canal es `EstroboUpdateChannel=beta|stable`, nunca inferido de tag/latest o una preferencia. Beta usa `vVERSION-beta.BUILD`. Estable correctiva usa `vVERSION+build.BUILD`, permitiendo el mismo marketing version con build superior; `vVERSION` sólo es válido si se asignó explícitamente como tag inicial convencional. No confundir ejemplos con reservas.

```sh
python3 scripts/macos-updater-artifacts.py metadata \
  --version "$VERSION" --build "$BUILD_NUMBER" \
  --channel "$UPDATE_CHANNEL" --tag "$TAG" --distribution
```

## Claves, firma y notarización

`SPARKLE_PUBLIC_ED_KEY` es la parte pública externa aprobada; CI utiliza la variable pública `ESTROBO_SPARKLE_PUBLIC_ED_KEY`. La privada EdDSA pertenece al mantenedor, permanece en un account Keychain existente y necesita backup cifrado offline cuya recuperación esté demostrada. La cualificación utilizó la raíz existente; no acredita su backup ni recuperación. No usar claves de tests para distribución. Developer ID y credenciales notariales son autoridades separadas. No crear/exportar claves, poner credenciales en Git/logs o sustituir los certificados históricos beta 1/2.

El lookup oficial de la parte pública es de sólo lectura:

```sh
test "$("$SPARKLE_DIR/bin/generate_keys" --account "$EDDSA_ACCOUNT" -p)" = "$SPARKLE_PUBLIC_ED_KEY"
```

No ejecuta generación ni prueba el backup. La ausencia de raíz válida bloquea distribución antes de firmar; desarrollo puede compilar con actualizaciones no configuradas.

El [carril local de firma](../release/signing/README.md#single-maintainer-local-keychain-lane) conserva fuente limpia `HEAD == origin/main`, tag ausente, CI exacta y aprobación declarada del mantenedor. Con los inputs reales cargados de forma segura y autorización para ese candidato:

```sh
make mac-prototype-developer-id-local-source-verify
make mac-prototype-developer-id-local-release
make mac-prototype-developer-id-local-notarize-existing
make mac-prototype-developer-id-dmg-create-existing COMMIT="$COMMIT"
make mac-prototype-developer-id-dmg-verify-existing COMMIT="$COMMIT"
```

La guía canónica detalla los directorios privados nuevos fuera del repo, variables de evidencia y credenciales. App y DMG tienen solicitudes notariales distintas; si ya existe ID, reanudar el mismo ZIP/DMG preservado, sin submit automático nuevo:

```sh
NOTARY_SUBMISSION_ID=EXISTING_APP_SUBMISSION_ID \
  make mac-prototype-developer-id-local-resume-notarization-existing
DMG_NOTARY_SUBMISSION_ID=EXISTING_DMG_SUBMISSION_ID COMMIT="$COMMIT" \
  make mac-prototype-developer-id-dmg-resume-existing
```

No reanudar el DMG con el ID de app. En distribución Developer ID, los helpers/framework/host se firman explícitamente de dentro hacia fuera con Hardened Runtime y timestamp; entitlements y contenido permanecen en allowlists precisas. El DMG final stapled es exactamente el mismo para instalación manual y asistida. No publicar un ZIP alternativo ni deltas.

## De candidato firmado a catálogo aprobado

1. Completar firma/notarización/stapling del DMG, cargar el tuple exacto a draft y volver a descargar/verificar. Ejecutar clean-host, upgrade/persistencia y smokes físicos requeridos. Finalizar/verificar la aprobación local ligada a tag, commit y SHA del DMG. La [guía canónica](../release/signing/README.md) contiene comandos y variables; no marcar un smoke como pasado por un build o acuse de transporte.
2. Ejecutar `prepare` **antes de publicar/crear el tag**, con el checkout aprobado todavía limpio y los outputs/notas fuera del repo. Reutiliza el verificador de aprobación final y sus guards pre-tag. Si el tag ya existe, detenerse y resolver el estado con el contrato de release; no borrar/retaggear ni desactivar el guard.
3. Revisar el candidato firmado y su digest. Publicar la release exacta sólo con autorización separada, sin reemplazar sus assets inmutables.
4. Ejecutar `approve` después de publicación: verifica el feed y descarga cada oferta anónimamente, comprobando longitud/hash/EdDSA del DMG. Escribe una revisión **local** del source y conserva historia; no publica el feed.
5. Revisar/commitear ese source, construir el website, revalidar/serializar el despliegue autorizado y verificar públicamente firmas/bytes/estado/headers/retirada.

Inputs reales de catálogo, con la raíz pública y account existente ya configurados:

```sh
python3 scripts/macos-update-catalog.py prepare \
  --archive /PRIVATE/APPROVED/estrobo-v0.1.0-beta.5-macos-universal.dmg \
  --manifest /PRIVATE/APPROVED/estrobo-v0.1.0-beta.5-manifest.json \
  --checksums /PRIVATE/APPROVED/SHA256SUMS \
  --notes-en /PRIVATE/NOTES.en.txt --notes-es /PRIVATE/NOTES.es.txt \
  --account "$EDDSA_ACCOUNT" --sparkle-dir "$SPARKLE_DIR" \
  --output /PRIVATE/NEW/catalog-candidate

python3 scripts/macos-update-catalog.py approve \
  --candidate /PRIVATE/REVIEWED/catalog-candidate \
  --expected-feed-sha256 REVIEWED_64_HEX_SHA256 \
  --account "$EDDSA_ACCOUNT" --sparkle-dir "$SPARKLE_DIR"
```

El adaptador actual admite DMG completo hasta 64 MiB y notas de hasta 16,384 bytes UTF-8 por idioma. Las notas firmadas `estrobo:releaseNotesEn/Es` son texto autocontenido, sin recursos remotos automáticos. Mantener candidatos dentro de esos límites. El manifiesto/checksums final conserva su identidad; el commit editorial del catálogo puede ser posterior al commit de la app sin re-firmar el DMG.

Los fallos automáticos conservan un fallback de al menos 24 horas y plazos conocidos más largos entre reinicios. Preflight/descarga propios exponen status/Retry-After; un fallo posterior de Sparkle puede no exponerlos. No inferir headers desde mensajes localizados ni prometer conocer la respuesta oculta. La comprobación manual sigue disponible.

## Website, retirada y recuperación

`pnpm --dir website build` valida source firmado previamente aprobado y estado público fresco, sin adquirir la clave privada. Los digests verificados no sustituyen la firma hecha al aprobar. Appcast/state tienen `Cache-Control: no-cache, max-age=0, must-revalidate`, sin `stale-if-error`. `site` usa User-Agent honesto `EstroboCatalogVerifier/1.0`; sólo un 404 inicial permite bootstrap y los errores de red no permiten rollback. `--published-state FILE` sólo acepta operacionalmente un estado recién obtenido o un fixture aislado, nunca una copia vieja para eludir frescura.

La protección monotónica ocurre durante el build; **no existe CAS ni lock de infraestructura**. Serializar promoción/retirada y uploads editoriales, revalidar justo antes de desplegar, no subir dist viejo y verificar después el feed/state público, firmas, bytes exactos y headers finales. El [README del website](../website/README.md) describe el despliegue separado. La configuración local de headers no prueba cache/CDN reales y no promete propagación instantánea.

Para retirar una oferta, producir/revisar un candidato nuevo y aprobar/desplegar una revisión superior conservando archivos e historia:

```sh
python3 scripts/macos-update-catalog.py withdraw \
  --build BUILD_TO_RETIRE --reason 'REVIEWED_RETIREMENT_REASON' \
  --account "$EDDSA_ACCOUNT" --sparkle-dir "$SPARKLE_DIR" \
  --output /PRIVATE/NEW/withdrawal-candidate
```

Usar después `approve` con el nuevo candidato/digest y repetir el recorrido del website y la [verificación pública](../release/macos-updates/README.md#promotion-and-withdrawal-commands). Una descarga previa exige comprobar elegibilidad fresca antes de instalar; una retirada no deshace una instalación ya comprometida.

Preferir corrección hacia delante con build mayor. Downgrade no acredita compatibilidad inversa de datos/Keychain. Ante aprobación local parcial, inspeccionar el candidato y `history/REVISION`; no cambiar hashes, borrar historia o volver a unconfigured. No existe `resume` de catálogo.

Si se pierde la privada EdDSA, restaurar/probar el backup aprobado. Con firma obligatoria y expiración cero, esperar o servir un feed inválido no recupera clientes. Si no se puede restaurar, se necesita una nueva instalación manual firmada/verificada con nueva raíz y build mayor. Una rotación planificada requiere un puente probado antes de retirar confianza previa; no cambiar ambas raíces simultáneamente. Automatizar rotación/downgrade queda fuera de este MVP.

El [recorrido oficial 5→6](https://github.com/loomitz/estrobo/actions/runs/39912706540) registra la ejecución nativa por arquitectura y su verificación posterior de firma/notarización. Los resultados y capturas se conservan como evidencia acotada fuera de Git; no sustituyen los gates de Bluetooth/Godox físico, macOS 13, cuarentena/translocación desde navegador, permisos de administrador ni recuperación del backup de firma. Cada despliegue del feed exige verificar nuevamente sus bytes, firma, revisión y headers públicos. El ticket 17 conserva la aceptación integrada y revisión final; esta cualificación no aprueba la salida v1.
