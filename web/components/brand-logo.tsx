import Image from "next/image";
import styles from "./brand-logo.module.css";

type BrandLogoProps = {
  size?: number;
  priority?: boolean;
  className?: string;
};

export function BrandLogo({
  size = 40,
  priority = false,
  className,
}: BrandLogoProps) {
  return (
    <Image
      src="/brand/voteaxis-mark.png"
      alt=""
      width={size}
      height={size}
      priority={priority}
      className={`${styles.mark} ${className ?? ""}`}
    />
  );
}

export function BrandLockup({
  markSize = 40,
  priority = false,
  /** Drops the wordmark on narrow screens so the mark alone carries the brand. */
  compact = false,
}: {
  markSize?: number;
  priority?: boolean;
  compact?: boolean;
}) {
  return (
    <span className={`${styles.lockup} ${compact ? styles.lockupCompact : ""}`}>
      <BrandLogo size={markSize} priority={priority} />
      <span className={styles.wordmark}>Voteaxis</span>
    </span>
  );
}
