// Generates SENDER_PASSWORD_SALT + SENDER_PASSWORD_HASH for wrangler secrets.
// Usage:  node scripts/hash-password.mjs          (password from stdin)
//         node scripts/hash-password.mjs <saltHex>  (reuse an existing salt)
import { createInterface } from "node:readline";

const iterations = 310000;

async function readLine(prompt) {
  const rl = createInterface({ input: process.stdin, output: process.stdout });
  return new Promise((resolve) => {
    rl.question(prompt, (answer) => {
      rl.close();
      resolve(answer);
    });
  });
}

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

const providedSalt = process.argv[2];
const saltHex = providedSalt
  ? providedSalt.trim()
  : bytesToHex(crypto.getRandomValues(new Uint8Array(16)));

const password = await readLine("输入发送密码（不回显）: ");

const hash = await pbkdf2Hex(password, saltHex, iterations);

console.log("");
console.log("将下面两个值通过 npx wrangler secret put 配置：");
console.log(`  SENDER_PASSWORD_SALT=${saltHex}`);
console.log(`  SENDER_PASSWORD_HASH=${hash}`);
console.log(`(PBKDF2-SHA256, ${iterations} iterations)`);
