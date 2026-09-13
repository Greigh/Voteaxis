import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { ResultView } from "@/components/result-view";
import { SiteFooter, SiteHeader } from "@/components/site-chrome";
import type { ResultResponse } from "@/lib/result";
import { apiUrl } from "@/lib/site";
import styles from "./result.module.css";

const ID = /^[23456789abcdefghjkmnpqrstuvwxyz]{16}$/;

/**
 * A shared result is one person's placement behind a link they can revoke.
 * Never index it, and never let a stale copy leak a result that was taken
 * down or re-shared.
 */
export const metadata: Metadata = {
  title: "A shared result",
  description: "Someone shared where they landed on the Voteaxis spectrum.",
  robots: { index: false, follow: false },
};

export const dynamic = "force-dynamic";

async function fetchResult(id: string): Promise<ResultResponse | null> {
  try {
    const res = await fetch(`${apiUrl()}/v1/results/${id}`, {
      cache: "no-store",
    });
    if (!res.ok) return null;
    const body = (await res.json()) as ResultResponse;
    return body.ok ? body : null;
  } catch {
    return null;
  }
}

export default async function ResultPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  if (!ID.test(id)) notFound();

  const result = await fetchResult(id);
  if (!result) {
    return (
      <div className={styles.shell}>
        <SiteHeader />
        <main className={styles.main}>
          <div className={styles.inner}>
            <h1 className={styles.title}>This link is no longer live</h1>
            <p className={styles.body}>
              Shared results expire, and whoever sent it can take it down at any
              time. Ask them for a fresh link.
            </p>
            <Link className={styles.cta} href="/">
              See what Voteaxis is
            </Link>
          </div>
        </main>
        <SiteFooter />
      </div>
    );
  }

  return (
    <div className={styles.shell}>
      <SiteHeader />
      <main className={styles.main}>
        <div className={styles.inner}>
          <p className={styles.eyebrow}>SHARED RESULT</p>
          <h1 className={styles.title}>Where they landed</h1>
          <p className={styles.body}>
            Scored with the Spectrum Issue Index on{" "}
            <Link href="/methodology">the same scale</Link> everyone else uses.
            This page is not indexed, and the person who shared it can take it
            down whenever they want.
          </p>
          <ResultView initial={result} />
          <Link className={styles.cta} href="/">
            Find out where you land
          </Link>
        </div>
      </main>
      <SiteFooter />
    </div>
  );
}
