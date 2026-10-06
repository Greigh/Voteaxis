import type { Metadata } from "next";
import { DocPage, type DocSection } from "@/components/doc-page";
import styles from "@/components/doc-page.module.css";
import { JsonLd } from "@/components/json-ld";
import { SiteFooter, SiteHeader } from "@/components/site-chrome";
import { CONTACT_EMAIL, OG_IMAGE } from "@/lib/site";
import { breadcrumbs, pageGraph } from "@/lib/structured-data";

const DESCRIPTION =
  "Quiz answers never leave your phone. What Voteaxis stores, where, and how to take it down.";

export const metadata: Metadata = {
  title: "Privacy",
  description: DESCRIPTION,
  alternates: {
    canonical: "/privacy",
  },
  openGraph: {
    type: "website",
    url: "/privacy",
    title: "Privacy · Voteaxis",
    description: DESCRIPTION,
    images: [OG_IMAGE],
  },
  twitter: {
    title: "Privacy · Voteaxis",
    description: DESCRIPTION,
    images: [OG_IMAGE],
  },
};

const SECTIONS: readonly DocSection[] = [
  {
    title: "The short version",
    body: "Voteaxis has no accounts, no ads, no analytics SDK, and no tracking pixels. Your quiz answers are scored on your phone and never leave it. The only things our server ever sees are the ones you deliberately send it — a friend code, a shared result link, or a device key — and each one is revocable or expires on its own.",
  },
  {
    title: "What stays on your phone",
    list: [
      "Quiz answers (your Likert responses) — never transmitted, period.",
      "Your placement: axis score, pillar scores, and issue scores — stored in the platform keychain / encrypted storage.",
      "Saved runs and in-progress quizzes — same secure store.",
      "Settings and your home state — plain local storage, on-device only.",
    ],
    body: "Deleting the app deletes all of it. Settings → Delete everything wipes it without uninstalling.",
  },
  {
    title: "What the server sees, and only when you ask",
    list: [
      "Friend compare — publishing a 6-digit code stores your issue scores and axis for 48 hours. No Likert answers, no email, no device id. The code expires on its own.",
      "Shared result links — voteaxis.org/result/<id> stores the result payload until you revoke it. Password-protected links are encrypted on your phone first (AES-GCM under a PBKDF2 key): the server stores bytes it cannot read.",
      "Roster refresh — the app checks for an updated politician roster with a signed request from a device keypair generated on your phone. The server stores only the public key and timestamps — no IP, no identifier.",
      "Issue of the Week — a plain fetch of the current prompt. Nothing is sent.",
    ],
  },
  {
    title: "Server logs",
    body: "Our API rate-limits by IP address and logs failed roster-auth attempts — the IP and the route, never the credential tried. The VPS also keeps ordinary nginx and process logs. We do not ship logs to anyone.",
  },
  {
    title: "This website",
    list: [
      "Waitlist signups store your email and the teacher / newsroom checkboxes in a file on our own server — not a third-party mailing list.",
      "Contributions go through Stripe Checkout. Card numbers never touch our servers; we receive your email and the amount.",
      "No cookies for tracking, no fingerprinting, no third-party analytics.",
    ],
  },
  {
    title: "Third-party requests",
    body: "The app talks to our API at api.voteaxis.org and nothing else — fonts are bundled, there is no ad network, and no crash-reporting SDK. The marketing site is self-hosted on the same VPS.",
  },
  {
    title: "Your controls",
    list: [
      "Revoke a shared link at any time from Share & transfer — the page goes dead immediately.",
      "Friend codes die on their own after 48 hours.",
      "Settings → Delete everything erases runs, placement, and settings on that phone.",
      "To remove a waitlist email or ask a deletion question, write us — see below.",
    ],
  },
  {
    title: "Children",
    body: "Voteaxis is about American politics and is not directed at children under 13. We do not knowingly collect anything from anyone — there is no mechanism to.",
  },
  {
    title: "Changes",
    body: "If this policy changes, the change ships with an app update and the date above moves. We will not retroactively collect anything described here as staying on-device.",
  },
];

export default function PrivacyPage() {
  return (
    <>
      <JsonLd
        data={pageGraph({
          name: "Privacy",
          description: DESCRIPTION,
          path: "/privacy",
        })}
      />
      <JsonLd data={breadcrumbs([{ name: "Privacy", path: "/privacy" }])} />
      <SiteHeader />
      <DocPage
        eyebrow="Privacy policy"
        title="Your answers stay on your phone"
        lede={DESCRIPTION}
        updated="Last updated October 2026"
        sections={SECTIONS}
        focus={{ x: 0.3, y: 0.35 }}
      >
        <p className={styles.note}>
          Questions, corrections, or deletion requests:{" "}
          <a href={`mailto:${CONTACT_EMAIL}`}>{CONTACT_EMAIL}</a>. The Greigh
          Studios LLC runs both the app and this site.
        </p>
      </DocPage>
      <SiteFooter />
    </>
  );
}
