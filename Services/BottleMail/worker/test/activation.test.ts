import { describe, expect, it } from "vitest";
import { sha256Hex } from "../src/crypto.js";
import { createMemoryRepos } from "../src/repo/memory.js";
import { buildRequest, fetchSafe, login, makeEnv } from "./helpers.js";

async function createCode(env: Awaited<ReturnType<typeof makeEnv>>): Promise<string> {
  const session = await login(env);
  const response = await fetchSafe(
    env,
    buildRequest("POST", "/api/admin/activation-codes", {
      cookie: session.cookie,
      csrf: session.csrf,
    })
  );
  expect(response.status).toBe(201);
  const data = (await response.json()) as { code: string; expires_at: string };
  return data.code;
}

describe("activation codes", () => {
  it("requires a sender session to create codes", async () => {
    const env = await makeEnv();
    const response = await fetchSafe(env, buildRequest("POST", "/api/admin/activation-codes"));
    expect(response.status).toBe(401);
  });

  it("activates a device once and rejects the reuse", async () => {
    const env = await makeEnv();
    const code = await createCode(env);
    const first = await fetchSafe(
      env,
      buildRequest("POST", "/api/devices/activate", { body: { code } })
    );
    expect(first.status).toBe(201);
    const firstData = (await first.json()) as { device_token: string };
    expect(firstData.device_token).toMatch(/^[0-9a-f]{64}$/);

    const second = await fetchSafe(
      env,
      buildRequest("POST", "/api/devices/activate", { body: { code } })
    );
    expect(second.status).toBe(409);
  });

  it("rejects unknown codes", async () => {
    const env = await makeEnv();
    const response = await fetchSafe(
      env,
      buildRequest("POST", "/api/devices/activate", { body: { code: "ABCDEFGHJK" } })
    );
    expect(response.status).toBe(401);
  });

  it("rejects malformed code shapes", async () => {
    const env = await makeEnv();
    for (const code of ["", "abc", "A1B2C3", "x".repeat(40), "has space!"]) {
      const response = await fetchSafe(
        env,
        buildRequest("POST", "/api/devices/activate", { body: { code } })
      );
      expect(response.status).toBe(400);
    }
  });

  it("rejects expired codes", async () => {
    const env = await makeEnv();
    // Seed an already-expired code directly through the repository seam.
    const code = "EXPIREDCODE3";
    const codeHash = await sha256Hex(code);
    const past = new Date(Date.now() - 60_000).toISOString();
    await env.repos!.activations.createCode(codeHash, past, past);
    const response = await fetchSafe(
      env,
      buildRequest("POST", "/api/devices/activate", { body: { code } })
    );
    expect(response.status).toBe(410);
  });

  it("rejects already-used codes even after expiry tricks", async () => {
    const env = await makeEnv();
    const code = "USEDCODEXYZ";
    const codeHash = await sha256Hex(code);
    const now = new Date().toISOString();
    const future = new Date(Date.now() + 3_600_000).toISOString();
    await env.repos!.activations.createCode(codeHash, now, future);
    const redeem = await env.repos!.activations.redeemCode(codeHash, now, "device-1");
    expect(redeem.ok).toBe(true);
    const response = await fetchSafe(
      env,
      buildRequest("POST", "/api/devices/activate", { body: { code } })
    );
    expect(response.status).toBe(409);
  });

  it("never returns the plaintext code again (list endpoint is hashes only)", async () => {
    const env = await makeEnv();
    const code = await createCode(env);
    const session = await login(env);
    const response = await fetchSafe(
      env,
      buildRequest("GET", "/api/admin/activation-codes", {
        cookie: session.cookie,
        csrf: session.csrf,
      })
    );
    expect(response.status).toBe(200);
    const data = (await response.json()) as { codes: Array<{ code_hash: string }> };
    expect(data.codes.length).toBeGreaterThan(0);
    const body = JSON.stringify(data);
    expect(body).not.toContain(code);
    const codeHash = await sha256Hex(code);
    expect(data.codes.some((entry) => entry.code_hash === codeHash)).toBe(true);
  });

  it("stores only the hash in the repository", async () => {
    const repos = createMemoryRepos();
    const code = "FRESHCODE1";
    await repos.activations.createCode(await sha256Hex(code), new Date().toISOString(),
      new Date(Date.now() + 60_000).toISOString());
    const listed = await repos.activations.listCodes();
    expect(listed.some((entry) => entry.code_hash === code)).toBe(false);
  });
});
