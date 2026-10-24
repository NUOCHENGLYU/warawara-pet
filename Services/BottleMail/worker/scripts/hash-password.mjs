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

const iterations = 310000;

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

const providedSalt = process.argv[2];
const saltHex = providedSalt
  ? providedSalt.trim()
  : bytesToHex(crypto.getRandomValues(new Uint8Array(16)));

const password = await readSecret("输入发送密码（不回显）: ");

if (password.length === 0) {
  console.error("密码不能为空。");
  process.exit(1);
}

const hash = await pbkdf2Hex(password, saltHex, iterations);

console.log("");
console.log("将下面两个值通过 npx wrangler secret put 配置：");
console.log(`  SENDER_PASSWORD_SALT=${saltHex}`);
console.log(`  SENDER_PASSWORD_HASH=${hash}`);
console.log(`(PBKDF2-SHA256, ${iterations} iterations)`);
