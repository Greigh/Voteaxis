const { execSync } = require("node:child_process");
const { existsSync, readFileSync } = require("node:fs");
const { join } = require("node:path");

function bunBin() {
  if (process.env.BUN_BIN) return process.env.BUN_BIN;
  try {
    return execSync("command -v bun", { encoding: "utf8" }).trim();
  } catch {
    return "bun";
  }
}

function loadEnv(path) {
  const env = {};
  if (!existsSync(path)) return env;
  for (const line of readFileSync(path, "utf8").split("\n")) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith("#")) continue;
    const eq = trimmed.indexOf("=");
    if (eq === -1) continue;
    const key = trimmed.slice(0, eq).trim();
    let value = trimmed.slice(eq + 1).trim();
    if (
      (value.startsWith('"') && value.endsWith('"')) ||
      (value.startsWith("'") && value.endsWith("'"))
    ) {
      value = value.slice(1, -1);
    }
    env[key] = value;
  }
  return env;
}

// Next loads .env.production.local itself for app code, but the HTTP server
// boots before any of that: PORT must be a real env var, so PM2 injects it.
const fileEnv = loadEnv(join(__dirname, ".env.production.local"));

module.exports = {
  apps: [
    {
      name: "voteaxis-web",
      cwd: __dirname,
      script: "node_modules/next/dist/bin/next",
      // -H explicitly: `next start` defaults to 0.0.0.0 and, unlike --port,
      // has no env fallback. nginx proxies to 127.0.0.1:3020.
      // 3020 and not 3000: this VPS is shared, and 3000/3001/3010 are
      // already taken by the other sites on the box.
      args: "start -H 127.0.0.1",
      interpreter: bunBin(),
      // Waitlist JSONL is append-only from this process: one writer only.
      instances: 1,
      exec_mode: "fork",
      watch: false,
      autorestart: true,
      max_restarts: 10,
      min_uptime: "5s",
      exp_backoff_restart_delay: 200,
      max_memory_restart: "512M",
      // Next drains in-flight requests and pending after() callbacks on
      // SIGINT/SIGTERM; the docs ask for 10-30s before the hard kill.
      kill_timeout: 15000,
      time: true,
      env: {
        NODE_ENV: "production",
        PORT: "3020",
        ...fileEnv,
      },
    },
  ],
};
