import type { Metadata } from "next";
import Link from "next/link";
import { DocPage, type DocSection } from "@/components/doc-page";
import styles from "@/components/doc-page.module.css";
import { JsonLd } from "@/components/json-ld";
import { SiteFooter, SiteHeader } from "@/components/site-chrome";
import { CONTACT_EMAIL, OG_IMAGE } from "@/lib/site";
import { breadcrumbs, pageGraph } from "@/lib/structured-data";

const DESCRIPTION =
  "Get help with Voteaxis — moving phones, shared links, the widget, friend codes, and contributions.";

export const metadata: Metadata = {
  title: "Support",
  description: DESCRIPTION,
  alternates: {
    canonical: "/support",
  },
  openGraph: {
    type: "website",
    url: "/support",
    title: "Support · Voteaxis",
    description: DESCRIPTION,
    images: [OG_IMAGE],
  },
  twitter: {
    title: "Support · Voteaxis",
    description: DESCRIPTION,
    images: [OG_IMAGE],
  },
};

const SECTIONS: readonly DocSection[] = [
  {
    title: "Talk to a person",
    body: `Email ${CONTACT_EMAIL}. Include your phone's platform (iOS or Android) and what screen you were on — screenshots help. We read everything; a person replies, not a ticket system.`,
  },
  {
    title: "Move to a new phone",
    body: "There is no account to sign into — on purpose. On the old phone: Settings → Share & transfer. Either publish a link and open it on the new phone, or read out the offline transfer code (the ~80-character VX1 string) and type it in under Share & transfer → Enter a code. Your placement, weights, dealbreakers, home state, and settings all move.",
  },
  {
    title: "Take down a shared result",
    body: "Shared links are revocable. Settings → Share & transfer → your live link → Revoke. The voteaxis.org/result/<id> page goes dead immediately — for everyone, including anyone who had it open.",
  },
  {
    title: "Friend codes",
    body: "A 6-digit compare code lives for 48 hours and carries issue scores only — never your quiz answers. If a code stopped working, ask your friend to republish; a fresh code takes one tap.",
  },
  {
    title: "The Issue of the Day widget",
    list: [
      "iOS: interactive Agree/Disagree buttons need iOS 17 or later.",
      "Android: long-press the home screen → Widgets → Voteaxis → Issue of the Day.",
      "One calibration per calendar day — a second tap waits for tomorrow.",
      "If the widget says to open the app first, take the quiz once so there is a profile to nudge.",
      "Stopped updating? Check Settings → Issue of the Day widget is on.",
    ],
  },
  {
    title: "The quiz",
    body: "Quiz length is a setting — Short (12), Standard (25), or Long (40) — drawn fresh from an 81-question bank each run. Closing mid-quiz saves your place; resume from the hub. Marking a dealbreaker flags matches that clash hard on that issue even when the rest is close.",
  },
  {
    title: "Think a score is wrong?",
    body: "Email us the figure and the issue. Every stance carries a confidence tag — documented, inferred, contested, or rollcall — and the methodology page explains how each is reached. Corrections ship in the next roster update.",
  },
  {
    title: "Contributions",
    body: "Stripe emails you a receipt; a Sustainer contribution can be cancelled from that receipt. Nothing unlocks either way — the civic loop stays free. Receipt problems: forward it to us.",
  },
];

export default function SupportPage() {
  return (
    <>
      <JsonLd
        data={pageGraph({
          name: "Support",
          description: DESCRIPTION,
          path: "/support",
        })}
      />
      <JsonLd data={breadcrumbs([{ name: "Support", path: "/support" }])} />
      <SiteHeader />
      <DocPage
        eyebrow="Support"
        title="Get help with Voteaxis"
        lede={DESCRIPTION}
        sections={SECTIONS}
        focus={{ x: 0.68, y: 0.38 }}
      >
        <p className={styles.note}>
          Prefer to read the fine print first?{" "}
          <Link href="/methodology">How scoring works</Link> ·{" "}
          <Link href="/privacy">Privacy policy</Link>
        </p>
      </DocPage>
      <SiteFooter />
    </>
  );
}
