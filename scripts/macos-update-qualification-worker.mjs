// Generated into Pages advanced mode only for a signed qualification catalog.
// The replacement is supplied by the catalog builder, never a request parameter.
const expiresAt = "__ESTROBO_QUALIFICATION_EXPIRES_AT__";
// Qualified feed bytes are a Worker binding, never a public static asset. Even
// a provider quota fallback must not expose an unrestricted appcast file.
const feed = Uint8Array.from(atob("__ESTROBO_QUALIFICATION_FEED_BASE64__"), c => c.charCodeAt(0));

export default {
  async fetch(request, env) {
    const path = new URL(request.url).pathname;
    if (path === "/updates/macos/state.json" || !path.startsWith("/updates/macos/")) {
      return env.ASSETS.fetch(request);
    }
    const allowed = (env.ESTROBO_UPDATER_QUALIFICATION_IPS || "").split(",").map(s => s.trim()).filter(Boolean);
    const ip = request.headers.get("CF-Connecting-IP");
    if (!["GET", "HEAD"].includes(request.method) || !ip || !allowed.includes(ip) ||
        !Number.isFinite(Date.parse(expiresAt)) || Date.now() >= Date.parse(expiresAt)) {
      return new Response("Not found", {status: 404, headers: {"Cache-Control": "private, no-store"}});
    }
    if (path !== "/updates/macos/appcast.xml") {
      return new Response("Not found", {status: 404, headers: {"Cache-Control": "private, no-store"}});
    }
    return new Response(request.method === "HEAD" ? null : feed, {headers: {
      "Content-Type": "application/xml; charset=utf-8", "Content-Length": String(feed.byteLength),
      "Cache-Control": "private, no-store", "X-Content-Type-Options": "nosniff"
    }});
  }
};
