import { describe, expect, test } from "bun:test";
import type { Metadata } from "next";
import { GET as llmsTxt } from "../app/llms.txt/route";
import manifest from "../app/manifest";
import robots from "../app/robots";
import sitemap from "../app/sitemap";
import { OG_IMAGE } from "../lib/site";
import {
  breadcrumbs,
  methodologyGraph,
  serializeJsonLd,
  siteGraph,
} from "../lib/structured-data";

type Rule = {
  userAgent?: string | string[];
  allow?: string | string[];
  disallow?: string | string[];
};

function rulesFor(agent: string): Rule[] {
  const file = robots();
  const rules = (
    Array.isArray(file.rules) ? file.rules : [file.rules]
  ) as Rule[];
  return rules.filter((rule) => {
    const ua = rule.userAgent;
    return Array.isArray(ua) ? ua.includes(agent) : ua === agent;
  });
}

describe("marketing metadata", () => {
  test("sitemap lists home, methodology, and contribute", () => {
    const entries = sitemap();
    const urls = entries.map((row) => row.url);
    expect(urls.some((url) => url.endsWith("voteaxis.org"))).toBe(true);
    expect(urls.some((url) => url.includes("/methodology"))).toBe(true);
    expect(urls.some((url) => url.includes("/contribute"))).toBe(true);
  });

  test("sitemap omits the noindex thanks page", () => {
    expect(sitemap().some((row) => row.url.includes("/thanks"))).toBe(false);
  });

  test("robots allow the site and block /api and shared results", () => {
    const file = robots();
    expect(file.sitemap).toContain("/sitemap.xml");
    const wildcard = rulesFor("*")[0];
    expect(wildcard?.allow).toBe("/");
    // /result/<id> is one person's placement behind a revocable link.
    expect(wildcard?.disallow).toEqual(["/api/", "/result/"]);
  });
});

describe("AI crawler policy", () => {
  test("answer engines are allowed the site", () => {
    for (const agent of [
      "OAI-SearchBot",
      "PerplexityBot",
      "Claude-SearchBot",
    ]) {
      const rule = rulesFor(agent)[0];
      expect(rule, `${agent} has no rule`).toBeDefined();
      expect(rule?.allow).toBe("/");
    }
  });

  test("training-only scrapers are blocked", () => {
    for (const agent of ["GPTBot", "ClaudeBot", "CCBot", "Bytespider"]) {
      const rule = rulesFor(agent)[0];
      expect(rule, `${agent} has no rule`).toBeDefined();
      expect(rule?.disallow).toBe("/");
      expect(rule?.allow).toBeUndefined();
    }
  });

  test("every named group restates the private paths, since groups do not inherit", () => {
    for (const rule of rulesFor("OAI-SearchBot").concat(
      rulesFor("Amazonbot"),
    )) {
      expect(rule.disallow).toEqual(["/api/", "/result/"]);
    }
  });

  test("link-preview fetchers are never named, so they fall through to *", () => {
    for (const agent of [
      "facebookexternalhit",
      "Twitterbot",
      "LinkedInBot",
      "Slackbot",
      "Discordbot",
    ]) {
      expect(rulesFor(agent), `${agent} must not have its own group`).toEqual(
        [],
      );
    }
  });

  test("no agent appears in both the allow and block lists", () => {
    const file = robots();
    const rules = (
      Array.isArray(file.rules) ? file.rules : [file.rules]
    ) as Rule[];
    const seen = new Set<string>();
    for (const rule of rules) {
      const agents = Array.isArray(rule.userAgent)
        ? rule.userAgent
        : [rule.userAgent ?? ""];
      for (const agent of agents) {
        expect(seen.has(agent), `${agent} is listed twice`).toBe(false);
        seen.add(agent);
      }
    }
  });
});

describe("llms.txt", () => {
  test("is plain text and states the mobile-only constraint", async () => {
    const res = llmsTxt();
    expect(res.headers.get("Content-Type")).toContain("text/plain");
    const text = await res.text();
    expect(text.startsWith("# Voteaxis")).toBe(true);
    expect(text).toContain("only in the iOS and Android app");
    expect(text).toContain("voteaxis.org/methodology");
  });
});

describe("structured data", () => {
  test("site graph carries org, website, and app with cross-referenced ids", () => {
    const graph = siteGraph()["@graph"] as Record<string, unknown>[];
    const types = graph.map((node) => node["@type"]);
    expect(types).toEqual(["Organization", "WebSite", "MobileApplication"]);

    const ids = new Set(graph.map((node) => node["@id"] as string));
    const website = graph[1] as { publisher: { "@id": string } };
    expect(ids.has(website.publisher["@id"])).toBe(true);
  });

  test("app node claims nothing it cannot back up before launch", () => {
    const app = (siteGraph()["@graph"] as Record<string, unknown>[])[2];
    expect(app.aggregateRating).toBeUndefined();
    expect(app.offers).toBeUndefined();
    expect(app.downloadUrl).toBeUndefined();
    expect(app.isAccessibleForFree).toBe(true);
  });

  test("breadcrumbs start at home and number from one", () => {
    const trail = breadcrumbs([{ name: "Contribute", path: "/contribute" }]);
    const items = trail.itemListElement as Record<string, unknown>[];
    expect(items).toHaveLength(2);
    expect(items[0].name).toBe("Home");
    expect(items[0].position).toBe(1);
    expect(items[1].item).toContain("/contribute");
  });

  test("methodology article mirrors the section titles it is given", () => {
    const graph = methodologyGraph(["Issues", "Five pillars"]);
    expect(graph.articleSection).toEqual(["Issues", "Five pillars"]);
    expect(graph.url).toContain("/methodology");
  });

  test("serializer escapes < so a stray tag cannot break out of the script", () => {
    const json = serializeJsonLd({ name: "<script>alert(1)</script>" });
    expect(json).not.toContain("<");
    expect(json).toContain("\\u003c");
  });
});

describe("social card images", () => {
  // Declaring `openGraph` on a page REPLACES the inherited root object rather
  // than merging into it, so the file-convention image silently disappears
  // from that page's link previews unless it names OG_IMAGE itself.
  test.each([
    ["methodology", () => import("../app/methodology/page")],
    ["contribute", () => import("../app/contribute/page")],
  ])(
    "%s declares an image alongside its openGraph override",
    async (_name, load) => {
      const { metadata } = (await load()) as { metadata: Metadata };
      expect(metadata.openGraph).toBeDefined();
      expect(metadata.openGraph?.images).toEqual([OG_IMAGE]);
      expect(metadata.twitter?.images).toEqual([OG_IMAGE]);
    },
  );
});

describe("web app manifest", () => {
  test("declares icons that exist at the sizes install prompts require", () => {
    const sizes = (manifest().icons ?? []).map((icon) => icon.sizes);
    expect(sizes).toContain("192x192");
    expect(sizes).toContain("512x512");
    expect(
      (manifest().icons ?? []).some((icon) => icon.purpose === "maskable"),
    ).toBe(true);
  });
});
