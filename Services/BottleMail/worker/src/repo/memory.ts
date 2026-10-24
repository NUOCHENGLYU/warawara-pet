import type {
  ActivateDeviceResult,
  ActivationRepository,
  DeviceRecord,
  DeviceRepository,
  LetterRecord,
  LetterRepository,
  Repos,
} from "./types.js";

/// Deterministic in-memory repositories for unit tests and local
/// preview. Mirrors the D1 semantics (race-free idempotent inserts,
/// single-use codes bound to their device, idempotent opened_at)
/// without any SQL. Single-threaded: atomicity is trivially satisfied.
export function createMemoryRepos(): Repos {
  const letters = new Map<string, LetterRecord>(); // by id
  const lettersByClientRequestId = new Map<string, LetterRecord>();
  const clientRequestIdByLetterId = new Map<string, string>();
  const letterOrder: LetterRecord[] = [];
  const devices = new Map<string, DeviceRecord & { token_hash: string }>(); // by id
  const devicesByTokenHash = new Map<string, string>(); // token_hash -> id
  const codes = new Map<string, { created_at: string; expires_at: string; used_at: string | null; device_id: string | null }>();

  let nextSeq = 1;

  const letterRepo: LetterRepository = {
    async insertLetter(input) {
      const existing =
        letters.get(input.id) ??
        (input.clientRequestId ? lettersByClientRequestId.get(input.clientRequestId) : undefined);
      if (existing) return { record: existing, created: false };
      const record: LetterRecord = {
        seq: nextSeq,
        id: input.id,
        body: input.body,
        created_at: input.createdAt,
        opened_at: null,
      };
      nextSeq += 1;
      letters.set(record.id, record);
      letterOrder.push(record);
      if (input.clientRequestId) {
        lettersByClientRequestId.set(input.clientRequestId, record);
        clientRequestIdByLetterId.set(record.id, input.clientRequestId);
      }
      return { record, created: true };
    },

    async listLetters(afterSeq, limit) {
      return letterOrder.filter((letter) => letter.seq > afterSeq).slice(0, limit);
    },

    async findLetterById(id) {
      return letters.get(id) ?? null;
    },

    async deleteLetter(id) {
      const record = letters.get(id);
      if (!record) return false;
      letters.delete(id);
      const clientRequestId = clientRequestIdByLetterId.get(id);
      if (clientRequestId && lettersByClientRequestId.get(clientRequestId) === record) {
        lettersByClientRequestId.delete(clientRequestId);
      }
      clientRequestIdByLetterId.delete(id);
      const index = letterOrder.findIndex((letter) => letter.id === id);
      if (index >= 0) letterOrder.splice(index, 1);
      return true;
    },

    async markOpened(id, at) {
      const record = letters.get(id);
      if (!record) throw new Error("letter not found");
      const alreadyOpened = record.opened_at !== null;
      if (!alreadyOpened) record.opened_at = at;
      return { record, alreadyOpened };
    },
  };

  const activationRepo: ActivationRepository = {
    async createCode(codeHash, createdAt, expiresAt) {
      codes.set(codeHash, { created_at: createdAt, expires_at: expiresAt, used_at: null, device_id: null });
    },

    async listCodes() {
      return Array.from(codes.entries()).map(([code_hash, code]) => ({
        code_hash,
        created_at: code.created_at,
        expires_at: code.expires_at,
        used_at: code.used_at,
      }));
    },
  };

  const deviceRepo: DeviceRepository = {
    async findDeviceByTokenHash(tokenHash) {
      const id = devicesByTokenHash.get(tokenHash);
      if (!id) return null;
      const record = devices.get(id);
      if (!record) return null;
      return {
        id: record.id,
        label: record.label,
        created_at: record.created_at,
        revoked_at: record.revoked_at,
      };
    },

    async listDevices() {
      return Array.from(devices.values()).map((record) => ({
        id: record.id,
        label: record.label,
        created_at: record.created_at,
        revoked_at: record.revoked_at,
      }));
    },

    async revokeDevice(id, at) {
      const record = devices.get(id);
      if (!record || record.revoked_at !== null) return false;
      record.revoked_at = at;
      return true;
    },
  };

  const activateDevice: Repos["activateDevice"] = async (input): Promise<ActivateDeviceResult> => {
    const code = codes.get(input.codeHash);
    if (!code) return { ok: false, reason: "invalid" };
    if (code.used_at !== null) return { ok: false, reason: "used" };
    if (code.expires_at < input.at) return { ok: false, reason: "expired" };
    code.used_at = input.at;
    code.device_id = input.deviceId;
    const device: DeviceRecord & { token_hash: string } = {
      id: input.deviceId,
      token_hash: input.tokenHash,
      label: input.label,
      created_at: input.at,
      revoked_at: null,
    };
    devices.set(device.id, device);
    devicesByTokenHash.set(device.token_hash, device.id);
    return {
      ok: true,
      device: {
        id: device.id,
        label: device.label,
        created_at: device.created_at,
        revoked_at: device.revoked_at,
      },
    };
  };

  return { letters: letterRepo, activations: activationRepo, devices: deviceRepo, activateDevice };
}
