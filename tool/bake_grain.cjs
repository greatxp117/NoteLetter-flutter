#!/usr/bin/env node
// Bakes web's paper grain into assets/paper/grain.png: the `--grain` token from
// NoteLetter-web/src/styles/theme.css, drawn by the browser that draws web, one
// 160px tile at 3x on a transparent page.
//
//   node tool/bake_grain.cjs
//
// Flutter has no feTurbulence, and a noise made up here is a different paper:
// the 48px tile this replaced averaged 245 on white where web averages 250.
// test/kit/ground_test.dart holds the token this was baked from, so a change to
// `--grain` fails there until this is run again.
const path = require('path');
const fs = require('fs');

const repo = path.resolve(__dirname, '..');
const web = path.resolve(repo, '../NoteLetter-web');
const { chromium } = require(path.join(web, 'node_modules/playwright'));
const css = fs.readFileSync(path.join(web, 'src/styles/theme.css'), 'utf8');

(async () => {
  const browser = await chromium.launch();
  const page = await (await browser.newContext({
    viewport: { width: 160, height: 160 },
    deviceScaleFactor: 3,
  })).newPage();
  await page.setContent(`<!doctype html><html><head><style>${css}</style><style>
    html, body { margin: 0; background: transparent; }
    div { width: 160px; height: 160px; background-image: var(--grain); background-size: 160px 160px; }
  </style></head><body><div></div></body></html>`);
  await page.waitForTimeout(200);
  const out = path.join(repo, 'assets/paper/grain.png');
  await page.screenshot({ path: out, omitBackground: true });
  await browser.close();
  console.log(`baked ${out} (${fs.statSync(out).size} bytes)`);
})();
