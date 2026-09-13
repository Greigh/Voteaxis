const KEY = /^[a-z][a-z0-9_]{0,39}$/;
const MAX_ISSUES = 40;

function isScore(n: unknown): n is number {
  return typeof n === "number" && Number.isFinite(n) && n >= -100 && n <= 100;
}

function scoreMap(value: unknown, label: string): Record<string, number> | string {
  if (value == null) return {};
  if (typeof value !== "object" || Array.isArray(value)) {
    return `${label} must be an object.`;
  }
  const out: Record<string, number> = {};
  const entries = Object.entries(value as Record<string, unknown>);
  if (entries.length > MAX_ISSUES) return `${label} has too many keys.`;
  for (const [k, v] of entries) {
    if (!KEY.test(k)) return `Invalid ${label} key.`;
    // Strictly a JSON number. Coercing meant `null`, `[]`, `false`, and `""`
    // all arrived as a silent 0 and were stored as a real score.
    if (!isScore(v)) return `Invalid ${label} value.`;
    out[k] = v;
  }
  return out;
}

export type FriendPayload = {
  displayName: string;
  axisScore: number;
  issueScores: Record<string, number>;
  issueWeights: Record<string, number>;
  pillarScores: Record<string, number>;
  dealbreakerIssueIds: string[];
};

export function parsePayload(body: unknown): FriendPayload | string {
  if (typeof body !== "object" || body === null || Array.isArray(body)) {
    return "Invalid body.";
  }
  const raw = body as Record<string, unknown>;
  // Strictly a JSON number, for the same reason as scoreMap: `Number(null)` is
  // 0, which would have passed the range check as a legitimate centre score.
  const axis = raw.axisScore;
  if (!isScore(axis)) return "axisScore must be between -100 and 100.";

  const issueScores = scoreMap(raw.issueScores, "issueScores");
  if (typeof issueScores === "string") return issueScores;
  if (Object.keys(issueScores).length < 1) return "issueScores is required.";

  const issueWeights = scoreMap(raw.issueWeights, "issueWeights");
  if (typeof issueWeights === "string") return issueWeights;

  const pillarScores = scoreMap(raw.pillarScores, "pillarScores");
  if (typeof pillarScores === "string") return pillarScores;

  let displayName = "";
  if (raw.displayName != null) {
    if (typeof raw.displayName !== "string") return "displayName must be a string.";
    displayName = raw.displayName.trim().slice(0, 40);
  }

  const dealbreakerIssueIds: string[] = [];
  if (raw.dealbreakerIssueIds != null) {
    if (!Array.isArray(raw.dealbreakerIssueIds)) {
      return "dealbreakerIssueIds must be an array.";
    }
    if (raw.dealbreakerIssueIds.length > 3) {
      return "At most 3 dealbreakers.";
    }
    for (const id of raw.dealbreakerIssueIds) {
      if (typeof id !== "string" || !KEY.test(id)) {
        return "Invalid dealbreaker id.";
      }
      dealbreakerIssueIds.push(id);
    }
  }

  return {
    displayName,
    axisScore: axis,
    issueScores,
    issueWeights,
    pillarScores,
    dealbreakerIssueIds,
  };
}
