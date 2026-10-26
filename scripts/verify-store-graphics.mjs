#!/usr/bin/env node
/** Verify exported artwork, source preservation, and actual composited UI pixels. */
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const directory = path.join(root, 'store/graphics');
const manifest = JSON.parse(fs.readFileSync(path.join(directory, 'manifest.json')));
const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'voteaxis-verify-'));
const sha = data => createHash('sha256').update(data).digest('hex');
const run = args => execFileSync('magick', args, { maxBuffer: 8 * 1024 * 1024 });
const expectedGroups = {
  'app-store/iphone-6.9': [5, 1320, 2868],
  'app-store/ipad-13': [4, 2064, 2752],
  'app-store/iphone-6.1': [5, 1179, 2556],
  'app-store/iphone-6.3': [5, 1206, 2622],
  'app-store/duo-outer-portrait': [4, 1398, 2034],
  'app-store/duo-outer-landscape': [4, 2034, 1398],
  'app-store/duo-inner-portrait': [4, 2007, 2853],
  'app-store/duo-inner-landscape': [4, 2853, 2007],
  'play-store/phone': [5, 1080, 1920],
  'play-store/tablet': [4, 1440, 2560],
  'play-store': [1, 1024, 500],
};
const groups = {};
const sources = new Map();
let exactPanels = 0;

function checkPanel(asset, record, index, laterPanels) {
  const source = path.join(root, record.source);
  const bytes = fs.readFileSync(source);
  if (sha(bytes) !== record.source_sha256) throw new Error(`Source changed: ${record.source}`);
  sources.set(record.source, record.source_sha256);
  const panel = record.panel, crop = record.crop;
  const inset = panel.radius + 8;
  const width = panel.width - inset * 2;
  const height = Math.min(panel.height - inset * 2, asset.height - panel.y - inset);
  if (width <= 0 || height <= 0) throw new Error(`No visible panel interior: ${asset.file}`);
  const expected = path.join(temp, `${index}-expected.png`);
  const actual = path.join(temp, `${index}-actual.png`);
  run([source, '-crop', `${crop.width}x${crop.height}+${crop.x}+${crop.y}`, '+repage', '-resize', `${panel.width}x`, '-crop', `${width}x${height}+${inset}+${inset}`, '+repage', '-colorspace', 'sRGB', '-alpha', 'off', '-depth', '8', `PNG24:${expected}`]);
  run([path.join(directory, asset.file), '-crop', `${width}x${height}+${panel.x + inset}+${panel.y + inset}`, '+repage', actual]);
  // The rear phone in Header artwork is partly covered by the front phone.
  // Exclude those deliberately occluded rectangles from both comparisons.
  const rectangles = laterPanels.map(({ panel: next }) => {
    const padding = Math.max(24, next.radius / 2);
    const x1 = Math.max(0, Math.floor(next.x - padding - panel.x - inset));
    const y1 = Math.max(0, Math.floor(next.y - padding - panel.y - inset));
    const x2 = Math.min(width - 1, Math.ceil(next.x + next.width + padding - panel.x - inset));
    const y2 = Math.min(height - 1, Math.ceil(next.y + next.height + padding - panel.y - inset));
    return x2 >= x1 && y2 >= y1 ? `rectangle ${x1},${y1} ${x2},${y2}` : null;
  }).filter(Boolean);
  if (rectangles.length) for (const file of [expected, actual]) run([file, '-fill', 'black', '-draw', rectangles.join(' '), file]);
  try {
    execFileSync('magick', ['compare', '-metric', 'AE', expected, actual, 'null:'], { stdio: ['ignore', 'pipe', 'pipe'] });
  } catch (error) {
    throw new Error(`App pixels differ in ${asset.file}: ${error.stderr?.toString().trim()}`, { cause: error });
  }
  exactPanels++;
}

try {
  if (manifest.asset_count !== 50 || manifest.assets.length !== 50) throw new Error('Expected 50 upload images');
  for (const [index, asset] of manifest.assets.entries()) {
    const data = fs.readFileSync(path.join(directory, asset.file));
    if (data.subarray(0, 8).toString('hex') !== '89504e470d0a1a0a') throw new Error(`Not a PNG: ${asset.file}`);
    if (data[24] !== 8 || data[25] !== 2) throw new Error(`Not 8-bit RGB/no-alpha: ${asset.file}`);
    if (data.readUInt32BE(16) !== asset.width || data.readUInt32BE(20) !== asset.height) throw new Error(`Wrong dimensions: ${asset.file}`);
    if (sha(data) !== asset.sha256) throw new Error(`Output changed: ${asset.file}`);
    const group = asset.file.split('/').slice(0, -1).join('/');
    groups[group] = (groups[group] ?? 0) + 1;
    const expected = expectedGroups[group];
    if (expected && (asset.width !== expected[1] || asset.height !== expected[2])) throw new Error(`Wrong placement size: ${asset.file}`);
    if (asset.placement === 'Product page Header' && !['5244x2950', '3840x1646'].includes(`${asset.width}x${asset.height}`)) throw new Error('Wrong Header size');
    if (asset.placement === 'Search Results' && !['5244x2950', '3840x2560', '1920x1280'].includes(`${asset.width}x${asset.height}`)) throw new Error('Wrong Search Results size');
    const records = asset.source_panels ?? (asset.source ? [asset] : []);
    for (const [layer, record] of records.entries()) checkPanel(asset, record, `${index}-${layer}`, records.slice(layer + 1));
    if ((index + 1) % 10 === 0) console.log(`Verified ${index + 1}/50 images`);
  }
  for (const [group, expected] of Object.entries(expectedGroups)) if (groups[group] !== expected[0]) throw new Error(`Wrong count for ${group}`);
  if (groups['app-store/header'] !== 2 || groups['app-store/search-results'] !== 3) throw new Error('Missing creative placements');
  let originals = 0, nativeDuo = 0;
  for (const [source, hash] of sources) {
    if (path.basename(source).startsWith('duo-')) {
      const fraction = Number(run([path.join(root, source), '-alpha', 'off', '-gravity', 'south', '-crop', '100%x120+0+0', '+repage', '-fx', '(r>0.7 && g>0.7 && b<0.15)?1:0', '-format', '%[fx:mean]', 'info:']).toString());
      if (fraction > 0.005) throw new Error(`Possible debug overflow stripe: ${source}`);
      nativeDuo++;
    } else {
      const committed = execFileSync('git', ['show', `HEAD:${source}`], { cwd: root, maxBuffer: 16 * 1024 * 1024 });
      if (sha(committed) !== hash) throw new Error(`Original capture differs from its committed version: ${source}`);
      originals++;
    }
  }
  if (originals !== 9 || nativeDuo !== 16) throw new Error(`Wrong source counts: ${originals} originals, ${nativeDuo} Duo captures`);
  const report = { asset_count: manifest.assets.length, groups, format: 'All 50 upload PNGs are 8-bit RGB with no alpha', dimensions: 'All exact dimensions and output SHA-256 values match the manifest', source_integrity: 'All nine provided captures match their committed SHA-256 values; all 16 native Duo captures match their recorded source hashes', screenshot_integrity: `All ${exactPanels} visible app panel interiors match the cropped and uniformly resized real captures exactly; rounded corners and deliberate front-panel overlaps are excluded`, native_duo: '16 native captures, all four display/orientation combinations; no yellow Flutter overflow stripes in the final captures', demo_profile: 'Completed 25-question sample quiz: Neutral responses, standard importance, no dealbreakers', manual_profile_issue: 'Separate manual-placement outer-landscape Matches overflow recorded in capture-notes.md; app code not modified' };
  fs.writeFileSync(path.join(directory, 'validation.json'), JSON.stringify(report, null, 2) + '\n');
  console.log(JSON.stringify(report, null, 2));
} finally {
  fs.rmSync(temp, { recursive: true, force: true });
}
