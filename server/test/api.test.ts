import { describe, expect, test } from "bun:test";
import { Database } from "bun:sqlite";
import {
  mkdtempSync,
  readFileSync,
  utimesSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { createApp, resetProxyWarning, weekIsStale } from "../src/app";
import { normalizeCode, randomCode } from "../src/codes";
import type { BicamApi } from "../src/congress";
import { createBicamClient, seedBicamDb } from "../src/congress";
import { createCongressGovEnricher } from "../src/congress-gov";
import { Store } from "../src/store";

const weekPath = join(import.meta.dir, "..", "data", "issue-of-the-week.json");

function app() {
  return createApp({
    store: new Store(":memory:"),
    ttlMs: 60 * 60 * 1000,
    weekPath,
    rateLimitPosts: 1000,
  });
}

async function call(
  fetch: (req: Request) => Response | Promise<Response>,
  path: string,
  init?: RequestInit,
) {
  return fetch(new Request(`http://voteaxis.test${path}`, init));
}

describe("voteaxis-api", () => {
  test("health", async () => {
    const res = await call(app().fetch, "/health");
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body.ok).toBe(true);
    expect(body.congress).toBe(false);
  });

  test("HEAD /health answers like GET, with no body", async () => {
    // Uptime monitors default to HEAD more often than not, and a 404 there
    // reads as the API being down.
    const res = await call(app().fetch, "/health", { method: "HEAD" });
    expect(res.status).toBe(200);
    expect(res.headers.get("content-type")).toContain("application/json");
    expect(await res.text()).toBe("");
    // The length still describes the GET, which is what HEAD is for.
    expect(Number(res.headers.get("content-length"))).toBeGreaterThan(0);

    const get = await call(app().fetch, "/health");
    expect(get.headers.get("content-length")).toBe(
      res.headers.get("content-length"),
    );
  });

  test("HEAD is not a way around a POST-only route", async () => {
    const res = await call(app().fetch, "/v1/codes", { method: "HEAD" });
    expect(res.status).toBe(404);
  });

  test("normalizeCode", () => {
    expect(normalizeCode("ab-c12z")).toBeNull();
    expect(randomCode()).toHaveLength(6);
    expect(normalizeCode("A2B3C4")).toBe("A2B3C4");
  });

  test("publish and lookup a friend profile", async () => {
    const api = app();
    const created = await call(api.fetch, "/v1/codes", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        displayName: "Alex",
        axisScore: -42,
        issueScores: { taxes: -50, abortion: -20 },
        issueWeights: { taxes: 2.5 },
        pillarScores: { economy: -50 },
        dealbreakerIssueIds: ["abortion"],
      }),
    });
    expect(created.status).toBe(200);
    const pub = await created.json();
    expect(pub.code).toHaveLength(6);
    expect(typeof pub.token).toBe("string");

    const found = await call(api.fetch, `/v1/codes/${pub.code}`);
    expect(found.status).toBe(200);
    const profile = await found.json();
    expect(profile.axisScore).toBe(-42);
    expect(profile.issueScores.taxes).toBe(-50);
    expect(profile.token).toBeUndefined();
  });

  test("same token keeps the same code", async () => {
    const api = app();
    const first = await (
      await call(api.fetch, "/v1/codes", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          axisScore: 10,
          issueScores: { taxes: 10 },
        }),
      })
    ).json();

    const second = await (
      await call(api.fetch, "/v1/codes", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          token: first.token,
          axisScore: 20,
          issueScores: { taxes: 20 },
        }),
      })
    ).json();

    expect(second.code).toBe(first.code);
    const found = await (await call(api.fetch, `/v1/codes/${first.code}`)).json();
    expect(found.axisScore).toBe(20);
  });

  test("missing code is 404", async () => {
    const res = await call(app().fetch, "/v1/codes/AAAAAA");
    expect(res.status).toBe(404);
  });

  test("rejects likert-sized junk", async () => {
    const res = await call(app().fetch, "/v1/codes", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ axisScore: 999, issueScores: { taxes: 0 } }),
    });
    expect(res.status).toBe(400);
  });

  /** A week file stamped [weekOf], written somewhere disposable. */
  function weekApp(weekOf: string, now: number, maxAgeMs?: number) {
    const dir = mkdtempSync(join(tmpdir(), "voteaxis-week-"));
    const path = join(dir, "issue-of-the-week.json");
    writeFileSync(
      path,
      JSON.stringify({
        weekOf,
        issueId: "immigration",
        headline: "Who belongs, and on what terms?",
        question: "Expand legal paths or tighten enforcement?",
      }),
    );
    return createApp({
      store: new Store(":memory:"),
      ttlMs: 60 * 60 * 1000,
      weekPath: path,
      rateLimitPosts: 1000,
      now: () => now,
      weekMaxAgeMs: maxAgeMs,
    });
  }

  const AUG_20 = Date.parse("2026-08-20T12:00:00Z");

  test("issue of the week", async () => {
    const res = await call(weekApp("2026-08-17", AUG_20).fetch, "/v1/week");
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body.issueId).toBe("immigration");
  });

  test("the week response is cached but re-read when the file changes", async () => {
    const dir = mkdtempSync(join(tmpdir(), "voteaxis-weekcache-"));
    const path = join(dir, "issue-of-the-week.json");
    const write = (issueId: string) =>
      writeFileSync(
        path,
        JSON.stringify({
          weekOf: "2026-08-17",
          issueId,
          headline: "h",
          question: "q",
        }),
      );
    write("immigration");
    const api = createApp({
      store: new Store(":memory:"),
      ttlMs: 60 * 60 * 1000,
      weekPath: path,
      rateLimitPosts: 1000,
      now: () => AUG_20,
    });
    expect((await (await call(api.fetch, "/v1/week")).json()).issueId).toBe(
      "immigration",
    );
    // Bump mtime forward so the stat-keyed cache misses.
    write("healthcare");
    const later = new Date(Date.now() + 2000);
    utimesSync(path, later, later);
    expect((await (await call(api.fetch, "/v1/week")).json()).issueId).toBe(
      "healthcare",
    );
  });

  test("a stale issue of the week is withheld, not served", async () => {
    // The card is labelled "ISSUE OF THE WEEK", so a month-old prompt is the
    // endpoint lying. 404 lets the client drop the card instead.
    const res = await call(weekApp("2026-07-01", AUG_20).fetch, "/v1/week");
    expect(res.status).toBe(404);
    const body = await res.json();
    expect(body.error).toContain("out of date");
  });

  test("weekIsStale needs a real date to call anything current", () => {
    const day = 24 * 60 * 60 * 1000;
    const fresh = { weekOf: "2026-08-17" };
    expect(weekIsStale(fresh, AUG_20, 10 * day)).toBe(false);
    expect(weekIsStale(fresh, AUG_20, 1 * day)).toBe(true);
    // No usable stamp means no way to expire, so it never counts as current.
    expect(weekIsStale({ weekOf: "not-a-date" }, AUG_20, 10 * day)).toBe(true);
    expect(weekIsStale({}, AUG_20, 10 * day)).toBe(true);
    expect(weekIsStale(null, AUG_20, 10 * day)).toBe(true);
  });

  test("the week checker agrees with the window the API serves", () => {
    // scripts/week.ts is what a cron runs to warn before the card vanishes.
    // If its idea of "stale" drifts from the endpoint's, the warning fires at
    // the wrong time — or worse, never.
    const script = readFileSync(
      join(import.meta.dir, "..", "scripts", "week.ts"),
      "utf8",
    );
    const scriptDays = Number(
      /const SERVED_FOR_DAYS = (\d+)/.exec(script)?.[1],
    );
    const app = readFileSync(
      join(import.meta.dir, "..", "src", "app.ts"),
      "utf8",
    );
    const appDays = Number(
      /weekMaxAgeMs = opts\.weekMaxAgeMs \?\? (\d+) \* DAY_MS/.exec(app)?.[1],
    );
    expect(scriptDays).toBeGreaterThan(0);
    expect(appDays).toBe(scriptDays);
  });

  test("OPTIONS gets no special handling", async () => {
    // The old 204 read like CORS was supported when no route ever sets
    // Access-Control-Allow-Origin. Falling through is the honest answer.
    const res = await call(app().fetch, "/v1/week", { method: "OPTIONS" });
    expect(res.status).toBe(404);
    expect(res.headers.get("access-control-allow-origin")).toBeNull();
  });

  test("an oversized body is refused before it is read", async () => {
    for (const path of ["/v1/codes", "/v1/results"]) {
      const res = await call(app().fetch, path, {
        method: "POST",
        headers: {
          "content-type": "application/json",
          "content-length": String(2 * 1024 * 1024),
        },
        body: JSON.stringify({ axisScore: 0, issueScores: { taxes: 0 } }),
      });
      expect(res.status).toBe(413);
    }
  });

  test("a missing proxy header warns once, not per request", async () => {
    resetProxyWarning();
    const warnings: string[] = [];
    const original = console.warn;
    console.warn = (...args: unknown[]) => warnings.push(String(args[0]));
    try {
      const api = app();
      await call(api.fetch, "/v1/codes/A2B3C4");
      await call(api.fetch, "/v1/codes/A2B3C4");
    } finally {
      console.warn = original;
    }
    expect(warnings).toHaveLength(1);
    expect(warnings[0]).toContain("one rate-limit bucket");
  });

  test("does not reflect CORS origins", async () => {
    const res = await app().fetch(
      new Request("http://voteaxis.test/health", {
        headers: { origin: "https://evil.example" },
      }),
    );
    expect(res.headers.get("access-control-allow-origin")).toBeNull();
  });

  test("client-chosen tokens are not stored", async () => {
    const api = app();
    const planted = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
    const created = await (
      await call(api.fetch, "/v1/codes", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          token: planted,
          axisScore: 0,
          issueScores: { taxes: 0 },
        }),
      })
    ).json();
    expect(created.token).not.toBe(planted);
    expect(created.token).toMatch(/^[0-9a-f]{48}$/);
  });

  test("X-Forwarded-For does not split the rate-limit bucket", async () => {
    const api = createApp({
      store: new Store(":memory:"),
      ttlMs: 60 * 60 * 1000,
      weekPath,
      rateLimitPosts: 2,
    });
    const body = JSON.stringify({ axisScore: 0, issueScores: { taxes: 0 } });
    for (let i = 0; i < 2; i++) {
      const res = await call(api.fetch, "/v1/codes", {
        method: "POST",
        headers: {
          "content-type": "application/json",
          "x-forwarded-for": `${i}.1.1.1`,
        },
        body,
      });
      expect(res.status).toBe(200);
    }
    const blocked = await call(api.fetch, "/v1/codes", {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-forwarded-for": "9.9.9.9",
      },
      body,
    });
    expect(blocked.status).toBe(429);
  });

  test("X-Real-IP is the rate-limit identity", async () => {
    const api = createApp({
      store: new Store(":memory:"),
      ttlMs: 60 * 60 * 1000,
      weekPath,
      rateLimitPosts: 1,
    });
    const body = JSON.stringify({ axisScore: 0, issueScores: { taxes: 0 } });
    const first = await call(api.fetch, "/v1/codes", {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-real-ip": "10.0.0.1",
      },
      body,
    });
    expect(first.status).toBe(200);
    const again = await call(api.fetch, "/v1/codes", {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-real-ip": "10.0.0.1",
      },
      body,
    });
    expect(again.status).toBe(429);
    const other = await call(api.fetch, "/v1/codes", {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-real-ip": "10.0.0.2",
      },
      body,
    });
    expect(other.status).toBe(200);
  });

  test("unknown route is 404", async () => {
    const res = await call(app().fetch, "/v1/nope");
    expect(res.status).toBe(404);
  });

  test("/v1/congress caches meta() rather than scanning the table every hit", async () => {
    let metaCalls = 0;
    let clock = 1_000_000;
    const bicam: BicamApi = {
      configured: true,
      meta: () => {
        metaCalls += 1;
        return {
          source: "bicam.net",
          attribution: "test",
          members: 1,
          bills: 2,
          minCongress: 117,
        };
      },
      member: () => null,
      memberBills: () => [],
      bill: () => null,
      getReceipts: () => ({
        source: "bicam.net",
        bioguideId: "S000033",
        name: null,
        memberUrl: "",
        sponsored: [],
        cosponsored: [],
      }),
    };
    const api = createApp({
      store: new Store(":memory:"),
      ttlMs: 60 * 60 * 1000,
      weekPath,
      rateLimitPosts: 1000,
      bicam,
      now: () => clock,
    });
    const congress = () =>
      call(api.fetch, "/v1/congress", { headers: { "x-real-ip": "4.4.4.4" } });

    for (let i = 0; i < 5; i++) {
      expect((await (await congress()).json()).bills).toBe(2);
    }
    expect(metaCalls).toBe(1);

    // Past the 5-minute TTL it refreshes once.
    clock += 5 * 60 * 1000 + 1;
    await congress();
    await congress();
    expect(metaCalls).toBe(2);
  });

  test("GET routes that read from disk or scan a table are metered per IP", async () => {
    // /v1/week and /v1/congress used to have no limiter at all — one reads and
    // parses a file per hit, the other runs COUNT(*) over the bills table.
    const dir = mkdtempSync(join(tmpdir(), "voteaxis-meter-"));
    const dbPath = join(dir, "bicam-receipts.sqlite");
    seedBicamDb(dbPath);
    const api = createApp({
      store: new Store(":memory:"),
      ttlMs: 60 * 60 * 1000,
      weekPath,
      rateLimitPosts: 1000,
      bicam: createBicamClient({ dbPath }),
    });
    const flood = async (path: string, cap: number) => {
      let last = 200;
      for (let i = 0; i < cap + 2; i++) {
        const res = await call(api.fetch, path, {
          headers: { "x-real-ip": `55.55.${cap}.1` },
        });
        last = res.status;
      }
      return last;
    };
    expect(await flood("/v1/congress", 120)).toBe(429);
    expect(await flood("/v1/week", 600)).toBe(429);
    // A different caller is not caught in someone else's bucket.
    const other = await call(api.fetch, "/v1/week", {
      headers: { "x-real-ip": "55.55.99.9" },
    });
    expect(other.status).not.toBe(429);
  });

  test("invalid friend code is 400", async () => {
    const res = await call(app().fetch, "/v1/codes/000000");
    expect(res.status).toBe(400);
  });

  test("week file missing is 404", async () => {
    const api = createApp({
      store: new Store(":memory:"),
      ttlMs: 60 * 60 * 1000,
      weekPath: join(tmpdir(), "missing-week.json"),
      rateLimitPosts: 1000,
    });
    const res = await call(api.fetch, "/v1/week");
    expect(res.status).toBe(404);
  });

  test("congress REST requires a BICAM sqlite file", async () => {
    const res = await call(app().fetch, "/v1/congress");
    expect(res.status).toBe(503);
    const body = await res.json();
    expect(body.source).toBe("bicam.net");
  });

  test("receipts reject a bad bioguide", async () => {
    const res = await call(app().fetch, "/v1/receipts/not-an-id");
    expect(res.status).toBe(400);
  });

  test("congress REST reads BICAM sqlite", async () => {
    const dir = mkdtempSync(join(tmpdir(), "voteaxis-congress-"));
    const dbPath = join(dir, "bicam-receipts.sqlite");
    seedBicamDb(dbPath);
    const api = createApp({
      store: new Store(":memory:"),
      ttlMs: 60 * 60 * 1000,
      weekPath,
      rateLimitPosts: 1000,
      bicam: createBicamClient({ dbPath }),
    });

    const meta = await (await call(api.fetch, "/v1/congress")).json();
    expect(meta.source).toBe("bicam.net");
    expect(meta.members).toBe(1);
    expect(meta.bills).toBe(1);

    const member = await call(api.fetch, "/v1/members/s000033");
    expect(member.status).toBe(200);
    const profile = await member.json();
    expect(profile.name).toBe("Bernard Sanders");
    expect(profile.party).toBe("Independent");
    expect(profile.current).toBe(true);

    const bills = await (
      await call(api.fetch, "/v1/members/S000033/bills?kind=sponsored")
    ).json();
    expect(bills.bills[0].number).toBe("1655");

    const bill = await call(api.fetch, "/v1/bills/118/s/1655");
    expect(bill.status).toBe(200);
    const citation = await bill.json();
    expect(citation.title).toBe("Medicare for All Act");

    const receipts = await call(api.fetch, "/v1/receipts/S000033");
    expect(receipts.status).toBe(200);
    const body = await receipts.json();
    expect(body.sponsored[0].number).toBe("1655");
    expect(body.source).toBe("bicam.net");
    expect(body.sponsored[0].latestAction).toBeNull();
    expect(body.sponsored[0].enrichedFrom).toBeUndefined();
  });

  test("receipts stay BICAM-only when Congress.gov has no key", async () => {
    const dir = mkdtempSync(join(tmpdir(), "voteaxis-nokey-"));
    const dbPath = join(dir, "bicam-receipts.sqlite");
    seedBicamDb(dbPath);
    const api = createApp({
      store: new Store(":memory:"),
      ttlMs: 60 * 60 * 1000,
      weekPath,
      rateLimitPosts: 1000,
      bicam: createBicamClient({ dbPath }),
      enricher: createCongressGovEnricher({
        cachePath: ":memory:",
        fetch: async () => {
          throw new Error("no-key fallback must not call Congress.gov");
        },
      }),
    });
    const res = await call(api.fetch, "/v1/receipts/S000033");
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body.source).toBe("bicam.net");
    expect(body.sponsored[0].title).toBe("Medicare for All Act");
    expect(body.sponsored[0].latestAction).toBeNull();
    expect(body.sponsored[0].summary).toBeUndefined();
  });

  test("receipts hydrate visible bills from Congress.gov", async () => {
    const dir = mkdtempSync(join(tmpdir(), "voteaxis-hydrate-"));
    const dbPath = join(dir, "bicam-receipts.sqlite");
    seedBicamDb(dbPath);
    const api = createApp({
      store: new Store(":memory:"),
      ttlMs: 60 * 60 * 1000,
      weekPath,
      rateLimitPosts: 1000,
      bicam: createBicamClient({ dbPath }),
      enricher: createCongressGovEnricher({
        apiKey: "test-key",
        cachePath: ":memory:",
        fetch: async (url) => {
          if (String(url).includes("/summaries")) {
            return new Response(
              JSON.stringify({
                summaries: [{ text: "<p>This bill creates Medicare for All.</p>" }],
              }),
            );
          }
          return new Response(
            JSON.stringify({
              bill: {
                latestAction: { text: "Became Public Law No: 117-169." },
              },
            }),
          );
        },
      }),
    });
    const body = await (await call(api.fetch, "/v1/receipts/S000033")).json();
    expect(body.source).toBe("bicam.net");
    expect(body.sponsored[0].latestAction).toBe(
      "Became Public Law No: 117-169.",
    );
    expect(body.sponsored[0].summary).toBe("This bill creates Medicare for All.");
    expect(body.sponsored[0].enrichedFrom).toBe("congress.gov");
  });

  describe("member bills ?limit", () => {
    /** seedBicamDb ships one bill; the default limit is 8, so we need more. */
    function seedManyBills(dbPath: string, count: number) {
      seedBicamDb(dbPath);
      const conn = new Database(dbPath);
      for (let i = 0; i < count; i++) {
        const id = `s${2000 + i}-118`;
        conn.run(
          "INSERT INTO bills (bill_id, congress, type, number, title, introduced_date) VALUES (?, ?, ?, ?, ?, ?)",
          [id, 118, "S", String(2000 + i), `Test Act ${i}`, "2023-05-17"],
        );
        conn.run(
          "INSERT INTO sponsorships (bioguide_id, bill_id, kind) VALUES (?, ?, ?)",
          ["S000033", id, "sponsored"],
        );
      }
      conn.close();
    }

    function bicamApp() {
      const dir = mkdtempSync(join(tmpdir(), "voteaxis-limit-"));
      const dbPath = join(dir, "bicam-receipts.sqlite");
      seedManyBills(dbPath, 20);
      return createApp({
        store: new Store(":memory:"),
        ttlMs: 60 * 60 * 1000,
        weekPath,
        rateLimitPosts: 1000,
        bicam: createBicamClient({ dbPath }),
      });
    }

    // Regression: Number(null) and Number("") are both 0, which is finite, so
    // the NaN-only guard skipped the fallback and clamped the default to 1.
    // Garbage input got the correct 8 while the ordinary request got one bill.
    test("omitted limit falls back to 8, not 1", async () => {
      const res = await call(bicamApp().fetch, "/v1/members/S000033/bills?kind=sponsored");
      expect(res.status).toBe(200);
      expect((await res.json()).bills).toHaveLength(8);
    });

    test("empty limit falls back to 8", async () => {
      const res = await call(
        bicamApp().fetch,
        "/v1/members/S000033/bills?kind=sponsored&limit=",
      );
      expect((await res.json()).bills).toHaveLength(8);
    });

    test("unparseable limit falls back to 8", async () => {
      const res = await call(
        bicamApp().fetch,
        "/v1/members/S000033/bills?kind=sponsored&limit=abc",
      );
      expect((await res.json()).bills).toHaveLength(8);
    });

    test("explicit limit is honoured and clamped to 50", async () => {
      const api = bicamApp();
      const three = await call(
        api.fetch,
        "/v1/members/S000033/bills?kind=sponsored&limit=3",
      );
      expect((await three.json()).bills).toHaveLength(3);

      const huge = await call(
        api.fetch,
        "/v1/members/S000033/bills?kind=sponsored&limit=9999",
      );
      // 21 sponsored rows exist, so the 50 clamp is not the binding constraint.
      expect((await huge.json()).bills).toHaveLength(21);

      const zero = await call(
        api.fetch,
        "/v1/members/S000033/bills?kind=sponsored&limit=0",
      );
      expect((await zero.json()).bills).toHaveLength(1);
    });
  });
});
