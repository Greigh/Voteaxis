import { describe, expect, test } from "bun:test";
import { createBicamClient, seedBicamDb } from "../src/congress";
import {
  billCacheKey,
  congressGovBillType,
  createCongressGovEnricher,
  trimOfficialSummary,
} from "../src/congress-gov";
import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

function seedReceipts() {
  const dir = mkdtempSync(join(tmpdir(), "voteaxis-enrich-"));
  const dbPath = join(dir, "bicam-receipts.sqlite");
  seedBicamDb(dbPath);
  return createBicamClient({ dbPath }).getReceipts("S000033");
}

function scriptedFetch(calls: string[]) {
  return async (url: string) => {
    calls.push(url);
    const path = new URL(url).pathname;
    if (path.endsWith("/summaries")) {
      return new Response(
        JSON.stringify({
          summaries: [
            {
              text: "<p>This bill establishes national health insurance. It also sets a timeline for states. A third leftover sentence.</p>",
            },
          ],
        }),
        { status: 200, headers: { "content-type": "application/json" } },
      );
    }
    if (path.includes("/bill/118/s/1655")) {
      return new Response(
        JSON.stringify({
          bill: {
            latestAction: {
              actionDate: "2023-05-17",
              text: "Read twice and referred to the Committee on Finance.",
            },
          },
        }),
        { status: 200, headers: { "content-type": "application/json" } },
      );
    }
    return new Response("{}", { status: 404 });
  };
}

describe("Congress.gov enricher", () => {
  test("cache keys and LOC bill types", () => {
    expect(billCacheKey(118, "hr", "3590")).toBe("118-HR-3590");
    expect(billCacheKey(118, "S", "1655")).toBe("118-S-1655");
    expect(congressGovBillType("HR")).toBe("hr");
    expect(congressGovBillType("HRES")).toBe("hres");
  });

  test("trims official summaries to two sentences", () => {
    expect(
      trimOfficialSummary(
        "<p>This bill expands Medicare. It also funds clinics. Extra clause stays off-screen.</p>",
      ),
    ).toBe("This bill expands Medicare. It also funds clinics.");
    expect(trimOfficialSummary("   ")).toBeNull();
  });

  test("no API key leaves BICAM receipts unchanged", async () => {
    const receipts = seedReceipts();
    const enricher = createCongressGovEnricher({
      cachePath: ":memory:",
      fetch: async () => {
        throw new Error("Congress.gov should not be called without a key");
      },
    });
    expect(enricher.configured).toBe(false);
    const out = await enricher.enrichReceipts(receipts);
    expect(out.sponsored[0]?.latestAction).toBeNull();
    expect(out.sponsored[0]?.summary).toBeUndefined();
    expect(out.sponsored[0]?.enrichedFrom).toBeUndefined();
    expect(out.source).toBe("bicam.net");
  });

  test("hydrates latestAction and summary from scripted Congress.gov", async () => {
    const calls: string[] = [];
    const enricher = createCongressGovEnricher({
      apiKey: "test-key",
      cachePath: ":memory:",
      fetch: scriptedFetch(calls),
    });
    const out = await enricher.enrichReceipts(seedReceipts());
    const bill = out.sponsored[0];
    expect(bill?.latestAction).toBe(
      "2023-05-17 — Read twice and referred to the Committee on Finance.",
    );
    expect(bill?.summary).toBe(
      "This bill establishes national health insurance. It also sets a timeline for states.",
    );
    expect(bill?.enrichedFrom).toBe("congress.gov");
    expect(out.source).toBe("bicam.net");
    expect(calls).toHaveLength(2);
    expect(calls[0]).toContain("api_key=test-key");
    expect(calls.some((url) => url.includes("/v3/bill/118/s/1655"))).toBe(true);
    expect(calls.some((url) => url.includes("/summaries"))).toBe(true);
  });

  test("cache avoids a second live hit within TTL", async () => {
    const calls: string[] = [];
    const enricher = createCongressGovEnricher({
      apiKey: "test-key",
      cachePath: ":memory:",
      fetch: scriptedFetch(calls),
    });
    const first = await enricher.enrichReceipts(seedReceipts());
    const second = await enricher.enrichReceipts(seedReceipts());
    expect(first.sponsored[0]?.latestAction).toBe(
      second.sponsored[0]?.latestAction,
    );
    expect(calls).toHaveLength(2);
  });

  test("expired cache refetches", async () => {
    const calls: string[] = [];
    let now = 1_000;
    const enricher = createCongressGovEnricher({
      apiKey: "test-key",
      cachePath: ":memory:",
      ttlMs: 100,
      now: () => now,
      fetch: scriptedFetch(calls),
    });
    await enricher.enrichReceipts(seedReceipts());
    now = 1_200;
    await enricher.enrichReceipts(seedReceipts());
    expect(calls).toHaveLength(4);
  });
});
