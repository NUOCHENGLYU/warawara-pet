import { pbkdf2Hex, randomHex, sha256Hex, timingSafeEqualHex } from "./crypto.js";
import {
  activationTtlMs,
  passwordIterations,
  senderUsername,
  type Env,
} from "./env.js";
import { createD1RateLimiter, MemoryRateLimiter } from "./ratelimit.js";
import { createRepos } from "./repo/d1.js";
import type { Repos } from "./repo/types.js";
import {
  clearedSessionCookieHeader,
  csrfCookieHeader,
  createSessionToken,
  CSRF_COOKIE,
  newCsrfToken,
  readCookie,
  SESSION_COOKIE,
  sessionCookieHeader,
  verifySessionToken,
} from "./session.js";
import { senderPageHtml } from "./senderPage.js";
import {
  isValidActivationCodeShape,
  validateClientRequestId,
  validateDeviceLabel,
  validateLetterBody,
} from "./validation.js";

const ACT_CODE_CHARSET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789";

/// Per-isolate memory limiter (fast first line for cheap routes).
const productionMemoryLimiter = new MemoryRateLimiter();

function nowIso(): string {
  return new Date().toISOString();
}

function jsonResponse(status: number, body: unknown, headers: Record<string, string> = {}): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "Content-Type": "application/json",
      "X-Content-Type-Options": "nosniff",
      "Referrer-Policy": "no-referrer",
      ...headers,
    },
  });
}

/// Security headers for the sender page: only the single inline script
/// and style are allowed; no external subresources, no embedding.
const PAGE_SECURITY_HEADERS: Record<string, string> = {
  "X-Content-Type-Options": "nosniff",
  "Referrer-Policy": "no-referrer",
  "Content-Security-Policy":
    "default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; " +
    "connect-src 'self'; img-src 'self' data:; form-action 'none'; base-uri 'none'; frame-ancestors 'none'",
};

function ipOf(request: Request): string {
  return request.headers.get("CF-Connecting-IP") ?? "local";
}

/// Cookie-authenticated endpoints are CSRF-protected: same-origin check
/// on the Origin header (when present) plus a double-submit token.
function enforceCsrf(request: Request, url: URL): boolean {
  const origin = request.headers.get("Origin");
  if (origin) {
    try {
      const originHost = new URL(origin).host;
      if (originHost !== url.host) return false;
    } catch {
      return false;
    }
  }
  const fetchSite = request.headers.get("Sec-Fetch-Site");
  if (fetchSite && fetchSite !== "same-origin" && fetchSite !== "none") return false;
  const cookieToken = readCookie(request.headers.get("Cookie"), CSRF_COOKIE);
  const headerToken = request.headers.get("X-CSRF-Token");
  if (!cookieToken || !headerToken) return false;
  return timingSafeEqualHex(cookieToken, headerToken);
}

async function isSenderSession(request: Request, env: Env): Promise<boolean> {
  const cookie = readCookie(request.headers.get("Cookie"), SESSION_COOKIE);
  if (!cookie) return false;
  return verifySessionToken(
    cookie,
    env.SESSION_SECRET,
    senderUsername(env),
    Math.floor(Date.now() / 1000)
  );
}

async function deviceForRequest(
  request: Request,
  repos: Repos
): Promise<{ id: string; label: string } | null> {
  const header = request.headers.get("Authorization");
  if (!header || !header.startsWith("Bearer ")) return null;
  const token = header.slice("Bearer ".length).trim();
  if (!token) return null;
  const tokenHash = await sha256Hex(token);
  const device = await repos.devices.findDeviceByTokenHash(tokenHash);
  if (!device || device.revoked_at !== null) return null;
  return { id: device.id, label: device.label };
}

function makeActivationCode(): string {
  // CSPRNG: activation codes guard device binding, so they must be
  // unguessable (10 chars from a 32-char alphabet ≈ 50 bits).
  const bytes = new Uint8Array(10);
  crypto.getRandomValues(bytes);
  let out = "";
  for (const byte of bytes) out += ACT_CODE_CHARSET[byte % ACT_CODE_CHARSET.length];
  return out;
}

/// The entire worker behind one exported handler so tests can drive it
/// with plain Request objects and injected repositories.
export async function handleRequest(request: Request, env: Env): Promise<Response> {
  const url = new URL(request.url);
  const method = request.method.toUpperCase();
  const repos: Repos = env.repos ?? createRepos(env.DB);
  // Sensitive routes (login / activation / sending) are throttled by
  // the DURABLE, cross-isolate D1 limiter; cheap read-only routes use
  // the fast per-isolate memory limiter. Tests inject either seam.
  const durableLimiter = env.durableRateLimiter ?? createD1RateLimiter(env.DB);
  const memoryLimiter = env.rateLimiter ?? productionMemoryLimiter;
  const path = url.pathname;

  try {
    if (method === "GET" && path === "/health") {
      return jsonResponse(200, { ok: true, service: "bottlemail" });
    }

    if (method === "GET" && path === "/") {
      const csrf = newCsrfToken();
      return new Response(senderPageHtml(), {
        status: 200,
        headers: {
          "Content-Type": "text/html; charset=utf-8",
          "Set-Cookie": csrfCookieHeader(csrf, url.protocol === "https:"),
          ...PAGE_SECURITY_HEADERS,
        },
      });
    }

    // ---- Sender session -------------------------------------------------
    if (method === "POST" && path === "/api/session") {
      if (!(await durableLimiter.allow(`login:${ipOf(request)}`, 10, 15 * 60 * 1000))) {
        return jsonResponse(429, { error: "too_many_attempts" });
      }
      if (!enforceCsrf(request, url)) {
        return jsonResponse(403, { error: "csrf" });
      }
      let payload: { password?: unknown };
      try {
        payload = (await request.json()) as { password?: unknown };
      } catch {
        return jsonResponse(400, { error: "bad_json" });
      }
      if (typeof payload.password !== "string" || payload.password.length === 0) {
        return jsonResponse(400, { error: "password_required" });
      }
      if (!env.SENDER_PASSWORD_HASH || !env.SENDER_PASSWORD_SALT || !env.SESSION_SECRET) {
        return jsonResponse(500, { error: "misconfigured" });
      }
      const hash = await pbkdf2Hex(
        payload.password,
        env.SENDER_PASSWORD_SALT,
        passwordIterations(env)
      );
      if (!timingSafeEqualHex(hash, env.SENDER_PASSWORD_HASH)) {
        return jsonResponse(401, { error: "invalid_password" });
      }
      const token = await createSessionToken(
        senderUsername(env),
        env.SESSION_SECRET,
        Math.floor(Date.now() / 1000)
      );
      return jsonResponse(200, { ok: true }, {
        "Set-Cookie": sessionCookieHeader(token, url.protocol === "https:"),
      });
    }

    if (method === "POST" && path === "/api/session/logout") {
      return new Response(JSON.stringify({ ok: true }), {
        status: 200,
        headers: {
          "Content-Type": "application/json",
          "Set-Cookie": clearedSessionCookieHeader(),
        },
      });
    }

    // ---- Device activation ----------------------------------------------
    if (method === "POST" && path === "/api/devices/activate") {
      if (!(await durableLimiter.allow(`activate:${ipOf(request)}`, 10, 10 * 60 * 1000))) {
        return jsonResponse(429, { error: "too_many_attempts" });
      }
      let payload: { code?: unknown; label?: unknown };
      try {
        payload = (await request.json()) as { code?: unknown; label?: unknown };
      } catch {
        return jsonResponse(400, { error: "bad_json" });
      }
      if (typeof payload.code !== "string" || !isValidActivationCodeShape(payload.code)) {
        return jsonResponse(400, { error: "invalid_code" });
      }
      const label = validateDeviceLabel(payload.label);
      const codeHash = await sha256Hex(payload.code);
      // The device id and token are generated FIRST so the atomic
      // redeem+bind step records the REAL devices.id as
      // activation_codes.device_id (never the label), and a failed
      // device insert leaves the code unconsumed (transactional batch).
      const deviceId = crypto.randomUUID();
      const deviceToken = randomHex(32);
      const tokenHash = await sha256Hex(deviceToken);
      const activated = await repos.activateDevice({
        codeHash,
        at: nowIso(),
        deviceId,
        tokenHash,
        label,
      });
      if (!activated.ok) {
        if (activated.reason === "expired") return jsonResponse(410, { error: "code_expired" });
        if (activated.reason === "used") return jsonResponse(409, { error: "code_used" });
        return jsonResponse(401, { error: "invalid_code" });
      }
      return jsonResponse(201, {
        device_id: deviceId,
        device_token: deviceToken,
        label,
      });
    }

    // ---- Sender-only management -----------------------------------------
    if (path === "/api/admin/activation-codes") {
      if (!(await isSenderSession(request, env))) {
        return jsonResponse(401, { error: "unauthorized" });
      }
      if (method === "POST") {
        if (!enforceCsrf(request, url)) return jsonResponse(403, { error: "csrf" });
        if (!(await durableLimiter.allow(`codes:${ipOf(request)}`, 20, 10 * 60 * 1000))) {
          return jsonResponse(429, { error: "too_many_attempts" });
        }
        const code = makeActivationCode();
        const createdAt = nowIso();
        const expiresAt = new Date(Date.now() + activationTtlMs(env)).toISOString();
        await repos.activations.createCode(await sha256Hex(code), createdAt, expiresAt);
        return jsonResponse(201, { code, expires_at: expiresAt });
      }
      if (method === "GET") {
        const codes = await repos.activations.listCodes();
        return jsonResponse(200, { codes });
      }
    }

    if (path === "/api/admin/devices") {
      if (!(await isSenderSession(request, env))) {
        return jsonResponse(401, { error: "unauthorized" });
      }
      if (method === "GET") {
        return jsonResponse(200, { devices: await repos.devices.listDevices() });
      }
    }

    if (method === "POST" && path.startsWith("/api/admin/devices/") && path.endsWith("/revoke")) {
      if (!(await isSenderSession(request, env))) {
        return jsonResponse(401, { error: "unauthorized" });
      }
      if (!enforceCsrf(request, url)) return jsonResponse(403, { error: "csrf" });
      const deviceId = decodeURIComponent(
        path.slice("/api/admin/devices/".length, -"/revoke".length)
      );
      const revoked = await repos.devices.revokeDevice(deviceId, nowIso());
      return jsonResponse(revoked ? 200 : 404, revoked ? { ok: true } : { error: "not_found" });
    }

    if (method === "GET" && path === "/api/admin/letters") {
      if (!(await isSenderSession(request, env))) {
        return jsonResponse(401, { error: "unauthorized" });
      }
      const letters = await repos.letters.listLetters(0, 100);
      return jsonResponse(200, { letters });
    }

    // ---- Sender: create a letter ----------------------------------------
    if (method === "POST" && path === "/api/letters") {
      if (!(await isSenderSession(request, env))) {
        return jsonResponse(401, { error: "unauthorized" });
      }
      if (!enforceCsrf(request, url)) return jsonResponse(403, { error: "csrf" });
      if (!(await durableLimiter.allow(`letter:${ipOf(request)}`, 30, 10 * 60 * 1000))) {
        return jsonResponse(429, { error: "too_many_attempts" });
      }
      let payload: { body?: unknown; client_request_id?: unknown };
      try {
        payload = (await request.json()) as { body?: unknown; client_request_id?: unknown };
      } catch {
        return jsonResponse(400, { error: "bad_json" });
      }
      const validated = validateLetterBody(payload.body);
      if (!validated.ok) return jsonResponse(400, { error: validated.message });
      const clientRequestId = validateClientRequestId(payload.client_request_id);
      if (clientRequestId === undefined) {
        return jsonResponse(400, { error: "client_request_id_must_be_a_uuid" });
      }
      const result = await repos.letters.insertLetter({
        id: crypto.randomUUID(),
        body: validated.body,
        createdAt: nowIso(),
        clientRequestId,
      });
      return jsonResponse(result.created ? 201 : 200, {
        id: result.record.id,
        seq: result.record.seq,
        created_at: result.record.created_at,
        duplicate: !result.created,
      });
    }

    // ---- Device: poll letters --------------------------------------------
    if (method === "GET" && path === "/api/letters") {
      if (!(await memoryLimiter.allow(`poll:${ipOf(request)}`, 120, 10 * 60 * 1000))) {
        return jsonResponse(429, { error: "too_many_requests" });
      }
      const device = await deviceForRequest(request, repos);
      if (!device) return jsonResponse(401, { error: "unauthorized" });
      const afterParam = url.searchParams.get("after");
      const after = afterParam === null ? 0 : Number.parseInt(afterParam, 10);
      if (!Number.isFinite(after) || after < 0) {
        return jsonResponse(400, { error: "invalid_cursor" });
      }
      const limitParam = url.searchParams.get("limit");
      const limit = limitParam === null ? 20 : Number.parseInt(limitParam, 10);
      if (!Number.isFinite(limit) || limit < 1 || limit > 50) {
        return jsonResponse(400, { error: "invalid_limit" });
      }
      const letters = await repos.letters.listLetters(after, limit);
      const nextAfter =
        letters.length > 0 ? Math.max(after, letters[letters.length - 1]?.seq ?? after) : after;
      return jsonResponse(200, { letters, next_after: nextAfter });
    }

    // ---- Sender: delete a letter (test-data cleanup only) --------------
    const deleteMatch = method === "DELETE" && path.match(/^\/api\/letters\/([^/]+)$/);
    if (deleteMatch) {
      if (!(await isSenderSession(request, env))) {
        return jsonResponse(401, { error: "unauthorized" });
      }
      if (!enforceCsrf(request, url)) return jsonResponse(403, { error: "csrf" });
      const letterId = decodeURIComponent(deleteMatch[1] ?? "");
      const removed = await repos.letters.deleteLetter(letterId);
      return jsonResponse(removed ? 200 : 404, removed ? { ok: true } : { error: "not_found" });
    }

    // ---- Device: open a letter (idempotent) ------------------------------
    const openMatch = method === "POST" && path.match(/^\/api\/letters\/([^/]+)\/open$/);
    if (openMatch) {
      if (!(await memoryLimiter.allow(`open:${ipOf(request)}`, 120, 10 * 60 * 1000))) {
        return jsonResponse(429, { error: "too_many_requests" });
      }
      const device = await deviceForRequest(request, repos);
      if (!device) return jsonResponse(401, { error: "unauthorized" });
      const letterId = decodeURIComponent(openMatch[1] ?? "");
      const letter = await repos.letters.findLetterById(letterId);
      if (!letter) return jsonResponse(404, { error: "not_found" });
      const opened = await repos.letters.markOpened(letterId, nowIso());
      return jsonResponse(200, {
        id: letter.id,
        opened_at: opened.record.opened_at,
        already_opened: opened.alreadyOpened,
      });
    }

    return jsonResponse(404, { error: "not_found" });
  } catch (error) {
    // Never log bodies, tokens or codes — only the request shape.
    console.error("bottlemail error", method, path, error instanceof Error ? error.message : "?");
    return jsonResponse(500, { error: "internal_error" });
  }
}
