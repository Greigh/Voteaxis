#!/usr/bin/env bun
/**
 * List waitlist signups from data/waitlist.jsonl (local / self-hosted).
 * Usage: bun run waitlist:list
 */
import { readFile } from "node:fs/promises";
import path from "node:path";

const store = path.join(process.cwd(), "data", "waitlist.jsonl");

try {
  const raw = await readFile(store, "utf8");
  const rows = raw
    .split("\n")
    .filter(Boolean)
    .map(
      (line) =>
        JSON.parse(line) as {
          email: string;
          createdAt: string;
          roles?: string[];
        },
    );
  console.log(`${rows.length} signup(s)\n`);
  for (const row of rows) {
    const roles =
      row.roles && row.roles.length > 0 ? `\t${row.roles.join(",")}` : "";
    console.log(`${row.createdAt}\t${row.email}${roles}`);
  }
} catch {
  console.log("No waitlist file yet. Signups will create data/waitlist.jsonl");
}
