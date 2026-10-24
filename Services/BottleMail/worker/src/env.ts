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
  /// Test seam: injected rate limiter (one per isolate in production;
  /// tests get a fresh instance per environment).
  rateLimiter?: RateLimiter;
}

export function senderUsername(env: Env): string {
  return (env.SENDER_USERNAME ?? "sender").trim() || "sender";
}

export function passwordIterations(env: Env): number {
  const parsed = Number.parseInt(env.SENDER_PASSWORD_ITERATIONS ?? "310000", 10);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : 310000;
}

export function activationTtlMs(env: Env): number {
  const parsed = Number.parseInt(env.ACTIVATION_TTL_MINUTES ?? "30", 10);
  const minutes = Number.isFinite(parsed) && parsed > 0 ? parsed : 30;
  return minutes * 60 * 1000;
}
