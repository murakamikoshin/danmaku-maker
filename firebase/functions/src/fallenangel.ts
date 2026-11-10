import { FALLEN_ANGEL_PATTERNS, type Emitter } from "./validate.js";

/**
 * 堕天使の5つの技の弾の出し方。アプリの FallenAngelPatterns.swift と同じ計算。
 * 弾の動き(羽・破片・閉じる輪)は fullsim.ts の step にある。
 */
export const FEATHER_SCRIPT = 11, SHARD_SCRIPT = 12, RING_SCRIPT = 13;
export const RING_START_RADIUS = 240;
export const FEATHER_DECEL_SECONDS = 32 / 60;
export const FEATHER_DECAY = Math.sqrt(0.93);

export const isFallenAngelPattern = (t: string): boolean => (FALLEN_ANGEL_PATTERNS as readonly string[]).includes(t);

const ORB_L = { dx: -44, dy: 10 }, ORB_R = { dx: 42, dy: 10 };
const HALO = { dx: -1, dy: -75 }, CHEST = { dx: 0, dy: -28 };

/** 出した弾の形(fullsim.ts の Bullet と同じ) */
export interface AngelBullet {
  x: number; y: number; vx: number; vy: number; color: number; turn: number; homeLeft: number; accel: number; maxSpeed: number; bounces: number; script: number; age: number;
  fuse?: number; u0?: number; u1?: number; u2?: number; u3?: number; look?: number;
}

export function mulberry(seed: number) {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a) >>> 0;
    t = ((t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t) >>> 0;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

/** 失楽園の抜け道の向き(最初はランダム、2つ目からは前の抜け道から ±90° 以内) */
export function paradiseGap(k: number, salt: number): number {
  const r = mulberry((salt ^ 0x5bd1e995) >>> 0);
  let g = r() * 2 * Math.PI;
  for (let i = 0; i < k; i++) g += (r() - 0.5) * Math.PI;
  const t = g % (2 * Math.PI);
  return t < 0 ? t + 2 * Math.PI : t;
}

export function emitFallenAngel(m: Emitter, k: number, cx: number, cy: number, px: number, py: number, rng: () => number, out: AngelBullet[],
  awakened: boolean, salt: number, maxBullets: number) {
  const sp = m.v * 60;
  const n = Math.max(1, m.c);
  const deg = Math.PI / 180;
  const off = (m.a ?? 0) * deg;
  const twoPi = 2 * Math.PI;
  const room = () => out.length < maxBullets;
  const alt = (i: number) => (i % 2 === 0 ? m.k : (m.k + 1) % 5);
  const plain = (x: number, y: number, vx: number, vy: number, color: number): AngelBullet => ({ x, y, vx, vy, color, turn: 0, homeLeft: 0, accel: 0, maxSpeed: 0, bounces: 0, script: 0, age: 0 });
  switch (m.t as string) {
    case "angelTwin": {
      const arms = n + (awakened ? 2 : 0);
      const turned = k * m.r * deg;
      for (const [side, orb] of [[-1, ORB_L], [1, ORB_R]] as const) {
        const ox = cx + orb.dx, oy = cy + orb.dy;
        for (let j = 0; j < arms; j++) {
          if (!room()) continue;
          const a = side * turned + off + (j * twoPi) / arms;
          out.push(plain(ox, oy, Math.cos(a) * sp, Math.sin(a) * sp, side < 0 ? m.k : (m.k + 2) % 5));
        }
      }
      break;
    }
    case "angelFeather": {
      for (const side of [-1, 1]) {
        for (let i = 0; i < n; i++) {
          const a = side > 0 ? -0.1 - i * 0.16 : Math.PI + 0.1 + i * 0.16;
          const ox = cx + side * (40 + rng() * 30);
          const oy = cy - rng() * 40;
          const speed = sp * (0.79 + rng() * 0.42);
          const seed = rng() * 99;
          if (!room()) continue;
          out.push({ ...plain(ox, oy, Math.cos(a + off) * speed, Math.sin(a + off) * speed, alt(i)), script: FEATHER_SCRIPT, fuse: seed, maxSpeed: awakened ? 180 : 138 });
        }
      }
      if (awakened) {
        const hx = cx + HALO.dx, hy = cy + HALO.dy;
        const aim = Math.atan2(py - hy, px - hx);
        for (const d of [-0.2, 0, 0.2]) {
          if (!room()) continue;
          out.push(plain(hx, hy, Math.cos(aim + d) * sp * 1.1, Math.sin(aim + d) * sp * 1.1, (m.k + 1) % 5));
        }
      }
      break;
    }
    case "angelHalo": {
      const rings = awakened ? 2 : 1;
      const count = awakened ? n + 4 : n;
      const hx = cx + HALO.dx, hy = cy + HALO.dy;
      for (let ring = 0; ring < rings; ring++) {
        const dir = ring === 0 ? 1 : -1;
        for (let i = 0; i < count; i++) {
          if (!room()) continue;
          out.push({ ...plain(hx, hy, 0, 0, ring === 0 ? m.k : (m.k + 1) % 5), script: SHARD_SCRIPT, u0: hx, u1: hy, u2: (i * twoPi) / count + k * 0.14 + off,
            turn: dir * 1.5, homeLeft: (64 + i * 2 + ring * 10) / 60, maxSpeed: 72 + ring * 30, u3: awakened ? sp * 1.24 : sp });
        }
      }
      break;
    }
    case "angelCross": {
      const cxp = cx + CHEST.dx, cyp = cy + CHEST.dy;
      const a0 = Math.atan2(py - cyp, px - cxp) + off;
      const va = (k % 2 === 1 ? -1 : 1) * (awakened ? 0.9 : 0.5);
      for (const [da, len] of [[0, 760], [Math.PI, 90], [Math.PI / 2, 170], [-Math.PI / 2, 170]] as const) {
        if (!room()) continue;
        const a = a0 + da;
        out.push({ ...plain(cxp, cyp, Math.cos(a), Math.sin(a), m.k), turn: va, homeLeft: 1.0, maxSpeed: len, bounces: 1, script: 4 });
      }
      break;
    }
    default: {
      // angelParadise
      const count = awakened ? Math.floor((n * 26) / 10) * 2 : n * 2;
      const gap = paradiseGap(k, salt);
      const width = (m.r === 0 ? 29 : Math.abs(m.r)) * deg * (awakened ? 0.76 : 1);
      const speed = awakened ? sp * 1.19 : sp;
      const rot = awakened ? (k % 2 === 1 ? 0.21 : -0.21) : 0;
      for (let i = 0; i < count; i++) {
        const a = (i * twoPi) / count;
        const d = Math.abs((a - gap + 3 * Math.PI) % twoPi - Math.PI);
        if (d < width / 2) continue;
        if (!room()) continue;
        out.push({ ...plain(px + Math.cos(a) * RING_START_RADIUS, py + Math.sin(a) * RING_START_RADIUS, 0, 0, alt(i)), script: RING_SCRIPT, u0: px, u1: py, u2: a, u3: speed, turn: rot, fuse: (RING_START_RADIUS - 4) / speed });
      }
    }
  }
}
