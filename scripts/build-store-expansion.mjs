#!/usr/bin/env node
/** Extend the campaign with actual Duo captures and Apple creative placements. */
import fs from 'node:fs';
import path from 'node:path';
import {
  root, output, captures, fonts, temp, assets, run, scratch, png, sha256,
  identify, shape, label, rail, render, stories, layouts, previews,
} from './build-store-graphics.mjs';

const wideBackdrop = path.join(output, 'source/spectrum-background-wide.png');
const manifestPath = path.join(output, 'manifest.json');
const baseManifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
const baseFolders = layouts.map(layout => layout.folder);
assets.push(...baseManifest.assets.filter(asset => baseFolders.some(folder => asset.file.startsWith(`${folder}/`)) || asset.file === 'play-store/feature-graphic-1024x500.png'));
if (assets.length !== 19) throw new Error('Build the original 19 images before the expansion');

function phoneLayout(width, height, key) {
  const original = layouts.find(layout => layout.key === 'iphone');
  const scale = width / original.width;
  const result = { ...original, width, height, key, folder: `app-store/${key}` };
  for (const field of ['brandY', 'brandSize', 'brandTracking', 'titleSize', 'bodySize', 'railY', 'railWidth', 'screenY', 'screenWidth', 'screenRadius', 'border']) result[field] = Math.round(original[field] * scale);
  result.titleY = original.titleY.map(value => Math.round(value * scale));
  result.bodyY = original.bodyY.map(value => Math.round(value * scale));
  return result;
}

const addedLayouts = [
  phoneLayout(1179, 2556, 'iphone-6.1'),
  phoneLayout(1206, 2622, 'iphone-6.3'),
  { key: 'duo-outer-portrait', folder: 'app-store/duo-outer-portrait', device: 'iPhone Duo outer display, portrait', capturePrefix: 'duo-outer-portrait', nativeSize: [1398, 2034], width: 1398, height: 2034, brandY: 74, brandSize: 35, brandTracking: 9, titleY: [172, 296], titleSize: 108, bodyY: [453, 507], bodySize: 40, railY: 602, railWidth: 320, screenY: 680, screenWidth: 840, screenRadius: 38, border: 11, platform: 'App Store', crop: [1398, 2034, 0, 0] },
  { key: 'duo-inner-portrait', folder: 'app-store/duo-inner-portrait', device: 'iPhone Duo inner display, portrait', capturePrefix: 'duo-inner-portrait', nativeSize: [2007, 2853], width: 2007, height: 2853, brandY: 80, brandSize: 44, brandTracking: 12, titleY: [182, 355], titleSize: 145, bodyY: [548, 620], bodySize: 53, railY: 730, railWidth: 430, screenY: 806, screenWidth: 1340, screenRadius: 43, border: 14, platform: 'App Store', crop: [2007, 2853, 0, 0] },
  { key: 'duo-outer-landscape', folder: 'app-store/duo-outer-landscape', device: 'iPhone Duo outer display, landscape', capturePrefix: 'duo-outer-landscape', nativeSize: [2034, 1398], width: 2034, height: 1398, brandY: 160, brandSize: 31, brandTracking: 8, titleY: [310, 425], titleSize: 101, bodyY: [613, 670], bodySize: 37, railY: 813, railWidth: 315, copyX: 98, copyWidth: 610, screenX: 790, screenY: 287, screenWidth: 1130, screenRadius: 36, border: 12, platform: 'App Store', crop: [2034, 1398, 0, 0], backdrop: wideBackdrop },
  { key: 'duo-inner-landscape', folder: 'app-store/duo-inner-landscape', device: 'iPhone Duo inner display, landscape', capturePrefix: 'duo-inner-landscape', nativeSize: [2853, 2007], width: 2853, height: 2007, brandY: 233, brandSize: 42, brandTracking: 11, titleY: [442, 600], titleSize: 141, bodyY: [856, 932], bodySize: 49, railY: 1135, railWidth: 430, copyX: 128, copyWidth: 820, screenX: 1080, screenY: 396, screenWidth: 1650, screenRadius: 44, border: 16, platform: 'App Store', crop: [2853, 2007, 0, 0], backdrop: wideBackdrop },
];

const duoStories = [
  { key: 'home', title: ['Your views.', 'Room to explore.'], body: ['Your quiz, spectrum, and matches.', 'Ready on either Duo display.'] },
  { key: 'quiz', title: ['Make every', 'answer count.'], body: ['Explore the issues in a layout', 'that adapts as you unfold.'] },
  { key: 'results', title: ['Your spectrum.', 'Your way.'], body: ['Take the quiz or set your level.', 'See where your views land.'] },
  { key: 'matches', title: ['Find who', 'stands closest.'], body: ['Compare political figures', 'by how their views overlap.'] },
];

function imagePanel(composition, source, crop, geometry, canvas, records) {
  const { x, y, width, radius = 30, border = 7 } = geometry;
  const resized = scratch('creative-ui.png');
  run([source, '-crop', `${crop.width}x${crop.height}+${crop.x}+${crop.y}`, '+repage', '-resize', `${width}x`, resized]);
  const size = identify(resized);
  const mask = shape(size.width, size.height, `<rect width="${size.width}" height="${size.height}" rx="${radius}" fill="white"/>`);
  const clipped = scratch('creative-ui-clipped.png');
  run([resized, mask, '-alpha', 'off', '-compose', 'CopyOpacity', '-composite', clipped]);
  const frame = shape(canvas.width, canvas.height, `<defs><linearGradient id="f"><stop stop-color="#A5B6D7"/><stop offset="1" stop-color="#5B577A"/></linearGradient></defs><rect x="${x-border}" y="${y-border}" width="${width+border*2}" height="${size.height+border*2}" rx="${radius+border}" fill="#0F1A2F" stroke="url(#f)" stroke-width="3"/>`);
  composition.push(frame, '-geometry', '+0+0', '-compose', 'over', '-composite', clipped, '-geometry', `+${x}+${y}`, '-compose', 'over', '-composite');
  records.push({ source: path.relative(root, source), source_sha256: sha256(source), crop, panel: { x, y, width, height: size.height, radius } });
}

function creative(kind, width, height, baseWidth, baseHeight, filename) {
  const scale = width / baseWidth;
  const number = value => Math.round(value * scale);
  const target = path.join(output, 'app-store', kind, filename);
  fs.mkdirSync(path.dirname(target), { recursive: true });
  const composition = [wideBackdrop, '-resize', `${width}x${height}!`];
  const ui = [];
  const text = (value, x, y, size, weight = 'ExtraBold', color = '#F4F7FC', tracking = 0, maxWidth = 900) => composition.push(label(value, number(size), weight, color, tracking * scale, number(maxWidth)), '-geometry', `+${number(x)}+${number(y)}`, '-compose', 'over', '-composite');
  const results = path.join(captures, 'iphone-6.9-04-results.png');
  const matches = path.join(captures, 'iphone-6.9-05-matches.png');
  const crop = { x: 0, y: 190, width: 1320, height: 2678 };

  if (kind === 'header') {
    const wide = baseHeight < 900;
    const m = wide ? { brandY: 65, titleY: [174, 303], titleSize: 108, bodyY: [472, 520], railY: 638, front: { x: 1095, y: 88, width: 390 }, back: { x: 1450, y: 177, width: 330 } } : { brandY: 100, titleY: [230, 373], titleSize: 119, bodyY: [574, 630], railY: 768, front: { x: 1110, y: 155, width: 480 }, back: { x: 1515, y: 280, width: 335 } };
    text('VOTEAXIS', 120, m.brandY, 29, 'Bold', '#B5CCF0', 7, 800);
    text('Where do', 114, m.titleY[0], m.titleSize, 'ExtraBold', '#F4F7FC', -2, 900);
    text('you land?', 114, m.titleY[1], m.titleSize, 'ExtraBold', '#F4F7FC', -2, 900);
    text('A political spectrum built', 120, m.bodyY[0], 31, 'Medium', '#C0CEE5', 0, 850);
    text('around your views.', 120, m.bodyY[1], 31, 'Medium', '#C0CEE5', 0, 850);
    composition.push(rail(width, height, number(120), number(m.railY), number(460), number(6)), '-geometry', '+0+0', '-compose', 'over', '-composite');
    for (const [source, panel] of [[matches, m.back], [results, m.front]]) imagePanel(composition, source, crop, { x: number(panel.x), y: number(panel.y), width: number(panel.width), radius: number(27), border: number(7) }, { width, height }, ui);
  } else {
    text('VOTEAXIS', 110, 89, 27, 'Bold', '#B5CCF0', 7, 650);
    ['Find your', 'political', 'spectrum.'].forEach((line, index) => text(line, 105, 210 + index * 131, 105, 'ExtraBold', '#F4F7FC', -2, 680));
    text('Take the quiz. See where you stand.', 110, 663, 30, 'Medium', '#C0CEE5', 0, 665);
    text('Explore who shares your views.', 110, 715, 30, 'Medium', '#C0CEE5', 0, 665);
    composition.push(rail(width, height, number(110), number(835), number(495), number(6)), '-geometry', '+0+0', '-compose', 'over', '-composite');
    imagePanel(composition, results, crop, { x: number(886), y: number(125), width: number(490), radius: number(30), border: number(8) }, { width, height }, ui);
  }
  png(composition, target);
  assets.push({ file: path.relative(output, target), width, height, platform: 'App Store', placement: kind === 'header' ? 'Product page Header' : 'Search Results', headline: kind === 'header' ? 'Where do you land?' : 'Find your political spectrum.', source_panels: ui, sha256: sha256(target), bytes: fs.statSync(target).size });
  console.log(`${path.relative(output, target)} (${width}×${height})`);
  return target;
}

function copyUniversal(source) {
  const file = 'app-store/search-results/search-results-5244x2950.png';
  const target = path.join(output, file);
  fs.mkdirSync(path.dirname(target), { recursive: true });
  fs.copyFileSync(source, target);
  const original = assets.find(asset => path.join(output, asset.file) === source);
  assets.push({ ...original, file, placement: 'Search Results', shared_with: original.file });
  console.log(`${file} (5244×2950, universal artwork)`);
}

function expansionPreviews() {
  previews(addedLayouts);
  const dir = path.join(output, 'previews');
  const a = scratch('duo-wide-preview.jpg'), b = scratch('duo-portrait-preview.jpg');
  run([path.join(dir, 'duo-inner-landscape.jpg'), '-resize', '1600x', a]);
  run([path.join(dir, 'duo-outer-portrait.jpg'), '-resize', '1600x', b]);
  run([a, b, '-background', '#DDE4F0', '-gravity', 'center', '-append', '-quality', '92', path.join(dir, 'duo-overview.jpg')]);
  const creatives = assets.filter(asset => asset.placement && !asset.shared_with).map(asset => path.join(output, asset.file));
  run(['montage', ...creatives, '-font', path.join(fonts, 'Manrope-Medium.ttf'), '-pointsize', '18', '-set', 'label', '%f', '-thumbnail', '720x480', '-tile', '2x2', '-geometry', '+15+25', '-background', '#DDE4F0', '-fill', '#17243B', '-quality', '92', path.join(dir, 'header-and-search.jpg')]);
}

try {
  for (const layout of addedLayouts) {
    const selected = layout.capturePrefix ? duoStories : stories;
    selected.forEach((story, index) => render(story, layout, index));
  }
  const universal = creative('header', 5244, 2950, 1920, 1080, 'header-5244x2950.png');
  creative('header', 3840, 1646, 1920, 823, 'header-3840x1646.png');
  creative('search-results', 3840, 2560, 1500, 1000, 'search-results-3840x2560.png');
  creative('search-results', 1920, 1280, 1500, 1000, 'search-results-1920x1280.png');
  copyUniversal(universal);
  expansionPreviews();
  if (assets.length !== 50) throw new Error(`Expected 50 final assets; got ${assets.length}`);
  const manifest = { ...baseManifest, asset_count: assets.length, source_platform: 'iOS, including 16 native iPhone Duo Simulator captures', note: 'All app panels use real captures. Duo variants use native outer and inner display captures in both orientations, not resized iPhone or iPad layouts. Duo spectrum and matches show a completed 25-question sample quiz with Neutral responses, standard importance, and no dealbreakers; these are demonstration values, not the owner\'s political preferences. Header and Search Results artwork uses real iPhone captures. Google Play variants adapt the original iOS captures with system bars removed. App UI is not regenerated. All screenshot panels are uniformly resized. The 5244×2950 creative is deliberately shared between Header and Search Results, as supported by Apple.', creative_specifications: 'https://developer.apple.com/help/app-store-connect/reference/app-information/creative-assets-specifications/', assets };
  fs.writeFileSync(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`);
  console.log('Rendered 31 additions; the complete set contains 50 upload images.');
} finally {
  fs.rmSync(temp, { recursive: true, force: true });
}
