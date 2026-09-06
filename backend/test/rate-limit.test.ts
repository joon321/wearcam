import assert from "node:assert/strict";
import test from "node:test";
import { FixedWindowRateLimiter } from "../src/rate-limit.ts";

test("limits requests and resets the fixed window", () => {
  let now = 0;
  const limiter = new FixedWindowRateLimiter(2, 100, () => now);
  assert.equal(limiter.allow("client"), true);
  assert.equal(limiter.allow("client"), true);
  assert.equal(limiter.allow("client"), false);
  now = 100;
  assert.equal(limiter.allow("client"), true);
});
