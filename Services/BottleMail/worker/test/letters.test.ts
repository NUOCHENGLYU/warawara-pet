import { describe, expect, it } from "vitest";
import { buildRequest, fetchSafe, login, makeEnv } from "./helpers.js";

async function activateDevice(env: Awaited<ReturnType<typeof makeEnv>>, code: string) {
  const response = await fetchSafe(
    env,
    buildRequest("POST", "/api/devices/activate", { body: { code, label: "测试设备" } })
  );
  return { status: response.status, data: (await response.json()) as {
    device_id?: string;
    device_token?: string;
    error?: string;
  } };
}

async function sendLetter(
  env: Awaited<ReturnType<typeof makeEnv>>,
  session: { cookie: string; csrf: string },
  body: string,
  clientRequestId?: string
) {
  const response = await fetchSafe(
    env,
    buildRequest("POST", "/api/letters", {
      cookie: session.cookie,
      csrf: session.csrf,
      body: clientRequestId ? { body, client_request_id: clientRequestId } : { body },
    })
  );
  return { status: response.status, data: (await response.json()) as Record<string, unknown> };
}

describe("letters (sender side)", () => {
  it("rejects anonymous letter creation", async () => {
    const env = await makeEnv();
    const response = await fetchSafe(
      env,
      buildRequest("POST", "/api/letters", { body: { body: "你好" } })
    );
    expect(response.status).toBe(401);
  });

  it("rejects invalid bodies", async () => {
    const env = await makeEnv();
    const session = await login(env);
    for (const body of [undefined, "", "   ", "x".repeat(2001), "\u0000"]) {
      const { status } = await sendLetter(env, session, body as string);
      expect(status).toBe(400);
    }
  });

  it("accepts Chinese, newlines and emoji within 2000 chars", async () => {
    const env = await makeEnv();
    const session = await login(env);
    const { status, data } = await sendLetter(
      env,
      session,
      "亲爱的朋友：\n见字如面。🌊🍾\n今天也祝你生日快乐。"
    );
    expect(status).toBe(201);
    expect(data.id).toBeTypeOf("string");
  });

  it("accepts the 2000-char boundary", async () => {
    const env = await makeEnv();
    const session = await login(env);
    const { status } = await sendLetter(env, session, "字".repeat(2000));
    expect(status).toBe(201);
  });

  it("deduplicates retries by client_request_id and returns the same letter", async () => {
    const env = await makeEnv();
    const session = await login(env);
    const requestId = crypto.randomUUID();
    const first = await sendLetter(env, session, "只有一封信", requestId);
    expect(first.status).toBe(201);
    const retry = await sendLetter(env, session, "只有一封信", requestId);
    expect(retry.status).toBe(200);
    expect(retry.data.id).toBe(first.data.id);
    expect(retry.data.duplicate).toBe(true);
  });

  it("rejects a malformed client_request_id", async () => {
    const env = await makeEnv();
    const session = await login(env);
    const response = await fetchSafe(
      env,
      buildRequest("POST", "/api/letters", {
        cookie: session.cookie,
        csrf: session.csrf,
        body: { body: "hello", client_request_id: "not-a-uuid" },
      })
    );
    expect(response.status).toBe(400);
  });

  it("rejects cross-origin POSTs (CSRF origin check)", async () => {
    const env = await makeEnv();
    const session = await login(env);
    const response = await fetchSafe(
      env,
      buildRequest("POST", "/api/letters", {
        cookie: session.cookie,
        csrf: session.csrf,
        origin: "https://evil.example",
        body: { body: "hi" },
      })
    );
    expect(response.status).toBe(403);
  });

  it("rejects POSTs without the CSRF header", async () => {
    const env = await makeEnv();
    const session = await login(env);
    const response = await fetchSafe(
      env,
      buildRequest("POST", "/api/letters", {
        cookie: session.cookie,
        csrf: "",
        body: { body: "hi" },
      })
    );
    expect(response.status).toBe(403);
  });
});

describe("letters (device side)", () => {
  it("requires a device bearer token", async () => {
    const env = await makeEnv();
    const response = await fetchSafe(env, buildRequest("GET", "/api/letters"));
    expect(response.status).toBe(401);
  });

  it("pages letters with a seq cursor without deleting anything", async () => {
    const env = await makeEnv();
    const session = await login(env);
    const ids: string[] = [];
    for (let i = 1; i <= 5; i += 1) {
      const { data } = await sendLetter(env, session, `第${i}封`);
      ids.push(String(data.id));
    }
    // Activate a device and poll.
    const codeResponse = await fetchSafe(
      env,
      buildRequest("POST", "/api/admin/activation-codes", { cookie: session.cookie, csrf: session.csrf })
    );
    const { code } = (await codeResponse.json()) as { code: string };
    const activated = await activateDevice(env, code);
    expect(activated.status).toBe(201);
    const token = activated.data.device_token!;

    const firstPage = await fetchSafe(
      env,
      buildRequest("GET", "/api/letters?after=0&limit=2", { bearer: token })
    );
    const page1 = (await firstPage.json()) as {
      letters: Array<{ seq: number; body: string }>;
      next_after: number;
    };
    expect(firstPage.status).toBe(200);
    expect(page1.letters).toHaveLength(2);
    expect(page1.next_after).toBe(page1.letters[1]!.seq);

    const secondPage = await fetchSafe(
      env,
      buildRequest("GET", `/api/letters?after=${page1.next_after}&limit=50`, { bearer: token })
    );
    const page2 = (await secondPage.json()) as { letters: Array<{ seq: number }> };
    expect(page2.letters).toHaveLength(3);

    // Repolling the same cursor returns the same letters again — polling
    // never deletes or marks anything read.
    const repoll = await fetchSafe(
      env,
      buildRequest("GET", "/api/letters?after=0&limit=50", { bearer: token })
    );
    const repollData = (await repoll.json()) as { letters: Array<{ body: string }> };
    expect(repollData.letters).toHaveLength(5);
    expect(repollData.letters.map((letter) => letter.body)).toEqual(
      ["第1封", "第2封", "第3封", "第4封", "第5封"]
    );
  });

  it("marks a letter opened exactly once and is idempotent", async () => {
    const env = await makeEnv();
    const session = await login(env);
    const { data } = await sendLetter(env, session, "要被打开的信");
    const id = String(data.id);

    const codeResponse = await fetchSafe(
      env,
      buildRequest("POST", "/api/admin/activation-codes", { cookie: session.cookie, csrf: session.csrf })
    );
    const { code } = (await codeResponse.json()) as { code: string };
    const activated = await activateDevice(env, code);
    const token = activated.data.device_token!;

    const first = await fetchSafe(env, buildRequest("POST", `/api/letters/${id}/open`, { bearer: token }));
    const firstData = (await first.json()) as { opened_at: string; already_opened: boolean };
    expect(first.status).toBe(200);
    expect(firstData.already_opened).toBe(false);
    expect(firstData.opened_at).toBeTypeOf("string");

    const second = await fetchSafe(env, buildRequest("POST", `/api/letters/${id}/open`, { bearer: token }));
    const secondData = (await second.json()) as { opened_at: string; already_opened: boolean };
    expect(second.status).toBe(200);
    expect(secondData.already_opened).toBe(true);
    expect(secondData.opened_at).toBe(firstData.opened_at);
  });

  it("returns 404 for unknown letters", async () => {
    const env = await makeEnv();
    const session = await login(env);
    const codeResponse = await fetchSafe(
      env,
      buildRequest("POST", "/api/admin/activation-codes", { cookie: session.cookie, csrf: session.csrf })
    );
    const { code } = (await codeResponse.json()) as { code: string };
    const activated = await activateDevice(env, code);
    const response = await fetchSafe(
      env,
      buildRequest("POST", `/api/letters/${crypto.randomUUID()}/open`, {
        bearer: activated.data.device_token!,
      })
    );
    expect(response.status).toBe(404);
  });

  it("cannot create letters with a device token (read-only device)", async () => {
    const env = await makeEnv();
    const session = await login(env);
    const codeResponse = await fetchSafe(
      env,
      buildRequest("POST", "/api/admin/activation-codes", { cookie: session.cookie, csrf: session.csrf })
    );
    const { code } = (await codeResponse.json()) as { code: string };
    const activated = await activateDevice(env, code);
    const response = await fetchSafe(
      env,
      buildRequest("POST", "/api/letters", {
        bearer: activated.data.device_token!,
        body: { body: "冒充发送者" },
      })
    );
    expect(response.status).toBe(401);
  });

  it("rejects a revoked device token", async () => {
    const env = await makeEnv();
    const session = await login(env);
    const codeResponse = await fetchSafe(
      env,
      buildRequest("POST", "/api/admin/activation-codes", { cookie: session.cookie, csrf: session.csrf })
    );
    const { code } = (await codeResponse.json()) as { code: string };
    const activated = await activateDevice(env, code);
    const token = activated.data.device_token!;

    const before = await fetchSafe(env, buildRequest("GET", "/api/letters", { bearer: token }));
    expect(before.status).toBe(200);

    const revoke = await fetchSafe(
      env,
      buildRequest("POST", `/api/admin/devices/${activated.data.device_id}/revoke`, {
        cookie: session.cookie,
        csrf: session.csrf,
      })
    );
    expect(revoke.status).toBe(200);

    const after = await fetchSafe(env, buildRequest("GET", "/api/letters", { bearer: token }));
    expect(after.status).toBe(401);
  });

  it("rejects invalid cursors and limits", async () => {
    const env = await makeEnv();
    const session = await login(env);
    const codeResponse = await fetchSafe(
      env,
      buildRequest("POST", "/api/admin/activation-codes", { cookie: session.cookie, csrf: session.csrf })
    );
    const { code } = (await codeResponse.json()) as { code: string };
    const activated = await activateDevice(env, code);
    const token = activated.data.device_token!;
    for (const query of ["after=-1", "after=abc", "limit=0", "limit=51"]) {
      const response = await fetchSafe(
        env,
        buildRequest("GET", `/api/letters?${query}`, { bearer: token })
      );
      expect(response.status).toBe(400);
    }
  });

  it("lets the SENDER delete a letter (test-data cleanup), devices cannot", async () => {
    const env = await makeEnv();
    const session = await login(env);
    const { data } = await sendLetter(env, session, "将被删除的测试信");
    const id = String(data.id);

    // Devices cannot delete (read-only identity).
    const codeResponse = await fetchSafe(
      env,
      buildRequest("POST", "/api/admin/activation-codes", { cookie: session.cookie, csrf: session.csrf })
    );
    const { code } = (await codeResponse.json()) as { code: string };
    const activated = await activateDevice(env, code);
    const deviceDelete = await fetchSafe(
      env,
      buildRequest("DELETE", `/api/letters/${id}`, { bearer: activated.data.device_token! })
    );
    expect(deviceDelete.status).toBe(401);

    // Sender delete removes it; polling no longer returns it.
    const removed = await fetchSafe(
      env,
      buildRequest("DELETE", `/api/letters/${id}`, { cookie: session.cookie, csrf: session.csrf })
    );
    expect(removed.status).toBe(200);
    const polled = await fetchSafe(
      env,
      buildRequest("GET", "/api/letters?after=0&limit=50", { bearer: activated.data.device_token! })
    );
    const pollData = (await polled.json()) as { letters: Array<{ id: string }> };
    expect(pollData.letters.some((letter) => letter.id === id)).toBe(false);

    // Double delete is a 404.
    const again = await fetchSafe(
      env,
      buildRequest("DELETE", `/api/letters/${id}`, { cookie: session.cookie, csrf: session.csrf })
    );
    expect(again.status).toBe(404);
  });
});
