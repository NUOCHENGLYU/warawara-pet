/// Repository contract: the handlers only talk to these interfaces.
/// Production implements them over D1 (`repo/d1.ts`); the unit test
/// suite uses the deterministic in-memory implementation
/// (`repo/memory.ts`), and the integration suite runs the REAL D1
/// implementation against Miniflare's local SQLite.
///
/// `activateDevice` is a SINGLE atomic operation spanning the activation
/// code and the device row: a consumed code must always end up with a
/// device, and a failed device insert must never consume the code.

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

export interface LetterRepository {
  /** Insert-or-deduplicate: same id OR same client_request_id returns
   *  the existing letter with created=false. Race-safe under D1: the
   *  insert uses INSERT OR IGNORE, so concurrent identical requests can
   *  never surface a unique-constraint error. */
  insertLetter(input: {
    id: string;
    body: string;
    createdAt: string;
    clientRequestId: string | null;
  }): Promise<{ record: LetterRecord; created: boolean }>;

  listLetters(afterSeq: number, limit: number): Promise<LetterRecord[]>;

  findLetterById(id: string): Promise<LetterRecord | null>;

  /** Sender-only removal (cleaning up development/test letters before
   *  the real recipient ever activates). Returns true when a letter was
   *  actually deleted. */
  deleteLetter(id: string): Promise<boolean>;

  /** Idempotent: sets opened_at only when it is still null. */
  markOpened(
    id: string,
    at: string
  ): Promise<{ record: LetterRecord; alreadyOpened: boolean }>;
}

export interface ActivationRepository {
  createCode(codeHash: string, createdAt: string, expiresAt: string): Promise<void>;
  listCodes(): Promise<
    Array<{ code_hash: string; created_at: string; expires_at: string; used_at: string | null }>
  >;
}

export interface DeviceRepository {
  findDeviceByTokenHash(tokenHash: string): Promise<DeviceRecord | null>;
  listDevices(): Promise<DeviceRecord[]>;
  revokeDevice(id: string, at: string): Promise<boolean>;
}

export type ActivateDeviceResult =
  | { ok: true; device: DeviceRecord }
  | { ok: false; reason: "invalid" | "expired" | "used" };

export interface Repos {
  letters: LetterRepository;
  activations: ActivationRepository;
  devices: DeviceRepository;
  /** Atomically redeems an activation code AND binds the device in the
   *  same transaction: `activation_codes.device_id` always equals the
   *  created `devices.id`, the code can only be consumed once even under
   *  concurrency, and a failed device insert leaves the code untouched. */
  activateDevice(input: {
    codeHash: string;
    at: string;
    deviceId: string;
    tokenHash: string;
    label: string;
  }): Promise<ActivateDeviceResult>;
}
