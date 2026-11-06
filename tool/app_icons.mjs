/**
 * The app icon on iOS and Android, rendered from the drawings every client
 * renders (../NoteLetter-contracts/assets/app-icon/; the rule is
 * spec/features/app-icon.md). Nothing is drawn or coloured here:
 * test/contract/app_icon_test.dart holds the drawings to AppColors and to the
 * mark, and the committed files to the drawings.
 *
 * Writes:
 *  - iOS: AppIcon.icon, the master as two layers with every system effect off,
 *    which Xcode must hold as a Runner resource. Given a bitmap, iOS 26 segments
 *    it and applies Liquid Glass: the weave and the pressed edge vanish and the
 *    quill turns a translucent pink. Seen on the 26.5 home screen; nothing else
 *    can show it. From this file Xcode also flattens the bitmaps every iOS below
 *    26 reads (Any and Dark are the master, pixel for pixel). Tinted hides the
 *    cloth and swaps in the mono quill, as the handoff's tinted slot asks.
 *  - AppIcon.appiconset, the same art as one 1024 with no alpha channel (the App
 *    Store refuses alpha), the Dark slot on the same file and Tinted as gray +
 *    alpha. While AppIcon.icon exists Xcode 26+ compiles none of these. It is
 *    what a toolchain below Xcode 26 builds, and what `flutter build ipa` reads
 *    when it checks that the icon is not Flutter's placeholder.
 *  - Android legacy ic_launcher.png at mdpi–xxxhdpi, from the flat drawing
 *    (the weave cannot be seen below 512 px). A launcher below API 26 applies
 *    no mask, so these round their own corners, as the favicon does.
 *  - Android adaptive icon (API 26+): the cloth as a colour, the pressed quill
 *    as a vector in the safe zone, and the quill alone as the themed layer.
 *    Each layer's path, placement and fill are the drawing's, verbatim.
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

const ART = resolve(ROOT, '../NoteLetter-contracts/assets/app-icon');
const art = (name) => readFileSync(resolve(ART, name), 'utf8');

const MASTER = art('noteletter-icon-1024.svg');
const FLAT = art('noteletter-icon-flat.svg');
const MONO = art('noteletter-icon-mono.svg');

const CLOTH = /<rect[^>]* fill="(#[0-9A-Fa-f]{6})"/.exec(FLAT)?.[1];
if (!CLOTH) throw new Error('noteletter-icon-flat.svg has no cloth; update this tool');

const IOS = resolve(ROOT, 'ios/Runner/Assets.xcassets/AppIcon.appiconset');
const RES = resolve(ROOT, 'android/app/src/main/res');

/** Android legacy launcher sizes. */
const ANDROID = [
  { dir: 'mipmap-mdpi', px: 48 },
  { dir: 'mipmap-hdpi', px: 72 },
  { dir: 'mipmap-xhdpi', px: 96 },
  { dir: 'mipmap-xxhdpi', px: 144 },
  { dir: 'mipmap-xxxhdpi', px: 192 },
];
/** The favicon drawing's corner, 230 of 1024: the one the art rounds itself. */
const CORNER = 230 / 1024;

const browser = await chromium.launch();
const page = await browser.newPage({ deviceScaleFactor: 1 });

async function render(svg, px, radius = 0) {
  await page.setViewportSize({ width: px, height: px });
  const sized = svg.replace(/<svg[^>]*>/, (tag) => tag.replace(/ (width|height)="\d+"/g, ''));
  await page.setContent(`<!doctype html><meta charset="utf-8">
<style>
  html,body{margin:0;padding:0;background:transparent}
  .tile{width:${px}px;height:${px}px;border-radius:${px * radius}px;overflow:hidden}
  svg{width:${px}px;height:${px}px;display:block}
</style>
<div class="tile">${sized}</div>`);
  return page.locator('.tile').screenshot({ omitBackground: true });
}

/** Re-save through Pillow in `mode`, dropping or reducing the channels. */
function resave(path, mode) {
  execFileSync('python3', ['-c',
    'import sys;from PIL import Image;p,m=sys.argv[1:];Image.open(p).convert(m).save(p,optimize=True)',
    path, mode]);
}

// The catalog: Any and Dark are one opaque file; Tinted is the quill alone, in gray.
for (const f of readdirSync(IOS)) if (f.endsWith('.png')) rmSync(resolve(IOS, f));
const iosPng = resolve(IOS, 'AppIcon-1024.png');
writeFileSync(iosPng, await render(MASTER, 1024));
resave(iosPng, 'RGB');
const tintedPng = resolve(IOS, 'AppIcon-1024-tinted.png');
writeFileSync(tintedPng, await render(MONO, 1024));
resave(tintedPng, 'LA');
const slot = (filename, value) => ({
  ...(value ? { appearances: [{ appearance: 'luminosity', value }] } : {}),
  filename, idiom: 'universal', platform: 'ios', size: '1024x1024',
});
writeFileSync(resolve(IOS, 'Contents.json'), JSON.stringify({
  images: [
    slot('AppIcon-1024.png'),
    slot('AppIcon-1024.png', 'dark'),
    slot('AppIcon-1024-tinted.png', 'tinted'),
  ],
  info: { author: 'xcode', version: 1 },
}, null, 2) + '\n');
console.log('  ios AppIcon-1024.png (no alpha; any + dark), AppIcon-1024-tinted.png (gray + alpha)');

// The layered icon: the same master, split where the handoff splits it. The first
// group is the frontmost, and every effect is off so the system draws only the art.
const ICON = resolve(ROOT, 'ios/Runner/AppIcon.icon');
rmSync(ICON, { recursive: true, force: true });
mkdirSync(resolve(ICON, 'Assets'), { recursive: true });
const svgTag = MASTER.match(/<svg[^>]*>/)[0];
const clothSvg = `${svgTag}${MASTER.match(/<rect[^>]*\/>/)[0]}${MASTER.match(/<path d="[^"]*"[^>]*\/>/)[0]}</svg>`;
const quillSvg = `${svgTag}${[...MASTER.matchAll(/<path transform=[^>]*\/>/g)].map((m) => m[0]).join('')}</svg>`;
const clothPng = resolve(ICON, 'Assets/cloth.png');
writeFileSync(clothPng, await render(clothSvg, 1024));
resave(clothPng, 'RGB');
writeFileSync(resolve(ICON, 'Assets/quill.png'), await render(quillSvg, 1024));
writeFileSync(resolve(ICON, 'Assets/quill-mono.png'), await render(MONO, 1024));
const srgb = (hex) => `srgb:${[1, 3, 5]
  .map((i) => (parseInt(hex.slice(i, i + 2), 16) / 255).toFixed(5)).join(',')},1.00000`;
const group = (layer) => ({
  layers: [{ glass: false, ...layer }],
  shadow: { kind: 'none', opacity: 0.5 },
  specular: false,
  translucency: { enabled: false, value: 0.5 },
});
writeFileSync(resolve(ICON, 'icon.json'), JSON.stringify({
  'fill-specializations': [
    { value: { solid: srgb(CLOTH) } },
    { appearance: 'tinted', value: 'none' },
  ],
  groups: [
    group({
      name: 'quill',
      'image-name-specializations': [
        { value: 'quill.png' },
        { appearance: 'tinted', value: 'quill-mono.png' },
      ],
    }),
    group({
      name: 'cloth',
      'image-name': 'cloth.png',
      'hidden-specializations': [{ appearance: 'tinted', value: true }],
    }),
  ],
  'supported-platforms': { squares: 'shared' },
}, null, 2) + '\n');
console.log('  ios AppIcon.icon (cloth + quill, no glass; tinted: the mono quill alone)');

// Android legacy: the flat drawing, rounded because no launcher will round it.
for (const { dir, px } of ANDROID) {
  mkdirSync(resolve(RES, dir), { recursive: true });
  writeFileSync(resolve(RES, dir, 'ic_launcher.png'), await render(FLAT, px, CORNER));
  console.log(`  android ${dir}/ic_launcher.png ${px}px`);
}
await browser.close();

/** A 108dp drawing's quill layers as VectorDrawable groups, in paint order. */
function vectorLayers(name) {
  const layers = [...art(name).matchAll(
    /<path transform="translate\(([-\d.]+) ([-\d.]+)\) scale\(([\d.]+)\)" fill="(#[0-9A-Fa-f]{6})" d="([^"]+)"\s*\/>/g)];
  if (!layers.length) throw new Error(`${name} changed shape; update this tool`);
  return layers.map(([, x, y, s, fill, d]) => `    <group
        android:translateX="${x}"
        android:translateY="${y}"
        android:scaleX="${s}"
        android:scaleY="${s}">
        <path
            android:fillColor="${fill}"
            android:pathData="${d}"/>
    </group>`).join('\n');
}

function vector(name) {
  return `<?xml version="1.0" encoding="utf-8"?>
<!-- Generated by tool/app_icons.mjs from NoteLetter-contracts/assets/app-icon/${name}. Do not edit; re-run it. -->
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="108dp"
    android:height="108dp"
    android:viewportWidth="108"
    android:viewportHeight="108">
${vectorLayers(name)}
</vector>
`;
}

// Android adaptive (API 26+).
mkdirSync(resolve(RES, 'mipmap-anydpi-v26'), { recursive: true });
writeFileSync(resolve(RES, 'mipmap-anydpi-v26/ic_launcher.xml'),
`<?xml version="1.0" encoding="utf-8"?>
<!-- Generated by tool/app_icons.mjs. Do not edit; re-run it. -->
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background"/>
    <foreground android:drawable="@drawable/ic_launcher_foreground"/>
    <monochrome android:drawable="@drawable/ic_launcher_monochrome"/>
</adaptive-icon>
`);
writeFileSync(resolve(RES, 'values/ic_launcher_background.xml'),
`<?xml version="1.0" encoding="utf-8"?>
<!-- Generated by tool/app_icons.mjs: the icon's cloth, brick-500. -->
<resources>
    <color name="ic_launcher_background">${CLOTH}</color>
</resources>
`);
writeFileSync(resolve(RES, 'drawable/ic_launcher_foreground.xml'),
  vector('android/ic_launcher_foreground.svg'));
writeFileSync(resolve(RES, 'drawable/ic_launcher_monochrome.xml'),
  vector('android/ic_launcher_monochrome.svg'));
console.log('  android adaptive icon (background colour, foreground, monochrome)');
