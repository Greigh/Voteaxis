/**
 * Reader half of the end-to-end encrypted share link.
 *
 * The wire format is fixed by mobile/lib/services/result_envelope.dart, which
 * seals the payload. The password never leaves this browser: we derive the
 * same PBKDF2 key and let the AES-GCM tag decide whether it was right. The
 * Voteaxis server stores the ciphertext and has no key, so a wrong guess is
 * answered here, offline, with nothing to report to anyone.
 */

export const ENVELOPE_VERSION = 1;
export const ENVELOPE_KDF = "pbkdf2-sha256";
export const MIN_PASSWORD_LENGTH = 8;

/**
 * The most PBKDF2 rounds this reader will agree to run.
 *
 * The count is chosen by whoever published the link and paid for by whoever
 * opens it, on their device, with no say in the number — so an unbounded value
 * is a way to hang a stranger's browser. The app seals at 210,000, and the API
 * refuses to store anything above this (`server/src/results.ts`); the check is
 * repeated here because a reader should not have to trust that the server was
 * strict. There is deliberately no floor: a low count only weakens the
 * author's own link, and rejecting one would dark-link an existing share.
 */
export const MAX_ITERATIONS = 600_000;

export type EncryptedEnvelope = {
  v: number;
  kdf: string;
  iterations: number;
  salt: string;
  nonce: string;
  ciphertext: string;
};

export function isEnvelope(value: unknown): value is EncryptedEnvelope {
  if (typeof value !== "object" || value === null) return false;
  const raw = value as Record<string, unknown>;
  return (
    raw.v === ENVELOPE_VERSION &&
    raw.kdf === ENVELOPE_KDF &&
    typeof raw.iterations === "number" &&
    Number.isInteger(raw.iterations) &&
    raw.iterations > 0 &&
    raw.iterations <= MAX_ITERATIONS &&
    typeof raw.salt === "string" &&
    typeof raw.nonce === "string" &&
    typeof raw.ciphertext === "string"
  );
}

/**
 * Backed by a real ArrayBuffer rather than a SharedArrayBuffer, which is what
 * WebCrypto's BufferSource parameters require.
 */
export function base64ToBytes(value: string): Uint8Array<ArrayBuffer> {
  const binary = atob(value);
  const bytes = new Uint8Array(new ArrayBuffer(binary.length));
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes;
}

/**
 * Returns the decrypted payload, or null when the password is wrong — an
 * authentication failure is indistinguishable from corruption by design, and
 * both mean "you cannot read this".
 */
export async function openEnvelope(
  envelope: EncryptedEnvelope,
  password: string,
  subtle: SubtleCrypto = crypto.subtle,
): Promise<Record<string, unknown> | null> {
  if (!isEnvelope(envelope)) return null;
  try {
    const material = await subtle.importKey(
      "raw",
      new TextEncoder().encode(password) as Uint8Array<ArrayBuffer>,
      "PBKDF2",
      false,
      ["deriveKey"],
    );
    const key = await subtle.deriveKey(
      {
        name: "PBKDF2",
        salt: base64ToBytes(envelope.salt),
        iterations: envelope.iterations,
        hash: "SHA-256",
      },
      material,
      { name: "AES-GCM", length: 256 },
      false,
      ["decrypt"],
    );
    // The app appends the 16-byte GCM tag to the ciphertext, which is exactly
    // what WebCrypto expects to receive as one buffer.
    const plain = await subtle.decrypt(
      { name: "AES-GCM", iv: base64ToBytes(envelope.nonce) },
      key,
      base64ToBytes(envelope.ciphertext),
    );
    const decoded: unknown = JSON.parse(new TextDecoder().decode(plain));
    if (
      typeof decoded !== "object" ||
      decoded === null ||
      Array.isArray(decoded)
    ) {
      return null;
    }
    return decoded as Record<string, unknown>;
  } catch {
    return null;
  }
}
