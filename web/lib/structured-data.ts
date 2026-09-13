/**
 * schema.org JSON-LD for search engines and AI answer engines.
 *
 * Rules this file holds itself to, because both Google and the answer engines
 * treat a mismatch as a trust signal against the site:
 *
 * - Every claim here is also visible in the page copy. No invisible facts.
 * - No aggregateRating, no offers, no downloadUrl for the app — it has not
 *   shipped, so there is nothing honest to put there yet. Add them at launch.
 * - Entities carry stable @ids so pages can reference the org and site rather
 *   than restating them.
 */

import {
  absoluteUrl,
  CONTACT_EMAIL,
  ORG_NAME,
  ORG_URL,
  PILLAR_LABELS,
  SCORING_METHOD,
  SCORING_VERSION,
  SITE_DESCRIPTION,
  SITE_NAME,
  SITE_TAGLINE,
} from "./site";

type JsonLdNode = Record<string, unknown>;

export const ORGANIZATION_ID = () => `${absoluteUrl("/")}/#organization`;
export const WEBSITE_ID = () => `${absoluteUrl("/")}/#website`;
export const APP_ID = () => `${absoluteUrl("/")}/#app`;

function organization(): JsonLdNode {
  return {
    "@type": "Organization",
    "@id": ORGANIZATION_ID(),
    name: ORG_NAME,
    url: ORG_URL,
    email: CONTACT_EMAIL,
    logo: {
      "@type": "ImageObject",
      url: absoluteUrl("/brand/voteaxis-mark.png"),
      width: 1024,
      height: 1024,
    },
    contactPoint: {
      "@type": "ContactPoint",
      email: CONTACT_EMAIL,
      contactType: "customer support",
      availableLanguage: "en",
    },
  };
}

function website(): JsonLdNode {
  return {
    "@type": "WebSite",
    "@id": WEBSITE_ID(),
    name: SITE_NAME,
    alternateName: `${SITE_NAME} — ${SITE_TAGLINE}`,
    url: absoluteUrl("/"),
    description: SITE_DESCRIPTION,
    inLanguage: "en-US",
    publisher: { "@id": ORGANIZATION_ID() },
  };
}

function application(): JsonLdNode {
  return {
    "@type": "MobileApplication",
    "@id": APP_ID(),
    name: SITE_NAME,
    url: absoluteUrl("/"),
    description: SITE_DESCRIPTION,
    applicationCategory: "ReferenceApplication",
    operatingSystem: "iOS, Android",
    inLanguage: "en-US",
    isAccessibleForFree: true,
    publisher: { "@id": ORGANIZATION_ID() },
    author: { "@id": ORGANIZATION_ID() },
    featureList: [
      "Roughly three-minute issue quiz with per-question importance",
      `Placement on one Liberal 100 ← 0 → Conservative 100 axis via the ${SCORING_METHOD} ${SCORING_VERSION}`,
      "Ballot candidates ranked by weighted issue overlap",
      "Up to three dealbreaker issues that flag hard clashes",
      "Historical figure matches and polar opposite",
      "Friend compare by six-digit code",
      "Issue of the Day home- and lock-screen widget",
    ],
  };
}

/** Org + site + app. Rendered once from the root layout. */
export function siteGraph(): JsonLdNode {
  return {
    "@context": "https://schema.org",
    "@graph": [organization(), website(), application()],
  };
}

/**
 * Breadcrumbs for a non-home page. `trail` excludes home, which is prepended.
 */
export function breadcrumbs(
  trail: readonly { name: string; path: string }[],
): JsonLdNode {
  const items = [{ name: "Home", path: "/" }, ...trail];
  return {
    "@context": "https://schema.org",
    "@type": "BreadcrumbList",
    itemListElement: items.map((item, index) => ({
      "@type": "ListItem",
      position: index + 1,
      name: item.name,
      item: absoluteUrl(item.path),
    })),
  };
}

/** The methodology page — the document AI engines should cite for scoring. */
export function methodologyGraph(sectionTitles: readonly string[]): JsonLdNode {
  return {
    "@context": "https://schema.org",
    "@type": "TechArticle",
    "@id": `${absoluteUrl("/methodology")}#article`,
    headline: "How we score your views",
    name: `${SCORING_METHOD} (${SCORING_VERSION}) methodology`,
    description: `How ${SITE_NAME} scores views with the ${SCORING_METHOD} (${SCORING_VERSION}) — issues, five pillars, one Liberal ↔ Conservative axis, and candidate matching.`,
    url: absoluteUrl("/methodology"),
    inLanguage: "en-US",
    isPartOf: { "@id": WEBSITE_ID() },
    about: {
      "@type": "DefinedTerm",
      name: SCORING_METHOD,
      alternateName: "SII",
      termCode: `SII ${SCORING_VERSION}`,
      description:
        "A first-party issue-scoring method placing answers and political figures on a shared Liberal 100 ← 0 → Conservative 100 scale. Not a third-party ideology score.",
      inDefinedTermSet: {
        "@type": "DefinedTermSet",
        name: `${SCORING_METHOD} pillars`,
        hasDefinedTerm: PILLAR_LABELS.map((label) => ({
          "@type": "DefinedTerm",
          name: label,
        })),
      },
    },
    articleSection: [...sectionTitles],
    publisher: { "@id": ORGANIZATION_ID() },
    author: { "@id": ORGANIZATION_ID() },
  };
}

/** A plain page node that ties a route back to the site and org. */
export function pageGraph(input: {
  name: string;
  description: string;
  path: string;
}): JsonLdNode {
  return {
    "@context": "https://schema.org",
    "@type": "WebPage",
    "@id": `${absoluteUrl(input.path)}#webpage`,
    name: input.name,
    description: input.description,
    url: absoluteUrl(input.path),
    inLanguage: "en-US",
    isPartOf: { "@id": WEBSITE_ID() },
    about: { "@id": APP_ID() },
    publisher: { "@id": ORGANIZATION_ID() },
  };
}

/**
 * Serialize for a <script type="application/ld+json">. Escaping `<` closes the
 * XSS hole `JSON.stringify` leaves open when a value ever carries markup.
 */
export function serializeJsonLd(node: JsonLdNode): string {
  return JSON.stringify(node).replace(/</g, "\\u003c");
}
