import assert from "node:assert/strict";
import test from "node:test";

async function render() {
  const workerUrl = new URL("../dist/server/index.js", import.meta.url);
  workerUrl.searchParams.set("test", `${process.pid}-${Date.now()}`);
  const { default: worker } = await import(workerUrl.href);

  return worker.fetch(
    new Request("http://localhost/", {
      headers: { accept: "text/html" },
    }),
    {
      ASSETS: {
        fetch: async () => new Response("Not found", { status: 404 }),
      },
    },
    {
      waitUntil() {},
      passThroughOnException() {},
    },
  );
}

test("server-renders the Memury product site", async () => {
  const response = await render();
  assert.equal(response.status, 200);
  assert.match(response.headers.get("content-type") ?? "", /^text\/html\b/i);

  const html = await response.text();
  assert.match(html, /<title>Memury — Learning in context<\/title>/i);
  assert.match(html, /Learning shouldn(?:&apos;|&#x27;|')t/i);
  assert.match(html, /lose its context/i);
  assert.match(html, /Q Graph/);
  assert.match(html, /Whole conversation summarized/);
  assert.match(html, /https:\/\/canvas\.memury\.net\/login/);
  assert.match(html, /https:\/\/github\.com\/Spiderrrrrr-44\/memury-canvas/);
  assert.doesNotMatch(html, /SkeletonPreview|Building your site|MEDIA PENDING/);
});
