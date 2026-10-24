/// The private sender page. Served at `/` by the same worker, so it is
/// same-origin: sessions, the CSRF cookie and every call stay in one
/// place. Plain HTML + vanilla JS — no framework, no secrets in code.
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

async function refreshAll() {
  refreshCodes();
  refreshDevices();
  refreshLetters();
}

async function refreshCodes() {
  const { status, data } = await api("GET", "/api/admin/activation-codes");
  if (status !== 200) return;
  $("codeList").innerHTML = (data.codes || []).map((c) =>
    \`<li><span>\${c.code_hash.slice(0, 12)}…</span>
       <span class="pill \${c.used_at ? "read" : ""}">\${c.used_at ? "已使用" : "未使用"}</span>
       <span class="muted">\${new Date(c.created_at).toLocaleString()}</span></li>\`
  ).join("");
}

async function refreshDevices() {
  const { status, data } = await api("GET", "/api/admin/devices");
  if (status !== 200) return;
  $("deviceList").innerHTML = (data.devices || []).map((d) =>
    \`<li><span>\${d.label} <span class="muted">(\${d.id.slice(0, 8)})</span></span>
       <span>\${d.revoked_at
         ? \`<span class="pill">已撤销</span>\`
         : \`<button data-device="\${d.id}" class="revokeBtn">撤销</button>\`}</span></li>\`
  ).join("");
  document.querySelectorAll(".revokeBtn").forEach((btn) => {
    btn.onclick = async () => {
      const { status } = await api("POST", \`/api/admin/devices/\${encodeURIComponent(btn.dataset.device)}/revoke\`);
      if (status === 200 || status === 404) refreshDevices();
    };
  });
}

async function refreshLetters() {
  const { status, data } = await api("GET", "/api/admin/letters");
  if (status !== 200) return;
  $("letterList").innerHTML = (data.letters || []).map((letter) =>
    \`<li><div style="flex:1"><div class="pre">\${escapeHtml(letter.body.slice(0, 160))}\${letter.body.length > 160 ? "…" : ""}</div>
      <span class="muted">\${new Date(letter.created_at).toLocaleString()}</span></div>
      <span class="pill \${letter.opened_at ? "read" : ""}">\${letter.opened_at ? "已读" : "未读"}</span></li>\`
  ).join("");
}

function escapeHtml(text) {
  return text.replace(/[&<>"']/g, (ch) => ({"&":"&amp;","<":"&lt;",">":"&gt;","\\"":"&quot;","'":"&#39;"}[ch]));
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
  const { data } = await api("GET", "/api/admin/letters");
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
        ? "已送达！她下次联网时 WarawaraPet 会收到这封信。"
        : "已送达（重试成功，未重复发送）。";
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
    $("codeMsg").className = "msg ok";
    $("codeMsg").innerHTML = \`请把下面这个码给她（只显示这一次，\${new Date(data.expires_at).toLocaleTimeString()} 前有效）：<div class="code" style="margin-top:6px">\${data.code}</div>\`;
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
