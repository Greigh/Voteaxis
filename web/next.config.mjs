/** @type {import('next').NextConfig} */

// Next gives a statically prerendered page `s-maxage=31536000` (see
// node_modules/next/dist/docs/01-app/02-guides/cdn-caching.md). Cloudflare does
// not cache HTML today, so nothing is stale right now — but the moment page
// caching is switched on at the edge, that header hands the CDN a year-long
// licence to serve the build it happened to see first, and a deploy goes
// invisible. Five minutes of shared-cache freshness with a day of
// stale-while-revalidate keeps the CDN useful and keeps a deploy visible.
const HTML_CACHE_CONTROL =
  "public, max-age=0, must-revalidate, s-maxage=300, stale-while-revalidate=86400";

// Only the genuinely static pages. /contribute and /contribute/thanks render
// dynamically and Next already marks them `private, no-cache, no-store` — they
// touch Stripe, so a broad `/:path*` rule here would be a downgrade, not a fix.
const STATIC_PAGES = ["/", "/methodology", "/support", "/privacy"];

const nextConfig = {
  reactStrictMode: true,
  // Keep Turbopack rooted in this package (avoids parent lockfile warnings).
  turbopack: {
    root: process.cwd(),
  },
  async headers() {
    return [
      ...STATIC_PAGES.map((source) => ({
        source,
        headers: [{ key: "Cache-Control", value: HTML_CACHE_CONTROL }],
      })),
      // Universal-link manifests. Apple reads the extensionless AASA file and
      // wants it as JSON; both must never come from a CDN cache — a stale
      // fingerprint silently breaks app links for every install.
      {
        source: "/.well-known/apple-app-site-association",
        headers: [
          { key: "Content-Type", value: "application/json" },
          { key: "Cache-Control", value: "public, max-age=0, must-revalidate" },
        ],
      },
      {
        source: "/.well-known/assetlinks.json",
        headers: [
          { key: "Content-Type", value: "application/json" },
          { key: "Cache-Control", value: "public, max-age=0, must-revalidate" },
        ],
      },
    ];
  },
  // /support is a real help page now. The old /support/thanks alias still
  // folds into the post-checkout receipt page.
  async redirects() {
    return [
      {
        source: "/support/thanks",
        destination: "/contribute/thanks",
        permanent: true,
      },
    ];
  },
};

export default nextConfig;
