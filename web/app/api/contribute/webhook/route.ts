import { NextResponse } from "next/server";
import type Stripe from "stripe";
import { sendMail } from "@/lib/mail";
import { clientIp, createRateLimiter } from "@/lib/rate-limit";
import { getStripe, isStripeConfigured } from "@/lib/stripe";

/**
 * Unauthenticated, and it runs an HMAC over the whole body before it can tell a
 * real event from junk. Real Stripe events are tens of KB and arrive from a
 * handful of source IPs well under this rate — anything past either bound is
 * not Stripe.
 */
const MAX_WEBHOOK_BYTES = 1024 * 1024;
const WEBHOOK_RATE = { max: 300, windowMs: 60 * 1000 };
let allow = createRateLimiter(WEBHOOK_RATE.max, WEBHOOK_RATE.windowMs);

/** Tests, which need a clean window per case. */
export function resetWebhookRateLimit(): void {
  allow = createRateLimiter(WEBHOOK_RATE.max, WEBHOOK_RATE.windowMs);
}

/**
 * Event ids already acted on.
 *
 * Stripe retries any webhook that does not answer 200 and can deliver the same
 * event more than once by design, so the notification below fires twice for
 * one contribution and reads like a double charge. In-process and bounded: PM2
 * runs a single instance, and the window only has to outlive Stripe's retry
 * schedule, not survive a redeploy. A missed dedupe after a restart costs one
 * duplicate email, which is the failure this is worth spending on.
 */
const MAX_SEEN = 500;
const seen = new Set<string>();

function alreadyHandled(eventId: string): boolean {
  if (seen.has(eventId)) return true;
  seen.add(eventId);
  if (seen.size > MAX_SEEN) {
    // Sets iterate in insertion order, so this drops the oldest ids first.
    const excess = seen.size - MAX_SEEN;
    let dropped = 0;
    for (const id of seen) {
      if (dropped++ >= excess) break;
      seen.delete(id);
    }
  }
  return false;
}

/** Tests, which need a clean window per case. */
export function resetWebhookDedupe(): void {
  seen.clear();
}

export async function POST(request: Request) {
  if (!allow(clientIp(request))) {
    return NextResponse.json(
      { ok: false, error: "Too many requests." },
      { status: 429 },
    );
  }

  const declared = Number(request.headers.get("content-length"));
  if (Number.isFinite(declared) && declared > MAX_WEBHOOK_BYTES) {
    return NextResponse.json(
      { ok: false, error: "Payload too large." },
      { status: 413 },
    );
  }

  const secret = process.env.STRIPE_WEBHOOK_SECRET?.trim() ?? "";
  if (!isStripeConfigured() || !secret) {
    return NextResponse.json(
      { ok: false, error: "Webhook is not configured." },
      { status: 503 },
    );
  }

  const signature = request.headers.get("stripe-signature");
  if (!signature) {
    return NextResponse.json(
      { ok: false, error: "Missing signature." },
      { status: 400 },
    );
  }

  const payload = await request.text();
  if (Buffer.byteLength(payload, "utf8") > MAX_WEBHOOK_BYTES) {
    // A body with no (or a lying) Content-Length still gets a ceiling.
    return NextResponse.json(
      { ok: false, error: "Payload too large." },
      { status: 413 },
    );
  }
  let event: Stripe.Event;
  try {
    // Async, not the sync `constructEvent`. The sync path only exists on the
    // Node crypto provider; the worker/edge build the SDK ships for every
    // other runtime (including Bun, which runs this repo's tests) throws
    // "use constructEventAsync" instead of verifying. Awaiting works on both,
    // so the route stays runtime-agnostic and the signature path is testable.
    event = await getStripe().webhooks.constructEventAsync(
      payload,
      signature,
      secret,
    );
  } catch (err) {
    console.error("[contribute] webhook signature failed", err);
    return NextResponse.json(
      { ok: false, error: "Invalid signature." },
      { status: 400 },
    );
  }

  // Answer 200 either way: a retry that gets an error only comes back again.
  if (alreadyHandled(event.id)) {
    return NextResponse.json({ ok: true, received: true, duplicate: true });
  }

  if (event.type === "checkout.session.completed") {
    const session = event.data.object;
    const sku =
      session.metadata?.sku ??
      (typeof session.amount_total === "number"
        ? `${session.amount_total}`
        : "unknown");
    const email = session.customer_details?.email ?? "unknown";
    const mode = session.mode ?? "payment";
    await notifyContribution({ sku, email, mode, id: session.id });
  }

  return NextResponse.json({ ok: true, received: true });
}

async function notifyContribution(details: {
  sku: string;
  email: string;
  mode: string;
  id: string;
}) {
  // Stripe retries a webhook that does not answer 200, so a mail outage must
  // not fail the handler: sendMail logs and reports instead of throwing.
  const result = await sendMail({
    // Recipient comes from MAIL_NOTIFY_TO via lib/mail.ts — see notifyTo().
    subject: `Contribution: ${details.sku}`,
    text: [
      "A Voteaxis contribution checkout completed.",
      `SKU: ${details.sku}`,
      `Mode: ${details.mode}`,
      `Email: ${details.email}`,
      `Session: ${details.id}`,
    ].join("\n"),
  });

  if (!result.sent && result.reason === "send_failed") {
    console.error("[contribute] notification not sent for session", details.id);
  }
}
