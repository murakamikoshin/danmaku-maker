/**
 * 弾幕パック3(1.4.2)の11パターン。弾の出し方と、専用の弾の動き(印 = script 40〜44)。
 * アプリの DanmakuCore/Sources/DanmakuCore/Pack3Patterns.swift と同じ計算(式を変えたら、両方を直して照合データを作り直す)。
 */
import { BEAM_SCRIPT, BLAST_SCRIPT } from "./adpatterns.js";
import { type BossBullet } from "./bossscripts.js";
import { type Emitter } from "./validate.js";

const W = 360, H = 540;

export const PACK3_PATTERNS = ["radialLaser", "lightning", "carpetBomb", "dashShot", "implode", "pincer", "whirlwind", "bounceBall", "needle", "trackLaser", "blinkShot"] as const;
export const isPack3Pattern = (t: string): boolean => (PACK3_PATTERNS as readonly string[]).includes(t);

export const DASH_SCRIPT = 40, BLINK_SCRIPT = 41, WHIRL_SCRIPT = 42, FLOOR_BOUNCE_SCRIPT = 43, IMPLODE_SCRIPT = 44;
const FLOOR_Y = H - 6, FLOOR_KEEP = 0.75;
export const IMPLODE_RADIUS = 150;
/** ニードルの弾の見た目の番号(アプリの BulletLook.code(.needle) = 16 + 31 × 2) */
export const NEEDLE_LOOK = 16 + 31 * 2;

const bullet = (x: number, y: number, vx: number, vy: number, color: number, script = 0): BossBullet =>
  ({ x, y, vx, vy, color, turn: 0, homeLeft: 0, accel: 0, maxSpeed: 0, bounces: 0, script, age: 0 });
/** チャージビーム(アプリの Bullet.beam と同じ) */
const beam = (x: number, y: number, a: number, color: number, sweep = 0, fireTime = 0): BossBullet =>
  ({ x, y, vx: Math.cos(a), vy: Math.sin(a), color, turn: sweep, homeLeft: fireTime, accel: 0, maxSpeed: 0, bounces: 1, script: BEAM_SCRIPT, age: 0 });
/** 爆風(アプリの Bullet.blast と同じ) */
const blast = (x: number, y: number, radius: number, warn: number, color: number): BossBullet =>
  ({ x, y, vx: 0, vy: 0, color, turn: 0, homeLeft: 0, accel: 0, maxSpeed: 0, bounces: 1, script: BLAST_SCRIPT, age: 0, radius, fuse: warn });

/** パック3の弾の出し方(アプリの Emit.emitPack3 と同じ) */
export function emitPack3(m: Emitter, k: number, cx: number, cy: number, px: number, py: number, rng: () => number, out: BossBullet[], maxBullets: number) {
  const sp = m.v * 60;
  const n = Math.max(1, m.c);
  const deg = Math.PI / 180;
  const off = (m.a ?? 0) * deg;
  const push = (b: BossBullet) => { if (out.length < maxBullets) out.push(b); };
  const fan = (base: number, j: number) => base + (n > 1 ? (j / (n - 1) - 0.5) * m.r * deg : 0);
  switch (m.t) {
    case "radialLaser": {
      const sweep = 40 * deg, fire = 1.4;
      for (let j = 0; j < n; j++) {
        const a = (j * 2 * Math.PI) / n + k * m.r * deg + off;
        push(beam(cx, cy, a - sweep / 2, m.k, sweep / fire, fire));
      }
      break;
    }
    case "lightning":
      for (let j = 0; j < n; j++) {
        const x = 12 + rng() * (W - 24);
        push(beam(x, -10, Math.PI / 2, m.k, 0, 0.35));
      }
      break;
    case "carpetBomb": {
      const a = Math.atan2(py - cy, px - cx) + off;
      for (let j = 0; j < n; j++) {
        const d = 36 + j * 34;
        push(blast(cx + Math.cos(a) * d, cy + Math.sin(a) * d, 22, 0.6 + j * 0.12, m.k));
      }
      break;
    }
    case "dashShot": {
      const b = Math.atan2(py - cy, px - cx) + off;
      for (let j = 0; j < n; j++) {
        const a = fan(b, j);
        const q = bullet(cx, cy, Math.cos(a) * sp * 0.35, Math.sin(a) * sp * 0.35, m.k, DASH_SCRIPT);
        q.u0 = 0.9; q.u1 = 4;
        push(q);
      }
      break;
    }
    case "implode": {
      const R = IMPLODE_RADIUS;
      for (let j = 0; j < n; j++) {
        const a = (j * 2 * Math.PI) / n + k * m.r * deg + off;
        push(bullet(cx + Math.cos(a) * R, cy + Math.sin(a) * R, -Math.cos(a) * sp, -Math.sin(a) * sp, m.k, IMPLODE_SCRIPT));
      }
      break;
    }
    case "pincer":
      for (let j = 0; j < n; j++) {
        const y = py + (j - (n - 1) / 2) * 18;
        push(bullet(-8, y, sp, 0, m.k));
        push(bullet(W + 8, y, -sp, 0, m.k));
      }
      break;
    case "whirlwind": {
      const a = Math.atan2(py - cy, px - cx) + off;
      const cvx = Math.cos(a) * sp * 0.6, cvy = Math.sin(a) * sp * 0.6;
      const R = 16;
      for (let j = 0; j < n; j++) {
        const a0 = (j * 2 * Math.PI) / n + k * 0.5;
        const q = bullet(cx + Math.cos(a0) * R, cy + Math.sin(a0) * R, cvx, cvy, m.k, WHIRL_SCRIPT);
        q.turn = 5; q.u0 = cx; q.u1 = cy; q.u2 = a0; q.u3 = R;
        push(q);
      }
      break;
    }
    case "bounceBall":
      for (let j = 0; j < n; j++) {
        const a = fan(-Math.PI / 2 + off, j);
        const q = bullet(cx, cy, Math.cos(a) * sp, Math.sin(a) * sp, m.k, FLOOR_BOUNCE_SCRIPT);
        q.gravity = 220; q.u0 = 1;
        push(q);
      }
      break;
    case "needle": {
      const b = Math.atan2(py - cy, px - cx) + off;
      for (let j = 0; j < n; j++) {
        const a = fan(b, j);
        for (let s = 0; s < 3; s++) {
          const q = bullet(cx - Math.cos(a) * 6 * s, cy - Math.sin(a) * 6 * s, Math.cos(a) * sp, Math.sin(a) * sp, m.k);
          q.look = NEEDLE_LOOK;
          push(q);
        }
      }
      break;
    }
    case "trackLaser":
      for (let j = 0; j < n; j++) {
        const dx = j === 0 ? 0 : Math.floor((j + 1) / 2) * 28 * (j % 2 === 1 ? 1 : -1);
        const x = cx + dx;
        const q = beam(x, cy, Math.atan2(py - cy, px - x) + off, m.k, 0, 0.6);
        q.u0 = 0.8;
        push(q);
      }
      break;
    case "blinkShot": {
      const b = Math.atan2(py - cy, px - cx) + off;
      for (let j = 0; j < n; j++) {
        const a = fan(b, j);
        const q = bullet(cx, cy, Math.cos(a) * sp, Math.sin(a) * sp, m.k, BLINK_SCRIPT);
        q.homeLeft = 0.5; q.u0 = 0.5; q.u1 = 48; q.u2 = 3;
        push(q);
      }
      break;
    }
    default:
      break;
  }
}

/** パック3の弾の1ステップ(アプリの Bullet.advancePack3Script と同じ)。パック3の弾でなければ null */
export function stepPack3(b: BossBullet, dt: number): "alive" | null {
  switch (b.script) {
    case DASH_SCRIPT:
      b.age += dt;
      if ((b.u0 ?? 0) > 0 && b.age >= (b.u0 ?? 0)) { b.vx *= b.u1 ?? 1; b.vy *= b.u1 ?? 1; b.u0 = 0; }
      b.x += b.vx * dt; b.y += b.vy * dt;
      return "alive";
    case BLINK_SCRIPT:
      b.age += dt;
      b.homeLeft -= dt;
      if (b.homeLeft <= 0 && (b.u2 ?? 0) > 0) {
        const sp = Math.sqrt(b.vx * b.vx + b.vy * b.vy);
        if (sp > 0) { b.x += (b.vx / sp) * (b.u1 ?? 0); b.y += (b.vy / sp) * (b.u1 ?? 0); }
        b.u2 = (b.u2 ?? 0) - 1;
        b.homeLeft += b.u0 ?? 0;
      }
      b.x += b.vx * dt; b.y += b.vy * dt;
      return "alive";
    case WHIRL_SCRIPT: {
      b.age += dt;
      const ang = (b.u2 ?? 0) + b.turn * b.age;
      b.x = (b.u0 ?? 0) + b.vx * b.age + Math.cos(ang) * (b.u3 ?? 0);
      b.y = (b.u1 ?? 0) + b.vy * b.age + Math.sin(ang) * (b.u3 ?? 0);
      return "alive";
    }
    case FLOOR_BOUNCE_SCRIPT:
      b.age += dt;
      b.vy += (b.gravity ?? 0) * dt;
      b.x += b.vx * dt; b.y += b.vy * dt;
      if ((b.u0 ?? 0) > 0 && b.vy > 0 && b.y > FLOOR_Y) {
        b.y = 2 * FLOOR_Y - b.y;
        b.vy = -b.vy * FLOOR_KEEP;
        b.u0 = (b.u0 ?? 0) - 1;
      }
      return "alive";
    case IMPLODE_SCRIPT:
      b.age += dt;
      b.x += b.vx * dt; b.y += b.vy * dt;
      return "alive";
    default:
      return null;
  }
}
