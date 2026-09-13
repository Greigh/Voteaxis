import { isAbsolute, join } from "node:path";
import {
  createApp,
  MAX_REQUEST_BODY_BYTES,
  politiciansFile,
  resolveHost,
  weekFile,
} from "./app";
import { createBicamClient } from "./congress";
import { createCongressGovEnricher } from "./congress-gov";
import { Store } from "./store";

const root = join(import.meta.dir, "..");

function resolvePath(value: string): string {
  if (value === ":memory:" || isAbsolute(value)) return value;
  return join(root, value);
}

const port = Number(process.env.PORT ?? 8787);
const dataDir = resolvePath(process.env.DATA_DIR?.trim() || "data");
const ttlHours = Number(process.env.CODE_TTL_HOURS ?? 48);
const store = new Store(join(dataDir, "voteaxis.db"), {
  autoSweepMs: 10 * 60 * 1000,
});
const bicam = createBicamClient({
  dbPath: resolvePath(
    process.env.BICAM_DB?.trim() || join(dataDir, "bicam-receipts.sqlite"),
  ),
});
const enricher = createCongressGovEnricher({
  apiKey: process.env.CONGRESS_API_KEY,
  cachePath: resolvePath(
    process.env.CONGRESS_CACHE?.trim() ||
      join(dataDir, "congress-gov-cache.sqlite"),
  ),
});
const politiciansApiKey = process.env.POLITICIANS_API_KEY?.trim() || undefined;
const politiciansAllowDeviceTokens =
  process.env.POLITICIANS_ALLOW_DEVICE_TOKENS?.trim().toLowerCase() === "true";
const app = createApp({
  store,
  ttlMs: Math.max(1, ttlHours) * 60 * 60 * 1000,
  weekPath: weekFile(),
  politiciansPath: politiciansFile(),
  politiciansApiKey,
  politiciansAllowDeviceTokens,
  bicam,
  enricher,
});

Bun.serve({
  port,
  // Loopback by default so the unsafe case is the one you have to ask for.
  // scripts/deploy.py pins this to 127.0.0.1 on the box regardless.
  hostname: resolveHost(),
  // Backstop for a chunked body app.ts's tooLarge() cannot see — see the
  // constant's doc comment.
  maxRequestBodySize: MAX_REQUEST_BODY_BYTES,
  fetch: (req) => app.fetch(req),
});

const congressNote = bicam.configured
  ? " (congress ready)"
  : " (congress index missing — run scripts/sync_bicam.py)";
const enrichNote = enricher.configured ? " (congress.gov enricher)" : "";
const politiciansAccess = [
  politiciansApiKey && "key",
  politiciansAllowDeviceTokens && "device tokens",
]
  .filter(Boolean)
  .join(" + ");
const politiciansNote = politiciansAccess
  ? ` (politicians: ${politiciansAccess})`
  : " (politicians: locked — set POLITICIANS_API_KEY or POLITICIANS_ALLOW_DEVICE_TOKENS=true)";
console.log(
  `voteaxis-api listening on :${port}${congressNote}${enrichNote}${politiciansNote}`,
);
