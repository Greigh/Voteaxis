import Stripe from "stripe";

let client: Stripe | null = null;

export function stripeSecretKey() {
  return process.env.STRIPE_SECRET_KEY?.trim() ?? "";
}

export function isStripeConfigured() {
  return stripeSecretKey().length > 0;
}

/** Lazy so Next.js build/import does not require STRIPE_SECRET_KEY. */
export function getStripe(): Stripe {
  const key = stripeSecretKey();
  if (!key) {
    throw new Error("STRIPE_SECRET_KEY is not set.");
  }
  if (!client) {
    client = new Stripe(key);
  }
  return client;
}
