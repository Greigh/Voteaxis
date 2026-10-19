#!/usr/bin/env node
'use strict';

/**
 * Version & build synchronizer for Voteaxis (monorepo — the app lives in
 * mobile/).
 *
 * Keeps every place a version or build number lives in sync:
 *   1. mobile/pubspec.yaml (Flutter version: X.Y.Z+N)
 *   2. mobile/ios/Runner.xcodeproj/project.pbxproj (MARKETING_VERSION &
 *      CURRENT_PROJECT_VERSION)
 *   3. mobile/android/local.properties (flutter.versionName / flutter.versionCode)
 *   4. mobile/ios/Flutter/Generated.xcconfig + ephemeral env files
 *   5. docs/changelogs/android/whatsnew-en-US.txt (Play "What's New")
 *   6. docs/changelogs/ios/release_notes.txt (TestFlight / App Store notes)
 *
 * The store notes are generated, not copied: they cover every build since the
 * one that store serves the public, per docs/changelogs/production-builds.json.
 *
 * Commands:
 *   node scripts/native-versions.js           # report sync state, change nothing
 *   node scripts/native-versions.js --sync    # write pubspec's numbers everywhere
 *   node scripts/native-versions.js --bump    # mint the next build number and sync
 *
 * Build numbers are minted as max(pubspec, git tags v*.*.*+N, production-builds)
 * + 1 — the tags are the cross-branch build-number registry, so tag each
 * shipped build `v<version>+<build>` and push it.
 */

const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

const ROOT = path.join(__dirname, '..');
const MOBILE = path.join(ROOT, 'mobile');
const PUBSPEC = path.join(MOBILE, 'pubspec.yaml');
const PBXPROJ = path.join(MOBILE, 'ios/Runner.xcodeproj/project.pbxproj');
const ANDROID_LOCAL_PROPERTIES = path.join(MOBILE, 'android/local.properties');
const IOS_GENERATED_XCCONFIG = path.join(MOBILE, 'ios/Flutter/Generated.xcconfig');
const FLUTTER_ENV_FILES = [
  path.join(MOBILE, 'ios/Flutter/flutter_export_environment.sh'),
];
const CHANGELOGS_DIR = path.join(ROOT, 'docs/changelogs');
const ANDROID_WHATSNEW = path.join(CHANGELOGS_DIR, 'android/whatsnew-en-US.txt');
const IOS_RELEASE_NOTES = path.join(CHANGELOGS_DIR, 'ios/release_notes.txt');
const STORE_CHANGELOG_COPIES = [
  ['android', 'docs/changelogs/android/whatsnew-en-US.txt'],
  ['ios', 'docs/changelogs/ios/release_notes.txt'],
];
const PRODUCTION_BUILDS = path.join(CHANGELOGS_DIR, 'production-builds.json');

const NOTES_PLATFORMS = ['android', 'ios'];
const PLAY_NOTES_LIMIT = 500;
const APPLE_NOTES_LIMIT = 4000;

function readPubspec() {
  if (!fs.existsSync(PUBSPEC)) {
    throw new Error(`pubspec.yaml not found at ${PUBSPEC}`);
  }
  const content = fs.readFileSync(PUBSPEC, 'utf8');
  const m = content.match(/^version:\s*([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)/m);
  if (!m) {
    throw new Error('Could not parse version: X.Y.Z+N from mobile/pubspec.yaml');
  }
  return {
    versionName: m[1],
    versionCode: parseInt(m[2], 10),
  };
}

function writePubspec(versionName, versionCode) {
  let content = fs.readFileSync(PUBSPEC, 'utf8');
  content = content.replace(
    /^version:\s*[0-9]+\.[0-9]+\.[0-9]+\+[0-9]+/m,
    `version: ${versionName}+${versionCode}`
  );
  fs.writeFileSync(PUBSPEC, content, 'utf8');
}

function writePbxproj(versionName, versionCode) {
  if (!fs.existsSync(PBXPROJ)) return;
  let content = fs.readFileSync(PBXPROJ, 'utf8');
  content = content.replace(
    /MARKETING_VERSION = [0-9]+(\.[0-9]+)+;/g,
    `MARKETING_VERSION = ${versionName};`
  );
  content = content.replace(
    /CURRENT_PROJECT_VERSION = [0-9]+;/g,
    `CURRENT_PROJECT_VERSION = ${versionCode};`
  );
  fs.writeFileSync(PBXPROJ, content, 'utf8');
}

function upsertKeyValue(content, key, value, separator = '=') {
  const re = new RegExp(`^${key}\\s*${separator}.*$`, 'm');
  const line = `${key}${separator}${value}`;
  if (re.test(content)) {
    return content.replace(re, line);
  }
  const trimmed = content.replace(/\s*$/, '');
  return `${trimmed}\n${line}\n`;
}

/**
 * Keep Flutter tool caches in lockstep with pubspec. Stale
 * FLUTTER_BUILD_NUMBER / flutter.versionCode is how wrong build numbers ship.
 */
function writeFlutterToolVersions(versionName, versionCode) {
  if (fs.existsSync(ANDROID_LOCAL_PROPERTIES)) {
    let content = fs.readFileSync(ANDROID_LOCAL_PROPERTIES, 'utf8');
    content = upsertKeyValue(content, 'flutter.versionName', versionName);
    content = upsertKeyValue(content, 'flutter.versionCode', String(versionCode));
    fs.writeFileSync(ANDROID_LOCAL_PROPERTIES, content, 'utf8');
  }

  if (fs.existsSync(IOS_GENERATED_XCCONFIG)) {
    let content = fs.readFileSync(IOS_GENERATED_XCCONFIG, 'utf8');
    content = upsertKeyValue(content, 'FLUTTER_BUILD_NAME', versionName);
    content = upsertKeyValue(content, 'FLUTTER_BUILD_NUMBER', String(versionCode));
    fs.writeFileSync(IOS_GENERATED_XCCONFIG, content, 'utf8');
  }

  for (const envFile of FLUTTER_ENV_FILES) {
    if (!fs.existsSync(envFile)) continue;
    let content = fs.readFileSync(envFile, 'utf8');
    content = content.replace(
      /FLUTTER_BUILD_NAME=[0-9]+(?:\.[0-9]+)*/g,
      `FLUTTER_BUILD_NAME=${versionName}`
    );
    content = content.replace(
      /FLUTTER_BUILD_NUMBER=[0-9]+/g,
      `FLUTTER_BUILD_NUMBER=${versionCode}`
    );
    fs.writeFileSync(envFile, content, 'utf8');
  }
}

function readProductionBuilds() {
  if (!fs.existsSync(PRODUCTION_BUILDS)) return {};
  return JSON.parse(fs.readFileSync(PRODUCTION_BUILDS, 'utf8'));
}

/**
 * The highest build number ever minted: the max of pubspec, every
 * `vX.Y.Z+N` git tag, and every build production-builds.json says a store
 * serves the public. Pubspec alone is per-branch; Play rejects a reused
 * versionCode outright while every notes file keyed by build number silently
 * collides. Tags are the registry: tag each release commit `v<version>+<build>`
 * when it ships.
 */
function highWaterBuild({ root = ROOT } = {}) {
  let best = readPubspec().versionCode;
  const prod = readProductionBuilds();
  for (const platform of Object.values(prod)) {
    if (Number.isInteger(platform?.build)) best = Math.max(best, platform.build);
  }
  try {
    execSync('git fetch --all --tags --quiet', {
      cwd: root,
      stdio: 'ignore',
      timeout: 15000,
    });
  } catch {
    // Offline or not a repo — local refs still bound the number.
  }
  let tags = '';
  try {
    tags = execSync('git tag --list "v*.*.*+*"', {
      cwd: root,
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'ignore'],
    });
  } catch {
    // No git or no matching tags.
  }
  for (const m of tags.matchAll(/^v\d+\.\d+\.\d+\+(\d+)$/gm)) {
    best = Math.max(best, parseInt(m[1], 10));
  }
  return best;
}

/**
 * What build [versionCode] still needs before it can be synced: its notes file
 * on each platform (first line naming this build and version).
 */
function missingReleaseNotes(versionCode, { changelogsDir = CHANGELOGS_DIR, versionName } = {}) {
  const missing = [];
  for (const platform of NOTES_PLATFORMS) {
    const label = `docs/changelogs/${platform}/${versionCode}.txt`;
    const file = path.join(changelogsDir, platform, `${versionCode}.txt`);
    const text = fs.existsSync(file) ? fs.readFileSync(file, 'utf8').trim() : '';
    const header = text.split('\n')[0];
    if (!header.includes(`(Build ${versionCode})`)) {
      missing.push(label);
    } else if (versionName && !header.includes(versionName)) {
      missing.push(`${label} (names "${header}", not version ${versionName})`);
    } else if (platform === 'android' && text.length > PLAY_NOTES_LIMIT) {
      missing.push(`${label} (over ${PLAY_NOTES_LIMIT} characters)`);
    }
  }
  return missing;
}

function assertReleaseNotes(versionName, versionCode) {
  const missing = missingReleaseNotes(versionCode, { versionName });
  if (missing.length === 0) return;
  throw new Error(
    `Build ${versionCode} has no release notes yet, so nothing was changed. Write these first ` +
      `(first line "Voteaxis ${versionName} (Build ${versionCode})"; see docs/changelogs/README.md):\n` +
      missing.map((m) => `   - ${m}`).join('\n'),
  );
}

/**
 * The builds a store's "What's New" must cover: every build with a notes file
 * that is newer than the build that store serves the public, newest first.
 * `live` is the build currently served (versionCode when the store has none or
 * already serves this one, so the range is just the release being cut).
 */
function coveredBuilds(
  platform,
  versionCode,
  { changelogsDir = CHANGELOGS_DIR, productionBuilds = PRODUCTION_BUILDS } = {},
) {
  let live = versionCode;
  try {
    const prod = JSON.parse(fs.readFileSync(productionBuilds, 'utf8'));
    const b = prod?.[platform]?.build;
    if (Number.isInteger(b) && b < versionCode) live = b;
  } catch {
    // No production manifest — nothing public to diff against.
  }
  const builds = [];
  for (let b = versionCode; b > live; b--) {
    if (fs.existsSync(path.join(changelogsDir, platform, `${b}.txt`))) {
      builds.push(b);
    }
  }
  return { builds, live };
}

/**
 * The "What's New" text a store shows for [versionCode]: every build newer
 * than the one that store serves the public, per production-builds.json.
 * Newest build's bullets lead, then one bullet per build per round (newest
 * first) until the platform's character limit is reached, so no covered build
 * is crowded out by its successors. Exact-duplicate bullets are dropped once.
 */
function storeNotesForRelease(
  platform,
  versionName,
  versionCode,
  { changelogsDir = CHANGELOGS_DIR, productionBuilds = PRODUCTION_BUILDS } = {},
) {
  const readBuild = (b) => {
    const f = path.join(changelogsDir, platform, `${b}.txt`);
    return fs.existsSync(f) ? fs.readFileSync(f, 'utf8') : null;
  };
  const newFile = readBuild(versionCode);
  if (newFile === null) return null;

  const { builds, live } = coveredBuilds(platform, versionCode, {
    changelogsDir,
    productionBuilds,
  });
  if (builds.length <= 1) return newFile;

  const bulletsOf = (text) =>
    text
      .split(/\r?\n/)
      .map((l) => l.trim())
      .filter((l) => l.startsWith('•'));
  const seen = new Set();
  const perBuild = builds.map((b) =>
    bulletsOf(readBuild(b)).filter((l) => {
      const k = l.toLowerCase().replace(/\s+/g, ' ');
      if (seen.has(k)) return false;
      seen.add(k);
      return true;
    }),
  );

  const limit = platform === 'android' ? PLAY_NOTES_LIMIT : APPLE_NOTES_LIMIT;
  const header = `Voteaxis ${versionName} (Build ${versionCode})`;
  const fits = (lines) => `${header}\n\n${lines.join('\n')}\n`.length <= limit;

  const picked = [];
  let droppedAny = false;
  for (let round = 0; ; round++) {
    let progressed = false;
    for (const bullets of perBuild) {
      const bullet = bullets[round];
      if (bullet === undefined) continue;
      if (fits(picked.concat(bullet))) {
        picked.push(bullet);
        progressed = true;
      } else {
        droppedAny = true;
      }
    }
    if (!progressed) break;
  }
  const total = perBuild.reduce((n, b) => n + b.length, 0);
  droppedAny = droppedAny || picked.length < total;
  const trailer = `• And more changes since build ${live}`;
  if (droppedAny) {
    while (picked.length > 1 && !fits(picked.concat(trailer))) picked.pop();
    if (fits(picked.concat(trailer))) picked.push(trailer);
  }

  return `${header}\n\n${picked.join('\n')}\n`;
}

/** Writes the generated release notes into the files the stores read. */
function syncStoreChangelogs(versionName, versionCode) {
  for (const [platform, relative] of STORE_CHANGELOG_COPIES) {
    const content = storeNotesForRelease(platform, versionName, versionCode);
    if (content === null) continue; // missingReleaseNotes already reported it
    fs.writeFileSync(path.join(ROOT, relative), content, 'utf8');
  }
}

function syncAll(versionName, versionCode) {
  assertReleaseNotes(versionName, versionCode);
  writePubspec(versionName, versionCode);
  writePbxproj(versionName, versionCode);
  writeFlutterToolVersions(versionName, versionCode);
  syncStoreChangelogs(versionName, versionCode);

  console.log(`\n======================================================`);
  console.log(`  🚀 Voteaxis Version Synced: v${versionName} (Build ${versionCode})`);
  console.log(`======================================================`);
  console.log(`  ✓ mobile/pubspec.yaml:                 ${versionName}+${versionCode}`);
  console.log(`  ✓ iOS project.pbxproj:                 MARKETING=${versionName}, CURRENT=${versionCode}`);
  console.log(`  ✓ Flutter tool caches:                 versionName/versionCode`);
  console.log(`  ✓ Store changelogs:                    whatsnew-en-US.txt, release_notes.txt`);
  console.log(`======================================================\n`);
}

function checkSync() {
  const { versionName, versionCode } = readPubspec();
  console.log(`pubspec: v${versionName} (Build ${versionCode})`);

  let drift = false;
  if (fs.existsSync(PBXPROJ)) {
    const pbx = fs.readFileSync(PBXPROJ, 'utf8');
    const marketing = [...pbx.matchAll(/MARKETING_VERSION = ([0-9.]+);/g)].map((m) => m[1]);
    const current = [...pbx.matchAll(/CURRENT_PROJECT_VERSION = ([0-9]+);/g)].map((m) => m[1]);
    const badMarketing = marketing.filter((v) => v !== versionName);
    const badCurrent = current.filter((v) => v !== String(versionCode));
    if (badMarketing.length || badCurrent.length) {
      drift = true;
      console.log(`  ✗ pbxproj drift: MARKETING=${badMarketing.join(',') || 'ok'} CURRENT=${badCurrent.join(',') || 'ok'}`);
    }
  }

  const missing = missingReleaseNotes(versionCode, { versionName });
  for (const m of missing) console.log(`  ✗ ${m}`);

  if (!drift && missing.length === 0) {
    console.log('  ✓ everything in sync');
  }
  return drift || missing.length > 0 ? 1 : 0;
}

function bumpBuild() {
  const { versionName } = readPubspec();
  const next = highWaterBuild() + 1;
  const missing = missingReleaseNotes(next, { versionName });
  if (missing.length) {
    console.error(
      `Next build would be ${next}, but it has no release notes yet. Write these first ` +
        `(first line "Voteaxis ${versionName} (Build ${next})"; see docs/changelogs/README.md):\n` +
        missing.map((m) => `   - ${m}`).join('\n'),
    );
    process.exit(1);
  }
  syncAll(versionName, next);
  console.log(`Next build number: ${next}`);
  console.log(`Tag the release commit when it ships: git tag v${versionName}+${next} && git push --tags`);
}

function main() {
  const args = process.argv.slice(2);
  if (args.includes('--bump')) {
    bumpBuild();
  } else if (args.includes('--sync')) {
    const { versionName, versionCode } = readPubspec();
    syncAll(versionName, versionCode);
  } else {
    process.exit(checkSync());
  }
}

module.exports = {
  readPubspec,
  writePubspec,
  writePbxproj,
  writeFlutterToolVersions,
  highWaterBuild,
  missingReleaseNotes,
  storeNotesForRelease,
  syncAll,
  bumpBuild,
};

if (require.main === module) {
  main();
}
