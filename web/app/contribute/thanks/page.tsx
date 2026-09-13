import type { Metadata } from "next";
import { ClosingPanel } from "@/components/closing-panel";
import { SiteFooter, SiteHeader } from "@/components/site-chrome";
import styles from "../contribute.module.css";

export const metadata: Metadata = {
  title: "Thank you",
  description: "Your contribution helps keep Voteaxis independent.",
  robots: { index: false, follow: false },
  alternates: {
    canonical: "/contribute/thanks",
  },
};

const CLOSING_POINTS = [
  {
    label: "Your receipt",
    body: "Stripe emails it. A Sustainer renews yearly and cancels from that same receipt — there is no Voteaxis account to manage.",
  },
  {
    label: "What it covers",
    body: "Hosting, App Store fees, and keeping state-level candidate data current.",
  },
  {
    label: "What it never buys",
    body: "Placement, a friendlier score, or a sponsored result. There is no ad network to sell to.",
  },
] as const;

export default function ContributeThanksPage() {
  return (
    <div className={styles.shell}>
      <SiteHeader active="contribute" />
      <main className={styles.thanksInner}>
        <p className={styles.eyebrow}>Contribute to Voteaxis</p>
        <h1>Thank you</h1>
        <ClosingPanel
          kicker="What happens now"
          title="You funded the instrument, not a feature"
          lede="Nothing unlocks and nothing ranks differently — that is the point. Here is where a contribution actually lands."
          points={CLOSING_POINTS}
          primary={{ href: "/", label: "Back to home" }}
          secondary={{ href: "/methodology", label: "Read the methodology" }}
          note="Something wrong with a charge? Email hello@voteaxis.org."
          focus={{ x: 0.76, y: 0.46 }}
        />
      </main>
      <SiteFooter />
    </div>
  );
}
