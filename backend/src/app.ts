import {
  createServer,
  type IncomingMessage,
  type ServerResponse,
} from "node:http";
import type { Config } from "./config.ts";
import { FixedWindowRateLimiter } from "./rate-limit.ts";

const MAX_BODY_BYTES = 1024;
const IMAGE_SEARCH_BODY_LIMIT = 512;
export const INSTRUCTIONS = `You are WearCam, a concise spoken assistant in a user-started visual conversation. Visual access is already authorized while the bridge reports it enabled. Never ask the user to authorize, confirm, say “ready”, choose a visual scope, or start a visual session.
Only call get_current_view when the user explicitly asks you to look at something (e.g. “look at this”, “can you see this”, “check this out”). Never capture proactively or on your own initiative. Do not tell the user to position or point the camera — the app handles that. Keep responses short and conversational.
After receiving an image, do not describe or narrate what you see unless the user asks a question about it. Simply acknowledge briefly (e.g. “Got it” or “I see it”) and wait for the user to ask. Never claim to see anything before successful image transmission.
If the bridge returns vision_disabled, say that looking is currently off and that the user can say “resume looking” or press Resume Looking. Respect Stop Looking immediately while continuing the voice conversation.
If you hear unclear audio, background noise, or sounds that are not intelligible speech directed at you, stay completely silent — do not respond, ask for clarification, or acknowledge the noise. Only respond when you can clearly understand spoken words directed at you. Environmental sounds are only relevant if the user has been discussing them.
When you want to point out or highlight specific objects or areas in a captured image, call highlight_object with normalized coordinates (0.0–1.0). The app draws visual overlays so the user can see exactly what you mean.
When the user doesn't know what something looks like and needs a visual reference, call show_reference_image with a descriptive search query. The app will find and display a reference photo in the conversation.`;

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
      if (request.method === "POST" && request.url === "/v1/image-search") {
        if (!config.braveSearchApiKey) {
          json(
            response,
            501,
            { error: { code: "image_search_not_configured", requestId } },
            config.allowedOrigin,
          );
          return;
        }
        const clientAddress = request.socket.remoteAddress ?? "unknown";
        if (!limiter.allow(`img:${clientAddress}`)) {
          json(
            response,
            429,
            { error: { code: "rate_limited", requestId } },
            config.allowedOrigin,
          );
          return;
        }
        let body = "";
        let size = 0;
        for await (const chunk of request) {
          size += Buffer.byteLength(chunk);
          if (size > IMAGE_SEARCH_BODY_LIMIT)
            throw new Error("request_too_large");
          body += chunk;
        }
        let query: string;
        try {
          const parsed = JSON.parse(body);
          query = typeof parsed.query === "string" ? parsed.query.trim() : "";
        } catch {
          json(
            response,
            400,
            { error: { code: "invalid_body", requestId } },
            config.allowedOrigin,
          );
          return;
        }
        if (!query) {
          json(
            response,
            400,
            { error: { code: "missing_query", requestId } },
            config.allowedOrigin,
          );
          return;
        }
        try {
          const searchUrl = new URL(
            "https://api.search.brave.com/res/v1/images/search",
          );
          searchUrl.searchParams.set("q", query);
          searchUrl.searchParams.set("count", "1");
          searchUrl.searchParams.set("safesearch", "strict");
          const searchResponse = await requestFetch(searchUrl.toString(), {
            headers: {
              Accept: "application/json",
              "Accept-Encoding": "gzip",
              "X-Subscription-Token": config.braveSearchApiKey,
            },
            signal: AbortSignal.timeout(8_000),
          });
          if (!searchResponse.ok) {
            json(
              response,
              502,
              { error: { code: "image_search_failed", requestId } },
              config.allowedOrigin,
            );
            return;
          }
          const searchData = (await searchResponse.json()) as {
            results?: Array<{
              thumbnail?: { src?: string };
              url?: string;
              title?: string;
            }>;
          };
          const firstResult = searchData.results?.[0];
          const thumbnailUrl = firstResult?.thumbnail?.src;
          if (!thumbnailUrl) {
            json(response, 200, { results: [] }, config.allowedOrigin);
            return;
          }
          json(
            response,
            200,
            {
              results: [
                {
                  thumbnailUrl,
                  sourceUrl: firstResult.url ?? thumbnailUrl,
                  title: firstResult.title ?? query,
                },
              ],
            },
            config.allowedOrigin,
          );
        } catch {
          json(
            response,
            502,
            { error: { code: "image_search_failed", requestId } },
            config.allowedOrigin,
          );
        }
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
                    "Capture one fresh still image from the user's camera. The app handles camera preview and positioning. Call immediately when the user asks you to look at something.",
                  parameters: {
                    type: "object",
                    properties: {},
                    additionalProperties: false,
                  },
                },
                {
                  type: "function",
                  name: "highlight_object",
                  description:
                    "Highlight specific objects or areas in the most recently captured image. The app draws visual overlays so the user sees exactly what you mean. Use when the user asks where something is, or to visually guide them. Coordinates are normalized fractions of image width and height (0.0 to 1.0).",
                  parameters: {
                    type: "object",
                    properties: {
                      regions: {
                        type: "array",
                        items: {
                          type: "object",
                          properties: {
                            x: {
                              type: "number",
                              description:
                                "Left edge as fraction of image width (0.0–1.0)",
                            },
                            y: {
                              type: "number",
                              description:
                                "Top edge as fraction of image height (0.0–1.0)",
                            },
                            width: {
                              type: "number",
                              description:
                                "Width as fraction of image width (0.0–1.0)",
                            },
                            height: {
                              type: "number",
                              description:
                                "Height as fraction of image height (0.0–1.0)",
                            },
                            label: {
                              type: "string",
                              description: "Short label for the region",
                            },
                          },
                          required: ["x", "y", "width", "height", "label"],
                          additionalProperties: false,
                        },
                      },
                    },
                    required: ["regions"],
                    additionalProperties: false,
                  },
                },
                {
                  type: "function",
                  name: "show_reference_image",
                  description:
                    "Search for and display a reference photo when the user does not know what something looks like. The image appears in the conversation. Use when the user asks 'what does X look like?' or says they don't recognize something.",
                  parameters: {
                    type: "object",
                    properties: {
                      query: {
                        type: "string",
                        description:
                          "Descriptive search query for the reference image",
                      },
                    },
                    required: ["query"],
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
