// ボス専用の技のプレビュー用エンジン(見た目の確認用。ゲームの計算そのものではない)
// 画面は論理 360×600、ボスの絵は2倍。速さは 60fps の px/フレーム
"use strict";
const W = 360, H = 600, PI = Math.PI, TAU = PI * 2;
const sin = Math.sin, cos = Math.cos, atan2 = Math.atan2, hypot = Math.hypot, rand = Math.random;
const clamp = (v, a, b) => Math.max(a, Math.min(b, v));

// ---------- 専用の弾のドット絵(1文字 = 1論理px。上向きの絵は、進む向きへ回す) ----------
const MAPS = {
  kingyo: ["..oo..", ".oRRo.", "oRkRRo", "oRRRRo", ".oRLo.", "..oo..", ".FFFF.", "F.FF.F"],
  yoyo: ["..ooo..", ".oBBBo.", "oBWBBBo", "oSSSSSo", "oBBBBBo", ".oBBBo.", "..ooo..", "...o..."],
  spark: ["..W..", ".WYW.", "WYYYW", ".WYW.", "..W.."],
  awa: [".ooo.", "oW..o", "o...o", "o...o", ".ooo."],
  fox: ["...o...", "..oBo..", "..oBo..", ".obWBo.", ".oBWBo.", "obBWWBo", "obWWWBo", "obBWBbo", ".obbbo.", "..ooo.."],
  ofuda: ["kkkkk", "kwwwk", "kwrwk", "kwwwk", "kwrwk", "kwrwk", "kwwwk", "krrrk", "kkkkk"],
  plankton: [".gGg.", "gGWGg", "GWWWG", "gGWGg", ".gGg."],
  bubble: ["..ooooo..", ".o.....o.", "o..W....o", "o.W.....o", "o.......o", "o.......o", "o.......o", ".o.....o.", "..ooooo.."],
  ink: ["..kkkkk..", ".kPPPPPk.", "kPpWPPPPk", "kPWpPPPPk", "kPPPPPPPk", "kPPPPPPpk", "kPPPPPppk", ".kPPPppk.", "..kkkkk.."],
  missile: ["..o..", ".oWo.", ".oWo.", ".oMo.", ".oMo.", ".oMo.", "oRMRo", "oRMRo", ".oYo.", "..Y..", "..y.."],
  hex: ["..ooo..", ".oCCCo.", "oCWWWCo", "oCWWWCo", "oCWWWCo", ".oCCCo.", "..ooo.."],
  shell: [".Y.", "YWY", "YWY", "OYO", ".O."],
  flake: ["o..o..o", ".o.o.o.", "..oWo..", "ooWWWoo", "..oWo..", ".o.o.o.", "o..o..o"],
  icicle: ["..W..", "..W..", ".oWo.", ".oWo.", ".oLo.", ".oLo.", "oLWLo", "oLWLo", "oLLLo", "oLLLo", "oLWLo", ".ooo.", "..o.."],
  shard: ["..o..", ".oWo.", ".oWo.", "oWLWo", ".oLo.", ".oLo.", "..o.."],
  soul: ["..ooo..", ".oGGGo.", "oGWWWGo", "oGWWWGo", ".oGWGo.", ".ogGgo.", "..ogo..", "..og...", "...o..."],
  blade: ["...ooo.", ".ooWWo.", "oWWo...", "oWo....", "oWWo...", ".ooWWo.", "...ooo."],
  chain: [".ooo.", "oL.Lo", "oL.Lo", "oL.Lo", "oL.Lo", "oL.Lo", ".ooo."],
  jelly: ["..ooooo..", ".oPPPPPo.", "oPWPPPPPo", "oPWPPPPPo", "oPPPPPPPo", "oPPPPPPpo", ".oppppPo.", "..ooooo.."],
  eye: ["..ooooo..", ".oWWWWWo.", "oWWRRRWWo", "oWRRkRRWo", "oWRkkkRWo", "oWRRkRRWo", "oWWRRRWWo", ".oWWWWWo.", "..ooooo.."],
  tooth: ["ooooo", "oWWWo", "oWWWo", ".oWo.", ".oWo.", "..o..", "..o.."],
  goo: [".kkk.", "kPGPk", "kGWGk", "kPGPk", ".kkk."],
  // 最強のドラゴン: 大きい弾が中心(画面では big で拡大して使う)
  flame: ["..ooo..", ".oYYYo.", "oYWWWYo", "oYWWWYo", "oOYWYOo", ".oOYOo.", ".oOOOo.", "..oOo..", "..oOo..", "...o..."],
  slash: ["......ooo", "....ooWWo", "..ooWWYo.", ".oWWYYo..", "oWWYYo...", "oWYYo....", "oWYo.....", "oWYo.....", ".oWYo....", "..oWYo...", "...ooo..."],
  gust: ["..oo.....", ".oWWoo...", "oWLLWWoo.", ".oLLLLWWo", "..ooLLLWo", "....oLLWo", "..ooLLWo.", ".oLLWWo..", "oWWWoo...", ".ooo....."],
  sun: ["...ooooo...", "..oYYYYYo..", ".oYYWWWYYo.", "oYYWWWWWYYo", "oYWWWWWWWYo", "oYWWWWWWWYo", "oYWWWWWWWYo", "oYYWWWWWYYo", ".oYYWWWYYo.", "..oYYYYYo..", "...ooooo..."],
  rock: ["..oooo...", ".oRRRRoo.", "oRRrRRRRo", "oRrrRRYRo", "oRRRRYYRo", "oRRrRRRRo", ".oRRRrRo.", "..ooooo.."],
  spine: [".W.", ".W.", "oWo", "oYo", "oYo", "oYo", "oyo", "oyo", "oyo", ".o."],
  tornado: ["oWWWWWWWWWo", ".oLLLLLLLo.", ".oWWWWWWWo.", "..oLLLLLo..", "..oWWWWWo..", "...oLLLo...", "...oWWWo...", "....oLo....", "....oWo....", ".....o....."],
  ember: ["..o..", ".oYo.", "oYWYo", ".oYo.", "..o.."],
  pshot: [".W.", "oWo", "oCo", "oCo", "oCo", ".o."],
};
// 通常 / 覚醒 の色
const PALS = {
  kingyo: [{ o: "#7a1414", R: "#f04a28", L: "#ffa078", k: "#200808", F: "#ffb4a0" }, { o: "#0e0618", R: "#3a2050", L: "#6a4a88", k: "#ffd040", F: "#9070c0" }],
  yoyo: [{ o: "#20507a", B: "#78c8ff", W: "#ffffff", S: "#ff5078" }, { o: "#40104a", B: "#c878ff", W: "#ffffff", S: "#ffd040" }],
  spark: [{ W: "#fff6c8", Y: "#ffb420" }, { W: "#ffe0f6", Y: "#e050ff" }],
  awa: [{ o: "#8cd8f8", W: "#ffffff" }, { o: "#c8a0ff", W: "#ffffff" }],
  fox: [{ o: "#14286a", b: "#2878f0", B: "#6ec8ff", W: "#ebfaff" }, { o: "#2a0a46", b: "#7a28c8", B: "#c88cff", W: "#f6e8ff" }],
  ofuda: [{ k: "#3c1414", w: "#f5ebd7", r: "#c81e32" }, { k: "#1a0a28", w: "#d8c8f0", r: "#8c28dc" }],
  plankton: [{ g: "#127a72", G: "#3cdcc8", W: "#e6fff8" }, { g: "#7a1222", G: "#ff4664", W: "#ffe6ea" }],
  bubble: [{ o: "#96e6f0", W: "#ffffff" }, { o: "#ff7890", W: "#ffffff" }],
  ink: [{ k: "#0a0614", P: "#3c2a5a", p: "#1e1432", W: "#8c78b4" }, { k: "#14040a", P: "#5a1428", p: "#320a14", W: "#c86478" }],
  missile: [{ o: "#141820", W: "#ffffff", M: "#b4bed2", R: "#e03030", Y: "#ffdc50", y: "#ff8c1e" }, { o: "#140808", W: "#ffd0d0", M: "#5a3c46", R: "#ff3c3c", Y: "#ff6a3c", y: "#c81e1e" }],
  hex: [{ o: "#0a3c64", C: "#5adcff", W: "#e6faff" }, { o: "#640a14", C: "#ff3c32", W: "#ffe0d0" }],
  shell: [{ Y: "#ffaa3c", W: "#fff0c8", O: "#c85a14" }, { Y: "#ff3c3c", W: "#ffd0c8", O: "#8c0a14" }],
  flake: [{ o: "#aadcff", W: "#ffffff" }, { o: "#ff8cb4", W: "#ffe8f0" }],
  icicle: [{ o: "#3c78b4", L: "#aadcff", W: "#ffffff" }, { o: "#8c1e46", L: "#ff8cb4", W: "#ffe8f0" }],
  shard: [{ o: "#3c78b4", L: "#aadcff", W: "#ffffff" }, { o: "#8c1e46", L: "#ff8cb4", W: "#ffe8f0" }],
  soul: [{ o: "#0a3c28", G: "#50ffa0", g: "#1e8c5a", W: "#e6fff0" }, { o: "#3c0a14", G: "#ff3c50", g: "#8c1428", W: "#ffe0e4" }],
  blade: [{ o: "#3c4660", W: "#e6ebf5" }, { o: "#5a0a1e", W: "#ffc8d0" }],
  chain: [{ o: "#2a2a34", L: "#9696a8" }, { o: "#3c0a14", L: "#c8505a" }],
  jelly: [{ o: "#2a6450", P: "#96f0c8", p: "#5ac8a0", W: "#f0fff8" }, { o: "#2a6450", P: "#96f0c8", p: "#5ac8a0", W: "#f0fff8" }],
  eye: [{ o: "#140a1e", W: "#fff6dc", R: "#e01e3c", k: "#14060a" }, { o: "#140a1e", W: "#fff6dc", R: "#e01e3c", k: "#14060a" }],
  tooth: [{ o: "#3c2a32", W: "#fff8ec" }, { o: "#3c2a32", W: "#fff8ec" }],
  goo: [{ k: "#0e0618", P: "#3c1e5a", G: "#c8ff3c", W: "#f8ffd0" }, { k: "#0e0618", P: "#3c1e5a", G: "#c8ff3c", W: "#f8ffd0" }],
  // ドラゴンの弾は、姿ごとに4色(通常・覚醒1 蒼炎・覚醒2 紫電・覚醒3 白金)
  flame: [{ o: "#7a1408", O: "#f0541e", Y: "#ffb428", W: "#fff4c8" }, { o: "#0a2a6a", O: "#1e78f0", Y: "#5ad2ff", W: "#f0fcff" }, { o: "#3c0a50", O: "#aa28a0", Y: "#ff5adc", W: "#ffe6fa" }, { o: "#a06414", O: "#ffc83c", Y: "#fff0aa", W: "#ffffff" }],
  slash: [{ o: "#7a1408", Y: "#ffb428", W: "#fff4c8" }, { o: "#0a2a6a", Y: "#5ad2ff", W: "#f0fcff" }, { o: "#3c0a50", Y: "#ff5adc", W: "#ffe6fa" }, { o: "#a06414", Y: "#ffdc64", W: "#ffffff" }],
  gust: [{ o: "#8c5a28", L: "#ffd28c", W: "#fff6dc" }, { o: "#14508c", L: "#8cdcff", W: "#f0fcff" }, { o: "#641478", L: "#f08cf0", W: "#fff0ff" }, { o: "#b4823c", L: "#fff0b4", W: "#ffffff" }],
  sun: [{ o: "#c83c14", Y: "#ffb428", W: "#fff4c8" }, { o: "#1450c8", Y: "#5ad2ff", W: "#f0fcff" }, { o: "#8c1e96", Y: "#ff5adc", W: "#ffe6fa" }, { o: "#dca028", Y: "#fff0aa", W: "#ffffff" }],
  rock: [{ o: "#3c1410", R: "#8c2a20", r: "#5a1a14", Y: "#ffb428" }, { o: "#0c0a24", R: "#3a3070", r: "#241c50", Y: "#5ad2ff" }, { o: "#1e0a32", R: "#501e78", r: "#32144e", Y: "#ff5adc" }, { o: "#a07828", R: "#fff0d2", r: "#d4bc96", Y: "#ffc83c" }],
  spine: [{ o: "#6a3c08", W: "#fff4c8", Y: "#ffc83c", y: "#c88214" }, { o: "#0a2a6a", W: "#ffffff", Y: "#78dcff", y: "#2890e6" }, { o: "#3c0a50", W: "#ffffff", Y: "#ff78e6", y: "#b432aa" }, { o: "#a06414", W: "#ffffff", Y: "#fff0aa", y: "#ffc83c" }],
  tornado: [{ o: "#b43c14", L: "#ff8c28", W: "#ffdc8c" }, { o: "#143c96", L: "#3c96ff", W: "#b4e6ff" }, { o: "#641478", L: "#c83cc8", W: "#ffb4fa" }, { o: "#c88c28", L: "#ffdc64", W: "#ffffff" }],
  pshot: [{ o: "#1e6edc", C: "#5adcff", W: "#ffffff" }, { o: "#1e6edc", C: "#5adcff", W: "#ffffff" }, { o: "#1e6edc", C: "#5adcff", W: "#ffffff" }, { o: "#1e6edc", C: "#5adcff", W: "#ffffff" }],
  ember: [{ o: "#e0541e", Y: "#ffb428", W: "#fff0b4" }, { o: "#1e78f0", Y: "#5ad2ff", W: "#f0fcff" }, { o: "#aa28a0", Y: "#ff5adc", W: "#ffe6fa" }, { o: "#ffc83c", Y: "#fff0aa", W: "#ffffff" }],
};
const ORIENT = new Set(["kingyo", "fox", "ofuda", "missile", "shell", "icicle", "shard", "soul", "chain", "tooth", "flame", "slash", "spine", "pshot"]);
const SPRITES = {};
function makeSprite(map, pal) {
  const h = map.length, w = map[0].length, c = document.createElement("canvas");
  c.width = w; c.height = h; const x = c.getContext("2d");
  for (let j = 0; j < h; j++) for (let i = 0; i < w; i++) { const ch = map[j][i]; if (pal[ch]) { x.fillStyle = pal[ch]; x.fillRect(i, j, 1, 1); } }
  return c;
}
for (const k in MAPS) SPRITES[k] = PALS[k].map(pal => makeSprite(MAPS[k], pal));
const RADIUS = { kingyo: 3, yoyo: 4, spark: 2.5, awa: 2.5, fox: 3, ofuda: 3, plankton: 2.5, bubble: 4, ink: 6, missile: 3, hex: 3, shell: 2, flake: 3, icicle: 3, shard: 2.5, soul: 3, blade: 3, chain: 2.5, jelly: 3.5, eye: 4, tooth: 2.5, goo: 2.5, flame: 3, slash: 4, gust: 4, sun: 5, rock: 4, spine: 2.5, tornado: 5, ember: 2, pshot: 2 };

// ---------- 状態 ----------
const G = { T: 0, bullets: [], lasers: [], marks: [], tasks: [], walls: [], hits: 0, inv: 0, dark: 0, banner: null,
  B: { x: 180, y: 128 }, P: { x: 180, y: 500 }, aw: false, lv: 0, boss: null, pat: null, anim: "idle", animT: 0, auto: true, target: null, manualUntil: 0,
  // ここから下は、ドラゴンの技で使う: ボス本体の移動、自機を流す風・引き寄せ、バインド(動けない)、範囲攻撃、即死
  Boff: { x: 0, y: 0 }, wind: { x: 0, y: 0 }, pull: null, bind: 0, zones: [], kills: 0, heat: 0,
  // 見た目だけの粒(火花・煙・火の粉)と、画面のゆれ・ボスの絵の差し替え(横向きに飛ぶ姿)
  fx: [], shake: 0, flashes: [], pose: null };

function pt(sx, sy) { const b = G.boss, w = b.w, h = b.h; return { x: G.B.x - w + sx * 2, y: G.B.y - h + sy * 2 }; }
function aimFrom(o) { return atan2(G.P.y - o.y, G.P.x - o.x); }
function fire(type, x, y, a, s, extra) {
  const b = Object.assign({ type, x, y, vx: cos(a) * s, vy: sin(a) * s, t: 0, r: RADIUS[type], ph: rand() * 9 }, extra || {});
  G.bullets.push(b); return b;
}
function rot(b, da) { const c = cos(da), s = sin(da), vx = b.vx * c - b.vy * s; b.vy = b.vx * s + b.vy * c; b.vx = vx; }
function steer(b, max) {
  const want = aimFrom(b), cur = atan2(b.vy, b.vx);
  let d = want - cur; while (d > PI) d -= TAU; while (d < -PI) d += TAU;
  rot(b, clamp(d, -max, max));
}
function angDiff(a, b) { let d = a - b; while (d > PI) d -= TAU; while (d < -PI) d += TAU; return Math.abs(d); }
function spawn(gen) { G.tasks.push({ g: gen, wait: 0 }); }
// ---------- 見た目だけの粒: k=0 火花(白 → 明るい色 → 濃い色)、1 煙、2 ゆっくりのぼる火の粉、3 風の筋 ----------
function spark(x, y, n, sp, o) {
  o = o || {};
  for (let i = 0; i < n && G.fx.length < 900; i++) {
    const a = o.a !== undefined ? o.a + (rand() - 0.5) * (o.spread === undefined ? 0.6 : o.spread) : rand() * TAU, v = sp * (0.3 + rand() * 0.9), j = o.jit || 0;
    G.fx.push({ x: x + (rand() - 0.5) * j, y: y + (rand() - 0.5) * j, vx: cos(a) * v, vy: sin(a) * v, t: 0, life: (o.life || 24) * (0.6 + rand() * 0.8), s: o.s || 2, g: o.g || 0, k: o.k || 0, drag: o.drag || 0.95 });
  }
}
function shake(n) { G.shake = Math.max(G.shake, n); }
function boom(x, y, r) {       // 大爆発: 火花・破片・煙・画面のゆれ・光の輪
  shake(Math.min(16, 4 + r / 12));
  spark(x, y, Math.min(90, r * 0.6 | 0), r / 8, { life: 36, s: 3, g: 0.04 });
  spark(x, y, 26, r / 14, { life: 60, s: 5, k: 1, g: -0.03, jit: r * 0.8 });
  spark(x, y, 30, r / 20, { life: 70, s: 2, k: 2, g: -0.02, jit: r });
  G.flashes.push({ x, y, r, t: 0, life: 30 });
}

// ---------- 技 ----------
const R = {};
// 九尾の巫女
// 尻尾の先の狐火(左下 → 上 → 右下の順)。新しい絵(元絵→ドット化)の位置
const KFIRES = [[24,71],[21,54],[26,36],[40,24],[72,21],[84,32],[91,42],[94,57],[89,73]];
const TIP = k => pt(KFIRES[k][0], KFIRES[k][1]);
const KROOT = () => pt(56, 51);
R.kitsuneLanterns = function* (aw) {
  for (let r = 0; r < (aw ? 2 : 1); r++) {
    const order = r % 2 ? [8, 7, 6, 5, 4, 3, 2, 1, 0] : [0, 1, 2, 3, 4, 5, 6, 7, 8];
    for (const k of order) { G.marks.push({ k: "tip", at: () => TIP(k), t: 0, life: 50 + 5 * 9 }); yield 5; }
    for (const k of order) {
      const o = TIP(k), a = aimFrom(o);
      for (const d of aw ? [-0.18, 0, 0.18] : [0]) fire("fox", o.x, o.y, a + d, aw ? 3.8 : 3.2);
      yield 5;
    }
    yield 20;
  }
};
R.kitsuneBarrier = function* (aw) {
  for (let v = 0; v < 3; v++) {
    const o = KROOT(), n = aw ? 18 : 12;
    for (let i = 0; i < n; i++) {
      const s = i % 2 ? 1 : -1;
      fire("ofuda", o.x, o.y, v * 0.26 + i * TAU / n, 2, { u: b => {
        if (b.t === 36) { rot(b, s * PI / 2); b.vx *= 1.2; b.vy *= 1.2; }
        if (aw && b.t === 72) rot(b, -s * PI / 2);
      } });
    }
    yield 40;
  }
  yield 30;
};
R.kitsuneSunshower = function* (aw) {
  for (let t = 0; t < 150; t++) {
    if (t % (aw ? 2 : 4) === 0) fire("fox", rand() * W, -8, PI / 2, aw ? 2.8 : 2.2, { u: b => { b.vx = sin((b.t + b.ph * 20) * 0.04) * 0.8; } });
    if (t % 30 === 0) { const o = KROOT(), a = aimFrom(o); for (const d of [-0.2, 0, 0.2]) fire("ofuda", o.x, o.y, a + d, 2.6); }
    yield 1;
  }
};
R.kitsuneTorii = function* (aw) {
  let gx = 180;
  for (let row = 0; row < 8; row++) {
    gx = clamp(gx + (rand() < 0.5 ? -1 : 1) * (30 + rand() * 30), 50, 310);
    const gap = aw ? 48 : 60, y0 = KROOT().y, wall = { gx, ref: null, sway: aw };
    for (let x = 8; x < W; x += 16) {
      if (Math.abs(x - gx) < gap / 2) continue;
      const b = fire("ofuda", x, y0, PI / 2, 1.4, aw ? { u: b => { b.vx = sin(b.t * 0.05 + row) * 0.6; } } : {});
      if (!wall.ref) { wall.ref = b; b.x0 = b.x; }
    }
    G.walls.push(wall);
    yield 26;
  }
  yield 60;
};
R.kitsuneDance = function* (aw) {
  for (let t = 0; t < 120; t++) {
    if (t % (aw ? 5 : 4) === 0) for (let k = 0; k < 9; k++) {
      const o = TIP(k), base = PI / 2 + (k - 4) * 0.28;
      fire("fox", o.x, o.y, base + sin(t * 0.05 + k) * 0.5, aw ? 2.6 : 2.2);
      if (aw) fire("fox", o.x, o.y, base - sin(t * 0.05 + k) * 0.5, 2.6);
    }
    yield 1;
  }
};
// 深海の魔女
// 触手の先(新しい絵の位置)。TENT は付け根から見た向き(度)
const WTIPS = [[93,67],[88,76],[76,89],[64,93],[50,93],[40,87],[23,80],[27,64]];
const TENT = WTIPS.map(([x, y]) => atan2(y - 63, x - 56) * 180 / PI);
const tentTip = j => pt(WTIPS[j][0], WTIPS[j][1]);
R.witchAbyss = function* (aw) {
  G.dark = 150 + 80;
  const n = aw ? 9 : 7;
  for (let t = 0; t < 150; t++) {
    if (t % 8 === 0) for (let c = 0; c < n; c++) {
      const x0 = (c + 0.5) * W / n;
      fire("plankton", x0, -6, PI / 2, aw ? 2.2 : 1.8, { ox: x0, cph: c, u: b => { b.x = b.ox + sin(b.t * 0.06 + b.cph) * 14; } });
    }
    if (aw && t % 40 === 0) { const l = pt(77, 29); fire("bubble", l.x, l.y, aimFrom(l), 1.6, { r: 5 }); }
    yield 1;
  }
};
R.witchBubbles = function* (aw) {
  for (let v = 0; v < 4; v++) {
    for (let j = 0; j < (aw ? 8 : 4); j++) {
      const tp = tentTip(aw ? j : (j * 2 + v) % 8);
      fire("bubble", tp.x, tp.y, PI / 2 + (rand() - 0.5) * 1.2, 1.2, { r: 3, u: b => {
        b.r = Math.min(10, 3 + b.t * 0.09); b.vx *= 0.995; b.vy *= 0.995;
        if (b.t === 90) { b.dead = 1; const m = aw ? 10 : 6, a0 = rand() * TAU; for (let i = 0; i < m; i++) fire("plankton", b.x, b.y, a0 + i * TAU / m, 1.8); }
      } });
    }
    yield 45;
  }
  yield 50;
};
R.witchTentacles = function* (aw) {
  for (let t = 0; t < 90; t++) {
    if (t % 3 === 0) for (let j = 0; j < 8; j++) {
      const tp = tentTip(j), a = TENT[j] * PI / 180 + (aw ? sin(t * 0.03) * 0.4 : 0), amp = aw ? 18 : 12;
      fire("plankton", tp.x, tp.y, 0, 0, { ox: tp.x, oy: tp.y, a, amp, u: b => {
        const d = b.t * 2, lat = sin(b.t * 0.1 + j) * b.amp;
        b.x = b.ox + cos(b.a) * d - sin(b.a) * lat; b.y = b.oy + sin(b.a) * d + cos(b.a) * lat;
      } });
    }
    yield 1;
  }
  yield 30;
};
R.witchMaelstrom = function* (aw) {
  const n = aw ? 7 : 5;
  for (let t = 0; t < 120; t++) {
    if (t % 4 === 0) { const o = pt(56, 63); for (let a = 0; a < n; a++) {
      const dir = aw && a % 2 ? -1 : 1;
      fire("plankton", o.x, o.y, a * TAU / n + t * 0.02 * dir, 1.9, { u: b => rot(b, 0.012 * dir) });
    } }
    yield 1;
  }
  yield 30;
};
R.witchInk = function* (aw) {
  for (let v = 0; v < 3; v++) {
    for (const x of v % 2 ? [90, 270] : [45, 180, 315]) {
      fire("ink", x, -10, PI / 2, 1.0, { u: b => {
        if (b.y > (aw ? 260 : 300)) { b.dead = 1; const m = aw ? 12 : 8, a0 = aimFrom(b); for (let i = 0; i < m; i++) fire("plankton", b.x, b.y, a0 + i * TAU / m, 2); }
      } });
    }
    yield 50;
  }
  yield 120;
};
// 機神
const EYE = () => pt(56, 49), CANL = () => pt(25, 46), CANR = () => pt(86, 46);
R.mechLockOn = function* (aw) {
  for (let rep = 0; rep < 2; rep++) {
    const ret = { k: "ret", x: G.P.x, y: G.P.y, t: 0, life: 9999 }; G.marks.push(ret);
    for (let t = 0; t < 60; t++) { ret.x += (G.P.x - ret.x) * 0.12; ret.y += (G.P.y - ret.y) * 0.12; yield 1; }
    ret.lock = 1; yield 14;
    const e = EYE();
    G.lasers.push({ from: EYE, a: atan2(ret.y - e.y, ret.x - e.x), len: 900, w: aw ? 34 : 26, warn: 0, dur: 40, t: 0, va: 0, col: ["#5adcff", "#e6faff"] });
    ret.dead = 1;
    for (let i = 0; i < (aw ? 4 : 2); i++) {
      const c = i % 2 ? CANR() : CANL();
      fire("missile", c.x, c.y, -PI / 2 + (i % 2 ? 0.7 : -0.7) * (1 + (i >> 1) * 0.4), 2.6, { u: b => { if (b.t < 90) steer(b, 0.04); } });
    }
    yield 50;
  }
};
R.mechMissiles = function* (aw) {
  const n = aw ? 20 : 12;
  for (let i = 0; i < n; i++) {
    const c = i % 2 ? CANR() : CANL();
    fire("missile", c.x, c.y, -PI / 2 + (i % 2 ? 1 : -1) * (0.3 + rand() * 0.9), 3, { u: b => {
      if (b.t < 25) { b.vx *= 0.95; b.vy *= 0.95; }
      else if (b.t < 85) { steer(b, 0.06); const s = hypot(b.vx, b.vy), ns = Math.min(3.4, s + 0.08); b.vx *= ns / s; b.vy *= ns / s; }
    } });
    yield aw ? 3 : 5;
  }
  yield 60;
};
R.mechGatling = function* (aw) {
  for (let t = 0; t < 90; t++) {
    if (t % 3 === 0) {
      const f = t / 90;
      for (const side of [0, 1]) {
        const c = side ? CANR() : CANL(), a = side ? PI * 5 / 6 - f * PI * 2 / 3 : PI / 6 + f * PI * 2 / 3;
        for (const d of aw ? [-0.1, 0.1] : [0]) fire("shell", c.x, c.y, a + d, 3.4);
      }
    }
    yield 1;
  }
  yield 20;
};
let gridDir = 1;
R.mechGrid = function* (aw) {
  const n = aw ? 8 : 6, a0 = rand() * TAU; gridDir *= -1;
  for (let i = 0; i < n; i++) G.lasers.push({ from: EYE, a: a0 + i * TAU / n, len: 900, w: 10, warn: 50, dur: 70, t: 0, va: (aw ? 0.01 : 0.006) * gridDir, col: ["#5adcff", "#e6faff"] });
  for (let t = 0; t < 120; t++) { if (t % 24 === 0) { const e = EYE(); fire("hex", e.x, e.y, aimFrom(e), 2.4); } yield 1; }
};
R.mechOverload = function* (aw) {
  for (let v = 0; v < (aw ? 7 : 5); v++) {
    const e = EYE(), n = aw ? 32 : 24, gapA = aimFrom(e) + (v % 2 ? 0.5 : -0.5);
    for (let i = 0; i < n; i++) {
      const a = i * TAU / n + v * 0.13;
      if (angDiff(a, gapA) < (TAU / n) * 1.6) continue;
      fire("hex", e.x, e.y, a, 1.2, { u: b => { const s = hypot(b.vx, b.vy); if (s < 3.5) { const k = 1.025; b.vx *= k; b.vy *= k; } } });
    }
    yield 18;
  }
  yield 50;
};
// 雪の女王
const CRYS = () => pt(56, 48);
function splitter(b) {
  if (b.t === 30 && b.lv > 0) {
    b.dead = 1; const a = atan2(b.vy, b.vx), s = hypot(b.vx, b.vy);
    for (const d of [-0.5, 0.5]) fire(b.lv - 1 === 0 ? "flake" : "shard", b.x, b.y, a + d, s, { lv: b.lv - 1, u: splitter });
  }
}
R.iceCage = function* (aw) {
  for (let v = 0; v < 4; v++) {
    const c = CRYS();
    for (let i = 0; i < 6; i++) fire("shard", c.x, c.y, PI / 2 + i * PI / 3 + v * 0.17, 2, { lv: 2, u: splitter });
    if (aw) for (let i = 0; i < 6; i++) fire("shard", c.x, c.y, PI / 2 + PI / 6 + i * PI / 3 - v * 0.17, 2, { lv: 2, u: splitter });
    yield 50;
  }
  yield 40;
};
R.iceIcicles = function* (aw) {
  for (let w = 0; w < 5; w++) {
    const xs = []; for (let i = 0; i < (aw ? 9 : 6); i++) xs.push(16 + rand() * 328);
    xs.forEach(x => G.marks.push({ k: "glint", x, y: 10, t: 0, life: 30 }));
    yield 30;
    xs.forEach(x => fire("icicle", x, -6, PI / 2, 0.5, { u: b => { b.vy += aw ? 0.12 : 0.08; } }));
    yield 20;
  }
  yield 40;
};
let wind = 1;
R.iceBlizzard = function* (aw) {
  for (let t = 0; t < 200; t++) {
    if (t % 120 === 0) wind *= -1;
    if (t % (aw ? 2 : 3) === 0) {
      const side = rand() < 0.3, x = side ? (wind > 0 ? -6 : W + 6) : rand() * W, y = side ? rand() * 300 : -6;
      const b = fire("flake", x, y, 0, 0, { u: b => { b.vx += (wind * 1.2 - b.vx) * 0.03; b.vy = 1.6 + sin(b.t * 0.05 + b.ph) * 0.3; } });
      b.vx = wind * 1.2;
    }
    yield 1;
  }
};
R.iceFreeze = function* (aw) {
  for (let r = 0; r < 3; r++) {
    const c = CRYS(), n = aw ? 28 : 20;
    for (let i = 0; i < n; i++) fire("shard", c.x, c.y, i * TAU / n + r * 0.1, 2.5, { u: b => {
      if (b.t === 40) { b.vx = 0; b.vy = 0; b.type = "flake"; }
      if (b.t === 80) { b.dead = 1; for (let j = 0; j < 3; j++) fire("shard", b.x, b.y, aw ? aimFrom(b) + (j - 1) * 0.35 : rand() * TAU, 1.6); }
    } });
    yield 30;
  }
  yield 60;
};
R.iceMirror = function* (aw) {
  for (let v = 0; v < 6; v++) {
    const c = CRYS(), n = aw ? 7 : 5, a0 = aimFrom(c);
    for (let i = 0; i < n; i++) fire("shard", c.x, c.y, a0 + (i - (n - 1) / 2) * 0.22, 3, { bounce: 2, u: b => {
      if ((b.x < 4 && b.vx < 0) || (b.x > W - 4 && b.vx > 0)) { if (b.bounce > 0) { b.vx *= -1; b.bounce--; } }
    } });
    yield 20;
  }
  yield 30;
};
// 死神
const SKULL = () => pt(66, 30);
R.reaperScythe = function* (aw) {
  const placed = [];
  for (const [ri, R0] of (aw ? [150, 215] : [150]).entries()) {
    const cx = G.B.x, cy = G.B.y + 20, a0 = 160 * PI / 180, a1 = 20 * PI / 180;
    const n = Math.floor(R0 * (a0 - a1) / 13);
    const gaps = aw ? [Math.floor(n * (0.2 + rand() * 0.25)), Math.floor(n * (0.55 + rand() * 0.25))] : [];
    for (let i = 0; i <= n; i++) {
      if (gaps.some(g => i >= g && i < g + 4)) continue;
      const a = a0 - (a0 - a1) * i / n;
      placed.push(fire("blade", cx + cos(a) * R0, cy + sin(a) * R0, 0, 0, { spin: 1, u: b => { if (b.fall) b.vy = Math.min(b.vy + 0.06, 4); } }));
      if (i % 2) yield 1;
    }
  }
  const s = SKULL(); for (const d of [-0.5, 0.5]) fire("soul", s.x, s.y, aimFrom(s) + d, 1.2, { u: b => { if (b.t < 150) steer(b, 0.02); } });
  yield 30;
  placed.forEach(b => { b.fall = 1; b.vx = (rand() - 0.5) * 0.6; b.vy = 0.5; });
  yield 90;
};
R.reaperSouls = function* (aw) {
  const n = aw ? 16 : 10;
  for (let i = 0; i < n; i++) fire("soul", 0, 0, 0, 0, { a0: i * TAU / n, u: b => {
    if (b.t < 40) { const c = SKULL(), r = 10 + b.t * 1.2, a = b.a0 + b.t * 0.05; b.x = c.x + cos(a) * r; b.y = c.y + sin(a) * r; b.vx = 0; b.vy = 0; b.face = a + PI / 2; }
    else if (b.t === 40) { const a = aimFrom(b); b.vx = cos(a) * 1.4; b.vy = sin(a) * 1.4; b.face = undefined; }
    else if (b.t < 160) steer(b, 0.025);
  } });
  yield 200;
};
function* chain(o, tx, ty) {
  G.marks.push({ k: "line", x1: o.x, y1: o.y, x2: tx, y2: ty, t: 0, life: 20 });
  yield 20;
  const a = atan2(ty - o.y, tx - o.x);
  for (let d = 0; d < 760; d += 8) {
    const x = o.x + cos(a) * d, y = o.y + sin(a) * d;
    if (x < -10 || x > W + 10 || y > H + 10) break;
    fire("chain", x, y, 0, 0, { face: a + PI / 2, life: 60 });
    yield 2;
  }
}
R.reaperChains = function* (aw) {
  for (let v = 0; v < 3; v++) {
    const os = [{ x: 0, y: 0 }, { x: W, y: 0 }, { x: W / 2, y: -4 }, { x: 0, y: 220 }, { x: W, y: 220 }].slice(0, aw ? 5 : 3);
    const tx = G.P.x, ty = G.P.y;
    os.forEach(o => spawn(chain(o, tx, ty)));
    yield 70;
  }
  yield 60;
};
R.reaperDeadline = function* (aw) {
  let gx = 180;
  for (let row = 0; row < (aw ? 6 : 4); row++) {
    gx = clamp(gx + (rand() < 0.5 ? -1 : 1) * (40 + rand() * 40), 50, 310);
    const gap = aw ? 48 : 56;
    const wall = { gx, ref: null };
    for (let x = 10; x < W; x += 14) { if (Math.abs(x - gx) < gap / 2) continue; const b = fire("blade", x, 150, PI / 2, 0.8, { spin: 1 }); if (!wall.ref) { wall.ref = b; b.x0 = b.x; } }
    G.walls.push(wall);
    for (let t = 0; t < (aw ? 50 : 70); t++) { if (t % 30 === 0) { const s = SKULL(); fire("soul", s.x, s.y, aimFrom(s), 2); } yield 1; }
  }
  yield 120;
};
R.reaperRiver = function* (aw) {
  const lanes = [330, 380, 430, 480, 530];
  for (let t = 0; t < 180; t++) {
    if (t % (aw ? 8 : 10) === 0) {
      const idx = Math.floor(t / (aw ? 8 : 10));
      lanes.forEach((y, i) => {
        if ((idx + i * 3) % 7 < 2) return;
        const dir = i % 2 ? -1 : 1;
        fire("soul", dir > 0 ? -6 : W + 6, y, dir > 0 ? 0 : PI, aw ? 3 : 2.4, aw ? { oy: y, u: b => { b.y = b.oy + sin(b.t * 0.05) * 12; } } : {});
      });
    }
    yield 1;
  }
  yield 60;
};
// 金魚姫(金魚すくいの金魚娘)
const POI = () => pt(39, 33), FISHHAND = () => pt(73, 42), HCHEST = () => pt(56, 51);
R.hireSukui = function* (aw) {
  for (let v = 0; v < (aw ? 4 : 3); v++) {
    const o = FISHHAND(), a0 = aimFrom(o), n = aw ? 12 : 8;
    for (let i = 0; i < n; i++) fire("kingyo", o.x, o.y, a0 + (i - (n - 1) / 2) * 0.16, 2, { u: b => { rot(b, sin(b.t * 0.15 + b.ph) * 0.05); if (b.t < 60) steer(b, aw ? 0.022 : 0.015); } });
    yield 40;
  }
  yield 40;
};
R.hireYoyo = function* (aw) {
  const n = aw ? 9 : 6;
  for (let i = 0; i < n; i++) {
    const x = 20 + (i + 0.5) * (W - 40) / n + (rand() - 0.5) * 10;
    fire("yoyo", x, -8, PI / 2, 0, { u: b => {
      if (b.t <= 45) b.vy = 2.6 * (1 - b.t / 45) + 0.2; else if (b.t <= 60) b.vy = 0; else b.vy = -1.5;
      if (b.t === 100) { b.dead = 1; const m = aw ? 12 : 8, a0 = aw ? aimFrom(b) : rand() * TAU; for (let k = 0; k < m; k++) fire("awa", b.x, b.y, a0 + k * TAU / m, 1.6); }
    } });
    yield 8;
  }
  yield 120;
};
R.hireHanabi = function* (aw) {
  for (let v = 0; v < (aw ? 6 : 4); v++) {
    const o = POI(), tx = 40 + rand() * 280, ty = 60 + rand() * 140, a = atan2(ty - o.y, tx - o.x);
    fire("spark", o.x, o.y, a, 4, { big: 2, u: b => {
      b.vx *= 0.95; b.vy *= 0.95;
      if (b.t === 35) { b.dead = 1; const m = aw ? 24 : 18; for (let k = 0; k < m; k++) fire("spark", b.x, b.y, k * TAU / m, 1.6, { u: c => { c.vy += 0.025; c.vx *= 0.995; } }); }
    } });
    yield 26;
  }
  yield 120;
};
R.hireRipple = function* (aw) {
  for (let v = 0; v < 4; v++) {
    const pts = [];
    for (let k = 0; k < (aw ? 2 : 1); k++) {
      const a = rand() * TAU, d = 70 + rand() * 60;
      pts.push({ x: clamp(G.P.x + cos(a) * d, 16, W - 16), y: clamp(G.P.y + sin(a) * d, 240, H - 16) });
    }
    pts.forEach(q => G.marks.push({ k: "ripple", x: q.x, y: q.y, t: 0, life: 30 }));
    yield 30;
    pts.forEach(q => { const m = aw ? 20 : 14; for (let i = 0; i < m; i++) fire("awa", q.x, q.y, i * TAU / m, 1.4); });
    yield 15;
  }
  yield 60;
};
R.hireKaiyu = function* (aw) {
  const cx = G.P.x, cy = G.P.y, gapAt = rand() * TAU;
  for (const [ri, dir] of (aw ? [[0, 1], [1, -1]] : [[0, 1]])) {
    const n = 20, R0 = 150 + ri * 40;
    for (let i = 0; i < n; i++) {
      const a0 = i * TAU / n;
      if (angDiff(a0, gapAt + ri * PI) < TAU / n * 1.6) continue;
      fire("kingyo", cx + cos(a0) * R0, cy + sin(a0) * R0, 0, 0, { u: b => {
        if (b.t < 100) {
          const a = a0 + b.t * 0.02 * dir, r = R0 - b.t * (R0 - 60 - ri * 30) / 100;
          b.x = cx + cos(a) * r; b.y = cy + sin(a) * r; b.vx = 0; b.vy = 0; b.face = a + (dir > 0 ? PI : 0);
        } else if (b.t === 100) { const a = atan2(b.y - cy, b.x - cx); b.vx = cos(a) * 2; b.vy = sin(a) * 2; b.face = undefined; }
      } });
    }
  }
  yield 170;
};

// ぷにまる(覚醒すると、同じ枠の技が別物になる)
const PUNI = () => G.aw ? pt(68, 56) : pt(66, 88);
const EYES = (() => { let s = 7; const r = () => (s = (s * 1103515245 + 12345) % 2147483648) / 2147483648; const a = []; for (let i = 0; i < 22; i++) { const t = r() * TAU, d = 8 + r() * 26; a.push([68 + cos(t) * d * 1.1, 56 + sin(t) * d * 0.8]); } return a; })();
R.puniPoyon = function* (aw) {
  if (!aw) { for (let i = 0; i < 6; i++) { const c = PUNI(); fire("jelly", c.x, c.y + 8, PI / 2, 1.0); yield 60; } return; }
  for (let r = 0; r < 2; r++) for (let i = 0; i < 22; i++) { const e = pt(EYES[i][0], EYES[i][1]); fire("eye", e.x, e.y, aimFrom(e), 3); yield 4; }
  yield 40;
};
R.puniShower = function* (aw) {
  if (!aw) { for (let v = 0; v < 4; v++) { const c = PUNI(); for (const d of [-0.3, 0, 0.3]) fire("jelly", c.x, c.y + 6, PI / 2 + d, 1.2); yield 50; } yield 40; return; }
  for (let t = 0; t < 150; t++) {
    if (t % 4 === 0) { const c = PUNI(); for (let a = 0; a < 12; a++) fire("goo", c.x, c.y, a * PI / 6 + t * 0.03, 2, { u: b => rot(b, 0.01) }); }
    yield 1;
  }
};
R.puniKorokoro = function* (aw) {
  if (!aw) { for (let v = 0; v < 3; v++) { const c = PUNI(); for (const s of [-1, 1]) fire("jelly", c.x, c.y, -PI / 2 + s * 0.6, 2, { u: b => { b.vy += 0.05; } }); yield 50; } yield 60; return; }
  for (let v = 0; v < 5; v++) { const c = PUNI(); for (let i = 0; i < 24; i++) fire("tooth", c.x, c.y, i * TAU / 24 + v * 0.13, 1.6, { u: b => rot(b, (v % 2 ? 1 : -1) * 0.008) }); yield 25; }
  yield 60;
};
R.puniPurupuru = function* (aw) {
  if (!aw) { for (let v = 0; v < 2; v++) { const c = PUNI(); for (let i = 0; i < 8; i++) fire("jelly", c.x, c.y, i * PI / 4 + v * 0.4, 1.0); yield 60; } yield 60; return; }
  const cols = [["#3cf0ff", "#e6ffff"], ["#ff3cc8", "#ffe0f6"]];
  for (let i = 0; i < 4; i++) G.lasers.push({ from: PUNI, a: i * PI / 2 + PI / 4, len: 900, w: 9, warn: 40, dur: 150, t: 0, va: (i % 2 ? 1 : -1) * 0.008, col: cols[i % 2] });
  for (let t = 0; t < 190; t++) { if (t % 20 === 0) { const c = PUNI(); fire("goo", c.x, c.y, aimFrom(c), 2.2); } yield 1; }
};
R.puniOsusowake = function* (aw) {
  if (!aw) {
    for (let v = 0; v < 2; v++) { const c = PUNI(); fire("jelly", c.x, c.y + 6, PI / 2, 0.9, { big: 2, r: 7, u: b => { if (b.y > 320) { b.dead = 1; for (const d of [-0.5, 0, 0.5]) fire("jelly", b.x, b.y, PI / 2 + d, 1.4); } } }); yield 100; }
    yield 40; return;
  }
  for (let t = 0; t < 300; t++) {
    if (t % 40 === 0) { const c = PUNI(); for (let i = 0; i < 16; i++) fire("eye", c.x, c.y, i * TAU / 16 + t * 0.01, 1.5); }
    if (t % 75 === 37) {
      const live = G.bullets.filter(b => b.type === "eye" && !b.dead && b.y < 400).sort(() => rand() - 0.5).slice(0, 6);
      live.forEach(b => {
        const a = rand() * TAU, d = 50 + rand() * 30, tx = clamp(G.P.x + cos(a) * d, 8, W - 8), ty = clamp(G.P.y + sin(a) * d, 8, H - 8);
        G.marks.push({ k: "warp", x: tx, y: ty, t: 0, life: 30 });
        spawn((function* () { yield 30; if (!b.dead) { b.x = tx; b.y = ty; } })());
      });
    }
    yield 1;
  }
};

// ---------- 最強のドラゴン(絵は 240×200。口・胸・両手・翼の先・尻尾の先) ----------
// ほかのボスと違い、小さい弾は少なめで、大きい弾・範囲攻撃・本体の体当たりが中心。
// 範囲攻撃は G.zones に入れる: {shape: "rect"|"circle"|"safe", warn: 予告のフレーム, dur: 当たるフレーム, bind: 当たると動けなくなるフレーム, kill: 当たると即死}
const DMOUTH = () => pt(131, 86), DCHEST = () => pt(120, 94), DHAND = i => i ? pt(158, 108) : pt(80, 108), DWING = i => i ? pt(206, 112) : pt(34, 112), DTAIL = () => pt(103, 168);
function zone(z) { z.t = 0; G.zones.push(z); return z; }
function* glideTo(x, y, n) {        // ボス本体を、n フレームかけて (x, y) へ動かす(なめらかに)
  const x0 = G.Boff.x, y0 = G.Boff.y;
  for (let i = 1; i <= n; i++) { const t = i / n, e = t * t * (3 - 2 * t); G.Boff.x = x0 + (x - x0) * e; G.Boff.y = y0 + (y - y0) * e; yield 1; }
}
function bodyHit(frames, r) {       // ボス本体の当たり判定(見えない弾を体に重ねる)
  fire("body", G.B.x, G.B.y, 0, 0, { r: r || 40, life: frames, u: b => { b.x = G.B.x; b.y = G.B.y + 10; } });
}
R.dragonBreath = function* (aw, lv) {
  // 口から極太の炎の柱。ゆっくり自機を追う。通った跡に火柱が残る。
  // 柱は「自機に近い壁の側」から出て、広い側へ追い立てる(壁に追い詰めない)。追う速さは自機より遅い
  const o = DMOUTH();
  const L = { from: DMOUTH, a: aimFrom(o) + (G.P.x < W / 2 ? 0.45 : -0.45), len: 900, w: aw ? 96 + lv * 8 : 80, warn: 44, dur: aw ? 150 : 170, t: 0, va: 0, track: aw ? 0.0046 : 0.0042, fire: 1, col: ["#f0541e", "#ffdc8c"] };
  G.lasers.push(L);
  for (let t = 0; t < 214; t++) {
    if (t > 50 && t % (aw ? 11 : 13) === 0) {
      const m = DMOUTH(), d = 150 + rand() * 380, x = m.x + cos(L.a) * d + (rand() - 0.5) * 30, y = m.y + sin(L.a) * d;
      if (y < H - 10 && x > 10 && x < W - 10) fire("flame", x, y, -PI / 2, 0.15, { big: 2.6, r: 8, life: 110 });
    }
    yield 1;
  }
  yield 30;
};
R.dragonRaid = function* (aw, lv) {
  // 本体が自機めがけて飛んできて、左右の爪で2回ひっかく。体も爪も当たる。爪の跡は大きな斬撃になって飛ぶ
  for (let rep = 0; rep < (aw ? 3 : 2); rep++) {
    const tx = clamp(G.P.x, 70, W - 70), ty = clamp(G.P.y - 95, 150, 420);
    G.marks.push({ k: "target", x: tx, y: ty + 95, t: 0, life: 34 });
    // 爪が届く範囲は、飛んでくる間に予告する(右の爪 → 左の爪)
    zone({ shape: "circle", x: tx + 30, y: ty + 62, r: 68, warn: 40, dur: 8, col: "#fff4c8", claw: 1 });
    zone({ shape: "circle", x: tx - 30, y: ty + 62, r: 68, warn: 60, dur: 8, col: "#fff4c8", claw: 1 });
    yield 10;
    bodyHit(90, 44);
    yield* glideTo(tx - 180, ty - 128, 24);
    for (const side of [1, 0]) {
      yield 6;
      const h = DHAND(side), dir = side ? -1 : 1, n = aw ? 5 : 3;
      for (let k = 0; k < n; k++) fire("slash", h.x, h.y, PI / 2 + dir * (0.25 + k * 0.28), 4.4 + k * 0.3, { big: 3, r: 10, face: PI / 2 + dir * (0.25 + k * 0.28) + PI / 2 });
      yield 14;
    }
    yield* glideTo(0, 0, 30);
    yield 10;
  }
  yield 30;
};
R.dragonGale = function* (aw, lv) {
  // 羽ばたきの暴風で、自機が横へ流される。風に乗って、大きな風の刃が横から飛んでくる。風向きは羽ばたきごとに変わる
  let dir = rand() < 0.5 ? 1 : -1;
  for (let v = 0; v < (aw ? 6 : 4); v++) {
    dir = aw ? (rand() < 0.5 ? 1 : -1) : -dir;
    G.marks.push({ k: "wind", dir, t: 0, life: 26 });
    yield 26;
    G.wind = { x: dir * (aw ? 2.0 : 1.6), y: 0.5 };
    for (let k = 0; k < (aw ? 5 : 3); k++) {
      fire("gust", dir > 0 ? -20 : W + 20, 240 + rand() * 320, dir > 0 ? 0 : PI, 3.6 + rand(), { big: 3.2, r: 11, face: dir > 0 ? PI / 2 : -PI / 2 });
      yield 12;
    }
    for (const side of [0, 1]) { const o = DWING(side); fire("gust", o.x, o.y, aimFrom(o), 3.2, { big: 2.6, r: 9, face: aimFrom(o) + PI / 2 }); }
    yield 14;
    G.wind = { x: 0, y: 0 };
  }
  yield 40;
};
R.dragonInhale = function* (aw, lv) {
  // 息を吸い込む: 自機も火の粉も口へ引き寄せられる。自機の撃った弾も吸い込まれて食べられる(ボスに届かない)。
  // 吸い終わると、超巨大な火球を吐く。落ちた所で、画面の半分を焼く大爆発。そのあと、食べた自機の弾を撃ち返してくる(食べた数だけ)
  G.pull = { at: DMOUTH, f: aw ? 0.95 : 0.75 };
  let eaten = 0;
  for (let t = 0; t < 130; t++) {
    if (t % 5 === 0) fire("pshot", G.P.x, G.P.y - 12, -PI / 2, 6, { friendly: 1, u: b => {      // 自機の弾(試射場では、この技の間だけ撃つ)
      const m = DMOUTH(), a = atan2(m.y - b.y, m.x - b.x); b.vx += (cos(a) * 6 - b.vx) * 0.08; b.vy += (sin(a) * 6 - b.vy) * 0.08;
      if (hypot(m.x - b.x, m.y - b.y) < 16) { b.dead = 1; eaten++; }
    } });
    if (t % 10 === 0) {
      const side = rand(), x = side < 0.5 ? -6 : W + 6, y = 240 + rand() * 200;
      fire("ember", x, y, 0, 0, { big: 1.6, r: 3, u: b => { const m = DMOUTH(), a = atan2(m.y - b.y, m.x - b.x), sp = Math.min(5, 1.2 + b.t * 0.05); b.vx = cos(a) * sp; b.vy = sin(a) * sp; if (hypot(m.x - b.x, m.y - b.y) < 14) b.dead = 1; } });
    }
    yield 1;
  }
  G.pull = null;
  for (let n = 0; n < (aw ? 2 : 1); n++) {
    const m = DMOUTH(), tx = clamp(G.P.x, 60, W - 60), ty = clamp(G.P.y, 330, 520), Rr = aw ? 160 : 150, fl = aw ? 64 : 60;
    zone({ shape: "circle", x: tx, y: ty, r: Rr, warn: fl, dur: 26, col: "#ff8c28", boom: 1 });
    fire("sun", m.x, m.y, 0, 0, { big: 5, r: 26, life: fl, u: b => { const t = b.t / fl; b.x = m.x + (tx - m.x) * t; b.y = m.y + (ty - m.y) * t * t; } });
    yield fl + 40;
  }
  // 食べた弾を撃ち返す: 自機の弾と同じ見た目で、扇になって降ってくる
  const back = Math.min(eaten, aw ? 36 : 24);
  for (let i = 0; i < back; i++) {
    const m = DMOUTH(); fire("pshot", m.x, m.y, aimFrom(m) + sin(i * 0.9) * 0.5, 4.2, { big: 1.6, r: 3 });
    yield 3;
  }
  yield 40;
};
R.dragonGlide = function* (aw, lv) {
  // 画面の外へ飛び去り、横向きの姿で、自機の高さを右へ左へ突っ切る(体に当たるとダメージ)。通る帯は影で予告する。
  // 飛びながら下へ大きな火の玉を落とすので、帯の下にも長居できない
  yield* glideTo(0, -340, 26);
  for (let pass = 0; pass < (aw ? 4 : 3); pass++) {
    const dir = pass % 2 ? -1 : 1, hh = aw ? 120 : 100, y0 = clamp(G.P.y - hh / 2, 250, H - hh - 60);
    zone({ shape: "rect", x: 0, y: y0, w: W, h: hh, warn: 50, dur: 36, col: "#ff8c28", shadow: 1, fly: dir });
    yield 50;
    G.pose = dir > 0 ? "side_fly_r" : "side_fly_l";
    for (let i = 0; i < 36; i++) {
      const x = dir > 0 ? -260 + i * (W + 520) / 36 : W + 260 - i * (W + 520) / 36;
      G.Boff.x = x - 180 + dir * 20; G.Boff.y = y0 + hh / 2 - 24 - 128;
      if (i % (aw ? 3 : 4) === 0 && x > 10 && x < W - 10) fire("flame", x, y0 + hh / 2 + 16, PI / 2 + (rand() - 0.5) * 0.3, 1.6 + rand(), { big: 2.4, r: 8, life: 90 });
      yield 1;
    }
    G.pose = null; G.Boff.x = 0; G.Boff.y = -340;
    yield aw ? 10 : 18;
  }
  yield* glideTo(0, 0, 30);
  yield 20;
};
R.dragonRoar = function* (aw, lv) {
  // 咆哮の衝撃波が輪になって広がる。当たるとダメージに加えて、しばらく動けなくなる(バインド)。動けない所へ、自機狙いの大火球
  for (let v = 0; v < (aw ? 5 : 3); v++) {
    const m = DMOUTH(), gapA = aimFrom(m) + (rand() < 0.5 ? 1 : -1) * (0.3 + rand() * 0.25);
    zone({ shape: "ring", at: DMOUTH, x: m.x, y: m.y, r: 10, vr: aw ? 3.0 : 2.6, th: 16, gapA, gapW: aw ? 0.48 : 0.55, warn: 0, dur: 200, bind: 80, col: "#ffdc8c" });
    yield 34;
    if (v % 2 === 1 || aw) { const o = DMOUTH(); fire("sun", o.x, o.y, aimFrom(o), 3.0, { big: 3, r: 16 }); }
    yield 26;
  }
  yield 70;
};
R.dragonQuake = function* (aw, lv) {
  // 叩きつけで地面が裂ける。稲妻の形のひびが光って予告され、ひびに沿って炎の壁が噴き上がる。岩も飛び散る
  for (let v = 0; v < (aw ? 3 : 2); v++) {
    const pts = []; let x = clamp(G.P.x + (rand() - 0.5) * 80, 40, W - 40);
    for (let y = 150; y <= H + 20; y += 50) { pts.push({ x, y }); x = clamp(x + (rand() < 0.5 ? -1 : 1) * (30 + rand() * 40), 30, W - 30); }
    G.marks.push({ k: "crack", pts, t: 0, life: 44 });
    yield 44;
    for (let i = 0; i < pts.length - 1; i++) for (let k = 0; k < 2; k++) {
      const a = pts[i], b = pts[i + 1], px = a.x + (b.x - a.x) * k / 2, py = a.y + (b.y - a.y) * k / 2;
      zone({ shape: "circle", x: px, y: py, r: 24, warn: i * 2, dur: 46, col: "#ff8c28", pillar: 1 });
    }
    for (let k = 0; k < (aw ? 6 : 4); k++) { const q = pts[1 + Math.floor(rand() * (pts.length - 2))]; fire("rock", q.x, q.y, -PI / 2 + (rand() - 0.5) * 1.4, 3 + rand() * 2, { big: 2.2, r: 8, spin: 1, u: b => { b.vy += 0.07; } }); }
    yield aw ? 50 : 64;
  }
  yield 40;
};
R.dragonTail = function* (aw, lv) {
  // 尻尾の薙ぎ払い: 自機の高さに横一文字の帯が予告され、巨大な尻尾が画面を横切る。上下どちらかへ逃げる。通ったあと、トゲが上下に飛ぶ
  for (let v = 0; v < (aw ? 4 : 3); v++) {
    const hh = aw ? 96 : 76, y0 = clamp(G.P.y - hh / 2, 290, 470 - (aw ? 20 : 0)), dir = v % 2 ? -1 : 1;
    zone({ shape: "rect", x: 0, y: y0, w: W, h: hh, warn: 38, dur: 14, col: "#ffc83c", sweep: dir });
    yield 38;
    const sx0 = rand() * 40;
    for (let k = 0; k < 9; k++) { const x = sx0 + k * 40; fire("spine", x, y0 + hh / 2, k % 2 ? PI / 2 : -PI / 2, 2.6, { big: 2.2, r: 6 }); }
    yield aw ? 34 : 46;
  }
  yield 50;
};
R.dragonRampage = function* (aw, lv) {
  // 本体が画面じゅうを8の字に飛び回る。体に当たるとダメージ。飛んだ跡に炎の竜巻が2つ残り、自機を引き寄せる。竜巻に当たるとバインド
  const T = aw ? 250 : 210;
  bodyHit(T + 20, 44);
  const tor = [];
  for (let t = 0; t < T; t++) {
    const u = t / T * TAU * (aw ? 2 : 1.5), e = Math.min(1, t / 30, (T - t) / 30);
    G.Boff.x = sin(u) * 120 * e; G.Boff.y = (0.5 - 0.5 * cos(u * 2)) * 300 * e + sin(u) * 30 * e;
    if (t === 50 || t === 110) {
      const b = fire("tornado", G.B.x, G.B.y + 40, 0, 0, { big: 5, r: 22, bind: 50, life: 260, x0: G.B.x, y0: clamp(G.B.y + 60, 280, 520), u: q => { q.x = q.x0 + sin(q.t * 0.03 + q.ph) * 60; q.y = q.y0 + sin(q.t * 0.05) * 16; } });
      tor.push(b);
    }
    const live = tor.filter(q => !q.dead);
    G.pull = live.length ? { at: () => live.reduce((a, q) => hypot(q.x - G.P.x, q.y - G.P.y) < hypot(a.x - G.P.x, a.y - G.P.y) ? q : a), f: 0.7 } : null;
    if (t % 16 === 0) fire("flame", G.B.x, G.B.y + 30, PI / 2 + (rand() - 0.5) * 0.8, 1.4, { big: 2.4, r: 8 });
    yield 1;
  }
  G.Boff.x = 0; G.Boff.y = 0;
  yield 120; G.pull = null;
};
R.dragonEnd = function* (aw, lv) {
  // 終焉: 画面のほぼ全部が焼き尽くされる。当たると即死。光る竜鱗の輪の中だけが安全。輪は予告のあいだに少しずつ動く
  for (let v = 0; v < 2; v++) {
    const n = aw ? 1 : 2, safe = [];
    for (let k = 0; k < n; k++) safe.push({ x: 60 + rand() * (W - 120), y: 300 + rand() * 240, r: aw ? 40 : 46, vx: aw ? (rand() < 0.5 ? 0.5 : -0.5) : 0 });
    zone({ shape: "safe", safe, warn: aw ? 100 : 115, dur: 22, kill: 1, col: "#ffdc8c" });
    yield (aw ? 100 : 115) + 60;
  }
  yield 40;
};

// ---------- 進行(構え → 技中 → 硬直 → 待機) ----------
function animOf(st) {
  // ドラゴンは技ごとに動きが違う(spec の anim / windup)。ほかのボスは 構え・技中・硬直 が1種類
  const p = G.pat; if (!p || !p.anim || st === "idle") return st;
  return (st === "windup" ? (p.windup || p.anim) : p.anim) + "_" + st;
}
function* director() {
  while (true) {
    G.anim = "windup"; G.animT = 0; G.banner = { t: 0 };
    yield G.pat.anim ? 30 : 28;
    G.anim = "attack"; G.animT = 0;
    yield* R[G.pat.id](G.aw, G.lv);
    G.Boff.x = 0; G.Boff.y = 0; G.wind = { x: 0, y: 0 }; G.pull = null; G.pose = null;
    G.anim = "recover"; G.animT = 0; yield G.pat.anim ? 15 : 14;
    G.anim = "idle"; G.animT = 0; yield 50;
  }
}

function reset() {
  G.bullets = []; G.lasers = []; G.marks = []; G.tasks = []; G.walls = []; G.hits = 0; G.inv = 0; G.dark = 0; G.T = 0;
  G.Boff = { x: 0, y: 0 }; G.wind = { x: 0, y: 0 }; G.pull = null; G.bind = 0; G.zones = []; G.kills = 0; G.heat = 0;
  G.fx = []; G.shake = 0; G.flashes = []; G.pose = null;
  G.P = { x: 180, y: 500 };
  spawn(director());
}

// ---------- 自機(自動で避ける。ドラッグや矢印キーで動かせる) ----------
function danger(x, y) {
  let d = 0;
  for (const b of G.bullets) {
    if (b.friendly) continue;
    const dx0 = b.x - x, dy0 = b.y - y; if (dx0 * dx0 + dy0 * dy0 > 110 * 110) continue;
    for (let k = 2; k <= 14; k += 4) { const bx = b.x + b.vx * k, by = b.y + b.vy * k, q = (bx - x) ** 2 + (by - y) ** 2; d += (1 + b.r / 3) / (q + 4) * (18 - k); }
  }
  for (const L of G.lasers) {
    if (L.t > L.warn - 25) {
      const o = L.from(), ux = cos(L.a), uy = sin(L.a), px = x - o.x, py = y - o.y, pr = px * ux + py * uy;
      if (pr > 0 && pr < L.len) { const dist = Math.abs(px * uy - py * ux); if (dist < L.w / 2 + 16) d += (L.w / 2 + 16 - dist) * 0.5; }
    }
  }
  // 固定された照準: もうすぐ極太ビームが来る線
  for (const m of G.marks) if (m.k === "ret" && m.lock) {
    const o = EYE(), ux = m.x - o.x, uy = m.y - o.y, l = hypot(ux, uy), px = x - o.x, py = y - o.y;
    const dist = Math.abs(px * uy / l - py * ux / l); if (dist < 34) d += (34 - dist) * 1.5;
  }
  // 範囲攻撃(予告の間も避ける)
  for (const z of G.zones) {
    if (z.shape === "rect") {
      if (x > z.x - 14 && x < z.x + z.w + 14 && y > z.y - 14 && y < z.y + z.h + 14) {      // いちばん近い出口へ向かう
        const ex = Math.min(z.x <= 0 ? 1e9 : x - (z.x - 14), z.x + z.w >= W ? 1e9 : z.x + z.w + 14 - x), ey = Math.min(z.y <= 230 ? 1e9 : y - (z.y - 14), z.y + z.h >= H ? 1e9 : z.y + z.h + 14 - y);
        d += 40 + Math.min(ex, ey) * 0.8;
      }
    }
    else if (z.shape === "circle") { const q = hypot(x - z.x, y - z.y); if (q < z.r + 16) d += 40 + (z.r + 16 - q) * 0.8; }
    else if (z.shape === "safe") { const q = Math.min(...z.safe.map(c => hypot(x - c.x, y - c.y) - c.r + 14)); if (q > 0) d += 30 + q * 0.6; }
    else if (z.shape === "ring") {
      const q = hypot(x - z.x, y - z.y), a = atan2(y - z.y, x - z.x);
      if (q > z.r - 10 && q < z.r + 260) d += Math.max(0, angDiff(a, z.gapA) - z.gapW * 0.5) * 60;        // 輪が来る前に、抜け道の向きへ寄る
    }
  }
  // 下りてくる壁: 近い列の通り道へ寄る
  for (const w of G.walls) {
    if (!w.ref || w.ref.dead) continue;
    const dy = y - w.ref.y; if (dy > 0 && dy < 140) d += Math.abs(x - (w.gx + w.ref.x - w.ref.x0)) * 0.03 * (140 - dy) / 140;
  }
  return d;
}
const keys = {};
function movePlayer() {
  const P = G.P, sp = 3.3;
  // 風と引き寄せ(ドラゴン): 操作とは別に、自機が流される
  P.x += G.wind.x; P.y += G.wind.y;
  if (G.pull) { const o = G.pull.at(), l = hypot(o.x - P.x, o.y - P.y); if (l > 30) { P.x += (o.x - P.x) / l * G.pull.f; P.y += (o.y - P.y) / l * G.pull.f; } }
  if (G.bind > 0) { G.bind--; P.x = clamp(P.x, 8, W - 8); P.y = clamp(P.y, 220, H - 12); return; }      // バインド中は動けない
  let mx = (keys.ArrowRight ? 1 : 0) - (keys.ArrowLeft ? 1 : 0), my = (keys.ArrowDown ? 1 : 0) - (keys.ArrowUp ? 1 : 0);
  if (mx || my) { G.manualUntil = G.T + 90; const l = hypot(mx, my); P.x += mx / l * sp; P.y += my / l * sp; }
  else if (G.target) { G.manualUntil = G.T + 90; const dx = G.target.x - P.x, dy = G.target.y - P.y, l = hypot(dx, dy); if (l > 1) { const s = Math.min(l, 5); P.x += dx / l * s; P.y += dy / l * s; } }
  else if (G.auto && G.T > G.manualUntil) {
    let best = null, bv = 1e9;
    for (const dx of [-1, -0.5, 0, 0.5, 1]) for (const dy of [-1, -0.5, 0, 0.5, 1]) {
      const l = Math.max(1, hypot(dx, dy)), x = P.x + dx / l * sp, y = P.y + dy / l * sp; if (x < 10 || x > W - 10 || y < (G.zones.length ? 230 : 300) || y > H - 16) continue;
      const v = danger(x, y) + ((x - 180) ** 2 + (y - 500) ** 2) * 0.000004; if (v < bv) { bv = v; best = { x, y }; }
    }
    if (best) { P.x = best.x; P.y = best.y; }
  }
  P.x = clamp(P.x, 8, W - 8); P.y = clamp(P.y, 220, H - 12);
}

// ---------- 1フレーム ----------
function step() {
  G.T++; G.animT++;
  const b0 = G.boss;
  G.B.x = 180 + sin(G.T * 0.012) * (b0.id === "dragon" ? 12 : 30) + G.Boff.x;
  G.B.y = (b0.id === "puni" && !G.aw ? 150 : 128) + sin(G.T * 0.02) * 5 + G.Boff.y;
  for (const t of G.tasks) { if (t.done) continue; if (t.wait > 0) { t.wait--; continue; } const r = t.g.next(); if (r.done) t.done = 1; else t.wait = (r.value || 1) - 1; }
  G.tasks = G.tasks.filter(t => !t.done);
  if (G.dark > 0) G.dark--;
  if (G.banner) G.banner.t++;
  movePlayer();
  const P = G.P;
  for (const b of G.bullets) {
    b.t++; if (b.u) b.u(b); b.x += b.vx; b.y += b.vy;
    if (b.big >= 2 && b.type !== "body") {       // 大きい弾は火花の尾を引く
      if (b.type === "tornado") { spark(b.x + (rand() - 0.5) * 50, b.y + 20, 1, 2.4, { a: -PI / 2, spread: 0.8, life: 30, s: 2 }); if (b.t % 3 === 0) spark(b.x, b.y + 24, 1, 1, { k: 2, life: 40, jit: 40, g: -0.04 }); }
      else if (b.t % 2 === 0) spark(b.x, b.y, b.type === "sun" ? 3 : 1, b.type === "sun" ? 2 : 0.7, { life: b.type === "sun" ? 26 : 16, s: b.type === "sun" ? 3 : 2, jit: b.r });
    }
    if (b.life && b.t > b.life) b.dead = 1;
    if (b.x < -40 || b.x > W + 40 || b.y < -60 || b.y > H + 40) { if (b.t > 30 || b.y > H) b.dead = 1; }
    if (!G.inv && !b.dead && !b.friendly && (b.x - P.x) ** 2 + (b.y - P.y) ** 2 < (b.r + 2.5) ** 2) hit(b);
  }
  G.bullets = G.bullets.filter(b => !b.dead);
  for (const L of G.lasers) {
    L.t++; if (L.t > L.warn) L.a += L.va;
    if (L.fire && L.t > L.warn) {      // 炎の柱: ふちから火花が散り、口元と画面の下で炎がはじける
      const o = L.from(), ux = cos(L.a), uy = sin(L.a);
      for (let i = 0; i < 4; i++) { const d = rand() * 640, sd = rand() < 0.5 ? 1 : -1; spark(o.x + ux * d - uy * sd * L.w * 0.5, o.y + uy * d + ux * sd * L.w * 0.5, 1, 2.2, { a: L.a + sd * 1.1, spread: 0.9, life: 22, s: 2 }); }
      spark(o.x, o.y, 2, 3.5, { a: L.a, spread: 2.2, life: 16, s: 3 });
      if (uy > 0.2) { const d = (H - o.y) / uy; spark(o.x + ux * d, H - 4, 3, 4, { a: -PI / 2, spread: 2.4, life: 26, s: 3, g: 0.12 }); if (L.t % 4 === 0) spark(o.x + ux * d, H - 6, 1, 1.5, { k: 1, a: -PI / 2, life: 44, s: 6, jit: L.w }); }
      if (L.t === L.warn + 1) shake(8); else if (L.t % 6 === 0) shake(2);
    }
    if (L.track) { let d = aimFrom(L.from()) - L.a; while (d > PI) d -= TAU; while (d < -PI) d += TAU; L.a += clamp(d, -L.track, L.track); }
    if (L.t > L.warn && !G.inv) {
      const o = L.from(), ux = cos(L.a), uy = sin(L.a), px = P.x - o.x, py = P.y - o.y, pr = px * ux + py * uy;
      if (pr > 0 && pr < L.len && Math.abs(px * uy - py * ux) < L.w / 2) hit();
    }
  }
  G.lasers = G.lasers.filter(L => L.t < L.warn + L.dur);
  // 範囲攻撃(ドラゴン)
  for (const z of G.zones) {
    z.t++;
    if (z.shape === "ring") { if (z.at && z.t < 4) { const o = z.at(); z.x = o.x; z.y = o.y; } z.r += z.vr; }
    if (z.shape === "safe") for (const c of z.safe) { c.x += c.vx || 0; if (c.x < 50 || c.x > W - 50) c.vx = -(c.vx || 0); }
    if (z.t === z.warn + 1) {       // 当たり始めの瞬間
      if (z.shape === "circle" && z.boom) boom(z.x, z.y, z.r);
      else if (z.shape === "circle" && z.claw) { shake(7); spark(z.x, z.y, 30, 6, { life: 20, s: 3 }); G.flashes.push({ x: z.x, y: z.y, r: z.r, t: 0, life: 14, slash: z.x > G.B.x ? 1 : -1 }); }
      else if (z.shape === "circle" && z.pillar) { spark(z.x, z.y, 8, 5, { a: -PI / 2, spread: 1.2, life: 30, s: 3, g: 0.1 }); shake(5); }
      else if (z.shape === "rect") { shake(9); }
      else if (z.shape === "safe") { shake(18); for (let i = 0; i < 120; i++) spark(rand() * W, rand() * H, 1, 5, { life: 40, s: 3 }); }
    }
    if (z.shape === "ring") { for (let i = 0; i < 3; i++) { const a = z.gapA + z.gapW + rand() * (TAU - 2 * z.gapW); spark(z.x + cos(a) * z.r, z.y + sin(a) * z.r, 1, 1.5, { a, spread: 0.8, life: 18, s: 2 }); } }
    if (z.shape === "safe" && z.t <= z.warn) { for (let i = 0; i < 2 + (z.t / z.warn) * 5; i++) spark(rand() * W, H + 4, 1, 3 + 3 * z.t / z.warn, { a: -PI / 2, spread: 0.5, life: 60, s: 2, k: 2, g: -0.05 }); if (z.t > z.warn * 0.6) shake(2); }
    if (z.t > z.warn) {
      if (z.pillar && z.t % 2 === 0) spark(z.x, z.y + z.r * 0.5, 1, 4.5, { a: -PI / 2, spread: 0.7, life: 26, s: 3 });
      if (z.fly) for (let i = 0; i < 5; i++) spark(G.B.x - z.fly * (40 + rand() * 160), z.y + rand() * z.h, 1, 4, { a: z.fly > 0 ? PI : 0, spread: 1, life: 26, s: 3 });
      if (z.sweep) { const u = (z.t - z.warn) / z.dur, x = z.sweep > 0 ? -160 + u * (W + 320) : W + 160 - u * (W + 320); for (let i = 0; i < 6; i++) spark(x, z.y + rand() * z.h, 1, 5, { a: z.sweep > 0 ? PI : 0, spread: 1.2, life: 22, s: 3 }); }
    }
    if (z.t <= z.warn || G.inv) continue;
    let h = false;
    if (z.shape === "rect") h = P.x > z.x && P.x < z.x + z.w && P.y > z.y && P.y < z.y + z.h;
    else if (z.shape === "circle") h = hypot(P.x - z.x, P.y - z.y) < z.r;
    else if (z.shape === "safe") h = !z.safe.some(c => hypot(P.x - c.x, P.y - c.y) < c.r);
    else if (z.shape === "ring") { const q = hypot(P.x - z.x, P.y - z.y); h = Math.abs(q - z.r) < z.th / 2 && angDiff(atan2(P.y - z.y, P.x - z.x), z.gapA) > z.gapW; }
    if (h) hit(z);
  }
  G.zones = G.zones.filter(z => z.t < z.warn + z.dur && !(z.shape === "ring" && z.r > 760));
  // 風の筋・吸い込みの筋(見た目だけ)
  if (G.wind.x) for (let i = 0; i < 3; i++) spark(G.wind.x > 0 ? -10 : W + 10, 180 + rand() * 420, 1, 9, { a: G.wind.x > 0 ? 0.08 : PI - 0.08, spread: 0.05, life: 50, s: 2, k: 3, drag: 1 });
  if (G.pull && G.pull.f) { const o = G.pull.at(); if (o.y < 200) for (let i = 0; i < 2; i++) { const a = rand() * PI, d = 180 + rand() * 260, x = o.x + cos(a) * d, y = o.y + sin(a) * d; spark(x, y, 1, 7, { a: atan2(o.y - y, o.x - x), spread: 0.1, life: 30, s: 2, k: 3, drag: 1.02 }); } }
  for (const q of G.fx) { q.t++; q.x += q.vx; q.y += q.vy; q.vy += q.g; q.vx *= q.drag; q.vy *= q.drag; }
  G.fx = G.fx.filter(q => q.t < q.life);
  for (const f of G.flashes) f.t++;
  G.flashes = G.flashes.filter(f => f.t < f.life);
  if (G.shake > 0) G.shake *= 0.86;
  for (const m of G.marks) m.t++;
  G.marks = G.marks.filter(m => !m.dead && m.t < m.life);
  if (G.inv) G.inv--;
}
function hit(src) {
  G.hits++; G.inv = 40; spark(G.P.x, G.P.y, 20, 4, { life: 20, s: 2 }); shake(5);
  if (src && src.bind) G.bind = src.bind;        // バインド: しばらく動けない
  if (src && src.kill) { G.kills++; G.inv = 90; G.heat = 30; }      // 即死
}
