/**
 * Per-IP fixed-window limiter for the site's two unauthenticated POST routes.
 *
 * The Bun API has had one of these since it shipped; the Next side had none,
 * which left /api/waitlist as a free amplifier — every call sends mail through
 * the box's own Postfix, POSTs the optional webhook, and appends to the JSONL.
 * Anyone could point a loop at it and burn the sending reputation OpenDKIM is
 * there to protect.
 *
 * In-process and therefore per-worker: ecosystem.config.cjs runs `instances: 1`
 * (the JSONL is append-only from one writer), so there is exactly one map. It
 * resets on redeploy, which is the accepted tradeoff for having no Redis on the
 * box — this is a courtesy control against floods and accidents, not the
 * security boundary. Cloudflare sits in front for anything larger.
 */

type Bucket = { count: number; reset: number };

/** Sweep at most this often: the full expiry pass is O(buckets), so not per request. */
const SWEEP_INTERVAL_MS = 60 * 1000;
/** Ceiling on tracked buckets so a flood of distinct IPs cannot grow the map
 * until PM2's max_memory_restart takes the process down. */
export const MAX_BUCKETS = 50_000;

export type RateLimiter = (key: string) => boolean;

export function createRateLimiter(max: number, windowMs: number): RateLimiter {
  const hits = new Map<string, Bucket>();
  let nextSweep = 0;

  function sweep(now: number): void {
    const due = now >= nextSweep;
    // Common path: not time for a full sweep and the map is within bounds.
    if (!due && hits.size <= MAX_BUCKETS) return;
    if (due) {
      nextSweep = now + SWEEP_INTERVAL_MS;
      for (const [key, bucket] of hits) {
        if (bucket.reset <= now) hits.delete(key);
      }
    }
    // Trim any overflow whether or not a full sweep ran. Between scheduled
    // sweeps this is the only pass that walks the map, and each allow() call
    // adds at most one bucket — so it stays O(overflow), never O(buckets),
    // even under a flood of distinct IPs. Oldest-first for one shared window.
    if (hits.size > MAX_BUCKETS) {
      for (const key of hits.keys()) {
        if (hits.size <= MAX_BUCKETS) break;
        hits.delete(key);
      }
    }
  }

  /** True when the call is allowed. */
  return function allow(key: string): boolean {
    const now = Date.now();
    sweep(now);
    const bucket = hits.get(key);
    if (!bucket || bucket.reset <= now) {
      hits.set(key, { count: 1, reset: now + windowMs });
      return true;
    }
    if (bucket.count >= max) return false;
    bucket.count += 1;
    return true;
  };
}

function isProxyIp(value: string): boolean {
  return value.length > 0 && value.length <= 64 && !/[\s,]/.test(value);
}

/**
 * Client IP as the edge proxy reports it.
 *
 * nginx sets X-Real-IP from $remote_addr on every proxied location (see
 * deploy/nginx.voteaxis.org.example), and the cloudflare-real-ip snippet
 * rewrites $remote_addr to the true client first. Client-supplied
 * X-Forwarded-For is deliberately ignored: it is appended to, not overwritten,
 * so a caller can prepend anything they like and mint a fresh bucket per
 * request. Same rule the API applies in server/src/app.ts.
 */
export function clientIp(req: Request): string {
  const realIp = req.headers.get("x-real-ip")?.trim();
  if (realIp && isProxyIp(realIp)) return realIp;
  const cf = req.headers.get("cf-connecting-ip")?.trim();
  if (cf && isProxyIp(cf)) return cf;
  return "local";
}
