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

module.exports = {
  apps: [
    {
      name: "voteaxis-api",
      cwd: __dirname,
      script: "src/index.ts",
      interpreter: bunBin(),
      // SQLite friend codes + BICAM + Congress.gov cache: one writer only.
      instances: 1,
      exec_mode: "fork",
      watch: false,
      autorestart: true,
      max_restarts: 10,
      min_uptime: "5s",
      exp_backoff_restart_delay: 200,
      max_memory_restart: "256M",
      kill_timeout: 4000,
      time: true,
      env: {
        NODE_ENV: "production",
        ...loadEnv(join(__dirname, ".env")),
      },
    },
  ],
};
