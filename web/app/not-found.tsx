import type { Metadata } from "next";
import { ClosingPanel } from "@/components/closing-panel";
import { SiteFooter, SiteHeader } from "@/components/site-chrome";

export const metadata: Metadata = {
  title: "Page not found",
  description: "That route isn’t on the spectrum.",
  robots: { index: false, follow: true },
};

const CLOSING_POINTS = [
  {
    label: "Methodology",
    href: "/methodology",
    body: "How the Spectrum Issue Index scores you and everyone on your ballot.",
  },
  {
    label: "Contribute",
    href: "/contribute",
    body: "Fund independent scoring and state-level data. The civic loop stays free.",
  },
  {
    label: "Broken link",
    body: "If something on this site sent you here, email hello@voteaxis.org with the page you came from.",
  },
] as const;

export default function NotFound() {
  return (
    <div className="notFoundShell">
      <SiteHeader />
      <main className="notFoundMain">
        <p className="notFoundCode">404</p>
        <h1>Page not found</h1>
        <ClosingPanel
          kicker="Where to go instead"
          title="That route isn’t on the spectrum"
          lede="The page moved, or it never existed. Everything on this site is one hop away."
          points={CLOSING_POINTS}
          primary={{ href: "/", label: "Back to home" }}
          secondary={{ href: "/#waitlist", label: "Join the waitlist" }}
          focus={{ x: 0.8, y: 0.5 }}
        />
      </main>
      <SiteFooter />
    </div>
  );
}
