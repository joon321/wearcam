export interface Config {
  readonly apiKey: string;
  readonly port: number;
  readonly allowedOrigin: string;
  readonly model: string;
  readonly apiBaseUrl: string;
}

export function loadConfig(env: NodeJS.ProcessEnv): Config {
  const apiKey = env.OPENAI_API_KEY?.trim();
  if (!apiKey) throw new Error("OPENAI_API_KEY is required");
  const port = Number(env.PORT ?? "8787");
  if (!Number.isInteger(port) || port < 1 || port > 65535) {
    throw new Error("PORT must be an integer from 1 to 65535");
  }
  return {
    apiKey,
    port,
    allowedOrigin: env.ALLOWED_ORIGIN ?? "*",
    model: env.OPENAI_REALTIME_MODEL ?? "gpt-realtime",
    apiBaseUrl: (env.OPENAI_API_BASE_URL ?? "https://api.openai.com").replace(
      /\/$/,
      "",
    ),
  };
}
