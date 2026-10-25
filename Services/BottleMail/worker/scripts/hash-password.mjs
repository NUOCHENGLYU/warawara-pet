// Generates SENDER_PASSWORD_SALT + SENDER_PASSWORD_HASH for wrangler secrets.
// Usage:  node scripts/hash-password.mjs          (password from stdin, NO echo)
//         node scripts/hash-password.mjs <saltHex>  (reuse an existing salt)
//
// Password input never appears on the terminal and is never written to
// any file or log. On a real console (Windows PowerShell / cmd, macOS
// Terminal) the terminal is put into raw mode and keystrokes are
// consumed directly. When stdin is piped/redirected (not a TTY) a plain
// line is read — nothing is echoed in that case either.
import { createInterface } from "node:readline";

// PBKDF2-SHA256 iteration count. MUST stay in sync with
// wrangler.jsonc `SENDER_PASSWORD_ITERATIONS`. 10 000 keeps the
// derivation inside the Cloudflare Workers FREE plan's 10 ms CPU budget
// (~3 ms measured); depth comes from the random 128-bit salt plus the
// durable login lockout (10 attempts / 15 min / IP).
const iterations = 10000;

function bytesToHex(bytes) {
  return Array.from(bytes, (b) => b.toString(16).padStart(2, "0")).join("");
}

function hexToBytes(hex) {
  const clean = hex.trim();
  const out = new Uint8Array(clean.length / 2);
  for (let i = 0; i < out.length; i += 1) {
    out[i] = Number.parseInt(clean.slice(i * 2, i * 2 + 2), 16);
  }
  return out;
}

async function pbkdf2Hex(password, saltHex, iter) {
  const keyMaterial = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(password),
    "PBKDF2",
    false,
    ["deriveBits"]
  );
  const bits = await crypto.subtle.deriveBits(
    { name: "PBKDF2", hash: "SHA-256", salt: hexToBytes(saltHex), iterations: iter },
    keyMaterial,
    256
  );
  return bytesToHex(new Uint8Array(bits));
}

/// Reads one line with the terminal echo disabled.
async function readSecret(prompt) {
  process.stdout.write(prompt);

  if (!process.stdin.isTTY || typeof process.stdin.setRawMode !== "function") {
    // Piped/redirected input: nothing to hide, nothing is echoed.
    const rl = createInterface({ input: process.stdin });
    const line = await new Promise((resolve) => {
      rl.question("", (answer) => {
        rl.close();
        resolve(answer);
      });
    });
    process.stdout.write("\n");
    return line.replace(/\r?\n$/, "");
  }

  // Real console: raw mode, consume keystrokes ourselves, print nothing.
  process.stdin.setRawMode(true);
  process.stdin.resume();
  return new Promise((resolve) => {
    let value = "";
    const onData = (chunk) => {
      const text = chunk.toString("utf8");
      for (const ch of text) {
        if (ch === "\r" || ch === "\n") {
          cleanup();
          resolve(value);
          return;
        }
        if (ch === "\u0003") {
          cleanup();
          process.exit(130);
        }
        if (ch === "\b" || ch === "\u007f") {
          value = value.slice(0, -1);
        } else if (ch >= " ") {
          value += ch;
        }
      }
    };
    const cleanup = () => {
      process.stdin.off("data", onData);
      process.stdin.setRawMode(false);
      process.stdin.pause();
      process.stdout.write("\n");
    };
    process.stdin.on("data", onData);
  });
}

const providedSalt = process.argv[2] === "--apply-secrets" ? undefined : process.argv[2];
const applySecrets = process.argv.includes("--apply-secrets");
const saltHex = providedSalt
  ? providedSalt.trim()
  : bytesToHex(crypto.getRandomValues(new Uint8Array(16)));

const password = await readSecret("输入发送密码（不回显）: ");

if (password.length === 0) {
  console.error("密码不能为空。");
  process.exit(1);
}

const hash = await pbkdf2Hex(password, saltHex, iterations);

if (applySecrets) {
  // Pipe the derived values straight into wrangler secret put (stdin,
  // no echo, no files, no logs). The plaintext password never leaves
  // this process.
  //
  // Windows note: `spawnSync("npx.cmd", …)` with shell:false is broken
  // (Node >= 20.12 refuses to spawn .cmd batch files directly). We
  // instead run the LOCAL wrangler JavaScript CLI with process.execPath,
  // so no batch wrapper is involved.
  const { spawnSync } = await import("node:child_process");
  const { existsSync } = await import("node:fs");
  const path = await import("node:path");
  const { fileURLToPath } = await import("node:url");

  const scriptDir = path.dirname(fileURLToPath(import.meta.url));
  const wranglerJs = path.resolve(scriptDir, "..", "node_modules", "wrangler", "bin", "wrangler.js");

  if (!existsSync(wranglerJs)) {
    console.error("未找到本地安装的 wrangler（node_modules/wrangler/bin/wrangler.js）。请先运行 npm ci。");
    process.exit(1);
  }

  const runWrangler = (args, options = {}) =>
    spawnSync(process.execPath, [wranglerJs, ...args], {
      stdio: ["pipe", "inherit", "inherit"],
      encoding: "utf8",
      ...options,
    });

  const describeFailure = (result) =>
    `error.code=${result.error?.code ?? "-"} status=${result.status ?? "-"} signal=${result.signal ?? "-"}`;

  // Preflight 1: must be logged in to Cloudflare.
  const who = runWrangler(["whoami"], { stdio: ["ignore", "inherit", "inherit"] });
  if (who.error || who.status !== 0) {
    console.error(`Wrangler 尚未登录 Cloudflare（${describeFailure(who)}）。请先执行 npx wrangler login 后重试。`);
    process.exit(1);
  }

  // Preflight 2: worker config (wrangler.jsonc + bindings) must be valid.
  const dryRun = runWrangler(["deploy", "--dry-run"], { stdio: ["ignore", "inherit", "inherit"] });
  if (dryRun.error || dryRun.status !== 0) {
    console.error(`Worker 配置校验失败（${describeFailure(dryRun)}）。请检查 wrangler.jsonc 后再重试。`);
    process.exit(1);
  }

  const put = (name, value) =>
    runWrangler(["secret", "put", name], { input: value });

  const saltResult = put("SENDER_PASSWORD_SALT", saltHex);
  if (saltResult.error || saltResult.status !== 0) {
    console.error(`配置 SENDER_PASSWORD_SALT 失败（${describeFailure(saltResult)}）。`);
    process.exit(1);
  }
  const hashResult = put("SENDER_PASSWORD_HASH", hash);
  if (hashResult.error || hashResult.status !== 0) {
    console.error(`配置 SENDER_PASSWORD_HASH 失败（${describeFailure(hashResult)}）。`);
    process.exit(1);
  }
  console.log("");
  console.log("两个 Secret 已配置完成（明文密码未出现在任何地方）。");
  console.log("salt 与 hash 已写入 Cloudflare，请勿再手动输出。");
  process.exit(0);
}

console.log("");
console.log("将下面两个值通过 npx wrangler secret put 配置：");
console.log(`  SENDER_PASSWORD_SALT=${saltHex}`);
console.log(`  SENDER_PASSWORD_HASH=${hash}`);
console.log(`(PBKDF2-SHA256, ${iterations} iterations)`);
