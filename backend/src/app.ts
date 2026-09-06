import {
  createServer,
  type IncomingMessage,
  type ServerResponse,
} from "node:http";
import type { Config } from "./config.ts";
import { FixedWindowRateLimiter } from "./rate-limit.ts";

const MAX_BODY_BYTES = 1024;
const INSTRUCTIONS = `You are WearCam, a concise spoken assistant. When the user refers to their current surroundings, says the view changed, or asks a visual question, call get_current_view. Never answer a current visual question from a stale image. Explain that Stop looking immediately disables images.`;

type Fetch = typeof fetch;

function json(
  response: ServerResponse,
  status: number,
  body: unknown,
  origin: string,
): void {
  response.writeHead(status, {
    "content-type": "application/json; charset=utf-8",
    "cache-control": "no-store",
    "access-control-allow-origin": origin,
    vary: "origin",
  });
  response.end(JSON.stringify(body));
}

async function consumeSmallBody(request: IncomingMessage): Promise<void> {
  let size = 0;
  for await (const chunk of request) {
    size += Buffer.byteLength(chunk);
    if (size > MAX_BODY_BYTES) throw new Error("request_too_large");
  }
}

export function createApp(
  config: Config,
  dependencies: { fetch?: Fetch; limiter?: FixedWindowRateLimiter } = {},
) {
  const requestFetch = dependencies.fetch ?? fetch;
  const limiter = dependencies.limiter ?? new FixedWindowRateLimiter();

  return createServer(async (request, response) => {
    const requestId = crypto.randomUUID();
    try {
      if (request.method === "OPTIONS") {
        response.writeHead(204, {
          "access-control-allow-origin": config.allowedOrigin,
          "access-control-allow-methods": "POST, GET, OPTIONS",
          "access-control-allow-headers": "content-type",
          vary: "origin",
        });
        response.end();
        return;
      }
      if (request.method === "GET" && request.url === "/health") {
        json(response, 200, { status: "ok" }, config.allowedOrigin);
        return;
      }
      if (
        request.method !== "POST" ||
        request.url !== "/v1/realtime/client-secret"
      ) {
        json(
          response,
          404,
          { error: { code: "not_found", requestId } },
          config.allowedOrigin,
        );
        return;
      }
      const clientAddress = request.socket.remoteAddress ?? "unknown";
      if (!limiter.allow(clientAddress)) {
        json(
          response,
          429,
          { error: { code: "rate_limited", requestId } },
          config.allowedOrigin,
        );
        return;
      }
      await consumeSmallBody(request);
      const upstream = await requestFetch(
        `${config.apiBaseUrl}/v1/realtime/client_secrets`,
        {
          method: "POST",
          headers: {
            authorization: `Bearer ${config.apiKey}`,
            "content-type": "application/json",
          },
          body: JSON.stringify({
            session: {
              type: "realtime",
              model: config.model,
              audio: { output: { voice: "marin" } },
              instructions: INSTRUCTIONS,
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
          }),
          signal: AbortSignal.timeout(10_000),
        },
      );
      const upstreamBody: unknown = await upstream.json();
      if (!upstream.ok) {
        console.error(
          JSON.stringify({
            requestId,
            event: "openai_error",
            status: upstream.status,
          }),
        );
        json(
          response,
          502,
          { error: { code: "credential_provider_failed", requestId } },
          config.allowedOrigin,
        );
        return;
      }
      // Deliberately whitelist the temporary value; never spread upstream or config.
      const value = (upstreamBody as { value?: unknown }).value;
      if (typeof value !== "string" || value.length === 0) {
        json(
          response,
          502,
          { error: { code: "invalid_provider_response", requestId } },
          config.allowedOrigin,
        );
        return;
      }
      json(response, 201, { value }, config.allowedOrigin);
    } catch (error) {
      const code =
        error instanceof Error && error.message === "request_too_large"
          ? "request_too_large"
          : "internal_error";
      json(
        response,
        code === "request_too_large" ? 413 : 500,
        { error: { code, requestId } },
        config.allowedOrigin,
      );
    }
  });
}
