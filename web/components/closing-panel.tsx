import Link from "next/link";
import type { ReactNode } from "react";
import { Reveal } from "@/components/reveal";
import { SpectrumField } from "@/components/spectrum-field";
import styles from "./closing-panel.module.css";

type Action = { href: string; label: string };

export type ClosingPoint = {
  label: string;
  body: ReactNode;
  /** Turns the row label into a link — used where the points are destinations. */
  href?: string;
};

type Props = {
  kicker: string;
  title: ReactNode;
  lede: ReactNode;
  points: readonly ClosingPoint[];
  primary: Action;
  secondary?: Action;
  note?: ReactNode;
  focus?: { x: number; y: number };
  className?: string;
};

/**
 * End-of-page panel: the pitch on the left, a ledger of what is actually true
 * on the right, under the same Liberal ↔ Conservative rule the app uses.
 */
export function ClosingPanel({
  kicker,
  title,
  lede,
  points,
  primary,
  secondary,
  note,
  focus = { x: 0.78, y: 0.5 },
  className = "",
}: Props) {
  return (
    <Reveal as="section" className={`${styles.wrap} ${className}`}>
      <div className={styles.panel}>
        <span className={styles.axis} aria-hidden="true">
          <i className={styles.axisLiberal} />
          <i className={styles.axisCenter} />
          <i className={styles.axisConservative} />
        </span>
        <div className={styles.field} aria-hidden="true">
          <SpectrumField focus={focus} intensity={0.3} />
        </div>

        <div className={styles.inner}>
          <div className={styles.pitch}>
            <p className={styles.kicker}>{kicker}</p>
            <h2 className={styles.title}>{title}</h2>
            <p className={styles.lede}>{lede}</p>
            <div className={styles.actions}>
              <Link href={primary.href} className={styles.primary}>
                {primary.label}
                <span aria-hidden="true">→</span>
              </Link>
              {secondary ? (
                <Link href={secondary.href} className={styles.secondary}>
                  {secondary.label}
                </Link>
              ) : null}
            </div>
            {note ? <p className={styles.note}>{note}</p> : null}
          </div>

          <dl className={styles.points}>
            {points.map((point) => (
              <div key={point.label} className={styles.point}>
                <dt>
                  {point.href ? (
                    <Link href={point.href} className={styles.pointLink}>
                      {point.label}
                      <span aria-hidden="true">→</span>
                    </Link>
                  ) : (
                    point.label
                  )}
                </dt>
                <dd>{point.body}</dd>
              </div>
            ))}
          </dl>
        </div>
      </div>
    </Reveal>
  );
}
