import { inflateRawSync } from "node:zlib";
import { BEAM_SCRIPT, BLAST_SCRIPT, BOOMERANG_SCRIPT, GIANT_SCRIPT, MINE_SCRIPT, RECIPES, WEAVE_SCRIPT, ZIGZAG_SCRIPT, emitRecipe } from "./adpatterns.js";
import { pathPosition } from "./custompath.js";
import { FEATHER_DECAY, FEATHER_DECEL_SECONDS, FEATHER_SCRIPT, RING_SCRIPT, RING_START_RADIUS, SHARD_SCRIPT, emitFallenAngel, isFallenAngelPattern } from "./fallenangel.js";
import { CURVE_SCRIPT, HOLD_SCRIPT, LATERAL_SCRIPT, ORBIT_SCRIPT, WIND_SCRIPT, branchChildren, isDormant, lockBeam, stepBossScript } from "./bossscripts.js";
import { emitReaper, isReaperPattern } from "./reaper.js";
import { emitIceQueen, isIceQueenPattern } from "./icequeen.js";
import { FOLD_SCRIPT, SWAY_SCRIPT, emitKitsune, isKitsunePattern } from "./kitsune.js";
import { BOSS_MOVE_COUNT, PATTERNS, timeLimitSec, type Emitter, type LifeMode, type Mode, type Wave } from "./validate.js";

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
/** チャージビーム: ためる時間・撃つ時間(秒)と、当たる太さ(中心からの距離の2乗)。アプリの DanmakuConfig と同じ */
const BEAM_CHARGE = 1.0, BEAM_FIRE = 0.5, BEAM_HIT_R2 = 81;
/** 巨大弾の当たる範囲(中心からの距離の2乗)。アプリの DanmakuConfig.giantHitRadiusSquared と同じ */
const GIANT_HIT_R2 = 400;
/** ふつうの弾の当たる半径、爆風の当たる時間、地雷の爆風の半径と散る弾の数。アプリの DanmakuConfig と同じ */
/** ボス専用の弾の、弾そのものの半径(種類の順はアプリの BulletLook.Kind と同じ)と、自機の半径、専用の弾の最初の look */
const BULLET_BODY_R = [3, 3, 2.5, 4, 6, 3, 3, 2, 3, 3, 2.5, 3, 3, 2.5, 3.5, 4, 2.5, 2.5];
const PLAYER_R = 2.5, FIRST_SPECIAL_LOOK = 16;
export function lookHitDistance(look: number | undefined): number | undefined {
  if (look === undefined || look < FIRST_SPECIAL_LOOK) return undefined;
  const r = BULLET_BODY_R[Math.floor((look - FIRST_SPECIAL_LOOK) / 2)];
  return r === undefined ? undefined : r + PLAYER_R;
}
const HIT_R = 5.5, BLAST_ACTIVE = 0.35, MINE_BLAST_RADIUS = 30, MINE_RING = 8;

/** 爆風(隕石・地雷の爆発)が (px, py) に当たるか。予告(fuse 秒)のあと、1つで1回だけ */
export function blastHits(b: { x: number; y: number; age: number; bounces: number; radius?: number; fuse?: number }, px: number, py: number): boolean {
  if (b.age < (b.fuse ?? 0) || b.bounces <= 0) return false;
  const dx = px - b.x, dy = py - b.y;
  const r = (b.radius ?? 0) + HIT_R;
  return dx * dx + dy * dy < r * r;
}

/** 自機に当たる距離の2乗(弾の種類と広さで変わる)。アプリの Bullet.hitDistanceSquared と同じ */
export function hitDistanceSquared(b: Bullet): number {
  if (b.script === GIANT_SCRIPT) return GIANT_HIT_R2;
  const radius = b.radius ?? 0;
  if (radius > 0) { const r = radius + HIT_R; return r * r; }
  const lr = lookHitDistance(b.look);
  if (lr !== undefined) return lr * lr;
  return HIT_R2;
}

/** チャージビームが (px, py) に当たるか。撃っている間だけ、出る場所から向きのほうへ伸びる光線に触れると当たる(1本で1回だけ) */
export function beamHits(b: { x: number; y: number; vx: number; vy: number; age: number; bounces: number; maxSpeed?: number }, px: number, py: number): boolean {
  if (b.age < BEAM_CHARGE || b.bounces <= 0) return false;
  const rx = px - b.x, ry = py - b.y;
  const along = rx * b.vx + ry * b.vy;
  const len = b.maxSpeed ?? 0;
  let d2: number;
  if (along < 0) d2 = rx * rx + ry * ry;
  else if (len > 0 && along > len) {
    // 長さのある光線は、先の端より向こうには届かない
    const ex = px - (b.x + b.vx * len), ey = py - (b.y + b.vy * len);
    d2 = ex * ex + ey * ey;
  } else d2 = rx * rx + ry * ry - along * along;
  const rad = (b as { radius?: number }).radius ?? 0;
  return d2 < (rad > 0 ? rad * rad : BEAM_HIT_R2);
}
/** ボスの大きさ(小・中・大)ごとの、弾が当たる半径。アプリの DanmakuConfig.bossRadii と同じ */
const BOSS_RADII = [17, 24, 34] as const;
/** 専用の絵を持つボス(堕天使)。bossLook がこの番号のとき、位置と当たり半径が図形のボスと違う。アプリの BossCharacter と同じ */
/** 専用の絵を持つボス(堕天使 5・九尾 6)。位置と当たり判定はアプリの BossCharacter と同じ */
const FALLEN_ANGEL_LOOK = 5, KITSUNE_LOOK = 6, ICE_QUEEN_LOOK = 7, REAPER_LOOK = 8;
const FALLEN_ANGEL_RADIUS = 40;
const BOSS_MOVES = [{ a: 0, w: 0 }, { a: 0.25, w: 0.6 }, { a: 0.32, w: 1.3 }] as const;
/** ボスの動き(Swift の Simulation.bossPoint と同じ式) */
const WARP_POINTS = [[0.5, 0.18], [0.22, 0.26], [0.78, 0.16], [0.35, 0.12], [0.68, 0.30], [0.5, 0.22]] as const;
const WARP_PERIOD = 4, WARP_HOLD = 3.4;
export function bossPoint(move: number, rawT: number): { x: number; y: number } {
  const t = Math.max(0, rawT);
  switch (Math.min(Math.max(move, 0), BOSS_MOVE_COUNT - 1)) {
    case 3: return { x: W * 0.5, y: H * (0.2 + 0.09 * Math.sin(t * 0.9)) };
    case 4: return { x: W * 0.5 + 85 * Math.cos(t * 0.7), y: H * 0.2 + 45 * Math.sin(t * 0.7) };
    case 5: return { x: W * 0.5 + 115 * Math.sin(t * 0.6), y: H * 0.2 + 40 * Math.sin(t * 1.2) };
    case 6: {
      const k = Math.floor(t / WARP_PERIOD);
      const idx = k % WARP_POINTS.length;
      const f = t - k * WARP_PERIOD;
      const a = WARP_POINTS[idx]!, b = WARP_POINTS[(idx + 1) % WARP_POINTS.length]!;
      if (f <= WARP_HOLD) return { x: W * a[0], y: H * a[1] };
      const u = (f - WARP_HOLD) / (WARP_PERIOD - WARP_HOLD);
      const s = u * u * (3 - 2 * u);
      return { x: W * (a[0] + (b[0] - a[0]) * s), y: H * (a[1] + (b[1] - a[1]) * s) };
    }
    case 7: return { x: W * 0.5 + 85 * Math.cos(t * 0.7), y: H * 0.2 - 45 * Math.sin(t * 0.7) };
    case 8: return { x: W * 0.5 - 115 * Math.sin(t * 0.6), y: H * 0.2 + 40 * Math.sin(t * 1.2) };
    case 9: case 10: {
      const bm = BOSS_MOVES[Math.min(Math.max(move, 0), 10) - 8]!;
      return { x: W * (0.5 - bm.a * Math.sin(t * bm.w)), y: H * 0.18 };
    }
    default: {
      const bm = BOSS_MOVES[Math.min(Math.max(move, 0), 2)]!;
      return { x: W * (0.5 + bm.a * Math.sin(t * bm.w)), y: H * 0.18 };
    }
  }
}

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
  bossLook?: number | null;
  awaken?: number | null;
  bossX?: number | null;
  bossY?: number | null;
}

/** 1つの場面。連戦以外は、ステージ全体が「場面1つ」 */
interface Spec { boss: boolean; damage: boolean; limit: number; hp: number; move: number; emitters: Emitter[]; size: number; look: number; awaken?: number; homeDX: number; homeDY: number }
const INTERMISSION = 1.5;

function specsOf(st: SimStage): Spec[] {
  if (st.mode === "sequence" && st.waves && st.waves.length > 0) {
    return st.waves.map((w) => ({ boss: w.kind === "boss", damage: false, limit: w.durationSec, hp: w.bossHp ?? 0, move: w.bossMove ?? 0, emitters: w.emitters, size: w.bossSize ?? 1, look: w.bossLook ?? 0, awaken: w.awaken, homeDX: ((w.bossX ?? 0.5) - 0.5) * W, homeDY: ((w.bossY ?? 0.2) - 0.2) * H }));
  }
  return [{ boss: st.mode !== "survive", damage: st.mode === "damage", limit: timeLimitSec(st.mode, st.durationSec), hp: st.bossHp ?? 0, move: st.bossMove ?? 0, emitters: st.emitters, size: st.bossSize ?? 1, look: st.bossLook ?? 0, awaken: st.awaken ?? undefined, homeDX: ((st.bossX ?? 0.5) - 0.5) * W, homeDY: ((st.bossY ?? 0.2) - 0.2) * H }];
}

export type Outcome = "playing" | "cleared" | "hit" | "timeUp";
export interface SimResult { outcome: Outcome; tick: number; hp: number; damage: number; lifeLeft: number; wave: number; defeats: number; bulletCount: number; bulletHash: number; bulletHashCoarse: number }

// --- 乱数(mulberry32)とハッシュ(FNV-1a)
export interface Rng { (): number; state: number }
export function mulberry(seed: number): Rng {
  const f = (() => {
    f.state = (f.state + 0x6d2b79f5) >>> 0;
    const a = f.state;
    let t = Math.imul(a ^ (a >>> 15), 1 | a) >>> 0;
    t = ((t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t) >>> 0;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  }) as Rng;
  f.state = seed >>> 0;
  return f;
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
interface Bullet {
  x: number; y: number; vx: number; vy: number; color: number; turn: number; homeLeft: number; accel: number; maxSpeed: number; bounces: number; script: number; age: number; follow?: Follow;
  /** 重力弾・膨らむ泡・地雷・爆風だけが使う(ない弾は 0 と同じ)。アプリの Bullet と同じ意味 */
  gravity?: number; radius?: number; grow?: number; growMax?: number; fuse?: number;
  /** スワイプ弾幕: もうかすった弾(1発で1回だけ数える) */
  grazed?: boolean;
  /** 見た目の番号。16 以上はボス専用の弾で、種類ごとに当たる半径が決まる(アプリの BulletLook と同じ) */
  look?: number;
  /** 堕天使の技だけが使う予備の数値(羽・破片・閉じる輪)。アプリの Bullet と同じ意味 */
  u0?: number; u1?: number; u2?: number; u3?: number;
}
interface Shot { x: number; y: number; vx: number; damage: number }

/** 左右反転(線対称)。アプリの Bullet.mirrorX と同じ */
function mirrorBullet(b: Bullet) {
  b.x = W - b.x; b.vx = -b.vx;
  switch (b.script) {
    case BEAM_SCRIPT: case BOOMERANG_SCRIPT: case WEAVE_SCRIPT: case ZIGZAG_SCRIPT: b.turn = -b.turn; break;
    case SHARD_SCRIPT: case RING_SCRIPT: b.u0 = W - (b.u0 ?? 0); b.u2 = Math.PI - (b.u2 ?? 0); b.turn = -b.turn; break;
    case FOLD_SCRIPT: b.u1 = -(b.u1 ?? 0); break;
    case SWAY_SCRIPT: if ((b.u3 ?? 0) !== 1) b.u2 = -(b.u2 ?? 0); break;
    case HOLD_SCRIPT: b.u1 = b.u2 === 1 ? -(b.u1 ?? 0) : Math.PI - (b.u1 ?? 0); break;
    case WIND_SCRIPT: case CURVE_SCRIPT: b.u0 = -(b.u0 ?? 0); break;
    case ORBIT_SCRIPT: b.u0 = W - (b.u0 ?? 0); b.u2 = Math.PI - (b.u2 ?? 0); b.u3 = -(b.u3 ?? 0); break;
    case LATERAL_SCRIPT: b.u0 = Math.PI - (b.u0 ?? 0); b.u2 = -(b.u2 ?? 0); break;
    default: break;
  }
  if (b.follow) b.follow.ox = W - b.follow.ox;
}

/** 弾を出す。mir === 1 のときは、左右を反転した世界で撃って、出た弾を反転して戻す(アプリの Emit.emit と同じ) */
function emit(m: Emitter, k: number, cx: number, cy: number, px: number, py: number, rng: () => number, out: Bullet[], awakened = false, salt = 0) {
  if (m.mir !== 1) { emitCore(m, k, cx, cy, px, py, rng, out, awakened, salt); return; }
  const before = out.length;
  emitCore(m, k, W - cx, cy, W - px, py, rng, out, awakened, salt);
  for (let j = before; j < out.length; j++) mirrorBullet(out[j]!);
}

function emitCore(m: Emitter, k: number, cx: number, cy: number, px: number, py: number, rng: () => number, out: Bullet[], awakened = false, salt = 0) {
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
      if (isReaperPattern(m.t)) { emitReaper(m, k, cx, cy, px, py, rng, out, awakened, salt, MAX_BULLETS); break; }
      if (isIceQueenPattern(m.t)) { emitIceQueen(m, k, cx, cy, px, py, rng, out, awakened, salt, MAX_BULLETS); break; }
      if (isKitsunePattern(m.t)) { emitKitsune(m, k, cx, cy, px, py, rng, out, awakened, salt, MAX_BULLETS); break; }
      if (isFallenAngelPattern(m.t)) { emitFallenAngel(m, k, cx, cy, px, py, rng, out, awakened, salt, MAX_BULLETS); break; }
      // 広告で解放するパターン: 弾の出し方の表に従う
      const recipe = RECIPES[m.t];
      if (recipe) {
        emitRecipe(recipe, m, k, cx, cy, px, py, off, sp, n, rng, HOMING_SECONDS, (x, y, vx, vy, e) => {
          if (out.length < MAX_BULLETS) {
            out.push({ x, y, vx, vy, color: m.k, turn: e.turn, homeLeft: e.homeLeft, accel: e.accel, maxSpeed: e.maxSpeed, bounces: e.bounces, script: e.script, age: 0,
              gravity: e.gravity, radius: e.radius, grow: e.grow, growMax: e.growMax, fuse: e.fuse });
          }
        });
      }
    }
  }
}

const clamp = (v: number, lo: number, hi: number) => Math.min(hi, Math.max(lo, v));
const LIVES_RANGE = [1, 5] as const, HP_RANGE = [3, 20] as const;

/** 操作記録(dx, dy は 0.25 論理px 単位)を再生して、結果を返す。入力が尽きたら動かさずに続ける */
/** 1ステップごとの弾の様子(分析用。ランキングの確認では使わない) */
export type StepObserver = (tick: number, bullets: readonly { x: number; y: number; vx: number; vy: number; script: number; radius?: number }[], player: { x: number; y: number }) => void;

export interface SwipeOptions { swipe?: boolean }

/** かする距離の2乗(アプリの Bullet.grazeDistanceSquared と同じ)。ふつうの弾は 18px、巨大弾や広さのある弾は当たる広さ + 12.5px */
const GRAZE_MARGIN = 12.5;
export function grazeDistanceSquared(b: Bullet): number {
  const radius = b.radius ?? 0;
  if (b.script !== GIANT_SCRIPT && radius === 0 && (b.look ?? 0) < FIRST_SPECIAL_LOOK) { const r = HIT_R + GRAZE_MARGIN; return r * r; }
  const r = Math.sqrt(hitDistanceSquared(b)) + GRAZE_MARGIN;
  return r * r;
}

/**
 * 1 ステップずつ進められるゲーム計算。`simulate` はこれを最後まで回すだけ。
 * `swipe: true` はスワイプ弾幕用(ライフ 1・自機はショットを撃たない・ボスの場面は「ダメージ勝負」と同じ扱い)
 */
export function createSim(stage: SimStage, shotType: ShotType = "standard", observe?: StepObserver, opts: SwipeOptions = {}) {
  const swipe = opts.swipe === true;
  const specs = specsOf(stage);
  if (swipe) for (const sp of specs) if (sp.boss) sp.damage = true;
  let wi = 0;
  const spec = () => specs[wi]!;
  const lifeMode: LifeMode = swipe ? "lives" : (stage.lifeMode ?? "lives");
  const range = lifeMode === "lives" ? LIVES_RANGE : HP_RANGE;
  const lifeMax = swipe ? 1 : clamp(stage.lifeCount ?? 1, range[0], range[1]);
  let lifeLeft = lifeMax;
  let hp = specs[0]!.hp;
  let damage = 0;
  let defeats = 0;
  const shotDef = SHOTS[shotType];
  const salt = stageSeed(stage);
  const rng = mulberry(salt);
  let next = specs[0]!.emitters.map((m) => m.s);
  let shotCount = specs[0]!.emitters.map(() => 0);
  let bullets: Bullet[] = [];
  let shots: Shot[] = [];
  let tick = 0, t = -READY, waveStart = 0;
  let px = W / 2, py = H * 0.85;
  let phase = 1, banner = 0, flash = 0, cooldown = 0, shieldUntil = 0;
  let outcome: Outcome = "playing";
  let invincible = false, countsGrazes = true, grazeCount = 0;
  let grazedThisStep: Bullet[] = [];

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

  /** 1 ステップ(1/120 秒)進める。dx0, dy0 は 0.25 論理px 単位。終了後は何もしない */
  const step = (dx0: number, dy0: number): void => {
    if (outcome !== "playing") return;
    grazedThisStep = [];
    const dt = STEP;
    tick += 1;
    t += dt;
    px = clamp(px + dx0 * MOVE_UNIT, 6, W - 6);
    py = clamp(py + dy0 * MOVE_UNIT, 6, H - 6);

    const sp = spec();
    const waveT = t - waveStart;
    const angel = sp.look === FALLEN_ANGEL_LOOK || sp.look === KITSUNE_LOOK || sp.look === ICE_QUEEN_LOOK || sp.look === REAPER_LOOK;
    const wt = Math.max(0, waveT);
    let bp = sp.boss && !angel ? bossPoint(sp.move, wt) : { x: 0, y: 0 };
    if (sp.boss && !angel && (sp.homeDX !== 0 || sp.homeDY !== 0)) {
      bp = { x: Math.min(Math.max(bp.x + sp.homeDX, 24), W - 24), y: Math.min(Math.max(bp.y + sp.homeDY, 24), H * 0.5) };
    }
    const bx = !sp.boss ? 0 : angel ? W / 2 + Math.sin(wt * 60 * 0.012) * 30 : bp.x;
    const by = !sp.boss ? 0 : angel ? 128 + Math.sin(wt * 60 * 0.02) * 5 : bp.y;
    const bossRadius = angel ? FALLEN_ANGEL_RADIUS : BOSS_RADII[Math.min(Math.max(sp.size, 0), 2)]!;
    if (sp.boss) {
      const ph = phaseOf(waveT);
      if (ph !== phase) {
        phase = ph;
        if (ph > 1) { bullets = []; banner = 1.2; }
      }
      if (banner > 0) banner -= dt;
      cooldown -= dt;
      if (!swipe && waveT >= 0 && cooldown <= 0) {
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
        if (dx * dx + dy * dy < bossRadius ** 2) {
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
        return;
      }
    }

    if (waveT >= 0) {
      sp.emitters.forEach((m, idx) => {
        if (sp.boss) {
          if (!(m.ph === 0 || m.ph === phase) || banner > 0) { next[idx] = waveT; return; }
          while (waveT >= next[idx]!) {
            emit(m, shotCount[idx]!, m.t === "rain" ? 0 : m.p === 1 ? m.x * W : bx, m.p === 1 ? m.y * H : by, px, py, rng, bullets,
              sp.boss && sp.awaken !== undefined && phase >= sp.awaken, salt);
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
      const bm = stepBossScript(b, dt, px, py);
      if (bm === "gone") continue;
      if (bm === "burst") {
        for (const c of branchChildren(b)) {
          if (w + born.length + (bullets.length - i - 1) >= MAX_BULLETS) break;
          born.push(c as Bullet);
        }
        continue;
      }
      if (bm === "alive") {
        // 専用の弾の動き(上で進めた)
      } else if (b.script === BEAM_SCRIPT) {
        // チャージビーム: 動かない。ためて、撃って、消える。当たっても光線は消えない。なぎ払いは、撃っている間だけ首を振る
        b.age += dt;
        if (b.age >= BEAM_CHARGE + (b.homeLeft > 0 ? b.homeLeft : BEAM_FIRE)) continue;
        if ((b.u0 ?? 0) > 0 && b.age < (b.u0 ?? 0)) lockBeam(b, px, py);
        if (b.turn !== 0 && b.age >= BEAM_CHARGE) {
          const na = Math.atan2(b.vy, b.vx) + b.turn * dt;
          b.vx = Math.cos(na); b.vy = Math.sin(na);
        }
        if (beamHits(b, px, py) && !(invincible || tick < shieldUntil)) {
          b.bounces = 0;
          lifeLeft -= 1;
          if (lifeLeft <= 0) { outcome = "hit"; died = true; break; }
          if (lifeMode === "lives") shieldUntil = tick + Math.round(LIFE_SHIELD_SECONDS / dt);
        }
        bullets[w++] = b;
        continue;
      }
      if (bm !== "alive" && b.script === BLAST_SCRIPT) {
        // 爆風: 動かない。予告(fuse 秒)のあと、少しの間だけ当たって消える。当たっても消えない(1回だけ)
        b.age += dt;
        if (b.age >= (b.fuse ?? 0) + BLAST_ACTIVE) continue;
        if (blastHits(b, px, py) && !(invincible || tick < shieldUntil)) {
          b.bounces = 0;
          lifeLeft -= 1;
          if (lifeLeft <= 0) { outcome = "hit"; died = true; break; }
          if (lifeMode === "lives") shieldUntil = tick + Math.round(LIFE_SHIELD_SECONDS / dt);
        }
        bullets[w++] = b;
        continue;
      }
      if (bm === "alive") {
        // 専用の弾の動き(上で進めた)
      } else if (b.script === FEATHER_SCRIPT) {
        // 羽: 減速して止まり、そのあと左右に揺れながら、だんだん速く落ちる
        b.age += dt;
        if (b.age < FEATHER_DECEL_SECONDS) { b.vx *= FEATHER_DECAY; b.vy *= FEATHER_DECAY; }
        else {
          if ((b.u0 ?? 0) === 0) { b.u0 = 1; b.vx = 0; b.vy = 12; }
          b.vy = Math.min(b.vy + 180 * dt, b.maxSpeed);
          b.vx = Math.sin((b.age * 60 + (b.fuse ?? 0)) * 0.07) * 54;
        }
        b.x += b.vx * dt; b.y += b.vy * dt;
      } else if (b.script === SHARD_SCRIPT) {
        // 破片: 光輪から輪の形に広がり、回って、時間が来た順に自機へ突進する
        b.age += dt;
        if (b.age >= b.homeLeft) {
          const a = Math.atan2(py - b.y, px - b.x);
          b.vx = Math.cos(a) * (b.u3 ?? 0); b.vy = Math.sin(a) * (b.u3 ?? 0);
          b.script = 0; b.turn = 0; b.homeLeft = 0; b.maxSpeed = 0;
        } else {
          const q = 1 - Math.min(1, b.age / 0.4);
          const e = 1 - q * q * q;
          const ang = (b.u2 ?? 0) + b.turn * Math.max(0, b.age - 0.4);
          b.x = (b.u0 ?? 0) + Math.cos(ang) * b.maxSpeed * e;
          b.y = (b.u1 ?? 0) + Math.sin(ang) * b.maxSpeed * e * 0.8;
        }
      } else if (b.script === FOLD_SCRIPT) {
        // 御札: 決まった時間で直角に折れる(覚醒すると、もう一度逆に折れてジグザグになる)
        b.age += dt;
        if (b.homeLeft === 0 && b.age >= (b.u0 ?? 0)) {
          const sp = Math.sqrt(b.vx * b.vx + b.vy * b.vy) * (b.u3 ?? 1);
          const na = Math.atan2(b.vy, b.vx) + (b.u1 ?? 0);
          b.vx = Math.cos(na) * sp; b.vy = Math.sin(na) * sp;
          b.homeLeft = 1;
        } else if (b.homeLeft === 1 && (b.u2 ?? 0) > 0 && b.age >= (b.u2 ?? 0)) {
          const sp = Math.sqrt(b.vx * b.vx + b.vy * b.vy);
          const na = Math.atan2(b.vy, b.vx) - (b.u1 ?? 0);
          b.vx = Math.cos(na) * sp; b.vy = Math.sin(na) * sp;
          b.homeLeft = 2;
        }
        b.x += b.vx * dt; b.y += b.vy * dt;
      } else if (b.script === SWAY_SCRIPT) {
        // 揺れる弾: 横に揺れながら、まっすぐ落ちる
        b.age += dt;
        const sw = (b.u0 ?? 0) + b.age * 60 * (b.u1 ?? 0);
        if (b.u3 === 1) b.vy = Math.cos(sw) * (b.u2 ?? 0);
        else if (b.u3 === 2) b.vx = Math.cos(sw) * (b.u2 ?? 0);
        else b.vx = Math.sin(sw) * (b.u2 ?? 0);
        b.x += b.vx * dt; b.y += b.vy * dt;
      } else if (b.script === RING_SCRIPT) {
        // 閉じてくる輪: 中心へ向かって縮む(回る輪もある)。中心に着いたら消える
        b.age += dt;
        if (b.age >= (b.fuse ?? 0)) continue;
        const rad = RING_START_RADIUS - (b.u3 ?? 0) * b.age;
        const ang = (b.u2 ?? 0) + b.turn * b.age;
        b.x = (b.u0 ?? 0) + Math.cos(ang) * rad;
        b.y = (b.u1 ?? 0) + Math.sin(ang) * rad;
      } else if (b.script === MINE_SCRIPT) {
        // 地雷: 決まった時間だけ進んで止まり、時間が来たら爆風と弾の輪になって消える
        b.age += dt;
        if (b.age >= (b.fuse ?? 0)) {
          const speed = Math.sqrt(b.vx * b.vx + b.vy * b.vy);
          const base = Math.atan2(b.vy, b.vx);
          const frags: Bullet[] = [{ x: b.x, y: b.y, vx: 0, vy: 0, color: b.color, turn: 0, homeLeft: 0, accel: 0, maxSpeed: 0, bounces: 1, script: BLAST_SCRIPT, age: 0, radius: MINE_BLAST_RADIUS, fuse: 0 }];
          for (let j = 0; j < MINE_RING; j++) {
            const a = base + (j * 2 * Math.PI) / MINE_RING;
            frags.push({ x: b.x, y: b.y, vx: Math.cos(a) * speed, vy: Math.sin(a) * speed, color: b.color, turn: 0, homeLeft: 0, accel: 0, maxSpeed: 0, bounces: 0, script: 0, age: 0 });
          }
          const room = Math.max(0, MAX_BULLETS - (w + born.length + (bullets.length - i - 1)));
          for (const f of frags.slice(0, room)) born.push(f);
          continue;
        }
        if (b.age < b.homeLeft) { b.x += b.vx * dt; b.y += b.vy * dt; }
      } else if (b.script === WEAVE_SCRIPT || b.script === ZIGZAG_SCRIPT) {
        const speed = Math.sqrt(b.vx * b.vx + b.vy * b.vy);
        if (b.script === WEAVE_SCRIPT) {
          // 蛇行: なめらかに曲がり続け、決まった時間ごとに曲がる向きを逆にする
          if (b.homeLeft <= 0) { b.turn = -b.turn; b.homeLeft += b.fuse ?? 0; }
          const na = Math.atan2(b.vy, b.vx) + b.turn * dt;
          b.vx = Math.cos(na) * speed; b.vy = Math.sin(na) * speed;
          b.homeLeft -= dt;
        } else {
          // ジグザグ: 決まった時間ごとに、カクッと向きを折る(次は逆に)
          b.homeLeft -= dt;
          if (b.homeLeft <= 0) {
            const na = Math.atan2(b.vy, b.vx) + b.turn;
            b.vx = Math.cos(na) * speed; b.vy = Math.sin(na) * speed;
            b.turn = -b.turn;
            b.homeLeft += b.fuse ?? 0;
          }
        }
        b.x += b.vx * dt; b.y += b.vy * dt;
        if (b.bounces > 0) {
          if (b.x < 0) { b.x = -b.x; b.vx = -b.vx; b.bounces -= 1; }
          else if (b.x > W) { b.x = 2 * W - b.x; b.vx = -b.vx; b.bounces -= 1; }
        }
      } else if (b.script === BOOMERANG_SCRIPT) {
        // ブーメラン: 決まった時間だけ、同じ速さのまま向きを回して、弧を描いて戻ってくる
        if (b.homeLeft > 0) {
          const na = Math.atan2(b.vy, b.vx) + b.turn * dt;
          const speed = Math.sqrt(b.vx * b.vx + b.vy * b.vy);
          b.vx = Math.cos(na) * speed;
          b.vy = Math.sin(na) * speed;
          b.homeLeft -= dt;
        }
        b.x += b.vx * dt; b.y += b.vy * dt;
        if (b.bounces > 0) {
          if (b.x < 0) { b.x = -b.x; b.vx = -b.vx; b.bounces -= 1; }
          else if (b.x > W) { b.x = 2 * W - b.x; b.vx = -b.vx; b.bounces -= 1; }
        }
      } else if (b.follow) {
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
        } else if (b.script === 3) {
          if (b.age >= TIMED_HOLD) b.script = 0; else frozen = true;
        }   // 巨大弾など、時間で動きが変わらない印は、ここでは何もしない
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
      if (b.gravity) b.vy += b.gravity * dt;
      if (b.grow) b.radius = Math.min(b.growMax ?? 0, (b.radius ?? 0) + b.grow * dt);
      if (!frozen) { b.x += b.vx * dt; b.y += b.vy * dt; }
      if (b.bounces > 0) {
        if (b.x < 0) { b.x = -b.x; b.vx = -b.vx; b.bounces -= 1; }
        else if (b.x > W) { b.x = 2 * W - b.x; b.vx = -b.vx; b.bounces -= 1; }
      }
      }
      if (isDormant(b)) { bullets[w++] = b; continue; }
      if (b.script !== RING_SCRIPT && (b.x < -20 || b.x > W + 20 || b.y < -20 || b.y > H + 20)) continue;
      const dx = b.x - px, dy = b.y - py;
      if (dx * dx + dy * dy < hitDistanceSquared(b)) {
        if (invincible || tick < shieldUntil) continue;
        lifeLeft -= 1;
        if (lifeLeft <= 0) { outcome = "hit"; died = true; break; }   // その場で終了(弾の並びはそのまま)
        if (lifeMode === "lives") shieldUntil = tick + Math.round(LIFE_SHIELD_SECONDS / dt);
        continue;   // 当たった弾は消える
      }
      if (countsGrazes && !b.grazed && dx * dx + dy * dy < grazeDistanceSquared(b)) {
        b.grazed = true;
        grazeCount += 1;
        grazedThisStep.push(b);
      }
      bullets[w++] = b;
    }
    if (died) return;
    bullets.length = w;
    for (const nb of born) bullets.push(nb);
    observe?.(tick, bullets, { x: px, y: py });
    if (waveT >= sp.limit) {
      if (wi + 1 < specs.length) {
        // 連戦の途中: ボスの場面は、時間切れで失敗。生き残る場面は、クリアして次へ
        if (sp.boss && !sp.damage) outcome = "timeUp"; else advanceWave(dt);
      } else {
        outcome = sp.boss && !sp.damage ? "timeUp" : "cleared";
      }
    }
  };

  const result = (): SimResult => {
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
  };

  // --- スワイプ弾幕用(仕様書 3.2 章)。本編では使わない
  /** 自機を置く(画面の端から 6px の内側に収める) */
  const place = (x: number, y: number) => { px = clamp(x, 6, W - 6); py = clamp(y, 6, H - 6); };
  /** 弾も時間も止めたまま、自機だけ動かす(クリップの「GO」の間) */
  const nudgePlayer = (dx: number, dy: number) => place(px + dx * MOVE_UNIT, py + dy * MOVE_UNIT);
  /** 次の steps ステップの間、被弾しない(バリア) */
  const giveShield = (steps: number) => { shieldUntil = Math.max(shieldUntil, tick + steps + 1); };
  const clearBullets = () => { bullets = []; };
  /** 自機を動かさず、無敵で、かすりも数えずに target ステップ目まで進める */
  const fastForward = (target: number) => {
    const was = [invincible, countsGrazes] as const;
    invincible = true; countsGrazes = false;
    while (outcome === "playing" && tick < target) step(0, 0);
    invincible = was[0]; countsGrazes = was[1];
  };

  /** 状態を丸ごと控える/戻す(ボットが先読みするため)。控えは入れ替わらない値のコピー */
  type Snap = { wi: number; lifeLeft: number; hp: number; damage: number; defeats: number; next: number[]; shotCount: number[]; bullets: Bullet[]; shots: Shot[]; tick: number; t: number; waveStart: number; px: number; py: number; phase: number; banner: number; flash: number; cooldown: number; shieldUntil: number; outcome: Outcome; grazeCount: number; rng: number };
  const snapshot = (): Snap => ({ wi, lifeLeft, hp, damage, defeats, next: [...next], shotCount: [...shotCount], bullets: bullets.map((b) => ({ ...b })), shots: shots.map((x) => ({ ...x })), tick, t, waveStart, px, py, phase, banner, flash, cooldown, shieldUntil, outcome, grazeCount, rng: rng.state });
  const restore = (c: Snap) => {
    wi = c.wi; lifeLeft = c.lifeLeft; hp = c.hp; damage = c.damage; defeats = c.defeats; next = [...c.next]; shotCount = [...c.shotCount];
    bullets = c.bullets.map((b) => ({ ...b })); shots = c.shots.map((x) => ({ ...x }));
    tick = c.tick; t = c.t; waveStart = c.waveStart; px = c.px; py = c.py; phase = c.phase; banner = c.banner; flash = c.flash; cooldown = c.cooldown;
    shieldUntil = c.shieldUntil; outcome = c.outcome; grazeCount = c.grazeCount; rng.state = c.rng; grazedThisStep = [];
  };

  return {
    snapshot, restore, step, result, place, nudgePlayer, giveShield, clearBullets, fastForward,
    get tick() { return tick; },
    get outcome() { return outcome; },
    get bullets(): readonly Bullet[] { return bullets; },
    get player() { return { x: px, y: py }; },
    get grazeCount() { return grazeCount; },
    get grazedThisStep(): readonly Bullet[] { return grazedThisStep; },
    setInvincible(v: boolean) { invincible = v; },
    setCountsGrazes(v: boolean) { countsGrazes = v; },
    get isIntermission() { return wi > 0 && t - waveStart < 0; },
    get waveLimitTicks() { return (timeLimitSec(stage.mode, stage.durationSec) + 3) * 120 + 144; },
  };
}

export function simulate(stage: SimStage, moves: ArrayLike<number>, moveCount: number, shotType: ShotType = "standard", observe?: StepObserver): SimResult {
  const sim = createSim(stage, shotType, observe);
  const limit = sim.waveLimitTicks;
  while (sim.outcome === "playing" && sim.tick < limit) {
    const k = sim.tick;
    sim.step(k < moveCount ? moves[k * 2]! : 0, k < moveCount ? moves[k * 2 + 1]! : 0);
  }
  return sim.result();
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
