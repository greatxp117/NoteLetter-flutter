/**
 * The app icon: NoteLetter's quill knocked out of the seal tile, on iOS and
 * Android. Until 2026-11-03 both platforms shipped Flutter's stock icon and
 * "NoteLetter Flutter".
 *
 * Nothing is invented here:
 *  - The mark is READ from ../NoteLetter-browserextension/assets/logo-mark.svg.
 *    That is the one quill path that web (icons.jsx, SignIn, LandingActual)
 *    and the extension's toolbar icons all draw.
 *  - The treatment is the extension's `scripts/icons.mjs`: the mark on a seal
 *    tile, inset 0.14–0.16, corner radius 0.22.
 *  - The colours are TOKENS. The tile is `--seal` in light (`--brick-700`,
 *    AppColors.sealLight) and the mark is `--accent-fg` (`--paper-50`,
 *    AppColors.primaryForeground), as web draws a filled seal. The extension
 *    script still holds pre-ADR-066 literals (#7A2820 / #FAF7F2); these do not.
 *  test/contract/app_icon_test.dart holds all three to their sources.
 *
 * Writes:
 *  - iOS: AppIcon.appiconset as ONE 1024 universal image. It is full-bleed and
 *    opaque, because iOS applies its own mask and rejects alpha.
 *  - Android legacy ic_launcher.png at mdpi–xxxhdpi, as the rounded tile.
 *  - Android adaptive icon (API 26+): the seal as a colour plus the quill as a
 *    vector, with the path copied verbatim, also used as the themed
 *    (monochrome) layer.
 *
 * Rendered with headless Chromium, the same engine and the same Playwright
 * install the extension's icons come from:
 *
 *   node tool/app_icons.mjs        (needs ../NoteLetter-browserextension's
 *                                   node_modules, and python3 with Pillow)
 */
import { createRequire } from 'node:module';
import { execFileSync } from 'node:child_process';
import { readFileSync, writeFileSync, mkdirSync, readdirSync, rmSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const EXT = resolve(ROOT, '../NoteLetter-browserextension');
const { chromium } = createRequire(resolve(EXT, 'package.json'))('playwright');

const MARK = resolve(EXT, 'assets/logo-mark.svg');
const SEAL = '#6E1F18'; // --seal (light) = --brick-700 = AppColors.sealLight
const GLYPH = '#FAFAF7'; // --accent-fg = --paper-50 = AppColors.primaryForeground

const svg = readFileSync(MARK, 'utf8');
const inner = svg.replace(/^[\s\S]*?<svg[^>]*>/, '').replace(/<\/svg>\s*$/, '');
const viewBox = (svg.match(/viewBox="([^"]+)"/) || [, '0 0 512 512'])[1];
const pathData = (svg.match(/<path[^>]*\sd="([^"]+)"/) || [])[1];
if (!pathData || viewBox !== '0 0 512 512') {
  throw new Error(`logo-mark.svg changed shape (viewBox ${viewBox}); update this tool`);
}

const IOS = resolve(ROOT, 'ios/Runner/Assets.xcassets/AppIcon.appiconset');
const RES = resolve(ROOT, 'android/app/src/main/res');

/** Android legacy launcher sizes; inset as the extension's nearest size. */
const ANDROID = [
  { dir: 'mipmap-mdpi', px: 48, pad: 0.14 },
  { dir: 'mipmap-hdpi', px: 72, pad: 0.15 },
  { dir: 'mipmap-xhdpi', px: 96, pad: 0.15 },
  { dir: 'mipmap-xxhdpi', px: 144, pad: 0.15 },
  { dir: 'mipmap-xxxhdpi', px: 192, pad: 0.16 },
];

const browser = await chromium.launch();
const page = await browser.newPage({ deviceScaleFactor: 1 });

async function tile({ px, pad, radius }) {
  const markSize = Math.round(px * (1 - pad * 2));
  await page.setViewportSize({ width: px, height: px });
  await page.setContent(`<!doctype html><meta charset="utf-8">
<style>
  html,body{margin:0;padding:0;background:transparent}
  .tile{width:${px}px;height:${px}px;border-radius:${Math.round(px * radius)}px;
    background:${SEAL};display:grid;place-items:center;overflow:hidden}
  svg{width:${markSize}px;height:${markSize}px;display:block}
  svg path{fill:${GLYPH}}
</style>
<div class="tile"><svg viewBox="${viewBox}" xmlns="http://www.w3.org/2000/svg">${inner}</svg></div>`);
  return page.locator('.tile').screenshot({ omitBackground: true });
}

// iOS: one opaque, full-bleed 1024. iOS draws the squircle; radius 0 here.
for (const f of readdirSync(IOS)) if (f.endsWith('.png')) rmSync(resolve(IOS, f));
const iosPng = resolve(IOS, 'AppIcon-1024.png');
writeFileSync(iosPng, await tile({ px: 1024, pad: 0.16, radius: 0 }));
execFileSync('python3', ['-c',
  'import sys;from PIL import Image;p=sys.argv[1];Image.open(p).convert("RGB").save(p,optimize=True)',
  iosPng]);
writeFileSync(resolve(IOS, 'Contents.json'), JSON.stringify({
  images: [{ filename: 'AppIcon-1024.png', idiom: 'universal', platform: 'ios', size: '1024x1024' }],
  info: { author: 'xcode', version: 1 },
}, null, 2) + '\n');
console.log('  ios AppIcon-1024.png (opaque, universal)');

// Android legacy: the rounded tile, as the extension draws it.
for (const { dir, px, pad } of ANDROID) {
  mkdirSync(resolve(RES, dir), { recursive: true });
  writeFileSync(resolve(RES, dir, 'ic_launcher.png'), await tile({ px, pad, radius: 0.22 }));
  console.log(`  android ${dir}/ic_launcher.png ${px}px`);
}
await browser.close();

// Android adaptive (API 26+). The foreground canvas is 108dp; launchers show
// the middle 72dp and promise only a 66dp circle. The quill is diagonal, so
// its nib reaches ~0.69 of its box's half-diagonal: a 46dp mark keeps the
// nib inside that circle on a round mask.
const MARK_DP = 46;
const scale = (MARK_DP / 108).toFixed(4);
mkdirSync(resolve(RES, 'mipmap-anydpi-v26'), { recursive: true });
writeFileSync(resolve(RES, 'mipmap-anydpi-v26/ic_launcher.xml'),
`<?xml version="1.0" encoding="utf-8"?>
<!-- Generated by tool/app_icons.mjs. Do not edit; re-run it. -->
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background"/>
    <foreground android:drawable="@drawable/ic_launcher_foreground"/>
    <monochrome android:drawable="@drawable/ic_launcher_foreground"/>
</adaptive-icon>
`);
writeFileSync(resolve(RES, 'values/ic_launcher_background.xml'),
`<?xml version="1.0" encoding="utf-8"?>
<!-- Generated by tool/app_icons.mjs: the seal token (light), brick-700. XML comments cannot hold a double hyphen, so the CSS names are spelled out. -->
<resources>
    <color name="ic_launcher_background">${SEAL}</color>
</resources>
`);
writeFileSync(resolve(RES, 'drawable/ic_launcher_foreground.xml'),
`<?xml version="1.0" encoding="utf-8"?>
<!-- Generated by tool/app_icons.mjs from NoteLetter-browserextension/assets/logo-mark.svg.
     The pathData is that file's path, verbatim. -->
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="108dp"
    android:height="108dp"
    android:viewportWidth="512"
    android:viewportHeight="512">
    <group
        android:pivotX="256"
        android:pivotY="256"
        android:scaleX="${scale}"
        android:scaleY="${scale}">
        <path
            android:fillColor="${GLYPH}"
            android:pathData="${pathData}"/>
    </group>
</vector>
`);
console.log(`  android adaptive icon (mark ${MARK_DP}dp of 108)`);
