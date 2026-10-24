export const MAX_LETTER_BODY_LENGTH = 2000;

export interface LetterBodyValidation {
  ok: true;
  body: string;
}
export interface LetterBodyError {
  ok: false;
  message: string;
}

/** Letters are UTF-8 text (Chinese, English, newlines, emoji allowed).
 *  Only real restrictions: non-empty after trimming, <= 2000 chars,
 *  and no NUL bytes. */
export function validateLetterBody(input: unknown): LetterBodyValidation | LetterBodyError {
  if (typeof input !== "string") return { ok: false, message: "body must be a string" };
  const body = input.trim();
  if (body.length === 0) return { ok: false, message: "body must not be empty" };
  if (body.length > MAX_LETTER_BODY_LENGTH) {
    return { ok: false, message: `body must be at most ${MAX_LETTER_BODY_LENGTH} characters` };
  }
  if (body.includes("\u0000")) return { ok: false, message: "body contains invalid characters" };
  return { ok: true, body };
}

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export function isUuid(input: string): boolean {
  return UUID_RE.test(input);
}

export function validateClientRequestId(input: unknown): string | null | undefined {
  if (input === undefined || input === null || input === "") return null;
  if (typeof input !== "string") return undefined; // invalid -> reject
  if (!isUuid(input)) return undefined;
  return input;
}

const CODE_RE = /^[A-Z2-9]{8,32}$/;

/** Activation codes: readable base32-ish charset, 8-32 chars. */
export function isValidActivationCodeShape(input: string): boolean {
  return CODE_RE.test(input);
}

export function validateDeviceLabel(input: unknown): string {
  if (input === undefined || input === null || input === "") return "warawara";
  if (typeof input !== "string") return "warawara";
  const label = input.trim().slice(0, 64);
  return label || "warawara";
}
