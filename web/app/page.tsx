import { HomeIntro } from "@/components/home-intro";
import { Reveal } from "@/components/reveal";
import { SiteFooter, SiteHeader } from "@/components/site-chrome";
import { SpectrumField } from "@/components/spectrum-field";
import { SpectrumHero } from "@/components/spectrum-hero";
import { WaitlistForm } from "@/components/waitlist-form";
import styles from "./page.module.css";

/** Mirrors mobile/assets/data/pillars.json and issues.json. */
const PILLARS = [
  {
    id: "economy",
    label: "Economy & fiscal",
    issues: [
      "Jobs & the economy",
      "Taxes & government spending",
      "Budget deficit",
      "Inflation & prices",
      "Free markets vs regulation",
      "Welfare & safety net",
    ],
  },
  {
    id: "society",
    label: "Rights & society",
    issues: [
      "Abortion",
      "Civil rights & liberties",
      "LGBTQ rights",
      "Education",
      "Traditional values",
    ],
  },
  {
    id: "health",
    label: "Health & entitlements",
    issues: ["Health care", "Medicare", "Social Security"],
  },
  {
    id: "justice",
    label: "Justice & homeland",
    issues: ["Crime & criminal justice", "Gun control", "Immigration & border"],
  },
  {
    id: "world",
    label: "Climate, energy & world",
    issues: [
      "Climate & environment",
      "Energy",
      "National security & foreign policy",
      "Terrorism",
      "Military posture",
    ],
  },
] as const;

const ISSUE_COUNT = PILLARS.reduce(
  (total, pillar) => total + pillar.issues.length,
  0,
);

const FLOW = [
  {
    title: "Quiz",
    body: "About three minutes on the issues behind the Spectrum Issue Index.",
  },
  {
    title: "Spectrum",
    body: "Answers roll into five pillars, then one clear Liberal ↔ Conservative axis.",
  },
  {
    title: "Ballot",
    body: "Rank candidates on your state’s ballot — from statewide offices to the legislature.",
  },
] as const;

const WHAT_YOU_GET = [
  {
    title: "Your ballot",
    body: "Matches prioritize candidates from your state — statewide races through the legislature.",
  },
  {
    title: "Issue overlap",
    body: "Ranked by how close they are to your answers, with agreements and disagreements called out.",
  },
  {
    title: "Clear placement",
    body: "See yourself on Liberal 100 ← 0 → Conservative 100. In the quiz, you say how much each question matters.",
  },
] as const;

export default function HomePage() {
  return (
    <div className={styles.shell}>
      <SiteHeader active="home" />

      <main>
        <HomeIntro />

        <SpectrumHero />

        <section className={styles.flow} aria-labelledby="flow-heading">
          <Reveal>
            <div className={styles.flowHead}>
              <h2 id="flow-heading">From answers to a ballot match</h2>
              <a href="/methodology" className={styles.textLink}>
                Full methodology
              </a>
            </div>
          </Reveal>
          <ol className={styles.flowTrack}>
            {FLOW.map((step, index) => (
              <Reveal key={step.title} as="li" delay={index * 0.07}>
                <span className={styles.flowIndex}>
                  {String(index + 1).padStart(2, "0")}
                </span>
                <span className={styles.flowTitle}>{step.title}</span>
                <span className={styles.flowBody}>{step.body}</span>
              </Reveal>
            ))}
          </ol>
        </section>

        <section className={styles.ruler} aria-labelledby="pillars-heading">
          <div className={styles.rulerInner}>
            <Reveal>
              <div className={styles.rulerHead}>
                <div>
                  <p className={styles.rulerKicker}>What the quiz asks</p>
                  <h2 id="pillars-heading">
                    Five pillars, {ISSUE_COUNT} issues
                  </h2>
                </div>
                <p className={styles.rulerCopy}>
                  Every issue sits on the same Liberal ↔ Conservative scale —
                  yours and every figure’s. You set how much each one matters
                  during the quiz, not after the fact, and a pillar score is the
                  weighted average of the issues inside it.
                </p>
              </div>
            </Reveal>
            <ol className={styles.rulerScale}>
              {PILLARS.map((pillar, index) => (
                <Reveal key={pillar.id} as="li" delay={index * 0.05}>
                  <span className={styles.pillarCount}>
                    {pillar.issues.length} issues
                  </span>
                  <h3 className={styles.pillarName}>{pillar.label}</h3>
                  <ul className={styles.pillarIssues}>
                    {pillar.issues.map((issue) => (
                      <li key={issue}>{issue}</li>
                    ))}
                  </ul>
                </Reveal>
              ))}
            </ol>
          </div>
        </section>

        <section className={styles.gets} aria-labelledby="gets-heading">
          <div className={styles.getsInner}>
            <Reveal>
              <p className={styles.getsKicker}>In the app</p>
              <h2 id="gets-heading">What you get</h2>
            </Reveal>
            <ul className={styles.getsList}>
              {WHAT_YOU_GET.map((item, index) => (
                <Reveal key={item.title} as="li" delay={index * 0.06}>
                  <span className={styles.getsTitle}>{item.title}</span>
                  <span className={styles.getsBody}>{item.body}</span>
                </Reveal>
              ))}
            </ul>
          </div>
        </section>

        <section
          className={styles.waitlist}
          id="waitlist"
          aria-labelledby="waitlist-heading"
        >
          <div className={styles.waitlistField} aria-hidden="true">
            <SpectrumField focus={{ x: 0.7, y: 0.45 }} intensity={0.35} />
          </div>
          <Reveal className={styles.waitlistInner}>
            <div>
              <p className={styles.waitlistKicker}>Beta list</p>
              <h2 id="waitlist-heading">Get notified at launch</h2>
              <p className={styles.waitlistLede}>
                TestFlight and Play invites when the first builds are ready. No
                spam — just launch access for Voteaxis.
              </p>
            </div>
            <WaitlistForm />
          </Reveal>
        </section>
      </main>

      <SiteFooter />
    </div>
  );
}
