# Estrobo website

Sitio estático de Estrobo construido con Astro y publicado en
[`https://estrobo.app`](https://estrobo.app) mediante Cloudflare Pages.

## Desarrollo

Requiere Node.js `22.12.x` o `24.x` y pnpm.

```sh
pnpm install
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

## Publicación

El proyecto de Cloudflare Pages se llama `estrobo` y actualmente usa carga
directa. Después de validar el build, se publica el contenido de `dist/`:

```sh
pnpm build
npx wrangler pages deploy ./dist --project-name=estrobo --branch=main
```
