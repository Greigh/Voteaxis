import { describe, expect, test } from "bun:test";
import { clientIp, createRateLimiter, MAX_BUCKETS } from "../lib/rate-limit";

describe("createRateLimiter", () => {
  test("allows up to the cap, then blocks", () => {
    const allow = createRateLimiter(3, 60_000);
    expect(allow("a")).toBe(true);
    expect(allow("a")).toBe(true);
    expect(allow("a")).toBe(true);
    expect(allow("a")).toBe(false);
    expect(allow("a")).toBe(false);
  });

  test("keys are independent", () => {
    const allow = createRateLimiter(1, 60_000);
    expect(allow("a")).toBe(true);
    expect(allow("a")).toBe(false);
    // b is untouched by a exhausting its bucket.
    expect(allow("b")).toBe(true);
    expect(allow("b")).toBe(false);
  });

  test("the window expires and the allowance returns", async () => {
    const allow = createRateLimiter(2, 50);
    expect(allow("a")).toBe(true);
    expect(allow("a")).toBe(true);
    expect(allow("a")).toBe(false);
    await Bun.sleep(70);
    expect(allow("a")).toBe(true);
  });

  test("a cap of zero blocks everything after the first window opens", () => {
    // Guards against an off-by-one making a misconfigured cap wide open.
    const allow = createRateLimiter(0, 60_000);
    // The first call seeds the bucket; every subsequent one is over the cap.
    allow("a");
    expect(allow("a")).toBe(false);
  });

  test("many distinct keys do not wedge the limiter", () => {
    // Exercises the sweep path. Each key must still be judged on its own
    // bucket rather than inheriting someone else's count.
    const allow = createRateLimiter(1, 60_000);
    for (let i = 0; i < 5_000; i++) {
      expect(allow(`key-${i}`)).toBe(true);
    }
    expect(allow("key-0")).toBe(false);
    expect(allow("key-4999")).toBe(false);
    expect(allow("fresh")).toBe(true);
  });

  test("a flood past MAX_BUCKETS stays O(1) per call and bounded", () => {
    // Regression: once the map filled, the sweep fell into a full O(buckets)
    // scan on EVERY call — this loop would take tens of seconds and time the
    // test out under that code.
    const allow = createRateLimiter(1, 60 * 60 * 1000);
    let everBlocked = false;
    for (let i = 0; i < MAX_BUCKETS + 5_000; i++) {
      if (!allow(`key-${i}`)) everBlocked = true;
    }
    // Every first-seen key was allowed; none inherited a full bucket.
    expect(everBlocked).toBe(false);
    // A brand-new key gets its own bucket.
    expect(allow("newcomer")).toBe(true);
    expect(allow("newcomer")).toBe(false);
    // An early key was evicted to hold the cap, so its allowance is back.
    expect(allow("key-0")).toBe(true);
    expect(allow("key-0")).toBe(false);
  });
});

describe("clientIp", () => {
  function ipOf(headers: Record<string, string>) {
    return clientIp(new Request("http://voteaxis.test/", { headers }));
  }

  test("client-supplied X-Forwarded-For is ignored", () => {
    // nginx appends to XFF rather than overwriting it, so honouring it would
    // let one caller mint a fresh bucket per request.
    expect(ipOf({ "x-forwarded-for": "1.2.3.4" })).toBe("local");
    expect(ipOf({ "x-forwarded-for": "1.2.3.4, 5.6.7.8" })).toBe("local");
  });

  test("X-Real-IP is preferred, CF-Connecting-IP is the fallback", () => {
    expect(ipOf({ "x-real-ip": "9.9.9.9" })).toBe("9.9.9.9");
    expect(ipOf({ "cf-connecting-ip": "8.8.8.8" })).toBe("8.8.8.8");
    expect(
      ipOf({ "x-real-ip": "9.9.9.9", "cf-connecting-ip": "8.8.8.8" }),
    ).toBe("9.9.9.9");
  });

  test("malformed proxy headers fail closed to a shared bucket", () => {
    expect(ipOf({ "x-real-ip": "1.2.3.4, 5.6.7.8" })).toBe("local");
    expect(ipOf({ "x-real-ip": "1.2.3.4 5.6.7.8" })).toBe("local");
    expect(ipOf({ "x-real-ip": "a".repeat(65) })).toBe("local");
    expect(ipOf({ "x-real-ip": "  " })).toBe("local");
  });

  test("no proxy headers at all is a single shared bucket", () => {
    expect(ipOf({})).toBe("local");
  });
});
