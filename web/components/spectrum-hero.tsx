"use client";

import { useGSAP } from "@gsap/react";
import gsap from "gsap";
import {
  type PointerEvent as ReactPointerEvent,
  useCallback,
  useId,
  useMemo,
  useRef,
  useState,
} from "react";
import { SpectrumField } from "@/components/spectrum-field";
import styles from "./spectrum-hero.module.css";

gsap.registerPlugin(useGSAP);

type Pin = {
  id: string;
  label: string;
  fullName: string;
  score: number;
  /** Label sits above or below the axis line. */
  side: "above" | "below";
  /** Keeps its label on narrow screens, where 18 labels would collide. */
  landmark?: boolean;
};

/** App roster landmarks for the marketing preview (all exist in politicians.json). */
const FIGURES: Pin[] = [
  {
    id: "aoc",
    label: "AOC",
    fullName: "A. Ocasio-Cortez",
    score: -86,
    side: "above",
    landmark: true,
  },
  {
    id: "sanders",
    label: "Sanders",
    fullName: "Bernie Sanders",
    score: -78,
    side: "below",
  },
  {
    id: "warren",
    label: "Warren",
    fullName: "Elizabeth Warren",
    score: -68,
    side: "above",
  },
  {
    id: "newsom",
    label: "Newsom",
    fullName: "Gavin Newsom",
    score: -58,
    side: "below",
  },
  {
    id: "whitmer",
    label: "Whitmer",
    fullName: "Gretchen Whitmer",
    score: -48,
    side: "above",
  },
  {
    id: "obama",
    label: "Obama",
    fullName: "Barack Obama",
    score: -40,
    side: "below",
    landmark: true,
  },
  {
    id: "biden",
    label: "Biden",
    fullName: "Joe Biden",
    score: -34,
    side: "above",
  },
  {
    id: "carter",
    label: "Carter",
    fullName: "Jimmy Carter",
    score: -24,
    side: "below",
  },
  {
    id: "jfk",
    label: "JFK",
    fullName: "John F. Kennedy",
    score: -10,
    side: "above",
    landmark: true,
  },
  {
    id: "clinton",
    label: "B. Clinton",
    fullName: "Bill Clinton",
    score: -4,
    side: "below",
  },
  {
    id: "ford",
    label: "Ford",
    fullName: "Gerald Ford",
    score: 16,
    side: "above",
  },
  {
    id: "nixon",
    label: "Nixon",
    fullName: "Richard Nixon",
    score: 26,
    side: "below",
    landmark: true,
  },
  {
    id: "romney",
    label: "Romney",
    fullName: "Mitt Romney",
    score: 34,
    side: "above",
  },
  {
    id: "bush",
    label: "Bush",
    fullName: "George W. Bush",
    score: 46,
    side: "below",
  },
  {
    id: "reagan",
    label: "Reagan",
    fullName: "Ronald Reagan",
    score: 58,
    side: "above",
    landmark: true,
  },
  {
    id: "desantis",
    label: "DeSantis",
    fullName: "Ron DeSantis",
    score: 66,
    side: "below",
  },
  { id: "cruz", label: "Cruz", fullName: "Ted Cruz", score: 74, side: "above" },
  {
    id: "trump",
    label: "Trump",
    fullName: "Donald Trump",
    score: 90,
    side: "below",
    landmark: true,
  },
];

const TICKS = [-100, -75, -50, -25, 0, 25, 50, 75, 100];

function scoreToPercent(score: number) {
  return ((score + 100) / 200) * 100;
}

function formatScore(score: number) {
  const abs = Math.abs(Math.round(score));
  if (abs === 0) return "Center 0";
  return score < 0 ? `Liberal ${abs}` : `Conservative ${abs}`;
}

function clampScore(value: number) {
  return Math.max(-100, Math.min(100, Math.round(value)));
}

function sideOf(score: number): "liberal" | "center" | "conservative" {
  if (score < -4) return "liberal";
  if (score > 4) return "conservative";
  return "center";
}

export function SpectrumHero() {
  const labelId = useId();
  const stageRef = useRef<HTMLElement>(null);
  const railRef = useRef<HTMLDivElement>(null);
  const youPinRef = useRef<HTMLSpanElement>(null);
  const scoreRef = useRef<HTMLParagraphElement>(null);
  const dragging = useRef(false);
  const ready = useRef(false);
  const [you, setYou] = useState(-38);
  const [active, setActive] = useState(false);

  const closest = useMemo(() => {
    return FIGURES.reduce((best, pin) =>
      Math.abs(pin.score - you) < Math.abs(best.score - you) ? pin : best,
    );
  }, [you]);

  const distance = Math.round(Math.abs(closest.score - you));
  const side = sideOf(you);
  const youPercent = scoreToPercent(you);
  const closestPercent = scoreToPercent(closest.score);

  useGSAP(
    () => {
      const reduce = window.matchMedia(
        "(prefers-reduced-motion: reduce)",
      ).matches;
      const root = stageRef.current;
      if (reduce || !root) {
        ready.current = true;
        return;
      }

      const panel = root.querySelector(`.${styles.panel}`);
      const track = root.querySelector(`.${styles.track}`);
      const figures = root.querySelectorAll(`.${styles.figure}`);
      const pin = root.querySelector(`.${styles.youPin}`);
      const tag = root.querySelector(`.${styles.youTag}`);
      const axis = root.querySelector(`.${styles.axisLabels}`);

      const tl = gsap.timeline({
        defaults: { ease: "power3.out" },
        delay: 0.15,
        onComplete: () => {
          ready.current = true;
          gsap.set([panel, track, figures, pin, tag, axis], {
            clearProps: "transform,opacity",
          });
        },
      });

      tl.from(panel, { opacity: 0, y: 18, duration: 0.75 })
        .from(track, { scaleX: 0.6, opacity: 0, duration: 0.85 }, "-=0.4")
        .from(
          figures,
          { opacity: 0, y: 8, duration: 0.4, stagger: 0.03 },
          "-=0.5",
        )
        .from(
          pin,
          { opacity: 0, scale: 0.5, duration: 0.55, ease: "back.out(1.5)" },
          "-=0.3",
        )
        .from(tag, { opacity: 0, y: 8, duration: 0.35 }, "-=0.35")
        .from(axis, { opacity: 0, duration: 0.4 }, "-=0.25");

      const safety = window.setTimeout(() => {
        if (tl.progress() < 1) tl.progress(1);
        ready.current = true;
      }, 2400);

      return () => window.clearTimeout(safety);
    },
    { scope: stageRef },
  );

  useGSAP(
    () => {
      if (!ready.current) return;
      const reduce = window.matchMedia(
        "(prefers-reduced-motion: reduce)",
      ).matches;
      if (reduce) return;
      if (youPinRef.current) {
        gsap.fromTo(
          youPinRef.current,
          { scale: 1.16 },
          { scale: 1, duration: 0.22, ease: "power2.out" },
        );
      }
      if (scoreRef.current) {
        gsap.fromTo(
          scoreRef.current,
          { y: 3, opacity: 0.7 },
          { y: 0, opacity: 1, duration: 0.18, ease: "power2.out" },
        );
      }
    },
    { dependencies: [you], revertOnUpdate: false },
  );

  const setFromClientX = useCallback((clientX: number) => {
    const rail = railRef.current;
    if (!rail) return;
    const track = rail.querySelector(`.${styles.track}`) as HTMLElement | null;
    const rect = (track ?? rail).getBoundingClientRect();
    if (rect.width <= 0) return;
    const ratio = (clientX - rect.left) / rect.width;
    setYou(clampScore(ratio * 200 - 100));
  }, []);

  const onPointerDown = (event: ReactPointerEvent<HTMLDivElement>) => {
    event.preventDefault();
    dragging.current = true;
    setActive(true);
    event.currentTarget.setPointerCapture(event.pointerId);
    setFromClientX(event.clientX);
  };

  const onPointerMove = (event: ReactPointerEvent<HTMLDivElement>) => {
    if (!dragging.current) return;
    setFromClientX(event.clientX);
  };

  const onPointerUp = (event: ReactPointerEvent<HTMLDivElement>) => {
    dragging.current = false;
    setActive(false);
    if (event.currentTarget.hasPointerCapture(event.pointerId)) {
      event.currentTarget.releasePointerCapture(event.pointerId);
    }
  };

  const onKeyDown = (event: React.KeyboardEvent<HTMLDivElement>) => {
    const step = event.shiftKey ? 10 : 5;
    if (event.key === "ArrowLeft" || event.key === "ArrowDown") {
      event.preventDefault();
      setYou((value) => clampScore(value - step));
    } else if (event.key === "ArrowRight" || event.key === "ArrowUp") {
      event.preventDefault();
      setYou((value) => clampScore(value + step));
    } else if (event.key === "Home") {
      event.preventDefault();
      setYou(-100);
    } else if (event.key === "End") {
      event.preventDefault();
      setYou(100);
    }
  };

  const bridgeLeft = Math.min(youPercent, closestPercent);
  const bridgeWidth = Math.abs(youPercent - closestPercent);

  return (
    <section ref={stageRef} className={styles.stage} aria-labelledby={labelId}>
      <div className={styles.field} aria-hidden="true">
        <SpectrumField focus={{ x: 0.5, y: 0.55 }} intensity={0.28} gap={15} />
      </div>

      <div className={styles.inner}>
        <div className={styles.panel}>
          <div className={styles.readout}>
            <div className={styles.readoutScoreBlock}>
              <p id={labelId} className={styles.readoutLabel}>
                Preview the axis
              </p>
              <p
                ref={scoreRef}
                className={`${styles.readoutScore} ${styles[`score_${side}`]}`}
                aria-live="polite"
              >
                {formatScore(you)}
              </p>
            </div>
            <div className={styles.matchCard}>
              <span className={styles.matchKicker}>Closest match</span>
              <p className={styles.matchName}>{closest.fullName}</p>
              <span className={styles.matchDelta}>{distance} pts apart</span>
            </div>
          </div>

          <div
            ref={railRef}
            className={`${styles.rail} ${active ? styles.railActive : ""}`}
            role="slider"
            tabIndex={0}
            aria-valuemin={-100}
            aria-valuemax={100}
            aria-valuenow={you}
            aria-valuetext={
              you === 0
                ? "Center 0"
                : you < 0
                  ? `Liberal ${Math.abs(you)}`
                  : `Conservative ${Math.abs(you)}`
            }
            aria-labelledby={labelId}
            onPointerDown={onPointerDown}
            onPointerMove={onPointerMove}
            onPointerUp={onPointerUp}
            onPointerCancel={onPointerUp}
            onKeyDown={onKeyDown}
          >
            <div className={styles.trackGlow} aria-hidden="true" />
            <div className={styles.track} aria-hidden="true">
              <span className={styles.trackSheen} />
            </div>
            <div className={styles.ticks} aria-hidden="true">
              {TICKS.map((tick) => (
                <span
                  key={tick}
                  className={`${styles.tick} ${tick === 0 ? styles.tickCenter : ""}`}
                  style={{ left: `${scoreToPercent(tick)}%` }}
                />
              ))}
            </div>
            <div
              className={styles.bridge}
              aria-hidden="true"
              style={{ left: `${bridgeLeft}%`, width: `${bridgeWidth}%` }}
            />
            {FIGURES.map((pin) => {
              const isHot = pin.id === closest.id;
              const above = pin.side === "above";
              const label = (
                <span className={styles.figureLabel}>{pin.label}</span>
              );
              const stem = <span className={styles.figureStem} />;
              const dot = <span className={styles.figureDot} />;
              return (
                <span
                  key={pin.id}
                  className={[
                    styles.figure,
                    above ? styles.figureAbove : styles.figureBelow,
                    isHot ? styles.figureHot : "",
                    pin.score < 0 ? styles.figureLeft : styles.figureRight,
                    !pin.landmark && !isHot ? styles.figureMuted : "",
                  ]
                    .filter(Boolean)
                    .join(" ")}
                  style={{ left: `${scoreToPercent(pin.score)}%` }}
                >
                  {above ? (
                    <>
                      {label}
                      {stem}
                      {dot}
                    </>
                  ) : (
                    <>
                      {dot}
                      {stem}
                      {label}
                    </>
                  )}
                </span>
              );
            })}
            <div
              className={`${styles.you} ${active ? styles.youActive : ""}`}
              style={{ left: `${youPercent}%` }}
              aria-hidden="true"
            >
              <span className={styles.youTag}>You</span>
              <span className={styles.youStem} />
              <span ref={youPinRef} className={styles.youPin}>
                <span className={styles.youCore} />
              </span>
            </div>
          </div>

          <div className={styles.axisLabels}>
            <span>
              <em>Liberal</em> 100
            </span>
            <span>0</span>
            <span>
              <em>Conservative</em> 100
            </span>
          </div>
        </div>
      </div>
    </section>
  );
}
