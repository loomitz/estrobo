// Generated into Pages advanced mode only for a signed qualification catalog.
// The replacement is supplied by the catalog builder, never a request parameter.
const expiresAt = "__ESTROBO_QUALIFICATION_EXPIRES_AT__";

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
    const asset = await env.ASSETS.fetch(request);
    const response = new Response(asset.body, asset);
    response.headers.set("Cache-Control", "private, no-store");
    response.headers.set("X-Content-Type-Options", "nosniff");
    return response;
  }
};
