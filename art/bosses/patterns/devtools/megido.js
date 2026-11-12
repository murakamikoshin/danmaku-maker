// 「メギドの火(dragonEnd)」の安全な輪が、予告のあいだに自機が届く所に必ず出るかを調べる
// 使い方: node art/bosses/patterns/devtools/megido.js [--n 回数] [--react フレーム] [--speed px/フレーム]
// 自機を画面の動ける範囲のいろいろな所に置いて、技を何回も始めさせ、出た輪ごとに
//   「予告が終わる瞬間の輪の位置(輪は横へ動く)」まで、気づくまでの遅れ(react)のあとにまっすぐ動いて、輪のふち(内側14px)に入れるか
// を計算する。1回でも届かない輪があれば、その数と一番悪い例を出して、終了コード 1 で終わる
// 自機の速さは試射場と同じ 3.3px/フレーム(--speed で変えられる)。輪の動き(端で跳ね返る)は engine.js の step と同じ計算
const fs = require('fs'), path = require('path');
const s = fs.readFileSync(path.join(__dirname, '..', 'engine.js'), 'utf8');
global.document = { createElement: () => ({ getContext: () => ({ fillRect() {} }), width: 0, height: 0 }) };
const args = process.argv.slice(2); let N = 400, react = 12, speed = 3.3;
for (let i = 0; i < args.length; i++) { if (args[i] === '--n') N = +args[++i]; else if (args[i] === '--react') react = +args[++i]; else if (args[i] === '--speed') speed = +args[++i]; }
let seed = 1; Math.random = () => (seed = (seed * 1103515245 + 12345) % 2147483648) / 2147483648;
const bad = new Function('N', 'react', 'speed', s + `;G.boss={id:"dragon",w:240,h:200};
const IN = 14, xs = [8, 60, 120, 180, 240, 300, 352], ys = [220, 300, 380, 460, 540, 588];
let fails = 0;
for (const lv of [0, 1, 2, 3]) {
  let rings = 0, ng = 0, worst = null, minSlack = 1e9, maxNeed = 0;
  for (let r = 0; r < N; r++) {
    reset(); G.aw = lv > 0; G.lv = lv; const gen = R.dragonEnd(G.aw, lv);
    for (let v = 0; v < 6; v++) {
      const P0 = { x: xs[(r + v * 3) % xs.length], y: ys[(r * 5 + v) % ys.length] }; G.P = { ...P0 }; G.zones = [];
      let z = null, done = false;
      for (let f = 0; f < 2000 && !z && !done; f++) { G.P = { ...P0 }; done = gen.next().done; z = G.zones.find(z => z.shape === "safe"); }      // 次の輪が出るまで進める
      if (!z) break;
      // 予告が終わる瞬間(z.t === z.warn + 1 で当たり始める)までの輪の動きを、engine.js の step と同じに動かす
      const cs = z.safe.map(c => ({ ...c }));
      for (let t = 0; t <= z.warn; t++) for (const c of cs) { c.x += c.vx || 0; if (c.x < 50 || c.x > W - 50) c.vx = -(c.vx || 0); }
      // いちばん近い輪へ(届く輪が1つでもあれば良い)
      let best = 1e9, bc = null;
      for (const c of cs) { const need = Math.max(0, hypot(c.x - P0.x, c.y - P0.y) - (c.r - IN)) / speed; if (need < best) { best = need; bc = c; } }
      const slack = z.warn - react - best; rings++;
      minSlack = Math.min(minSlack, slack); maxNeed = Math.max(maxNeed, best);
      if (slack < 0) { ng++; if (!worst || slack < worst.slack) worst = { P0, ring: { x: +bc.x.toFixed(0), y: +bc.y.toFixed(0), r: bc.r }, warn: z.warn, need: +best.toFixed(1), slack: +slack.toFixed(1) }; }
    }
  }
  fails += ng;
  console.log("姿" + lv, "輪の数", rings, "届かない", ng, "| 必要な移動の最大", maxNeed.toFixed(0) + "フレーム", "余り(予告 - 遅れ - 移動)の最小", minSlack.toFixed(0) + "フレーム" + (worst ? " | 一番悪い例 " + JSON.stringify(worst) : ""));
}
return fails;`)(N, react, speed);
console.log(bad ? "NG: 届かない輪がある" : "OK: どの輪も、予告のあいだに届く(気づくまで " + react + "フレーム、速さ " + speed + "px/フレーム)");
process.exit(bad ? 1 : 0);
