// ドラゴンの技を、自動で避ける自機で走らせて、被弾を数える(姿 0〜3 ごと)
// 使い方: node art/bosses/patterns/devtools/sim.js [技のID ...] [--n 回数]   例: node sim.js dragonRoar dragonTail --n 40
//   --react フレーム: 範囲攻撃・炎の柱の予告に気づくまでの遅れの平均(初期値 12 = 0.2秒。予告ごとに半分〜1.5倍でばらつく。人の反応に近づける。0 にすると見えた瞬間に逃げる)
//   --why を付けると、何に当たったか(弾の種類・範囲攻撃の形・炎の柱)の内訳も出す
// 1回 = 1400 フレーム(約23秒。技を何回か繰り返す)。表示は「1回あたりの被弾の平均」(即死はその内数)。回数の初期値は 20
// 乱数は回ごとに決まった種を使うので、同じ engine.js なら毎回同じ数になる(値を変えたときに比べやすいように)
// 見た目(template.html)は使わない。engine.js だけを読み込む。自動で避ける自機は人より上手い所と下手な所があるので、目安として見る
const fs = require('fs'), path = require('path');
const s = fs.readFileSync(path.join(__dirname, '..', 'engine.js'), 'utf8');
global.document = { createElement: () => ({ getContext: () => ({ fillRect() {} }), width: 0, height: 0 }) };
const args = process.argv.slice(2), ids = []; let N = 20, why = 0, react = 12;
for (let i = 0; i < args.length; i++) { if (args[i] === '--n') N = +args[++i]; else if (args[i] === '--why') why = 1; else if (args[i] === '--react') react = +args[++i]; else ids.push(args[i]); }
let seed = 1; Math.random = () => (seed = (seed * 1103515245 + 12345) % 2147483648) / 2147483648;
global.__seed = v => { seed = v; };
new Function('ids', 'N', 'why', 'react', s + `;G.boss={id:"dragon",w:240,h:200}; G.react = react;
const hit0 = hit; let src = {}; hit = o => { if (!G.inv) { const k = !o ? "炎の柱" : o.type || o.shape + (o.claw ? "(爪)" : o.boom ? "(爆発)" : o.pillar ? "(火柱)" : ""); src[k] = (src[k] || 0) + 1; } hit0(o); };
for (const id of (ids.length ? ids : Object.keys(R).filter(k => k.startsWith("dragon")))) { const out = [];
  for (const lv of [0, 1, 2, 3]) { G.aw = lv > 0; G.lv = lv; G.pat = { id, anim: "x" }; let h = 0, k = 0; src = {};
    for (let r = 0; r < N; r++) { __seed(r * 7919 + 13); reset(); for (let i = 0; i < 1400; i++) step(); h += G.hits; k += G.kills; }
    out.push(lv + ":" + (h / N).toFixed(1).padStart(4) + (k ? "(即死" + (k / N).toFixed(1) + ")" : "") + (why ? " [" + Object.entries(src).map(([a, c]) => a + " " + (c / N).toFixed(1)).join(", ") + "]" : "")); }
  console.log(id.padEnd(14), "1回あたりの被弾(姿ごと)", out.join("  ")); }`)(ids, N, why, react);
