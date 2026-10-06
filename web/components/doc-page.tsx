import type { ReactNode } from "react";
import { BrandLogo } from "@/components/brand-logo";
import { Reveal } from "@/components/reveal";
import { SpectrumField } from "@/components/spectrum-field";
import styles from "./doc-page.module.css";

export type DocSection = {
  title: string;
  body?: string;
  list?: readonly string[];
  /** Extra markup after the paragraph — links, nested lists. */
  children?: ReactNode;
};

/**
 * The lighter page shape for documents — privacy, support — where the heavy
 * methodology hero would oversell what is mostly text.
 */
export function DocPage({
  eyebrow,
  title,
  lede,
  updated,
  sections,
  focus = { x: 0.3, y: 0.4 },
  children,
}: {
  eyebrow: string;
  title: string;
  lede: string;
  /** Printed as "Last updated …" — legal pages need a visible vintage. */
  updated?: string;
  sections: readonly DocSection[];
  /** Where the ambient field concentrates, in fractional coordinates. */
  focus?: { x: number; y: number };
  children?: ReactNode;
}) {
  return (
    <div className={styles.shell}>
      <main>
        <header className={styles.hero}>
          <div className={styles.heroField} aria-hidden="true">
            <SpectrumField focus={focus} intensity={0.22} />
          </div>
          <div className={styles.heroInner}>
            <Reveal>
              <div className={styles.brandRow}>
                <BrandLogo size={44} priority />
                <p className={styles.eyebrow}>{eyebrow}</p>
              </div>
              <h1>{title}</h1>
              <p className={styles.lede}>{lede}</p>
              {updated ? <p className={styles.updated}>{updated}</p> : null}
            </Reveal>
          </div>
        </header>

        <div className={styles.main}>
          <ol className={styles.sections}>
            {sections.map((section, index) => (
              <Reveal key={section.title} as="li" delay={index * 0.03}>
                <span className={styles.index}>
                  {String(index + 1).padStart(2, "0")}
                </span>
                <div className={styles.sectionBody}>
                  <h2>{section.title}</h2>
                  {section.list ? (
                    <ul className={styles.list}>
                      {section.list.map((item) => (
                        <li key={item}>{item}</li>
                      ))}
                    </ul>
                  ) : null}
                  {section.body ? <p>{section.body}</p> : null}
                  {section.children}
                </div>
              </Reveal>
            ))}
          </ol>
          {children}
        </div>
      </main>
    </div>
  );
}
