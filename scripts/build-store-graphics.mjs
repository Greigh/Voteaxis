#!/usr/bin/env node
/** Render store artwork from the committed captures without redrawing the UI. */
import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const output = path.join(root, 'store/graphics');
const captures = path.join(root, 'docs/store-screenshots/ios');
const fonts = path.join(root, 'mobile/assets/fonts');
const backdrop = path.join(output, 'source/spectrum-background.png');
const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'voteaxis-graphics-'));
const assets = [];
let serial = 0;

const run = (args) => execFileSync('magick', args, { maxBuffer: 8 * 1024 * 1024 });
const scratch = (name) => path.join(temp, `${serial++}-${name}`);
const png = (args, destination) => run([...args, '-colorspace', 'sRGB', '-depth', '8', '-alpha', 'off', '-strip', `PNG24:${destination}`]);
const sha256 = (file) => createHash('sha256').update(fs.readFileSync(file)).digest('hex');
const identify = (file) => {
  const [width, height] = run(['identify', '-format', '%w %h', file]).toString().split(' ').map(Number);
  return { width, height };
};

function shape(width, height, contents) {
  const svg = scratch('shape.svg');
  const image = scratch('shape.png');
  fs.writeFileSync(svg, `<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${height}" viewBox="0 0 ${width} ${height}">${contents}</svg>`);
  execFileSync('rsvg-convert', ['-o', image, svg]);
  return image;
}

function label(text, size, weight = 'ExtraBold', color = '#F4F7FC', kerning = 0, maxWidth = Infinity) {
  const destination = scratch('label.png');
  run(['-background', 'none', '-fill', color, '-font', path.join(fonts, `Manrope-${weight}.ttf`), '-pointsize', String(size), '-kerning', String(kerning), `label:${text}`, destination]);
  const dimensions = identify(destination);
  if (dimensions.width > maxWidth) {
    run([destination, '-resize', `${maxWidth}x`, destination]);
  }
  return destination;
}

function placeText(composition, canvasWidth, text, y, size, weight, color, kerning = 0, maxWidth = canvasWidth * 0.88) {
  const image = label(text, size, weight, color, kerning, maxWidth);
  const { width } = identify(image);
  composition.push(image, '-geometry', `+${Math.round((canvasWidth - width) / 2)}+${y}`, '-compose', 'over', '-composite');
}

function rail(width, height, x, y, length, stroke = 5) {
  return shape(width, height, `<defs><linearGradient id="s"><stop stop-color="#2668FF"/><stop offset=".48" stop-color="#BDCBE5"/><stop offset=".52" stop-color="#D9C7CF"/><stop offset="1" stop-color="#EF4249"/></linearGradient></defs><rect x="${x}" y="${y}" width="${length}" height="${stroke}" rx="${stroke / 2}" fill="url(#s)"/><circle cx="${x + length / 2}" cy="${y + stroke / 2}" r="${stroke * 1.55}" fill="#F4F7FC"/><circle cx="${x + length / 2}" cy="${y + stroke / 2}" r="${stroke * 0.65}" fill="#14213A"/>`);
}

const stories = [
  { key: 'onboarding', title: ['Where do', 'you land?'], body: ['Your views. Your spectrum.', 'Start with the issues that matter.'] },
  { key: 'home', title: ['Your views.', 'Your starting point.'], body: ['Take a short quiz, explore the roster,', 'or set your place on the axis.'] },
  { key: 'quiz', title: ['Make every', 'answer count.'], body: ['Answer real questions. Give more weight', 'to the issues that matter to you.'] },
  { key: 'results', title: ['See your', 'political spectrum.'], body: ['One clear placement, with a breakdown', 'across five pillars.'] },
  { key: 'matches', title: ['Find who', 'stands closest.'], body: ['Explore politicians ranked by how', 'closely their positions match yours.'] },
];

const layouts = [
  { key: 'iphone', folder: 'app-store/iphone-6.9', width: 1320, height: 2868, brandY: 105, brandSize: 36, brandTracking: 10, titleY: [210, 345], titleSize: 112, bodyY: [525, 583], bodySize: 42, railY: 674, railWidth: 318, screenY: 736, screenWidth: 1040, screenRadius: 48, border: 10, tablet: false, platform: 'App Store', crop: [1320, 2678, 0, 190] },
  { key: 'ipad', folder: 'app-store/ipad-13', width: 2064, height: 2752, brandY: 87, brandSize: 48, brandTracking: 14, titleY: [185, 365], titleSize: 148, bodyY: [564, 636], bodySize: 54, railY: 746, railWidth: 440, screenY: 824, screenWidth: 1420, screenRadius: 42, border: 14, tablet: true, platform: 'App Store', crop: [2064, 2688, 0, 64] },
  { key: 'play-phone', folder: 'play-store/phone', width: 1080, height: 1920, brandY: 67, brandSize: 28, brandTracking: 8, titleY: [145, 251], titleSize: 88, bodyY: [384, 430], bodySize: 32, railY: 507, railWidth: 260, screenY: 568, screenWidth: 916, screenRadius: 38, border: 9, tablet: false, platform: 'Google Play', crop: [1320, 2678, 0, 190] },
  { key: 'play-tablet', folder: 'play-store/tablet', width: 1440, height: 2560, brandY: 90, brandSize: 38, brandTracking: 10, titleY: [202, 337], titleSize: 112, bodyY: [515, 573], bodySize: 42, railY: 678, railWidth: 330, screenY: 768, screenWidth: 1260, screenRadius: 38, border: 12, tablet: true, platform: 'Google Play', crop: [2064, 2688, 0, 64] },
];

function render(story, layout, index) {
  const { width: w, height: h } = layout;
  const sourceName = layout.capturePrefix
    ? `${layout.capturePrefix}-${String(index + 1).padStart(2, '0')}-${story.key}.png`
    : layout.tablet
    ? `ipad-13-${String(index + 1).padStart(2, '0')}-${story.key}.png`
    : `iphone-6.9-${String(index + 1).padStart(2, '0')}-${story.key}.png`;
  const source = path.join(captures, sourceName);
  const target = path.join(output, layout.folder, `${String(index + 1).padStart(2, '0')}-${story.key}.png`);
  fs.mkdirSync(path.dirname(target), { recursive: true });
  const expected = layout.nativeSize ?? (layout.tablet ? [2064, 2752] : [1320, 2868]);
  const sourceSize = identify(source);
  if (sourceSize.width !== expected[0] || sourceSize.height !== expected[1]) throw new Error(`Unexpected capture size: ${sourceName}`);

  const screen = scratch('screen.png');
  const [cw, ch, cx, cy] = layout.crop;
  run([source, '-crop', `${cw}x${ch}+${cx}+${cy}`, '+repage', '-resize', `${layout.screenWidth}x`, screen]);
  const size = identify(screen);
  const mask = shape(size.width, size.height, `<rect width="${size.width}" height="${size.height}" rx="${layout.screenRadius}" fill="white"/>`);
  const clipped = scratch('clipped.png');
  run([screen, mask, '-alpha', 'off', '-compose', 'CopyOpacity', '-composite', clipped]);

  const sx = layout.screenX ?? Math.round((w - size.width) / 2);
  const sy = layout.screenY;
  const b = layout.border;
  const frame = shape(w, h, `<defs><filter id="shadow" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="26"/></filter><linearGradient id="edge" x2="1" y2="1"><stop stop-color="#9BABCA"/><stop offset=".5" stop-color="#384A69"/><stop offset="1" stop-color="#8E6780"/></linearGradient></defs><rect x="${sx - 6}" y="${sy + 24}" width="${size.width + 12}" height="${size.height + 12}" rx="${layout.screenRadius + b}" fill="#000918" opacity=".8" filter="url(#shadow)"/><rect x="${sx - b}" y="${sy - b}" width="${size.width + b * 2}" height="${size.height + b * 2}" rx="${layout.screenRadius + b}" fill="#111B2C" stroke="url(#edge)" stroke-width="2.5"/>`);
  const composition = [layout.backdrop ?? backdrop, '-resize', `${w}x${h}!`, frame, '-compose', 'over', '-composite'];
  composition.push(clipped, '-geometry', `+${sx}+${sy}`, '-compose', 'over', '-composite');
  const text = (value, y, pointSize, weight, color, tracking = 0) => {
    if (layout.copyX == null) return placeText(composition, w, value, y, pointSize, weight, color, tracking);
    const image = label(value, pointSize, weight, color, tracking, layout.copyWidth);
    composition.push(image, '-geometry', `+${layout.copyX}+${y}`, '-compose', 'over', '-composite');
  };
  text('VOTEAXIS', layout.brandY, layout.brandSize, 'Bold', '#AFC6EF', layout.brandTracking);
  story.title.forEach((value, i) => text(value, layout.titleY[i], layout.titleSize, 'ExtraBold', '#F4F7FC', -2));
  story.body.forEach((value, i) => text(value, layout.bodyY[i], layout.bodySize, 'Medium', '#AFBDD2'));
  const accent = rail(w, h, layout.copyX ?? (w - layout.railWidth) / 2, layout.railY, layout.railWidth, layout.tablet ? 7 : 5);
  composition.push(accent, '-geometry', '+0+0', '-compose', 'over', '-composite');
  png(composition, target);
  assets.push({ file: path.relative(output, target), width: w, height: h, platform: layout.platform, capture_device: layout.device ?? (layout.tablet ? 'iPad 13-inch' : 'iPhone 6.9-inch'), source: path.relative(root, source), source_sha256: sha256(source), source_dimensions: { width: expected[0], height: expected[1] }, crop: { x: cx, y: cy, width: cw, height: ch }, panel: { x: sx, y: sy, width: size.width, height: size.height, radius: layout.screenRadius }, headline: story.title.join(' '), caption: story.body.join(' '), alt_text: `${story.title.join(' ')} Voteaxis ${story.key} screen.`, sha256: sha256(target), bytes: fs.statSync(target).size });
  console.log(`${layout.folder}/${path.basename(target)} (${w}×${h})`);
}

function featureGraphic() {
  const w = 1024, h = 500;
  const target = path.join(output, 'play-store/feature-graphic-1024x500.png');
  const composition = [backdrop, '-resize', `${w}x${h}!`];
  const write = (text, x, y, size, weight, color, kerning = 0) => composition.push(label(text, size, weight, color, kerning), '-geometry', `+${x}+${y}`, '-compose', 'over', '-composite');
  write('VOTEAXIS', 80, 60, 23, 'Bold', '#B5CEF5', 7);
  write('Where do', 76, 132, 60, 'ExtraBold', '#F4F7FC', -1.5);
  write('you land?', 76, 207, 60, 'ExtraBold', '#F4F7FC', -1.5);
  write('A short quiz. A clearer picture.', 80, 322, 23, 'Medium', '#C2CDE0');
  const spectrum = shape(w, h, `<defs><linearGradient id="s"><stop stop-color="#2470FF"/><stop offset=".5" stop-color="#CFD7EB"/><stop offset="1" stop-color="#ED3F49"/></linearGradient><filter id="glow" x="-100%" y="-100%" width="300%" height="300%"><feGaussianBlur stdDeviation="18"/></filter></defs><path d="M594 284 A174 174 0 0 1 942 284" fill="none" stroke="#3066C8" stroke-width="20" opacity=".28" filter="url(#glow)"/><path d="M594 284 A174 174 0 0 1 942 284" fill="none" stroke="#61779C" stroke-width="2" opacity=".75"/><rect x="582" y="276" width="372" height="14" rx="7" fill="url(#s)"/><path d="M768 235 L759 252 L777 252 Z" fill="#F5F7FC"/><circle cx="768" cy="283" r="18" fill="#0D192F" stroke="#F4F7FC" stroke-width="5"/><circle cx="768" cy="283" r="6" fill="#F4F7FC"/>`);
  composition.push(spectrum, '-geometry', '+0+0', '-compose', 'over', '-composite');
  write('YOUR SPECTRUM', 654, 197, 17, 'Bold', '#C1D0EA', 2);
  write('Liberal', 582, 316, 19, 'Medium', '#9DBBFF');
  write('Conservative', 837, 316, 17, 'Medium', '#F4B0B8');
  png(composition, target);
  assets.push({ file: path.relative(output, target), width: w, height: h, platform: 'Google Play', alt_text: 'Voteaxis: Where do you land? A blue-to-red political spectrum with a center marker on a navy background.', sha256: sha256(target), bytes: fs.statSync(target).size });
  console.log('play-store/feature-graphic-1024x500.png (1024×500)');
}

function previews(layoutList = layouts) {
  const directory = path.join(output, 'previews');
  fs.mkdirSync(directory, { recursive: true });
  for (const layout of layoutList) {
    const files = assets.filter((asset) => asset.file.startsWith(`${layout.folder}/`)).map((asset) => path.join(output, asset.file));
    run(['montage', ...files, '-thumbnail', layout.width > layout.height ? '480x340' : layout.tablet ? '330x550' : '290x630', '-tile', `${files.length}x1`, '-geometry', '+10+10', '-background', '#DDE4F0', '-quality', '91', path.join(directory, `${layout.key}.jpg`)]);
  }
  const phone = path.join(directory, 'iphone.jpg');
  const pad = path.join(directory, 'ipad.jpg');
  const p = scratch('phone-preview.jpg');
  const t = scratch('tablet-preview.jpg');
  run([phone, '-resize', '1600x', p]);
  run([pad, '-resize', '1600x', t]);
  run([p, t, '-background', '#DDE4F0', '-gravity', 'center', '-append', '-quality', '92', path.join(directory, 'app-store-overview.jpg')]);
}

function buildBase() {
try {
  for (const layout of layouts) {
    const selected = layout.tablet ? stories.slice(1) : stories;
    selected.forEach((story, index) => render(story, layout, index));
  }
  featureGraphic();
  previews();
  const manifest = { product: 'Voteaxis', design_reference: 'Sensecast Google Play screenshot campaign', design_reference_url: 'https://play.google.com/store/apps/details?id=com.greighstudios.sensecast', source_platform: 'iOS', note: 'All app panels use actual committed iPhone/iPad captures. Only system-bar margins are cropped. Google Play variants use neutral panels and are adaptations of the supplied iOS captures, not new Android runtime captures. The Play phone panels intentionally continue beyond the lower canvas edge, matching the reference campaign. The app UI, text, scores, and candidates are not regenerated.', format: '24-bit opaque sRGB PNG', asset_count: assets.length, assets };
  fs.writeFileSync(path.join(output, 'manifest.json'), `${JSON.stringify(manifest, null, 2)}\n`);
  if (assets.length !== 19) throw new Error(`Expected 19 assets; got ${assets.length}`);
  console.log('Rendered 19 store images and five preview sheets.');
} finally {
  fs.rmSync(temp, { recursive: true, force: true });
}
}

export { root, output, captures, fonts, backdrop, temp, assets, run, scratch, png, sha256, identify, shape, label, rail, render, stories, layouts, previews };

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) buildBase();
