"use client";

import { BrandLogo } from "@/components/brand-logo";
import { SpectrumField } from "@/components/spectrum-field";
import styles from "./home-intro.module.css";

export function HomeIntro() {
  return (
    <header className={styles.hero}>
      <div className={styles.atmosphere} aria-hidden="true">
        <SpectrumField focus={{ x: 0.78, y: 0.42 }} intensity={0.32} />
      </div>
      <div className={styles.inner}>
        <div className={styles.brandBlock}>
          <BrandLogo size={56} priority />
          <p className={styles.brand}>Voteaxis</p>
        </div>
        <h1 className={styles.headline}>
          See where you stand.
          <br />
          Choose who to vote for.
        </h1>
        <p className={styles.lede}>
          A short quiz places you on Liberal 100 ← 0 → Conservative 100, then
          ranks ballot candidates — including Michigan’s 2026 races — by how
          close they are to your issues.
        </p>
        <div className={styles.ctaRow}>
          <a className={styles.primaryCta} href="#waitlist">
            Join the waitlist
            <span className={styles.arrow} aria-hidden="true">
              →
            </span>
          </a>
          <a className={styles.secondaryCta} href="/methodology">
            How scoring works
          </a>
        </div>
        <p className={styles.meta}>Coming soon on iOS &amp; Android</p>
      </div>
    </header>
  );
}
