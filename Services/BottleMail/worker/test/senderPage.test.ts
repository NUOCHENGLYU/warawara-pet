// @vitest-environment jsdom
import { beforeAll, describe, expect, it, vi } from "vitest";
import { JSDOM } from "jsdom";
import { senderPageHtml } from "../src/senderPage.js";

/// XSS regression tests: every dynamic field of the sender page must be
/// rendered as inert TEXT. Loading the real page script in jsdom and
/// driving its exposed render hooks proves that labels, letter bodies,
/// codes and ids can never inject markup or attributes.
describe("sender page XSS safety", () => {
  let page: {
    renderDeviceList: (el: HTMLElement, data: unknown[]) => void;
    renderCodeList: (el: HTMLElement, data: unknown[]) => void;
    renderLetterList: (el: HTMLElement, data: unknown[]) => void;
    renderCodeMessage: (el: HTMLElement, code: string, expiresAt: string) => void;
  };

  beforeAll(() => {
    // The page's auto-init fetch runs on load: stub it with a minimal
    // response shape (jsdom has no fetch/Response) so the login view
    // stays put.
    const dom = new JSDOM(senderPageHtml(), {
      runScripts: "dangerously",
      url: "https://bottlemail.test/",
      beforeParse(window) {
        window.fetch = vi.fn(async () => ({
          status: 401,
          json: async () => ({ error: "unauthorized" }),
        })) as unknown as typeof fetch;
      },
    });
    page = (dom.window as unknown as {
      BottleMailPage: typeof page;
    }).BottleMailPage;
    expect(page).toBeDefined();
  });

  function container(): HTMLElement {
    return document.createElement("ul");
  }

  it("renders a hostile device label as inert text", () => {
    const list = container();
    page.renderDeviceList(list, [
      { id: "abc12345", label: `<img src=x onerror="window.__pwned=1">`, created_at: "2026-01-01T00:00:00Z", revoked_at: null },
      { id: "abc12346", label: `" onmouseover="window.__pwned=2`, created_at: "2026-01-01T00:00:00Z", revoked_at: null },
    ]);
    expect(list.querySelector("img")).toBeNull();
    expect(list.querySelector("[onmouseover]")).toBeNull();
    expect(list.textContent).toContain(`<img src=x onerror="window.__pwned=1">`);
    expect((window as unknown as { __pwned?: number }).__pwned).toBeUndefined();
  });

  it("renders a hostile letter body as inert text", () => {
    const list = container();
    page.renderLetterList(list, [
      { body: `<script>window.__pwned=3<\/script>hello`, created_at: "2026-01-01T00:00:00Z", opened_at: null },
    ]);
    expect(list.querySelector("script")).toBeNull();
    expect(list.textContent).toContain("<script>window.__pwned=3</script>hello");
    expect((window as unknown as { __pwned?: number }).__pwned).toBeUndefined();
  });

  it("renders the one-time activation code as inert text", () => {
    const box = document.createElement("div");
    page.renderCodeMessage(box, "<b>EVILCODE</b>", "2026-01-01T00:30:00Z");
    expect(box.querySelector("b")).toBeNull();
    expect(box.textContent).toContain("<b>EVILCODE</b>");
  });

  it("renders code hashes and ids as inert text", () => {
    const list = container();
    page.renderCodeList(list, [
      { code_hash: "<i>x</i>AAABBBCCCDDD", created_at: "2026-01-01T00:00:00Z", expires_at: "2026-01-01T00:30:00Z", used_at: null },
    ]);
    expect(list.querySelector("i")).toBeNull();
    expect(list.textContent).toContain("<i>x</i>AAAB");
  });

  it("builds an exact DOM structure, never injecting extra elements", () => {
    // A clean label must render as exactly: li > div.li-main > (span +
    // text + span.muted) + button. Any injected element (img/script/…)
    // would appear in this structure.
    const list = container();
    page.renderDeviceList(list, [{ id: "x", label: "正常设备", created_at: "2026-01-01T00:00:00Z", revoked_at: null }]);
    expect(list.querySelectorAll("*")).toHaveLength(5);
    expect(list.querySelector("li")?.children).toHaveLength(2);
    expect(list.textContent).toContain("正常设备");
    expect(list.textContent).toContain("撤销");
  });
});
