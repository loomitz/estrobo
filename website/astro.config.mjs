import { defineConfig } from "astro/config";

export default defineConfig({
  site: "https://estrobo.app",
  output: "static",
  trailingSlash: "always",
  devToolbar: {
    enabled: false,
  },
  build: {
    format: "directory",
  },
  vite: {
    server: {
      host: "0.0.0.0",
      allowedHosts: ["terminal.local"],
    },
  },
});
