import { pbkdf2Hex, randomHex } from "../src/crypto.js";
import type { Env } from "../src/env.js";
import { RateLimiter } from "../src/ratelimit.js";
import { createMemoryRepos } from "../src/repo/memory.js";

export const TEST_PASSWORD = "test-password-正确";

export async function makeEnv(): Promise<Env> {
  const salt = randomHex(16);
  const hash = await pbkdf2Hex(TEST_PASSWORD, salt, 1000);
  return {
    DB: {} as D1Database,
    SESSION_SECRET: "s".repeat(64),
    SENDER_PASSWORD_HASH: hash,
    SENDER_PASSWORD_SALT: salt,
    SENDER_USERNAME: "sender",
    SENDER_PASSWORD_ITERATIONS: "1000",
    ACTIVATION_TTL_MINUTES: "30",
    repos: createMemoryRepos(),
    rateLimiter: new RateLimiter(),
  };
}

const ORIGIN = "https://bottlemail.test";

export interface RequestOptions {
  body?: unknown;
  cookie?: string;
  csrf?: string;
  bearer?: string;
  origin?: string | null;
  ip?: string;
}

export function buildRequest(
  method: string,
  path: string,
  options: RequestOptions = {}
): Request {
  const headers = new Headers();
  if (options.body !== undefined) headers.set("Content-Type", "application/json");
  if (options.cookie) headers.set("Cookie", options.cookie);
  if (options.csrf) headers.set("X-CSRF-Token", options.csrf);
  if (options.bearer) headers.set("Authorization", `Bearer ${options.bearer}`);
  if (options.origin !== null) headers.set("Origin", options.origin ?? ORIGIN);
  if (options.ip) headers.set("CF-Connecting-IP", options.ip);
  return new Request(`${ORIGIN}${path}`, {
    method,
    headers,
    body: options.body === undefined ? undefined : JSON.stringify(options.body),
  });
}

export function parseSetCookie(header: string | null): Map<string, string> {
  const cookies = new Map<string, string>();
  if (!header) return cookies;
  for (const part of header.split(/,(?=\s*[A-Za-z0-9_-]+=)/)) {
    const first = part.trim().split(";")[0];
    if (!first) continue;
    const eq = first.indexOf("=");
    if (eq > 0) cookies.set(first.slice(0, eq), first.slice(eq + 1));
  }
  return cookies;
}

export function cookieValue(response: Response, name: string): string | null {
  const all = response.headers.get("set-cookie") ?? "";
  const parsed = parseSetCookie(all);
  return parsed.get(name) ?? null;
}

/// Full login flow: GET / for the CSRF cookie, then POST /api/session.
/// Returns the cookie header to attach to later sender requests.
export async function login(env: Env, password: string = TEST_PASSWORD): Promise<{
  cookie: string;
  csrf: string;
}> {
  const page = await fetchSafe(env, buildRequest("GET", "/"));
  const csrf = cookieValue(page, "bottlemail_csrf");
  if (!csrf) throw new Error("no csrf cookie on GET /");
  // A real browser attaches the cookie jar automatically; mirror that.
  const response = await fetchSafe(
    env,
    buildRequest("POST", "/api/session", {
      body: { password },
      csrf,
      cookie: `bottlemail_csrf=${csrf}`,
    })
  );
  if (response.status !== 200) throw new Error(`login failed: ${response.status}`);
  const session = cookieValue(response, "bottlemail_session");
  if (!session) throw new Error("no session cookie");
  return {
    cookie: `bottlemail_csrf=${csrf}; bottlemail_session=${session}`,
    csrf,
  };
}

/// Shared fetch shim (keep in one place; swaps cleanly if needed).
export async function fetchSafe(env: Env, request: Request): Promise<Response> {
  const { handleRequest } = await import("../src/app.js");
  return handleRequest(request, env);
}
