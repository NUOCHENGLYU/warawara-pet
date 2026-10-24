/// Repository contract: the handlers only talk to these interfaces.
/// Production implements them over D1 (`repo/d1.ts`); the test suite
/// uses the deterministic in-memory implementation (`repo/memory.ts`),
/// so every handler rule can be verified without a Cloudflare account.

export interface LetterRecord {
  seq: number;
  id: string;
  body: string;
  created_at: string;
  opened_at: string | null;
}

export interface DeviceRecord {
  id: string;
  label: string;
  created_at: string;
  revoked_at: string | null;
}

export interface ActivationRecord {
  created_at: string;
  expires_at: string;
  used_at: string | null;
}

export interface LetterRepository {
  /** Insert-or-deduplicate: same id OR same client_request_id returns
   *  the existing letter with created=false. */
  insertLetter(input: {
    id: string;
    body: string;
    createdAt: string;
    clientRequestId: string | null;
  }): Promise<{ record: LetterRecord; created: boolean }>;

  listLetters(afterSeq: number, limit: number): Promise<LetterRecord[]>;

  findLetterById(id: string): Promise<LetterRecord | null>;

  /** Idempotent: sets opened_at only when it is still null. */
  markOpened(
    id: string,
    at: string
  ): Promise<{ record: LetterRecord; alreadyOpened: boolean }>;
}

export interface ActivationRepository {
  createCode(codeHash: string, createdAt: string, expiresAt: string): Promise<void>;
  redeemCode(
    codeHash: string,
    at: string,
    deviceId: string
  ): Promise<{ ok: true } | { ok: false; reason: "invalid" | "expired" | "used" }>;
  listCodes(): Promise<
    Array<{ code_hash: string; created_at: string; expires_at: string; used_at: string | null }>
  >;
}

export interface DeviceRepository {
  createDevice(id: string, tokenHash: string, label: string, createdAt: string): Promise<void>;
  findDeviceByTokenHash(tokenHash: string): Promise<DeviceRecord | null>;
  listDevices(): Promise<DeviceRecord[]>;
  revokeDevice(id: string, at: string): Promise<boolean>;
}

export interface Repos {
  letters: LetterRepository;
  activations: ActivationRepository;
  devices: DeviceRepository;
}
