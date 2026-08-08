export type Locale = "es" | "en";

export const localeRoutes = {
  home: {
    es: "/",
    en: "/en/",
  },
  guide: {
    es: "/guia/",
    en: "/en/guide/",
  },
} as const;

export const localeMeta = {
  es: {
    htmlLang: "es",
    ogLocale: "es_MX",
    languageName: "Español",
  },
  en: {
    htmlLang: "en",
    ogLocale: "en_US",
    languageName: "English",
  },
} as const satisfies Record<Locale, {
  htmlLang: string;
  ogLocale: string;
  languageName: string;
}>;
