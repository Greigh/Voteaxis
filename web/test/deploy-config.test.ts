import { describe, expect, test } from "bun:test";
import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";

/**
 * Guards the class of bug that broke the Stripe webhook: a route was renamed
 * (/support -> /contribute) and the code moved, but the reverse-proxy configs
 * and the operator instructions kept pointing at the old path. Nothing failed
 * at build time — Stripe just started getting 404s and the contribution
 * notifications stopped, silently.
 *
 * The invariant is narrow on purpose. Only *actionable* references are checked:
 *
 *   - `location /api/...` in an nginx config, and
 *   - a fully-qualified `https://host/api/...` URL in docs or an env file
 *
 * Both are things a human or a dashboard will actually be pointed at. Bare
 * paths inside prose ("NOT /api/support/webhook", "Disallow: /api/") are
 * deliberately excluded, so a comment can still name a wrong path in order to
 * warn about it.
 */

const repoRoot = join(import.meta.dir, "..", "..");

/** Files that tell a human or a proxy where to send a request. */
const CONFIG_FILES = [
  "deploy/nginx.voteaxis.org.example",
  "deploy/Caddyfile.example",
  "web/.env.example",
  ".env.example",
  "server/.env.example",
  "DEPLOY.md",
  "README.md",
  "web/README.md",
  // Gitignored and absent on a fresh clone, but it is the file that carried the
  // stale webhook URL, so check it whenever it is there.
  "web/.env.production.local",
];

function read(rel: string): string | null {
  const path = join(repoRoot, rel);
  return existsSync(path) ? readFileSync(path, "utf8") : null;
}

/** Route path -> the file Next.js would need for it to resolve. */
function routeFileFor(apiPath: string): string {
  return join(repoRoot, "web", "app", apiPath.replace(/^\//, ""), "route.ts");
}

function actionableApiPaths(source: string): string[] {
  const found = new Set<string>();

  // nginx: location /api/contribute/webhook { ... }
  for (const m of source.matchAll(
    /^\s*location\s+(=\s*)?(\/api\/[\w\-/]+)/gm,
  )) {
    found.add(m[2].replace(/\/$/, ""));
  }

  // A URL someone pastes into a dashboard or a curl line.
  for (const m of source.matchAll(/https?:\/\/[^\s/]+(\/api\/[\w\-/]+)/g)) {
    found.add(m[1].replace(/\/$/, ""));
  }

  return [...found];
}

describe("deploy config references real routes", () => {
  test("every actionable /api path resolves to a route handler", () => {
    const checked: string[] = [];

    for (const rel of CONFIG_FILES) {
      const source = read(rel);
      if (source === null) continue;

      for (const apiPath of actionableApiPaths(source)) {
        const routeFile = routeFileFor(apiPath);
        checked.push(`${rel} -> ${apiPath}`);
        expect(
          existsSync(routeFile),
          `${rel} points at ${apiPath}, but ${routeFile.replace(`${repoRoot}/`, "")} does not exist`,
        ).toBe(true);
      }
    }

    // The guard is worthless if the extraction silently matched nothing.
    expect(checked.length).toBeGreaterThan(0);
  });

  test("the Stripe webhook route exists where the configs say it does", () => {
    expect(existsSync(routeFileFor("/api/contribute/webhook"))).toBe(true);
    // The path it was renamed away from must stay gone, so a stale dashboard
    // entry fails loudly rather than being quietly resurrected.
    expect(existsSync(routeFileFor("/api/support/webhook"))).toBe(false);
  });

  test("no config still instructs anyone to use the old /api/support path", () => {
    for (const rel of CONFIG_FILES) {
      const source = read(rel);
      if (source === null) continue;
      for (const apiPath of actionableApiPaths(source)) {
        expect(
          apiPath.startsWith("/api/support"),
          `${rel} still uses ${apiPath}`,
        ).toBe(false);
      }
    }
  });

  test("next.config redirects do not rescue a stale /api path", () => {
    // /support -> /contribute is a page redirect. It matches the two page
    // routes exactly and nothing under /api, which is precisely why a stale
    // webhook URL 404s instead of being forwarded. If that ever changes, the
    // reasoning in the comments above needs revisiting.
    const config = read("web/next.config.mjs");
    expect(config).not.toBeNull();
    const sources = [...(config ?? "").matchAll(/source:\s*"([^"]+)"/g)].map(
      (m) => m[1],
    );
    expect(sources.length).toBeGreaterThan(0);
    for (const source of sources) {
      expect(source.startsWith("/api")).toBe(false);
    }
  });
});

describe("secrets stay out of git", () => {
  const gitignore = readFileSync(join(repoRoot, ".gitignore"), "utf8");

  test("env files and their backup variants are ignored", () => {
    for (const pattern of [".env", ".env*.local", ".env*.bak"]) {
      expect(gitignore).toContain(pattern);
    }
  });

  test("the API and waitlist stores are ignored", () => {
    expect(gitignore).toContain("server/data/*.db");
    expect(gitignore).toContain("server/data/*.sqlite");
    expect(readFileSync(join(repoRoot, "web", ".gitignore"), "utf8")).toContain(
      "data/waitlist.jsonl",
    );
  });

  test("no example file carries a real credential", () => {
    // Placeholders only. A live key in a committed example is the classic way
    // one ends up in the history.
    for (const rel of [
      ".env.example",
      "web/.env.example",
      "server/.env.example",
    ]) {
      const source = read(rel) ?? "";
      expect(source).not.toMatch(/sk_live_[A-Za-z0-9]/);
      expect(source).not.toMatch(/whsec_[A-Za-z0-9]{16}/);
      expect(source).not.toMatch(/sk_test_[A-Za-z0-9]{16}/);
    }
  });
});

describe("API bind address is loopback in the shipped config", () => {
  test("server/.env.example pins HOST to loopback", () => {
    const source = read("server/.env.example") ?? "";
    const host = source.match(/^HOST=(.*)$/m)?.[1]?.trim();
    expect(host).toBe("127.0.0.1");
  });

  test("deploy.py refuses to ship a non-loopback HOST", () => {
    // The local .env is allowed to say 0.0.0.0 for LAN testing against a
    // phone; the deploy must overwrite it rather than pass it through.
    const deploy = read("scripts/deploy.py") ?? "";
    expect(deploy).toContain('"HOST=127.0.0.1"');
    // HOST must not be in the passthrough allowlist, or the pin is defeated.
    const allowlist =
      deploy.match(/API_ENV_ALLOWLIST = \(([\s\S]*?)\)/)?.[1] ?? "";
    expect(allowlist.length).toBeGreaterThan(0);
    expect(allowlist).not.toContain('"HOST"');
  });

  test("both proxy examples forward to loopback upstreams", () => {
    for (const rel of [
      "deploy/nginx.voteaxis.org.example",
      "deploy/Caddyfile.example",
    ]) {
      const source = read(rel) ?? "";
      const upstreams = [
        ...source.matchAll(
          /(?:proxy_pass|reverse_proxy)\s+(?:http:\/\/)?([\d.]+):(\d+)/g,
        ),
      ];
      expect(upstreams.length).toBeGreaterThan(0);
      for (const [, host] of upstreams) {
        expect(host).toBe("127.0.0.1");
      }
    }
  });

  /**
   * Both proxies terminate TLS for a page that renders data a stranger wrote
   * (/result/<id>), and both front a POST route that buffers its body before
   * validating it. Neither hardening step has a build-time failure mode, so
   * they only stay in place if something asserts they are there.
   */
  test("both proxy examples carry the security headers", () => {
    for (const rel of [
      "deploy/nginx.voteaxis.org.example",
      "deploy/Caddyfile.example",
    ]) {
      const source = read(rel) ?? "";
      expect(source).toContain("Strict-Transport-Security");
      expect(source).toContain("X-Content-Type-Options");
      expect(source).toContain("Permissions-Policy");
      // Report-only on the site (Next needs inline scripts), enforced on the
      // JSON-only API where there is nothing to render.
      expect(source).toContain("Content-Security-Policy-Report-Only");
      expect(source).toContain("default-src 'none'; frame-ancestors 'none'");
    }
  });

  test("both proxy examples cap the request body", () => {
    // The API enforces 64 KB itself, but nginx's default is 1 MB and Caddy has
    // no default at all — so the proxy is where an oversized body should die.
    const nginx = read("deploy/nginx.voteaxis.org.example") ?? "";
    expect(nginx).toContain("client_max_body_size 64k;");
    expect(nginx).toContain("client_max_body_size 1m;");

    const caddy = read("deploy/Caddyfile.example") ?? "";
    expect(caddy).toContain("max_size 64KB");
    expect(caddy).toContain("max_size 1MB");
  });

  /**
   * NEXT_PUBLIC_* is substituted into the client bundle by `next build`, so a
   * missing or wrong value fails at runtime in someone else's browser, long
   * after the deploy looked clean. /result/<id> is the first page that depends
   * on one pointing at a host the visitor can actually reach.
   */
  test("build-time public vars are pinned in the production env file", () => {
    const source = read("web/.env.production.local");
    if (source === null) return; // Gitignored; absent on a fresh clone.

    for (const key of ["NEXT_PUBLIC_SITE_URL", "NEXT_PUBLIC_API_URL"]) {
      const line = source
        .split("\n")
        .find((row) => row.trimStart().startsWith(`${key}=`));
      expect(
        line,
        `${key} is not set in web/.env.production.local`,
      ).toBeString();
      const value = (line as string).split("=").slice(1).join("=").trim();
      expect(value, `${key} is empty`).not.toBe("");
      // A loopback address builds fine and then breaks for every visitor.
      expect(value).not.toContain("127.0.0.1");
      expect(value).not.toContain("localhost");
      expect(value.endsWith("/"), `${key} must not have a trailing slash`).toBe(
        false,
      );
    }
  });

  test("the shared-result page reads the API base rather than hardcoding it", () => {
    const page = read("web/app/result/[id]/page.tsx") ?? "";
    expect(page).toContain("apiUrl()");
    expect(page).not.toContain("https://api.voteaxis.org");
  });
});
