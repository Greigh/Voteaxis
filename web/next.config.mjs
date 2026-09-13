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
const STATIC_PAGES = ["/", "/methodology"];

const nextConfig = {
  reactStrictMode: true,
  // Keep Turbopack rooted in this package (avoids parent lockfile warnings).
  turbopack: {
    root: process.cwd(),
  },
  async headers() {
    return STATIC_PAGES.map((source) => ({
      source,
      headers: [{ key: "Cache-Control", value: HTML_CACHE_CONTROL }],
    }));
  },
  // /support read as a help desk, so the page is /contribute. Permanent so any
  // indexed or already-shared /support link folds into the new route.
  async redirects() {
    return [
      {
        source: "/support",
        destination: "/contribute",
        permanent: true,
      },
      {
        source: "/support/thanks",
        destination: "/contribute/thanks",
        permanent: true,
      },
    ];
  },
};

export default nextConfig;
