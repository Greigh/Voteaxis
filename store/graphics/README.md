# Voteaxis store graphics

Store artwork in the style of the Sensecast campaign: a dark glowing backdrop,
centered feature headlines, a small spectrum accent, and framed app screenshots.
Voteaxis uses its own navy, blue, red, and slate palette and bundled Manrope type.

## Exported images

| Folder or file | Count | Dimensions |
| --- | ---: | --- |
| `app-store/iphone-6.9/` | 5 | 1320 × 2868 |
| `app-store/ipad-13/` | 4 | 2064 × 2752 |
| `app-store/iphone-6.1/` | 5 | 1179 × 2556 |
| `app-store/iphone-6.3/` | 5 | 1206 × 2622 |
| `app-store/duo-outer-portrait/` | 4 | 1398 × 2034 |
| `app-store/duo-outer-landscape/` | 4 | 2034 × 1398 |
| `app-store/duo-inner-portrait/` | 4 | 2007 × 2853 |
| `app-store/duo-inner-landscape/` | 4 | 2853 × 2007 |
| `app-store/header/` | 2 | 5244 × 2950; 3840 × 1646 |
| `app-store/search-results/` | 3 | 5244 × 2950; 3840 × 2560; 1920 × 1280 |
| `play-store/phone/` | 5 | 1080 × 1920 |
| `play-store/tablet/` | 4 | 1440 × 2560 |
| `play-store/feature-graphic-1024x500.png` | 1 | 1024 × 500 |

Every store image is an opaque, 24-bit sRGB PNG. `previews/` contains contact
sheets for review; upload the individual PNGs to the stores.

The complete pack contains **50 upload images**, including the original 19.
Header and Search Results are distinct App Store Connect placements. The
5244 × 2950 universal artwork is included in both folders, deliberately using
the same image. The narrower Header and the two 3:2 Search Results images use
layouts made for their respective aspect ratios.

These are static images. The app-preview sizes listed by App Store Connect
describe video slots; this package does not contain app-preview videos.

The filename prefixes give the intended order. iPhone and Play phone tell the
onboarding → home → quiz → spectrum → matches story. Tablet sets begin at home.

## Source captures

The nine originals remain in `docs/store-screenshots/ios/`. App panels retain
their real text, candidates, and scores. Phone panels remove the upper 190 pixels
of the status area; tablet panels remove the upper 64 pixels. The remainder of
each capture is retained. Screens are scaled uniformly and clipped to rounded panels. No app UI is
generated or redrawn. The Play phone panels extend below the canvas, as in the
Sensecast reference.

Google Play artwork adapts the supplied iOS captures, with system bars removed
and no Apple device imagery. These are not fresh captures of the Android build.
The same templates can use Android captures later if exact platform parity is
needed. `manifest.json` records every source, crop, caption, and checksum.

## iPhone Duo

The 16 Duo app panels come from native Device Hub screenshots of the running
Voteaxis app on an iOS 27.1 iPhone Duo Simulator. They retain the actual compact
outer layout and the adaptive inner layout, including the landscape context
rail. They are not iPhone or iPad captures resized into Duo dimensions.

The four views are home, quiz, spectrum, and matches. Spectrum and matches show
a completed 25-question demonstration run using Neutral responses, standard
importance, and no dealbreakers. These are sample values, not the owner's
political preferences. The native originals are in
`docs/store-screenshots/ios/duo-*.png`. The campaign retains each entire native
Duo capture, uniformly scaled inside its frame.

See `capture-notes.md` for the separate manual-placement layout issue found
while preparing the Duo captures. No app source code was changed.

## Rebuild

Requires Node.js, ImageMagick (`magick`), and librsvg (`rsvg-convert`). No package
installation or network access is needed once these tools are present.

From the repository root:

```sh
node scripts/build-store-graphics.mjs
node scripts/build-store-expansion.mjs
node scripts/verify-store-graphics.mjs
```

Edit the headline and caption strings in `scripts/build-store-graphics.mjs` to
change copy. The original background artwork is
`store/graphics/source/spectrum-background.png` and
`store/graphics/source/spectrum-background-wide.png`; fonts are in
`mobile/assets/fonts/`. Existing captures are never overwritten.

The downloaded package includes reference copies of the render/verification
scripts and original captures under `source/`. Run the commands above from the
original repository, where the bundled fonts and expected paths are present.

Reference: https://play.google.com/store/apps/details?id=com.greighstudios.sensecast

Size references:

- https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/
- https://developer.apple.com/help/app-store-connect/reference/app-information/creative-assets-specifications/
- https://support.google.com/googleplay/android-developer/answer/9866151

Feature graphic alt text: Voteaxis: Where do you land? A blue-to-red political
spectrum with a center marker on a navy background.
