import { appendFile, mkdir, readFile } from "node:fs/promises";
import path from "node:path";
import { isMailConfigured, sendMail } from "./mail";

export const WAITLIST_ROLES = ["teacher", "newsroom"] as const;

export type WaitlistRole = (typeof WAITLIST_ROLES)[number];

export type WaitlistEntry = {
  email: string;
  createdAt: string;
  source: string;
  roles: WaitlistRole[];
};

export function parseWaitlistRoles(raw: unknown): WaitlistRole[] {
  if (!Array.isArray(raw)) return [];
  const roles = new Set<WaitlistRole>();
  for (const item of raw) {
    if (item === "teacher" || item === "newsroom") roles.add(item);
  }
  return [...roles];
}

/**
 * Operator-configurable on purpose: on the VPS this points outside the deploy
 * directory so the JSONL survives a git-pull-and-rebuild. Because the path is
 * not statically known, Turbopack would trace the whole project into the
 * server output — the reads below opt out with `turbopackIgnore`.
 */
function storePath() {
  return (
    process.env.WAITLIST_STORE_PATH ??
    path.join(process.cwd(), "data", "waitlist.jsonl")
  );
}

function isValidEmail(email: string) {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) && email.length <= 254;
}

/**
 * How many addresses the in-memory dedupe set holds. The store is append-only
 * and roughly chronological, so the resident set is the most recent
 * DEDUPE_LIMIT signups — the ones a double-submit or a same-week retry would
 * actually hit. An address older than that which signs up again slips through
 * as one duplicate row plus one duplicate operator notification, which is the
 * accepted cost of not running a datastore on the box. Matches the
 * MAX_BUCKETS ceiling the rate limiters use.
 */
export const DEDUPE_LIMIT = 50_000;

/** Every stored address, oldest first. Skips blank and unparseable lines. */
async function readAllEmails(): Promise<string[]> {
  try {
    const raw = await readFile(/*turbopackIgnore: true*/ storePath(), "utf8");
    const out: string[] = [];
    for (const line of raw.split("\n")) {
      if (!line.trim()) continue;
      try {
        const row = JSON.parse(line) as WaitlistEntry;
        if (row.email) out.push(row.email);
      } catch {
        // skip bad lines
      }
    }
    return out;
  } catch {
    return [];
  }
}

async function readEmails(): Promise<Set<string>> {
  // Only the tail is kept resident — see DEDUPE_LIMIT. Reading the file itself
  // is still O(size), but that happens once per process, not per signup.
  return new Set((await readAllEmails()).slice(-DEDUPE_LIMIT));
}

/** Adds an address to the resident set, evicting the oldest to stay bounded. */
export function rememberEmail(emails: Set<string>, email: string): void {
  emails.add(email);
  while (emails.size > DEDUPE_LIMIT) {
    // Sets iterate in insertion order, so this drops the oldest-seen address.
    const oldest = emails.values().next().value;
    if (oldest === undefined) break;
    emails.delete(oldest);
  }
}

async function appendEntry(entry: WaitlistEntry) {
  await mkdir(path.dirname(storePath()), { recursive: true });
  await appendFile(storePath(), `${JSON.stringify(entry)}\n`, "utf8");
}

/**
 * The known-address set, read from disk once and kept current by our own
 * appends.
 *
 * Re-reading and JSON-parsing the whole JSONL on every signup made the cost of
 * a signup grow with the list. This process is the only writer — PM2 runs
 * `instances: 1` precisely so the append stays single-writer — so the set can
 * not drift underneath us. It is capped at DEDUPE_LIMIT so a runaway list
 * cannot grow it without bound. Keyed by path so the tests, which point
 * WAITLIST_STORE_PATH at a fresh temp dir per case, do not see each other.
 */
let cache: { path: string; emails: Set<string> } | null = null;

async function emailSet(): Promise<Set<string>> {
  const current = storePath();
  if (cache?.path === current) return cache.emails;
  const emails = await readEmails();
  cache = { path: current, emails };
  return emails;
}

/** Tests and long-lived processes that repoint WAITLIST_STORE_PATH at runtime. */
export function resetWaitlistCache(): void {
  cache = null;
}

/**
 * Serializes the check-then-append critical section.
 *
 * Reading the set and appending to the file are two awaits, and two concurrent
 * signups for the same address could both observe "not present" and both write
 * a row. Only the dedupe and the append are held — mail and the webhook stay
 * outside, or every signup would queue behind someone else's SMTP round trip.
 */
let queue: Promise<unknown> = Promise.resolve();

function withLock<T>(fn: () => Promise<T>): Promise<T> {
  const run = queue.then(fn, fn);
  queue = run.catch(() => undefined);
  return run;
}

function formatRoles(roles: WaitlistRole[]) {
  return roles.length > 0 ? roles.join(", ") : "(none)";
}

/** Notify over the self-hosted SMTP relay (loopback Postfix on the VPS). */
async function notifyMail(email: string, roles: WaitlistRole[]) {
  return sendMail({
    // No `to`: lib/mail.ts resolves the notification address from
    // MAIL_NOTIFY_TO. Passing one from env here is what made that setting a
    // no-op the first time round.
    // The address is user-supplied and lands in a header; lib/mail.ts strips
    // anything that could terminate the line.
    subject: `Waitlist: ${email}`,
    text: [
      `${email} joined the Voteaxis waitlist.`,
      "",
      `Roles: ${formatRoles(roles)}`,
      "Source: voteaxis-web",
      `Time: ${new Date().toISOString()}`,
    ].join("\n"),
    // Replying to the notification reaches the person who signed up.
    replyTo: email,
  });
}

/**
 * The signup request awaits this call, and PM2 runs a single instance, so a
 * webhook that accepts the connection and never answers holds the site's only
 * signup path open until the platform gives up. A few of those is an outage.
 */
const WEBHOOK_TIMEOUT_MS = 5000;

async function notifyWebhook(email: string, roles: WaitlistRole[]) {
  const webhook = process.env.WAITLIST_WEBHOOK_URL;
  if (!webhook)
    return { sent: false as const, reason: "missing_webhook" as const };

  let res: Response;
  try {
    res = await fetch(webhook, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        email,
        roles,
        source: "voteaxis-web",
        timestamp: new Date().toISOString(),
      }),
      signal: AbortSignal.timeout(WEBHOOK_TIMEOUT_MS),
    });
  } catch (err) {
    // A timeout and a refused connection are the same thing to the caller: the
    // signup still lands in the JSONL, the notification just did not go out.
    console.error("[waitlist] webhook unreachable", err);
    return { sent: false as const, reason: "webhook_failed" as const };
  }

  if (!res.ok) {
    console.error("[waitlist] webhook status", res.status);
    return { sent: false as const, reason: "webhook_failed" as const };
  }
  return { sent: true as const };
}

export type JoinResult =
  | { ok: true; alreadyJoined: boolean }
  | { ok: false; error: string; status: number };

/**
 * Persist signup to data/waitlist.jsonl and notify via SMTP and/or webhook.
 */
export async function joinWaitlist(
  rawEmail: string,
  rawRoles?: unknown,
): Promise<JoinResult> {
  const email = rawEmail.trim().toLowerCase();
  if (!email || !isValidEmail(email)) {
    return { ok: false, error: "Enter a valid email address.", status: 400 };
  }

  const roles = parseWaitlistRoles(rawRoles);

  const claim = await withLock(async () => {
    const emails = await emailSet();
    if (emails.has(email)) return { fresh: false as const, stored: false };

    const entry: WaitlistEntry = {
      email,
      createdAt: new Date().toISOString(),
      source: "voteaxis-web",
      roles,
    };

    let stored = false;
    try {
      await appendEntry(entry);
      // Only after the write lands. Caching a failed append would make every
      // later attempt look like a duplicate and silently drop the signup.
      rememberEmail(emails, email);
      stored = true;
    } catch (err) {
      console.error("[waitlist] file store failed", err);
    }
    return { fresh: true as const, stored };
  });

  if (!claim.fresh) {
    return { ok: true, alreadyJoined: true };
  }
  const stored = claim.stored;

  let notified = false;
  try {
    const mail = await notifyMail(email, roles);
    if (mail.sent) notified = true;
  } catch (err) {
    console.error("[waitlist] mail threw", err);
  }

  try {
    const hook = await notifyWebhook(email, roles);
    if (hook.sent) notified = true;
  } catch (err) {
    console.error("[waitlist] webhook threw", err);
  }

  const hasRemote =
    isMailConfigured() || Boolean(process.env.WAITLIST_WEBHOOK_URL);

  if (!stored && !notified) {
    return {
      ok: false,
      error: hasRemote
        ? "Could not join the waitlist right now."
        : "Waitlist storage isn’t configured yet.",
      status: 503,
    };
  }

  // On ephemeral hosts, file may not persist — require a remote channel in production.
  if (
    process.env.NODE_ENV === "production" &&
    !notified &&
    hasRemote === false &&
    stored
  ) {
    console.warn(
      "[waitlist] stored to local file only — set SMTP_HOST or WAITLIST_WEBHOOK_URL for durable production delivery",
    );
  }

  return { ok: true, alreadyJoined: false };
}

/**
 * Dev helper — distinct addresses in the store, without exposing them via API.
 * Reads the file rather than the resident set, so it stays accurate past
 * DEDUPE_LIMIT.
 */
export async function waitlistCount(): Promise<number> {
  return new Set(await readAllEmails()).size;
}
