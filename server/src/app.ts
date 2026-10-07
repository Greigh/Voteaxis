import { createPublicKey, timingSafeEqual, verify as verifySignature } from "node:crypto";
import { readFileSync, statSync } from "node:fs";
import { join } from "node:path";
import { normalizeCode, normalizeToken } from "./codes";
import { BIOGUIDE, BILL_TYPE, type BicamApi } from "./congress";
import type { CongressGovEnricher } from "./congress-gov";
import {
  normalizeResultId,
  parseEnvelope,
  parseResultPayload,
} from "./results";
import { Store } from "./store";
import { parsePayload } from "./validate";

const jsonHeaders = {
  "content-type": "application/json; charset=utf-8",
  "cache-control": "no-store",
};

function json(req: Request, status: number, body: unknown): Response {
  const payload = JSON.stringify(body);
  return new Response(
    // A HEAD response carries the headers of the GET and none of the body.
    // Content-Length still describes what a GET would have returned.
    req.method === "HEAD" ? null : payload,
    {
      status,
      headers: {
        ...jsonHeaders,
        "content-length": String(Buffer.byteLength(payload)),
      },
    },
  );
}

/**
 * Ids in the roster are lowercase snake_case (`john_moolenaar`), never empty,
 * never long enough to be an abuse vector against the byId map's key space.
 */
const POLITICIAN_ID = /^[a-z][a-z0-9_]{0,79}$/;

/**
 * Constant-time key compare, same reasoning as `tokensMatch` in store.ts:
 * never a practical timing target at these lengths, but free to close the
 * question. Length is checked first because `timingSafeEqual` throws on a
 * mismatch rather than returning false.
 */
function keysMatch(configured: string, given: string): boolean {
  if (configured.length !== given.length) return false;
  return timingSafeEqual(Buffer.from(configured), Buffer.from(given));
}

/** A device's raw 32-byte Ed25519 public key, lowercase hex. */
const DEVICE_PUBLIC_KEY_HEX = /^[0-9a-f]{64}$/;
/** A deviceId minted by randomToken() — same shape as the friend-code/result tokens. */
const DEVICE_ID_HEX = /^[0-9a-f]{48}$/;
/** A per-request nonce: 8–32 bytes hex, generated client-side. */
const DEVICE_NONCE_HEX = /^[0-9a-f]{16,64}$/;
/** A raw 64-byte Ed25519 signature, lowercase hex. */
const DEVICE_SIGNATURE_HEX = /^[0-9a-f]{128}$/;

/**
 * How far a signed request's own timestamp may drift from the server's clock
 * before it's refused. Bounds how long a captured request stays replayable
 * even before `nonceIsFresh` catches the exact repeat, and how much clock
 * skew a real device gets away with. Five minutes is generous for skew,
 * tight for an attacker.
 */
const DEVICE_SIGNATURE_WINDOW_MS = 5 * 60 * 1000;

/**
 * Verifies a signed `/v1/politicians*` request against the public key on file
 * for its deviceId. The signed message binds the method and path too, so a
 * signature captured off one route can't be replayed against another.
 *
 * Returns false — never throws — for anything malformed: an invalid-length
 * hex string handed to `createPublicKey`/`verify` throws inside Node's
 * crypto bindings, and "not a valid signature" is exactly the verdict a
 * malformed one should get here.
 */
function verifyDeviceSignature(
  publicKeyHex: string,
  message: string,
  signatureHex: string,
): boolean {
  try {
    const publicKey = createPublicKey({
      key: { kty: "OKP", crv: "Ed25519", x: Buffer.from(publicKeyHex, "hex").toString("base64url") },
      format: "jwk",
    });
    return verifySignature(
      null,
      Buffer.from(message, "utf8"),
      publicKey,
      Buffer.from(signatureHex, "hex"),
    );
  } catch {
    return false;
  }
}

/**
 * `/v1/politicians` is public, unauthenticated, and changes only when someone
 * edits the roster and reruns sync_politicians.py — the opposite of the
 * friend-code/result routes' `no-store`. An ETag plus a short max-age lets a
 * repeat app launch skip re-downloading ~1.5 MB when nothing changed.
 */
function politiciansJson(
  req: Request,
  status: number,
  etag: string,
  body: unknown,
): Response {
  const payload = JSON.stringify(body);
  return new Response(req.method === "HEAD" ? null : payload, {
    status,
    headers: {
      "content-type": "application/json; charset=utf-8",
      "cache-control": "public, max-age=3600",
      etag,
      "content-length": String(Buffer.byteLength(payload)),
    },
  });
}

function notModified(req: Request, etag: string): Response {
  return new Response(null, {
    status: 304,
    headers: { "cache-control": "public, max-age=3600", etag },
  });
}

/**
 * Largest POST body this service will read.
 *
 * Both POST routes buffer the whole body before a single validator runs, and
 * `Bun.serve` defaults to a ceiling measured in hundreds of megabytes. nginx's
 * own default `client_max_body_size` covered this by accident; Caddy has no
 * equivalent default, so the guard belongs here where every deployment gets it.
 * A sealed envelope tops out around 8 KB of base64, so 64 KB is generous.
 */
const MAX_BODY_BYTES = 64 * 1024;

/**
 * Hard ceiling passed to `Bun.serve` (see index.ts). `tooLarge` below only sees
 * a declared Content-Length; a chunked body has none, and Bun's own default is
 * measured in hundreds of megabytes against a 256 MB `max_memory_restart`. The
 * reverse proxy caps the body too, but a deployment that skips that directive —
 * or a direct hit on the port — still needs this backstop. Generous next to an
 * ~8 KB envelope so a legitimate request is never the one it catches.
 */
export const MAX_REQUEST_BODY_BYTES = 512 * 1024;

/**
 * Rejects an oversized body before it is read. Content-Length can be absent or
 * a lie, so this is the cheap first pass — Bun still enforces MAX_REQUEST_BODY_BYTES
 * on a chunked body that never declares a length.
 */
function tooLarge(req: Request): boolean {
  const declared = Number(req.headers.get("content-length"));
  return Number.isFinite(declared) && declared > MAX_BODY_BYTES;
}

/**
 * decodeURIComponent throws a URIError on malformed escapes ("%", "%zz"), and
 * every route param below comes off the URL — so a fuzzed request like
 * GET /v1/codes/% would leave fetch() to answer 500 instead of the 400 the
 * id regexes were going to produce. Returning "" keeps the verdict the same:
 * no id pattern this file matches accepts an empty string.
 */
function safeDecode(raw: string): string {
  try {
    return decodeURIComponent(raw);
  } catch {
    return "";
  }
}

type Bucket = { count: number; reset: number };

function isProxyIp(value: string): boolean {
  return value.length > 0 && value.length <= 64 && !/[\s,]/.test(value);
}

/**
 * Every caller collapses into this one bucket when the proxy forgets to set a
 * header, which turns the limiter into a site-wide lockout with no error that
 * says so. Warn once rather than per request.
 */
let warnedAboutProxy = false;

/** Headers the edge proxy overwrites. Client-supplied X-Forwarded-For is ignored. */
export function clientIp(req: Request): string {
  const realIp = req.headers.get("x-real-ip")?.trim();
  if (realIp && isProxyIp(realIp)) return realIp;
  const cf = req.headers.get("cf-connecting-ip")?.trim();
  if (cf && isProxyIp(cf)) return cf;
  if (!warnedAboutProxy) {
    warnedAboutProxy = true;
    console.warn(
      "[voteaxis-api] no X-Real-IP or CF-Connecting-IP on an incoming request — " +
        "every caller now shares one rate-limit bucket. Check the proxy config " +
        "against deploy/nginx.voteaxis.org.example or deploy/Caddyfile.example.",
    );
  }
  return "local";
}

/** Tests, which assert the warning fires exactly once. */
export function resetProxyWarning(): void {
  warnedAboutProxy = false;
}

/** Sweep at most this often: the full expiry pass is O(buckets), so not per request. */
const SWEEP_INTERVAL_MS = 60 * 1000;
/** Hard ceiling on tracked buckets, so a flood of distinct IPs cannot grow the
 * map until `max_memory_restart` takes the process down. */
export const MAX_BUCKETS = 50_000;

/** Exposed for tests; the app creates exactly one via `createApp`. */
export function createRateLimiter() {
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
    // sweeps this is the only pass that walks the map, and each rateLimit()
    // call adds at most one bucket — so it stays O(overflow), never
    // O(buckets), even under a flood of distinct IPs. Evicts in insertion
    // order (oldest-first for equal windows); the evicted caller gets a fresh
    // allowance, but an unbounded map is the worse failure — the limiter is a
    // courtesy control, not the security boundary.
    if (hits.size > MAX_BUCKETS) {
      for (const key of hits.keys()) {
        if (hits.size <= MAX_BUCKETS) break;
        hits.delete(key);
      }
    }
  }

  return function rateLimit(ip: string, max: number, windowMs: number): boolean {
    const now = Date.now();
    sweep(now);
    const bucket = hits.get(ip);
    if (!bucket || bucket.reset <= now) {
      hits.set(ip, { count: 1, reset: now + windowMs });
      return true;
    }
    if (bucket.count >= max) return false;
    bucket.count += 1;
    return true;
  };
}

export type AppOptions = {
  store: Store;
  ttlMs: number;
  weekPath: string;
  /** Curated roster served by `/v1/politicians`. Defaults to `politiciansFile()`. */
  politiciansPath?: string;
  /**
   * Shared secret required as `x-voteaxis-key` on every `/v1/politicians*`
   * request. Unset (the default) means locked to nobody, not open to
   * everybody — a forgotten env var fails closed. Set `POLITICIANS_API_KEY`
   * to open it to whoever holds that key. Independent of, and compatible
   * with, `politiciansAllowDeviceTokens` below — a request needs only one of
   * the two credentials, not both.
   */
  politiciansApiKey?: string;
  /**
   * When true, a request signed by a registered per-install keypair also
   * authorizes `/v1/politicians*` — the mechanism meant to replace
   * `politiciansApiKey` for a general release, where a value baked into the
   * shipped app is not actually secret. A device registers its public key
   * once via `POST /v1/device-tokens`; the private key never leaves it, and
   * every request is signed fresh, so there is no static value to extract
   * from the binary or replay. Off by default: registration has no gate of
   * its own (there is no account to check it against), so turning this on is
   * a deliberate "the roster is public now, just behind a signature and a
   * clock" decision, not a default. See server/README.md.
   */
  politiciansAllowDeviceTokens?: boolean;
  rateLimitPosts?: number;
  bicam?: BicamApi;
  enricher?: CongressGovEnricher;
  /** How long a shared result page stays up. Defaults to 90 days. */
  resultTtlMs?: number;
  /** Where shared results are read. Defaults to the production site. */
  siteBase?: string;
  /**
   * How old `issue-of-the-week.json` may be before /v1/week stops serving it.
   * Defaults to 10 days — a week plus slack for a late rotation.
   */
  weekMaxAgeMs?: number;
  /** Injectable clock, so the staleness window is testable. */
  now?: () => number;
};

/**
 * True when a week prompt is too old to keep showing. The app labels this card
 * "ISSUE OF THE WEEK", so serving a month-old prompt is the endpoint lying
 * rather than the client misreading it — better to 404 and let the card go.
 */
export function weekIsStale(
  body: unknown,
  now: number,
  maxAgeMs: number,
): boolean {
  if (typeof body !== "object" || body === null) return true;
  const weekOf = (body as { weekOf?: unknown }).weekOf;
  if (typeof weekOf !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(weekOf)) {
    // Undated prompts have no way to expire, so they never get to be current.
    return true;
  }
  const stamped = Date.parse(`${weekOf}T00:00:00Z`);
  if (!Number.isFinite(stamped)) return true;
  return now - stamped > maxAgeMs;
}

function clampLimit(raw: string | null, fallback = 8): number {
  // `Number(null)` and `Number("")` are both 0, which is finite — so testing
  // only for NaN made an absent `?limit` clamp to 1 while `?limit=abc`
  // correctly fell back to 8. Absent and empty have to be caught first.
  if (raw === null || raw.trim() === "") return fallback;
  const n = Number(raw);
  if (!Number.isFinite(n)) return fallback;
  return Math.min(50, Math.max(1, Math.trunc(n)));
}

const DAY_MS = 24 * 60 * 60 * 1000;

export function createApp(opts: AppOptions) {
  const postMax = opts.rateLimitPosts ?? 30;
  const rateLimit = createRateLimiter();
  const resultTtlMs = opts.resultTtlMs ?? 90 * DAY_MS;
  const weekMaxAgeMs = opts.weekMaxAgeMs ?? 10 * DAY_MS;
  const now = opts.now ?? Date.now;
  const siteBase = (opts.siteBase ?? "https://voteaxis.org").replace(/\/+$/, "");

  const resultUrl = (id: string) => `${siteBase}/result/${id}`;

  // `bicam.meta()` runs COUNT(*) over the bills table on every call; those
  // numbers only move when sync_bicam replaces the file, which restarts the
  // process. Cache briefly so an unauthenticated flood of /v1/congress cannot
  // turn every request into a table scan.
  const CONGRESS_META_TTL_MS = 5 * 60 * 1000;
  let congressMetaCache: { at: number; body: unknown } | null = null;

  // /v1/week reads and JSON-parses a file per request. Re-read only when the
  // file actually changes on disk; a stat is cheap, a parse is not.
  let weekCache: { key: string; body: unknown } | null = null;
  const readWeek = (): unknown => {
    const stat = statSync(opts.weekPath);
    const key = `${stat.mtimeMs}:${stat.size}`;
    if (weekCache?.key === key) return weekCache.body;
    const body: unknown = JSON.parse(readFileSync(opts.weekPath, "utf8"));
    weekCache = { key, body };
    return body;
  };

  // /v1/politicians serves a ~1.5 MB array from disk. Re-read and re-index
  // only when the file changes — same stat-then-parse shortcut as readWeek,
  // plus a byId map so GET /v1/politicians/:id doesn't scan the array.
  const politiciansPath = opts.politiciansPath ?? politiciansFile();
  let politiciansCache: {
    key: string;
    etag: string;
    all: Record<string, unknown>[];
    byId: Map<string, Record<string, unknown>>;
  } | null = null;
  const readPoliticians = () => {
    const stat = statSync(politiciansPath);
    const key = `${stat.mtimeMs}:${stat.size}`;
    if (politiciansCache?.key === key) return politiciansCache;
    const parsed = JSON.parse(readFileSync(politiciansPath, "utf8"));
    const all = Array.isArray(parsed) ? (parsed as Record<string, unknown>[]) : [];
    const byId = new Map(
      all
        .filter((p) => typeof p.id === "string")
        .map((p) => [p.id as string, p]),
    );
    // Weak: this is a content version marker for 304s, not a byte-for-byte
    // integrity hash. Quoted per RFC 9110, W/ prefix since re-parsing the
    // same bytes twice is not guaranteed to produce an identical re-serialization.
    politiciansCache = { key, etag: `W/"${key}"`, all, byId };
    return politiciansCache;
  };

  /**
   * What a reader gets. An encrypted result hands back the sealed envelope and
   * nothing else — this process has no password and no way to open it, so
   * there is no "locked" state to negotiate, just bytes the client decrypts.
   */
  const readResult = (
    found: NonNullable<ReturnType<Store["lookupResult"]>>,
  ) => {
    const shared = {
      ok: true,
      id: found.id,
      url: resultUrl(found.id),
      createdAt: found.createdAt,
      expiresAt: found.expiresAt,
    };
    if (found.envelope) {
      return { ...shared, encrypted: true, envelope: found.envelope };
    }
    return { ...shared, encrypted: false, ...found.payload };
  };

  /**
   * True when the request may see `/v1/politicians`, by either credential:
   * the shared `x-voteaxis-key` (no key configured means locked to everyone,
   * key holder included — see the option's doc comment) or, when
   * `politiciansAllowDeviceTokens` is on, a request signed by a registered
   * device keypair. Both responses on failure are the same generic 401 —
   * distinguishing "no key configured" from "wrong key" from "bad signature"
   * would tell a prober which case they're in.
   *
   * The signed path checks, in order: deviceId and signature are the right
   * shape; the deviceId is registered; the timestamp is within
   * DEVICE_SIGNATURE_WINDOW_MS of now; the signature verifies over
   * `method\npath\ndeviceId\ntimestamp\nnonce` under that device's public
   * key; and the (deviceId, nonce) pair hasn't been used before. Only a
   * request that clears all five gets `touchDevice` — a rejected attempt
   * must not extend a real device's idle-sweep window or spend its nonce.
   */
  const politiciansAuthorized = (req: Request, method: string, path: string): boolean => {
    const configuredKey = opts.politiciansApiKey;
    const givenKey = req.headers.get("x-voteaxis-key");
    if (configuredKey && givenKey && keysMatch(configuredKey, givenKey)) {
      return true;
    }
    if (opts.politiciansAllowDeviceTokens) {
      const deviceId = req.headers.get("x-voteaxis-device-id") ?? "";
      const timestampRaw = req.headers.get("x-voteaxis-timestamp") ?? "";
      const nonce = req.headers.get("x-voteaxis-nonce") ?? "";
      const signature = req.headers.get("x-voteaxis-signature") ?? "";
      const timestamp = Number(timestampRaw);
      if (
        DEVICE_ID_HEX.test(deviceId) &&
        DEVICE_NONCE_HEX.test(nonce) &&
        DEVICE_SIGNATURE_HEX.test(signature) &&
        Number.isFinite(timestamp) &&
        Math.abs(now() - timestamp) <= DEVICE_SIGNATURE_WINDOW_MS
      ) {
        const publicKey = opts.store.getDevicePublicKey(deviceId);
        const message = `${method}\n${path}\n${deviceId}\n${timestampRaw}\n${nonce}`;
        if (
          publicKey &&
          verifyDeviceSignature(publicKey, message, signature) &&
          opts.store.nonceIsFresh(deviceId, nonce, now())
        ) {
          opts.store.touchDevice(deviceId);
          return true;
        }
      }
    }
    return false;
  };

  const politiciansUnauthorized = (req: Request) =>
    json(req, 401, {
      ok: false,
      error: "Missing or invalid API key.",
    });

  /**
   * Logs every failed `/v1/politicians*` auth attempt, and escalates to a
   * louder line once one IP racks up more than a handful in a short window —
   * a plain grep for "repeated politicians auth failures" in `pm2 logs` is
   * the whole point: a signal for whether scraping is an observed problem
   * yet, not a bearer of it. Never logs the given key or signature — only
   * that one was wrong. Reuses the same bucket mechanism as the request rate
   * limiter (so memory stays bounded by `MAX_BUCKETS`), keyed separately so
   * failures don't share a count with successful traffic.
   */
  const politiciansAuthFailed = (ip: string, path: string): void => {
    console.warn(`[voteaxis-api] politicians auth failed ip=${ip} path=${path}`);
    if (!rateLimit(`politicians-auth-fail:${ip}`, 10, 15 * 60 * 1000)) {
      console.error(
        `[voteaxis-api] repeated politicians auth failures from ip=${ip} ` +
          "in the last 15m — possible scraping or key-guessing",
      );
    }
  };

  const missingBicam = (req: Request) =>
    json(req, 503, {
      ok: false,
      error:
        "Congress API is not loaded. On the server run python3 scripts/sync_bicam.py — see https://py.docs.bicam.net/en/latest/installation.html",
      source: "bicam.net",
    });

  return {
    fetch(req: Request): Response | Promise<Response> {
      const url = new URL(req.url);
      const path = url.pathname.replace(/\/+$/, "") || "/";

      // HEAD as well as GET: uptime monitors default to HEAD more often than
      // not, and answering 404 to one reads as the API being down. `json()`
      // drops the body for a HEAD, which is what the method means.
      if (
        (req.method === "GET" || req.method === "HEAD") &&
        (path === "/health" || path === "/v1/health")
      ) {
        return json(req, 200, {
          ok: true,
          service: "voteaxis-api",
          congress: Boolean(opts.bicam?.configured),
          congressGov: Boolean(opts.enricher?.configured),
          politiciansGated: Boolean(opts.politiciansApiKey),
          politiciansDeviceTokens: Boolean(opts.politiciansAllowDeviceTokens),
        });
      }

      if (req.method === "GET" && path === "/v1/week") {
        const ip = clientIp(req);
        if (!rateLimit(`week:${ip}`, 600, 60 * 60 * 1000)) {
          return json(req, 429, { ok: false, error: "Too many requests. Try later." });
        }
        try {
          const body = readWeek();
          if (weekIsStale(body, now(), weekMaxAgeMs)) {
            return json(req, 404, {
              ok: false,
              error: "The issue of the week is out of date.",
            });
          }
          return json(req, 200, body);
        } catch {
          weekCache = null;
          return json(req, 404, { ok: false, error: "No issue of the week." });
        }
      }

      if (req.method === "GET" && path === "/v1/congress") {
        const ip = clientIp(req);
        if (!rateLimit(`congress:${ip}`, 120, 60 * 60 * 1000)) {
          return json(req, 429, { ok: false, error: "Too many Congress lookups." });
        }
        if (!opts.bicam?.configured) return missingBicam(req);
        try {
          const at = now();
          if (
            !congressMetaCache ||
            at - congressMetaCache.at > CONGRESS_META_TTL_MS
          ) {
            congressMetaCache = { at, body: { ok: true, ...opts.bicam.meta() } };
          }
          return json(req, 200, congressMetaCache.body);
        } catch {
          congressMetaCache = null;
          return missingBicam(req);
        }
      }

      const memberBills = path.match(/^\/v1\/members\/([^/]+)\/bills$/);
      if (req.method === "GET" && memberBills) {
        const ip = clientIp(req);
        if (!rateLimit(`congress:${ip}`, 120, 60 * 60 * 1000)) {
          return json(req, 429, { ok: false, error: "Too many Congress lookups." });
        }
        const bioguide = safeDecode(memberBills[1] ?? "");
        if (!BIOGUIDE.test(bioguide)) {
          return json(req, 400, { ok: false, error: "Invalid bioguide id." });
        }
        if (!opts.bicam?.configured) return missingBicam(req);
        const kindRaw = (url.searchParams.get("kind") ?? "all").toLowerCase();
        const kind =
          kindRaw === "sponsored" || kindRaw === "cosponsored" ? kindRaw : "all";
        try {
          return json(req, 200, {
            ok: true,
            source: "bicam.net",
            bioguideId: bioguide.toUpperCase(),
            bills: opts.bicam.memberBills(
              bioguide,
              kind,
              clampLimit(url.searchParams.get("limit")),
            ),
          });
        } catch {
          return json(req, 502, {
            ok: false,
            error: "Congress API could not load those bills.",
            source: "bicam.net",
          });
        }
      }

      const member = path.match(/^\/v1\/members\/([^/]+)$/);
      if (req.method === "GET" && member) {
        const ip = clientIp(req);
        if (!rateLimit(`congress:${ip}`, 120, 60 * 60 * 1000)) {
          return json(req, 429, { ok: false, error: "Too many Congress lookups." });
        }
        const bioguide = safeDecode(member[1] ?? "");
        if (!BIOGUIDE.test(bioguide)) {
          return json(req, 400, { ok: false, error: "Invalid bioguide id." });
        }
        if (!opts.bicam?.configured) return missingBicam(req);
        const found = opts.bicam.member(bioguide);
        if (!found) {
          return json(req, 404, {
            ok: false,
            error: "No BICAM member for that bioguide id.",
            source: "bicam.net",
          });
        }
        return json(req, 200, { ok: true, source: "bicam.net", ...found });
      }

      const bill = path.match(/^\/v1\/bills\/(\d+)\/([^/]+)\/([^/]+)$/);
      if (req.method === "GET" && bill) {
        const ip = clientIp(req);
        if (!rateLimit(`congress:${ip}`, 120, 60 * 60 * 1000)) {
          return json(req, 429, { ok: false, error: "Too many Congress lookups." });
        }
        const congress = Number(bill[1]);
        const type = safeDecode(bill[2] ?? "");
        const number = safeDecode(bill[3] ?? "");
        if (!Number.isInteger(congress) || !BILL_TYPE.test(type) || !number) {
          return json(req, 400, { ok: false, error: "Invalid bill citation." });
        }
        if (!opts.bicam?.configured) return missingBicam(req);
        const found = opts.bicam.bill(congress, type, number);
        if (!found) {
          return json(req, 404, {
            ok: false,
            error: "No BICAM bill for that citation.",
            source: "bicam.net",
          });
        }
        return json(req, 200, { ok: true, source: "bicam.net", ...found });
      }

      const receipts = path.match(/^\/v1\/receipts\/([^/]+)$/);
      if (req.method === "GET" && receipts) {
        const ip = clientIp(req);
        if (!rateLimit(`receipts:${ip}`, 60, 60 * 60 * 1000)) {
          return json(req, 429, { ok: false, error: "Too many receipt lookups." });
        }
        const bioguide = safeDecode(receipts[1] ?? "");
        if (!BIOGUIDE.test(bioguide)) {
          return json(req, 400, { ok: false, error: "Invalid bioguide id." });
        }
        if (!opts.bicam?.configured) return missingBicam(req);
        return Promise.resolve(opts.bicam.getReceipts(bioguide))
          .then((data) => opts.enricher?.enrichReceipts(data) ?? data)
          .then((data) => json(req, 200, { ok: true, ...data }))
          .catch(() =>
            json(req, 502, {
              ok: false,
              error: "Congress API did not return receipts for that member.",
              source: "bicam.net",
            }),
          );
      }

      if (req.method === "GET" && path === "/v1/politicians") {
        const ip = clientIp(req);
        if (!rateLimit(`politicians:${ip}`, 60, 60 * 60 * 1000)) {
          return json(req, 429, { ok: false, error: "Too many roster requests." });
        }
        if (!politiciansAuthorized(req, req.method, path)) {
          politiciansAuthFailed(ip, path);
          return politiciansUnauthorized(req);
        }
        try {
          const { all, byId, etag } = readPoliticians();
          if (req.headers.get("if-none-match") === etag) {
            return notModified(req, etag);
          }
          const state = url.searchParams.get("state");
          const officeType = url.searchParams.get("officeType");
          const party = url.searchParams.get("party");
          const currentRaw = url.searchParams.get("current");
          const q = url.searchParams.get("q")?.trim().toLowerCase();
          let filtered = all;
          if (state) {
            const s = state.toUpperCase();
            filtered = filtered.filter((p) => p.state === s);
          }
          if (officeType) {
            filtered = filtered.filter((p) => p.officeType === officeType);
          }
          if (party) {
            filtered = filtered.filter((p) => p.party === party);
          }
          if (currentRaw === "true" || currentRaw === "false") {
            const want = currentRaw === "true";
            filtered = filtered.filter((p) => p.current === want);
          }
          if (q) {
            filtered = filtered.filter((p) =>
              typeof p.name === "string" && p.name.toLowerCase().includes(q),
            );
          }
          return politiciansJson(req, 200, etag, {
            ok: true,
            source: "voteaxis",
            total: byId.size,
            count: filtered.length,
            politicians: filtered,
          });
        } catch {
          return json(req, 503, {
            ok: false,
            error:
              "Roster is not loaded. Run python3 scripts/sync_politicians.py on the server.",
          });
        }
      }

      const politicianById = path.match(/^\/v1\/politicians\/([^/]+)$/);
      if (req.method === "GET" && politicianById) {
        const ip = clientIp(req);
        if (!rateLimit(`politicians:${ip}`, 60, 60 * 60 * 1000)) {
          return json(req, 429, { ok: false, error: "Too many roster requests." });
        }
        if (!politiciansAuthorized(req, req.method, path)) {
          politiciansAuthFailed(ip, path);
          return politiciansUnauthorized(req);
        }
        const id = safeDecode(politicianById[1] ?? "");
        if (!POLITICIAN_ID.test(id)) {
          return json(req, 400, { ok: false, error: "Invalid politician id." });
        }
        try {
          const { byId, etag } = readPoliticians();
          if (req.headers.get("if-none-match") === etag) {
            return notModified(req, etag);
          }
          const found = byId.get(id);
          if (!found) {
            return json(req, 404, {
              ok: false,
              error: "No politician with that id.",
            });
          }
          return politiciansJson(req, 200, etag, {
            ok: true,
            source: "voteaxis",
            politician: found,
          });
        } catch {
          return json(req, 503, {
            ok: false,
            error:
              "Roster is not loaded. Run python3 scripts/sync_politicians.py on the server.",
          });
        }
      }

      if (req.method === "POST" && path === "/v1/device-tokens") {
        // No auth gate here on purpose: there is no account to check a fresh
        // install against, so this is the bootstrap step, not a protected
        // route. What keeps it from being an open roster proxy is that a
        // registered device only reads anything once
        // politiciansAllowDeviceTokens is on, and every read after that
        // still needs a fresh signature this device_id's key verifies — the
        // registration call itself hands over nothing but a public key, and
        // stays cheap to rate-limit since a real install needs at most one
        // of these, ever.
        if (tooLarge(req)) {
          return json(req, 413, { ok: false, error: "That payload is too large." });
        }
        const ip = clientIp(req);
        if (!rateLimit(`device-token:${ip}`, 5, 60 * 60 * 1000)) {
          return json(req, 429, { ok: false, error: "Too many registration requests." });
        }
        return req.json().then(
          (body) => {
            const publicKey =
              typeof body === "object" && body !== null
                ? (body as { publicKey?: unknown }).publicKey
                : undefined;
            if (typeof publicKey !== "string" || !DEVICE_PUBLIC_KEY_HEX.test(publicKey)) {
              return json(req, 400, { ok: false, error: "Invalid public key." });
            }
            const { deviceId, issuedAt } = opts.store.registerDevice(publicKey);
            return json(req, 200, { ok: true, deviceId, issuedAt });
          },
          () => json(req, 400, { ok: false, error: "Invalid JSON." }),
        );
      }

      if (req.method === "POST" && path === "/v1/codes") {
        if (tooLarge(req)) {
          return json(req, 413, { ok: false, error: "That payload is too large." });
        }
        const ip = clientIp(req);
        if (!rateLimit(`post:${ip}`, postMax, 60 * 60 * 1000)) {
          return json(req, 429, { ok: false, error: "Too many codes. Try later." });
        }
        return req.json().then(
          (body) => {
            const token =
              typeof body === "object" && body !== null
                ? normalizeToken((body as { token?: unknown }).token)
                : undefined;
            const payload = parsePayload(body);
            if (typeof payload === "string") {
              return json(req, 400, { ok: false, error: payload });
            }
            const published = opts.store.publish(payload, token, opts.ttlMs);
            return json(req, 200, {
              ok: true,
              code: published.code,
              token: published.token,
              expiresAt: published.expiresAt,
            });
          },
          () => json(req, 400, { ok: false, error: "Invalid JSON." }),
        );
      }

      const lookup = path.match(/^\/v1\/codes\/([^/]+)$/);
      if (req.method === "GET" && lookup) {
        const ip = clientIp(req);
        if (!rateLimit(`get:${ip}`, 120, 60 * 60 * 1000)) {
          return json(req, 429, { ok: false, error: "Too many lookups. Try later." });
        }
        const code = normalizeCode(safeDecode(lookup[1] ?? ""));
        if (!code) {
          return json(req, 400, { ok: false, error: "That code is not valid." });
        }
        const found = opts.store.lookup(code);
        if (!found) {
          return json(req, 404, { ok: false, error: "Code expired or not found." });
        }
        return json(req, 200, {
          ok: true,
          code: found.code,
          displayName: found.payload.displayName,
          axisScore: found.payload.axisScore,
          issueScores: found.payload.issueScores,
          issueWeights: found.payload.issueWeights,
          pillarScores: found.payload.pillarScores,
          dealbreakerIssueIds: found.payload.dealbreakerIssueIds,
          createdAt: found.createdAt,
          expiresAt: found.expiresAt,
        });
      }

      // ── Shared result pages ─────────────────────────────────────────
      if (req.method === "POST" && path === "/v1/results") {
        if (tooLarge(req)) {
          return json(req, 413, { ok: false, error: "That payload is too large." });
        }
        const ip = clientIp(req);
        if (!rateLimit(`result-post:${ip}`, postMax, 60 * 60 * 1000)) {
          return json(req, 429, { ok: false, error: "Too many links. Try later." });
        }
        return req.json().then(
          (body) => {
            const raw =
              typeof body === "object" && body !== null
                ? (body as Record<string, unknown>)
                : {};
            const token = normalizeToken(raw.token);

            // A client sends readable scores or a sealed envelope, never both.
            // There is no `password` field: the server is not in that loop.
            if (raw.envelope != null) {
              if (raw.payload != null) {
                return json(req, 400, {
                  ok: false,
                  error: "Send a payload or an envelope, not both.",
                });
              }
              const envelope = parseEnvelope(raw.envelope);
              if (typeof envelope === "string") {
                return json(req, 400, { ok: false, error: envelope });
              }
              const published = opts.store.publishResult(
                envelope,
                true,
                token,
                resultTtlMs,
              );
              return json(req, 200, {
                ok: true,
                id: published.id,
                token: published.token,
                url: resultUrl(published.id),
                encrypted: true,
                expiresAt: published.expiresAt,
              });
            }

            const payload = parseResultPayload(raw.payload ?? body);
            if (typeof payload === "string") {
              return json(req, 400, { ok: false, error: payload });
            }
            const published = opts.store.publishResult(
              payload,
              false,
              token,
              resultTtlMs,
            );
            return json(req, 200, {
              ok: true,
              id: published.id,
              token: published.token,
              url: resultUrl(published.id),
              encrypted: false,
              expiresAt: published.expiresAt,
            });
          },
          () => json(req, 400, { ok: false, error: "Invalid JSON." }),
        );
      }

      const resultLookup = path.match(/^\/v1\/results\/([^/]+)$/);
      if (resultLookup) {
        const id = normalizeResultId(safeDecode(resultLookup[1] ?? ""));

        if (req.method === "GET") {
          const ip = clientIp(req);
          if (!rateLimit(`result-get:${ip}`, 240, 60 * 60 * 1000)) {
            return json(req, 429, { ok: false, error: "Too many lookups. Try later." });
          }
          if (!id) return json(req, 400, { ok: false, error: "Invalid link." });
          const found = opts.store.lookupResult(id);
          if (!found) {
            return json(req, 404, { ok: false, error: "This link expired or was removed." });
          }
          return json(req, 200, readResult(found));
        }

        if (req.method === "DELETE") {
          const ip = clientIp(req);
          if (!rateLimit(`result-delete:${ip}`, postMax, 60 * 60 * 1000)) {
            return json(req, 429, { ok: false, error: "Too many requests. Try later." });
          }
          if (!id) return json(req, 400, { ok: false, error: "Invalid link." });
          const token = normalizeToken(req.headers.get("x-voteaxis-token"));
          if (!token) return json(req, 401, { ok: false, error: "Missing token." });
          const removed = opts.store.deleteResult(id, token);
          if (!removed) {
            return json(req, 404, { ok: false, error: "This link expired or was removed." });
          }
          return json(req, 200, { ok: true, id });
        }
      }

      return json(req, 404, { ok: false, error: "Not found." });
    },
  };
}

export function weekFile(root = import.meta.dir): string {
  return join(root, "..", "data", "issue-of-the-week.json");
}

/**
 * `mobile/assets/data/politicians.json` stays the source of truth; this is a
 * served copy `scripts/sync_politicians.py` writes here, because
 * `scripts/deploy.py` never ships `mobile/` to the box.
 */
export function politiciansFile(root = import.meta.dir): string {
  return join(root, "..", "data", "politicians.json");
}

/**
 * Interface to bind, defaulting to loopback.
 *
 * Lives here rather than inline in index.ts so it is reachable from a test
 * without importing the module that calls Bun.serve. Binding 0.0.0.0 publishes
 * the API with no TLS and lets any caller forge the X-Real-IP the limiter is
 * built on, so it has to be an explicit opt-in for LAN dev — never something
 * you get from an unset or blank variable.
 */
export function resolveHost(raw = process.env.HOST): string {
  return raw?.trim() || "127.0.0.1";
}
