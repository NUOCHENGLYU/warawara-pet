/// Worker environment: bindings + secrets. Secrets come from
/// `wrangler secret put` (or `.dev.vars` locally) — never from Git.
import type { Repos } from "./repo/types.js";
import type { RateLimiter } from "./ratelimit.js";

export interface Env {
  DB: D1Database;
  SESSION_SECRET: string;
  SENDER_PASSWORD_HASH: string;
  SENDER_PASSWORD_SALT: string;
  SENDER_USERNAME?: string;
  SENDER_PASSWORD_ITERATIONS?: string;
  ACTIVATION_TTL_MINUTES?: string;
  /// Test seam: injected repositories. Production builds them from DB.
  repos?: Repos;
  /// Test seams: injected rate limiters (one per isolate in production
  /// for the memory limiter; the durable limiter is D1-backed).
  rateLimiter?: RateLimiter;
  durableRateLimiter?: RateLimiter;
}

export function senderUsername(env: Env): string {
  return (env.SENDER_USERNAME ?? "sender").trim() || "sender";
}

export function passwordIterations(env: Env): number {
  // 10 000 iterations: PBKDF2-SHA256 at ~3 ms stays well inside the
  // Cloudflare Workers FREE plan's 10 ms CPU budget (310 000 iterations
  // measures ~80 ms and throws a CPU-limit exception on every login).
  // Protection depth comes from the 128-bit random salt plus the
  // D1-durable login lockout (10 attempts / 15 min / IP).
  const parsed = Number.parseInt(env.SENDER_PASSWORD_ITERATIONS ?? "10000", 10);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : 10000;
}

export function activationTtlMs(env: Env): number {
  const parsed = Number.parseInt(env.ACTIVATION_TTL_MINUTES ?? "30", 10);
  const minutes = Number.isFinite(parsed) && parsed > 0 ? parsed : 30;
  return minutes * 60 * 1000;
}
