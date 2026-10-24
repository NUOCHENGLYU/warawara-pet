/// In-memory sliding-window rate limiter. Per-isolate (Workers are
/// ephemeral): this throttles abuse, not a durable quota. The clock is
/// injectable so tests are deterministic.
export class RateLimiter {
  private hits = new Map<string, number[]>();

  constructor(private readonly now: () => number = () => Date.now()) {}

  /** True when the request is allowed; false when the limit is exceeded. */
  allow(key: string, limit: number, windowMs: number): boolean {
    const now = this.now();
    const cutoff = now - windowMs;
    const entries = (this.hits.get(key) ?? []).filter((t) => t > cutoff);
    if (entries.length >= limit) {
      this.hits.set(key, entries);
      return false;
    }
    entries.push(now);
    this.hits.set(key, entries);
    // Bounded memory: drop keys that have been idle for a while.
    if (this.hits.size > 512) {
      for (const [entryKey, times] of this.hits) {
        if (times.every((t) => t <= cutoff)) this.hits.delete(entryKey);
      }
    }
    return true;
  }

  reset(): void {
    this.hits.clear();
  }
}
