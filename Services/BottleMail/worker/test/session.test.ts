import { describe, expect, it } from "vitest";
import { hmacSha256Hex } from "../src/crypto.js";
import { RateLimiter } from "../src/ratelimit.js";
import { createSessionToken, verifySessionToken } from "../src/session.js";

describe("session token", () => {
  it("issues a verifiable signed token", async () => {
    const secret = "secret".repeat(10);
    const token = await createSessionToken("sender", secret, 1_000);
    expect(await verifySessionToken(token, secret, "sender", 1_001)).toBe(true);
    expect(await verifySessionToken(token, secret, "other", 1_001)).toBe(false);
    expect(await verifySessionToken(token, "wrong-secret", "sender", 1_001)).toBe(false);
    // Expires after the 7-day TTL.
    expect(
      await verifySessionToken(token, secret, "sender", 1_000 + 7 * 24 * 3600 + 1)
    ).toBe(false);
  });

  it("rejects malformed tokens", async () => {
    const secret = "secret".repeat(10);
    for (const token of ["", "nodot", "a.b.c", "!.!", "a.b.c.d"]) {
      expect(await verifySessionToken(token, secret, "sender", 1_000)).toBe(false);
    }
  });

  it("survives a payload that decodes to non-object JSON", async () => {
    const secret = "secret".repeat(10);
    const payload = btoa(JSON.stringify("just a string"))
      .replace(/\+/g, "-")
      .replace(/\//g, "_")
      .replace(/=+$/, "");
    const signature = await hmacSha256Hex(secret, payload);
    expect(
      await verifySessionToken(`${payload}.${signature}`, secret, "sender", 1_000)
    ).toBe(false);
  });
});

describe("rate limiter", () => {
  it("allows up to the limit then blocks", () => {
    let now = 0;
    const limiter = new RateLimiter(() => now);
    for (let i = 0; i < 3; i += 1) expect(limiter.allow("k", 3, 10_000)).toBe(true);
    expect(limiter.allow("k", 3, 10_000)).toBe(false);
  });

  it("reopens after the window slides", () => {
    let now = 0;
    const limiter = new RateLimiter(() => now);
    limiter.allow("k", 1, 10_000);
    expect(limiter.allow("k", 1, 10_000)).toBe(false);
    now = 10_001;
    expect(limiter.allow("k", 1, 10_000)).toBe(true);
  });

  it("scopes limits per key", () => {
    let now = 0;
    const limiter = new RateLimiter(() => now);
    expect(limiter.allow("a", 1, 10_000)).toBe(true);
    expect(limiter.allow("b", 1, 10_000)).toBe(true);
    expect(limiter.allow("a", 1, 10_000)).toBe(false);
  });
});
