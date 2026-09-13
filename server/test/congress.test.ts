import { describe, expect, test } from "bun:test";
import { existsSync, mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import {
  billPageUrl,
  congressOrdinal,
  createBicamClient,
  seedBicamDb,
} from "../src/congress";

describe("BICAM receipts helpers", () => {
  test("ordinal and bill URLs", () => {
    expect(congressOrdinal(118)).toBe("118th");
    expect(congressOrdinal(121)).toBe("121st");
    expect(billPageUrl(118, "S", "1655")).toBe(
      "https://www.congress.gov/bill/118th-congress/senate-bill/1655",
    );
    expect(billPageUrl(116, "HRES", "109")).toBe(
      "https://www.congress.gov/bill/116th-congress/house-resolution/109",
    );
  });

  test("sqlite client returns sponsored bills", () => {
    const dir = mkdtempSync(join(tmpdir(), "voteaxis-bicam-"));
    const dbPath = join(dir, "bicam-receipts.sqlite");
    seedBicamDb(dbPath);
    const client = createBicamClient({ dbPath });
    expect(client.configured).toBe(true);
    const receipts = client.getReceipts("s000033");
    expect(receipts.source).toBe("bicam.net");
    expect(receipts.name).toBe("Bernard Sanders");
    expect(receipts.sponsored).toHaveLength(1);
    expect(receipts.sponsored[0]?.number).toBe("1655");
    expect(receipts.sponsored[0]?.url).toContain("senate-bill/1655");
  });

  test("python sync indexes fixture CSVs", () => {
    const dir = mkdtempSync(join(tmpdir(), "voteaxis-bicam-sync-"));
    const dbPath = join(dir, "bicam-receipts.sqlite");
    const result = Bun.spawnSync({
      cmd: [
        "python3",
        join(import.meta.dir, "..", "scripts", "sync_bicam.py"),
        "--from-dir",
        join(import.meta.dir, "fixtures", "bicam"),
        "--db",
        dbPath,
        "--min-congress",
        "116",
      ],
    });
    if (result.exitCode !== 0) {
      throw new Error(result.stderr.toString() || result.stdout.toString());
    }
    const client = createBicamClient({ dbPath });
    const sanders = client.getReceipts("S000033");
    expect(sanders.sponsored[0]?.title).toBe("Medicare for All Act");
    expect(sanders.sponsored.every((bill) => bill.congress >= 116)).toBe(true);
    const aoc = client.getReceipts("O000172");
    expect(aoc.sponsored[0]?.type).toBe("HRES");
    expect(aoc.cosponsored[0]?.number).toBe("1655");
    expect(client.member("O000172")?.party).toBe("Democratic");
    expect(client.member("O000172")?.district).toBe("14");
  });
});

const liveDb = join(import.meta.dir, "..", "data", "bicam-receipts.sqlite");
if (existsSync(liveDb)) {
  describe("live BICAM index", () => {
    test("Sanders receipts load from sqlite", () => {
      const client = createBicamClient({ dbPath: liveDb });
      expect(client.configured).toBe(true);
      const meta = client.meta();
      expect(meta.members).toBeGreaterThan(1000);
      const receipts = client.getReceipts("S000033");
      expect(receipts.name).toContain("Sanders");
      expect(receipts.sponsored.length).toBeGreaterThan(0);
      expect(receipts.sponsored[0]?.url).toContain("congress.gov/bill/");
    });
  });
}
