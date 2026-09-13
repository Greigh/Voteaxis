"use client";

import { useState } from "react";
import {
  CONTRIBUTE_OFFERS,
  type ContributeSku,
  DEFAULT_CONTRIBUTE_SKU,
} from "@/lib/contribute";
import styles from "./contribute.module.css";

const ONE_TIME = CONTRIBUTE_OFFERS.filter((row) => row.mode === "payment");
const SUSTAINER = CONTRIBUTE_OFFERS.find((row) => row.mode === "subscription");

export function ContributeForm() {
  const [sku, setSku] = useState<ContributeSku>(DEFAULT_CONTRIBUTE_SKU);
  const [status, setStatus] = useState<"idle" | "loading" | "error">("idle");
  const [message, setMessage] = useState("");

  const selected = CONTRIBUTE_OFFERS.find((row) => row.sku === sku);

  async function onSubmit() {
    setStatus("loading");
    setMessage("");
    try {
      const res = await fetch("/api/contribute/checkout", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ sku }),
      });
      const data = (await res.json()) as {
        ok?: boolean;
        url?: string;
        error?: string;
      };
      if (!res.ok || !data.ok || !data.url) {
        setStatus("error");
        setMessage(
          data.error ??
            "Checkout isn’t available right now. Email hello@voteaxis.org.",
        );
        return;
      }
      window.location.assign(data.url);
    } catch {
      setStatus("error");
      setMessage("Network error. Check your connection and try again.");
    }
  }

  return (
    <div className={styles.form}>
      <p className={styles.scaleKicker}>One-time</p>
      <div
        className={styles.scale}
        role="radiogroup"
        aria-label="One-time contribution amount"
      >
        <div className={styles.scaleTrack} aria-hidden="true">
          {ONE_TIME.map((offer) => (
            <i
              key={offer.sku}
              className={
                sku === offer.sku ? styles.scaleTickOn : styles.scaleTick
              }
            />
          ))}
        </div>
        <div className={styles.scaleOptions}>
          {ONE_TIME.map((offer) => {
            const selectedOffer = sku === offer.sku;
            return (
              <label
                key={offer.sku}
                className={selectedOffer ? styles.amountOn : styles.amount}
              >
                <input
                  type="radio"
                  name="contribute-sku"
                  value={offer.sku}
                  checked={selectedOffer}
                  onChange={() => setSku(offer.sku)}
                />
                <span className={styles.amountLabel}>{offer.label}</span>
                <span className={styles.amountBlurb}>{offer.blurb}</span>
              </label>
            );
          })}
        </div>
      </div>

      {SUSTAINER ? (
        <label
          className={
            sku === SUSTAINER.sku ? styles.sustainerOn : styles.sustainer
          }
        >
          <input
            type="radio"
            name="contribute-sku"
            value={SUSTAINER.sku}
            checked={sku === SUSTAINER.sku}
            onChange={() => setSku(SUSTAINER.sku)}
          />
          <span>
            <span className={styles.sustainerKicker}>Sustainer</span>
            <span className={styles.amountLabel}>{SUSTAINER.label}</span>
            <span className={styles.amountBlurb}>{SUSTAINER.blurb}</span>
          </span>
        </label>
      ) : null}

      <button
        type="button"
        className={styles.submit}
        onClick={onSubmit}
        disabled={status === "loading"}
      >
        {status === "loading"
          ? "Opening Stripe…"
          : `Continue to Stripe · ${selected?.label ?? ""}`}
      </button>
      {status === "error" ? (
        <p className={styles.error} role="alert">
          {message}
        </p>
      ) : null}
      <p className={styles.fine}>
        Stripe handles the card. Voteaxis never sees it. This does not unlock
        features — the quiz, axis, and your state’s ballot stay free.
      </p>
    </div>
  );
}
