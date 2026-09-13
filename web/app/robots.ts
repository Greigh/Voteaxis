import type { MetadataRoute } from "next";
import { absoluteUrl } from "@/lib/site";

/**
 * Crawler policy.
 *
 * A crawler obeys exactly ONE group — the most specific User-agent match — and
 * ignores every other, `*` included. So each named group below has to restate
 * the /api/ block; it does not inherit it.
 *
 * The split is deliberate: bots that answer a user's question and cite the
 * source send traffic back, so they get the site. Bots that exist to bulk-copy
 * text into a training set give nothing back, so they do not.
 *
 * Link-preview fetchers (facebookexternalhit, Twitterbot, LinkedInBot,
 * Slackbot, Discordbot) are intentionally unnamed — they fall through to `*`
 * and keep working. Naming them here to "block AI" would kill OG cards.
 */

/**
 * Never crawled. /result/<id> is one person's placement behind a link they can
 * revoke — the page also sends `noindex`, but a Disallow keeps it out of the
 * crawl queue in the first place.
 */
const NO_API = ["/api/", "/result/"];

/**
 * Answer engines and AI search indexes: they attribute and link out.
 * Google-Extended is dual-purpose — it gates both Gemini grounding AND Gemini
 * training, with no way to separate them. Allowed because being absent from
 * Gemini/AI Overviews costs more reach than the training use costs us.
 */
const AI_SEARCH_AGENTS = [
  "OAI-SearchBot",
  "ChatGPT-User",
  "Claude-SearchBot",
  "Claude-User",
  "PerplexityBot",
  "Perplexity-User",
  "DuckAssistBot",
  "MistralAI-User",
  "Amazonbot",
  "Google-Extended",
];

/** Bulk training scrapers and dataset builders: no citation, no referral. */
const AI_TRAINING_AGENTS = [
  "GPTBot",
  "ClaudeBot",
  "anthropic-ai",
  "CCBot",
  "Bytespider",
  "TikTokSpider",
  "Meta-ExternalAgent",
  "Applebot-Extended",
  "cohere-ai",
  "cohere-training-data-crawler",
  "Diffbot",
  "omgili",
  "omgilibot",
  "Timpibot",
  "Webzio-Extended",
  "ImagesiftBot",
  "AI2Bot",
  "PanguBot",
];

export default function robots(): MetadataRoute.Robots {
  return {
    rules: [
      { userAgent: "*", allow: "/", disallow: NO_API },
      { userAgent: AI_SEARCH_AGENTS, allow: "/", disallow: NO_API },
      { userAgent: AI_TRAINING_AGENTS, disallow: "/" },
    ],
    sitemap: absoluteUrl("/sitemap.xml"),
    host: absoluteUrl("/"),
  };
}
