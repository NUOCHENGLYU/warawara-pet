/// The private sender page. Served at `/` by the same worker, so it is
/// same-origin: sessions, the CSRF cookie and every call stay in one
/// place. Plain HTML + vanilla JS — no framework, no secrets in code.
///
/// XSS policy: NO dynamic value is ever written through innerHTML.
/// Every dynamic field (device label, letter body, activation code,
/// code hashes, ids) is rendered with createElement + textContent, so
/// `<img onerror=...>` and friends stay inert text. The only innerHTML
/// assignments in the page script are constant markup templates.
export function senderPageHtml(): string {
  return `<!doctype html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Bottle Mail · 发信</title>
<style>
  :root { --ink:#2e3a4a; --paper:#f7f2e9; --line:#d8cdb8; --sea:#4a7ba6; --sea2:#2f5d82; }
  * { box-sizing: border-box; }
  body { margin:0; background:linear-gradient(180deg,#e9f0f5,#f7f2e9 70%); color:var(--ink);
         font-family:-apple-system,"PingFang SC","Microsoft YaHei",sans-serif; min-height:100vh; }
  main { max-width:640px; margin:0 auto; padding:24px 16px 64px; }
  h1 { font-size:22px; display:flex; align-items:center; gap:8px; }
  .card { background:var(--paper); border:1px solid var(--line); border-radius:12px;
          padding:16px; margin-top:14px; box-shadow:0 2px 8px rgba(60,70,90,.08); }
  .card h2 { margin:0 0 10px; font-size:15px; color:var(--sea2); }
  textarea, input[type=password], input[type=text] { width:100%; padding:10px; border:1px solid var(--line);
          border-radius:8px; font-size:14px; background:#fff; }
  textarea { min-height:120px; resize:vertical; }
  button { background:var(--sea); color:#fff; border:0; border-radius:8px; padding:9px 16px;
           font-size:14px; cursor:pointer; }
  button:hover { background:var(--sea2); }
  button:disabled { opacity:.5; cursor:default; }
  .row { display:flex; justify-content:space-between; align-items:center; gap:8px; }
  .muted { color:#7a7f88; font-size:12px; }
  .code { font-family:ui-monospace,Menlo,monospace; font-size:18px; letter-spacing:2px;
          background:#fff; border:1px dashed var(--sea); padding:8px 10px; border-radius:8px;
          word-break:break-all; }
  ul { list-style:none; padding:0; margin:0; }
  li { padding:8px 0; border-bottom:1px solid var(--line); font-size:13px; display:flex;
       justify-content:space-between; gap:8px; align-items:center; }
  li:last-child { border-bottom:0; }
  .pill { font-size:11px; padding:2px 8px; border-radius:99px; background:#e3ecf3; color:var(--sea2); }
  .pill.read { background:#dceae3; color:#2f6b4f; }
  .msg { font-size:13px; margin-top:8px; min-height:18px; }
  .msg.ok { color:#2f6b4f; } .msg.err { color:#a33; }
  .hidden { display:none; }
  .pre { white-space:pre-wrap; word-break:break-word; }
  .li-main { flex:1; }
</style>
</head>
<body>
<main>
  <h1>&#127796; Bottle Mail <span class="muted">发信台</span></h1>

  <section id="loginView" class="card">
    <h2>登录</h2>
    <input id="password" type="password" placeholder="发送密码" autocomplete="current-password">
    <div class="row" style="margin-top:10px">
      <button id="loginBtn">登录</button>
    </div>
    <div id="loginMsg" class="msg"></div>
  </section>

  <section id="appView" class="hidden">
    <div class="row">
      <span class="muted" id="whoami"></span>
      <button id="logoutBtn">登出</button>
    </div>

    <section class="card">
      <h2>&#9993; 写一封信</h2>
      <textarea id="body" maxlength="2000" placeholder="写下想对她说的话…（最多 2000 字，支持换行和 Emoji）"></textarea>
      <div class="row" style="margin-top:10px">
        <span class="muted" id="counter">0 / 2000</span>
        <button id="sendBtn">装进漂流瓶</button>
      </div>
      <div id="sendMsg" class="msg"></div>
    </section>

    <section class="card">
      <h2>&#128274; 设备激活码</h2>
      <p class="muted">在收信端的 WarawaraPet 里输入一次即可绑定设备。每个码只能兑换一次，30 分钟内有效。</p>
      <div class="row">
        <button id="newCodeBtn">生成新激活码</button>
      </div>
      <div id="codeMsg" class="msg"></div>
      <ul id="codeList"></ul>
    </section>

    <section class="card">
      <h2>&#128241; 已绑定设备</h2>
      <ul id="deviceList"></ul>
    </section>

    <section class="card">
      <h2>&#128230; 已发出的信</h2>
      <ul id="letterList"></ul>
    </section>
  </section>
</main>

<script>
"use strict";
const $ = (id) => document.getElementById(id);

function csrfToken() {
  const match = document.cookie.match(/(?:^|;\\s*)bottlemail_csrf=([^;]+)/);
  return match ? decodeURIComponent(match[1]) : "";
}

async function api(method, path, body) {
  const headers = { "X-CSRF-Token": csrfToken() };
  if (body !== undefined) headers["Content-Type"] = "application/json";
  const response = await fetch(path, {
    method,
    headers,
    body: body === undefined ? undefined : JSON.stringify(body),
    credentials: "same-origin",
  });
  let data = null;
  try { data = await response.json(); } catch (_) { /* no body */ }
  return { status: response.status, data };
}

// ---- Safe renderers: every dynamic value goes through textContent ----
function makeLi(className) {
  const li = document.createElement("li");
  if (className) li.className = className;
  return li;
}
function makePill(text, read) {
  const pill = document.createElement("span");
  pill.className = "pill" + (read ? " read" : "");
  pill.textContent = text;
  return pill;
}
function makeMuted(text) {
  const muted = document.createElement("span");
  muted.className = "muted";
  muted.textContent = text;
  return muted;
}

function renderDeviceList(container, devices) {
  container.textContent = "";
  for (const device of devices || []) {
    const li = makeLi();
    const main = document.createElement("div");
    main.className = "li-main";
    const name = document.createElement("span");
    name.textContent = device.label;
    main.appendChild(name);
    main.appendChild(document.createTextNode(" "));
    main.appendChild(makeMuted("(" + (device.id || "").slice(0, 8) + ")"));
    li.appendChild(main);
    if (device.revoked_at) {
      li.appendChild(makePill("已撤销", false));
    } else {
      const button = document.createElement("button");
      button.textContent = "撤销";
      button.addEventListener("click", async () => {
        const { status } = await api("POST", "/api/admin/devices/" + encodeURIComponent(device.id) + "/revoke");
        if (status === 200 || status === 404) refreshDevices();
      });
      li.appendChild(button);
    }
    container.appendChild(li);
  }
}

function renderCodeList(container, codes) {
  container.textContent = "";
  for (const entry of codes || []) {
    const li = makeLi();
    li.appendChild(makeMuted((entry.code_hash || "").slice(0, 12) + "…"));
    li.appendChild(makePill(entry.used_at ? "已使用" : "未使用", Boolean(entry.used_at)));
    li.appendChild(makeMuted(new Date(entry.created_at).toLocaleString()));
    container.appendChild(li);
  }
}

function renderLetterList(container, letters) {
  container.textContent = "";
  for (const letter of letters || []) {
    const li = makeLi();
    const main = document.createElement("div");
    main.className = "li-main";
    const preview = document.createElement("div");
    preview.className = "pre";
    preview.textContent = (letter.body || "").slice(0, 160)
      + ((letter.body || "").length > 160 ? "…" : "");
    main.appendChild(preview);
    main.appendChild(makeMuted(new Date(letter.created_at).toLocaleString()));
    li.appendChild(main);
    li.appendChild(makePill(letter.opened_at ? "已读" : "未读", Boolean(letter.opened_at)));
    container.appendChild(li);
  }
}

function renderCodeMessage(container, code, expiresAt) {
  container.textContent = "";
  container.className = "msg ok";
  const label = document.createElement("div");
  label.textContent = "请把下面这个码给她（只显示这一次，" + new Date(expiresAt).toLocaleTimeString() + " 前有效）：";
  const codeBox = document.createElement("div");
  codeBox.className = "code";
  codeBox.style.marginTop = "6px";
  codeBox.textContent = code;
  container.appendChild(label);
  container.appendChild(codeBox);
}

// Test/QA hooks (no secrets; pure renderers only).
window.BottleMailPage = { renderDeviceList, renderCodeList, renderLetterList, renderCodeMessage };

async function refreshAll() {
  refreshCodes();
  refreshDevices();
  refreshLetters();
}

async function refreshCodes() {
  const { status, data } = await api("GET", "/api/admin/activation-codes");
  if (status !== 200) return;
  renderCodeList($("codeList"), data.codes);
}

async function refreshDevices() {
  const { status, data } = await api("GET", "/api/admin/devices");
  if (status !== 200) return;
  renderDeviceList($("deviceList"), data.devices);
}

async function refreshLetters() {
  const { status, data } = await api("GET", "/api/admin/letters");
  if (status !== 200) return;
  renderLetterList($("letterList"), data.letters);
}

async function tryLogin() {
  $("loginMsg").textContent = "";
  const { status, data } = await api("POST", "/api/session", { password: $("password").value });
  if (status === 200) { showApp(); }
  else if (status === 429) { $("loginMsg").textContent = "尝试次数过多，请稍后再试。"; }
  else if (status === 401) { $("loginMsg").textContent = "密码不正确。"; }
  else { $("loginMsg").textContent = "登录失败：" + (data && data.error ? data.error : status); }
}

async function showApp() {
  $("loginView").classList.add("hidden");
  $("appView").classList.remove("hidden");
  $("whoami").textContent = "已登录 · 发送者";
  refreshAll();
}

let pendingSend = null;

async function sendLetter() {
  const body = $("body").value;
  if (!body.trim()) { $("sendMsg").className = "msg err"; $("sendMsg").textContent = "先写点什么吧。"; return; }
  if (!pendingSend) pendingSend = crypto.randomUUID();
  $("sendBtn").disabled = true;
  $("sendMsg").className = "msg"; $("sendMsg").textContent = "漂流瓶出发中…";
  try {
    const { status, data } = await api("POST", "/api/letters",
      { body: body.trim(), client_request_id: pendingSend });
    if (status === 201 || status === 200) {
      $("sendMsg").className = "msg ok";
      $("sendMsg").textContent = status === 201
        ? "已寄出并保存至云端！她下次联网时 WarawaraPet 会收到这封信。"
        : "已寄出并保存至云端（重试成功，未重复发送）。";
      $("body").value = "";
      pendingSend = null;
      refreshLetters();
    } else if (status === 429) {
      $("sendMsg").className = "msg err"; $("sendMsg").textContent = "发送太频繁，稍后再试。";
    } else if (status === 401) {
      backToLogin();
    } else {
      $("sendMsg").className = "msg err";
      $("sendMsg").textContent = "发送失败（" + (data && data.error ? data.error : status) + "）。重试不会重复发送。";
    }
  } catch (_) {
    $("sendMsg").className = "msg err";
    $("sendMsg").textContent = "网络错误。可稍后点击重试，不会重复发送。";
  } finally {
    $("sendBtn").disabled = false;
  }
}

function backToLogin() {
  $("appView").classList.add("hidden");
  $("loginView").classList.remove("hidden");
  pendingSend = null;
}

async function newCode() {
  const { status, data } = await api("POST", "/api/admin/activation-codes");
  if (status === 201) {
    renderCodeMessage($("codeMsg"), data.code, data.expires_at);
    refreshCodes();
  } else if (status === 401) { backToLogin(); }
  else { $("codeMsg").className = "msg err"; $("codeMsg").textContent = "生成失败，请重试。"; }
}

$("loginBtn").onclick = tryLogin;
$("password").addEventListener("keydown", (event) => { if (event.key === "Enter") tryLogin(); });
$("logoutBtn").onclick = async () => { await api("POST", "/api/session/logout"); backToLogin(); };
$("sendBtn").onclick = sendLetter;
$("newCodeBtn").onclick = newCode;
$("body").addEventListener("input", () => { $("counter").textContent = $("body").value.length + " / 2000"; });

(async () => {
  const { status } = await api("GET", "/api/admin/letters");
  if (status === 200) showApp();
})();
</script>
</body>
</html>`;
}
