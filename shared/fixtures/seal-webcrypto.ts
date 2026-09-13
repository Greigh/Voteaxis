/**
 * Seals the interop fixture with WebCrypto, the way a browser would if it
 * were the author rather than the reader. The app then opens it in a test, so
 * the two implementations cannot drift apart silently.
 */
import { readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";

const path = join(import.meta.dir, "envelope-interop.json");
const fixture = JSON.parse(readFileSync(path, "utf8")) as {
  password: string;
  iterations: number;
  payload: unknown;
  sealedByWebCrypto: unknown;
};

const salt = crypto.getRandomValues(new Uint8Array(16));
const nonce = crypto.getRandomValues(new Uint8Array(12));
const material = await crypto.subtle.importKey(
  "raw",
  new TextEncoder().encode(fixture.password),
  "PBKDF2",
  false,
  ["deriveKey"],
);
const key = await crypto.subtle.deriveKey(
  { name: "PBKDF2", salt, iterations: fixture.iterations, hash: "SHA-256" },
  material,
  { name: "AES-GCM", length: 256 },
  false,
  ["encrypt"],
);
const sealed = await crypto.subtle.encrypt(
  { name: "AES-GCM", iv: nonce },
  key,
  new TextEncoder().encode(JSON.stringify(fixture.payload)),
);

fixture.sealedByWebCrypto = {
  v: 1,
  kdf: "pbkdf2-sha256",
  iterations: fixture.iterations,
  salt: Buffer.from(salt).toString("base64"),
  nonce: Buffer.from(nonce).toString("base64"),
  ciphertext: Buffer.from(new Uint8Array(sealed)).toString("base64"),
};

writeFileSync(path, `${JSON.stringify(fixture, null, 2)}\n`);
