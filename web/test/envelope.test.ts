import { describe, expect, test } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import {
  base64ToBytes,
  ENVELOPE_KDF,
  ENVELOPE_VERSION,
  type EncryptedEnvelope,
  isEnvelope,
  MAX_ITERATIONS,
  openEnvelope,
} from "../lib/envelope";

const PASSWORD = "correct horse battery staple";

/**
 * Seals a payload exactly the way the app does — PBKDF2-SHA256 to a 256-bit
 * AES-GCM key, tag appended to the ciphertext. If this and the reader ever
 * disagree, every shared link goes dark, so the round trip is the test.
 */
async function seal(
  payload: unknown,
  password = PASSWORD,
  iterations = 50_000,
): Promise<EncryptedEnvelope> {
  const salt = crypto.getRandomValues(new Uint8Array(16));
  const nonce = crypto.getRandomValues(new Uint8Array(12));
  const material = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(password),
    "PBKDF2",
    false,
    ["deriveKey"],
  );
  const key = await crypto.subtle.deriveKey(
    { name: "PBKDF2", salt, iterations, hash: "SHA-256" },
    material,
    { name: "AES-GCM", length: 256 },
    false,
    ["encrypt"],
  );
  const sealed = await crypto.subtle.encrypt(
    { name: "AES-GCM", iv: nonce },
    key,
    new TextEncoder().encode(JSON.stringify(payload)),
  );
  return {
    v: ENVELOPE_VERSION,
    kdf: ENVELOPE_KDF,
    iterations,
    salt: Buffer.from(salt).toString("base64"),
    nonce: Buffer.from(nonce).toString("base64"),
    ciphertext: Buffer.from(new Uint8Array(sealed)).toString("base64"),
  };
}

const payload = {
  axisScore: -42.5,
  issueScores: { taxes: -60, climate: -80 },
  pillarScores: { economy: -55 },
  transferCode: "VX1-ABCDE-FGHJK",
};

describe("base64ToBytes", () => {
  test("decodes to a real ArrayBuffer WebCrypto will accept", () => {
    const bytes = base64ToBytes(Buffer.from([1, 2, 255]).toString("base64"));
    expect(Array.from(bytes)).toEqual([1, 2, 255]);
    expect(bytes.buffer).toBeInstanceOf(ArrayBuffer);
  });
});

describe("isEnvelope", () => {
  test("accepts the wire shape and rejects everything else", async () => {
    const envelope = await seal(payload);
    expect(isEnvelope(envelope)).toBe(true);
    expect(isEnvelope(null)).toBe(false);
    expect(isEnvelope({ ...envelope, v: 2 })).toBe(false);
    expect(isEnvelope({ ...envelope, kdf: "md5" })).toBe(false);
    expect(isEnvelope({ ...envelope, iterations: "lots" })).toBe(false);
    // The reader pays this cost on their own device, so an unbounded count is
    // a way to hang a stranger's browser. Anything above the cap is not an
    // envelope this page will open.
    expect(isEnvelope({ ...envelope, iterations: MAX_ITERATIONS })).toBe(true);
    expect(isEnvelope({ ...envelope, iterations: MAX_ITERATIONS + 1 })).toBe(
      false,
    );
    expect(isEnvelope({ ...envelope, iterations: 5_000_000 })).toBe(false);
    expect(isEnvelope({ ...envelope, iterations: 0 })).toBe(false);
    expect(isEnvelope({ ...envelope, iterations: 1.5 })).toBe(false);
  });
});

describe("openEnvelope", () => {
  test("the right password returns the payload", async () => {
    const envelope = await seal(payload);
    const opened = await openEnvelope(envelope, PASSWORD);
    expect(opened).toEqual(payload);
  });

  test("the wrong password returns null, not a throw", async () => {
    const envelope = await seal(payload);
    expect(await openEnvelope(envelope, "wrong password")).toBeNull();
    expect(await openEnvelope(envelope, "")).toBeNull();
  });

  test("a tampered ciphertext fails the GCM tag", async () => {
    const envelope = await seal(payload);
    const bytes = base64ToBytes(envelope.ciphertext);
    bytes[0] = bytes[0] ^ 0xff;
    const tampered = {
      ...envelope,
      ciphertext: Buffer.from(bytes).toString("base64"),
    };
    expect(await openEnvelope(tampered, PASSWORD)).toBeNull();
  });

  test("a swapped salt or nonce fails too", async () => {
    const envelope = await seal(payload);
    const other = await seal(payload);
    expect(
      await openEnvelope({ ...envelope, salt: other.salt }, PASSWORD),
    ).toBeNull();
    expect(
      await openEnvelope({ ...envelope, nonce: other.nonce }, PASSWORD),
    ).toBeNull();
  });

  test("an iteration count the sealer did not use fails", async () => {
    const envelope = await seal(payload);
    expect(
      await openEnvelope({ ...envelope, iterations: 60_000 }, PASSWORD),
    ).toBeNull();
  });

  test("a malformed envelope is refused before any crypto runs", async () => {
    const envelope = await seal(payload);
    expect(
      await openEnvelope({ ...envelope, v: 99 } as EncryptedEnvelope, PASSWORD),
    ).toBeNull();
    expect(
      await openEnvelope(
        { ...envelope, ciphertext: "not base64 !!" },
        PASSWORD,
      ),
    ).toBeNull();
  });

  test("a payload that is not a JSON object is refused", async () => {
    const envelope = await seal(["an", "array"]);
    expect(await openEnvelope(envelope, PASSWORD)).toBeNull();
  });

  test("round-trips the same unicode the app would send", async () => {
    const body = { label: "Set by hand — 2026", note: "Liberal ← 0 → 100" };
    const envelope = await seal(body);
    expect(await openEnvelope(envelope, PASSWORD)).toEqual(body);
  });
});

describe("interop with the app", () => {
  // A share link is sealed on a phone and opened here. If these two
  // implementations ever disagree, every link already out there goes dark —
  // so each side opens a fixture the other one sealed.
  const fixture = JSON.parse(
    readFileSync(
      join(
        import.meta.dir,
        "..",
        "..",
        "shared",
        "fixtures",
        "envelope-interop.json",
      ),
      "utf8",
    ),
  ) as {
    password: string;
    payload: Record<string, unknown>;
    sealedByDart: EncryptedEnvelope;
    sealedByWebCrypto: EncryptedEnvelope;
  };

  test("opens an envelope the Flutter app sealed", async () => {
    expect(isEnvelope(fixture.sealedByDart)).toBe(true);
    const opened = await openEnvelope(fixture.sealedByDart, fixture.password);
    expect(opened).toEqual(fixture.payload);
  });

  test("the wrong password fails against the app envelope too", async () => {
    expect(
      await openEnvelope(fixture.sealedByDart, "not the password"),
    ).toBeNull();
  });

  test("both sides declare the same version and KDF", () => {
    for (const sealed of [fixture.sealedByDart, fixture.sealedByWebCrypto]) {
      expect(sealed.v).toBe(ENVELOPE_VERSION);
      expect(sealed.kdf).toBe(ENVELOPE_KDF);
      expect(base64ToBytes(sealed.salt)).toHaveLength(16);
      expect(base64ToBytes(sealed.nonce)).toHaveLength(12);
    }
  });
});

describe("a hostile iteration count", () => {
  test("is refused before any key is derived", async () => {
    const envelope = await seal({ hello: "world" });
    let derived = false;
    const spy = {
      importKey: () => {
        derived = true;
        return Promise.reject(new Error("should not be reached"));
      },
    } as unknown as SubtleCrypto;
    const opened = await openEnvelope(
      { ...envelope, iterations: 5_000_000 },
      PASSWORD,
      spy,
    );
    expect(opened).toBeNull();
    expect(derived).toBe(false);
  });
});
