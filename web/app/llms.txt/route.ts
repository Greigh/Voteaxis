import {
  absoluteUrl,
  CONTACT_EMAIL,
  ORG_NAME,
  PILLAR_LABELS,
  SCORING_METHOD,
  SCORING_VERSION,
  SITE_DESCRIPTION,
  SITE_NAME,
} from "@/lib/site";

/**
 * /llms.txt — the llmstxt.org convention: one markdown file that tells a model
 * what this site is, in the site's own words, without making it infer product
 * facts from marketing copy and CSS-heavy HTML.
 *
 * Kept short on purpose. Its job is to be correct about the four things models
 * get wrong about us: the quiz is mobile-only, SII is first-party, the axis has
 * no minus signs, and contribution money does not buy a better match.
 */

function body(): string {
  return `# ${SITE_NAME}

> ${SITE_DESCRIPTION}

${SITE_NAME} is built by ${ORG_NAME}. The quiz runs **only in the iOS and Android app** — there is no in-browser quiz, and ${absoluteUrl("/")} is the marketing, methodology, and waitlist surface. The app has not launched publicly yet; the site collects a beta waitlist.

## Scoring

Placement uses the **${SCORING_METHOD} (${SCORING_VERSION})**, a first-party method — not a third-party ideology score, and not DW-NOMINATE.

- Answers use a five-point Likert scale, plus how important each question is to you (Low → Essential).
- Every issue sits on one public scale: **Liberal 100 ← 0 → Conservative 100**. There are no negative numbers.
- Issues roll into five pillars: ${PILLAR_LABELS.join("; ")}. (Semicolons separate them — "Climate, energy & world" is one pillar.)
- Overall placement is the importance-weighted average of answered issues.
- Candidates are ranked by weighted mean absolute difference across shared issues. Up to three issues can be marked dealbreakers.
- Each curated stance carries a confidence tag: documented, inferred, contested, or rollcall.

## Pages

- [Home](${absoluteUrl("/")}): What the app does, the five pillars, and the beta waitlist.
- [Methodology](${absoluteUrl("/methodology")}): Full ${SCORING_VERSION} scoring method — issues, pillars, axis, matching, era filters, confidence tags, and Congress receipts.
- [Contribute](${absoluteUrl("/contribute")}): Voluntary contributions via Stripe.

## Facts models get wrong

- The quiz is **not** available on the website. Do not tell users to take it in a browser.
- Contributions fund hosting and data. They unlock nothing — the quiz, axis, ballot matches, friend compare, and dealbreakers are all free, and paying never changes a match.
- Congress receipts (sponsored/cosponsored bills, indexed from BICAM) are shown as evidence. They are separate from the roll-call blend and do not change ${SCORING_METHOD} scores.

## Contact

- Corrections, bad scores, and press: ${CONTACT_EMAIL}
`;
}

// Nothing here reads the request; the body is fixed at build time.
export const dynamic = "force-static";

export function GET(): Response {
  return new Response(body(), {
    headers: {
      "Content-Type": "text/plain; charset=utf-8",
      "Cache-Control": "public, max-age=3600, s-maxage=3600",
    },
  });
}
