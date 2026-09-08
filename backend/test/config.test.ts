import assert from "node:assert/strict";
import test from "node:test";
import { loadConfig } from "../src/config.ts";

const required = { OPENAI_API_KEY: "provider-secret" };

test("uses a local development origin by default", () => {
  assert.equal(loadConfig(required).allowedOrigin, "http://localhost:8787");
});

test("rejects a wildcard origin in production", () => {
  assert.throws(
    () =>
      loadConfig({
        ...required,
        NODE_ENV: "production",
        ALLOWED_ORIGIN: "*",
      }),
    /ALLOWED_ORIGIN must not be "\*" in production/,
  );
});

test("accepts an explicit HTTPS origin in production", () => {
  const config = loadConfig({
    ...required,
    NODE_ENV: "production",
    ALLOWED_ORIGIN: "https://wearcam.example.com",
  });
  assert.equal(config.allowedOrigin, "https://wearcam.example.com");
});
