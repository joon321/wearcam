import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import test from "node:test";
import { pathToFileURL } from "node:url";
import { loadConfig } from "../src/config.ts";

const required = { OPENAI_API_KEY: "provider-secret" };

test("uses a local development origin by default", () => {
  assert.equal(loadConfig(required).allowedOrigin, "http://localhost:8787");
});

test("loads development configuration from an env file without logging the key", () => {
  const directory = mkdtempSync(join(tmpdir(), "wearcam-config-"));
  const envFile = join(directory, ".env");
  const secret = "test-only-provider-secret";
  writeFileSync(envFile, `OPENAI_API_KEY=${secret}\nPORT=9876\n`, {
    mode: 0o600,
  });

  try {
    const configUrl = pathToFileURL(resolve("src/config.ts")).href;
    const result = spawnSync(
      process.execPath,
      [
        `--env-file=${envFile}`,
        "--experimental-strip-types",
        "--input-type=module",
        "--eval",
        `import { loadConfig } from ${JSON.stringify(configUrl)}; console.log(loadConfig(process.env).port);`,
      ],
      { encoding: "utf8", env: {} },
    );

    assert.equal(result.status, 0, result.stderr);
    assert.equal(result.stdout.trim(), "9876");
    assert.doesNotMatch(`${result.stdout}${result.stderr}`, new RegExp(secret));
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
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
