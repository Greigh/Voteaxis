import { afterEach, describe, expect, test } from "bun:test";
import { mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import {
  DEDUPE_LIMIT,
  joinWaitlist,
  parseWaitlistRoles,
  rememberEmail,
  resetWaitlistCache,
  waitlistCount,
} from "../lib/waitlist";

describe("joinWaitlist", () => {
  const prev = process.env.WAITLIST_STORE_PATH;
  const prevSmtp = process.env.SMTP_HOST;
  const prevHook = process.env.WAITLIST_WEBHOOK_URL;

  afterEach(() => {
    if (prev === undefined) delete process.env.WAITLIST_STORE_PATH;
    else process.env.WAITLIST_STORE_PATH = prev;
    if (prevSmtp === undefined) delete process.env.SMTP_HOST;
    else process.env.SMTP_HOST = prevSmtp;
    if (prevHook === undefined) delete process.env.WAITLIST_WEBHOOK_URL;
    else process.env.WAITLIST_WEBHOOK_URL = prevHook;
    resetWaitlistCache();
  });

  test("rejects invalid email", async () => {
    const dir = mkdtempSync(join(tmpdir(), "waitlist-"));
    process.env.WAITLIST_STORE_PATH = join(dir, "waitlist.jsonl");
    const result = await joinWaitlist("not-an-email");
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.status).toBe(400);
  });

  test("stores a new address and treats a second join as already joined", async () => {
    delete process.env.SMTP_HOST;
    delete process.env.WAITLIST_WEBHOOK_URL;
    const dir = mkdtempSync(join(tmpdir(), "waitlist-"));
    const file = join(dir, "waitlist.jsonl");
    process.env.WAITLIST_STORE_PATH = file;
    const first = await joinWaitlist("  Alex@Example.COM ");
    expect(first.ok).toBe(true);
    if (first.ok) expect(first.alreadyJoined).toBe(false);
    const raw = readFileSync(file, "utf8");
    expect(raw).toContain("alex@example.com");
    expect(raw).toContain('"roles":[]');
    expect(await waitlistCount()).toBe(1);
    const again = await joinWaitlist("alex@example.com");
    expect(again.ok).toBe(true);
    if (again.ok) expect(again.alreadyJoined).toBe(true);
  });

  // Regression: reading the known-address set and appending were two separate
  // awaits, so concurrent signups for one address could both see "not present"
  // and both write a row.
  test("concurrent signups for one address write exactly one row", async () => {
    delete process.env.SMTP_HOST;
    delete process.env.WAITLIST_WEBHOOK_URL;
    const dir = mkdtempSync(join(tmpdir(), "waitlist-race-"));
    const file = join(dir, "waitlist.jsonl");
    process.env.WAITLIST_STORE_PATH = file;
    resetWaitlistCache();

    const results = await Promise.all(
      Array.from({ length: 8 }, () => joinWaitlist("race@example.com")),
    );

    expect(results.every((r) => r.ok)).toBe(true);
    const fresh = results.filter((r) => r.ok && !r.alreadyJoined);
    expect(fresh).toHaveLength(1);

    const lines = readFileSync(file, "utf8").trim().split("\n").filter(Boolean);
    expect(lines).toHaveLength(1);
    expect(await waitlistCount()).toBe(1);
  });

  test("the resident dedupe set stays bounded", () => {
    const emails = new Set<string>();
    for (let i = 0; i < DEDUPE_LIMIT + 500; i++) {
      rememberEmail(emails, `user${i}@example.com`);
    }
    expect(emails.size).toBe(DEDUPE_LIMIT);
    // The oldest were evicted; the most recent are still tracked.
    expect(emails.has("user0@example.com")).toBe(false);
    expect(emails.has(`user${DEDUPE_LIMIT + 499}@example.com`)).toBe(true);
  });

  test("an address older than the dedupe window can slip through, count stays right", async () => {
    delete process.env.SMTP_HOST;
    delete process.env.WAITLIST_WEBHOOK_URL;
    const dir = mkdtempSync(join(tmpdir(), "waitlist-cap-"));
    const file = join(dir, "waitlist.jsonl");
    process.env.WAITLIST_STORE_PATH = file;
    resetWaitlistCache();

    const overflow = DEDUPE_LIMIT + 5;
    const seed = Array.from({ length: overflow }, (_, i) =>
      JSON.stringify({
        email: `seed${i}@example.com`,
        createdAt: "2026-01-01T00:00:00.000Z",
        source: "seed",
        roles: [],
      }),
    ).join("\n");
    writeFileSync(file, `${seed}\n`);

    // In the window: recognised as a duplicate, no new row.
    const recent = await joinWaitlist(`seed${overflow - 1}@example.com`);
    expect(recent.ok && recent.alreadyJoined).toBe(true);

    // Evicted from the window: slips through as a fresh signup.
    const ancient = await joinWaitlist("seed0@example.com");
    expect(ancient.ok && !ancient.alreadyJoined).toBe(true);

    // The file grew by one row, but the distinct count is unchanged.
    const lines = readFileSync(file, "utf8").trim().split("\n").filter(Boolean);
    expect(lines).toHaveLength(overflow + 1);
    expect(await waitlistCount()).toBe(overflow);
  });

  test("stores teacher and newsroom roles and ignores unknown values", async () => {
    delete process.env.SMTP_HOST;
    delete process.env.WAITLIST_WEBHOOK_URL;
    const dir = mkdtempSync(join(tmpdir(), "waitlist-"));
    const file = join(dir, "waitlist.jsonl");
    process.env.WAITLIST_STORE_PATH = file;
    const result = await joinWaitlist("teacher@example.com", [
      "teacher",
      "newsroom",
      "cycle_pass",
    ]);
    expect(result.ok).toBe(true);
    const row = JSON.parse(readFileSync(file, "utf8").trim()) as {
      roles: string[];
    };
    expect(row.roles).toEqual(["teacher", "newsroom"]);
  });
});

describe("parseWaitlistRoles", () => {
  test("keeps only teacher and newsroom", () => {
    expect(parseWaitlistRoles(["teacher", "newsroom", "pro"])).toEqual([
      "teacher",
      "newsroom",
    ]);
    expect(parseWaitlistRoles("teacher")).toEqual([]);
    expect(parseWaitlistRoles(undefined)).toEqual([]);
  });
});
