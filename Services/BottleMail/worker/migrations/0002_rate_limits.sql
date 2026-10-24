-- Durable rate-limit counters (cross-isolate). Each row is one
-- (scope + fixed window) bucket; counters reset automatically when a
-- new window starts (see createD1RateLimiter in src/ratelimit.ts).
CREATE TABLE rate_limits (
  bucket TEXT PRIMARY KEY,
  window_start INTEGER NOT NULL,
  count INTEGER NOT NULL
);
