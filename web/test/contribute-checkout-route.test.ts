import { afterEach, describe, expect, test } from "bun:test";
import { POST } from "../app/api/contribute/checkout/route";
import { CONTRIBUTE_OFFERS } from "../lib/contribute";

/**
 * The limiter lives at module scope in the route, so every test in this file
 * shares it. Each case uses its own X-Real-IP to stay in its own bucket —
 * otherwise test order would decide which ones see a 429.
 */
function post(body: unknown, ip: string, raw?: string) {
  return POST(
    new Request("http://voteaxis.test/api/contribute/checkout", {
      method: "POST",
      headers: { "content-type": "application/json", "x-real-ip": ip },
      body: raw ?? JSON.stringify(body),
    }),
  );
}

describe("POST /api/contribute/checkout", () => {
  const prev = process.env.STRIPE_SECRET_KEY;

  afterEach(() => {
    if (prev === undefined) delete process.env.STRIPE_SECRET_KEY;
    else process.env.STRIPE_SECRET_KEY = prev;
  });

  test("rejects invalid JSON", async () => {
    const res = await post(null, "20.0.0.1", "not-json");
    expect(res.status).toBe(400);
  });

  test("rejects an unknown sku", async () => {
    const res = await post({ sku: "cycle_pass" }, "20.0.0.2");
    expect(res.status).toBe(400);
    expect((await res.json()).ok).toBe(false);
  });

  test("returns 503 when Stripe is not configured", async () => {
    delete process.env.STRIPE_SECRET_KEY;
    const res = await post({ sku: "tip_15" }, "20.0.0.3");
    expect(res.status).toBe(503);
    const body = await res.json();
    expect(body.ok).toBe(false);
    expect(String(body.error)).toContain("hello@voteaxis.org");
  });

  // The amount is never taken from the request. A caller can only name a SKU,
  // and the server looks the price up — so there is no field to tamper with.
  test("a client-supplied amount cannot influence the charge", async () => {
    delete process.env.STRIPE_SECRET_KEY;
    for (const attempt of [
      { sku: "tip_30", amountCents: 1 },
      { sku: "tip_30", unit_amount: 1 },
      { sku: "tip_30", amount: 0 },
      { sku: "tip_30", price_data: { unit_amount: 1 } },
    ]) {
      const res = await post(attempt, "20.0.0.4");
      // Reaches the Stripe-not-configured branch, meaning the SKU was accepted
      // on its own terms and the extra fields were simply never read.
      expect(res.status).toBe(503);
    }
  });

  test("rejects a sku smuggled in as a non-string", async () => {
    for (const sku of [
      { toString: () => "tip_15" },
      ["tip_15"],
      123,
      null,
      true,
    ]) {
      const res = await post({ sku }, "20.0.0.5");
      expect(res.status).toBe(400);
    }
  });

  test("every advertised offer is accepted by the route", async () => {
    delete process.env.STRIPE_SECRET_KEY;
    // A SKU shown on the page but missing from the allowlist would render a
    // button that always 400s.
    for (const offer of CONTRIBUTE_OFFERS) {
      const res = await post({ sku: offer.sku }, `20.1.0.${offer.sku.length}`);
      expect(res.status).toBe(503);
    }
  });

  test("rate-limits a single IP after 10 attempts", async () => {
    delete process.env.STRIPE_SECRET_KEY;
    const ip = "20.0.0.9";
    for (let i = 0; i < 10; i++) {
      const res = await post({ sku: "tip_15" }, ip);
      expect(res.status).toBe(503); // allowed through, Stripe just isn't set up
    }
    const blocked = await post({ sku: "tip_15" }, ip);
    expect(blocked.status).toBe(429);
    expect(blocked.headers.get("retry-after")).toBe("600");

    // A different caller is unaffected.
    expect((await post({ sku: "tip_15" }, "20.0.0.10")).status).toBe(503);
  });
});
