// ドラゴンの技を、自動で避ける自機で走らせて、被弾を数える(姿 0〜3 ごとに4回ずつ)
// 使い方: node art/bosses/patterns/devtools/sim.js [技のID ...]   例: node sim.js dragonRoar dragonTail
// 見た目(template.html)は使わない。engine.js だけを読み込む。数は毎回少し変わる(乱数)ので、目安として見る
const fs = require('fs'), path = require('path');
const s = fs.readFileSync(path.join(__dirname, '..', 'engine.js'), 'utf8');
global.document = { createElement: () => ({ getContext: () => ({ fillRect() {} }), width: 0, height: 0 }) };
const ids = process.argv.slice(2);
new Function('ids', s + `;G.boss={id:"dragon",w:240,h:200};
for (const id of (ids.length ? ids : Object.keys(R).filter(k => k.startsWith("dragon")))) { const out = [];
  for (const lv of [0, 1, 2, 3]) { G.aw = lv > 0; G.lv = lv; G.pat = { id, anim: "x" }; let h = 0, k = 0;
    for (let r = 0; r < 4; r++) { reset(); for (let i = 0; i < 1400; i++) step(); h += G.hits; k += G.kills; }
    out.push(lv + ":" + h + (k ? "/即死" + k : "")); }
  console.log(id, "4回の被弾(姿ごと)", out.join("  ")); }`)(ids);
