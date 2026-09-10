import assert from "node:assert/strict";
import { once } from "node:events";
import test from "node:test";
import { createApp, INSTRUCTIONS } from "../src/app.ts";
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
      audio: {
        input: {
          transcription: { model: "gpt-4o-mini-transcribe" },
        },
        output: { voice: "marin" },
      },
      instructions: INSTRUCTIONS,
      tools: [
        {
          type: "function",
          name: "get_current_view",
          description:
            "Request one fresh task-relevant image from the selected camera. The bridge rejects this unless the user authorized One Look or an active Visual Session.",
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

test("logs only safe request metadata after the response", async () => {
  const logs: Array<{
    requestId: string;
    method: string;
    path: string;
    status: number;
    durationMs: number;
  }> = [];
  const server = createApp(config, {
    fetch: async () => {
      throw new Error("must not run");
    },
    requestLog: (entry) => logs.push(entry),
  });
  server.listen(0, "127.0.0.1");
  await once(server, "listening");
  const address = server.address();
  assert(address && typeof address !== "string");
  try {
    const response = await fetch(
      `http://127.0.0.1:${address.port}/health?token=must-not-be-logged`,
      { headers: { authorization: `Bearer ${permanentKey}` } },
    );
    await response.text();
    assert.equal(response.headers.get("x-request-id"), logs[0]?.requestId);
    assert.deepEqual(logs, [
      {
        requestId: logs[0]?.requestId,
        method: "GET",
        path: "/health",
        status: 404,
        durationMs: logs[0]?.durationMs,
      },
    ]);
    const serialized = JSON.stringify(logs);
    assert.equal(serialized.includes(permanentKey), false);
    assert.equal(serialized.includes("must-not-be-logged"), false);
    assert.equal(typeof logs[0]?.durationMs, "number");
  } finally {
    server.close();
    await once(server, "close");
  }
});

test("contains request logger failures after completing a response", async () => {
  const server = createApp(config, {
    fetch: async () => {
      throw new Error("must not run");
    },
    requestLog: () => {
      throw new Error("logger failed");
    },
  });
  server.listen(0, "127.0.0.1");
  await once(server, "listening");
  const address = server.address();
  assert(address && typeof address !== "string");
  try {
    const response = await fetch(`http://127.0.0.1:${address.port}/health`);
    assert.equal(response.status, 200);
    assert.deepEqual(await response.json(), { status: "ok" });
  } finally {
    server.close();
    await once(server, "close");
  }
});
