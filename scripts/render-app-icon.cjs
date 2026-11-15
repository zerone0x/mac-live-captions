#!/usr/bin/env node
// Renders the macOS app icon PNGs of App/Assets.xcassets/AppIcon.appiconset
// from the committed SVG sources in design/icon (docs/DECISIONS.md 0025).
//
// A developer tool, not a CI step: it needs Node with Playwright and a
// Chromium. The rendered PNGs are committed; CI only compiles them.
//
//   python3 design/icon/generate-svgs.py           # only if the design changed
//   NODE_PATH=/path/to/node_modules CHROME=/path/to/chromium \
//     node scripts/render-app-icon.cjs
//
// CHROME is optional (Playwright's own Chromium is used without it).
// Each size renders the SVG at its final pixel size (no downscaling of a
// large bitmap); 16 px and 32 px use their own pixel-snapped masters.
'use strict';

const fs = require('fs');
const path = require('path');
const { chromium } = require('playwright');

const root = path.resolve(__dirname, '..');
const sources = path.join(root, 'design/icon');
const iconset = path.join(root, 'App/Assets.xcassets/AppIcon.appiconset');

// Pixel size -> SVG master.
function masterFor(pixels) {
  if (pixels <= 16) return 'AppIcon-16.svg';
  if (pixels <= 32) return 'AppIcon-32.svg';
  return 'AppIcon.svg';
}

const sizes = [16, 32, 128, 256, 512];
const images = [];
for (const size of sizes) {
  for (const scale of [1, 2]) {
    images.push({ size, scale, pixels: size * scale, filename: `icon_${size}x${size}${scale === 2 ? '@2x' : ''}.png` });
  }
}

(async () => {
  const browser = await chromium.launch(process.env.CHROME ? { executablePath: process.env.CHROME } : {});
  try {
    const page = await browser.newPage({ deviceScaleFactor: 1 });
    for (const image of images) {
      const svg = fs.readFileSync(path.join(sources, masterFor(image.pixels)));
      const s = image.pixels;
      await page.setViewportSize({ width: s, height: s });
      await page.setContent(
        '<style>html,body{margin:0;background:transparent}</style>' +
          `<img id="icon" width="${s}" height="${s}" src="data:image/svg+xml;base64,${svg.toString('base64')}">`,
      );
      await page.waitForFunction(() => document.getElementById('icon').complete);
      await page.locator('#icon').screenshot({ path: path.join(iconset, image.filename), omitBackground: true });
      console.log(`rendered ${image.filename} (${s} px, ${masterFor(s)})`);
    }
  } finally {
    await browser.close();
  }

  const contents = {
    images: images.map((image) => ({
      filename: image.filename,
      idiom: 'mac',
      scale: `${image.scale}x`,
      size: `${image.size}x${image.size}`,
    })),
    info: { author: 'xcode', version: 1 },
  };
  fs.writeFileSync(path.join(iconset, 'Contents.json'), JSON.stringify(contents, null, 2) + '\n');
  console.log('wrote Contents.json');
})().catch((error) => {
  console.error(error);
  process.exit(1);
});
