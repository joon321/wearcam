export interface Config {
  readonly apiKey: string;
  readonly port: number;
  readonly allowedOrigin: string;
  readonly model: string;
  readonly apiBaseUrl: string;
  readonly braveSearchApiKey?: string | undefined;
}

export function loadConfig(env: NodeJS.ProcessEnv): Config {
  const apiKey = env.OPENAI_API_KEY?.trim();
  if (!apiKey) throw new Error("OPENAI_API_KEY is required");
  const port = Number(env.PORT ?? "8787");
  if (!Number.isInteger(port) || port < 1 || port > 65535) {
    throw new Error("PORT must be an integer from 1 to 65535");
  }
  const environment = env.NODE_ENV?.trim() || "development";
  const allowedOrigin = env.ALLOWED_ORIGIN?.trim() || "http://localhost:8787";
  if (environment === "production" && allowedOrigin === "*") {
    throw new Error('ALLOWED_ORIGIN must not be "*" in production');
  }
  return {
    apiKey,
    port,
    allowedOrigin,
    model: env.OPENAI_REALTIME_MODEL ?? "gpt-realtime",
    apiBaseUrl: (env.OPENAI_API_BASE_URL ?? "https://api.openai.com").replace(
      /\/$/,
      "",
    ),
    braveSearchApiKey: env.BRAVE_SEARCH_API_KEY?.trim() || undefined,
  };
}
