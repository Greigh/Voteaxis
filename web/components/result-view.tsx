"use client";

import { useState } from "react";
import { isEnvelope, MIN_PASSWORD_LENGTH, openEnvelope } from "@/lib/envelope";
import {
  formatScore,
  ISSUE_LABELS,
  isEncrypted,
  labelForScore,
  openedResultFrom,
  PILLARS,
  type ResultResponse,
  railPercent,
  type SharedResult,
  sideColor,
} from "@/lib/result";
import styles from "./result-view.module.css";

/**
 * Renders a shared result, or the password gate in front of it.
 *
 * A protected result arrives as ciphertext the Voteaxis server cannot read.
 * Everything below happens in this browser: the password types the key, and a
 * failed AES-GCM tag is what says "wrong password". Nothing about the attempt
 * is sent anywhere, which is also why nobody can reset it for you.
 */
export function ResultView({ initial }: { initial: ResultResponse }) {
  const [opened, setOpened] = useState<SharedResult | null>(
    isEncrypted(initial) ? null : initial,
  );
  const [password, setPassword] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  async function unlock(event: React.FormEvent) {
    event.preventDefault();
    if (busy || !isEncrypted(initial)) return;
    const entered = password.trim();
    if (entered === "") return;
    setBusy(true);
    setError(null);
    // Let the browser paint the busy state before the KDF blocks the thread.
    await new Promise((resolve) => setTimeout(resolve, 0));
    try {
      const body = await openEnvelope(initial.envelope, entered);
      if (!body) {
        setError("That password is not right.");
        return;
      }
      const result = openedResultFrom(body, {
        id: initial.id,
        url: initial.url,
        createdAt: initial.createdAt,
        expiresAt: initial.expiresAt,
      });
      if (!result) {
        setError("The link opened, but its contents could not be read.");
        return;
      }
      setOpened(result);
    } catch {
      setError("This browser could not decrypt the link.");
    } finally {
      setBusy(false);
    }
  }

  // An envelope this build will not run — a version it does not know, or a
  // KDF cost outside the range a reader should be asked to pay. Say so instead
  // of showing a password box that can only ever answer "wrong password".
  if (!opened && isEncrypted(initial) && !isEnvelope(initial.envelope)) {
    return (
      <div className={styles.gate}>
        <h2 className={styles.gateTitle}>This link cannot be opened here</h2>
        <p className={styles.gateBody}>
          It was sealed in a format this page does not support. Ask whoever sent
          it to share a fresh link from a current version of the app.
        </p>
      </div>
    );
  }

  if (!opened) {
    return (
      <form className={styles.gate} onSubmit={unlock}>
        <h2 className={styles.gateTitle}>This result is encrypted</h2>
        <p className={styles.gateBody}>
          Whoever sent you this link set a password on it, and the result was
          encrypted on their phone before it was uploaded. Ask them for the
          password — nobody at Voteaxis can read this page or recover it.
        </p>
        <label className={styles.label} htmlFor="result-password">
          Password
        </label>
        <input
          id="result-password"
          className={styles.input}
          type="password"
          autoComplete="off"
          minLength={MIN_PASSWORD_LENGTH}
          value={password}
          onChange={(e) => setPassword(e.target.value)}
        />
        {error ? (
          <p className={styles.error} role="alert">
            {error}
          </p>
        ) : null}
        <button className={styles.button} type="submit" disabled={busy}>
          {busy ? "Decrypting…" : "Open result"}
        </button>
      </form>
    );
  }

  return <Result result={opened} />;
}

function Result({ result }: { result: SharedResult }) {
  const issues = Object.entries(result.issueScores).sort(
    (a, b) => Math.abs(b[1]) - Math.abs(a[1]),
  );
  const dealbreakers = result.dealbreakerIssueIds
    .map((id) => ISSUE_LABELS[id] ?? id)
    .filter(Boolean);

  return (
    <div className={styles.result}>
      <section className={styles.axis}>
        <p className={styles.eyebrow}>OVERALL PLACEMENT</p>
        <p
          className={styles.axisScore}
          style={{ color: sideColor(result.axisScore) }}
        >
          {formatScore(result.axisScore)}
        </p>
        <p className={styles.axisLabel}>{labelForScore(result.axisScore)}</p>
        <div className={styles.rail}>
          <span
            className={styles.marker}
            style={{ left: `${railPercent(result.axisScore)}%` }}
          />
        </div>
        <div className={styles.railEnds}>
          <span>Liberal 100</span>
          <span>0</span>
          <span>Conservative 100</span>
        </div>
      </section>

      <section className={styles.block}>
        <h2 className={styles.blockTitle}>Five pillars</h2>
        <ul className={styles.bars}>
          {PILLARS.map((pillar) => {
            const score = result.pillarScores[pillar.id];
            if (score === undefined) return null;
            return (
              <li className={styles.bar} key={pillar.id}>
                <div className={styles.barHead}>
                  <span className={styles.barLabel}>{pillar.label}</span>
                  <span
                    className={styles.barValue}
                    style={{ color: sideColor(score) }}
                  >
                    {formatScore(score)}
                  </span>
                </div>
                <div className={styles.track}>
                  <span
                    className={styles.dot}
                    style={{
                      left: `${railPercent(score)}%`,
                      background: sideColor(score),
                    }}
                  />
                </div>
              </li>
            );
          })}
        </ul>
      </section>

      {dealbreakers.length > 0 ? (
        <section className={styles.block}>
          <h2 className={styles.blockTitle}>Dealbreakers</h2>
          <p className={styles.blockBody}>
            Issues they will not compromise on: {dealbreakers.join(", ")}.
          </p>
        </section>
      ) : null}

      <section className={styles.block}>
        <h2 className={styles.blockTitle}>Issue by issue</h2>
        <ul className={styles.issues}>
          {issues.map(([id, score]) => (
            <li className={styles.issue} key={id}>
              <span className={styles.issueLabel}>
                {ISSUE_LABELS[id] ?? id}
              </span>
              <span
                className={styles.issueScore}
                style={{ color: sideColor(score) }}
              >
                {formatScore(score)}
              </span>
            </li>
          ))}
        </ul>
      </section>
    </div>
  );
}
