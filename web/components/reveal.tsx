"use client";

import { useGSAP } from "@gsap/react";
import gsap from "gsap";
import { useRef } from "react";

gsap.registerPlugin(useGSAP);

type Props = {
  children: React.ReactNode;
  className?: string;
  y?: number;
  delay?: number;
  as?: "div" | "li" | "section";
};

export function Reveal({
  children,
  className = "",
  y = 24,
  delay = 0,
  as: Tag = "div",
}: Props) {
  const ref = useRef<HTMLElement>(null);

  useGSAP(
    () => {
      const el = ref.current;
      if (!el) return;

      const reduce = window.matchMedia(
        "(prefers-reduced-motion: reduce)",
      ).matches;
      if (reduce) return;

      const tween = gsap.fromTo(
        el,
        { opacity: 0, y },
        {
          opacity: 1,
          y: 0,
          duration: 0.85,
          delay,
          ease: "power3.out",
          paused: true,
          immediateRender: false,
          onComplete: () => {
            gsap.set(el, { clearProps: "transform,opacity" });
          },
        },
      );

      let played = false;
      const play = () => {
        if (played) return;
        played = true;
        tween.play();
        window.setTimeout(
          () => {
            if (tween.progress() < 1) tween.progress(1);
          },
          1200 + delay * 1000,
        );
      };

      const io = new IntersectionObserver(
        ([entry]) => {
          if (!entry?.isIntersecting) return;
          play();
          io.disconnect();
        },
        { rootMargin: "0px 0px -8% 0px", threshold: 0.05 },
      );
      io.observe(el);

      const boot = window.setTimeout(() => {
        const rect = el.getBoundingClientRect();
        if (rect.top < window.innerHeight * 0.92 && rect.bottom > 0) {
          play();
        }
      }, 80);

      return () => {
        window.clearTimeout(boot);
        io.disconnect();
        tween.kill();
      };
    },
    { scope: ref },
  );

  return (
    <Tag
      ref={ref as React.Ref<HTMLDivElement & HTMLLIElement & HTMLElement>}
      className={className}
    >
      {children}
    </Tag>
  );
}
