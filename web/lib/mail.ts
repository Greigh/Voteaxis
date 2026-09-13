import nodemailer, { type Transporter } from "nodemailer";

/**
 * Thin nodemailer wrapper. On the VPS this talks to the local Postfix on
 * 127.0.0.1:25 — the same loopback-only relay FiHaven uses — which signs
 * outbound mail with OpenDKIM and delivers it itself. No third-party API, no
 * key, no per-message billing.
 *
 * SMTP_HOST is the switch: unset (the dev default) means the app sends no
 * mail at all, so nothing tries to reach a relay that isn't there. Waitlist
 * signups still land in the JSONL sink.
 *
 *   SMTP_HOST=localhost
 *   SMTP_PORT=25
 *   MAIL_FROM=Voteaxis <no-reply@voteaxis.org>
 *
 * SMTP_USER / SMTP_PASS only when the relay requires auth; loopback Postfix
 * does not.
 *
 * The From domain must be one OpenDKIM signs — see the Mail section of
 * DEPLOY.md. Sending as an unsigned domain is how you get filed as spam.
 */

const DEFAULT_FROM = "Voteaxis <no-reply@voteaxis.org>";

let cached: Transporter | null = null;

/** Collapse anything that could terminate a header line.
 *
 * Subjects here interpolate user-supplied text (the address someone typed into
 * the waitlist form), and a raw CR/LF in one is the classic header-injection
 * primitive: an attacker-supplied "\r\nBcc: ..." riding along as a real header.
 * Nodemailer folds and encodes subjects itself, but the guarantee should not
 * rest on a library internal. Built from escapes rather than literal control
 * characters so the class cannot be silently corrupted in transit:
 * U+0000-U+001F, DEL, and the Unicode line separators parsers also treat as
 * line breaks.
 */
// Matching control characters is the whole point here: this is the guard that
// keeps them out of headers, not an accidental use of one.
// biome-ignore lint/suspicious/noControlCharactersInRegex: intentional
const HEADER_UNSAFE = /[\u0000-\u001f\u007f\u2028\u2029]+/g;

export function sanitizeHeader(value: string): string {
  return value.replace(HEADER_UNSAFE, " ").trim();
}

/** True when an SMTP relay is configured. Callers use it to stay quiet in dev. */
export function isMailConfigured(): boolean {
  return Boolean(process.env.SMTP_HOST);
}

export function mailFrom(): string {
  return process.env.MAIL_FROM ?? DEFAULT_FROM;
}

/** Where operational notifications go (waitlist signups, contribution checkouts).
 *
 * One knob for every channel. Callers must NOT pass their own `to` from env —
 * doing that is how MAIL_NOTIFY_TO silently became dead config once already.
 * WAITLIST_NOTIFY_TO is the older name for the same thing, still honoured.
 *
 * No hardcoded fallback address: mail with nowhere to go should report
 * `no_recipient` loudly, not quietly deliver to whoever was in the source when
 * the file was written.
 */
export function notifyTo(): string {
  return process.env.MAIL_NOTIFY_TO ?? process.env.WAITLIST_NOTIFY_TO ?? "";
}

function transporter(): Transporter {
  if (cached) return cached;
  const host = process.env.SMTP_HOST ?? "localhost";
  const port = Number.parseInt(process.env.SMTP_PORT ?? "25", 10);
  const auth =
    process.env.SMTP_USER && process.env.SMTP_PASS
      ? { user: process.env.SMTP_USER, pass: process.env.SMTP_PASS }
      : undefined;

  cached = nodemailer.createTransport({
    host,
    port,
    // Loopback Postfix has no valid certificate for "localhost" and needs
    // none — the hop never leaves the machine, and Postfix negotiates STARTTLS
    // itself on the way out. A real relay on 465/587 gets the usual treatment.
    secure: port === 465,
    requireTLS: port === 587,
    tls: { rejectUnauthorized: port !== 25 },
    auth,
  });
  return cached;
}

export type MailMessage = {
  to?: string;
  subject: string;
  text: string;
  html?: string;
  replyTo?: string;
  headers?: Record<string, string>;
};

export type MailResult =
  | { sent: true }
  | { sent: false; reason: "not_configured" | "no_recipient" | "send_failed" };

/** Send one message. Never throws: mail is a side channel, not the request. */
export async function sendMail(message: MailMessage): Promise<MailResult> {
  if (!isMailConfigured()) return { sent: false, reason: "not_configured" };

  const to = message.to ?? notifyTo();
  if (!to) return { sent: false, reason: "no_recipient" };

  try {
    await transporter().sendMail({
      from: mailFrom(),
      to,
      // Sanitized here rather than at each call site so a new caller cannot
      // forget.
      subject: sanitizeHeader(message.subject),
      text: message.text,
      html: message.html,
      // Also a header, also built from user-supplied addresses upstream.
      replyTo: message.replyTo ? sanitizeHeader(message.replyTo) : undefined,
      headers: message.headers,
    });
    return { sent: true };
  } catch (err) {
    console.error("[mail] send failed", err);
    return { sent: false, reason: "send_failed" };
  }
}

/** Probe the connection (and auth, if configured) without sending anything. */
export async function verifyMail(): Promise<void> {
  await transporter().verify();
}

/** Tests and long-lived processes that change SMTP_* at runtime. */
export function resetMailTransport(): void {
  cached = null;
}
