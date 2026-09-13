/**
 * Shape of a shared result as the API returns it, plus the small amount of
 * scoring vocabulary the page needs. Mirrors mobile/lib/models/scoring.dart —
 * scores are Liberal 100 ← 0 → Conservative 100 with no minus signs shown.
 */

import type { EncryptedEnvelope } from "./envelope";

export type SharedResult = {
  ok: true;
  id: string;
  encrypted: false;
  url: string;
  createdAt: number;
  expiresAt: number;
  displayName: string;
  label: string;
  axisScore: number;
  issueScores: Record<string, number>;
  issueWeights: Record<string, number>;
  pillarScores: Record<string, number>;
  dealbreakerIssueIds: string[];
  homeState: string | null;
  takenAt: number | null;
};

/**
 * A password-protected result as it arrives: a sealed envelope and nothing
 * else. The server cannot open it, so neither can this page until the reader
 * supplies the password.
 */
export type EncryptedResult = {
  ok: true;
  id: string;
  encrypted: true;
  envelope: EncryptedEnvelope;
  url: string;
  createdAt: number;
  expiresAt: number;
};

export type ResultResponse = SharedResult | EncryptedResult;

export function isEncrypted(result: ResultResponse): result is EncryptedResult {
  return result.encrypted === true;
}

function finiteNumber(value: unknown): number | null {
  return typeof value === "number" && Number.isFinite(value) ? value : null;
}

function numberMap(value: unknown): Record<string, number> {
  if (!value || typeof value !== "object" || Array.isArray(value)) return {};
  const out: Record<string, number> = {};
  for (const [key, raw] of Object.entries(value as Record<string, unknown>)) {
    if (typeof raw === "number" && Number.isFinite(raw)) out[key] = raw;
  }
  return out;
}

/**
 * The plaintext inside a decrypted envelope carries the same fields an open
 * link returns inline — but it was sealed on someone else's device, so the
 * reader validates the shape before the view trusts it. A malformed payload
 * returns null (handled as "could not read") rather than throwing mid-render.
 */
export function openedResultFrom(
  body: Record<string, unknown>,
  meta: { id: string; url: string; createdAt: number; expiresAt: number },
): SharedResult | null {
  const axisScore = finiteNumber(body.axisScore);
  if (axisScore === null) return null;

  const issueScores = numberMap(body.issueScores);
  if (Object.keys(issueScores).length === 0) return null;

  return {
    ok: true,
    encrypted: false,
    id: meta.id,
    url: meta.url,
    createdAt: meta.createdAt,
    expiresAt: meta.expiresAt,
    displayName: typeof body.displayName === "string" ? body.displayName : "",
    label: typeof body.label === "string" ? body.label : "",
    axisScore,
    issueScores,
    issueWeights: numberMap(body.issueWeights),
    pillarScores: numberMap(body.pillarScores),
    dealbreakerIssueIds: Array.isArray(body.dealbreakerIssueIds)
      ? body.dealbreakerIssueIds.filter(
          (id): id is string => typeof id === "string",
        )
      : [],
    homeState: typeof body.homeState === "string" ? body.homeState : null,
    takenAt: finiteNumber(body.takenAt),
  };
}

/** Mirrors mobile/assets/data/pillars.json. */
export const PILLARS: { id: string; label: string }[] = [
  { id: "economy", label: "Economy & fiscal" },
  { id: "society", label: "Rights & society" },
  { id: "health", label: "Health & entitlements" },
  { id: "justice", label: "Justice & homeland" },
  { id: "world", label: "Climate, energy & world" },
];

/** Mirrors mobile/assets/data/issues.json. */
export const ISSUE_LABELS: Record<string, string> = {
  jobs: "Jobs & the economy",
  taxes: "Taxes & spending",
  deficit: "Budget deficit",
  inflation: "Inflation & prices",
  free_market: "Free markets vs regulation",
  welfare: "Welfare & safety net",
  abortion: "Abortion",
  civil_rights: "Civil rights & liberties",
  lgbtq: "LGBTQ rights",
  education: "Education",
  traditional_values: "Traditional values",
  healthcare: "Health care",
  medicare: "Medicare",
  social_security: "Social Security",
  crime: "Crime & criminal justice",
  gun_control: "Gun control",
  immigration: "Immigration & border",
  climate: "Climate & environment",
  energy: "Energy",
  foreign_policy: "Foreign policy",
  terrorism: "Terrorism",
  military: "Military & defense",
};

export function formatScore(score: number): string {
  const abs = Math.round(Math.abs(score));
  if (abs === 0) return "Center 0";
  return score < 0 ? `Liberal ${abs}` : `Conservative ${abs}`;
}

export function labelForScore(score: number): string {
  const abs = Math.abs(score);
  if (abs < 8) return "Centrist";
  const side = score < 0 ? "liberal" : "conservative";
  if (abs < 25) return `Slightly ${side}`;
  if (abs < 50) return `Moderately ${side}`;
  if (abs < 75) return `Strongly ${side}`;
  return `Very ${side}`;
}

/** 0 at Liberal 100, 100 at Conservative 100 — the position along the rail. */
export function railPercent(score: number): number {
  const clamped = Math.max(-100, Math.min(100, score));
  return ((clamped + 100) / 200) * 100;
}

export function sideColor(score: number): string {
  if (score < -4) return "var(--liberal)";
  if (score > 4) return "var(--conservative)";
  return "var(--ink-3)";
}
