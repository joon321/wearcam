import assert from "node:assert/strict";
import { once } from "node:events";
import test from "node:test";
import { createApp } from "../src/app.ts";
import type { Config } from "../src/config.ts";

const permanentKey = "permanent-provider-secret-for-isolation-test";
const config: Config = {
  apiKey: permanentKey,
  port: 8787,
  allowedOrigin: "*",
  model: "gpt-realtime",
  apiBaseUrl: "https://api.openai.test",
};

async function withServer(
  fetchMock: typeof fetch,
  run: (base: string) => Promise<void>,
) {
  const server = createApp(config, { fetch: fetchMock });
  server.listen(0, "127.0.0.1");
  await once(server, "listening");
  const address = server.address();
  assert(address && typeof address !== "string");
  try {
    await run(`http://127.0.0.1:${address.port}`);
  } finally {
    server.close();
    await once(server, "close");
  }
}

test("returns only the short-lived credential and never the permanent key", async () => {
  let authorization = "";
  let requestedUrl = "";
  let requestBody: unknown;
  await withServer(
    async (input, init) => {
      requestedUrl = input.toString();
      authorization = new Headers(init?.headers).get("authorization") ?? "";
      requestBody = JSON.parse(init?.body as string);
      return Response.json({
        value: "ek_short_lived",
        expires_at: 123,
        secret: permanentKey,
      });
    },
    async (base) => {
      const response = await fetch(`${base}/v1/realtime/client-secret`, {
        method: "POST",
      });
      assert.equal(response.status, 201);
      const text = await response.text();
      assert.deepEqual(JSON.parse(text), { value: "ek_short_lived" });
      assert.equal(text.includes(permanentKey), false);
    },
  );
  assert.equal(authorization, `Bearer ${permanentKey}`);
  assert.equal(
    requestedUrl,
    "https://api.openai.test/v1/realtime/client_secrets",
  );
  assert.deepEqual(requestBody, {
    session: {
      type: "realtime",
      model: "gpt-realtime",
      audio: { output: { voice: "marin" } },
      instructions:
        "You are WearCam, a concise spoken assistant. When the user refers to their current surroundings, says the view changed, or asks a visual question, call get_current_view. Never answer a current visual question from a stale image. Explain that Stop looking immediately disables images.",
      tools: [
        {
          type: "function",
          name: "get_current_view",
          description:
            "Capture a genuinely fresh image from the active rear camera.",
          parameters: {
            type: "object",
            properties: {},
            additionalProperties: false,
          },
        },
      ],
      tool_choice: "auto",
    },
  });
});

test("uses structured errors without leaking an upstream body", async () => {
  await withServer(
    async () => Response.json({ error: permanentKey }, { status: 401 }),
    async (base) => {
      const response = await fetch(`${base}/v1/realtime/client-secret`, {
        method: "POST",
      });
      const text = await response.text();
      assert.equal(response.status, 502);
      assert.equal(text.includes(permanentKey), false);
      assert.equal(JSON.parse(text).error.code, "credential_provider_failed");
    },
  );
});

test("health does not need provider access", async () => {
  await withServer(
    async () => {
      throw new Error("must not run");
    },
    async (base) => {
      const response = await fetch(`${base}/health`);
      assert.deepEqual(await response.json(), { status: "ok" });
    },
  );
});
