import { base64UrlDecode, base64UrlEncode, hmacSha256Hex, randomHex, timingSafeEqualHex } from "./crypto.js";

export const SESSION_COOKIE = "bottlemail_session";
export const CSRF_COOKIE = "bottlemail_csrf";
const SESSION_TTL_SECONDS = 7 * 24 * 3600;

/// Signed session token: base64url(payload) + "." + hmac(secret, payload).
export async function createSessionToken(
  username: string,
  secret: string,
  nowSeconds: number
): Promise<string> {
  const payload = base64UrlEncode(
    new TextEncoder().encode(JSON.stringify({ u: username, exp: nowSeconds + SESSION_TTL_SECONDS }))
  );
  const signature = await hmacSha256Hex(secret, payload);
  return `${payload}.${signature}`;
}

export async function verifySessionToken(
  token: string,
  secret: string,
  username: string,
  nowSeconds: number
): Promise<boolean> {
  const parts = token.split(".");
  if (parts.length !== 2) return false;
  const [payload, signature] = parts;
  if (!payload || !signature) return false;
  const expected = await hmacSha256Hex(secret, payload);
  if (!timingSafeEqualHex(expected, signature)) return false;
  let data: { u?: string; exp?: number };
  try {
    data = JSON.parse(new TextDecoder().decode(base64UrlDecode(payload)));
  } catch {
    return false;
  }
  if (data.u !== username) return false;
  if (typeof data.exp !== "number" || data.exp < nowSeconds) return false;
  return true;
}

export function readCookie(cookieHeader: string | null, name: string): string | null {
  if (!cookieHeader) return null;
  for (const part of cookieHeader.split(";")) {
    const [rawName, ...rawValue] = part.trim().split("=");
    if (rawName === name && rawValue !== undefined) {
      return decodeURIComponent(rawValue.join("="));
    }
  }
  return null;
}

export function sessionCookieHeader(token: string, secure: boolean): string {
  const parts = [
    `${SESSION_COOKIE}=${token}`,
    "HttpOnly",
    "SameSite=Strict",
    "Path=/",
    `Max-Age=${SESSION_TTL_SECONDS}`,
  ];
  if (secure) parts.push("Secure");
  return parts.join("; ");
}

export function clearedSessionCookieHeader(): string {
  return `${SESSION_COOKIE}=; HttpOnly; SameSite=Strict; Path=/; Max-Age=0`;
}

export function csrfCookieHeader(token: string, secure: boolean): string {
  const parts = [`${CSRF_COOKIE}=${token}`, "SameSite=Strict", "Path=/", "Max-Age=86400"];
  if (secure) parts.push("Secure");
  return parts.join("; ");
}

export function newCsrfToken(): string {
  return randomHex(16);
}
