import { inflateRawSync } from "node:zlib";
import { RECIPES, emitRecipe } from "./adpatterns.js";
import { pathPosition } from "./custompath.js";
import { PATTERNS, timeLimitSec, type Emitter, type LifeMode, type Mode, type Wave } from "./validate.js";

/**
 * ゲーム計算の完全版(アプリの DanmakuCore.Simulation の移植)。ランキングの記録を、
 * アプリから届いた操作記録(リプレイ)を再生して確かめるために使う。
 * アプリ側と同じ結果になることは、test/fullsim.test.ts が Swift 版の正解データで確かめている。
 */
const W = 360, H = 540;
const STEP = 1 / 120;
const READY = 1.2;
const MAX_BULLETS = 1600;
const HIT_R2 = 30.25;
const MOVE_UNIT = 0.25;
const LIFE_SHIELD_SECONDS = 2.0;
const HOMING_SECONDS = 2.5;
const STOPGO_MOVE = 0.55, STOPGO_HOLD = 0.6, STOPGO_BOOST = 1.3;
const SPLIT_AFTER = 0.7, SPLIT_COUNT = 6, SPLIT_SPEED = 0.7;
const TIMED_HOLD = 1.1;
/** ボスの大きさ(小・中・大)ごとの、弾が当たる半径。アプリの DanmakuConfig.bossRadii と同じ */
const BOSS_RADII = [17, 24, 34] as const;
const BOSS_MOVES = [{ a: 0, w: 0 }, { a: 0.25, w: 0.6 }, { a: 0.32, w: 1.3 }] as const;

export type ShotType = "standard" | "spread" | "heavy";
const SHOTS: Record<ShotType, { interval: number; volley: { dx: number; vx: number; damage: number }[] }> = {
  standard: { interval: 0.09, volley: [{ dx: -5, vx: 0, damage: 1 }, { dx: 5, vx: 0, damage: 1 }] },
  spread: { interval: 0.135, volley: [{ dx: -4, vx: -28, damage: 1 }, { dx: 0, vx: 0, damage: 1 }, { dx: 4, vx: 28, damage: 1 }] },
  heavy: { interval: 0.18, volley: [{ dx: 0, vx: 0, damage: 4 }] },
};
export const isShotType = (v: unknown): v is ShotType => v === "standard" || v === "spread" || v === "heavy";

export interface SimStage {
  mode: Mode;
  durationSec: number;
  bossHp?: number | null;
  bossMove?: number | null;
  emitters: Emitter[];
  lifeMode?: LifeMode | null;
  lifeCount?: number | null;
  waves?: Wave[] | null;
  bossSize?: number | null;
}

/** 1つの場面。連戦以外は、ステージ全体が「場面1つ」 */
interface Spec { boss: boolean; damage: boolean; limit: number; hp: number; move: number; emitters: Emitter[]; size: number }
const INTERMISSION = 1.5;

function specsOf(st: SimStage): Spec[] {
  if (st.mode === "sequence" && st.waves && st.waves.length > 0) {
    return st.waves.map((w) => ({ boss: w.kind === "boss", damage: false, limit: w.durationSec, hp: w.bossHp ?? 0, move: w.bossMove ?? 0, emitters: w.emitters, size: w.bossSize ?? 1 }));
  }
  return [{ boss: st.mode !== "survive", damage: st.mode === "damage", limit: timeLimitSec(st.mode, st.durationSec), hp: st.bossHp ?? 0, move: st.bossMove ?? 0, emitters: st.emitters, size: st.bossSize ?? 1 }];
}

export type Outcome = "playing" | "cleared" | "hit" | "timeUp";
export interface SimResult { outcome: Outcome; tick: number; hp: number; damage: number; lifeLeft: number; wave: number; defeats: number; bulletCount: number; bulletHash: number; bulletHashCoarse: number }

// --- 乱数(mulberry32)とハッシュ(FNV-1a)
function mulberry(seed: number) {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a) >>> 0;
    t = ((t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t) >>> 0;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

class Fnv {
  value = 2166136261;
  addByte(b: number) { this.value = Math.imul(this.value ^ (b & 0xff), 16777619) >>> 0; }
  addInt32(n: number) { const u = n >>> 0; for (let s = 0; s < 32; s += 8) this.addByte((u >>> s) & 0xff); }
}

/** アプリの Stage.seed と同じ。ライフの設定は入れない */
export function stageSeed(st: SimStage): number {
  const h = new Fnv();
  h.addInt32(st.mode === "boss" ? 1 : st.mode === "damage" ? 2 : st.mode === "sequence" ? 3 : 0);
  h.addInt32(st.bossHp ?? 0);
  h.addInt32(st.bossMove ?? 0);
  h.addInt32(st.durationSec);
  hashEmitters(h, st.emitters);
  if (st.mode === "sequence") {
    for (const w of st.waves ?? []) {
      h.addInt32(w.kind === "boss" ? 1 : 0);
      h.addInt32(w.durationSec);
      h.addInt32(w.bossHp ?? 0);
      h.addInt32(w.bossMove ?? 0);
      hashEmitters(h, w.emitters);
    }
  }
  return h.value;
}

function hashEmitters(h: Fnv, list: Emitter[]) {
  for (const m of list) {
    h.addInt32((PATTERNS as readonly string[]).indexOf(m.t));
    for (const q of [m.x, m.y, m.s, m.e, m.i, m.v]) h.addInt32(Math.round(q * 100));
    h.addInt32(m.c); h.addInt32(Math.round(m.r)); h.addInt32(m.k); h.addInt32(m.ph);
    if (m.a) h.addInt32(1000 + m.a);   // 回さないときは混ぜない(アプリの Stage.seed と同じ)
    if (m.p) h.addInt32(m.p);   // 標準(0)のときは混ぜない: アプリの Stage.seed と同じ
  }
}

interface Follow { pts: readonly number[]; ox: number; oy: number; cs: number; sn: number; scale: number }
interface Bullet { x: number; y: number; vx: number; vy: number; color: number; turn: number; homeLeft: number; accel: number; maxSpeed: number; bounces: number; script: number; age: number; follow?: Follow }
interface Shot { x: number; y: number; vx: number; damage: number }

function emit(m: Emitter, k: number, cx: number, cy: number, px: number, py: number, rng: () => number, out: Bullet[]) {
  const sp = m.v * 60;
  const n = Math.max(1, m.c);
  const deg = Math.PI / 180;
  const off = (m.a ?? 0) * deg;   // パターン全体を回す角度
  const add = (x: number, y: number, a: number) => {
    if (out.length < MAX_BULLETS) out.push({ x, y, vx: Math.cos(a) * sp, vy: Math.sin(a) * sp, color: m.k, turn: 0, homeLeft: 0, accel: 0, maxSpeed: 0, bounces: 0, script: 0, age: 0 });
  };
  switch (m.t) {
    case "ring": case "spiral":
      for (let j = 0; j < n; j++) add(cx, cy, (j * 2 * Math.PI) / n + k * m.r * deg + off);
      break;
    case "aim": {
      const b = Math.atan2(py - cy, px - cx) + off;
      for (let j = 0; j < n; j++) add(cx, cy, b + (n > 1 ? (j / (n - 1) - 0.5) * m.r * deg : 0));
      break;
    }
    case "rain":
      for (let j = 0; j < n; j++) { const x = rng() * W; const a = Math.PI / 2 + (rng() - 0.5) * 0.3; add(x, -8, a); }
      break;
    case "homing": {
      const b = Math.atan2(py - cy, px - cx) + off;
      const turn = Math.max(25, Math.abs(m.r) * 2) * deg;
      for (let j = 0; j < n; j++) {
        const a = b + (j - (n - 1) / 2) * 0.35;
        if (out.length < MAX_BULLETS) out.push({ x: cx, y: cy, vx: Math.cos(a) * sp, vy: Math.sin(a) * sp, color: m.k, turn, homeLeft: HOMING_SECONDS, accel: 0, maxSpeed: 0, bounces: 0, script: 0, age: 0 });
      }
      break;
    }
    case "flower": case "star": case "heart": {
      const rot = k * m.r * deg;
      for (let j = 0; j < n; j++) {
        const th = (j * 2 * Math.PI) / n + rot + off;
        const rel = th - rot - off;
        let f: number;
        if (m.t === "flower") f = 0.4 + 0.6 * Math.abs(Math.cos(2.5 * rel));
        else if (m.t === "star") {
          const u = (rel * 5 / (2 * Math.PI)) % 1;
          const ph = u < 0 ? u + 1 : u;
          f = 0.45 + 0.55 * Math.abs(ph - 0.5) * 2;
        } else {
          const q = -rel;
          const sq = Math.sqrt(Math.abs(Math.cos(q)));
          const rr = (2 - 2 * Math.sin(q) + (Math.sin(q) * sq) / (Math.sin(q) + 1.4)) / 4;
          f = 0.15 + 0.85 * Math.max(0, Math.min(1, rr));
        }
        if (out.length < MAX_BULLETS) out.push({ x: cx, y: cy, vx: Math.cos(th) * sp * f, vy: Math.sin(th) * sp * f, color: m.k, turn: 0, homeLeft: 0, accel: 0, maxSpeed: 0, bounces: 0, script: 0, age: 0 });
      }
      break;
    }
    case "beam": {
      const b = Math.atan2(py - cy, px - cx) + off + m.r * deg * 0.2;
      for (let j = 0; j < n; j++) {
        const f = 1 + j * 0.18;
        if (out.length < MAX_BULLETS) out.push({ x: cx, y: cy, vx: Math.cos(b) * sp * f, vy: Math.sin(b) * sp * f, color: m.k, turn: 0, homeLeft: 0, accel: 0, maxSpeed: 0, bounces: 0, script: 0, age: 0 });
      }
      break;
    }
    case "cross": {
      const per = Math.max(1, Math.trunc(n / 4));
      const rot = k * m.r * deg;
      for (let arm = 0; arm < 4; arm++) {
        const a = (arm * Math.PI) / 2 + rot + off;
        for (let j = 0; j < per; j++) {
          const f = 1 + j * 0.25;
          if (out.length < MAX_BULLETS) out.push({ x: cx, y: cy, vx: Math.cos(a) * sp * f, vy: Math.sin(a) * sp * f, color: m.k, turn: 0, homeLeft: 0, accel: 0, maxSpeed: 0, bounces: 0, script: 0, age: 0 });
        }
      }
      break;
    }
    case "accel": case "bounce": {
      const b = Math.atan2(py - cy, px - cx) + off;
      for (let j = 0; j < n; j++) {
        const a = b + (n > 1 ? (j / (n - 1) - 0.5) * m.r * deg : 0);
        if (out.length >= MAX_BULLETS) continue;
        if (m.t === "accel") out.push({ x: cx, y: cy, vx: Math.cos(a) * sp * 0.3, vy: Math.sin(a) * sp * 0.3, color: m.k, turn: 0, homeLeft: 0, accel: 0.9, maxSpeed: sp * 2, bounces: 0, script: 0, age: 0 });
        else out.push({ x: cx, y: cy, vx: Math.cos(a) * sp, vy: Math.sin(a) * sp, color: m.k, turn: 0, homeLeft: 0, accel: 0, maxSpeed: 0, bounces: 2, script: 0, age: 0 });
      }
      break;
    }
    case "stopgo": case "split": {
      const b = Math.atan2(py - cy, px - cx) + off;
      for (let j = 0; j < n; j++) {
        const a = b + (n > 1 ? (j / (n - 1) - 0.5) * m.r * deg : 0);
        if (out.length < MAX_BULLETS) out.push({ x: cx, y: cy, vx: Math.cos(a) * sp, vy: Math.sin(a) * sp, color: m.k, turn: 0, homeLeft: 0, accel: 0, maxSpeed: 0, bounces: 0, script: m.t === "stopgo" ? 1 : 2, age: 0 });
      }
      break;
    }
    case "timed": {
      for (let j = 0; j < n; j++) {
        const a = (j * 2 * Math.PI) / n + k * m.r * deg + off;
        if (out.length < MAX_BULLETS) out.push({ x: cx, y: cy, vx: Math.cos(a) * sp, vy: Math.sin(a) * sp, color: m.k, turn: 0, homeLeft: 0, accel: 0, maxSpeed: 0, bounces: 0, script: 3, age: 0 });
      }
      break;
    }
    case "sideL": case "sideR": {
      const toRight = m.t === "sideL";
      const x0 = toRight ? -8 : W + 8;
      const spread = Math.abs(m.r) * deg;
      for (let j = 0; j < n; j++) {
        const y = rng() * H * 0.78;
        const a = (toRight ? 0 : Math.PI) + (rng() - 0.5) * 2 * spread;
        add(x0, y, a);
      }
      break;
    }
    case "corner": {
      for (const [ox, oy] of [[-8, -8], [W + 8, -8], [-8, H * 0.6], [W + 8, H * 0.6]] as const) {
        const b = Math.atan2(py - oy, px - ox);
        for (let j = 0; j < n; j++) add(ox, oy, b + (n > 1 ? (j / (n - 1) - 0.5) * m.r * deg : 0));
      }
      break;
    }
    case "sweep": {
      const b = Math.PI / 2 + Math.sin(k * 0.25) * m.r * deg;
      for (let j = 0; j < n; j++) add(cx, cy, b + (n > 1 ? (j / (n - 1) - 0.5) * 0.5 : 0));
      break;
    }
    case "custom": {
      // 弾幕作成モードで描いた軌道を、n 個、均等に回して出す
      const pts = m.path;
      if (!pts) break;
      for (let j = 0; j < n; j++) {
        const a = (j * 2 * Math.PI) / n + k * m.r * deg + off;
        if (out.length < MAX_BULLETS) out.push({ x: cx, y: cy, vx: 0, vy: 0, color: m.k, turn: 0, homeLeft: 0, accel: 0, maxSpeed: 0, bounces: 0, script: 0, age: 0, follow: { pts, ox: cx, oy: cy, cs: Math.cos(a), sn: Math.sin(a), scale: m.v / 2 } });
      }
      break;
    }
    default: {
      // 広告で解放するパターン: 弾の出し方の表に従う
      const recipe = RECIPES[m.t];
      if (recipe) {
        emitRecipe(recipe, m, k, cx, cy, px, py, off, sp, n, rng, HOMING_SECONDS, (x, y, vx, vy, e) => {
          if (out.length < MAX_BULLETS) out.push({ x, y, vx, vy, color: m.k, turn: e.turn, homeLeft: e.homeLeft, accel: e.accel, maxSpeed: e.maxSpeed, bounces: e.bounces, script: e.script, age: 0 });
        });
      }
    }
  }
}

const clamp = (v: number, lo: number, hi: number) => Math.min(hi, Math.max(lo, v));
const LIVES_RANGE = [1, 5] as const, HP_RANGE = [3, 20] as const;

/** 操作記録(dx, dy は 0.25 論理px 単位)を再生して、結果を返す。入力が尽きたら動かさずに続ける */
export function simulate(stage: SimStage, moves: ArrayLike<number>, moveCount: number, shotType: ShotType = "standard"): SimResult {
  const specs = specsOf(stage);
  let wi = 0;
  const spec = () => specs[wi]!;
  const lifeMode: LifeMode = stage.lifeMode ?? "lives";
  const range = lifeMode === "lives" ? LIVES_RANGE : HP_RANGE;
  const lifeMax = clamp(stage.lifeCount ?? 1, range[0], range[1]);
  let lifeLeft = lifeMax;
  let hp = specs[0]!.hp;
  let damage = 0;
  let defeats = 0;
  const shotDef = SHOTS[shotType];
  const rng = mulberry(stageSeed(stage));
  let next = specs[0]!.emitters.map((m) => m.s);
  let shotCount = specs[0]!.emitters.map(() => 0);
  let bullets: Bullet[] = [];
  let shots: Shot[] = [];
  let tick = 0, t = -READY, waveStart = 0;
  let px = W / 2, py = H * 0.85;
  let phase = 1, banner = 0, flash = 0, cooldown = 0, shieldUntil = 0;
  let outcome: Outcome = "playing";
  const limitSec = timeLimitSec(stage.mode, stage.durationSec);
  const limit = (limitSec + 3) * 120 + 144;

  const phaseOf = (waveT: number) => {
    const sp = spec();
    if (sp.damage) { const f = Math.max(0, waveT) / sp.limit; return f < 1 / 3 ? 1 : f < 2 / 3 ? 2 : 3; }
    const r = hp / Math.max(1, sp.hp);
    return r > 2 / 3 ? 1 : r > 1 / 3 ? 2 : 3;
  };

  /** 次の場面へ: 画面の弾と自機の弾を消し、切り替えの間(自機は動ける)のあとに新しい場面が始まる */
  const advanceWave = (dt: number) => {
    wi += 1;
    waveStart = t + INTERMISSION;
    bullets = [];
    shots = [];
    next = spec().emitters.map((m) => m.s);
    shotCount = spec().emitters.map(() => 0);
    hp = spec().hp;
    phase = 1; banner = 0; flash = 0; cooldown = 0;
    shieldUntil = Math.max(shieldUntil, tick + Math.round(INTERMISSION / dt));
  };

  while (outcome === "playing" && tick < limit) {
    const dx0 = tick < moveCount ? moves[tick * 2]! : 0;
    const dy0 = tick < moveCount ? moves[tick * 2 + 1]! : 0;
    const dt = STEP;
    tick += 1;
    t += dt;
    px = clamp(px + dx0 * MOVE_UNIT, 6, W - 6);
    py = clamp(py + dy0 * MOVE_UNIT, 6, H - 6);

    const sp = spec();
    const waveT = t - waveStart;
    const bm = BOSS_MOVES[sp.move] ?? BOSS_MOVES[0];
    const bx = sp.boss ? W * (0.5 + bm.a * Math.sin(Math.max(0, waveT) * bm.w)) : 0;
    const by = sp.boss ? H * 0.18 : 0;
    if (sp.boss) {
      const ph = phaseOf(waveT);
      if (ph !== phase) {
        phase = ph;
        if (ph > 1) { bullets = []; banner = 1.2; }
      }
      if (banner > 0) banner -= dt;
      cooldown -= dt;
      if (waveT >= 0 && cooldown <= 0) {
        cooldown = shotDef.interval;
        for (const v of shotDef.volley) shots.push({ x: px + v.dx, y: py - 10, vx: v.vx, damage: v.damage });
      }
      let w = 0;
      for (let i = 0; i < shots.length; i++) {
        const s = shots[i]!;
        s.x += s.vx * dt;
        s.y -= 600 * dt;
        if (s.y < -10 || s.x < -10 || s.x > W + 10) continue;
        const dx = s.x - bx, dy = s.y - by;
        if (dx * dx + dy * dy < BOSS_RADII[Math.min(Math.max(sp.size, 0), 2)]! ** 2) {
          damage += s.damage;
          if (!sp.damage) hp -= s.damage;
          flash = 0.06; continue;
        }
        shots[w++] = s;
      }
      shots.length = w;
      if (flash > 0) flash -= dt;
      if (!sp.damage && hp <= 0) {
        defeats += 1;
        if (wi + 1 < specs.length) advanceWave(dt); else outcome = "cleared";
        continue;
      }
    }

    if (waveT >= 0) {
      sp.emitters.forEach((m, idx) => {
        if (sp.boss) {
          if (!(m.ph === 0 || m.ph === phase) || banner > 0) { next[idx] = waveT; return; }
          while (waveT >= next[idx]!) {
            emit(m, shotCount[idx]!, m.t === "rain" ? 0 : m.p === 1 ? m.x * W : bx, m.p === 1 ? m.y * H : by, px, py, rng, bullets);
            shotCount[idx]!++;
            next[idx]! += Math.max(0.05, m.i);
          }
        } else {
          const end = Math.min(m.e, sp.limit);
          while (waveT >= next[idx]! && next[idx]! < end) {
            emit(m, shotCount[idx]!, m.x * W, m.y * H, px, py, rng, bullets);
            shotCount[idx]!++;
            next[idx]! += Math.max(0.05, m.i);
          }
        }
      });
    }

    let w = 0;
    let died = false;
    const born: Bullet[] = [];
    for (let i = 0; i < bullets.length; i++) {
      const b = bullets[i]!;
      if (b.follow) {
        // 描いた軌道の上を、時間に沿って進む
        const f = b.follow;
        b.age += dt;
        const p = pathPosition(f.pts, b.age * f.scale);
        b.x = f.ox + f.cs * p.x - f.sn * p.y;
        b.y = f.oy + f.sn * p.x + f.cs * p.y;
      } else {
      let frozen = false;
      if (b.script !== 0) {
        b.age += dt;
        if (b.script === 1) {
          if (b.age >= STOPGO_MOVE + STOPGO_HOLD) {
            const speed = Math.sqrt(b.vx * b.vx + b.vy * b.vy) * STOPGO_BOOST;
            const a = Math.atan2(py - b.y, px - b.x);
            b.vx = Math.cos(a) * speed; b.vy = Math.sin(a) * speed;
            b.script = 0;
          } else if (b.age >= STOPGO_MOVE) frozen = true;
        } else if (b.script === 2) {
          if (b.age >= SPLIT_AFTER) {
            const speed = Math.sqrt(b.vx * b.vx + b.vy * b.vy) * SPLIT_SPEED;
            const base = Math.atan2(b.vy, b.vx);
            for (let j = 0; j < SPLIT_COUNT; j++) {
              if (w + born.length + (bullets.length - i - 1) >= MAX_BULLETS) break;
              const a = base + (j * 2 * Math.PI) / SPLIT_COUNT;
              born.push({ x: b.x, y: b.y, vx: Math.cos(a) * speed, vy: Math.sin(a) * speed, color: b.color, turn: 0, homeLeft: 0, accel: 0, maxSpeed: 0, bounces: 0, script: 0, age: 0 });
            }
            continue;
          }
        } else if (b.age >= TIMED_HOLD) b.script = 0; else frozen = true;
      }
      if (b.homeLeft > 0) {
        const want = Math.atan2(py - b.y, px - b.x);
        const cur = Math.atan2(b.vy, b.vx);
        let diff = want - cur;
        while (diff > Math.PI) diff -= 2 * Math.PI;
        while (diff < -Math.PI) diff += 2 * Math.PI;
        const maxTurn = b.turn * dt;
        const na = cur + Math.min(maxTurn, Math.max(-maxTurn, diff));
        const speed = Math.sqrt(b.vx * b.vx + b.vy * b.vy);
        b.vx = Math.cos(na) * speed;
        b.vy = Math.sin(na) * speed;
        b.homeLeft -= dt;
      }
      if (b.accel !== 0) {
        const speed = Math.sqrt(b.vx * b.vx + b.vy * b.vy);
        if (speed < b.maxSpeed) {
          const g = Math.min(1 + b.accel * dt, b.maxSpeed / speed);
          b.vx *= g; b.vy *= g;
        }
      }
      if (!frozen) { b.x += b.vx * dt; b.y += b.vy * dt; }
      if (b.bounces > 0) {
        if (b.x < 0) { b.x = -b.x; b.vx = -b.vx; b.bounces -= 1; }
        else if (b.x > W) { b.x = 2 * W - b.x; b.vx = -b.vx; b.bounces -= 1; }
      }
      }
      if (b.x < -20 || b.x > W + 20 || b.y < -20 || b.y > H + 20) continue;
      const dx = b.x - px, dy = b.y - py;
      if (dx * dx + dy * dy < HIT_R2) {
        if (tick < shieldUntil) continue;
        lifeLeft -= 1;
        if (lifeLeft <= 0) { outcome = "hit"; died = true; break; }   // その場で終了(弾の並びはそのまま)
        if (lifeMode === "lives") shieldUntil = tick + Math.round(LIFE_SHIELD_SECONDS / dt);
        continue;   // 当たった弾は消える
      }
      bullets[w++] = b;
    }
    if (died) break;
    bullets.length = w;
    for (const nb of born) bullets.push(nb);
    if (waveT >= sp.limit) {
      if (wi + 1 < specs.length) {
        // 連戦の途中: ボスの場面は、時間切れで失敗。生き残る場面は、クリアして次へ
        if (sp.boss && !sp.damage) outcome = "timeUp"; else advanceWave(dt);
      } else {
        outcome = sp.boss && !sp.damage ? "timeUp" : "cleared";
      }
    }
  }

  const h = new Fnv();
  const f64 = new Float64Array(1), u32 = new Uint32Array(f64.buffer);
  for (const b of bullets) {
    for (const q of [b.x, b.y]) {
      f64[0] = q;
      // リトルエンディアン: 下位32bit → 上位32bit の順に1バイトずつ
      for (const word of [u32[0]!, u32[1]!]) for (let s = 0; s < 32; s += 8) h.addByte((word >>> s) & 0xff);
    }
  }
  const c = new Fnv();
  for (const b of bullets) for (const q of [b.x, b.y]) c.addInt32(Math.round(q * 1000));
  return { outcome, tick, hp, damage, lifeLeft, wave: wi, defeats, bulletCount: bullets.length, bulletHash: h.value, bulletHashCoarse: c.value };
}

/** アプリが送ってくる操作記録(Base64 → [先頭1バイト: 0=そのまま/1=圧縮] → (回数, dx, dy) の繰り返し)を、1ステップずつの [dx, dy, ...] に戻す */
export function decodeReplay(encoded: string, maxSteps: number): { moves: Int8Array; steps: number } | null {
  let data: Buffer;
  try { data = Buffer.from(encoded, "base64"); } catch { return null; }
  if (data.length < 4) return null;
  const flag = data[0];
  let rle: Buffer;
  try {
    if (flag === 1) rle = inflateRawSync(data.subarray(1), { maxOutputLength: maxSteps * 3 + 3 });
    else if (flag === 0) rle = data.subarray(1);
    else return null;
  } catch { return null; }
  if (rle.length % 3 !== 0) return null;
  const out = new Int8Array(maxSteps * 2);
  let steps = 0;
  for (let i = 0; i < rle.length; i += 3) {
    const n = rle[i]!;
    if (n === 0) return null;
    const dx = (rle[i + 1]! << 24) >> 24, dy = (rle[i + 2]! << 24) >> 24;
    if (steps + n > maxSteps) return null;
    for (let k = 0; k < n; k++) { out[steps * 2] = dx; out[steps * 2 + 1] = dy; steps++; }
  }
  return { moves: out, steps };
}
