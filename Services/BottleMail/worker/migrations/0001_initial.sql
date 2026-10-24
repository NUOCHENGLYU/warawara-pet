-- Bottle Mail initial schema (Cloudflare D1 / SQLite).
-- Applied with: npx wrangler d1 migrations apply bottlemail-db

-- One recipient device at a time; the stored token is a SHA-256 hash of
-- the bearer token, so a DB leak never exposes a usable token.
CREATE TABLE devices (
  id TEXT PRIMARY KEY,
  token_hash TEXT NOT NULL UNIQUE,
  label TEXT NOT NULL DEFAULT 'warawara',
  created_at TEXT NOT NULL,
  revoked_at TEXT
);

-- One-time activation codes. Only the SHA-256 hash is stored; the
-- plaintext is shown to the sender exactly once at creation.
CREATE TABLE activation_codes (
  code_hash TEXT PRIMARY KEY,
  created_at TEXT NOT NULL,
  expires_at TEXT NOT NULL,
  used_at TEXT,
  device_id TEXT
);

-- Letters: sender -> the recipient. Never deleted by polling; opened_at
-- is only set when the recipient actually opens the letter.
-- client_request_id (optional) makes sender retries idempotent.
CREATE TABLE letters (
  seq INTEGER PRIMARY KEY AUTOINCREMENT,
  id TEXT NOT NULL UNIQUE,
  body TEXT NOT NULL,
  created_at TEXT NOT NULL,
  opened_at TEXT,
  client_request_id TEXT UNIQUE
);
