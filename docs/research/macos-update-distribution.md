# Publicación y confianza de actualizaciones de Estrobo para macOS

Investigado: 2026-10-14, America/Mexico_City (consultas HTTP: 2026-10-15 UTC).
Base local: `91eeeb9f02ca8268dfb1908c4dcd85994c738be4`.
Tipo: investigación para wayfinder; alternativas y restricciones, sin elegir proveedor ni publicar software.

## Respuesta a la pregunta

GitHub Releases puede alojar los archivos de actualización y un appcast independiente puede seleccionar qué ofrecer.
Sparkle consume RSS enriquecido, no el JSON de Releases: usar la API exige transformar/publicar un appcast o construir otro cliente. [Sparkle][sparkle-start] [GitHub Releases][gh-releases]
Mantener separadas la identidad del archivo, su autenticidad y su elegibilidad permite retirar una oferta sin reemplazar el archivo.
Esta separación es una propuesta de contrato, no una decisión ya adoptada.

## Evidencia comprobada y límites

- El plist local declara `mx.loo.estrobo`, marketing `0.1.0`, build `4` y macOS mínimo `13.0`. [Plist exacto][local-plist]
- El workflow de candidato deriva `v<marketing>-beta.<build>` y rechaza tags ya existentes; no representa todavía un flujo estable. [Workflow exacto][local-workflow]
- El contrato local exige app y DMG firmados, notarizados y stapled; calcula hashes después de stapling y verifica los bytes descargados del draft antes de publicar. [Promoción existente][local-signing]
- La API pública consultada devuelve beta.4 con `prerelease=true`, `immutable=true`, DMG de `6402463` bytes y SHA-256 `ca9cfbeddba9a63ddbcf3058c3b250097f33e852ebe304f2305c6b34cffcc337`. [Release observada][estrobo-release]
- Una petición HEAD al DMG siguió redirects y terminó en `release-assets.githubusercontent.com`, HTTP 200 y esa longitud; no descargó ni verificó el binario.
- Sparkle estable vigente observado: **2.10.0**, publicado el 13 de septiembre de 2026; commit `eef1a539a373c1f1a320624b1130fc5de7b2e100`; requiere macOS 12+. [Release oficial][sparkle-release]
- Las fuentes de código siguientes están fijadas a ese commit. Las páginas de documentación son vivas: revalidarlas al fijar la dependencia.
- No se inspeccionaron llaveros, secretos ni infraestructura privada. No se acredita hosting de feed, integración, recuperación de claves ni instalación real.

## Opciones de metadata y alojamiento

| Alternativa | Qué aporta | Responsabilidad o límite |
| --- | --- | --- |
| Appcast estático en GitHub Pages; archivos en Releases | Pages publica archivos estáticos desde un repo; Sparkle usa una URL HTTPS estable. | Configurar Pages sería trabajo posterior. Feed pequeño; binarios en Releases para reducir consumo de Pages. [Pages][gh-pages] [Límites][gh-pages-limits] |
| Appcast estático en otro hosting HTTPS; archivos en Releases | Conserva el mismo protocolo y separa control de ofertas de archivos. | Elegir operador, dominio, caché y permisos de publicación. No hay proveedor seleccionado. [Formato Sparkle][sparkle-publish] |
| API de Releases como entrada de un generador de appcast | API expone flags, tags, assets, tamaño y digest; puede alimentar publicación controlada. | La generación debe validar candidatos y producir RSS/firmas; la API por sí sola no reemplaza ese contrato. [API][gh-releases] [Appcast][sparkle-item] |
| API de Releases consultada directamente por la app | Puede construir selección propia usando datos públicos. | Exige cliente, paginación, autenticidad, instalación y recuperación propios; no es el feed nativo de Sparkle. Esta opción requiere decisión del mecanismo. [API][gh-releases] [Sparkle][sparkle-start] |

Pages publica como máximo 1 GB; tiene límite blando de 100 GB/mes y puede responder 429.
No debe interpretarse como disponibilidad garantizada ni alojarse allí el histórico de DMG por defecto. [Límites Pages][gh-pages-limits]

**Inferencia operativa:** el feed debe ser mutable y conservar una URL estable; el enclosure debe apuntar al asset de una versión exacta.
Un `appcast.xml` adjunto a una release inmutable tampoco puede reemplazarse, por lo que no sirve como único índice mutable de ofertas. [Inmutabilidad][gh-immutable]
No usar `latest/download` como identidad del archivo firmado: un alias que cambia puede entregar bytes que no corresponden a la firma/longitud del ítem.
Esto se deduce del contrato de firma del archivo y de los campos del enclosure. [Firma][sparkle-start] [Enclosure][sparkle-item]

## Archivo, firma y Apple

Sparkle soporta app bundles dentro de DMG, ZIP y otros archivos; el nombre de la app debe mantenerse y el empaquetado debe preservar symlinks.
La documentación recomienda `ditto` para ZIP y ofrece `generate_appcast` para generar metadata y firmas del archivo final. [Publicación][sparkle-publish]
Reutilizar el **DMG exacto** ya promovido es una opción; crear un ZIP para actualizaciones añade un artefacto distinto que requiere su propio hash, firma y validación.
Esto es una inferencia de la identidad por bytes, no una exigencia de crear dos formatos. [Validación Sparkle][sparkle-validator] [Promoción local][local-signing]

| Capa | Qué acredita | Qué no sustituye |
| --- | --- | --- |
| SHA-256 y longitud | Correspondencia de bytes con una referencia. | Una firma con raíz de confianza ya embebida; un atacante que cambia archivo y hash no queda autenticado. [API assets][gh-assets] [Firma Sparkle][sparkle-start] |
| EdDSA/Ed25519 de Sparkle | El archivo corresponde a la clave pública de confianza de la app. | Developer ID, notarización o autorización editorial de la oferta. [Validación][sparkle-validator] |
| Developer ID / code signing | Identidad y validez de código Apple; participa en continuidad de confianza durante rotaciones. | La firma EdDSA del archivo como contrato normal de publicación. [Validación][sparkle-validator] |
| Notarización y stapling | Apple examinó software y emitió ticket; stapling facilita comprobación sin conexión. | App Review, ausencia de bugs o validación de la política beta/estable. [Apple notarización][apple-notarize] [Stapling][apple-workflow] |

**Orden propuesto:** construir → firmar código → notarizar/staple app → empaquetar/finalizar DMG → notarizar/staple DMG → calcular hash/longitud → firmar EdDSA esos bytes → generar/verificar feed → verificar descarga → ofrecer.
El orden conserva la promoción local y evita invalidar una firma de archivo con modificaciones posteriores. [Contrato local][local-signing] [Archivo firmado][sparkle-publish]
ZIP puede notarizarse, pero Apple no permite stapling directamente al ZIP: se staplea la app y después se crea el ZIP de distribución. [Apple workflow][apple-workflow]

Sparkle ofrece `SUVerifyUpdateBeforeExtraction` desde 2.7.3 y feeds/notas firmados desde 2.9 mediante `SURequireSignedFeed`; este último exige el primero. [Configuración][sparkle-custom]
Son opciones disponibles en 2.10.0, no funciones hipotéticas; fijar su uso y política de fallos sigue pendiente. [Release vigente][sparkle-release]
Firmar el archivo autentica el código; firmar el feed también protege la información y enlaces mostrados al usuario.
Las ediciones de feed/notas firmados necesitan nuevas firmas. [Configuración][sparkle-custom] [Firma de feed][sparkle-start]

## Versiones y canales

Apple define `CFBundleVersion` como build numérico de una a tres partes y pide incrementarlo antes de distribuir un build macOS.
`CFBundleShortVersionString` es la versión visible de tres enteros; no conviene trasladar un tag `-beta` literalmente al plist. [Build Apple][apple-build] [Versión Apple][apple-marketing]
Sparkle compara `sparkle:version` con `CFBundleVersion`; la versión visible proviene de `sparkle:shortVersionString` / `CFBundleShortVersionString`. [API appcast][sparkle-item]
El flag `prerelease`, tag Git y fecha de publicación de GitHub no ordenan el build que Sparkle instala. [API][gh-releases] [Comparación implementada][sparkle-driver]

**Opciones de representación:**

- Contador global creciente entre beta y estable, manteniendo marketing separado. Ejemplo ilustrativo: beta build `5` → estable build `6` → siguiente beta build `7`.
- Esquema numérico por partes que garantice el mismo orden global. Necesita reglas escritas y prueba de transiciones; reiniciar el contador en cada marketing puede impedir actualizaciones.

Ambas son propuestas; **no hay numeración elegida**. La exigencia común es que todo sucesor deseado sea mayor según el comparador del cliente. [Apple build][apple-build] [Sparkle driver][sparkle-driver]
Si beta y estable conservan el mismo `CFBundleVersion`, no habrá actualización normal entre ellas: la comparación requiere ser estrictamente mayor. [Código exacto][sparkle-driver]

La política humana ya aprobada encaja en un feed con canal default=estable y `sparkle:channel=beta`; el cliente beta permite `beta` y recibe también default; el estable permite sólo default.
Sparkle no permite excluir el canal default y describe estos canales como ramas que vuelven a una release default más nueva. [Canales oficiales][sparkle-publish]
Alternativa: dos feeds; el beta debe incluir también las estables. Duplica la obligación de publicación coherente. [Feed alternativo][sparkle-publish]
Todavía hay que decidir si la preferencia beta persiste después de instalar una estable y cómo se permite salir voluntariamente de beta.
Salir de beta con un build superior al estable sólo permite esperar una estable posterior o recuperación manual; no equivale a downgrade automático. [Selección][sparkle-driver]

Para compatibilidad existen `minimumSystemVersion`, `maximumSystemVersion`, hardware `arm64` y, desde 2.9, `minimumUpdateVersion`.
Este último restringe build de origen; no confundirlo con `minimumAutoupdateVersion`, que controla instalación en segundo plano y puede mostrar interfaz. [API requisitos][sparkle-item]
**Propuesta:** conservar en el feed la última oferta compatible para cada población soportada y validar arm64/x86_64 y mínimo macOS del paquete exacto.
Un universal evita dividir arquitectura hoy; elevar mínimos exige revisar alcance, metadata y pruebas. [Plist actual][local-plist] [Filtrado Sparkle][sparkle-driver]

## Releases API, redirects, caché y disponibilidad

`/releases/latest` excluye prereleases/drafts y tiene semántica propia de “latest”; no sirve para descubrir betas ni como comparador de builds.
El listado de releases requiere tratar paginación y filtrar explícitamente drafts, elegibilidad y archivos; no asumir que la primera fila es el candidato correcto. [API][gh-releases] [Buenas prácticas][gh-best]
La API admite lectura pública sin token. Límite primario anónimo: 60 peticiones/hora por IP, compartido por usuarios detrás de una NAT. [API][gh-releases] [Límites][gh-rates]
Respuestas 403/429 requieren respetar `Retry-After`/reset y backoff; nunca mostrarlas como “ya estás actualizado”. [Límites][gh-rates]
GitHub documenta ETag/Last-Modified y 304; la exención de cuota para 304 sólo se promete con autenticación correcta.
No justificar un token embebido en la app para eludir cuotas; esa sería una credencial recuperable por sus destinatarios. [Condicionales][gh-best]

El endpoint de binario puede responder 200 o 302; usar el `browser_download_url` exacto y tolerar redirects HTTPS. [Descarga de assets][gh-assets]
La URL final firmada del CDN observada es temporal: no guardarla como enclosure ni registrar su query de autorización.
La observación HEAD acredita sólo acceso en este momento, no un dominio/CDN fijo ni garantías futuras.
Sparkle 2.10.0 solicita feeds/notas ignorando caché local; su código advierte que eso no controla descargas persistentes de archivos. [Downloader exacto][sparkle-download]
**Inferencia:** definir latencia de retirada y pruebas con caché CDN real; la política del cliente no permite prometer retirada instantánea.

## Retirar una oferta, recuperar y custodiar claves

Una release inmutable impide cambiar/eliminar assets o mover el tag; GitHub permite editar notas/título y flags prerelease/latest.
Eliminar la release no permite reutilizar el tag. Esos flags editables no son una firma de elegibilidad. [GitHub inmutabilidad][gh-immutable]
**Propuesta de retirada:** quitar el ítem defectuoso del feed (y re-firmarlo si aplica), conservar bytes/evidencias, publicar aviso y preparar una corrección con build mayor.
No retaggear ni reemplazar DMG. Si se eligiera API directa, haría falta además una lista de elegibilidad/retirada verificable; cambiar “latest” no retira todas las rutas. [Inmutabilidad][gh-immutable] [Selección][sparkle-driver]
Quitar el ítem impide futuras selecciones tras obtener el feed nuevo; no desinstala versiones instaladas ni acredita cancelar un archivo ya descargado.
La revisión del flujo de instalación pendiente debe fijar cómo tratar esa carrera; esta investigación no probó un kill switch.
Sparkle selecciona únicamente versiones mayores: revertir cambios de código con un **nuevo build mayor** es una recuperación hacia delante, distinta de reinstalar un binario viejo. [Código de selección][sparkle-driver]
Revertir código no garantiza compatibilidad inversa de datos/configuración; definir respaldos y pruebas antes de prometer rollback.

La clave EdDSA privada es distinta de Developer ID y de credenciales notariales; la app contiene sólo su clave pública.
`generate_keys` guarda la privada en Keychain; Sparkle aconseja protegerla y mantenerla fuera del servidor de distribución. [Custodia][sparkle-start]
El contrato deberá nombrar custodio, backup recuperable, acceso mínimo, recuperación ensayada y rotación; esta sesión no crea ni exporta claves.
Sparkle permite rotar una raíz manteniendo la otra: no cambiar EdDSA y Apple simultáneamente.
Con verificación previa a extracción, perder EdDSA requiere la vía DMG firmado por Developer ID para rotar; conservar ese camino debe decidirse antes de activarla. [Validación exacta][sparkle-validator]
Feeds firmados tienen un fallback por fallos prolongados (20 días por defecto; `0` lo desactiva), con información restringida: decidir ese compromiso explícitamente. [Configuración][sparkle-custom]
Si se pierden ambas raíces útiles, no prometer continuidad automática: documentar distribución e instalación manual verificadas como recuperación.

## Datos enviados y decisiones que quedan

Sin system profiling, Sparkle sigue usando un User-Agent con nombre/versión de la app y versión Sparkle; se envía al descargar feed, notas y archivo. [User-Agent exacto][sparkle-agent] [Downloader][sparkle-download]
Profiling añade por GET datos de OS, CPU, modelo, RAM, idioma y app; debe permanecer desactivado y no añadirse información de Bluetooth en parámetros personalizados. [Profiling oficial][sparkle-profile]
GitHub recibe IP y datos normales de uso/petición y mantiene estadísticas de descarga de assets: “sin telemetría propia” no significa ausencia de registros del proveedor. [Privacidad GitHub][gh-privacy] [API assets][gh-assets]
**Propuesta:** notas autocontenidas sin imágenes/recursos remotos; JavaScript desactivado; inventario de dominios y captura de tráfico del candidato para verificar sólo actualizaciones. [Opciones de notas][sparkle-custom]
Las conexiones del sistema para Gatekeeper/notarización son otra capa: no confundirlas con el actualizador ni prometer control de todo el tráfico macOS. [Apple tickets][apple-notarize]

Falta decidir hosting del feed, una o dos URLs/canales, esquema monotónico, permanencia de beta, formato(s), política de firma de feed/fallback y operación de retirada/recuperación.
La evidencia permite tomar esas decisiones; no autoriza modificar beta.4, publicar feeds/claves/releases o asegurar que la app ya se autoactualiza.

## Fuentes primarias

[sparkle-start]: https://sparkle-project.org/documentation/
[sparkle-publish]: https://sparkle-project.org/documentation/publishing/
[sparkle-custom]: https://sparkle-project.org/documentation/customization/
[sparkle-item]: https://sparkle-project.org/documentation/api-reference/Classes/SUAppcastItem.html
[sparkle-profile]: https://sparkle-project.org/documentation/system-profiling/
[sparkle-release]: https://github.com/sparkle-project/Sparkle/releases/tag/2.10.0
[sparkle-driver]: https://github.com/sparkle-project/Sparkle/blob/eef1a539a373c1f1a320624b1130fc5de7b2e100/Sparkle/SUAppcastDriver.m#L575
[sparkle-validator]: https://github.com/sparkle-project/Sparkle/blob/eef1a539a373c1f1a320624b1130fc5de7b2e100/Sparkle/SUUpdateValidator.m
[sparkle-agent]: https://github.com/sparkle-project/Sparkle/blob/eef1a539a373c1f1a320624b1130fc5de7b2e100/Sparkle/SPUUserAgent%2BPrivate.m#L18
[sparkle-download]: https://github.com/sparkle-project/Sparkle/blob/eef1a539a373c1f1a320624b1130fc5de7b2e100/Sparkle/SPUDownloadDriver.m#L117
[gh-releases]: https://docs.github.com/en/rest/releases/releases
[gh-assets]: https://docs.github.com/en/rest/releases/assets
[gh-immutable]: https://docs.github.com/en/code-security/concepts/supply-chain-security/immutable-releases
[gh-pages]: https://docs.github.com/en/pages/getting-started-with-github-pages/what-is-github-pages
[gh-pages-limits]: https://docs.github.com/en/pages/getting-started-with-github-pages/github-pages-limits
[gh-rates]: https://docs.github.com/en/rest/using-the-rest-api/rate-limits-for-the-rest-api
[gh-best]: https://docs.github.com/en/rest/using-the-rest-api/best-practices-for-using-the-rest-api
[gh-privacy]: https://docs.github.com/en/site-policy/privacy-policies/github-general-privacy-statement
[apple-build]: https://developer.apple.com/documentation/bundleresources/information-property-list/cfbundleversion
[apple-marketing]: https://developer.apple.com/documentation/bundleresources/information-property-list/cfbundleshortversionstring
[apple-notarize]: https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution
[apple-workflow]: https://developer.apple.com/documentation/security/customizing-the-notarization-workflow
[local-plist]: https://github.com/loomitz/estrobo/blob/91eeeb9f02ca8268dfb1908c4dcd85994c738be4/prototype/EstroboMac/Info.plist#L26
[local-workflow]: https://github.com/loomitz/estrobo/blob/91eeeb9f02ca8268dfb1908c4dcd85994c738be4/.github/workflows/developer-id-candidate.yml#L31
[local-signing]: https://github.com/loomitz/estrobo/blob/91eeeb9f02ca8268dfb1908c4dcd85994c738be4/release/signing/README.md#L208
[estrobo-release]: https://api.github.com/repos/loomitz/estrobo/releases/tags/v0.1.0-beta.4
