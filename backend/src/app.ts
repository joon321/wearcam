import {
  createServer,
  type IncomingMessage,
  type ServerResponse,
} from "node:http";
import type { Config } from "./config.ts";
import { FixedWindowRateLimiter } from "./rate-limit.ts";

const MAX_BODY_BYTES = 1024;
export const INSTRUCTIONS = `You are WearCam, a concise spoken assistant using the selected Phone camera.
Decide whether vision would materially improve the answer and recommend the narrowest sufficient scope. Use One Look when one image is likely enough. Explain briefly what must be visible, then say to open the camera, point the phone at it, hold still, move closer, or switch to the rear camera as appropriate, and ask the user to say “ready”. Do not call get_current_view until the bridge confirms authorization.
Use a Visual Session only when several task-related observations are likely needed. Explain why and ask “May I start a visual session?” The suggestion itself is never authorization. Never claim the session started until the bridge confirms it. Never silently start, extend, reactivate, or upgrade to a Visual Session.
A clear direct request such as “look at this” needs no redundant confirmation, but still permits only one image. If scope is ambiguous, choose One Look or ask whether the user wants one view or a Visual Session.
During an authorized Visual Session, call get_current_view only when a fresh view materially helps; never request periodic or unnecessary frames. Never claim to see anything before a successful image transmission. If a view is inadequate, give specific repositioning guidance and request another One Look or session permission rather than silently retrying. Respect Stop Looking immediately.`;

type Fetch = typeof fetch;
type RequestLog = (entry: {
  requestId: string;
  method: string;
  path: string;
  status: number;
  durationMs: number;
}) => void;

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
  dependencies: {
    fetch?: Fetch;
    limiter?: FixedWindowRateLimiter;
    requestLog?: RequestLog;
  } = {},
) {
  const requestFetch = dependencies.fetch ?? fetch;
  const limiter = dependencies.limiter ?? new FixedWindowRateLimiter();
  const requestLog =
    dependencies.requestLog ??
    ((entry: Parameters<RequestLog>[0]) => console.log(JSON.stringify(entry)));

  return createServer(async (request, response) => {
    const requestId = crypto.randomUUID();
    const startedAt = performance.now();
    const method = request.method ?? "UNKNOWN";
    const path = new URL(request.url ?? "/", "http://localhost").pathname;
    response.setHeader("x-request-id", requestId);
    response.once("finish", () => {
      try {
        requestLog({
          requestId,
          method,
          path,
          status: response.statusCode,
          durationMs: Math.round(performance.now() - startedAt),
        });
      } catch {
        // Logging is observational and must never affect request handling.
      }
    });
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
