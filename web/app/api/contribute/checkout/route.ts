import { NextResponse } from "next/server";
import { isContributeSku, offerForSku, siteUrl } from "@/lib/contribute";
import { clientIp, createRateLimiter } from "@/lib/rate-limit";
import { getStripe, isStripeConfigured } from "@/lib/stripe";

// Every call creates a real Checkout Session against the live key. Looser than
// the waitlist — changing your mind about an amount is normal — but not
// unbounded.
const allow = createRateLimiter(10, 10 * 60 * 1000);

export async function POST(request: Request) {
  if (!allow(clientIp(request))) {
    return NextResponse.json(
      { ok: false, error: "Too many attempts. Try again in a few minutes." },
      { status: 429, headers: { "retry-after": "600" } },
    );
  }

  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return NextResponse.json(
      { ok: false, error: "Invalid request." },
      { status: 400 },
    );
  }

  const rawSku =
    typeof body === "object" && body !== null && "sku" in body
      ? (body as { sku: unknown }).sku
      : null;
  const sku = isContributeSku(rawSku) ? rawSku : null;

  if (!sku) {
    return NextResponse.json(
      { ok: false, error: "Choose an amount." },
      { status: 400 },
    );
  }

  if (!isStripeConfigured()) {
    return NextResponse.json(
      {
        ok: false,
        error:
          "Checkout isn’t live yet. Email hello@voteaxis.org if you want to help fund Voteaxis.",
      },
      { status: 503 },
    );
  }

  const offer = offerForSku(sku);
  const origin = siteUrl();
  const productName =
    offer.mode === "subscription"
      ? "Voteaxis Sustainer"
      : "Contribute to Voteaxis";
  const productDescription =
    "Contribution to independent Spectrum Issue Index scoring and state-level data. Does not unlock app features.";

  try {
    const session = await getStripe().checkout.sessions.create({
      mode: offer.mode,
      ...(offer.mode === "payment" ? { submit_type: "donate" as const } : {}),
      billing_address_collection: "auto",
      line_items: [
        {
          quantity: 1,
          price_data: {
            currency: "usd",
            unit_amount: offer.amountCents,
            product_data: {
              name: productName,
              description: productDescription,
            },
            ...(offer.mode === "subscription" && offer.interval
              ? { recurring: { interval: offer.interval } }
              : {}),
          },
        },
      ],
      metadata: {
        sku: offer.sku,
        product: "voteaxis-contribution",
      },
      success_url: `${origin}/contribute/thanks?session_id={CHECKOUT_SESSION_ID}`,
      cancel_url: `${origin}/contribute`,
    });

    if (!session.url) {
      return NextResponse.json(
        { ok: false, error: "Could not start checkout." },
        { status: 502 },
      );
    }

    return NextResponse.json({ ok: true, url: session.url });
  } catch (err) {
    console.error("[contribute] checkout failed", err);
    return NextResponse.json(
      { ok: false, error: "Could not start checkout. Try again." },
      { status: 502 },
    );
  }
}
