#!/usr/bin/env bun
/**
 * The Issue of the Week prompt: check whether it is current, or stamp a new one.
 *
 * `/v1/week` refuses to serve a prompt older than the window in
 * `src/app.ts` (10 days), so a stale file makes the card disappear from the
 * app rather than lie about being this week's. That is the right failure — but
 * nothing was telling anyone it had happened, and the prompt sat 13 days old
 * before an audit noticed.
 *
 *   bun run week:check            # exit 1 once it is stale, 0 otherwise
 *   bun run week:check --days 5   # warn earlier, e.g. from a Monday cron
 *   bun run week:set --issue immigration --headline "…" --question "…"
 *
 * Cron on the box, Mondays at 09:00, mailing root on a non-zero exit:
 *
 *   0 9 * * 1 cd /srv/voteaxis/server && /usr/local/bin/bun run week:check
 */

import { readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";

const WEEK_PATH = join(import.meta.dir, "..", "data", "issue-of-the-week.json");
const DAY_MS = 24 * 60 * 60 * 1000;
/** Matches weekMaxAgeMs in src/app.ts. Change both together. */
const SERVED_FOR_DAYS = 10;

type Week = {
  weekOf: string;
  issueId: string;
  headline: string;
  question: string;
  context?: string;
};

function read(): Week {
  return JSON.parse(readFileSync(WEEK_PATH, "utf8")) as Week;
}

/** `--flag value` pairs; a flag with no value is treated as a boolean. */
function args(argv: string[]): Record<string, string> {
  const out: Record<string, string> = {};
  for (let i = 0; i < argv.length; i++) {
    const key = argv[i];
    if (!key?.startsWith("--")) continue;
    const next = argv[i + 1];
    out[key.slice(2)] = next && !next.startsWith("--") ? next : "true";
  }
  return out;
}

function ageInDays(weekOf: string, now = Date.now()): number {
  const stamped = Date.parse(`${weekOf}T00:00:00Z`);
  if (!Number.isFinite(stamped)) return Number.POSITIVE_INFINITY;
  return Math.floor((now - stamped) / DAY_MS);
}

function check(warnAfterDays: number): number {
  let week: Week;
  try {
    week = read();
  } catch (err) {
    console.error(`✗ Cannot read ${WEEK_PATH}: ${String(err)}`);
    return 1;
  }

  const age = ageInDays(week.weekOf);
  if (!Number.isFinite(age)) {
    console.error(`✗ weekOf is not a date: ${JSON.stringify(week.weekOf)}`);
    return 1;
  }

  const line = `weekOf ${week.weekOf} · ${age} day${age === 1 ? "" : "s"} old · "${week.headline}"`;

  if (age > SERVED_FOR_DAYS) {
    console.error(`✗ STALE — /v1/week is already 404ing. ${line}`);
    console.error("  The app is showing no Issue of the Week card at all.");
    console.error("  Stamp a new one:  bun run week:set --issue <id> --headline <…> --question <…>");
    return 1;
  }
  if (age >= warnAfterDays) {
    console.error(`! Due — ${line}`);
    console.error(`  It stops being served after ${SERVED_FOR_DAYS} days.`);
    return 1;
  }
  console.log(`✓ Current — ${line}`);
  return 0;
}

function set(input: Record<string, string>): number {
  const issueId = input.issue;
  const headline = input.headline;
  const question = input.question;
  if (!issueId || !headline || !question) {
    console.error(
      "Usage: bun run week:set --issue <issueId> --headline <text> --question <text> [--context <text>] [--week YYYY-MM-DD]",
    );
    return 1;
  }

  const weekOf = input.week ?? new Date().toISOString().slice(0, 10);
  if (!/^\d{4}-\d{2}-\d{2}$/.test(weekOf)) {
    console.error(`✗ --week must be YYYY-MM-DD, got ${weekOf}`);
    return 1;
  }

  const previous = (() => {
    try {
      return read();
    } catch {
      return null;
    }
  })();

  const week: Week = {
    weekOf,
    issueId,
    headline,
    question,
    context:
      input.context ??
      previous?.context ??
      "This is one of the 22 issues in the Spectrum Issue Index. A weekly prompt is editorial — it does not rescore your quiz until you retake.",
  };

  writeFileSync(WEEK_PATH, `${JSON.stringify(week, null, 2)}\n`);
  console.log(`✓ Wrote ${WEEK_PATH}`);
  console.log(`  ${weekOf} · ${issueId} · "${headline}"`);
  console.log("  Deploy it:  bun run deploy:api");
  return 0;
}

const argv = process.argv.slice(2);
const flags = args(argv);
const command = argv.find((a) => !a.startsWith("--")) ?? "check";

process.exit(
  command === "set"
    ? set(flags)
    : check(Number(flags.days ?? SERVED_FOR_DAYS) || SERVED_FOR_DAYS),
);
