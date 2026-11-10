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
  es: {
    '01_home': ['Juega al instante', 'con niveles de muestra'], '02_play_hell': ['Un solo dedo', '¡para esquivarlo todo!'], '03_play_boss': ['También puedes', 'crear jefes'],
    '04_editor': ['Crea niveles de', 'balas con facilidad'], '05_play_fireworks': ['Hasta patrones', 'como fuegos artificiales'], '07_shop': ['Añade disparos, patrones', 'y estilos en la tienda'],
  },
  de: {
    '01_home': ['Sofort spielen', 'mit Beispielstufen'], '02_play_hell': ['Ein Finger,', 'alles ausweichen!'], '03_play_boss': ['Auch Bosskämpfe', 'kannst du bauen'],
    '04_editor': ['Bullet-Hell-Stufen', 'ganz einfach bauen'], '05_play_fireworks': ['Sogar feuerwerks-', 'artige Muster'], '07_shop': ['Schüsse, Muster, Looks', 'im Shop hinzufügen'],
  },
  fr: {
    '01_home': ['Jouez tout de suite', "avec des niveaux d'exemple"], '02_play_hell': ['Un seul doigt', 'pour tout esquiver !'], '03_play_boss': ['Créez aussi', 'vos combats de boss'],
    '04_editor': ['Créez des niveaux', 'de bullet hell'], '05_play_fireworks': ['Même des motifs', "façon feu d'artifice"], '07_shop': ['Tirs, motifs et looks', 'à ajouter dans la boutique'],
  },
  'pt-BR': {
    '01_home': ['Jogue na hora', 'com fases de exemplo'], '02_play_hell': ['Um dedo só', 'para desviar de tudo!'], '03_play_boss': ['Crie também', 'batalhas de chefe'],
    '04_editor': ['Crie fases de', 'bullet hell com facilidade'], '05_play_fireworks': ['Até padrões', 'como fogos de artifício'], '07_shop': ['Adicione tiros, padrões', 'e visuais na loja'],
  },
  ru: {
    '01_home': ['Играйте сразу', 'на примерах уровней'], '02_play_hell': ['Одним пальцем', 'уклоняйтесь от всего!'], '03_play_boss': ['Создавайте и', 'битвы с боссами'],
    '04_editor': ['Легко создавайте', 'уровни с пулями'], '05_play_fireworks': ['Даже узоры', 'как салют'], '07_shop': ['Выстрелы, узоры и вид', '— в магазине'],
  },
  ko: {
    '01_home': ['바로 플레이', '샘플 스테이지'], '02_play_hell': ['손가락 하나로', '탄막을 피해라!'], '03_play_boss': ['보스전도', '직접 만들 수 있어요'],
    '04_editor': ['탄막 스테이지를', '간단하게 제작'], '05_play_fireworks': ['불꽃놀이 같은', '탄막도 만들 수 있어요'], '07_shop': ['공격·탄막·스타일을', '상점에서 추가'],
  },
  'zh-Hans': {
    '01_home': ['立即开玩', '附带示例关卡'], '02_play_hell': ['一根手指', '躲开所有弹幕！'], '03_play_boss': ['连Boss战', '也能自己做'],
    '04_editor': ['轻松制作', '弹幕关卡'], '05_play_fireworks': ['烟花般的', '弹幕也能做'], '07_shop': ['在商店中添加', '射击、弹幕与外观'],
  },
  'zh-Hant': {
    '01_home': ['立即開玩', '附帶範例關卡'], '02_play_hell': ['一根手指', '躲開所有彈幕！'], '03_play_boss': ['連Boss戰', '也能自己做'],
    '04_editor': ['輕鬆製作', '彈幕關卡'], '05_play_fireworks': ['煙火般的', '彈幕也能做'], '07_shop': ['在商店中新增', '射擊、彈幕與外觀'],
  },
};
const SETS = {
  iphone: { dir: SRC, W: 1290, H: 2796, font: 112, top: 150, imgTop: 620, imgW: 0.82, keys: ['01_home', '02_play_hell', '03_play_boss', '05_play_fireworks', '04_editor'] },
  ipad: { dir: path.join(SRC, 'ipad'), W: 2048, H: 2732, font: 104, top: 130, imgTop: 470, imgW: 0.74, keys: ['01_home', '02_play_hell', '03_play_boss', '04_editor', '07_shop'] },
};

const browser = await chromium.connectOverCDP('http://127.0.0.1:9222');
const ctx = browser.contexts()[0];
const page = await ctx.newPage();
for (const [dev, s] of Object.entries(SETS)) {
  await page.setViewportSize({ width: s.W, height: s.H });
  for (const lang of (process.env.LANGS || 'ja en').split(' ')) {
    fs.mkdirSync(path.join(OUT, dev), { recursive: true });
    for (const key of s.keys) {
      const [l1, l2] = CAPTIONS[lang][key];
      const img = 'data:image/png;base64,' + fs.readFileSync(path.join(s.dir, `${lang}_${key}.png`)).toString('base64');
      const fs0 = ['ja', 'ko', 'zh-Hans', 'zh-Hant'].includes(lang) ? s.font : s.font * (['de', 'ru', 'fr'].includes(lang) ? 0.74 : 0.82);
      const html = `<html><body style="margin:0;width:${s.W}px;height:${s.H}px;overflow:hidden;
        background:radial-gradient(120% 70% at 50% 0%, #3b1f6e 0%, #150b33 55%, #0a0820 100%);
        font-family:'Hiragino Sans','Hiragino Kaku Gothic ProN','Apple SD Gothic Neo','PingFang SC','PingFang TC','Helvetica Neue',sans-serif;position:relative">
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
