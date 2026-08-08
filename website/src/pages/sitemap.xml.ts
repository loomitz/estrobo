import { localeRoutes } from "../i18n/config";

export const prerender = true;

const origin = "https://estrobo.app";
const routePairs = [localeRoutes.home, localeRoutes.guide];

const absoluteUrl = (path: string) => new URL(path, origin).toString();

const urls = routePairs.flatMap((pair) => {
  const alternates = [
    `<xhtml:link rel="alternate" hreflang="es" href="${absoluteUrl(pair.es)}" />`,
    `<xhtml:link rel="alternate" hreflang="en" href="${absoluteUrl(pair.en)}" />`,
    `<xhtml:link rel="alternate" hreflang="x-default" href="${absoluteUrl(pair.es)}" />`,
  ].join("");

  return [pair.es, pair.en].map((path) => `<url><loc>${absoluteUrl(path)}</loc>${alternates}</url>`);
});

export function GET() {
  const body = `<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9" xmlns:xhtml="http://www.w3.org/1999/xhtml">${urls.join("")}</urlset>\n`;

  return new Response(body, {
    headers: {
      "Content-Type": "application/xml; charset=utf-8",
    },
  });
}
