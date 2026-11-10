import { HIRE_PATTERNS, type Emitter } from "./validate.js";
import { type AngelBullet } from "./fallenangel.js";
import { KIND, WOBBLE_SCRIPT, YOYO_SCRIPT, KAIYU_SCRIPT, holdBullet, lookCode, plainBullet } from "./bossscripts.js";

/** 金魚姫の5つの技の弾の出し方。アプリの HirePatterns.swift と同じ計算。 */
export const isHirePattern = (t: string): boolean => (HIRE_PATTERNS as readonly string[]).includes(t);

export function emitHire(m: Emitter, k: number, cx: number, cy: number, px: number, py: number, rng: () => number, out: AngelBullet[],
  awakened: boolean, _salt: number, maxBullets: number) {
  const sp = m.v * 60;
  const n = Math.max(1, m.c);
  const off = ((m.a ?? 0) * Math.PI) / 180;
  const twoPi = 2 * Math.PI;
  const W = 360, H = 540;
  const room = () => out.length < maxBullets;
  const look = (kind: number) => lookCode(kind, awakened);
  const angDiff = (a: number, b: number) => {
    let d = (a - b) % twoPi;
    if (d > Math.PI) d -= twoPi;
    if (d < -Math.PI) d += twoPi;
    return Math.abs(d);
  };
  const hand = { x: cx + 34, y: cy - 28 }, poi = { x: cx - 34, y: cy - 46 };
  switch (m.t as string) {
    case "hireSukui": {
      const volleys = awakened ? 4 : 3;
      if (k % (volleys + 1) >= volleys) break;
      const count = awakened ? Math.floor((n * 3 + 1) / 2) : n;
      const a0 = Math.atan2(py - hand.y, px - hand.x) + off;
      for (let i = 0; i < count; i++) {
        const ph = rng() * 9;
        if (!room()) continue;
        const a = a0 + (i - (count - 1) / 2) * 0.16;
        const b = plainBullet(hand.x, hand.y, Math.cos(a) * sp, Math.sin(a) * sp, m.k, look(KIND.kingyo));
        b.script = WOBBLE_SCRIPT; b.u0 = 3; b.u1 = 9; b.u2 = ph; b.u3 = 1.0; b.turn = awakened ? 1.32 : 0.9;
        out.push(b);
      }
      break;
    }
    case "hireYoyo": {
      const count = awakened ? Math.floor((n * 3 + 1) / 2) : n;
      const pieces = awakened ? 12 : 8;
      for (let i = 0; i < count; i++) {
        const x = 20 + ((i + 0.5) * (W - 40)) / count + (rng() - 0.5) * 10;
        const a0 = rng() * twoPi;
        if (!room()) continue;
        const delay = (i * 8) / 60;
        const b = plainBullet(x, -8, 0, 0, m.k, look(KIND.yoyo));
        b.script = YOYO_SCRIPT; b.fuse = delay;
        out.push(b);
        let yy = -8, tt = 0;
        const dt = 1 / 120;
        for (;;) {
          tt += dt;
          if (tt >= 100 / 60) break;
          const vy = tt <= 0.75 ? (2.6 * (1 - tt / 0.75) + 0.2) * 60 : tt <= 1.0 ? 0 : -90;
          yy += vy * dt;
        }
        for (let j = 0; j < pieces; j++) if (room()) out.push(holdBullet(x, yy, delay + 100 / 60, sp, (awakened ? 0 : a0) + (j * twoPi) / pieces, awakened, look(KIND.awa), m.k));
      }
      break;
    }
    case "hireHanabi": {
      const shells = awakened ? 6 : 4;
      if (k % (shells + 4) >= shells) break;
      const tx = 40 + rng() * 280, ty = 60 + rng() * 140;
      const a = Math.atan2(ty - poi.y, tx - poi.x);
      if (!room()) break;
      const dist = Math.sqrt((tx - poi.x) * (tx - poi.x) + (ty - poi.y) * (ty - poi.y)) * 0.8;
      const life = 35 / 60;
      out.push(holdBullet(poi.x, poi.y, 0, dist / life, a, false, look(KIND.spark), m.k, life));
      const bx = poi.x + Math.cos(a) * dist, by = poi.y + Math.sin(a) * dist;
      const count = awakened ? 24 : 18;
      for (let j = 0; j < count; j++) if (room()) out.push(holdBullet(bx, by, life, (sp * 1.6) / 4.0, (j * twoPi) / count, false, look(KIND.spark), m.k, 0, 0.025 * 3600));
      break;
    }
    case "hireRipple": {
      if (k % 6 >= 4) break;
      for (let q = 0; q < (awakened ? 2 : 1); q++) {
        const a = rng() * twoPi, d = 70 + rng() * 60;
        const x = Math.min(W - 16, Math.max(16, px + Math.cos(a) * d)), y = Math.min(H - 16, Math.max(240, py + Math.sin(a) * d));
        const count = awakened ? Math.floor((n * 10 + 6) / 7) : n;
        for (let i = 0; i < count; i++) if (room()) out.push(holdBullet(x, y, 0.5, sp, (i * twoPi) / count, false, look(KIND.awa), m.k));
      }
      break;
    }
    default: {
      const gapAt = rng() * twoPi;
      for (const [ri, dir] of (awakened ? [[0, 1], [1, -1]] : [[0, 1]]) as [number, number][]) {
        const r0 = 150 + ri * 40;
        for (let i = 0; i < 20; i++) {
          const a0 = (i * twoPi) / 20;
          if (angDiff(a0, gapAt + ri * Math.PI) < (twoPi / 20) * 1.6) continue;
          if (!room()) continue;
          const b = plainBullet(px + Math.cos(a0) * r0, py + Math.sin(a0) * r0, 0, 0, m.k, look(KIND.kingyo));
          b.script = KAIYU_SCRIPT; b.fuse = 100 / 60; b.u0 = px; b.u1 = py; b.u2 = a0; b.maxSpeed = r0; b.accel = 60 + ri * 30; b.turn = dir * 1.2;
          out.push(b);
        }
      }
    }
  }
}
