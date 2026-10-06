"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { BrandLockup, BrandLogo } from "@/components/brand-logo";
import styles from "./site-chrome.module.css";

export function SiteHeader({
  active,
}: {
  active?: "home" | "methodology" | "contribute";
}) {
  const [scrolled, setScrolled] = useState(false);

  useEffect(() => {
    const onScroll = () => setScrolled(window.scrollY > 12);
    onScroll();
    window.addEventListener("scroll", onScroll, { passive: true });
    return () => window.removeEventListener("scroll", onScroll);
  }, []);

  return (
    <header
      className={`${styles.header} ${scrolled ? styles.headerScrolled : ""}`}
    >
      <div className={styles.headerInner}>
        <Link href="/" className={styles.logo} aria-label="Voteaxis home">
          <BrandLockup markSize={34} priority compact />
        </Link>
        <nav className={styles.nav} aria-label="Primary">
          <Link
            href="/methodology"
            prefetch={false}
            className={
              active === "methodology" ? styles.navLinkActive : styles.navLink
            }
          >
            Methodology
          </Link>
          <Link
            href="/contribute"
            prefetch={false}
            className={
              active === "contribute" ? styles.navLinkActive : styles.navLink
            }
          >
            Contribute
          </Link>
          <a href="/#waitlist" className={styles.navCta}>
            Join the waitlist
            <span className={styles.navArrow} aria-hidden="true">
              →
            </span>
          </a>
        </nav>
      </div>
    </header>
  );
}

export function SiteFooter() {
  return (
    <footer className={styles.footer}>
      <div className={styles.footerInner}>
        <div className={styles.footerBrandRow}>
          <BrandLogo size={36} />
          <div>
            <p className={styles.footerBrand}>Voteaxis</p>
            <p className={styles.footerMeta}>
              The Greigh Studios LLC · Spectrum Issue Index v1
            </p>
          </div>
        </div>
        <div className={styles.footerLinks}>
          <Link href="/methodology" prefetch={false}>
            Methodology
          </Link>
          <Link href="/contribute" prefetch={false}>
            Contribute
          </Link>
          <Link href="/support" prefetch={false}>
            Support
          </Link>
          <Link href="/privacy" prefetch={false}>
            Privacy
          </Link>
          <a href="/#waitlist">Waitlist</a>
        </div>
      </div>
    </footer>
  );
}
