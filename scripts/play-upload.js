#!/usr/bin/env node
'use strict';

/**
 * Build & Upload Release AAB to Google Play Console.
 *
 * Usage:
 *   node scripts/play-upload.js --build                    # Build release AAB and upload
 *   node scripts/play-upload.js --build --track beta       # Upload to beta track
 *   node scripts/play-upload.js --bump --build             # Bump build code, build, and upload
 *   node scripts/play-upload.js path/to/app-release.aab    # Upload existing bundle
 *
 * Environment variables (loaded from .env):
 *   GOOGLE_PLAY_SA_LOCAL — Service account JSON file path (dev machines)
 *   GOOGLE_PLAY_SERVICE_ACCOUNT_JSON — the service-account JSON inline (CI)
 *   GOOGLE_PLAY_PACKAGE — Default: com.greighstudios.voteaxis
 *   GOOGLE_PLAY_TRACK   — internal | alpha | beta | production (Default: internal)
 *   GOOGLE_PLAY_ROLLOUT — Staged rollout fraction (e.g. 0.1 for 10%, default: 1.0)
 */

const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');
const { google } = require('googleapis');
const nativeVersions = require('./native-versions');
const { resolveServiceAccount } = require('./lib/service-account');

const ROOT = path.join(__dirname, '..');
const MOBILE = path.join(ROOT, 'mobile');
const DEFAULT_AAB = path.join(MOBILE, 'build/app/outputs/bundle/release/app-release.aab');
const DEFAULT_MAPPING = path.join(MOBILE, 'build/app/outputs/mapping/release/mapping.txt');

const TRACKS = ['internal', 'alpha', 'beta', 'production'];
const TRACK_LABELS = {
  internal: 'Internal Testing',
  alpha: 'Closed Testing',
  beta: 'Open Testing',
  production: 'Production Release',
};

function loadEnvFile() {
  const envPath = path.join(ROOT, '.env');
  if (!fs.existsSync(envPath)) return;
  for (const line of fs.readFileSync(envPath, 'utf8').split('\n')) {
    const m = line.match(/^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*?)\s*$/);
    if (!m) continue;
    const key = m[1];
    if (process.env[key] != null && process.env[key] !== '') continue;
    let val = m[2];
    if ((val.startsWith('"') && val.endsWith('"')) || (val.startsWith("'") && val.endsWith("'"))) {
      val = val.slice(1, -1);
    }
    process.env[key] = val;
  }
}

function parseArgs(argv) {
  let build = false;
  let bump = false;
  let aab = null;
  let track = null;
  let rollout = null;

  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    if (arg === '--build' || arg === '-b') {
      build = true;
    } else if (arg === '--bump') {
      bump = true;
    } else if (arg === '--track') {
      track = argv[++i];
      if (!track) throw new Error(`--track requires a value (${TRACKS.join(' | ')})`);
    } else if (arg.startsWith('--track=')) {
      track = arg.slice('--track='.length);
    } else if (arg === '--rollout') {
      rollout = parseFloat(argv[++i]);
    } else if (arg.startsWith('--rollout=')) {
      rollout = parseFloat(arg.slice('--rollout='.length));
    } else if (arg === '-h' || arg === '--help') {
      console.log(`Voteaxis Google Play Upload Utility

Usage:
  node scripts/play-upload.js [--build] [--bump] [--track NAME] [--rollout 0.1-1.0] [path/to/app-release.aab]

Tracks (--track, or GOOGLE_PLAY_TRACK):
${TRACKS.map((t) => `  ${t.padEnd(12)} - ${TRACK_LABELS[t]}`).join('\n')}

Options:
  --build, -b       Build release App Bundle with 'flutter build appbundle --release'
  --bump            Bump versionCode in mobile/pubspec.yaml before building
  --track <name>    Google Play release track (default: internal)
  --rollout <frac>  Staged rollout fraction (e.g. 0.1 for 10% rollout)
`);
      process.exit(0);
    } else if (!arg.startsWith('-')) {
      aab = arg;
    }
  }

  return { build, bump, aab: aab || DEFAULT_AAB, track, rollout };
}

function buildAppBundle() {
  console.log('\n🔹 Building signed release Android App Bundle (AAB)...');

  const args = ['build', 'appbundle', '--release'];

  // Obfuscate the Dart AOT snapshot — R8 minification (isMinifyEnabled) only
  // touches the thin Kotlin/Java plugin glue, not the Dart snapshot, which is
  // the vast majority of this app's logic. Archive mobile/build/symbols/android
  // per release; it's required to symbolicate obfuscated crash stack traces.
  const symbolsDir = path.join(MOBILE, 'build/symbols/android');
  fs.mkdirSync(symbolsDir, { recursive: true });
  args.push('--obfuscate', `--split-debug-info=${symbolsDir}`);
  console.log(`   + obfuscation (symbols: ${symbolsDir} — archive this, needed to symbolicate crashes)`);

  const result = spawnSync('flutter', args, {
    cwd: MOBILE,
    stdio: 'inherit',
    env: process.env,
  });

  if (result.status !== 0) {
    console.error('❌ Flutter App Bundle build failed.');
    process.exit(result.status || 1);
  }
  console.log('✅ Flutter release AAB compiled successfully.\n');
}

async function main() {
  loadEnvFile();
  const { build, bump, aab, track: trackArg, rollout: rolloutArg } = parseArgs(process.argv.slice(2));

  const packageName = process.env.GOOGLE_PLAY_PACKAGE || 'com.greighstudios.voteaxis';
  const track = trackArg || process.env.GOOGLE_PLAY_TRACK || 'internal';

  if (!TRACKS.includes(track)) {
    console.error(`❌ Unknown track "${track}". Allowed: ${TRACKS.join(', ')}`);
    process.exit(1);
  }

  if (bump) {
    nativeVersions.bumpBuild();
  }

  if (build || !fs.existsSync(aab)) {
    buildAppBundle();
  }

  if (!fs.existsSync(aab)) {
    console.error(`❌ App Bundle not found at: ${aab}`);
    process.exit(1);
  }

  let serviceAccount;
  try {
    serviceAccount = resolveServiceAccount(process.env, ROOT);
  } catch (err) {
    console.error(`\n❌ ${err.message}`);
    process.exit(1);
  }

  if (!serviceAccount) {
    console.error(`\n⚠️  Google Play Service Account credential not found.`);
    console.error(`   Set GOOGLE_PLAY_SA_LOCAL to the JSON file's path, or`);
    console.error(`   GOOGLE_PLAY_SERVICE_ACCOUNT_JSON to the JSON itself (CI).`);
    console.error(`   AAB generated successfully at: ${aab}`);
    process.exit(1);
  }

  console.log(`🔹 Initializing Google Play Developer API...`);
  console.log(`   Package:  ${packageName}`);
  console.log(`   Track:    ${track} (${TRACK_LABELS[track]})`);
  console.log(`   Key from: ${serviceAccount.source}`);
  console.log(`   Bundle:   ${aab}`);

  try {
    const keyData = serviceAccount.credentials;
    const auth = new google.auth.JWT({
      email: keyData.client_email,
      key: keyData.private_key,
      scopes: ['https://www.googleapis.com/auth/androidpublisher'],
    });

    const publisher = google.androidpublisher({
      version: 'v3',
      auth,
    });

    console.log(`🔹 Creating new Google Play edit...`);
    const editRes = await publisher.edits.insert({
      packageName,
    });
    const editId = editRes.data.id;
    console.log(`   Edit ID: ${editId}`);

    console.log(`🔹 Uploading App Bundle (${(fs.statSync(aab).size / (1024 * 1024)).toFixed(1)} MB)...`);
    const bundleRes = await publisher.edits.bundles.upload({
      packageName,
      editId,
      media: {
        mimeType: 'application/octet-stream',
        body: fs.createReadStream(aab),
      },
    });

    const versionCode = bundleRes.data.versionCode;
    console.log(`✅ App Bundle uploaded successfully! Version Code: ${versionCode}`);

    // Upload ProGuard / R8 mapping file if present
    if (fs.existsSync(DEFAULT_MAPPING)) {
      console.log(`🔹 Uploading R8 deobfuscation mapping file...`);
      try {
        await publisher.edits.deobfuscationfiles.upload({
          packageName,
          editId,
          apkVersionCode: versionCode,
          deobfuscationFileType: 'proguard',
          media: {
            mimeType: 'application/octet-stream',
            body: fs.createReadStream(DEFAULT_MAPPING),
          },
        });
        console.log(`✅ Deobfuscation mapping uploaded.`);
      } catch (err) {
        console.warn(`⚠️  Mapping upload warning: ${err.message}`);
      }
    }

    // Release config
    const versionInfo = nativeVersions.readPubspec();
    const releaseName = `${versionInfo.versionName} (${versionCode})`;

    const releaseData = {
      name: releaseName,
      versionCodes: [versionCode.toString()],
      status: rolloutArg != null && rolloutArg < 1.0 ? 'inProgress' : 'completed',
    };

    // Load release notes from changelogs if present
    const changelogPath = path.join(ROOT, `docs/changelogs/android/${versionCode}.txt`);
    const defaultWhatsNewPath = path.join(ROOT, 'docs/changelogs/android/whatsnew-en-US.txt');
    let notesText = '';
    if (fs.existsSync(changelogPath)) {
      notesText = fs.readFileSync(changelogPath, 'utf8').trim();
    } else if (fs.existsSync(defaultWhatsNewPath)) {
      notesText = fs.readFileSync(defaultWhatsNewPath, 'utf8').trim();
    }

    if (notesText) {
      releaseData.releaseNotes = [
        {
          language: 'en-US',
          text: notesText.slice(0, 500),
        },
      ];
      console.log(`📝 Attached release notes from docs/changelogs/android (${notesText.length} chars).`);
    }

    if (rolloutArg != null && rolloutArg < 1.0) {
      releaseData.userFraction = rolloutArg;
    }

    console.log(`🔹 Assigning bundle to track: ${track}...`);
    await publisher.edits.tracks.update({
      packageName,
      editId,
      track,
      requestBody: {
        track,
        releases: [releaseData],
      },
    });

    console.log(`🔹 Committing edit to Google Play...`);
    await publisher.edits.commit({
      packageName,
      editId,
    });

    console.log(`\n🎉 SUCCESS: Voteaxis v${releaseName} published to Google Play (${TRACK_LABELS[track]})!`);
    console.log(`👉 View in Google Play Console: https://play.google.com/console/developers/app/${packageName}/tracks/${track}\n`);
    console.log(`👉 Tag the release: git tag v${versionInfo.versionName}+${versionCode} && git push --tags`);
  } catch (err) {
    console.error(`\n❌ Google Play upload failed:`, err.message || err);
    if (err.response?.data?.error) {
      console.error('Details:', JSON.stringify(err.response.data.error, null, 2));
    }
    process.exit(1);
  }
}

if (require.main === module) {
  main();
}
