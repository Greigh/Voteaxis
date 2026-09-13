/** Unambiguous 6-character codes. No 0/O, 1/I/L. */
export const ALPHABET = "23456789ABCDEFGHJKMNPQRSTUVWXYZ";
export const CODE_LENGTH = 6;
export const TOKEN_BYTES = 24;
export const TOKEN_LENGTH = TOKEN_BYTES * 2;

const TOKEN_HEX = /^[0-9a-f]{48}$/;
/** Largest multiple of the alphabet length that fits in a byte. */
const CODE_BYTE_MAX = 31 * 8;

export function randomCode(): string {
  let out = "";
  while (out.length < CODE_LENGTH) {
    const bytes = crypto.getRandomValues(new Uint8Array(CODE_LENGTH - out.length));
    for (const b of bytes) {
      if (b >= CODE_BYTE_MAX) continue;
      out += ALPHABET[b % ALPHABET.length];
      if (out.length === CODE_LENGTH) break;
    }
  }
  return out;
}

export function randomToken(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(TOKEN_BYTES));
  return Buffer.from(bytes).toString("hex");
}

/** Server-minted write tokens only. Client-chosen strings are ignored. */
export function normalizeToken(raw: unknown): string | undefined {
  if (typeof raw !== "string") return undefined;
  const token = raw.trim().toLowerCase();
  if (!TOKEN_HEX.test(token)) return undefined;
  return token;
}

export function normalizeCode(raw: string): string | null {
  const cleaned = raw.toUpperCase().replace(/[^0-9A-Z]/g, "");
  if (cleaned.length !== CODE_LENGTH) return null;
  for (const ch of cleaned) {
    if (!ALPHABET.includes(ch)) return null;
  }
  return cleaned;
}
