import type { Metadata } from "next";
import { BrandLogo } from "@/components/brand-logo";
import { ClosingPanel } from "@/components/closing-panel";
import { JsonLd } from "@/components/json-ld";
import { Reveal } from "@/components/reveal";
import { SiteFooter, SiteHeader } from "@/components/site-chrome";
import { SpectrumField } from "@/components/spectrum-field";
import { OG_IMAGE } from "@/lib/site";
import { breadcrumbs, pageGraph } from "@/lib/structured-data";
import styles from "./contribute.module.css";
import { ContributeForm } from "./contribute-form";

const DESCRIPTION =
  "Fund independent Spectrum Issue Index scoring and state-level data. The quiz, axis, and your state’s ballot stay free.";

export const metadata: Metadata = {
  title: "Contribute",
  description: DESCRIPTION,
  alternates: {
    canonical: "/contribute",
  },
  openGraph: {
    type: "website",
    url: "/contribute",
    title: "Fund the instrument, not a paywall · Voteaxis",
    description: DESCRIPTION,
    images: [OG_IMAGE],
  },
  twitter: {
    title: "Fund the instrument, not a paywall · Voteaxis",
    description: DESCRIPTION,
    images: [OG_IMAGE],
  },
};

const NOTES = [
  {
    title: "The civic loop stays free",
    body: "Quiz, axis, Active Ballot, historical matches, friend compare, and dealbreakers are not behind a paywall. A contribution funds the instrument. It does not buy a fairer match.",
  },
  {
    title: "What the money covers",
    body: "Hosting, App Store fees, and keeping state-level candidate data current. Voteaxis is built by The Greigh Studios LLC — no ad network, no sponsored results.",
  },
  {
    title: "No account required",
    body: "Stripe collects the payment. You do not need a Voteaxis login. A Sustainer is a yearly contribution you can cancel from the receipt Stripe emails you.",
  },
] as const;

const CLOSING_POINTS = [
  {
    label: "Join the beta",
    body: "TestFlight and Play invites go out before public launch. Early answers stress-test the question wording.",
  },
  {
    label: "Flag a bad score",
    body: "Send the figure and the issue. Curated stances get corrected, and the confidence tag says how the score was reached.",
  },
  {
    label: "Bring it to a room",
    body: "Teachers, professors, and newsrooms can flag themselves on the waitlist form and get classroom notes with the beta.",
  },
] as const;

export default function ContributePage() {
  return (
    <div className={styles.shell}>
      <JsonLd
        data={pageGraph({
          name: "Fund the instrument, not a paywall",
          description: DESCRIPTION,
          path: "/contribute",
        })}
      />
      <JsonLd
        data={breadcrumbs([{ name: "Contribute", path: "/contribute" }])}
      />
      <SiteHeader active="contribute" />
      <main>
        <header className={styles.hero}>
          <div className={styles.heroField} aria-hidden="true">
            <SpectrumField focus={{ x: 0.72, y: 0.38 }} intensity={0.26} />
          </div>
          <div className={styles.heroInner}>
            <Reveal>
              <div className={styles.brandRow}>
                <BrandLogo size={44} priority />
                <p className={styles.eyebrow}>Independent scoring</p>
              </div>
              <h1>Fund the instrument, not a paywall</h1>
              <p className={styles.lede}>
                Voteaxis stays free — the quiz, your axis, and your state’s
                ballot. A contribution covers hosting and state-level data. It
                does not unlock fairness, and it never will.
              </p>
            </Reveal>
          </div>
        </header>

        <div className={styles.main}>
          <ol className={styles.notes}>
            {NOTES.map((note, index) => (
              <Reveal key={note.title} as="li" delay={index * 0.04}>
                <span className={styles.index}>
                  {String(index + 1).padStart(2, "0")}
                </span>
                <div>
                  <h2>{note.title}</h2>
                  <p>{note.body}</p>
                </div>
              </Reveal>
            ))}
          </ol>
          <Reveal delay={0.08}>
            <aside className={styles.panel} aria-label="Choose an amount">
              <ContributeForm />
            </aside>
          </Reveal>

          <ClosingPanel
            className={styles.closing}
            kicker="Other ways to help"
            title="Money is not the only useful thing"
            lede="A contribution is not the only way to keep this honest. These matter just as much to a scoring project with no ad network behind it."
            points={CLOSING_POINTS}
            primary={{ href: "/#waitlist", label: "Join the waitlist" }}
            secondary={{ href: "/methodology", label: "Read the methodology" }}
            note="Questions before you give? Email hello@voteaxis.org."
            focus={{ x: 0.74, y: 0.5 }}
          />
        </div>
      </main>
      <SiteFooter />
    </div>
  );
}
