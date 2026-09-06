export class FixedWindowRateLimiter {
  readonly #requests = new Map<string, { count: number; resetAt: number }>();
  readonly #limit: number;
  readonly #windowMs: number;
  readonly #now: () => number;

  constructor(limit = 10, windowMs = 60_000, now = Date.now) {
    this.#limit = limit;
    this.#windowMs = windowMs;
    this.#now = now;
  }

  allow(key: string): boolean {
    const current = this.#now();
    for (const [trackedKey, tracked] of this.#requests) {
      if (current >= tracked.resetAt) this.#requests.delete(trackedKey);
    }
    const entry = this.#requests.get(key);
    if (!entry || current >= entry.resetAt) {
      this.#requests.set(key, { count: 1, resetAt: current + this.#windowMs });
      return true;
    }
    if (entry.count >= this.#limit) return false;
    entry.count += 1;
    return true;
  }

  get trackedClientCount(): number {
    return this.#requests.size;
  }
}
