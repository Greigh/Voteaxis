import { describe, expect, test } from "bun:test";
import { join } from "node:path";
import { createApp } from "../src/app";
import {
  ENVELOPE_KDF,
  ENVELOPE_VERSION,
  normalizeResultId,
  MAX_ITERATIONS,
  parseEnvelope,
  parseResultPayload,
  randomResultId,
} from "../src/results";
import { Store } from "../src/store";

const weekPath = join(import.meta.dir, "..", "data", "issue-of-the-week.json");

function app(overrides: Partial<Parameters<typeof createApp>[0]> = {}) {
  return createApp({
    store: new Store(":memory:"),
    ttlMs: 60 * 60 * 1000,
    weekPath,
    rateLimitPosts: 1000,
    siteBase: "https://voteaxis.test",
    ...overrides,
  });
}

const b64 = (bytes: number) => Buffer.alloc(bytes, 7).toString("base64");

/** Shape only — the server never decrypts, so the bytes need not be real. */
const envelope = {
  v: ENVELOPE_VERSION,
  kdf: ENVELOPE_KDF,
  iterations: 210000,
  salt: b64(16),
  nonce: b64(12),
  ciphertext: b64(64),
};

async function call(
  fetch: (req: Request) => Response | Promise<Response>,
  path: string,
  init?: RequestInit,
) {
  return fetch(new Request(`http://voteaxis.test${path}`, init));
}

function post(fetch: (req: Request) => Response | Promise<Response>, body: unknown) {
  return call(fetch, "/v1/results", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(body),
  });
}

const payload = {
  axisScore: -42.5,
  issueScores: { taxes: -60, climate: -80, immigration: -10 },
  issueWeights: { taxes: 2.5, climate: 1 },
  pillarScores: { economy: -55, world: -80 },
  dealbreakerIssueIds: ["climate"],
  homeState: "MI",
  transferCode: "VX1-ABCDE-FGHJK-MNPQR",
  takenAt: 1_760_000_000_000,
};

describe("result ids", () => {
  test("minted ids round-trip through normalize", () => {
    for (let i = 0; i < 20; i++) {
      const id = randomResultId();
      expect(id).toHaveLength(16);
      expect(normalizeResultId(id)).toBe(id);
    }
  });

  test("normalize lowercases and rejects the wrong shape", () => {
    const id = randomResultId();
    expect(normalizeResultId(` ${id.toUpperCase()} `)).toBe(id);
    expect(normalizeResultId("short")).toBeNull();
    // 0, 1, i, l, o, and u are excluded from the alphabet.
    expect(normalizeResultId("oooooooooooooooo")).toBeNull();
    expect(normalizeResultId("../../etc/passwd")).toBeNull();
  });
});

describe("parseResultPayload", () => {
  test("accepts a full payload", () => {
    const parsed = parseResultPayload(payload);
    expect(typeof parsed).not.toBe("string");
    if (typeof parsed === "string") return;
    expect(parsed.axisScore).toBe(-42.5);
    expect(parsed.homeState).toBe("MI");
    expect(parsed.transferCode).toBe("VX1-ABCDE-FGHJK-MNPQR");
    expect(parsed.dealbreakerIssueIds).toEqual(["climate"]);
  });

  test("issueScores is required and range-checked", () => {
    expect(parseResultPayload({ ...payload, issueScores: {} })).toBe(
      "issueScores is required.",
    );
    expect(
      parseResultPayload({ ...payload, issueScores: { taxes: 101 } }),
    ).toBe("Invalid issueScores value.");
    // null coerces to 0 in JS; it must not pass as a centre score.
    expect(
      parseResultPayload({ ...payload, issueScores: { taxes: null } }),
    ).toBe("Invalid issueScores value.");
  });

  test("importance weights use their own ceiling, not the score range", () => {
    const ok = parseResultPayload({ ...payload, issueWeights: { taxes: 2.5 } });
    expect(typeof ok).not.toBe("string");
    expect(
      parseResultPayload({ ...payload, issueWeights: { taxes: 50 } }),
    ).toBe("Invalid issueWeights value.");
  });

  test("rejects a malformed home state or transfer code", () => {
    expect(parseResultPayload({ ...payload, homeState: "Michigan" })).toBe(
      "homeState must be a 2-letter code.",
    );
    expect(parseResultPayload({ ...payload, transferCode: "nope" })).toBe(
      "transferCode is not valid.",
    );
    // Blank means "not set", not invalid.
    const blank = parseResultPayload({ ...payload, homeState: "", transferCode: "" });
    expect(typeof blank).not.toBe("string");
    if (typeof blank === "string") return;
    expect(blank.homeState).toBeNull();
    expect(blank.transferCode).toBeNull();
  });

  test("caps dealbreakers at three", () => {
    expect(
      parseResultPayload({
        ...payload,
        dealbreakerIssueIds: ["a", "b", "c", "d"],
      }),
    ).toBe("At most 3 dealbreakers.");
  });
});

describe("parseEnvelope", () => {
  test("accepts a well-formed envelope", () => {
    const parsed = parseEnvelope(envelope);
    expect(typeof parsed).not.toBe("string");
    if (typeof parsed === "string") return;
    expect(parsed.iterations).toBe(210000);
    expect(parsed.salt).toBe(envelope.salt);
  });

  test("pins the version and the KDF", () => {
    expect(parseEnvelope({ ...envelope, v: 2 })).toBe(
      "Unsupported envelope version.",
    );
    expect(parseEnvelope({ ...envelope, kdf: "md5" })).toBe(
      "Unsupported envelope kdf.",
    );
  });

  test("rejects an iteration count outside the sane band", () => {
    expect(parseEnvelope({ ...envelope, iterations: 10 })).toBe(
      "Invalid envelope iterations.",
    );
    // The reader runs this count on their own device with no say in it, so the
    // ceiling protects them, not the author.
    expect(parseEnvelope({ ...envelope, iterations: 5_000_000 })).toBe(
      "Invalid envelope iterations.",
    );
    expect(parseEnvelope({ ...envelope, iterations: MAX_ITERATIONS + 1 })).toBe(
      "Invalid envelope iterations.",
    );
    expect(
      parseEnvelope({ ...envelope, iterations: MAX_ITERATIONS }),
    ).toMatchObject({ iterations: MAX_ITERATIONS });
    expect(parseEnvelope({ ...envelope, iterations: 1.5 })).toBe(
      "Invalid envelope iterations.",
    );
  });

  test("checks the decoded lengths, not just the strings", () => {
    expect(parseEnvelope({ ...envelope, salt: b64(8) })).toBe(
      "Invalid envelope salt.",
    );
    expect(parseEnvelope({ ...envelope, nonce: b64(16) })).toBe(
      "Invalid envelope nonce.",
    );
    // Nothing but the GCM tag is not a message.
    expect(parseEnvelope({ ...envelope, ciphertext: b64(16) })).toBe(
      "Invalid envelope ciphertext.",
    );
  });

  test("refuses to be used as free storage", () => {
    expect(
      parseEnvelope({ ...envelope, ciphertext: "A".repeat(9000) }),
    ).toBe("Envelope is too large.");
  });

  test("rejects junk in place of an envelope", () => {
    expect(parseEnvelope(null)).toBe("Invalid envelope.");
    expect(parseEnvelope([])).toBe("Invalid envelope.");
    expect(parseEnvelope({ ...envelope, salt: "not base64!!" })).toBe(
      "Invalid envelope salt.",
    );
  });
});

describe("password-protected results are opaque to the server", () => {
  test("an envelope goes in and comes back byte-identical", async () => {
    const { fetch } = app();
    const created = await (await post(fetch, { envelope })).json();
    expect(created.encrypted).toBe(true);

    const read = await call(fetch, `/v1/results/${created.id}`);
    expect(read.status).toBe(200);
    const body = await read.json();
    expect(body.encrypted).toBe(true);
    expect(body.envelope).toEqual(envelope);
    // Nothing readable leaks alongside it.
    expect(body.axisScore).toBeUndefined();
    expect(body.issueScores).toBeUndefined();
    expect(body.transferCode).toBeUndefined();
  });

  test("there is no unlock endpoint to brute-force", async () => {
    const { fetch } = app();
    const created = await (await post(fetch, { envelope })).json();
    const res = await call(fetch, `/v1/results/${created.id}/unlock`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ password: "hunter2" }),
    });
    expect(res.status).toBe(404);
  });

  test("the raw row holds ciphertext, not scores", () => {
    const store = new Store(":memory:");
    const published = store.publishResult(envelope, true, undefined, 60_000);
    const found = store.lookupResult(published.id);
    expect(found?.payload).toBeNull();
    expect(found?.envelope).toEqual(envelope);
  });

  test("a payload and an envelope together are refused", async () => {
    const { fetch } = app();
    const res = await post(fetch, { payload, envelope });
    expect(res.status).toBe(400);
    expect((await res.json()).error).toBe(
      "Send a payload or an envelope, not both.",
    );
  });

  test("a malformed envelope is rejected", async () => {
    const { fetch } = app();
    const res = await post(fetch, { envelope: { ...envelope, v: 99 } });
    expect(res.status).toBe(400);
  });

  test("the token swaps an open link for an encrypted one", async () => {
    const { fetch } = app();
    const first = await (await post(fetch, { payload })).json();
    expect(first.encrypted).toBe(false);

    await post(fetch, { envelope, token: first.token });
    const read = await (await call(fetch, `/v1/results/${first.id}`)).json();
    expect(read.encrypted).toBe(true);
    expect(read.axisScore).toBeUndefined();
  });

  test("and back again", async () => {
    const { fetch } = app();
    const first = await (await post(fetch, { envelope })).json();
    await post(fetch, { payload, token: first.token });
    const read = await (await call(fetch, `/v1/results/${first.id}`)).json();
    expect(read.encrypted).toBe(false);
    expect(read.axisScore).toBe(-42.5);
  });
});

describe("revoking and expiry", () => {
  test("the token takes a link down; a wrong token does not", async () => {
    const { fetch } = app();
    const created = await (await post(fetch, { payload })).json();

    const noToken = await call(fetch, `/v1/results/${created.id}`, {
      method: "DELETE",
    });
    expect(noToken.status).toBe(401);

    const wrongToken = await call(fetch, `/v1/results/${created.id}`, {
      method: "DELETE",
      headers: { "x-voteaxis-token": "a".repeat(48) },
    });
    expect(wrongToken.status).toBe(404);
    expect((await call(fetch, `/v1/results/${created.id}`)).status).toBe(200);

    const removed = await call(fetch, `/v1/results/${created.id}`, {
      method: "DELETE",
      headers: { "x-voteaxis-token": created.token },
    });
    expect(removed.status).toBe(200);
    expect((await call(fetch, `/v1/results/${created.id}`)).status).toBe(404);
  });

  test("an expired link reads as gone", async () => {
    const { fetch } = app({ resultTtlMs: -1 });
    const created = await (await post(fetch, { payload })).json();
    const res = await call(fetch, `/v1/results/${created.id}`);
    expect(res.status).toBe(404);
  });

  test("a malformed id is rejected before it reaches the store", async () => {
    const { fetch } = app();
    expect((await call(fetch, "/v1/results/nope")).status).toBe(400);
    expect(
      (await call(fetch, "/v1/results/nope", { method: "DELETE" })).status,
    ).toBe(400);
  });

  test("publishing is rate limited", async () => {
    // Guessing a password happens offline now, so publishing is the abuse
    // surface that is left.
    const { fetch } = app({ rateLimitPosts: 3 });
    for (let i = 0; i < 3; i++) {
      expect((await post(fetch, { payload })).status).toBe(200);
    }
    const blocked = await post(fetch, { payload });
    expect(blocked.status).toBe(429);
  });
});

describe("store-level result behaviour", () => {
  test("purgeExpired drops results as well as profiles", () => {
    const store = new Store(":memory:");
    const parsed = parseResultPayload(payload);
    if (typeof parsed === "string") throw new Error(parsed);
    const published = store.publishResult(parsed, false, undefined, -1);
    expect(store.lookupResult(published.id)).toBeNull();
  });

  test("an open link keeps a readable payload and no envelope", () => {
    const store = new Store(":memory:");
    const parsed = parseResultPayload(payload);
    if (typeof parsed === "string") throw new Error(parsed);
    const published = store.publishResult(parsed, false, undefined, 60_000);
    const found = store.lookupResult(published.id);
    expect(found?.envelope).toBeNull();
    expect(found?.payload?.axisScore).toBe(-42.5);
  });
});
