"use client";

import { useEffect, useRef } from "react";
import styles from "./spectrum-field.module.css";

type Props = {
  className?: string;
  /** Focal point of the solid mass, as a fraction of the canvas box. */
  focus?: { x: number; y: number };
  cell?: number;
  gap?: number;
  intensity?: number;
};

/**
 * Ambient cell field inspired by Greigh Studios' dissolve mark — tinted
 * liberal→conservative so it reads as spectrum atmosphere, not brand cyan.
 */
export function SpectrumField({
  className = "",
  focus = { x: 0.5, y: 0.5 },
  cell = 4,
  gap = 14,
  intensity = 0.42,
}: Props) {
  const canvasRef = useRef<HTMLCanvasElement>(null);

  useEffect(() => {
    const node = canvasRef.current;
    if (!node) return;
    const context = node.getContext("2d");
    if (!context) return;

    const surface: HTMLCanvasElement = node;
    const ctx: CanvasRenderingContext2D = context;

    const reduce = window.matchMedia(
      "(prefers-reduced-motion: reduce)",
    ).matches;
    const step = cell + gap;

    type Cell = {
      x: number;
      y: number;
      base: number;
      phase: number;
      speed: number;
      t: number;
    };
    let cells: Cell[] = [];
    let width = 0;
    let height = 0;
    let raf = 0;

    const hash = (x: number, y: number) => {
      const n = Math.sin(x * 127.1 + y * 311.7) * 43758.5453;
      return n - Math.floor(n);
    };

    function build() {
      const rect = surface.getBoundingClientRect();
      width = rect.width;
      height = rect.height;
      if (width === 0 || height === 0) return;

      const dpr = Math.min(window.devicePixelRatio || 1, 2);
      surface.width = Math.round(width * dpr);
      surface.height = Math.round(height * dpr);
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);

      const fx = width * focus.x;
      const fy = height * focus.y;
      const reach = Math.hypot(
        Math.max(fx, width - fx),
        Math.max(fy, height - fy),
      );

      const next: Cell[] = [];
      for (let y = 0; y < height; y += step) {
        for (let x = 0; x < width; x += step) {
          const d = Math.hypot(x - fx, y - fy) / reach;
          const density = Math.max(0, 1 - d * 1.4) ** 2.6;
          const r = hash(x, y);
          if (r > density) continue;
          next.push({
            x,
            y,
            base: density * intensity * (0.55 + hash(y, x) * 0.45),
            phase: hash(x + 7, y + 13) * Math.PI * 2,
            speed: 0.4 + hash(x + 31, y + 17) * 0.7,
            t: x / width,
          });
        }
      }
      cells = next;
    }

    function colorAt(t: number, a: number) {
      // Blue left → soft mid → red right
      if (t < 0.5) {
        const k = t * 2;
        const r = Math.round(29 + (120 - 29) * k);
        const g = Math.round(78 + (130 - 78) * k);
        const b = Math.round(216 + (180 - 216) * k);
        return `rgba(${r}, ${g}, ${b}, ${a.toFixed(3)})`;
      }
      const k = (t - 0.5) * 2;
      const r = Math.round(120 + (220 - 120) * k);
      const g = Math.round(130 + (38 - 130) * k);
      const b = Math.round(180 + (38 - 180) * k);
      return `rgba(${r}, ${g}, ${b}, ${a.toFixed(3)})`;
    }

    function draw(t: number) {
      if (!width || !height) return;
      ctx.clearRect(0, 0, width, height);
      for (const c of cells) {
        const pulse = reduce
          ? 1
          : 0.78 + 0.22 * Math.sin(t * 0.00055 * c.speed + c.phase);
        const a = c.base * pulse;
        if (a <= 0.01) continue;
        ctx.fillStyle = colorAt(c.t, a);
        ctx.fillRect(c.x, c.y, cell, cell);
      }
    }

    function loop(now: number) {
      draw(now);
      raf = requestAnimationFrame(loop);
    }

    let onScreen = false;

    const sync = () => {
      const shouldRun = onScreen && !document.hidden && !reduce;
      if (shouldRun && !raf) {
        raf = requestAnimationFrame(loop);
      } else if (!shouldRun && raf) {
        cancelAnimationFrame(raf);
        raf = 0;
      }
    };

    build();
    draw(0);

    const io = new IntersectionObserver(
      ([entry]) => {
        onScreen = entry.isIntersecting;
        sync();
      },
      { rootMargin: "120px" },
    );
    io.observe(surface);

    const ro = new ResizeObserver(() => {
      build();
      if (!raf) draw(0);
    });
    ro.observe(surface);

    document.addEventListener("visibilitychange", sync);

    return () => {
      cancelAnimationFrame(raf);
      io.disconnect();
      ro.disconnect();
      document.removeEventListener("visibilitychange", sync);
    };
  }, [cell, gap, focus.x, focus.y, intensity]);

  return (
    <canvas
      ref={canvasRef}
      aria-hidden
      className={`${styles.canvas} ${className}`.trim()}
    />
  );
}
