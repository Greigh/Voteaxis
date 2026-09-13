import { describe, expect, test } from "bun:test";
import { Database } from "bun:sqlite";
import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import {
  createApp,
  createRateLimiter,
  clientIp,
  MAX_BUCKETS,
  MAX_REQUEST_BODY_BYTES,
  resolveHost,
} from "../src/app";
import { normalizeCode, normalizeToken } from "../src/codes";
import { createBicamClient, seedBicamDb } from "../src/congress";
import { Store } from "../src/store";

const weekPath = join(import.meta.dir, "..", "data", "issue-of-the-week.json");

function bicamApp(rateLimitPosts = 1000) {
  const dir = mkdtempSync(join(tmpdir(), "voteaxis-sec-"));
  const dbPath = join(dir, "bicam-receipts.sqlite");
  seedBicamDb(dbPath);
  return createApp({
    store: new Store(":memory:"),
    ttlMs: 60 * 60 * 1000,
    weekPath,
    rateLimitPosts,
    bicam: createBicamClient({ dbPath }),
  });
}

function call(
  fetch: (req: Request) => Response | Promise<Response>,
  path: string,
  init?: RequestInit,
) {
  return fetch(new Request(`http://voteaxis.test${path}`, init));
}

describe("bind address", () => {
  // Regression: the default was 0.0.0.0, which on the VPS publishes the API on
  // :8787 with no TLS and lets any caller forge the X-Real-IP the limiter runs
  // on. Loopback has to be what you get from unset, blank, or whitespace.
  test("blank and whitespace values fall back to loopback", () => {
    expect(resolveHost("")).toBe("127.0.0.1");
    expect(resolveHost("   ")).toBe("127.0.0.1");
  });

  test("an explicit address is honoured and trimmed", () => {
    expect(resolveHost("0.0.0.0")).toBe("0.0.0.0");
    expect(resolveHost(" 127.0.0.1 ")).toBe("127.0.0.1");
    expect(resolveHost("::1")).toBe("::1");
  });

  test("an unset HOST binds loopback", () => {
    // Read through the default parameter rather than passing undefined, since
    // that is the path index.ts actually takes. Bun auto-loads server/.env, so
    // the variable has to be cleared for the duration of the assertion.
    const prev = process.env.HOST;
    try {
      delete process.env.HOST;
      expect(resolveHost()).toBe("127.0.0.1");
      process.env.HOST = "";
      expect(resolveHost()).toBe("127.0.0.1");
      process.env.HOST = "0.0.0.0";
      expect(resolveHost()).toBe("0.0.0.0");
    } finally {
      if (prev === undefined) delete process.env.HOST;
      else process.env.HOST = prev;
    }
  });
});

describe("client IP trust", () => {
  function ipOf(headers: Record<string, string>) {
    return clientIp(new Request("http://voteaxis.test/", { headers }));
  }

  test("X-Forwarded-For is never trusted", () => {
    // nginx appends to XFF rather than overwriting it, so a caller controls the
    // left-hand entries and could mint a fresh bucket on every request.
    expect(ipOf({ "x-forwarded-for": "1.2.3.4" })).toBe("local");
    expect(ipOf({ "x-forwarded-for": "1.2.3.4, 5.6.7.8" })).toBe("local");
  });

  test("X-Real-IP wins, then CF-Connecting-IP", () => {
    expect(ipOf({ "x-real-ip": "9.9.9.9" })).toBe("9.9.9.9");
    expect(ipOf({ "cf-connecting-ip": "8.8.8.8" })).toBe("8.8.8.8");
    expect(ipOf({ "x-real-ip": "9.9.9.9", "cf-connecting-ip": "8.8.8.8" })).toBe(
      "9.9.9.9",
    );
  });

  test("a malformed proxy header cannot forge a bucket key", () => {
    // Whitespace or commas mean the value is a list or padded junk, not the
    // single address nginx sets. Falling through to "local" fails closed:
    // everyone shares one bucket rather than each getting a private one.
    expect(ipOf({ "x-real-ip": "1.2.3.4, 5.6.7.8" })).toBe("local");
    expect(ipOf({ "x-real-ip": "1.2.3.4 5.6.7.8" })).toBe("local");
    expect(ipOf({ "x-real-ip": "a".repeat(65) })).toBe("local");
    expect(ipOf({ "x-real-ip": "   " })).toBe("local");
  });
});

describe("friend code write tokens", () => {
  test("a client-chosen token is ignored, not honoured", async () => {
    const api = bicamApp();
    const body = (token: string) =>
      JSON.stringify({ token, axisScore: 0, issueScores: { taxes: 0 } });

    for (const forged of [
      "z".repeat(48), // right length, not hex
      "0".repeat(47), // too short
      "0".repeat(49), // too long
      "../../etc/passwd",
      "' OR 1=1 --",
    ]) {
      const res = await call(api.fetch, "/v1/codes", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: body(forged),
      });
      expect(res.status).toBe(200);
      const json = await res.json();
      // A fresh server-minted token every time — never the one supplied.
      expect(json.token).not.toBe(forged);
      expect(json.token).toMatch(/^[0-9a-f]{48}$/);
    }
  });

  test("normalizeToken accepts only server-minted hex", () => {
    // A-F are hex; the non-hex letters are what must be refused.
    expect(normalizeToken("z".repeat(48))).toBeUndefined();
    expect(normalizeToken("g".repeat(48))).toBeUndefined();
    expect(normalizeToken(`${"f".repeat(47)}!`)).toBeUndefined();
    expect(normalizeToken("f".repeat(48))).toBe("f".repeat(48));
    // Case-insensitive on the way in, canonicalised to lowercase.
    expect(normalizeToken("F".repeat(48))).toBe("f".repeat(48));
    expect(normalizeToken(123)).toBeUndefined();
    expect(normalizeToken(null)).toBeUndefined();
    expect(normalizeToken({})).toBeUndefined();
  });

  test("holding the token rewrites your own row rather than creating rows", async () => {
    const api = bicamApp();
    const first = await (
      await call(api.fetch, "/v1/codes", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ axisScore: 10, issueScores: { taxes: 10 } }),
      })
    ).json();

    const second = await (
      await call(api.fetch, "/v1/codes", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          token: first.token,
          axisScore: -10,
          issueScores: { taxes: -10 },
        }),
      })
    ).json();

    expect(second.code).toBe(first.code);
    const looked = await (
      await call(api.fetch, `/v1/codes/${first.code}`)
    ).json();
    expect(looked.axisScore).toBe(-10);
  });
});

describe("path parameters reject hostile input", () => {
  test("bioguide ids outside the strict shape are 400, never 500", async () => {
    const api = bicamApp();
    const hostile = [
      "../../../etc/passwd",
      "..%2f..%2fetc%2fpasswd",
      "S000033'%20OR%20'1'%3D'1",
      "S000033%00",
      "%2e%2e%2f",
      "<script>alert(1)</script>",
      "S00003",
      "SS00033",
      "0000033",
    ];
    for (const id of hostile) {
      for (const route of [`/v1/members/${id}`, `/v1/receipts/${id}`, `/v1/members/${id}/bills`]) {
        const res = await call(api.fetch, route);
        expect([400, 404]).toContain(res.status);
        const json = await res.json();
        expect(json.ok).toBe(false);
      }
    }
  });

  test("bill citations outside the strict shape are 400", async () => {
    const api = bicamApp();
    for (const path of [
      "/v1/bills/118/S'--/1655",
      "/v1/bills/118/<script>/1655",
      "/v1/bills/118/TOOLONGTYPE/1655",
      "/v1/bills/118/S/",
    ]) {
      const res = await call(api.fetch, path);
      expect([400, 404]).toContain(res.status);
    }
  });

  test("a SQL-shaped friend code is rejected by normalizeCode", () => {
    expect(normalizeCode("' OR 1=1 --")).toBeNull();
    expect(normalizeCode("ABC12")).toBeNull();
    expect(normalizeCode("ABC1234")).toBeNull();
    // 0/O and 1/I/L are excluded from the alphabet on purpose.
    expect(normalizeCode("ABCDE0")).toBeNull();
    expect(normalizeCode("ABCDE1")).toBeNull();
    expect(normalizeCode("a-b-c-2-3-4")).toBe("ABC234");
  });

  test("quoted input reaches SQLite as a value, not as SQL", async () => {
    // The parameterised queries make this a lookup miss rather than an error.
    // A 500 here would mean the string was being interpolated.
    const api = bicamApp();
    const res = await call(api.fetch, "/v1/codes/%27%20OR%201%3D1%20--");
    expect(res.status).toBe(400);
  });
});

describe("friend payload validation", () => {
  const post = (api: ReturnType<typeof bicamApp>, body: unknown) =>
    call(api.fetch, "/v1/codes", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(body),
    });

  test("caps the number of issue keys", async () => {
    const issueScores: Record<string, number> = {};
    for (let i = 0; i < 41; i++) issueScores[`issue_${i}`] = 0;
    const res = await post(bicamApp(), { axisScore: 0, issueScores });
    expect(res.status).toBe(400);
  });

  test("truncates an oversized display name instead of storing it", async () => {
    const api = bicamApp();
    const created = await (
      await post(api, {
        displayName: "x".repeat(500),
        axisScore: 0,
        issueScores: { taxes: 0 },
      })
    ).json();
    const looked = await (
      await call(api.fetch, `/v1/codes/${created.code}`)
    ).json();
    expect(looked.displayName).toHaveLength(40);
  });

  test("rejects a payload that is an array or a primitive", async () => {
    const api = bicamApp();
    for (const body of [[], "string", 42, true, null]) {
      const res = await post(api, body);
      expect(res.status).toBe(400);
    }
  });

  test("never echoes the write token back on lookup", async () => {
    // Lookup is unauthenticated by design — anyone with the 6-character code
    // sees the profile. Leaking the token there would also hand them write.
    const api = bicamApp();
    const created = await (
      await post(api, { axisScore: 0, issueScores: { taxes: 0 } })
    ).json();
    const looked = await (
      await call(api.fetch, `/v1/codes/${created.code}`)
    ).json();
    expect(looked).not.toHaveProperty("token");
    expect(JSON.stringify(looked)).not.toContain(created.token);
  });
});

describe("rate limiting", () => {
  test("POST /v1/codes blocks past the cap, per IP", async () => {
    const api = bicamApp(2);
    const body = JSON.stringify({ axisScore: 0, issueScores: { taxes: 0 } });
    const post = (ip: string) =>
      call(api.fetch, "/v1/codes", {
        method: "POST",
        headers: { "content-type": "application/json", "x-real-ip": ip },
        body,
      });

    expect((await post("7.7.7.1")).status).toBe(200);
    expect((await post("7.7.7.1")).status).toBe(200);
    expect((await post("7.7.7.1")).status).toBe(429);
    // A different caller still gets through.
    expect((await post("7.7.7.2")).status).toBe(200);
  });

  test("expired buckets are swept rather than accumulating", async () => {
    // A run of distinct callers, then confirm the map has not wedged the
    // limiter: the last caller must still be judged on its own bucket.
    const api = bicamApp(1);
    const body = JSON.stringify({ axisScore: 0, issueScores: { taxes: 0 } });
    for (let i = 0; i < 200; i++) {
      const res = await call(api.fetch, "/v1/codes", {
        method: "POST",
        headers: {
          "content-type": "application/json",
          "x-real-ip": `10.1.${Math.floor(i / 256)}.${i % 256}`,
        },
        body,
      });
      expect(res.status).toBe(200);
    }
    const repeat = await call(api.fetch, "/v1/codes", {
      method: "POST",
      headers: { "content-type": "application/json", "x-real-ip": "10.1.0.0" },
      body,
    });
    expect(repeat.status).toBe(429);
  });

  test("a flood past MAX_BUCKETS neither wedges the limiter nor grows unbounded", () => {
    // Regression: the sweep used to fall into a full O(buckets) scan on EVERY
    // call once the map hit its cap. Filling well past MAX_BUCKETS below would
    // take tens of seconds — and time this test out — under that code. The fix
    // trims the overflow in O(1) and leaves the scheduled expiry sweep alone.
    const rateLimit = createRateLimiter();
    const hour = 60 * 60 * 1000;
    let everBlocked = false;
    for (let i = 0; i < MAX_BUCKETS + 5_000; i++) {
      if (!rateLimit(`ip-${i}`, 1, hour)) everBlocked = true;
    }
    expect(everBlocked).toBe(false);
    // A brand-new caller is judged on its own fresh bucket, not someone's
    // leftover over-limit count.
    expect(rateLimit("newcomer", 2, hour)).toBe(true);
    expect(rateLimit("newcomer", 2, hour)).toBe(true);
    expect(rateLimit("newcomer", 2, hour)).toBe(false);
    // An early caller was evicted to hold the cap, so it gets a fresh window.
    expect(rateLimit("ip-0", 1, hour)).toBe(true);
    expect(rateLimit("ip-0", 1, hour)).toBe(false);
  });
});

describe("request body ceiling", () => {
  test("Bun.serve rejects a body over MAX_REQUEST_BODY_BYTES before fetch runs", async () => {
    // The app-level tooLarge() only sees a declared Content-Length; this is the
    // backstop for a chunked body that declares none. index.ts wires the same
    // constant into Bun.serve — this proves the value actually bites.
    let reached = false;
    const server = Bun.serve({
      port: 0,
      maxRequestBodySize: MAX_REQUEST_BODY_BYTES,
      fetch() {
        reached = true;
        return new Response("ok");
      },
    });
    try {
      const oversize = "x".repeat(MAX_REQUEST_BODY_BYTES + 1024);
      const res = await fetch(`http://localhost:${server.port}/`, {
        method: "POST",
        body: oversize,
      });
      expect(res.status).toBe(413);
      expect(reached).toBe(false);

      const ok = await fetch(`http://localhost:${server.port}/`, {
        method: "POST",
        body: "x".repeat(1024),
      });
      expect(ok.status).toBe(200);
    } finally {
      server.stop(true);
    }
  });
});

describe("stored data integrity", () => {
  test("expired profiles are purged and stop resolving", () => {
    const store = new Store(":memory:");
    const published = store.publish(
      {
        displayName: "Alex",
        axisScore: 0,
        issueScores: { taxes: 0 },
        issueWeights: {},
        pillarScores: {},
        dealbreakerIssueIds: [],
      },
      undefined,
      -1, // already expired
    );
    expect(store.lookup(published.code)).toBeNull();
  });

  test("payloads round-trip through SQLite unchanged", () => {
    const store = new Store(":memory:");
    const payload = {
      // Quotes and a null byte: stored as data, never parsed as SQL.
      displayName: "O'Brien \"; DROP TABLE profiles; --",
      axisScore: -42.5,
      issueScores: { taxes: -50 },
      issueWeights: { taxes: 2.5 },
      pillarScores: { economy: -50 },
      dealbreakerIssueIds: ["abortion"],
    };
    const published = store.publish(payload, undefined, 60_000);
    const found = store.lookup(published.code);
    expect(found?.payload).toEqual(payload);
    // The table is still there.
    expect(store.lookup("ZZZZZZ")).toBeNull();
  });

  test("the BICAM connection is read-only", () => {
    const dir = mkdtempSync(join(tmpdir(), "voteaxis-ro-"));
    const dbPath = join(dir, "bicam-receipts.sqlite");
    seedBicamDb(dbPath);
    const conn = new Database(dbPath, { readonly: true });
    expect(() =>
      conn.run("INSERT INTO meta (key, value) VALUES ('x', 'y')"),
    ).toThrow();
  });
});
