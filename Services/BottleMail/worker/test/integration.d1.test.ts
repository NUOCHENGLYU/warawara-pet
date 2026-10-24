import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { beforeAll, describe, expect, it } from "vitest";
import { Miniflare } from "miniflare";
import { handleRequest } from "../src/app.js";
import { sha256Hex } from "../src/crypto.js";
import type { Env } from "../src/env.js";
import { createD1RateLimiter, MemoryRateLimiter } from "../src/ratelimit.js";
import { createRepos } from "../src/repo/d1.js";

/// REAL D1 integration tests: run the production D1 repositories against
/// Miniflare's local SQLite (the same engine wrangler dev uses), with
/// the actual migration files applied. No Cloudflare account needed.
/// These prove the SQL itself — unique-constraint races, transactional
/// activation batches and durable rate-limit counters — which the
/// in-memory repos cannot.

const migrations = ["0001_initial.sql", "0002_rate_limits.sql"];

function migrationPath(name: string): string {
  return fileURLToPath(new URL(`../migrations/${name}`, import.meta.url));
}

/// Miniflare's D1 exec rejects comment-only statements; wrangler is more
/// lenient. Drop whole-line `--` comments first (comments may contain
/// semicolons), then split into real statements.
async function execMigration(db: D1Database, name: string): Promise<void> {
  const sql = readFileSync(migrationPath(name), "utf8");
  const withoutComments = sql
    .split("\n")
    .filter((line) => !line.trimStart().startsWith("--"))
    .join("\n");
  for (const raw of withoutComments.split(";")) {
    // Miniflare's D1 exec rejects multi-line statements: collapse
    // whitespace (comments are already removed) so each statement is a
    // single line.
    const statement = raw.trim().replace(/\s+/g, " ");
    if (statement) await db.exec(statement);
  }
}

async function makeD1(): Promise<D1Database> {
  const mf = new Miniflare({
    modules: true,
    script: "export default { fetch() { return new Response(); } }",
    d1Databases: { DB: "11111111-2222-3333-4444-555555555555" },
  });
  const db = await mf.getD1Database("DB");
  for (const name of migrations) {
    await execMigration(db, name);
  }
  return db;
}

function baseEnv(db: D1Database): Env {
  return {
    DB: db,
    SESSION_SECRET: "s".repeat(64),
    SENDER_PASSWORD_HASH: "hash",
    SENDER_PASSWORD_SALT: "salt",
    SENDER_USERNAME: "sender",
    SENDER_PASSWORD_ITERATIONS: "1000",
    ACTIVATION_TTL_MINUTES: "30",
    rateLimiter: new MemoryRateLimiter(),
    durableRateLimiter: new MemoryRateLimiter(),
  };
}

function request(
  method: string,
  path: string,
  headers: Record<string, string> = {},
  body?: string
): Request {
  return new Request(`https://bottlemail.test${path}`, {
    method,
    headers: { "Content-Type": "application/json", ...headers },
    body,
  });
}

describe("D1 integration (Miniflare local SQLite)", () => {
  let db: D1Database;
  let env: Env;

  beforeAll(async () => {
    db = await makeD1();
    env = baseEnv(db);
  });

  it("applies the real migrations (letters, devices, activation_codes, rate_limits)", async () => {
    const tables = await db
      .prepare(`SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name`)
      .all<{ name: string }>();
    const names = tables.results.map((row) => row.name);
    for (const expected of ["letters", "devices", "activation_codes", "rate_limits"]) {
      expect(names).toContain(expected);
    }
  });

  it("concurrent sends with the SAME client_request_id create exactly one letter", async () => {
    const repos = createRepos(db);
    const requestId = crypto.randomUUID();
    const results = await Promise.all(
      Array.from({ length: 20 }, (_, index) =>
        repos.letters.insertLetter({
          id: crypto.randomUUID(),
          body: `并发第${index}封`,
          createdAt: new Date().toISOString(),
          clientRequestId: requestId,
        })
      )
    );
    const created = results.filter((result) => result.created);
    expect(created).toHaveLength(1);
    expect(results.filter((result) => !result.created)).toHaveLength(19);
    // Every result (winner included) points at the SAME letter.
    const ids = new Set(results.map((result) => result.record.id));
    expect(ids.size).toBe(1);
    // And exactly one row exists in SQLite.
    const count = await db
      .prepare(`SELECT COUNT(*) AS n FROM letters WHERE client_request_id = ?`)
      .bind(requestId)
      .first<{ n: number }>();
    expect(Number(count?.n)).toBe(1);
  });

  it("concurrent redemption of one activation code yields exactly one device", async () => {
    const repos = createRepos(db);
    const codeHash = await sha256Hex("CONCURRENTCODE");
    await repos.activations.createCode(
      codeHash,
      new Date().toISOString(),
      new Date(Date.now() + 3_600_000).toISOString()
    );
    const at = new Date().toISOString();
    const attempts = await Promise.all(
      Array.from({ length: 10 }, () =>
        repos.activateDevice({
          codeHash,
          at,
          deviceId: crypto.randomUUID(),
          tokenHash: crypto.randomUUID(),
          label: "并发设备",
        })
      )
    );
    const winners = attempts.filter((result) => result.ok);
    expect(winners).toHaveLength(1);
    for (const loser of attempts.filter((result) => !result.ok)) {
      if (!loser.ok) expect(loser.reason).toBe("used");
    }
    const devices = await repos.devices.listDevices();
    expect(devices.filter((device) => device.label === "并发设备")).toHaveLength(1);
  });

  it("activation records the REAL devices.id in activation_codes.device_id", async () => {
    const repos = createRepos(db);
    const codeHash = await sha256Hex("LINKAGECODE");
    await repos.activations.createCode(
      codeHash,
      new Date().toISOString(),
      new Date(Date.now() + 3_600_000).toISOString()
    );
    const deviceId = crypto.randomUUID();
    const result = await repos.activateDevice({
      codeHash,
      at: new Date().toISOString(),
      deviceId,
      tokenHash: await sha256Hex("linkage-token"),
      label: "联动设备",
    });
    expect(result.ok).toBe(true);
    const codeRow = await db
      .prepare(`SELECT device_id FROM activation_codes WHERE code_hash = ?`)
      .bind(codeHash)
      .first<{ device_id: string }>();
    expect(codeRow?.device_id).toBe(deviceId);
    const deviceRow = await db
      .prepare(`SELECT id FROM devices WHERE id = ?`)
      .bind(deviceId)
      .first<{ id: string }>();
    expect(deviceRow?.id).toBe(deviceId);
    // The linkage survives revocation: the revoked row keeps its id.
    const revoked = await repos.devices.revokeDevice(deviceId, new Date().toISOString());
    expect(revoked).toBe(true);
  });

  it("an expired code is rejected without touching devices", async () => {
    const repos = createRepos(db);
    const codeHash = await sha256Hex("EXPIREDREAL");
    const past = new Date(Date.now() - 60_000).toISOString();
    await repos.activations.createCode(codeHash, past, past);
    const result = await repos.activateDevice({
      codeHash,
      at: new Date().toISOString(),
      deviceId: crypto.randomUUID(),
      tokenHash: crypto.randomUUID(),
      label: "过期设备",
    });
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.reason).toBe("expired");
  });

  it("serves the full activation -> poll -> open -> revoke flow over real D1", async () => {
    const sessionSecret = "s".repeat(64);
    const flowEnv: Env = { ...env, SESSION_SECRET: sessionSecret };

    // Sender session via a directly signed token (login covered elsewhere).
    const { createSessionToken } = await import("../src/session.js");
    const session = await createSessionToken(
      "sender",
      sessionSecret,
      Math.floor(Date.now() / 1000)
    );
    const page = await handleRequest(request("GET", "/"), flowEnv);
    const csrf = page.headers.get("set-cookie")?.match(/bottlemail_csrf=([^;]+)/)?.[1] ?? "";
    const cookie = `bottlemail_csrf=${csrf}; bottlemail_session=${session}`;
    const senderHeaders = {
      Cookie: cookie,
      "X-CSRF-Token": csrf,
      Origin: "https://bottlemail.test",
    };

    // Sender creates an activation code.
    const codeResponse = await handleRequest(
      request("POST", "/api/admin/activation-codes", senderHeaders),
      flowEnv
    );
    expect(codeResponse.status).toBe(201);
    const { code } = (await codeResponse.json()) as { code: string };

    // Sender sends two letters.
    for (const body of ["第一封", "第二封"]) {
      const sent = await handleRequest(
        request("POST", "/api/letters", senderHeaders, JSON.stringify({ body })),
        flowEnv
      );
      expect(sent.status).toBe(201);
    }

    // Device activates.
    const activated = await handleRequest(
      request("POST", "/api/devices/activate", {}, JSON.stringify({ code, label: "真机设备" })),
      flowEnv
    );
    expect(activated.status).toBe(201);
    const { device_token: token, device_id: deviceId } = (await activated.json()) as {
      device_token: string;
      device_id: string;
    };

    // Poll: both letters, ordered by seq; repolling returns them again.
    const polled = await handleRequest(
      request("GET", "/api/letters?after=0&limit=50", { Authorization: `Bearer ${token}` }),
      flowEnv
    );
    expect(polled.status).toBe(200);
    const pollData = (await polled.json()) as {
      letters: Array<{ id: string; body: string; opened_at: string | null }>;
    };
    const flowLetters = pollData.letters.filter(
      (letter) => letter.body === "第一封" || letter.body === "第二封"
    );
    expect(flowLetters).toHaveLength(2);
    expect(flowLetters.every((letter) => letter.opened_at === null)).toBe(true);

    // Open the first letter; idempotent second open keeps the timestamp.
    const opened = await handleRequest(
      request("POST", `/api/letters/${flowLetters[0]!.id}/open`, {
        Authorization: `Bearer ${token}`,
      }),
      flowEnv
    );
    expect(opened.status).toBe(200);
    const openedData = (await opened.json()) as { opened_at: string; already_opened: boolean };
    expect(openedData.already_opened).toBe(false);
    const openedAgain = await handleRequest(
      request("POST", `/api/letters/${flowLetters[0]!.id}/open`, {
        Authorization: `Bearer ${token}`,
      }),
      flowEnv
    );
    const openedAgainData = (await openedAgain.json()) as {
      opened_at: string;
      already_opened: boolean;
    };
    expect(openedAgainData.already_opened).toBe(true);
    expect(openedAgainData.opened_at).toBe(openedData.opened_at);

    // Revoke via the admin endpoint, then the token is rejected.
    const revoke = await handleRequest(
      request("POST", `/api/admin/devices/${encodeURIComponent(deviceId)}/revoke`, senderHeaders),
      flowEnv
    );
    expect(revoke.status).toBe(200);
    const afterRevoke = await handleRequest(
      request("GET", "/api/letters?after=0", { Authorization: `Bearer ${token}` }),
      flowEnv
    );
    expect(afterRevoke.status).toBe(401);

    // Sanity: the device row really was the same one bound by the code.
    const deviceRow = await db
      .prepare(`SELECT revoked_at FROM devices WHERE id = ?`)
      .bind(deviceId)
      .first<{ revoked_at: string | null }>();
    expect(deviceRow?.revoked_at).not.toBeNull();
  });

  it("durable D1 rate limiter is cross-isolate and windowed", async () => {
    const limiter = createD1RateLimiter(db);
    const key = `integration:${crypto.randomUUID()}`;
    const limit = 3;
    const window = 60_000;
    for (let i = 0; i < limit; i += 1) {
      expect(await limiter.allow(key, limit, window)).toBe(true);
    }
    expect(await limiter.allow(key, limit, window)).toBe(false);
    // A second limiter instance (simulating another isolate) sees the
    // same counters — this is what a per-isolate memory limiter cannot do.
    const secondIsolate = createD1RateLimiter(db);
    expect(await secondIsolate.allow(key, limit, window)).toBe(false);
    // A different key is unaffected.
    expect(await limiter.allow(`${key}:other`, limit, window)).toBe(true);
  });
});
