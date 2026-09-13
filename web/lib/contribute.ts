/**
 * Year-1 monetization: voluntary contributions only. Nothing unlocks.
 *
 * Deferred until contribution data shows we need a paid depth tier:
 * - Cycle Pass / Voteaxis Pro
 * - user accounts
 * - StoreKit / Play Billing IAP tips for non-US storefronts
 * - classroom dashboard, era packs, ads
 */
export const CONTRIBUTE_SKUS = [
  "tip_5",
  "tip_15",
  "tip_30",
  "sustainer_year",
] as const;

export type ContributeSku = (typeof CONTRIBUTE_SKUS)[number];

export type ContributeOffer = {
  sku: ContributeSku;
  amountCents: number;
  label: string;
  blurb: string;
  mode: "payment" | "subscription";
  interval?: "year";
};

export const CONTRIBUTE_OFFERS: readonly ContributeOffer[] = [
  {
    sku: "tip_5",
    amountCents: 500,
    label: "$5",
    blurb: "Covers a slice of hosting",
    mode: "payment",
  },
  {
    sku: "tip_15",
    amountCents: 1500,
    label: "$15",
    blurb: "Typical one-time contribution",
    mode: "payment",
  },
  {
    sku: "tip_30",
    amountCents: 3000,
    label: "$30",
    blurb: "Keeps state data current",
    mode: "payment",
  },
  {
    sku: "sustainer_year",
    amountCents: 2500,
    label: "$25 / year",
    blurb: "Optional Sustainer — cancel anytime",
    mode: "subscription",
    interval: "year",
  },
] as const;

export const DEFAULT_CONTRIBUTE_SKU: ContributeSku = "tip_15";

export function isContributeSku(value: unknown): value is ContributeSku {
  return (
    typeof value === "string" &&
    (CONTRIBUTE_SKUS as readonly string[]).includes(value)
  );
}

export function offerForSku(sku: ContributeSku): ContributeOffer {
  const offer = CONTRIBUTE_OFFERS.find((row) => row.sku === sku);
  if (!offer) {
    throw new Error(`Unknown contribute sku: ${sku}`);
  }
  return offer;
}

export { siteUrl } from "./site";
