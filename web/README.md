# Voteaxis — web

Next.js marketing site for **Voteaxis** (The Greigh Studios LLC).

This package is **not** the quiz. The quiz ships only in the Flutter iOS/Android app ([`../mobile`](../mobile)). This site sells the product, previews the spectrum, explains methodology, collects launch waitlist emails, and hosts contribution checkout.

## What’s here

- Brand landing with animated, draggable liberal↔conservative preview  
- [`/methodology`](app/methodology) — Spectrum Issue Index (SII) v1 in plain language  
- [`/contribute`](app/contribute) — voluntary $5 / $15 / $30 and $25/year Sustainer via Stripe Checkout (nothing unlocks)  
- Waitlist form → `data/waitlist.jsonl` (+ optional SMTP mail / webhook), including teacher / newsroom checkboxes  
- SEO + AI discovery — see [SEO and AI crawlers](#seo-and-ai-crawlers)

## Stack

- Next.js (App Router) + React  
- Bun for install / scripts  
- GSAP for motion  
- Biome for lint/format  

## Develop

From the monorepo root:

```bash
bun run dev
```

Or in this folder:

```bash
bun install
bun run dev
```

→ [http://localhost:3000](http://localhost:3000)

```bash
bun run build
bun run lint
bun run waitlist:list
```

## Deploy

Self-hosted on the VPS under PM2 (`voteaxis-web`), bound to `127.0.0.1:3020`
behind Caddy — see [`../DEPLOY.md`](../DEPLOY.md).

```bash
cp .env.example .env.production.local   # set NEXT_PUBLIC_SITE_URL first
bun install && bun run build
BUN_BIN=$(command -v bun) pm2 start ecosystem.config.cjs
```

`NEXT_PUBLIC_SITE_URL` is inlined at build time, so it must be set **before**
`bun run build`. The rest of the table below is read per request — edit and
`pm2 restart voteaxis-web`.

## Waitlist

Signups append to `data/waitlist.jsonl` (gitignored).

Optional env (see `.env.example`):

| Variable | Purpose |
|----------|---------|
| `SMTP_HOST` | SMTP relay for notifications (`localhost` on the VPS; unset = no mail) |
| `MAIL_FROM` | Sender identity, must be DKIM-signed (default `Voteaxis <no-reply@voteaxis.org>`) |
| `MAIL_NOTIFY_TO` | Recipient (default `hello@greighstudios.com`) |
| `WAITLIST_WEBHOOK_URL` | Zapier / Make / n8n POST |
| `NEXT_PUBLIC_SITE_URL` | Canonical URL for metadata |
| `STRIPE_SECRET_KEY` | Stripe Checkout for `/contribute` |
| `STRIPE_WEBHOOK_SECRET` | Verifies `checkout.session.completed` |

Cycle Pass, accounts, and StoreKit are **not** in this package yet. Contributing is voluntary, not a paywall.

## SEO and AI crawlers

Every product fact a crawler can quote lives in [`lib/site.ts`](lib/site.ts). Metadata, JSON-LD, and `/llms.txt` all read from it, so an edit there updates all three at once.

| Route | Source | Purpose |
|-------|--------|---------|
| `/robots.txt` | [`app/robots.ts`](app/robots.ts) | Crawler policy, including the AI split below |
| `/sitemap.xml` | [`app/sitemap.ts`](app/sitemap.ts) | Indexable routes only (`/contribute/thanks` is noindex) |
| `/llms.txt` | [`app/llms.txt/route.ts`](app/llms.txt/route.ts) | Plain-text product brief for models, in our own words |
| `/manifest.webmanifest` | [`app/manifest.ts`](app/manifest.ts) | Install metadata + maskable icons |
| `/opengraph-image` | [`app/opengraph-image.tsx`](app/opengraph-image.tsx) | Generated 1200×630 link-preview card |

**AI crawler policy.** Answer engines that cite and link out (`OAI-SearchBot`, `PerplexityBot`, `Claude-SearchBot`, `Google-Extended`, …) are allowed. Bulk training scrapers that give nothing back (`GPTBot`, `ClaudeBot`, `CCBot`, `Bytespider`, …) are blocked. Two traps the tests in [`test/metadata.test.ts`](test/metadata.test.ts) guard against:

- A crawler obeys exactly **one** `User-agent` group — the most specific match — and ignores `*` entirely. Every named group therefore has to restate `Disallow: /api/`; it is not inherited.
- Link-preview fetchers (`facebookexternalhit`, `Twitterbot`, `Slackbot`, …) are deliberately **unnamed** so they fall through to `*`. Naming them to "block AI" would kill OG cards.

**Structured data.** [`lib/structured-data.ts`](lib/structured-data.ts) builds the schema.org graph: `Organization` + `WebSite` + `MobileApplication` site-wide, `TechArticle` on `/methodology`, `WebPage` + `BreadcrumbList` on subpages. It deliberately omits `aggregateRating`, `offers`, and `downloadUrl` — the app has not shipped, so there is nothing honest to put there. Add them at launch.

**Adding a page.** Setting `openGraph` on a page *replaces* the inherited root object instead of merging, which silently drops the link-preview image. Spread `OG_IMAGE` from `lib/site.ts` into both `openGraph.images` and `twitter.images`, and add the route to `app/sitemap.ts`.

Optional env: `GOOGLE_SITE_VERIFICATION` / `BING_SITE_VERIFICATION` (token only, not the full meta tag).

## Related

- Monorepo overview: [`../README.md`](../README.md)  
- Flutter app: [`../mobile/README.md`](../mobile/README.md)
