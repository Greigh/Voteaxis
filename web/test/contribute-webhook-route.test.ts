import { afterEach, describe, expect, test } from "bun:test";
import { createHmac } from "node:crypto";
import {
  POST,
  resetWebhookDedupe,
  resetWebhookRateLimit,
} from "../app/api/contribute/webhook/route";

const SECRET = "whsec_test_secret_for_signing_only";

/** The header Stripe sends: HMAC-SHA256 over `<timestamp>.<body>`. */
function signed(body: string): string {
  const t = Math.floor(Date.now() / 1000);
  const v1 = createHmac("sha256", SECRET).update(`${t}.${body}`).digest("hex");
  return `t=${t},v1=${v1}`;
}

function post(body: string, signature = signed(body)) {
  return POST(
    new Request("http://voteaxis.test/api/contribute/webhook", {
      method: "POST",
      headers: { "stripe-signature": signature },
      body,
    }),
  );
}

describe("POST /api/contribute/webhook", () => {
  const prevKey = process.env.STRIPE_SECRET_KEY;
  const prevSecret = process.env.STRIPE_WEBHOOK_SECRET;

  afterEach(() => {
    if (prevKey === undefined) delete process.env.STRIPE_SECRET_KEY;
    else process.env.STRIPE_SECRET_KEY = prevKey;
    if (prevSecret === undefined) delete process.env.STRIPE_WEBHOOK_SECRET;
    else process.env.STRIPE_WEBHOOK_SECRET = prevSecret;
    resetWebhookDedupe();
    resetWebhookRateLimit();
  });

  function configure() {
    process.env.STRIPE_SECRET_KEY = "sk_test_not_a_real_key";
    process.env.STRIPE_WEBHOOK_SECRET = SECRET;
  }

  function event(id: string) {
    return JSON.stringify({
      id,
      type: "checkout.session.completed",
      data: {
        object: {
          id: "cs_test_123",
          mode: "payment",
          amount_total: 1500,
          metadata: { sku: "one_time_15" },
          customer_details: { email: "someone@example.com" },
        },
      },
    });
  }

  test("returns 503 when the webhook secret is missing", async () => {
    delete process.env.STRIPE_SECRET_KEY;
    delete process.env.STRIPE_WEBHOOK_SECRET;
    const res = await POST(
      new Request("http://voteaxis.test/api/contribute/webhook", {
        method: "POST",
        body: "{}",
      }),
    );
    expect(res.status).toBe(503);
  });

  test("rejects a body whose signature does not match", async () => {
    configure();
    const res = await post(event("evt_tampered"), "t=1,v1=deadbeef");
    expect(res.status).toBe(400);
    expect((await res.json()).error).toBe("Invalid signature.");
  });

  test("accepts a correctly signed event", async () => {
    configure();
    const res = await post(event("evt_first"));
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body.received).toBe(true);
    expect(body.duplicate).toBeUndefined();
  });

  test("a replayed event id is acknowledged, not acted on twice", async () => {
    // Stripe retries anything that does not answer 200, and can deliver the
    // same event more than once by design — which sent two "you got a
    // contribution" notifications for a single payment.
    configure();
    const first = await post(event("evt_replayed"));
    expect((await first.json()).duplicate).toBeUndefined();

    const second = await post(event("evt_replayed"));
    // Still 200: answering an error to a retry only brings it back again.
    expect(second.status).toBe(200);
    expect((await second.json()).duplicate).toBe(true);
  });

  test("a different event id is still handled", async () => {
    configure();
    await post(event("evt_one"));
    const other = await post(event("evt_two"));
    expect((await other.json()).duplicate).toBeUndefined();
  });

  test("an oversized body is refused before the HMAC runs", async () => {
    configure();
    const huge = `{"padding":"${"x".repeat(1_100_000)}"}`;
    const res = await POST(
      new Request("http://voteaxis.test/api/contribute/webhook", {
        method: "POST",
        headers: {
          "stripe-signature": "t=1,v1=deadbeef",
          "content-length": String(Buffer.byteLength(huge)),
        },
        body: huge,
      }),
    );
    expect(res.status).toBe(413);
  });

  test("an oversized body with no Content-Length is still caught after the read", async () => {
    configure();
    // A chunked request declares no Content-Length, so the header pre-check
    // cannot see it — the post-read byte count is the backstop.
    const huge = `{"padding":"${"x".repeat(1_100_000)}"}`;
    const chunked = {
      headers: new Headers({ "stripe-signature": "t=1,v1=deadbeef" }),
      text: async () => huge,
    } as unknown as Request;
    const res = await POST(chunked);
    expect(res.status).toBe(413);
  });

  test("blocks past the per-minute cap", async () => {
    configure();
    const body = event("evt_flood");
    // Wrong signature so nothing is acted on; the limiter runs before that.
    const statuses = new Set<number>();
    for (let i = 0; i < 305; i++) {
      statuses.add((await post(body, "t=1,v1=deadbeef")).status);
    }
    expect(statuses.has(400)).toBe(true); // allowed calls reached the sig check
    expect(statuses.has(429)).toBe(true); // and the cap eventually bit
  });
});
