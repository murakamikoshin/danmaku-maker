import { inflateRawSync } from "node:zlib";
import { PATTERNS, timeLimitSec, type Emitter, type LifeMode, type Mode } from "./validate.js";

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
}

export type Outcome = "playing" | "cleared" | "hit" | "timeUp";
export interface SimResult { outcome: Outcome; tick: number; hp: number; damage: number; lifeLeft: number; bulletCount: number; bulletHash: number }

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
  h.addInt32(st.mode === "boss" ? 1 : st.mode === "damage" ? 2 : 0);
  h.addInt32(st.bossHp ?? 0);
  h.addInt32(st.bossMove ?? 0);
  h.addInt32(st.durationSec);
  for (const m of st.emitters) {
    h.addInt32((PATTERNS as readonly string[]).indexOf(m.t));
    for (const q of [m.x, m.y, m.s, m.e, m.i, m.v]) h.addInt32(Math.round(q * 100));
    h.addInt32(m.c); h.addInt32(Math.round(m.r)); h.addInt32(m.k); h.addInt32(m.ph);
    if (m.p) h.addInt32(m.p);   // 標準(0)のときは混ぜない: アプリの Stage.seed と同じ
  }
  return h.value;
}

interface Bullet { x: number; y: number; vx: number; vy: number; color: number; turn: number; homeLeft: number }
interface Shot { x: number; y: number; vx: number; damage: number }

function emit(m: Emitter, k: number, cx: number, cy: number, px: number, py: number, rng: () => number, out: Bullet[]) {
  const sp = m.v * 60;
  const n = Math.max(1, m.c);
  const deg = Math.PI / 180;
  const add = (x: number, y: number, a: number) => {
    if (out.length < MAX_BULLETS) out.push({ x, y, vx: Math.cos(a) * sp, vy: Math.sin(a) * sp, color: m.k, turn: 0, homeLeft: 0 });
  };
  switch (m.t) {
    case "ring": case "spiral":
      for (let j = 0; j < n; j++) add(cx, cy, (j * 2 * Math.PI) / n + k * m.r * deg);
      break;
    case "aim": {
      const b = Math.atan2(py - cy, px - cx);
      for (let j = 0; j < n; j++) add(cx, cy, b + (n > 1 ? (j / (n - 1) - 0.5) * m.r * deg : 0));
      break;
    }
    case "rain":
      for (let j = 0; j < n; j++) { const x = rng() * W; const a = Math.PI / 2 + (rng() - 0.5) * 0.3; add(x, -8, a); }
      break;
    case "homing": {
      const b = Math.atan2(py - cy, px - cx);
      const turn = Math.max(25, Math.abs(m.r) * 2) * deg;
      for (let j = 0; j < n; j++) {
        const a = b + (j - (n - 1) / 2) * 0.35;
        if (out.length < MAX_BULLETS) out.push({ x: cx, y: cy, vx: Math.cos(a) * sp, vy: Math.sin(a) * sp, color: m.k, turn, homeLeft: HOMING_SECONDS });
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
  }
}

const clamp = (v: number, lo: number, hi: number) => Math.min(hi, Math.max(lo, v));
const LIVES_RANGE = [1, 5] as const, HP_RANGE = [3, 20] as const;

/** 操作記録(dx, dy は 0.25 論理px 単位)を再生して、結果を返す。入力が尽きたら動かさずに続ける */
export function simulate(stage: SimStage, moves: ArrayLike<number>, moveCount: number, shotType: ShotType = "standard"): SimResult {
  const isBoss = stage.mode !== "survive";
  const isDamage = stage.mode === "damage";
  const lifeMode: LifeMode = stage.lifeMode ?? "lives";
  const range = lifeMode === "lives" ? LIVES_RANGE : HP_RANGE;
  const lifeMax = clamp(stage.lifeCount ?? 1, range[0], range[1]);
  let lifeLeft = lifeMax;
  let hp = stage.bossHp ?? 0;
  let damage = 0;
  const shotDef = SHOTS[shotType];
  const rng = mulberry(stageSeed(stage));
  const next = stage.emitters.map((m) => m.s);
  const shotCount = stage.emitters.map(() => 0);
  let bullets: Bullet[] = [];
  const shots: Shot[] = [];
  let tick = 0, t = -READY;
  let px = W / 2, py = H * 0.85;
  let phase = 1, banner = 0, flash = 0, cooldown = 0, shieldUntil = 0;
  let outcome: Outcome = "playing";
  const limitSec = timeLimitSec(stage.mode, stage.durationSec);
  const limit = (limitSec + 3) * 120 + 144;
  const bm = BOSS_MOVES[stage.bossMove ?? 0] ?? BOSS_MOVES[0];

  const phaseOf = () => {
    if (isDamage) { const f = Math.max(0, t) / stage.durationSec; return f < 1 / 3 ? 1 : f < 2 / 3 ? 2 : 3; }
    const r = hp / (stage.bossHp ?? 1);
    return r > 2 / 3 ? 1 : r > 1 / 3 ? 2 : 3;
  };

  while (outcome === "playing" && tick < limit) {
    const dx0 = tick < moveCount ? moves[tick * 2]! : 0;
    const dy0 = tick < moveCount ? moves[tick * 2 + 1]! : 0;
    const dt = STEP;
    tick += 1;
    t += dt;
    px = clamp(px + dx0 * MOVE_UNIT, 6, W - 6);
    py = clamp(py + dy0 * MOVE_UNIT, 6, H - 6);

    const bx = isBoss ? W * (0.5 + bm.a * Math.sin(Math.max(0, t) * bm.w)) : 0;
    const by = isBoss ? H * 0.18 : 0;
    if (isBoss) {
      const ph = phaseOf();
      if (ph !== phase) {
        phase = ph;
        if (ph > 1) { bullets = []; banner = 1.2; }
      }
      if (banner > 0) banner -= dt;
      cooldown -= dt;
      if (t >= 0 && cooldown <= 0) {
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
        if (dx * dx + dy * dy < 24 * 24) {
          damage += s.damage;
          if (!isDamage) hp -= s.damage;
          flash = 0.06; continue;
        }
        shots[w++] = s;
      }
      shots.length = w;
      if (flash > 0) flash -= dt;
      if (!isDamage && hp <= 0) { outcome = "cleared"; break; }
    }

    if (t >= 0) {
      stage.emitters.forEach((m, idx) => {
        if (isBoss) {
          if (!(m.ph === 0 || m.ph === phase) || banner > 0) { next[idx] = t; return; }
          while (t >= next[idx]!) {
            emit(m, shotCount[idx]!, m.t === "rain" ? 0 : m.p === 1 ? m.x * W : bx, m.p === 1 ? m.y * H : by, px, py, rng, bullets);
            shotCount[idx]!++;
            next[idx]! += Math.max(0.05, m.i);
          }
        } else {
          const end = Math.min(m.e, stage.durationSec);
          while (t >= next[idx]! && next[idx]! < end) {
            emit(m, shotCount[idx]!, m.x * W, m.y * H, px, py, rng, bullets);
            shotCount[idx]!++;
            next[idx]! += Math.max(0.05, m.i);
          }
        }
      });
    }

    let w = 0;
    let died = false;
    for (let i = 0; i < bullets.length; i++) {
      const b = bullets[i]!;
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
      b.x += b.vx * dt;
      b.y += b.vy * dt;
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
    if (t >= limitSec) outcome = isBoss && !isDamage ? "timeUp" : "cleared";
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
  return { outcome, tick, hp, damage, lifeLeft, bulletCount: bullets.length, bulletHash: h.value };
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
