import type { Metadata } from "next";
import { BrandLogo } from "@/components/brand-logo";
import { ClosingPanel } from "@/components/closing-panel";
import { JsonLd } from "@/components/json-ld";
import { Reveal } from "@/components/reveal";
import { SiteFooter, SiteHeader } from "@/components/site-chrome";
import { SpectrumField } from "@/components/spectrum-field";
import { OG_IMAGE } from "@/lib/site";
import { breadcrumbs, methodologyGraph } from "@/lib/structured-data";
import styles from "./methodology.module.css";

const DESCRIPTION =
  "How Voteaxis scores views with the Spectrum Issue Index (SII) v1 — issues, five pillars, one Liberal ↔ Conservative axis, and how candidates are matched.";

export const metadata: Metadata = {
  title: "Methodology",
  description: DESCRIPTION,
  alternates: {
    canonical: "/methodology",
  },
  openGraph: {
    type: "article",
    url: "/methodology",
    title: "How we score your views · Voteaxis",
    description: DESCRIPTION,
    images: [OG_IMAGE],
  },
  twitter: {
    title: "How we score your views · Voteaxis",
    description: DESCRIPTION,
    images: [OG_IMAGE],
  },
};

/** The four hops a score actually makes, drawn before the prose explains them. */
const PIPELINE = [
  ["Your answers", "Five-point Likert, plus how much it matters"],
  ["Issues", "One shared scale for you and every figure"],
  ["Five pillars", "Importance-weighted average per theme"],
  ["Your axis", "One score, then everyone ranked against it"],
] as const;

type Section = {
  title: string;
  body: string;
  list?: readonly string[];
  /** The one line from this section people quote back at us. */
  callout?: string;
};

const GROUPS: readonly { group: string; sections: readonly Section[] }[] = [
  {
    group: "How you are scored",
    sections: [
      {
        title: "Issues",
        body: "Each stance sits on the same public scale: Liberal 100 ← 0 → Conservative 100 (no minus signs). Quiz answers use a five-point Likert that maps onto that scale. A second control asks how important the question is to you (Low → Essential). If you land hard on one side of an issue, results can flip a Steel Man card — the strongest case for the opposite view. It does not change your score.",
      },
      {
        title: "Five pillars",
        list: [
          "Economy & fiscal",
          "Rights & society",
          "Health & entitlements",
          "Justice & homeland",
          "Climate, energy & world",
        ],
        body: "A pillar score is the importance-weighted average of its issue scores.",
      },
      {
        title: "Overall axis",
        body: "Overall placement is an importance-weighted average of the issues you answered (Liberal 100 ← 0 → Conservative 100). Mark up to three dealbreakers in the quiz — candidates who clash hard on those issues are flagged even if the rest of the match is close.",
      },
    ],
  },
  {
    group: "How figures are scored",
    sections: [
      {
        title: "Matching",
        body: "Candidates are ranked by weighted mean absolute difference across shared issues — questions you marked more important count more. Results highlight top agreements and disagreements so you can see why someone is close.",
      },
      {
        title: "Confidence",
        body: "Each curated stance is tagged documented, inferred, contested, or rollcall. Older presidents often use inferred historical judgments. For members of Congress, issue scores blend the curated vector with coded floor votes (VoteView, 117th Congress on) when an issue has at least three mapped votes. We map bills to SII issues by title; the VoteView cutting line says which side is conservative. We do not import DW-NOMINATE member scores. A profile vote-record slider can show those floor votes by Congress; dragging it does not change the lifetime blend used for matching.",
        callout: "We do not import DW-NOMINATE member scores.",
      },
      {
        title: "Congress receipts",
        body: "ProPublica retired their Congress API. We run our own Congress REST API, indexed from BICAM (bicam.net), and show recent sponsored and cosponsored bills. Congress.gov can freshen latest action and official summaries on the cards already on screen.",
        callout:
          "Those bill lists are receipts, not the roll-call blend. A fresher “Became Public Law No. 117-169” line does not change Spectrum Issue Index scores.",
      },
    ],
  },
  {
    group: "Settings that change this",
    sections: [
      {
        title: "How far back",
        body: "The app defaults to 2000s plus — anyone last in office in 2000 or later. Settings can step to 1980s plus (Reagan era) or 1960s plus (Kennedy era, including Progressive Era quiz wording). Sitting members always appear. Time-blind matching and political ancestry unlock below the 2000s plus default.",
      },
      {
        title: "Home-screen micro-calibrations",
        body: "The Issue of the Day widget (home screen on Android; home or lock screen on iOS) shows one prompt. Agree or Disagree nudges that one issue with a small blend. One calibration per calendar day. If you have not taken the quiz, the widget asks you to open Voteaxis first.",
        callout: "It does not replace the quiz.",
      },
    ],
  },
];

const SECTIONS = GROUPS.flatMap((entry) => entry.sections);

const CLOSING_POINTS = [
  {
    label: "Free to use",
    body: "Quiz, axis, Active Ballot, friend compare, and dealbreakers stay outside the paywall. A contribution funds the instrument, not a better match.",
  },
  {
    label: "Versioned, not silent",
    body: "This page documents SII v1. When the scoring changes, it ships as a new version and this page changes with it.",
  },
  {
    label: "Sourced per stance",
    body: "Every stance carries a tag — documented, inferred, contested, or rollcall — so you can see how much weight it should hold.",
  },
] as const;

export default function MethodologyPage() {
  return (
    <div className={styles.shell}>
      <JsonLd
        data={methodologyGraph(SECTIONS.map((section) => section.title))}
      />
      <JsonLd
        data={breadcrumbs([{ name: "Methodology", path: "/methodology" }])}
      />
      <SiteHeader active="methodology" />
      <main>
        <header className={styles.hero}>
          <div className={styles.heroField} aria-hidden="true">
            <SpectrumField focus={{ x: 0.28, y: 0.4 }} intensity={0.26} />
          </div>
          <div className={styles.heroInner}>
            <Reveal>
              <div className={styles.brandRow}>
                <BrandLogo size={44} priority />
                <p className={styles.eyebrow}>Spectrum Issue Index · v1</p>
              </div>
              <h1>How we score your views</h1>
              <p className={styles.lede}>
                We built our own method — not a third-party ideology score. You
                answer the same issues we score for each political figure, and
                say how much each question matters. Those answers roll into five
                pillars, then one Liberal ↔ Conservative axis used to rank your
                ballot.
              </p>
              <div className={styles.axisBar} aria-hidden="true">
                <span>Liberal 100</span>
                <div className={styles.axisTrack}>
                  <i className={styles.axisLiberal} />
                  <i className={styles.axisCenter} />
                  <i className={styles.axisConservative} />
                </div>
                <span>Conservative 100</span>
              </div>
            </Reveal>
          </div>
        </header>

        <div className={styles.main}>
          <ol className={styles.pipeline} aria-label="How a score is built">
            {PIPELINE.map(([step, detail], index) => (
              <li key={step}>
                <span className={styles.pipelineIndex}>{index + 1}</span>
                <div>
                  <h2>{step}</h2>
                  <p>{detail}</p>
                </div>
              </li>
            ))}
          </ol>

          {GROUPS.map((entry) => {
            const offset = SECTIONS.findIndex(
              (section) => section.title === entry.sections[0].title,
            );
            return (
              <section key={entry.group} className={styles.group}>
                <h2 className={styles.groupHeading}>{entry.group}</h2>
                <ol className={styles.sections}>
                  {entry.sections.map((section, index) => (
                    <Reveal key={section.title} as="li" delay={index * 0.04}>
                      <span className={styles.index}>
                        {String(offset + index + 1).padStart(2, "0")}
                      </span>
                      <div className={styles.sectionBody}>
                        <h3>{section.title}</h3>
                        {section.list ? (
                          <ul className={styles.pillars}>
                            {section.list.map((item) => (
                              <li key={item}>{item}</li>
                            ))}
                          </ul>
                        ) : null}
                        <p>{section.body}</p>
                        {section.callout ? (
                          <p className={styles.callout}>{section.callout}</p>
                        ) : null}
                      </div>
                    </Reveal>
                  ))}
                </ol>
              </section>
            );
          })}

          <ClosingPanel
            kicker="Use the index"
            title="Same questions. Same math. Your ballot."
            lede="Everything above runs the same way for you and for every figure we score. When betas open, you answer the questions once and the index does the rest."
            points={CLOSING_POINTS}
            primary={{ href: "/#waitlist", label: "Join the waitlist" }}
            secondary={{ href: "/contribute", label: "Fund the instrument" }}
            note="Think a score is wrong? Email hello@voteaxis.org with the figure and the issue."
            focus={{ x: 0.8, y: 0.42 }}
          />
        </div>
      </main>
      <SiteFooter />
    </div>
  );
}
