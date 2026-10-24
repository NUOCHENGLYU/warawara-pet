import { describe, expect, it } from "vitest";
import { buildRequest, fetchSafe, login, makeEnv } from "./helpers.js";
import { createSessionToken, verifySessionToken } from "../src/session.js";

describe("sender session", () => {
  it("rejects a wrong password", async () => {
    const env = await makeEnv();
    const page = await fetchSafe(env, buildRequest("GET", "/"));
    const csrf = page.headers.get("set-cookie")?.match(/bottlemail_csrf=([^;]+)/)?.[1];
    const response = await fetchSafe(
      env,
      buildRequest("POST", "/api/session", {
        body: { password: "wrong" },
        csrf,
        cookie: `bottlemail_csrf=${csrf}`,
      })
    );
    expect(response.status).toBe(401);
    expect(response.headers.get("set-cookie") ?? "").not.toContain("bottlemail_session=");
  });

  it("issues a session cookie on the correct password", async () => {
    const env = await makeEnv();
    const { cookie } = await login(env);
    expect(cookie).toContain("bottlemail_session=");
  });

  it("rejects missing or empty passwords", async () => {
    const env = await makeEnv();
    const page = await fetchSafe(env, buildRequest("GET", "/"));
    const csrf = page.headers.get("set-cookie")?.match(/bottlemail_csrf=([^;]+)/)?.[1];
    for (const body of [{}, { password: "" }, { password: 42 }]) {
      const response = await fetchSafe(
        env,
        buildRequest("POST", "/api/session", {
          body,
          csrf,
          cookie: `bottlemail_csrf=${csrf}`,
        })
      );
      expect(response.status).toBe(400);
    }
  });

  it("rejects a tampered session token", async () => {
    const env = await makeEnv();
    const { cookie, csrf } = await login(env);
    const tampered = cookie.replace(/bottlemail_session=[^;]+/, "bottlemail_session=abc.def");
    const response = await fetchSafe(
      env,
      buildRequest("GET", "/api/admin/letters", { cookie: tampered, csrf })
    );
    expect(response.status).toBe(401);
  });

  it("rejects a session signed for a different username", async () => {
    const env = await makeEnv();
    const token = await createSessionToken("someone-else", env.SESSION_SECRET, 1_000_000);
    const response = await fetchSafe(
      env,
      buildRequest("GET", "/api/admin/letters", {
        cookie: `bottlemail_session=${token}`,
      })
    );
    expect(response.status).toBe(401);
  });

  it("expires sessions past their TTL", async () => {
    const env = await makeEnv();
    const token = await createSessionToken("sender", env.SESSION_SECRET, 1_000_000);
    const valid = await verifySessionToken(token, env.SESSION_SECRET, "sender", 1_000_001);
    expect(valid).toBe(true);
    const expired = await verifySessionToken(
      token,
      env.SESSION_SECRET,
      "sender",
      1_000_000 + 8 * 24 * 3600
    );
    expect(expired).toBe(false);
  });

  it("logs out by clearing the cookie", async () => {
    const env = await makeEnv();
    const { cookie, csrf } = await login(env);
    const response = await fetchSafe(
      env,
      buildRequest("POST", "/api/session/logout", { cookie, csrf })
    );
    expect(response.status).toBe(200);
    expect(response.headers.get("set-cookie")).toContain("bottlemail_session=;");
  });
});
