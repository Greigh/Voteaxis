import type { Metadata, Viewport } from "next";
import { IBM_Plex_Mono, Manrope } from "next/font/google";
import { JsonLd } from "@/components/json-ld";
import {
  ORG_NAME,
  SITE_DESCRIPTION,
  SITE_DESCRIPTION_SHORT,
  SITE_NAME,
  SITE_TAGLINE,
  SOCIAL_HANDLE,
  siteUrl,
} from "@/lib/site";
import { siteGraph } from "@/lib/structured-data";
import "./globals.css";

const sans = Manrope({
  subsets: ["latin"],
  variable: "--font-sans",
});

const mono = IBM_Plex_Mono({
  subsets: ["latin"],
  weight: ["400", "500", "600"],
  variable: "--font-mono",
});

const socialTitle = `${SITE_NAME} — See where you stand`;

export const metadata: Metadata = {
  metadataBase: new URL(siteUrl()),
  title: {
    default: `${SITE_NAME} — ${SITE_TAGLINE}`,
    template: `%s · ${SITE_NAME}`,
  },
  description: SITE_DESCRIPTION,
  applicationName: SITE_NAME,
  authors: [{ name: ORG_NAME }],
  creator: ORG_NAME,
  publisher: ORG_NAME,
  category: "politics",
  keywords: [
    "voteaxis",
    "political quiz",
    "political spectrum test",
    "ballot matching",
    "candidate match quiz",
    "liberal conservative",
    "voter guide",
    "Michigan elections",
    "Spectrum Issue Index",
  ],
  openGraph: {
    type: "website",
    locale: "en_US",
    url: siteUrl(),
    siteName: SITE_NAME,
    title: socialTitle,
    description: SITE_DESCRIPTION_SHORT,
  },
  twitter: {
    card: "summary_large_image",
    site: SOCIAL_HANDLE,
    creator: SOCIAL_HANDLE,
    title: socialTitle,
    description: SITE_DESCRIPTION_SHORT,
  },
  robots: {
    index: true,
    follow: true,
    googleBot: {
      index: true,
      follow: true,
      "max-image-preview": "large",
      "max-snippet": -1,
      "max-video-preview": -1,
    },
  },
  alternates: {
    canonical: "/",
  },
  // Console/Webmaster ownership. Unset in dev and on any deploy that has not
  // claimed the property — Next omits the tag rather than emitting an empty one.
  verification: {
    google: process.env.GOOGLE_SITE_VERIFICATION,
    other: process.env.BING_SITE_VERIFICATION
      ? { "msvalidate.01": process.env.BING_SITE_VERIFICATION }
      : undefined,
  },
  // icon.png / apple-icon.png in app/ are picked up by file convention.
};

export const viewport: Viewport = {
  themeColor: "#07111f",
  width: "device-width",
  initialScale: 1,
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en" data-scroll-behavior="smooth">
      <body className={`${sans.variable} ${mono.variable}`}>
        <JsonLd data={siteGraph()} />
        {children}
      </body>
    </html>
  );
}
