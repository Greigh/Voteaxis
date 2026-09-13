import { describe, expect, test } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import {
  formatScore,
  ISSUE_LABELS,
  isEncrypted,
  labelForScore,
  openedResultFrom,
  PILLARS,
  type ResultResponse,
  railPercent,
  sideColor,
} from "../lib/result";
import { apiUrl } from "../lib/site";

const mobile = join(import.meta.dir, "..", "..", "mobile", "assets", "data");

describe("shared-result vocabulary mirrors the app", () => {
  test("every issue in the app has a label here", () => {
    const ids = (
      JSON.parse(readFileSync(join(mobile, "issues.json"), "utf8")) as {
        id: string;
      }[]
    ).map((issue) => issue.id);
    for (const id of ids) {
      expect(ISSUE_LABELS[id]).toBeString();
    }
    // No labels for issues the app does not have.
    expect(Object.keys(ISSUE_LABELS).sort()).toEqual([...ids].sort());
  });

  test("pillar ids and order match pillars.json", () => {
    const ids = (
      JSON.parse(readFileSync(join(mobile, "pillars.json"), "utf8")) as {
        id: string;
      }[]
    ).map((pillar) => pillar.id);
    expect(PILLARS.map((p) => p.id)).toEqual(ids);
  });
});

describe("formatScore", () => {
  test("no minus signs — the side carries the direction", () => {
    expect(formatScore(-65)).toBe("Liberal 65");
    expect(formatScore(72)).toBe("Conservative 72");
    expect(formatScore(0)).toBe("Center 0");
    // Rounds toward the nearest whole point, like the app.
    expect(formatScore(-42.5)).toBe("Liberal 43");
    expect(formatScore(0.4)).toBe("Center 0");
  });
});

describe("labelForScore", () => {
  test("bands match the app's wording", () => {
    expect(labelForScore(3)).toBe("Centrist");
    expect(labelForScore(-3)).toBe("Centrist");
    expect(labelForScore(-20)).toBe("Slightly liberal");
    expect(labelForScore(40)).toBe("Moderately conservative");
    expect(labelForScore(-60)).toBe("Strongly liberal");
    expect(labelForScore(90)).toBe("Very conservative");
  });
});

describe("railPercent", () => {
  test("maps the axis onto the rail and clamps beyond it", () => {
    expect(railPercent(-100)).toBe(0);
    expect(railPercent(0)).toBe(50);
    expect(railPercent(100)).toBe(100);
    expect(railPercent(-500)).toBe(0);
    expect(railPercent(500)).toBe(100);
  });
});

describe("sideColor", () => {
  test("the dead-centre band is neutral, not blue or red", () => {
    expect(sideColor(-40)).toBe("var(--liberal)");
    expect(sideColor(40)).toBe("var(--conservative)");
    expect(sideColor(0)).toBe("var(--ink-3)");
    expect(sideColor(-4)).toBe("var(--ink-3)");
    expect(sideColor(4)).toBe("var(--ink-3)");
  });
});

describe("isEncrypted", () => {
  test("narrows a sealed envelope away from a readable result", () => {
    const sealed = {
      ok: true,
      id: "a2b3c4d5e6f7g8h9",
      encrypted: true,
      envelope: {
        v: 1,
        kdf: "pbkdf2-sha256",
        iterations: 210000,
        salt: "AAAAAAAAAAAAAAAAAAAAAA==",
        nonce: "AAAAAAAAAAAAAAAA",
        ciphertext: "AAAAAAAAAAAAAAAAAAAAAA==",
      },
      url: "https://voteaxis.org/result/a2b3c4d5e6f7g8h9",
      createdAt: 1,
      expiresAt: 2,
    } satisfies ResultResponse;
    expect(isEncrypted(sealed)).toBe(true);

    const open = { ...sealed, encrypted: false } as unknown as ResultResponse;
    expect(isEncrypted(open)).toBe(false);
  });
});

describe("openedResultFrom", () => {
  const meta = {
    id: "a2b3c4d5e6f7g8h9",
    url: "https://voteaxis.org/result/a2b3c4d5e6f7g8h9",
    createdAt: 1,
    expiresAt: 2,
  };

  test("builds a readable result from a well-formed envelope body", () => {
    const result = openedResultFrom(
      {
        axisScore: -40,
        issueScores: { taxes: -50, climate: -80 },
        issueWeights: { taxes: 2.5 },
        pillarScores: { economy: -55 },
        dealbreakerIssueIds: ["climate"],
        displayName: "Sam",
        homeState: "MI",
        takenAt: 1_760_000_000_000,
      },
      meta,
    );
    expect(result).not.toBeNull();
    expect(result?.axisScore).toBe(-40);
    expect(result?.issueScores.climate).toBe(-80);
    expect(result?.dealbreakerIssueIds).toEqual(["climate"]);
    expect(result?.id).toBe(meta.id);
    expect(result?.encrypted).toBe(false);
  });

  test("rejects a payload the view would have crashed on", () => {
    // Regression: the decrypted body was spread straight into the view, so a
    // missing issueScores threw Object.entries(undefined) mid-render.
    expect(openedResultFrom({}, meta)).toBeNull();
    expect(openedResultFrom({ axisScore: -40 }, meta)).toBeNull();
    expect(
      openedResultFrom({ axisScore: "left", issueScores: { a: 1 } }, meta),
    ).toBeNull();
    expect(
      openedResultFrom({ axisScore: 0, issueScores: {} }, meta),
    ).toBeNull();
    expect(
      openedResultFrom({ axisScore: Number.NaN, issueScores: { a: 1 } }, meta),
    ).toBeNull();
  });

  test("drops non-numeric map entries instead of trusting them", () => {
    const result = openedResultFrom(
      {
        axisScore: 10,
        issueScores: { taxes: 10, junk: "x", nan: Number.POSITIVE_INFINITY },
        dealbreakerIssueIds: ["ok", 5, null],
      },
      meta,
    );
    expect(result?.issueScores).toEqual({ taxes: 10 });
    expect(result?.dealbreakerIssueIds).toEqual(["ok"]);
  });
});

describe("apiUrl", () => {
  test("falls back to the production API and drops a trailing slash", () => {
    const previous = process.env.NEXT_PUBLIC_API_URL;
    delete process.env.NEXT_PUBLIC_API_URL;
    expect(apiUrl()).toBe("https://api.voteaxis.org");

    process.env.NEXT_PUBLIC_API_URL = "http://127.0.0.1:8787/";
    expect(apiUrl()).toBe("http://127.0.0.1:8787");

    if (previous === undefined) delete process.env.NEXT_PUBLIC_API_URL;
    else process.env.NEXT_PUBLIC_API_URL = previous;
  });
});
