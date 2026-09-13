#!/usr/bin/env bun
/**
 * Probe the SMTP relay this site sends through.
 *
 *   NODE_ENV=production bun run mail:check
 *   NODE_ENV=production bun run mail:check you@example.com   # also sends one
 *
 * NODE_ENV=production matters: it is what makes Bun load
 * .env.production.local, where SMTP_HOST lives on the VPS.
 *
 * Run it on the VPS, where SMTP_HOST points at loopback Postfix. Locally it
 * exits 0 with a note unless you have a relay configured — that is the same
 * "no SMTP_HOST means no mail" rule the app follows.
 *
 * scripts/deploy.py runs this after every deploy and reports failures without
 * failing the deploy: a mail misconfiguration is worth knowing about, but the
 * site is up either way.
 */
import { isMailConfigured, mailFrom, sendMail, verifyMail } from "../lib/mail";

const to = process.argv[2];
const host = process.env.SMTP_HOST;
const port = process.env.SMTP_PORT ?? "25";

if (!isMailConfigured()) {
  console.log("SMTP_HOST is unset — this deployment sends no mail.");
  console.log("Set it in web/.env.production.local (localhost on the VPS),");
  console.log("and run this with NODE_ENV=production — that is what makes Bun");
  console.log("load .env.production.local at all.");
  process.exit(0);
}

console.log(`Connecting to ${host}:${port} as ${mailFrom()}…`);

try {
  await verifyMail();
  console.log("✅ SMTP reachable");
} catch (err) {
  console.error("❌ SMTP connection failed:", (err as Error).message);
  console.error(
    "   On the VPS: systemctl status postfix, then ss -lntp | grep :25",
  );
  process.exit(1);
}

if (!to) {
  console.log("No recipient given — skipping the send test.");
  console.log("Send one with: bun run mail:check you@example.com");
  process.exit(0);
}

const result = await sendMail({
  to,
  subject: "Voteaxis mail check",
  text: [
    "This is a test message from the Voteaxis site.",
    "",
    `Relay: ${host}:${port}`,
    `From: ${mailFrom()}`,
    `Time: ${new Date().toISOString()}`,
  ].join("\n"),
});

if (result.sent) {
  console.log(`✅ Test message accepted for ${to}`);
  console.log("   Check the inbox AND the spam folder — if it landed in spam,");
  console.log("   verify SPF/DKIM/DMARC for the From domain (see DEPLOY.md).");
} else {
  console.error(`❌ Send failed (${result.reason})`);
  console.error("   Postfix log: journalctl -u postfix -n 50");
  process.exit(1);
}
