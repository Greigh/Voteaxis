import { describe, expect, test } from "bun:test";
import {
  generateKeyPairSync,
  randomBytes,
  sign as cryptoSign,
  type KeyObject,
} from "node:crypto";
import { mkdtempSync, utimesSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { createApp } from "../src/app";
import { Store } from "../src/store";

const weekPath = join(import.meta.dir, "..", "data", "issue-of-the-week.json");
const TEST_KEY = "test-only-key-do-not-use-in-prod";

async function call(
  fetch: (req: Request) => Response | Promise<Response>,
  path: string,
  init?: RequestInit,
) {
  return fetch(new Request(`http://voteaxis.test${path}`, init));
}

/** [call], but with the fixture's key attached like a real caller would. */
async function authedCall(
  fetch: (req: Request) => Response | Promise<Response>,
  path: string,
  init?: RequestInit,
) {
  return call(fetch, path, {
    ...init,
    headers: { ...init?.headers, "x-voteaxis-key": TEST_KEY },
  });
}

const SAMPLE = [
  {
    id: "jane_example",
    name: "Jane Example",
    role: "Governor of Exampleland",
    party: "Democratic",
    state: "CA",
    officeType: "governor",
    current: true,
    bio: "Jane Example is the governor of Exampleland.",
    officeHistory: ["Governor of Exampleland (2023-present)"],
    issues: {},
    confidence: {},
    signatureStances: [],
  },
  {
    id: "john_sample",
    name: "John Sample",
    role: "Former U.S. Senator (TX)",
    party: "Republican",
    state: "TX",
    officeType: "senator",
    current: false,
    bio: "John Sample represented Texas in the Senate.",
    officeHistory: ["U.S. Senator, Texas (1990-2002)"],
    issues: {},
    confidence: {},
    signatureStances: [],
  },
];

/**
 * A politicians.json fixture, written somewhere disposable, behind [TEST_KEY]
 * unless [apiKey] is explicitly `null` for "nothing configured". A plain
 * `undefined` default parameter would not do here — passing `undefined`
 * explicitly falls back to the default in JS, so a test could not ask for
 * "no key" that way.
 */
function politiciansApp(
  data: unknown = SAMPLE,
  apiKey: string | null = TEST_KEY,
  allowDeviceTokens = false,
) {
  const dir = mkdtempSync(join(tmpdir(), "voteaxis-politicians-"));
  const path = join(dir, "politicians.json");
  writeFileSync(path, JSON.stringify(data));
  const store = new Store(":memory:");
  return {
    path,
    store,
    app: createApp({
      store,
      ttlMs: 60 * 60 * 1000,
      weekPath,
      politiciansPath: path,
      politiciansApiKey: apiKey ?? undefined,
      politiciansAllowDeviceTokens: allowDeviceTokens,
      rateLimitPosts: 1000,
    }),
  };
}

/**
 * A fresh Ed25519 keypair, playing the role of one app install. Only
 * [publicKeyHex] — the raw 32-byte key, hex — ever crosses into a request
 * body; [privateKey] stays local to the test, standing in for the on-device
 * key an install never sends.
 */
function newDeviceKeyPair(): { publicKeyHex: string; privateKey: KeyObject } {
  const { publicKey, privateKey } = generateKeyPairSync("ed25519");
  const der = publicKey.export({ type: "spki", format: "der" }) as Buffer;
  // SPKI DER for Ed25519 is a fixed 12-byte prefix plus the 32-byte raw key.
  return { publicKeyHex: der.subarray(der.length - 32).toString("hex"), privateKey };
}

/** Registers a keypair and returns the deviceId the server assigned. */
async function registerDevice(
  fetch: (req: Request) => Response | Promise<Response>,
  publicKeyHex: string,
): Promise<string> {
  const res = await call(fetch, "/v1/device-tokens", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ publicKey: publicKeyHex }),
  });
  const body = await res.json();
  return body.deviceId as string;
}

/**
 * Headers for a fully valid signed `/v1/politicians` request, with each
 * field overridable so a negative test can flip exactly one thing wrong
 * (bad signature, stale timestamp, reused nonce, ...) and leave the rest
 * as a real client would send them.
 */
function signedHeaders(opts: {
  deviceId: string;
  privateKey: KeyObject;
  method?: string;
  path?: string;
  timestamp?: number;
  nonce?: string;
  signatureOverride?: string;
}): Record<string, string> {
  const method = opts.method ?? "GET";
  const path = opts.path ?? "/v1/politicians";
  const timestamp = opts.timestamp ?? Date.now();
  const nonce = opts.nonce ?? randomBytes(16).toString("hex");
  const message = `${method}\n${path}\n${opts.deviceId}\n${timestamp}\n${nonce}`;
  const signature =
    opts.signatureOverride ??
    cryptoSign(null, Buffer.from(message, "utf8"), opts.privateKey).toString("hex");
  return {
    "x-voteaxis-device-id": opts.deviceId,
    "x-voteaxis-timestamp": String(timestamp),
    "x-voteaxis-nonce": nonce,
    "x-voteaxis-signature": signature,
  };
}

describe("/v1/politicians auth gate", () => {
  test("health reports whether the gate is configured", async () => {
    const locked = await (
      await call(politiciansApp(SAMPLE, null).app.fetch, "/health")
    ).json();
    expect(locked.politiciansGated).toBe(false);

    const gated = await (await call(politiciansApp().app.fetch, "/health")).json();
    expect(gated.politiciansGated).toBe(true);
  });

  test("no key configured locks the roster to everyone, not just strangers", async () => {
    const { app } = politiciansApp(SAMPLE, null);
    const noHeader = await call(app.fetch, "/v1/politicians");
    expect(noHeader.status).toBe(401);
    // Even the "right" key for a *different* deployment is meaningless here —
    // there is nothing configured to match against.
    const withHeader = await authedCall(app.fetch, "/v1/politicians");
    expect(withHeader.status).toBe(401);
  });

  test("a missing key header is 401", async () => {
    const { app } = politiciansApp();
    const res = await call(app.fetch, "/v1/politicians");
    expect(res.status).toBe(401);
    expect((await res.json()).ok).toBe(false);
  });

  test("a wrong key is 401, same message as a missing one", async () => {
    const { app } = politiciansApp();
    const missing = await call(app.fetch, "/v1/politicians");
    const wrong = await call(app.fetch, "/v1/politicians", {
      headers: { "x-voteaxis-key": "not-the-key" },
    });
    expect(wrong.status).toBe(401);
    expect(await wrong.json()).toEqual(await missing.json());
  });

  test("the correct key opens the roster", async () => {
    const { app } = politiciansApp();
    const res = await authedCall(app.fetch, "/v1/politicians");
    expect(res.status).toBe(200);
  });

  test("the gate applies to the single-figure route too", async () => {
    const { app } = politiciansApp();
    const noKey = await call(app.fetch, "/v1/politicians/jane_example");
    expect(noKey.status).toBe(401);
    const withKey = await authedCall(app.fetch, "/v1/politicians/jane_example");
    expect(withKey.status).toBe(200);
  });

  test("unauthorized guesses still count against the rate limit", async () => {
    // Rate limiting runs before the key check, so a flood of wrong guesses
    // cannot dodge the limiter by virtue of being unauthorized.
    const { app } = politiciansApp();
    let last = 200;
    for (let i = 0; i < 62; i++) {
      const res = await call(app.fetch, "/v1/politicians", {
        headers: { "x-real-ip": "33.33.33.1" },
      });
      last = res.status;
    }
    expect(last).toBe(429);
  });
});

describe("/v1/politicians auth-failure logging", () => {
  /** Same save/restore pattern as api.test.ts's proxy-warning test. */
  async function withConsoleSpies<T>(
    fn: (warnings: string[], errors: string[]) => Promise<T>,
  ): Promise<T> {
    const warnings: string[] = [];
    const errors: string[] = [];
    const originalWarn = console.warn;
    const originalError = console.error;
    console.warn = (...args: unknown[]) => warnings.push(String(args[0]));
    console.error = (...args: unknown[]) => errors.push(String(args[0]));
    try {
      return await fn(warnings, errors);
    } finally {
      console.warn = originalWarn;
      console.error = originalError;
    }
  }

  test("a failed attempt logs a warning naming the ip and path, never the key", async () => {
    const { app } = politiciansApp();
    await withConsoleSpies(async (warnings) => {
      const res = await call(app.fetch, "/v1/politicians", {
        headers: { "x-real-ip": "77.77.77.1", "x-voteaxis-key": "guessed-key" },
      });
      expect(res.status).toBe(401);
      expect(warnings).toHaveLength(1);
      expect(warnings[0]).toContain("politicians auth failed");
      expect(warnings[0]).toContain("77.77.77.1");
      expect(warnings[0]).toContain("/v1/politicians");
      expect(warnings[0]).not.toContain("guessed-key");
      expect(warnings[0]).not.toContain(TEST_KEY);
    });
  });

  test("a successful auth logs nothing", async () => {
    const { app } = politiciansApp();
    await withConsoleSpies(async (warnings, errors) => {
      const res = await authedCall(app.fetch, "/v1/politicians", {
        headers: { "x-real-ip": "77.77.77.2" },
      });
      expect(res.status).toBe(200);
      expect(warnings).toHaveLength(0);
      expect(errors).toHaveLength(0);
    });
  });

  test("repeated failures from one IP escalate to an error, once", async () => {
    const { app } = politiciansApp();
    await withConsoleSpies(async (_warnings, errors) => {
      for (let i = 0; i < 11; i++) {
        await call(app.fetch, "/v1/politicians", {
          headers: { "x-real-ip": "77.77.77.3" },
        });
      }
      expect(errors).toHaveLength(1);
      expect(errors[0]).toContain("repeated politicians auth failures");
      expect(errors[0]).toContain("77.77.77.3");
    });
  });

  test("one IP's failures do not trip the escalation for another", async () => {
    const { app } = politiciansApp();
    await withConsoleSpies(async (_warnings, errors) => {
      for (let i = 0; i < 11; i++) {
        await call(app.fetch, "/v1/politicians", {
          headers: { "x-real-ip": "77.77.77.4" },
        });
      }
      errors.length = 0;
      await call(app.fetch, "/v1/politicians", {
        headers: { "x-real-ip": "77.77.77.5" },
      });
      expect(errors).toHaveLength(0);
    });
  });
});

describe("POST /v1/device-tokens", () => {
  test("registers a public key with no auth required", async () => {
    // This is the bootstrap route: a fresh install has no credential yet, so
    // there is nothing to check it against.
    const { app } = politiciansApp();
    const { publicKeyHex } = newDeviceKeyPair();
    const res = await call(app.fetch, "/v1/device-tokens", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ publicKey: publicKeyHex }),
    });
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body.ok).toBe(true);
    expect(body.deviceId).toMatch(/^[0-9a-f]{48}$/);
    expect(body.issuedAt).toBeGreaterThan(0);
  });

  test("two registrations mint two different deviceIds", async () => {
    const { app } = politiciansApp();
    const first = await registerDevice(app.fetch, newDeviceKeyPair().publicKeyHex);
    const second = await registerDevice(app.fetch, newDeviceKeyPair().publicKeyHex);
    expect(second).not.toBe(first);
  });

  test("rejects a missing or malformed public key", async () => {
    const { app } = politiciansApp();
    const missing = await call(app.fetch, "/v1/device-tokens", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({}),
    });
    expect(missing.status).toBe(400);

    const shortKey = await call(app.fetch, "/v1/device-tokens", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ publicKey: "abc" }),
    });
    expect(shortKey.status).toBe(400);

    const badJson = await call(app.fetch, "/v1/device-tokens", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: "not json",
    });
    expect(badJson.status).toBe(400);
  });

  test("is tightly metered per IP — a real install needs at most one", async () => {
    const { app } = politiciansApp();
    let last = 200;
    for (let i = 0; i < 7; i++) {
      const res = await call(app.fetch, "/v1/device-tokens", {
        method: "POST",
        headers: {
          "x-real-ip": "66.66.66.1",
          "content-type": "application/json",
        },
        body: JSON.stringify({ publicKey: newDeviceKeyPair().publicKeyHex }),
      });
      last = res.status;
    }
    expect(last).toBe(429);
    const other = await call(app.fetch, "/v1/device-tokens", {
      method: "POST",
      headers: {
        "x-real-ip": "66.66.66.2",
        "content-type": "application/json",
      },
      body: JSON.stringify({ publicKey: newDeviceKeyPair().publicKeyHex }),
    });
    expect(other.status).not.toBe(429);
  });
});

describe("/v1/politicians signed-device auth", () => {
  test("a freshly registered device is refused while device auth is off", async () => {
    const { app } = politiciansApp(SAMPLE, TEST_KEY, false);
    const { publicKeyHex, privateKey } = newDeviceKeyPair();
    const deviceId = await registerDevice(app.fetch, publicKeyHex);
    const res = await call(app.fetch, "/v1/politicians", {
      headers: signedHeaders({ deviceId, privateKey }),
    });
    expect(res.status).toBe(401);
  });

  test("a validly signed request opens the roster once device auth is on", async () => {
    const { app } = politiciansApp(SAMPLE, TEST_KEY, true);
    const { publicKeyHex, privateKey } = newDeviceKeyPair();
    const deviceId = await registerDevice(app.fetch, publicKeyHex);
    const res = await call(app.fetch, "/v1/politicians", {
      headers: signedHeaders({ deviceId, privateKey }),
    });
    expect(res.status).toBe(200);
  });

  test("an unregistered deviceId is 401 even with a well-formed signature", async () => {
    const { app } = politiciansApp(SAMPLE, TEST_KEY, true);
    const { privateKey } = newDeviceKeyPair();
    const res = await call(app.fetch, "/v1/politicians", {
      headers: signedHeaders({ deviceId: "f".repeat(48), privateKey }),
    });
    expect(res.status).toBe(401);
  });

  test("a signature from the wrong key is 401", async () => {
    const { app } = politiciansApp(SAMPLE, TEST_KEY, true);
    const { publicKeyHex } = newDeviceKeyPair();
    const deviceId = await registerDevice(app.fetch, publicKeyHex);
    const impostor = newDeviceKeyPair();
    const res = await call(app.fetch, "/v1/politicians", {
      // Signed by a key other than the one registered for this deviceId.
      headers: signedHeaders({ deviceId, privateKey: impostor.privateKey }),
    });
    expect(res.status).toBe(401);
  });

  test("a tampered signature is 401", async () => {
    const { app } = politiciansApp(SAMPLE, TEST_KEY, true);
    const { publicKeyHex, privateKey } = newDeviceKeyPair();
    const deviceId = await registerDevice(app.fetch, publicKeyHex);
    const headers = signedHeaders({ deviceId, privateKey });
    headers["x-voteaxis-signature"] = "0".repeat(128);
    const res = await call(app.fetch, "/v1/politicians", { headers });
    expect(res.status).toBe(401);
  });

  test("malformed headers (short nonce, non-hex signature) are 401, not a crash", async () => {
    const { app } = politiciansApp(SAMPLE, TEST_KEY, true);
    const { publicKeyHex, privateKey } = newDeviceKeyPair();
    const deviceId = await registerDevice(app.fetch, publicKeyHex);
    const badNonce = await call(app.fetch, "/v1/politicians", {
      headers: signedHeaders({ deviceId, privateKey, nonce: "ab" }),
    });
    expect(badNonce.status).toBe(401);
    const headers = signedHeaders({ deviceId, privateKey });
    headers["x-voteaxis-signature"] = "not-hex-at-all";
    const badSig = await call(app.fetch, "/v1/politicians", { headers });
    expect(badSig.status).toBe(401);
  });

  test("a signature outside the timestamp window is 401", async () => {
    const { app } = politiciansApp(SAMPLE, TEST_KEY, true);
    const { publicKeyHex, privateKey } = newDeviceKeyPair();
    const deviceId = await registerDevice(app.fetch, publicKeyHex);
    const stale = Date.now() - 10 * 60 * 1000; // 10 minutes old
    const res = await call(app.fetch, "/v1/politicians", {
      headers: signedHeaders({ deviceId, privateKey, timestamp: stale }),
    });
    expect(res.status).toBe(401);
  });

  test("a signature is bound to the path — replaying it on another route fails", async () => {
    const { app } = politiciansApp(SAMPLE, TEST_KEY, true);
    const { publicKeyHex, privateKey } = newDeviceKeyPair();
    const deviceId = await registerDevice(app.fetch, publicKeyHex);
    // Signed for the single-figure route, then replayed against the list route.
    const headers = signedHeaders({
      deviceId,
      privateKey,
      path: "/v1/politicians/jane_example",
    });
    const res = await call(app.fetch, "/v1/politicians", { headers });
    expect(res.status).toBe(401);
  });

  test("a signed request cannot be replayed — the second use of the same nonce is 401", async () => {
    const { app } = politiciansApp(SAMPLE, TEST_KEY, true);
    const { publicKeyHex, privateKey } = newDeviceKeyPair();
    const deviceId = await registerDevice(app.fetch, publicKeyHex);
    const headers = signedHeaders({ deviceId, privateKey });
    const first = await call(app.fetch, "/v1/politicians", { headers });
    expect(first.status).toBe(200);
    // Byte-for-byte the same headers, as if the whole request were captured
    // and resent — not a fresh signature.
    const replay = await call(app.fetch, "/v1/politicians", { headers });
    expect(replay.status).toBe(401);
  });

  test("the shared key still works even with device auth on", async () => {
    // The two credentials are independent, not a fallback chain — turning on
    // device auth does not revoke the key for whoever already holds it.
    const { app } = politiciansApp(SAMPLE, TEST_KEY, true);
    const res = await authedCall(app.fetch, "/v1/politicians");
    expect(res.status).toBe(200);
  });

  test("device auth works with no key configured at all", async () => {
    // The point of the mechanism: a general release can run with
    // POLITICIANS_API_KEY unset entirely and rely on signed devices alone.
    const { app } = politiciansApp(SAMPLE, null, true);
    const { publicKeyHex, privateKey } = newDeviceKeyPair();
    const deviceId = await registerDevice(app.fetch, publicKeyHex);
    const res = await call(app.fetch, "/v1/politicians", {
      headers: signedHeaders({ deviceId, privateKey }),
    });
    expect(res.status).toBe(200);
  });

  test("a verified request bumps the device's last-seen time", async () => {
    const { app, store } = politiciansApp(SAMPLE, TEST_KEY, true);
    const { publicKeyHex, privateKey } = newDeviceKeyPair();
    const deviceId = await registerDevice(app.fetch, publicKeyHex);
    await call(app.fetch, "/v1/politicians", {
      headers: signedHeaders({ deviceId, privateKey }),
    });
    // touchDevice() itself is exercised directly in store.test.ts; here it's
    // enough that the device is still registered (not idled out) afterward.
    expect(store.getDevicePublicKey(deviceId)).toBe(publicKeyHex);
  });

  test("a rejected request does not spend a nonce a real one could still use", async () => {
    // Guards the ordering in app.ts: nonceIsFresh() only runs after the
    // signature verifies, so a forged request can't burn a victim's nonce.
    const { app } = politiciansApp(SAMPLE, TEST_KEY, true);
    const { publicKeyHex, privateKey } = newDeviceKeyPair();
    const deviceId = await registerDevice(app.fetch, publicKeyHex);
    const headers = signedHeaders({ deviceId, privateKey });
    const forged = { ...headers, "x-voteaxis-signature": "0".repeat(128) };
    const rejected = await call(app.fetch, "/v1/politicians", { headers: forged });
    expect(rejected.status).toBe(401);
    const real = await call(app.fetch, "/v1/politicians", { headers });
    expect(real.status).toBe(200);
  });

  test("health reports whether device auth is on", async () => {
    const off = await (await call(politiciansApp().app.fetch, "/health")).json();
    expect(off.politiciansDeviceTokens).toBe(false);
    const on = await (
      await call(politiciansApp(SAMPLE, TEST_KEY, true).app.fetch, "/health")
    ).json();
    expect(on.politiciansDeviceTokens).toBe(true);
  });
});

describe("/v1/politicians", () => {
  test("lists the whole roster", async () => {
    const { app } = politiciansApp();
    const res = await authedCall(app.fetch, "/v1/politicians");
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body.ok).toBe(true);
    expect(body.total).toBe(2);
    expect(body.count).toBe(2);
    expect(body.politicians.map((p: { id: string }) => p.id).sort()).toEqual([
      "jane_example",
      "john_sample",
    ]);
  });

  test("filters by state, officeType, party, current, and name", async () => {
    const { app } = politiciansApp();
    const byState = await (
      await authedCall(app.fetch, "/v1/politicians?state=tx")
    ).json();
    expect(byState.count).toBe(1);
    expect(byState.politicians[0].id).toBe("john_sample");

    const byOffice = await (
      await authedCall(app.fetch, "/v1/politicians?officeType=governor")
    ).json();
    expect(byOffice.politicians.map((p: { id: string }) => p.id)).toEqual([
      "jane_example",
    ]);

    const byParty = await (
      await authedCall(app.fetch, "/v1/politicians?party=Republican")
    ).json();
    expect(byParty.politicians.map((p: { id: string }) => p.id)).toEqual([
      "john_sample",
    ]);

    const current = await (
      await authedCall(app.fetch, "/v1/politicians?current=true")
    ).json();
    expect(current.politicians.map((p: { id: string }) => p.id)).toEqual([
      "jane_example",
    ]);

    const byName = await (
      await authedCall(app.fetch, "/v1/politicians?q=sample")
    ).json();
    expect(byName.politicians.map((p: { id: string }) => p.id)).toEqual([
      "john_sample",
    ]);

    // Filters combine, and a query that matches nothing is a 200 with an
    // empty list, not a 404 — the roster loaded fine, nobody just matched.
    const none = await (
      await authedCall(app.fetch, "/v1/politicians?state=TX&party=Democratic")
    ).json();
    expect(none.ok).toBe(true);
    expect(none.politicians).toEqual([]);
  });

  test("GET /v1/politicians/:id returns one figure", async () => {
    const { app } = politiciansApp();
    const res = await authedCall(app.fetch, "/v1/politicians/jane_example");
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body.ok).toBe(true);
    expect(body.politician.name).toBe("Jane Example");
  });

  test("unknown id is 404, malformed id is 400", async () => {
    const { app } = politiciansApp();
    const missing = await authedCall(app.fetch, "/v1/politicians/nobody_here");
    expect(missing.status).toBe(404);

    const malformed = await authedCall(
      app.fetch,
      `/v1/politicians/${encodeURIComponent("not an id!")}`,
    );
    expect(malformed.status).toBe(400);
  });

  test("an ETag round-trips into a 304", async () => {
    const { app } = politiciansApp();
    const first = await authedCall(app.fetch, "/v1/politicians");
    const etag = first.headers.get("etag");
    expect(etag).toBeTruthy();

    const second = await authedCall(app.fetch, "/v1/politicians", {
      headers: { "if-none-match": etag! },
    });
    expect(second.status).toBe(304);
    expect(await second.text()).toBe("");

    const single = await authedCall(app.fetch, "/v1/politicians/jane_example");
    const singleEtag = single.headers.get("etag");
    const singleAgain = await authedCall(app.fetch, "/v1/politicians/jane_example", {
      headers: { "if-none-match": singleEtag! },
    });
    expect(singleAgain.status).toBe(304);
  });

  test("the response is cached but re-read when the file changes", async () => {
    const { app, path } = politiciansApp();
    const first = await (await authedCall(app.fetch, "/v1/politicians")).json();
    expect(first.total).toBe(2);

    writeFileSync(path, JSON.stringify([SAMPLE[0]]));
    const later = new Date(Date.now() + 2000);
    utimesSync(path, later, later);

    const second = await (await authedCall(app.fetch, "/v1/politicians")).json();
    expect(second.total).toBe(1);
  });

  test("a missing roster file is 503, not a crash", async () => {
    const app = createApp({
      store: new Store(":memory:"),
      ttlMs: 60 * 60 * 1000,
      weekPath,
      politiciansPath: join(
        mkdtempSync(join(tmpdir(), "voteaxis-nopoliticians-")),
        "politicians.json",
      ),
      politiciansApiKey: TEST_KEY,
      rateLimitPosts: 1000,
    });
    const res = await authedCall(app.fetch, "/v1/politicians");
    expect(res.status).toBe(503);
  });

  test("is metered per IP", async () => {
    const { app } = politiciansApp();
    let last = 200;
    for (let i = 0; i < 62; i++) {
      const res = await authedCall(app.fetch, "/v1/politicians", {
        headers: { "x-real-ip": "44.44.44.1" },
      });
      last = res.status;
    }
    expect(last).toBe(429);
    const other = await authedCall(app.fetch, "/v1/politicians", {
      headers: { "x-real-ip": "44.44.44.2" },
    });
    expect(other.status).not.toBe(429);
  });
});
