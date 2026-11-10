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
};
const ORIENT = new Set(["kingyo", "fox", "ofuda", "missile", "shell", "icicle", "shard", "soul", "chain", "tooth"]);
const SPRITES = {};
function makeSprite(map, pal) {
  const h = map.length, w = map[0].length, c = document.createElement("canvas");
  c.width = w; c.height = h; const x = c.getContext("2d");
  for (let j = 0; j < h; j++) for (let i = 0; i < w; i++) { const ch = map[j][i]; if (pal[ch]) { x.fillStyle = pal[ch]; x.fillRect(i, j, 1, 1); } }
  return c;
}
for (const k in MAPS) SPRITES[k] = [makeSprite(MAPS[k], PALS[k][0]), makeSprite(MAPS[k], PALS[k][1])];
const RADIUS = { kingyo: 3, yoyo: 4, spark: 2.5, awa: 2.5, fox: 3, ofuda: 3, plankton: 2.5, bubble: 4, ink: 6, missile: 3, hex: 3, shell: 2, flake: 3, icicle: 3, shard: 2.5, soul: 3, blade: 3, chain: 2.5, jelly: 3.5, eye: 4, tooth: 2.5, goo: 2.5 };

// ---------- 状態 ----------
const G = { T: 0, bullets: [], lasers: [], marks: [], tasks: [], walls: [], hits: 0, inv: 0, dark: 0, banner: null,
  B: { x: 180, y: 128 }, P: { x: 180, y: 500 }, aw: false, boss: null, pat: null, anim: "idle", animT: 0, auto: true, target: null, manualUntil: 0 };

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
const CRYS = () => pt(56, 50);
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
const SKULL = () => pt(56, 40);
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
// ひれ(金魚すくいの金魚娘)
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

// ---------- 進行(構え → 技中 → 硬直 → 待機) ----------
function* director() {
  while (true) {
    G.anim = "windup"; G.animT = 0; G.banner = { t: 0 };
    yield 28;
    G.anim = "attack"; G.animT = 0;
    yield* R[G.pat.id](G.aw);
    G.anim = "recover"; G.animT = 0; yield 14;
    G.anim = "idle"; G.animT = 0; yield 50;
  }
}

function reset() {
  G.bullets = []; G.lasers = []; G.marks = []; G.tasks = []; G.walls = []; G.hits = 0; G.inv = 0; G.dark = 0; G.T = 0;
  G.P = { x: 180, y: 500 };
  spawn(director());
}

// ---------- 自機(自動で避ける。ドラッグや矢印キーで動かせる) ----------
function danger(x, y) {
  let d = 0;
  for (const b of G.bullets) {
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
  let mx = (keys.ArrowRight ? 1 : 0) - (keys.ArrowLeft ? 1 : 0), my = (keys.ArrowDown ? 1 : 0) - (keys.ArrowUp ? 1 : 0);
  if (mx || my) { G.manualUntil = G.T + 90; const l = hypot(mx, my); P.x += mx / l * sp; P.y += my / l * sp; }
  else if (G.target) { G.manualUntil = G.T + 90; const dx = G.target.x - P.x, dy = G.target.y - P.y, l = hypot(dx, dy); if (l > 1) { const s = Math.min(l, 5); P.x += dx / l * s; P.y += dy / l * s; } }
  else if (G.auto && G.T > G.manualUntil) {
    let best = null, bv = 1e9;
    for (const dx of [-1, -0.5, 0, 0.5, 1]) for (const dy of [-1, -0.5, 0, 0.5, 1]) {
      const x = P.x + dx * sp, y = P.y + dy * sp; if (x < 10 || x > W - 10 || y < 300 || y > H - 16) continue;
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
  G.B.x = 180 + sin(G.T * 0.012) * 30;
  G.B.y = (b0.id === "puni" && !G.aw ? 150 : 128) + sin(G.T * 0.02) * 5;
  for (const t of G.tasks) { if (t.done) continue; if (t.wait > 0) { t.wait--; continue; } const r = t.g.next(); if (r.done) t.done = 1; else t.wait = (r.value || 1) - 1; }
  G.tasks = G.tasks.filter(t => !t.done);
  if (G.dark > 0) G.dark--;
  if (G.banner) G.banner.t++;
  movePlayer();
  const P = G.P;
  for (const b of G.bullets) {
    b.t++; if (b.u) b.u(b); b.x += b.vx; b.y += b.vy;
    if (b.life && b.t > b.life) b.dead = 1;
    if (b.x < -40 || b.x > W + 40 || b.y < -60 || b.y > H + 40) { if (b.t > 30 || b.y > H) b.dead = 1; }
    if (!G.inv && !b.dead && (b.x - P.x) ** 2 + (b.y - P.y) ** 2 < (b.r + 2.5) ** 2) hit();
  }
  G.bullets = G.bullets.filter(b => !b.dead);
  for (const L of G.lasers) {
    L.t++; if (L.t > L.warn) L.a += L.va;
    if (L.t > L.warn && !G.inv) {
      const o = L.from(), ux = cos(L.a), uy = sin(L.a), px = P.x - o.x, py = P.y - o.y, pr = px * ux + py * uy;
      if (pr > 0 && pr < L.len && Math.abs(px * uy - py * ux) < L.w / 2) hit();
    }
  }
  G.lasers = G.lasers.filter(L => L.t < L.warn + L.dur);
  for (const m of G.marks) m.t++;
  G.marks = G.marks.filter(m => !m.dead && m.t < m.life);
  if (G.inv) G.inv--;
}
function hit() { G.hits++; G.inv = 40; }
