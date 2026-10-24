import { describe, expect, it } from "vitest";
import { buildRequest, fetchSafe, makeEnv } from "./helpers.js";

describe("service basics", () => {
  it("serves the sender page at / with a CSRF cookie", async () => {
    const env = await makeEnv();
    const response = await fetchSafe(env, buildRequest("GET", "/"));
    expect(response.status).toBe(200);
    expect(response.headers.get("content-type")).toContain("text/html");
    expect(response.headers.get("set-cookie")).toContain("bottlemail_csrf=");
    expect(response.headers.get("content-security-policy")).toContain("default-src 'none'");
    expect(response.headers.get("x-content-type-options")).toBe("nosniff");
    const html = await response.text();
    expect(html).toContain("写一封信");
    expect(html).toContain("设备激活码");
  });

  it("health endpoint leaks nothing private", async () => {
    const env = await makeEnv();
    const response = await fetchSafe(env, buildRequest("GET", "/health"));
    expect(response.status).toBe(200);
    const text = await response.text();
    const data = JSON.parse(text) as Record<string, unknown>;
    expect(data.ok).toBe(true);
    expect(text).not.toContain(env.SENDER_PASSWORD_HASH);
    expect(text).not.toContain(env.SESSION_SECRET);
  });

  it("returns JSON 404 for unknown routes", async () => {
    const env = await makeEnv();
    const response = await fetchSafe(env, buildRequest("GET", "/api/nope"));
    expect(response.status).toBe(404);
    expect(((await response.json()) as { error: string }).error).toBe("not_found");
  });
});
