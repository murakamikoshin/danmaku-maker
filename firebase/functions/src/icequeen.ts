import { ICE_QUEEN_PATTERNS, type Emitter } from "./validate.js";
import { type AngelBullet } from "./fallenangel.js";
import { BRANCH_SCRIPT, FREEZE_SCRIPT, KIND, WIND_SCRIPT, holdBullet, lookCode, plainBullet } from "./bossscripts.js";

/** 雪の女王の5つの技の弾の出し方。アプリの IceQueenPatterns.swift と同じ計算。 */
export const isIceQueenPattern = (t: string): boolean => (ICE_QUEEN_PATTERNS as readonly string[]).includes(t);

export function emitIceQueen(m: Emitter, k: number, cx: number, cy: number, px: number, py: number, rng: () => number, out: AngelBullet[],
  awakened: boolean, _salt: number, maxBullets: number) {
  const sp = m.v * 60;
  const n = Math.max(1, m.c);
  const off = ((m.a ?? 0) * Math.PI) / 180;
  const twoPi = 2 * Math.PI;
  const c = { x: cx, y: cy - 16 };
  const room = () => out.length < maxBullets;
  const look = (kind: number) => lookCode(kind, awakened);
  const plain = (x: number, y: number, a: number, speed: number, kind: number): AngelBullet => plainBullet(x, y, Math.cos(a) * speed, Math.sin(a) * speed, m.k, look(kind));
  switch (m.t as string) {
    case "iceCage": {
      const v = k % 4;
      for (let set = 0; set < (awakened ? 2 : 1); set++) {
        for (let i = 0; i < 6; i++) {
          if (!room()) continue;
          const a = set === 0 ? Math.PI / 2 + (i * Math.PI) / 3 + v * 0.17 + off : Math.PI / 2 + Math.PI / 6 + (i * Math.PI) / 3 - v * 0.17 + off;
          const b = plain(c.x, c.y, a, sp, KIND.shard);
          b.script = BRANCH_SCRIPT; b.homeLeft = 2; b.u0 = 0.5; b.u1 = 0.5;
          out.push(b);
        }
      }
      break;
    }
    case "iceIcicles": {
      const xs: number[] = [];
      const cnt = awakened ? Math.floor((n * 3 + 1) / 2) : n;
      for (let i = 0; i < cnt; i++) xs.push(16 + rng() * 328);
      const g = (awakened ? 0.12 : 0.08) * 3600 * m.v;
      for (const x of xs) if (room()) out.push(holdBullet(x, -6, 0.5, 30, Math.PI / 2, false, look(KIND.icicle), m.k, 0, g));
      break;
    }
    case "iceBlizzard": {
      const frame = k * m.i * 60;
      const idx = Math.floor(frame / 120);
      const wind = idx % 2 === 0 ? -1 : 1;
      const untilFlip = ((idx + 1) * 120 - frame) / 60;
      const drops = awakened ? (k % 2 === 0 ? 2 : 1) : 1;
      for (let q = 0; q < drops; q++) {
        const side = rng() < 0.3;
        const x = side ? (wind > 0 ? -6 : 360 + 6) : rng() * 360;
        const y = side ? rng() * 300 : -6;
        const ph = rng() * 9;
        if (!room()) continue;
        const b = plainBullet(x, y, wind * 72, sp, m.k, look(KIND.flake));
        b.script = WIND_SCRIPT; b.u0 = wind * 72; b.u1 = ph; b.u2 = untilFlip; b.u3 = sp;
        out.push(b);
      }
      break;
    }
    case "iceFreeze": {
      const count = awakened ? Math.floor((n * 7 + 2) / 5) : n;
      for (let i = 0; i < count; i++) {
        if (!room()) continue;
        const a = (i * twoPi) / count + k * 0.1 + off;
        const b = plain(c.x, c.y, a, sp, KIND.shard);
        b.script = FREEZE_SCRIPT; b.u0 = 40 / 60; b.u1 = 80 / 60;
        out.push(b);
        const fx = c.x + (Math.cos(a) * sp * 40) / 60, fy = c.y + (Math.sin(a) * sp * 40) / 60;
        for (let j = 0; j < 3; j++) {
          const ang = awakened ? (j - 1) * 0.35 : rng() * twoPi;
          if (!room()) continue;
          out.push(holdBullet(fx, fy, 80 / 60, 96, ang, awakened, look(KIND.shard), m.k));
        }
      }
      break;
    }
    default: {
      const count = awakened ? n + 2 : n;
      const a0 = Math.atan2(py - c.y, px - c.x) + off;
      for (let i = 0; i < count; i++) {
        if (!room()) continue;
        const a = a0 + (i - (count - 1) / 2) * 0.22;
        const b = plain(c.x, c.y, a, sp, KIND.shard);
        b.bounces = 2;
        out.push(b);
      }
    }
  }
}
