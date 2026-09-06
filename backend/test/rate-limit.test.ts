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

test("removes expired inactive client entries", () => {
  let now = 0;
  const limiter = new FixedWindowRateLimiter(2, 100, () => now);
  limiter.allow("inactive");
  assert.equal(limiter.trackedClientCount, 1);

  now = 100;
  limiter.allow("current");
  assert.equal(limiter.trackedClientCount, 1);
});
