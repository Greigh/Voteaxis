#!/usr/bin/env node
'use strict';

/**
 * Credential preflight for the store pipelines. Reports which release
 * credentials are usable and which are missing — naming the variable and the
 * fix, never the value (the values are private keys).
 *
 * Checks:
 *   Android signing   mobile/android/key.properties → keystore file + 4 props
 *   Google Play API   service-account JSON (inline or path) via
 *                     scripts/lib/service-account.js
 *   App Store Connect APP_STORE_CONNECT_API_KEY_ID / _ISSUER_ID and one of
 *                     APP_STORE_CONNECT_API_KEY (inline), _KEY_PATH (file), or
 *                     ~/.appstoreconnect/private_keys/AuthKey_<ID>.p8
 *
 * Exit 0 when everything needed for the requested stores resolves; exit 1 on
 * any hard failure. Sections are OK / WARN / FAIL — WARN means a store can be
 * skipped or falls back to interactive Xcode signing.
 *
 * Usage:
 *   node scripts/check-credentials.js            # report everything
 *   node scripts/check-credentials.js --play     # require Google Play auth
 *   node scripts/check-credentials.js --apple    # require App Store Connect auth
 */

const fs = require('fs');
const os = require('os');
const path = require('path');
const { resolveServiceAccount } = require('./lib/service-account');

const ROOT = path.join(__dirname, '..');
const MOBILE = path.join(ROOT, 'mobile');
const KEY_PROPERTIES = path.join(MOBILE, 'android/key.properties');

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

const rows = [];
const report = (status, area, detail) => rows.push({ status, area, detail });
const ok = (area, detail) => report('OK  ', area, detail);
const warn = (area, detail) => report('WARN', area, detail);
const fail = (area, detail) => report('FAIL', area, detail);

function checkAndroidSigning() {
  if (!fs.existsSync(KEY_PROPERTIES)) {
    fail('android-signing', 'mobile/android/key.properties missing — releases sign with the debug key (not distributable)');
    return;
  }
  const props = {};
  for (const line of fs.readFileSync(KEY_PROPERTIES, 'utf8').split('\n')) {
    const m = line.match(/^\s*([A-Za-z0-9_.]+)\s*=\s*(.*?)\s*$/);
    if (m) props[m[1]] = m[2];
  }
  const missing = ['storeFile', 'storePassword', 'keyAlias', 'keyPassword'].filter((k) => !props[k]);
  if (missing.length) {
    fail('android-signing', `key.properties missing: ${missing.join(', ')}`);
    return;
  }
  const storeFile = path.isAbsolute(props.storeFile)
    ? props.storeFile
    : path.join(MOBILE, 'android/app', props.storeFile);
  if (!fs.existsSync(storeFile)) {
    fail('android-signing', `storeFile not found: ${props.storeFile}`);
    return;
  }
  ok('android-signing', `key.properties → ${storeFile} (alias: ${props.keyAlias})`);
}

function checkPlayAuth() {
  try {
    const sa = resolveServiceAccount(process.env, ROOT);
    if (!sa) {
      warn('google-play', 'no service account — set GOOGLE_PLAY_SA_LOCAL (path) or GOOGLE_PLAY_SERVICE_ACCOUNT_JSON (inline) to upload');
      return;
    }
    ok('google-play', `service account resolves (${sa.source})`);
  } catch (err) {
    fail('google-play', err.message);
  }
}

function checkAppleAuth() {
  const keyId = process.env.APP_STORE_CONNECT_API_KEY_ID || '';
  const issuer = process.env.APP_STORE_CONNECT_API_ISSUER_ID || '';
  const inline = process.env.APP_STORE_CONNECT_API_KEY || '';
  let keyPath = process.env.APP_STORE_CONNECT_API_KEY_PATH || '';
  if (keyPath.startsWith('~')) keyPath = path.join(os.homedir(), keyPath.slice(1));

  const missing = [];
  if (!keyId) missing.push('APP_STORE_CONNECT_API_KEY_ID');
  if (!issuer) missing.push('APP_STORE_CONNECT_API_ISSUER_ID');

  let material = null;
  if (inline) {
    if (!inline.includes('-----BEGIN') || !inline.includes('-----END') || !inline.includes('PRIVATE KEY-----')) {
      fail('apple-asc', 'APP_STORE_CONNECT_API_KEY is not a complete PEM (needs BEGIN+END PRIVATE KEY markers; .env values need \\n escapes)');
      return;
    }
    material = 'inline key';
  } else if (keyPath) {
    if (fs.existsSync(keyPath)) {
      material = `key file ${keyPath}`;
    } else {
      missing.push(`readable file at APP_STORE_CONNECT_API_KEY_PATH=${keyPath}`);
    }
  } else if (keyId) {
    const conventional = path.join(os.homedir(), '.appstoreconnect/private_keys', `AuthKey_${keyId}.p8`);
    if (fs.existsSync(conventional)) {
      material = `~/.appstoreconnect/private_keys/AuthKey_${keyId}.p8`;
    } else {
      missing.push('APP_STORE_CONNECT_API_KEY (inline), APP_STORE_CONNECT_API_KEY_PATH, or ~/.appstoreconnect/private_keys/AuthKey_<ID>.p8');
    }
  } else {
    missing.push('APP_STORE_CONNECT_API_KEY_ID (+ issuer + key material)');
  }

  if (missing.length) {
    warn('apple-asc', `incomplete — ${missing.join('; ')} — uploads fall back to a signed-in Xcode account (local only)`);
    return;
  }
  ok('apple-asc', `API key resolves (key id ${keyId.slice(0, 4)}…, ${material})`);
}

function main() {
  loadEnvFile();
  const args = process.argv.slice(2);
  const wantPlay = args.includes('--play');
  const wantApple = args.includes('--apple');
  const scoped = wantPlay || wantApple;

  console.log('\n  Voteaxis release credentials\n  ─────────────────────────────\n');

  if (scoped) {
    if (wantPlay) {
      checkAndroidSigning();
      checkPlayAuth();
    }
    if (wantApple) {
      checkAppleAuth();
    }
  } else {
    checkAndroidSigning();
    checkPlayAuth();
    checkAppleAuth();
  }

  for (const r of rows) console.log(`  [${r.status}] ${r.area.padEnd(16)} ${r.detail}`);
  console.log('');

  const failed = rows.filter((r) => r.status === 'FAIL');
  const warned = rows.filter((r) => r.status === 'WARN');
  if (wantPlay && rows.some((r) => r.area === 'google-play' && r.status !== 'OK  ')) {
    console.log('  --play requested: Google Play auth must resolve. Exiting 1.\n');
    process.exit(1);
  }
  if (wantApple && rows.some((r) => r.area === 'apple-asc' && r.status !== 'OK  ')) {
    console.log('  --apple requested: App Store Connect auth must resolve. Exiting 1.\n');
    process.exit(1);
  }
  if (failed.length) {
    console.log(`  ${failed.length} check(s) failed — fix before releasing.\n`);
    process.exit(1);
  }
  if (warned.length) {
    console.log(`  ${warned.length} warning(s) — that store uploads need the missing credential or a signed-in Xcode account.\n`);
    process.exit(0);
  }
  console.log('  ✓ all release credentials resolve\n');
}

if (require.main === module) {
  main();
}
