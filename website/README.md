# Estrobo website

Sitio estático de Estrobo construido con Astro y publicado en
[`https://estrobo.app`](https://estrobo.app) mediante Cloudflare Pages.

El sitio se publica en español en `/` y `/guia/`, con versiones inglesas
equivalentes en `/en/` y `/en/guide/`. Cada par declara canonical y `hreflang`
recíprocos; el sitemap se genera en `/sitemap.xml`.

## Desarrollo

Requiere Node.js `22.12.x` o `24.x`, pnpm `11.16.0` y Python `3.12+` para validar el catálogo aprobado.

```sh
pnpm install --frozen-lockfile
pnpm dev
pnpm check
pnpm build
```

Las capturas originales dentro de `screenshots/app/` provienen de una beta
pública ejecutada con el transporte sintético `--mock-radio`. Las copias WebP
optimizadas que usa el sitio están en `public/images/app/`. No inicializan
Bluetooth ni demuestran compatibilidad física.

Las ocho referencias de ImageGen usadas para definir la dirección visual están
en `design-references/`; los originales de las imágenes finales están en
`design-assets/` y el sitio sirve copias WebP optimizadas.

## Releases y catálogo de actualizaciones

`src/config/release.ts` conserva la descarga pública exacta `0.1.0-beta.4`, sin actualizador. La nueva implementación macOS y su catálogo aún no son una release pública; iOS/iPadOS no incluyen el mecanismo. El copy ES/EN mantiene esta distinción. No cambiar enlaces o versión hasta una promoción real aprobada.

`pnpm build` ejecuta `scripts/macos-update-catalog.py site` antes de Astro. Valida bytes firmados previamente aprobados, catálogo/retiradas y el estado público fresco; copia sólo el source canónico de `release/macos-updates`. Una fuente unconfigured no genera feed y sólo admite el bootstrap público 404 sin historia previa. Un error de red no permite borrar historial ni retroceder revisión. El User-Agent del verificador es `EstroboCatalogVerifier/1.0`; no simula ser un navegador.

La validación es de **build**, no un CAS de infraestructura. Las promociones y retiradas se serializan con despliegues editoriales, se revalida el estado justo antes de subir y se comprueba el resultado público después. No desplegar un dist construido antes de otra retirada. `--published-state FILE` sólo sirve para un estado recién obtenido o un fixture aislado, nunca para eludir frescura en producción. El generador escribe `_headers` completo y requiere revalidación para appcast/state, sin `stale-if-error`; cualquier nueva regla del sitio debe conservarse conscientemente allí.

Consulta [catálogo y comandos de promoción/retirada](../release/macos-updates/README.md) y [mantenimiento en español](../docs/ACTUALIZACIONES-MACOS.md). Raíz/backup, upgrades firmados/notarizados, plataformas y recorrido público siguen pendientes. Un build verde no autoriza release ni despliegue.

## Publicación

El proyecto de Cloudflare Pages se llama `estrobo` y actualmente usa carga
directa. Sólo tras autorización separada, build vigente, revalidación fresca y serialización, se publica `dist/`:

```sh
pnpm build
npx wrangler pages deploy ./dist --project-name=estrobo --branch=main
```
