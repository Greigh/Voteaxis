import { Database } from "bun:sqlite";
import { mkdirSync } from "node:fs";
import { dirname } from "node:path";
import type { ReceiptBill, Receipts } from "./congress";

export const DEFAULT_ENRICH_TTL_MS = 18 * 60 * 60 * 1000;
export const VISIBLE_RECEIPT_LIMIT = 5;

export type EnricherFetch = (
  input: string,
  init?: RequestInit,
) => Promise<Response>;

export type BillEnrichment = {
  latestAction: string | null;
  summary: string | null;
};

export type CongressGovEnricher = {
  configured: boolean;
  enrichReceipts: (receipts: Receipts) => Promise<Receipts>;
};

type CacheRow = {
  latest_action: string | null;
  summary: string | null;
  fetched_at: number;
};

export function billCacheKey(
  congress: number,
  type: string,
  number: string,
): string {
  const digits = String(number).replace(/\D/g, "") || String(number);
  return `${congress}-${type.toUpperCase()}-${digits}`;
}

export function congressGovBillType(type: string): string {
  return type.toLowerCase();
}

export function trimOfficialSummary(raw: string, sentences = 2): string | null {
  const text = raw
    .replace(/<[^>]+>/g, " ")
    .replace(/&nbsp;/gi, " ")
    .replace(/&amp;/gi, "&")
    .replace(/&lt;/gi, "<")
    .replace(/&gt;/gi, ">")
    .replace(/&#39;|&apos;/gi, "'")
    .replace(/&quot;/gi, '"')
    .replace(/\s+/g, " ")
    .trim();
  if (!text) return null;
  const parts = text.match(/[^.!?]+[.!?]+(?:["')\]]+)?|[^.!?]+$/g) ?? [text];
  const clipped = parts
    .map((part) => part.trim())
    .filter(Boolean)
    .slice(0, Math.max(1, sentences))
    .join(" ")
    .trim();
  return clipped || null;
}

function parseLatestAction(body: unknown): string | null {
  if (!body || typeof body !== "object") return null;
  const action = (body as { bill?: { latestAction?: unknown } }).bill
    ?.latestAction;
  if (!action || typeof action !== "object") return null;
  const text = (action as { text?: unknown }).text;
  if (typeof text !== "string" || !text.trim()) return null;
  const date = (action as { actionDate?: unknown }).actionDate;
  const trimmed = text.trim();
  return typeof date === "string" && date.trim()
    ? `${date.trim()} — ${trimmed}`
    : trimmed;
}

function parseSummary(body: unknown): string | null {
  if (!body || typeof body !== "object") return null;
  const summaries = (body as { summaries?: unknown }).summaries;
  if (!Array.isArray(summaries)) return null;
  for (const item of summaries) {
    if (!item || typeof item !== "object") continue;
    const text = (item as { text?: unknown }).text;
    if (typeof text !== "string") continue;
    const trimmed = trimOfficialSummary(text);
    if (trimmed) return trimmed;
  }
  return null;
}

function applyEnrichment(
  bill: ReceiptBill,
  hit: BillEnrichment | null,
): ReceiptBill {
  if (!hit) return bill;
  const latestAction = hit.latestAction ?? bill.latestAction;
  const filled = Boolean(hit.latestAction || hit.summary);
  return {
    ...bill,
    latestAction,
    ...(hit.summary ? { summary: hit.summary } : {}),
    ...(filled ? { enrichedFrom: "congress.gov" as const } : {}),
  };
}

export function createCongressGovEnricher(opts: {
  apiKey?: string | null;
  cachePath: string;
  ttlMs?: number;
  visibleLimit?: number;
  fetch?: EnricherFetch;
  now?: () => number;
}): CongressGovEnricher {
  const apiKey = opts.apiKey?.trim() || "";
  const ttlMs = opts.ttlMs ?? DEFAULT_ENRICH_TTL_MS;
  const visibleLimit = opts.visibleLimit ?? VISIBLE_RECEIPT_LIMIT;
  const fetchFn = opts.fetch ?? fetch;
  const now = opts.now ?? Date.now;
  let db: Database | null = null;

  const open = (): Database => {
    if (db) return db;
    if (opts.cachePath !== ":memory:") {
      mkdirSync(dirname(opts.cachePath), { recursive: true });
    }
    db = new Database(opts.cachePath);
    db.exec(`
      CREATE TABLE IF NOT EXISTS enrichments (
        bill_key TEXT PRIMARY KEY,
        latest_action TEXT,
        summary TEXT,
        fetched_at INTEGER NOT NULL
      );
    `);
    return db;
  };

  const readCache = (key: string): BillEnrichment | null => {
    const row = open()
      .query(
        "SELECT latest_action, summary, fetched_at FROM enrichments WHERE bill_key = ?",
      )
      .get(key) as CacheRow | null;
    if (!row || row.fetched_at + ttlMs <= now()) return null;
    return {
      latestAction: row.latest_action,
      summary: row.summary,
    };
  };

  const writeCache = (key: string, hit: BillEnrichment): void => {
    open()
      .query(
        `INSERT OR REPLACE INTO enrichments (bill_key, latest_action, summary, fetched_at)
         VALUES (?, ?, ?, ?)`,
      )
      .run(key, hit.latestAction, hit.summary, now());
  };

  const locUrl = (bill: ReceiptBill, suffix = ""): string => {
    const type = congressGovBillType(bill.type);
    const number = String(bill.number).replace(/\D/g, "") || bill.number;
    const url = new URL(
      `https://api.congress.gov/v3/bill/${bill.congress}/${type}/${number}${suffix}`,
    );
    url.searchParams.set("api_key", apiKey);
    url.searchParams.set("format", "json");
    return url.toString();
  };

  const getJson = async (url: string): Promise<unknown | null> => {
    try {
      const res = await fetchFn(url, {
        headers: {
          accept: "application/json",
          "user-agent": "voteaxis-api (congress.gov enricher)",
        },
        signal: AbortSignal.timeout(8000),
      });
      if (!res.ok) return null;
      return await res.json();
    } catch {
      return null;
    }
  };

  const fetchFresh = async (bill: ReceiptBill): Promise<BillEnrichment | null> => {
    const [billBody, summaryBody] = await Promise.all([
      getJson(locUrl(bill)),
      getJson(locUrl(bill, "/summaries")),
    ]);
    if (!billBody && !summaryBody) return null;
    return {
      latestAction: parseLatestAction(billBody),
      summary: parseSummary(summaryBody),
    };
  };

  const enrichBill = async (bill: ReceiptBill): Promise<ReceiptBill> => {
    const key = billCacheKey(bill.congress, bill.type, bill.number);
    const cached = readCache(key);
    if (cached) return applyEnrichment(bill, cached);
    const fresh = await fetchFresh(bill);
    if (fresh) writeCache(key, fresh);
    return applyEnrichment(bill, fresh);
  };

  const enrichList = async (bills: ReceiptBill[]): Promise<ReceiptBill[]> => {
    const head = bills.slice(0, visibleLimit);
    const tail = bills.slice(visibleLimit);
    const enriched = await Promise.all(head.map(enrichBill));
    return [...enriched, ...tail];
  };

  return {
    get configured() {
      return Boolean(apiKey);
    },
    async enrichReceipts(receipts) {
      if (!apiKey) return receipts;
      try {
        const [sponsored, cosponsored] = await Promise.all([
          enrichList(receipts.sponsored),
          enrichList(receipts.cosponsored),
        ]);
        return { ...receipts, sponsored, cosponsored };
      } catch {
        return receipts;
      }
    },
  };
}
