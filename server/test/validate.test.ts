import { describe, expect, test } from "bun:test";
import { parsePayload } from "../src/validate";

describe("parsePayload", () => {
  test("accepts a compact friend profile", () => {
    const parsed = parsePayload({
      displayName: "  Alex  ",
      axisScore: -42,
      issueScores: { taxes: -50 },
      issueWeights: { taxes: 2.5 },
      pillarScores: { economy: -50 },
      dealbreakerIssueIds: ["abortion"],
    });
    expect(typeof parsed).not.toBe("string");
    if (typeof parsed === "string") return;
    expect(parsed.displayName).toBe("Alex");
    expect(parsed.axisScore).toBe(-42);
    expect(parsed.dealbreakerIssueIds).toEqual(["abortion"]);
  });

  test("rejects out-of-range axis scores", () => {
    expect(parsePayload({ axisScore: 101, issueScores: { taxes: 0 } })).toBe(
      "axisScore must be between -100 and 100.",
    );
  });

  test("requires at least one issue score", () => {
    expect(parsePayload({ axisScore: 0, issueScores: {} })).toBe(
      "issueScores is required.",
    );
  });

  test("caps dealbreakers at three", () => {
    expect(
      parsePayload({
        axisScore: 0,
        issueScores: { taxes: 0 },
        dealbreakerIssueIds: ["a", "b", "c", "d"],
      }),
    ).toBe("At most 3 dealbreakers.");
  });

  test("rejects invalid issue keys", () => {
    expect(
      parsePayload({
        axisScore: 0,
        issueScores: { "Taxes!": 0 },
      }),
    ).toBe("Invalid issueScores key.");
  });

  // Regression: values used to go through Number(), so each of these coerced
  // to 0 and was stored as a legitimate centre-of-the-axis score.
  test("rejects non-numeric scores instead of coercing them to 0", () => {
    for (const bad of [null, [], false, "", "0", {}]) {
      expect(
        parsePayload({ axisScore: 0, issueScores: { taxes: bad } }),
      ).toBe("Invalid issueScores value.");
    }
  });

  test("rejects a non-numeric axisScore instead of coercing it", () => {
    for (const bad of [null, [], false, "", "0", undefined]) {
      expect(parsePayload({ axisScore: bad, issueScores: { taxes: 0 } })).toBe(
        "axisScore must be between -100 and 100.",
      );
    }
  });

  test("still accepts genuine numeric edges", () => {
    const parsed = parsePayload({
      axisScore: 0,
      issueScores: { taxes: -100, guns: 100 },
    });
    expect(typeof parsed).not.toBe("string");
    if (typeof parsed === "string") return;
    expect(parsed.issueScores).toEqual({ taxes: -100, guns: 100 });
  });
});
