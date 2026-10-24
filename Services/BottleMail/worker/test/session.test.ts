import { describe, expect, it } from "vitest";
import { hmacSha256Hex } from "../src/crypto.js";
import { MemoryRateLimiter } from "../src/ratelimit.js";
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
  it("allows up to the limit then blocks", async () => {
    let now = 0;
    const limiter = new MemoryRateLimiter(() => now);
    for (let i = 0; i < 3; i += 1) expect(await limiter.allow("k", 3, 10_000)).toBe(true);
    expect(await limiter.allow("k", 3, 10_000)).toBe(false);
  });

  it("reopens after the window slides", async () => {
    let now = 0;
    const limiter = new MemoryRateLimiter(() => now);
    await limiter.allow("k", 1, 10_000);
    expect(await limiter.allow("k", 1, 10_000)).toBe(false);
    now = 10_001;
    expect(await limiter.allow("k", 1, 10_000)).toBe(true);
  });

  it("scopes limits per key", async () => {
    let now = 0;
    const limiter = new MemoryRateLimiter(() => now);
    expect(await limiter.allow("a", 1, 10_000)).toBe(true);
    expect(await limiter.allow("b", 1, 10_000)).toBe(true);
    expect(await limiter.allow("a", 1, 10_000)).toBe(false);
  });
});
