import assert from "node:assert/strict";
import test from "node:test";
import {readFile} from "node:fs/promises";

const template = await readFile(new URL("../macos-update-qualification-worker.mjs", import.meta.url), "utf8");
async function worker(expiry) {
  return (await import("data:text/javascript;base64," + Buffer.from(template.replace("__ESTROBO_QUALIFICATION_EXPIRES_AT__", expiry).replace("__ESTROBO_QUALIFICATION_FEED_BASE64__", Buffer.from("signed bytes").toString("base64"))).toString("base64"))).default;
}
test("qualification requires exact edge IP, live policy and GET/HEAD; never trusts forwarded client headers", async () => {
  const gate = await worker(new Date(Date.now() + 60000).toISOString());
  let fetched = 0;
  const env = {ESTROBO_UPDATER_QUALIFICATION_IPS: "192.0.2.1, 2001:db8::1", ASSETS: {fetch: async () => { fetched++; return new Response("signed bytes", {headers: {"Cache-Control": "public, max-age=3600"}}); }}};
  for (const [ip, method, expected] of [["192.0.2.1", "GET", 200], ["2001:db8::1", "HEAD", 200], ["192.0.2.10", "GET", 404], ["", "GET", 404], ["192.0.2.1", "POST", 404]]) {
    const response = await gate.fetch(new Request("https://estrobo.app/updates/macos/appcast.xml", {method, headers: {"CF-Connecting-IP": ip, "X-Forwarded-For": "192.0.2.1"}}), env);
    assert.equal(response.status, expected);
    assert.equal(response.headers.get("Cache-Control"), "private, no-store");
    if (method === "GET" && expected === 200) assert.equal(await response.text(), "signed bytes");
  }
  assert.equal(fetched, 0); // The qualified feed has no static asset fallback.
  const request = new Request("https://estrobo.app/updates/macos/appcast.xml", {headers: {"CF-Connecting-IP": "192.0.2.1"}});
  assert.equal((await gate.fetch(request, {...env, ESTROBO_UPDATER_QUALIFICATION_IPS: ""})).status, 404);
  assert.equal((await (await worker("2000-01-01T00:00:00Z")).fetch(request, env)).status, 404);
  assert.equal((await (await worker("invalid")).fetch(request, env)).status, 404);
  for (const path of ["/updates/macos/state.json", "/"]) {
    assert.equal((await gate.fetch(new Request("https://estrobo.app" + path), env)).status, 200);
  }
});
