import { afterEach, describe, expect, test } from "bun:test";
import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { POST } from "../app/api/waitlist/route";
import { resetWaitlistCache } from "../lib/waitlist";

/**
 * The limiter lives at module scope in the route, so it is shared by every test
 * in this file. Each case gets its own X-Real-IP to stay in its own bucket —
 * otherwise the order of tests would decide which ones see a 429.
 */
function post(body: unknown, ip: string, raw?: string) {
  return POST(
    new Request("http://voteaxis.test/api/waitlist", {
      method: "POST",
      headers: { "content-type": "application/json", "x-real-ip": ip },
      body: raw ?? JSON.stringify(body),
    }),
  );
}

function isolatedStore() {
  const dir = mkdtempSync(join(tmpdir(), "waitlist-route-"));
  process.env.WAITLIST_STORE_PATH = join(dir, "waitlist.jsonl");
  resetWaitlistCache();
}

describe("POST /api/waitlist", () => {
  const prev = process.env.WAITLIST_STORE_PATH;
  const prevSmtp = process.env.SMTP_HOST;
  const prevHook = process.env.WAITLIST_WEBHOOK_URL;

  afterEach(() => {
    if (prev === undefined) delete process.env.WAITLIST_STORE_PATH;
    else process.env.WAITLIST_STORE_PATH = prev;
    if (prevSmtp === undefined) delete process.env.SMTP_HOST;
    else process.env.SMTP_HOST = prevSmtp;
    if (prevHook === undefined) delete process.env.WAITLIST_WEBHOOK_URL;
    else process.env.WAITLIST_WEBHOOK_URL = prevHook;
    resetWaitlistCache();
  });

  test("rejects invalid JSON", async () => {
    const res = await post(null, "10.0.0.1", "not-json");
    expect(res.status).toBe(400);
    expect((await res.json()).ok).toBe(false);
  });

  test("rejects a missing email", async () => {
    const res = await post({}, "10.0.0.2");
    expect(res.status).toBe(400);
  });

  test("accepts optional roles alongside email", async () => {
    const res = await post(
      { email: "not-an-email", roles: ["teacher"] },
      "10.0.0.3",
    );
    expect(res.status).toBe(400);
  });

  // Regression: the route used to echo joinWaitlist's `alreadyJoined`, which
  // let anyone POST an address and learn from the response whether that person
  // had signed up. Both answers must be byte-identical.
  test("does not reveal whether an address is already on the list", async () => {
    delete process.env.SMTP_HOST;
    delete process.env.WAITLIST_WEBHOOK_URL;
    isolatedStore();

    const first = await post({ email: "probe@example.com" }, "10.0.0.4");
    const second = await post({ email: "probe@example.com" }, "10.0.0.5");

    expect(first.status).toBe(200);
    expect(second.status).toBe(200);

    const a = await first.json();
    const b = await second.json();
    expect(a).toEqual({ ok: true });
    expect(b).toEqual({ ok: true });
    expect(a).not.toHaveProperty("alreadyJoined");
    expect(JSON.stringify(a)).toBe(JSON.stringify(b));
  });

  test("rate-limits a single IP after 5 signups", async () => {
    delete process.env.SMTP_HOST;
    delete process.env.WAITLIST_WEBHOOK_URL;
    isolatedStore();

    const ip = "10.0.0.6";
    for (let i = 0; i < 5; i++) {
      const res = await post({ email: `flood${i}@example.com` }, ip);
      expect(res.status).toBe(200);
    }

    const blocked = await post({ email: "flood5@example.com" }, ip);
    expect(blocked.status).toBe(429);
    expect(blocked.headers.get("retry-after")).toBe("600");
    expect((await blocked.json()).ok).toBe(false);

    // A different caller is unaffected.
    const other = await post({ email: "elsewhere@example.com" }, "10.0.0.7");
    expect(other.status).toBe(200);
  });

  // X-Forwarded-For is appended to rather than overwritten, so honouring it
  // would let one caller mint a fresh bucket per request.
  test("client-supplied X-Forwarded-For cannot split the bucket", async () => {
    delete process.env.SMTP_HOST;
    delete process.env.WAITLIST_WEBHOOK_URL;
    isolatedStore();

    const ip = "10.0.0.8";
    for (let i = 0; i < 5; i++) {
      await POST(
        new Request("http://voteaxis.test/api/waitlist", {
          method: "POST",
          headers: {
            "content-type": "application/json",
            "x-real-ip": ip,
            "x-forwarded-for": `${i}.1.1.1`,
          },
          body: JSON.stringify({ email: `xff${i}@example.com` }),
        }),
      );
    }

    const blocked = await POST(
      new Request("http://voteaxis.test/api/waitlist", {
        method: "POST",
        headers: {
          "content-type": "application/json",
          "x-real-ip": ip,
          "x-forwarded-for": "9.9.9.9",
        },
        body: JSON.stringify({ email: "xff-final@example.com" }),
      }),
    );
    expect(blocked.status).toBe(429);
  });
});
