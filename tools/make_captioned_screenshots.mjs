// ストア用スクリーンショットに、見出しの説明文を重ねた画像を作る。
// 使い方: node tools/make_captioned_screenshots.mjs  (Chrome を localhost:9222 で起動しておく)
import { chromium } from '/Users/murakami/.local/playwright/node_modules/playwright/index.mjs';
import fs from 'node:fs';
import path from 'node:path';

const ROOT = path.resolve(new URL('..', import.meta.url).pathname);
const SRC = path.join(ROOT, 'docs/store_screenshots');
const OUT = path.join(SRC, 'captioned');

const CAPTIONS = {
  ja: {
    '01_home': ['すぐ遊べる', 'サンプルステージ'],
    '02_play_hell': ['指ひとつで', '弾幕をよけきれ！'],
    '03_play_boss': ['ボス戦も', '自分で作れる'],
    '04_editor': ['弾幕ステージを', 'かんたんに作れる'],
    '05_play_fireworks': ['花火みたいな', '弾幕も作れる'],
    '07_shop': ['撃ち方・弾幕・見た目を', 'ショップで追加'],
  },
  en: {
    '01_home': ['Play right away', 'with sample stages'],
    '02_play_hell': ['One finger', 'to dodge it all!'],
    '03_play_boss': ['Boss fights', 'you can build too'],
    '04_editor': ['Build bullet-hell', 'stages with ease'],
    '05_play_fireworks': ['Even fireworks-like', 'patterns are yours'],
    '07_shop': ['Add shots, patterns', 'and looks in the shop'],
  },
};
const SETS = {
  iphone: { dir: SRC, W: 1290, H: 2796, font: 112, top: 150, imgTop: 620, imgW: 0.82, keys: ['01_home', '02_play_hell', '03_play_boss', '05_play_fireworks', '04_editor'] },
  ipad: { dir: path.join(SRC, 'ipad'), W: 2048, H: 2732, font: 104, top: 130, imgTop: 470, imgW: 0.74, keys: ['01_home', '02_play_hell', '03_play_boss', '04_editor', '07_shop'] },
};

const browser = await chromium.connectOverCDP('http://localhost:9222');
const ctx = browser.contexts()[0];
const page = await ctx.newPage();
for (const [dev, s] of Object.entries(SETS)) {
  await page.setViewportSize({ width: s.W, height: s.H });
  for (const lang of ['ja', 'en']) {
    fs.mkdirSync(path.join(OUT, dev), { recursive: true });
    for (const key of s.keys) {
      const [l1, l2] = CAPTIONS[lang][key];
      const img = 'data:image/png;base64,' + fs.readFileSync(path.join(s.dir, `${lang}_${key}.png`)).toString('base64');
      const fs0 = lang === 'en' ? s.font * 0.86 : s.font;
      const html = `<html><body style="margin:0;width:${s.W}px;height:${s.H}px;overflow:hidden;
        background:radial-gradient(120% 70% at 50% 0%, #3b1f6e 0%, #150b33 55%, #0a0820 100%);
        font-family:'Hiragino Sans','Hiragino Kaku Gothic ProN','Helvetica Neue',sans-serif;position:relative">
        <div style="position:absolute;top:${s.top}px;left:0;right:0;text-align:center;color:#fff;font-weight:900;white-space:nowrap;
          font-size:${fs0}px;line-height:1.22;letter-spacing:0.01em;text-shadow:0 6px 30px rgba(255,107,157,.5)">
          ${l1}<br><span style="color:#ffd166">${l2}</span></div>
        <img src="${img}" style="position:absolute;left:50%;transform:translateX(-50%);top:${s.imgTop}px;width:${s.W * s.imgW}px;
          border-radius:${s.W * 0.05}px;border:${s.W * 0.006}px solid rgba(255,255,255,.22);box-shadow:0 40px 120px rgba(0,0,0,.6)"></body></html>`;
      await page.setContent(html);
      await page.waitForTimeout(600);
      await page.screenshot({ path: path.join(OUT, dev, `${lang}_${key}.png`) });
      console.log('made', dev, lang, key);
    }
  }
}
await page.close();
process.exit(0);
