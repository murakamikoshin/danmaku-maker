// 試作(docs/prototype.html)の emit/step を Node で動かし、Swift 版と突き合わせる正解データを作る。
// 使い方: node tools/make_reference.mjs
import fs from 'node:fs';
import vm from 'node:vm';

const html = fs.readFileSync(new URL('../docs/prototype.html', import.meta.url), 'utf8');
const code = html.slice(html.indexOf('<script>') + 8, html.lastIndexOf('</script>'));

const stub = () => new Proxy(function () {}, {
  get: (_, k) => k === Symbol.toPrimitive ? () => 0 : k === Symbol.iterator ? function* () {} : stub(),
  set: () => true,
  apply: () => stub(),
});
const ctx = vm.createContext({
  document: stub(), window: stub(), performance: { now: () => 0 },
  requestAnimationFrame: () => 0, cancelAnimationFrame: () => {},
  localStorage: { getItem: () => null, setItem: () => {} }, console,
});
vm.runInContext(code, ctx);

const SEED = 12345;
const TICKS = [1, 100, 144, 145, 200, 300, 500, 800, 1200, 1800, 2500, 3600];
const em = (t, o = {}) => ({ t, x: .5, y: .2, s: 0, e: 30, i: 1, c: 16, v: 2, r: 0, k: 0, ph: 0, ...o });
const stages = [
  { name: 'ring', mode: 'survive', durationSec: 30, emitters: [em('ring', { y: .25, i: 1, c: 16, v: 2, r: 6 })] },
  { name: 'spiral', mode: 'survive', durationSec: 30, emitters: [em('spiral', { i: .12, c: 3, v: 1.8, r: 11 })] },
  { name: 'aim', mode: 'survive', durationSec: 30, emitters: [em('aim', { x: .2, y: .15, i: .9, c: 5, v: 3, r: 40 }), em('aim', { x: .8, y: .15, s: .45, i: .9, c: 5, v: 3, r: 40, k: 3 })] },
  { name: 'rain', mode: 'survive', durationSec: 30, emitters: [em('rain', { y: 0, i: .18, c: 2, v: 2.2 }), em('aim', { s: 5, i: 1.5, c: 3, v: 2.5, r: 30, k: 2 })] },
  { name: 'sweep', mode: 'survive', durationSec: 30, emitters: [em('sweep', { y: .1, i: .2, c: 3, v: 3, r: 70, k: 1 }), em('ring', { x: .3, s: 3.3, i: .7, c: 20, v: 2.2, r: -7 })] },
  { name: 'boss3', mode: 'boss', durationSec: 60, bossHp: 400, bossMove: 1, emitters: [
    em('aim', { i: .6, c: 5, v: 2.6, r: 50, k: 2, ph: 1 }), em('ring', { i: .55, c: 18, v: 2, r: 9, ph: 2 }),
    em('spiral', { i: .09, c: 4, v: 2.1, r: 13, k: 3, ph: 3 }), em('aim', { i: 1.4, c: 3, v: 3.2, r: 20, k: 1, ph: 3 })] },
  { name: 'bossHarmless', mode: 'boss', durationSec: 60, bossHp: 300, bossMove: 2, emitters: [
    em('ring', { i: .1, c: 1, v: 1, r: 0 })] },
];

const out = stages.map(st => {
  const proto = { m: st.mode, h: st.bossHp || 0, mv: st.bossMove || 0, n: st.name, a: 'x', d: st.durationSec, e: st.emitters, id: 'ref' };
  vm.runInContext(`startGame(${JSON.stringify(proto)},'play'); game.rng = mulberry(${SEED});`, ctx);
  const snaps = []; let over = null;
  for (let tick = 1; tick <= 8000; tick++) {
    vm.runInContext('step(1/120)', ctx);
    const r = JSON.parse(vm.runInContext(`JSON.stringify({o:game.over,t:game.t,n:game.bullets.length,hp:game.hp,ph:game.phase,
      sx:game.bullets.reduce((a,b)=>a+b.x,0),sy:game.bullets.reduce((a,b)=>a+b.y,0),
      fx:game.bullets[0]?game.bullets[0].x:0,fy:game.bullets[0]?game.bullets[0].y:0})`, ctx));
    if (r.o) { over = { tick, kind: r.o === 'win' ? 'win' : 'lose', hp: r.hp }; break; }
    if (TICKS.includes(tick)) snaps.push({ tick, count: r.n, hp: r.hp, phase: r.ph, sumX: r.sx, sumY: r.sy, firstX: r.fx, firstY: r.fy });
  }
  return { name: st.name, seed: SEED, stage: st, snapshots: snaps, over };
});
fs.writeFileSync(new URL('../DanmakuCore/Tests/DanmakuCoreTests/Resources/reference.json', import.meta.url), JSON.stringify(out, null, 1));
for (const s of out) console.log(s.name.padEnd(14), 'snaps', s.snapshots.length, 'over', JSON.stringify(s.over));
