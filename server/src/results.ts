/**
 * Shared result pages: `https://voteaxis.org/result/<id>`.
 *
 * One link both moves a placement to a new phone and shows a friend where you
 * landed.
 *
 * A link is stored one of two ways, and the server never chooses:
 *
 *  - **Open link** — plaintext scores. Anyone holding the URL can read them,
 *    which is the whole point, and the server can render a preview.
 *  - **Password-protected link** — an opaque [EncryptedEnvelope] sealed on the
 *    author's device with AES-GCM under a PBKDF2 key. The password never
 *    reaches this process, so there is nothing here to check it against and
 *    nothing to leak. The server stores bytes it cannot read and hands them
 *    back verbatim; the reader's browser or phone does the decryption.
 *
 * Either way a link is revocable and expires. Quiz answers never leave the
 * device at all — sharing a result is a separate, deliberate opt-in.
 */

/** Lowercase, unambiguous, and safe in a URL path. */
export const RESULT_ALPHABET = "23456789abcdefghjkmnpqrstuvwxyz";
export const RESULT_ID_LENGTH = 16;
const RESULT_ID = new RegExp(`^[${RESULT_ALPHABET}]{${RESULT_ID_LENGTH}}$`);
const ALPHABET_BYTE_MAX = 31 * 8;

const KEY = /^[a-z][a-z0-9_]{0,39}$/;
const MAX_ISSUES = 40;
const STATE = /^[A-Z]{2}$/;
/** Base-32 body with optional dashes, produced by the app's TransferCode. */
const TRANSFER_CODE = /^VX1[-0-9A-Z]{8,400}$/;

/** Ciphertext is base64 of a small JSON blob; this is generous headroom. */
const MAX_ENVELOPE_B64 = 8192;

/**
 * PBKDF2 bounds a reader will actually run.
 *
 * The ceiling is the one that matters: the count is chosen by the author and
 * paid for by the reader, on the reader's device, with no say in the number.
 * Five million rounds pinned a browser tab for minutes. The app publishes at
 * 210,000 (`ResultEnvelope.defaultIterations`), so this leaves a wide margin
 * above anything a real client sends.
 *
 * The floor stays where it was. A low count only weakens the author's own
 * link, the server cannot enforce their password strength anyway, and raising
 * it would dark-link every envelope already sealed below the new value —
 * including the cross-language interop fixture.
 */
const MIN_ITERATIONS = 1000;
export const MAX_ITERATIONS = 600_000;

export function randomResultId(): string {
  let out = "";
  while (out.length < RESULT_ID_LENGTH) {
    const bytes = crypto.getRandomValues(
      new Uint8Array(RESULT_ID_LENGTH - out.length),
    );
    for (const b of bytes) {
      if (b >= ALPHABET_BYTE_MAX) continue;
      out += RESULT_ALPHABET[b % RESULT_ALPHABET.length];
      if (out.length === RESULT_ID_LENGTH) break;
    }
  }
  return out;
}

export function normalizeResultId(raw: string): string | null {
  const cleaned = raw.trim().toLowerCase();
  return RESULT_ID.test(cleaned) ? cleaned : null;
}

function isScore(n: unknown): n is number {
  return typeof n === "number" && Number.isFinite(n) && n >= -100 && n <= 100;
}

function scoreMap(
  value: unknown,
  label: string,
  { max = 100 } = {},
): Record<string, number> | string {
  if (value == null) return {};
  if (typeof value !== "object" || Array.isArray(value)) {
    return `${label} must be an object.`;
  }
  const out: Record<string, number> = {};
  const entries = Object.entries(value as Record<string, unknown>);
  if (entries.length > MAX_ISSUES) return `${label} has too many keys.`;
  for (const [k, v] of entries) {
    if (!KEY.test(k)) return `Invalid ${label} key.`;
    if (typeof v !== "number" || !Number.isFinite(v)) {
      return `Invalid ${label} value.`;
    }
    if (v < -max || v > max) return `Invalid ${label} value.`;
    out[k] = v;
  }
  return out;
}

export type ResultPayload = {
  displayName: string;
  label: string;
  axisScore: number;
  issueScores: Record<string, number>;
  issueWeights: Record<string, number>;
  pillarScores: Record<string, number>;
  dealbreakerIssueIds: string[];
  homeState: string | null;
  /** The app's offline transfer code, so a restore is byte-exact. */
  transferCode: string | null;
  takenAt: number | null;
};

export function parseResultPayload(body: unknown): ResultPayload | string {
  if (typeof body !== "object" || body === null || Array.isArray(body)) {
    return "Invalid body.";
  }
  const raw = body as Record<string, unknown>;

  if (!isScore(raw.axisScore)) {
    return "axisScore must be between -100 and 100.";
  }

  const issueScores = scoreMap(raw.issueScores, "issueScores");
  if (typeof issueScores === "string") return issueScores;
  if (Object.keys(issueScores).length < 1) return "issueScores is required.";

  // Importance weights top out at 2.5, not 100.
  const issueWeights = scoreMap(raw.issueWeights, "issueWeights", { max: 10 });
  if (typeof issueWeights === "string") return issueWeights;

  const pillarScores = scoreMap(raw.pillarScores, "pillarScores");
  if (typeof pillarScores === "string") return pillarScores;

  let displayName = "";
  if (raw.displayName != null) {
    if (typeof raw.displayName !== "string") {
      return "displayName must be a string.";
    }
    displayName = raw.displayName.trim().slice(0, 40);
  }

  let label = "";
  if (raw.label != null) {
    if (typeof raw.label !== "string") return "label must be a string.";
    label = raw.label.trim().slice(0, 40);
  }

  const dealbreakerIssueIds: string[] = [];
  if (raw.dealbreakerIssueIds != null) {
    if (!Array.isArray(raw.dealbreakerIssueIds)) {
      return "dealbreakerIssueIds must be an array.";
    }
    if (raw.dealbreakerIssueIds.length > 3) return "At most 3 dealbreakers.";
    for (const id of raw.dealbreakerIssueIds) {
      if (typeof id !== "string" || !KEY.test(id)) {
        return "Invalid dealbreaker id.";
      }
      dealbreakerIssueIds.push(id);
    }
  }

  let homeState: string | null = null;
  if (raw.homeState != null) {
    if (typeof raw.homeState !== "string") return "homeState must be a string.";
    const upper = raw.homeState.trim().toUpperCase();
    if (upper !== "") {
      if (!STATE.test(upper)) return "homeState must be a 2-letter code.";
      homeState = upper;
    }
  }

  let transferCode: string | null = null;
  if (raw.transferCode != null) {
    if (typeof raw.transferCode !== "string") {
      return "transferCode must be a string.";
    }
    const upper = raw.transferCode.trim().toUpperCase();
    if (upper !== "") {
      if (!TRANSFER_CODE.test(upper)) return "transferCode is not valid.";
      transferCode = upper;
    }
  }

  let takenAt: number | null = null;
  if (raw.takenAt != null) {
    if (typeof raw.takenAt !== "number" || !Number.isFinite(raw.takenAt)) {
      return "takenAt must be a number.";
    }
    takenAt = Math.trunc(raw.takenAt);
  }

  return {
    displayName,
    label,
    axisScore: raw.axisScore,
    issueScores,
    issueWeights,
    pillarScores,
    dealbreakerIssueIds,
    homeState,
    transferCode,
    takenAt,
  };
}

/**
 * The sealed form of a result. Every field is opaque to this process — it is
 * validated for shape and size only, so a client cannot use the row as free
 * storage, and never inspected.
 *
 * The wire format is shared with mobile/lib/services/result_envelope.dart and
 * web/lib/envelope.ts. Bumping ENVELOPE_VERSION dark-links everything already
 * shared, so it needs a migration, not an edit.
 */
export const ENVELOPE_VERSION = 1;
export const ENVELOPE_KDF = "pbkdf2-sha256";
const SALT_BYTES = 16;
const NONCE_BYTES = 12;
/** AES-GCM tag, appended to the ciphertext by WebCrypto. */
const MAC_BYTES = 16;

export type EncryptedEnvelope = {
  v: number;
  kdf: string;
  iterations: number;
  salt: string;
  nonce: string;
  ciphertext: string;
};

function decodedLength(b64: string): number | null {
  if (!/^[A-Za-z0-9+/]+={0,2}$/.test(b64)) return null;
  try {
    return Buffer.from(b64, "base64").length;
  } catch {
    return null;
  }
}

export function parseEnvelope(value: unknown): EncryptedEnvelope | string {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    return "Invalid envelope.";
  }
  const raw = value as Record<string, unknown>;
  if (raw.v !== ENVELOPE_VERSION) return "Unsupported envelope version.";
  if (raw.kdf !== ENVELOPE_KDF) return "Unsupported envelope kdf.";
  if (
    typeof raw.iterations !== "number" ||
    !Number.isInteger(raw.iterations) ||
    raw.iterations < MIN_ITERATIONS ||
    raw.iterations > MAX_ITERATIONS
  ) {
    return "Invalid envelope iterations.";
  }
  for (const key of ["salt", "nonce", "ciphertext"]) {
    if (typeof raw[key] !== "string" || raw[key] === "") {
      return `Invalid envelope ${key}.`;
    }
  }
  const salt = decodedLength(raw.salt as string);
  const nonce = decodedLength(raw.nonce as string);
  const ciphertext = decodedLength(raw.ciphertext as string);
  if (salt !== SALT_BYTES) return "Invalid envelope salt.";
  if (nonce !== NONCE_BYTES) return "Invalid envelope nonce.";
  if (ciphertext === null || ciphertext <= MAC_BYTES) {
    return "Invalid envelope ciphertext.";
  }
  if ((raw.ciphertext as string).length > MAX_ENVELOPE_B64) {
    return "Envelope is too large.";
  }
  return {
    v: ENVELOPE_VERSION,
    kdf: ENVELOPE_KDF,
    iterations: raw.iterations,
    salt: raw.salt as string,
    nonce: raw.nonce as string,
    ciphertext: raw.ciphertext as string,
  };
}
