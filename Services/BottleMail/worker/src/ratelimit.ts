/// Rate limiting. Two implementations share one interface:
/// - `MemoryRateLimiter`: per-isolate sliding window (fast first line).
/// - `createD1RateLimiter`: D1-backed FIXED-window counters — durable
///   across isolates, which is what actually protects the public
///   login / activation / send endpoints. Only the sensitive routes use
///   the durable store; cheap read-only routes keep the memory limiter.
export interface RateLimiter {
  /** True when the request is allowed; false when the limit is exceeded. */
  allow(key: string, limit: number, windowMs: number): Promise<boolean>;
}

export class MemoryRateLimiter implements RateLimiter {
  private hits = new Map<string, number[]>();

  constructor(private readonly now: () => number = () => Date.now()) {}

  async allow(key: string, limit: number, windowMs: number): Promise<boolean> {
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
}

/// D1-backed fixed-window limiter. Each (key, window) pair is one row;
/// the counter resets automatically when the next window starts because
/// the bucket name embeds the window start. Cross-isolate by
/// construction (D1 is the shared store). Old buckets are pruned
/// opportunistically on the first hit of each new bucket.
export function createD1RateLimiter(db: D1Database): RateLimiter {
  return {
    async allow(key, limit, windowMs) {
      const now = Date.now();
      const windowStart = Math.floor(now / windowMs) * windowMs;
      const bucket = `${key}:${windowStart}`;
      const row = await db
        .prepare(
          `INSERT INTO rate_limits (bucket, window_start, count) VALUES (?, ?, 1)
           ON CONFLICT(bucket) DO UPDATE SET count = rate_limits.count + 1
           RETURNING count`
        )
        .bind(bucket, windowStart)
        .first<{ count: number }>();
      const count = row?.count ?? 0;
      if (count === 1) {
        // New bucket: opportunistically prune buckets older than an hour.
        db.prepare(`DELETE FROM rate_limits WHERE window_start < ?`)
          .bind(now - 3_600_000)
          .run()
          .catch(() => undefined);
      }
      return count <= limit;
    },
  };
}
