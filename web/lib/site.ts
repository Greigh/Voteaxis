/**
 * One source of truth for the facts that page metadata, JSON-LD, robots,
 * sitemap, and /llms.txt all have to agree on.
 *
 * Crawlers and answer engines quote these back at users verbatim, so a claim
 * that drifts between the OG description and the structured data reads as an
 * inconsistency about the product. Edit it here, once.
 */

export const SITE_NAME = "Voteaxis";
export const SITE_TAGLINE = "See where you stand. Choose who to vote for.";

export const SITE_DESCRIPTION =
  "A short quiz places you on Liberal 100 ← 0 → Conservative 100, then ranks ballot candidates by how close they are to your issues.";

export const SITE_DESCRIPTION_SHORT =
  "Take a short quiz. Land on the spectrum. Match ballot candidates to your issues.";

export const ORG_NAME = "The Greigh Studios LLC";
export const ORG_URL = "https://greighstudios.com";
/** Public contact address. An alias into daniel@voteaxis.org on the VPS —
 * see mail-server-logins.md. Structured data, llms.txt, and the pages that
 * print an address all read this. */
export const CONTACT_EMAIL = "hello@voteaxis.org";

/** Twitter card attribution — handle form, including the leading @. */
export const SOCIAL_HANDLE = "@greighstudios";

export const SCORING_METHOD = "Spectrum Issue Index";
export const SCORING_VERSION = "v1";

/** Mirrors mobile/assets/data/pillars.json. */
export const PILLAR_LABELS = [
  "Economy & fiscal",
  "Rights & society",
  "Health & entitlements",
  "Justice & homeland",
  "Climate, energy & world",
] as const;

/**
 * The generated card from app/opengraph-image.tsx.
 *
 * Next only auto-attaches the file-convention image to segments that do not
 * declare their own `openGraph` object — declaring one REPLACES the inherited
 * value wholesale, images included. So every page that sets `openGraph` has to
 * name this, or it ships a link preview with no image at all.
 */
export const OG_IMAGE = {
  url: "/opengraph-image",
  width: 1200,
  height: 630,
  alt: `${SITE_NAME} — ${SITE_TAGLINE}`,
} as const;

/**
 * Read at module scope in server components. NEXT_PUBLIC_* is inlined by
 * `next build`, so changing it needs a rebuild, not just a restart.
 */
export function siteUrl(): string {
  return process.env.NEXT_PUBLIC_SITE_URL ?? "https://voteaxis.org";
}

/**
 * The Voteaxis API root. Shared result pages read `/v1/results/<id>` from it.
 * Separate host from the site, so it needs its own variable.
 */
export function apiUrl(): string {
  return (
    process.env.NEXT_PUBLIC_API_URL ?? "https://api.voteaxis.org"
  ).replace(/\/$/, "");
}

/** Absolute URL for a site-root-relative path, e.g. "/methodology". */
export function absoluteUrl(path = "/"): string {
  const base = siteUrl().replace(/\/$/, "");
  if (!path || path === "/") {
    return base;
  }
  return `${base}${path.startsWith("/") ? path : `/${path}`}`;
}
