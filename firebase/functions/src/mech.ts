import { MECH_PATTERNS, type Emitter } from "./validate.js";
import { type AngelBullet } from "./fallenangel.js";
import { KIND, MISSILE_SCRIPT, lookCode, plainBullet, type BossBullet } from "./bossscripts.js";

/** 機神の5つの技の弾の出し方。アプリの MechPatterns.swift と同じ計算。 */
export const isMechPattern = (t: string): boolean => (MECH_PATTERNS as readonly string[]).includes(t);

const BEAM_SCRIPT = 4;
const cannon = (left: boolean, cx: number, cy: number) => ({ x: left ? cx - 62 : cx + 60, y: cy - 20 });

function missile(x: number, y: number, angle: number, speed: number, delay: number, decelEnd: number, steerEnd: number, turn: number, accel: number, maxSpeed: number, look: number, color: number): BossBullet {
  const b = plainBullet(x, y, Math.cos(angle) * speed, Math.sin(angle) * speed, color, look);
  b.script = MISSILE_SCRIPT; b.fuse = delay; b.u0 = decelEnd; b.u2 = steerEnd; b.u3 = accel; b.turn = turn; b.maxSpeed = maxSpeed;
  return b;
}
function beam(x: number, y: number, angle: number, color: number, sweep: number, fireTime: number): BossBullet {
  const b = plainBullet(x, y, Math.cos(angle), Math.sin(angle), color, 0);
  b.script = BEAM_SCRIPT; b.turn = sweep; b.homeLeft = fireTime; b.bounces = 1;
  return b;
}

export function emitMech(m: Emitter, k: number, cx: number, cy: number, px: number, py: number, rng: () => number, out: AngelBullet[],
  awakened: boolean, _salt: number, maxBullets: number) {
  const sp = m.v * 60;
  const n = Math.max(1, m.c);
  const off = ((m.a ?? 0) * Math.PI) / 180;
  const twoPi = 2 * Math.PI;
  const eye = { x: cx, y: cy - 14 };
  const room = () => out.length < maxBullets;
  const look = (kind: number) => lookCode(kind, awakened);
  switch (m.t as string) {
    case "mechLockOn": {
      if (room()) {
        const a = Math.atan2(py - eye.y, px - eye.x) + off;
        const b = beam(eye.x, eye.y, a, m.k, 0, 40 / 60);
        b.radius = awakened ? 17 : 13;
        b.u0 = 46 / 60;
        out.push(b);
      }
      for (let i = 0; i < (awakened ? 4 : 2); i++) {
        if (!room()) continue;
        const c = cannon(i % 2 === 0, cx, cy);
        const a = -Math.PI / 2 + (i % 2 === 1 ? 0.7 : -0.7) * (1 + Math.floor(i / 2) * 0.4);
        out.push(missile(c.x, c.y, a, 156, 1.0, 0, 1.5, 2.4, 0, 0, look(KIND.missile), m.k));
      }
      break;
    }
    case "mechMissiles": {
      const count = awakened ? Math.floor((n * 5) / 3) : n;
      const gap = awakened ? 3 : 5;
      for (let i = 0; i < count; i++) {
        const c = cannon(i % 2 === 0, cx, cy);
        const a = -Math.PI / 2 + (i % 2 === 1 ? 1 : -1) * (0.3 + rng() * 0.9);
        if (!room()) continue;
        out.push(missile(c.x, c.y, a, sp, (i * gap) / 60, 25 / 60, 85 / 60, 3.6, 288, 204, look(KIND.missile), m.k));
      }
      break;
    }
    case "mechGatling": {
      const cyc = k % 37;
      if (cyc >= 30) break;
      const f = cyc / 30;
      for (const left of [true, false]) {
        const c = cannon(left, cx, cy);
        const a = left ? Math.PI / 6 + (f * twoPi) / 3 : (Math.PI * 5) / 6 - (f * twoPi) / 3;
        for (const d of awakened ? [-0.1, 0.1] : [0]) {
          if (!room()) continue;
          out.push(plainBullet(c.x, c.y, Math.cos(a + d + off) * sp, Math.sin(a + d + off) * sp, m.k, look(KIND.shell)));
        }
      }
      break;
    }
    case "mechGrid": {
      if (k % 5 === 0) {
        const lasers = awakened ? n + 2 : n;
        const a0 = rng() * twoPi;
        const dir = Math.floor(k / 5) % 2 === 0 ? -1 : 1;
        for (let i = 0; i < lasers; i++) {
          if (!room()) continue;
          const b = beam(eye.x, eye.y, a0 + (i * twoPi) / lasers + off, m.k, (awakened ? 0.01 : 0.006) * 60 * dir, 70 / 60);
          b.radius = 5;
          out.push(b);
        }
      }
      if (room()) {
        const a = Math.atan2(py - eye.y, px - eye.x);
        out.push(plainBullet(eye.x, eye.y, Math.cos(a) * sp, Math.sin(a) * sp, m.k, look(KIND.hex)));
      }
      break;
    }
    default: {
      const rings = awakened ? 7 : 5;
      const v = k % (rings + 3);
      if (v >= rings) break;
      const count = awakened ? Math.floor((n * 4) / 3) : n;
      const gapA = Math.atan2(py - eye.y, px - eye.x) + (v % 2 === 1 ? 0.5 : -0.5);
      for (let i = 0; i < count; i++) {
        const a = (i * twoPi) / count + v * 0.13 + off;
        let d = (a - gapA) % twoPi;
        if (d > Math.PI) d -= twoPi;
        if (d < -Math.PI) d += twoPi;
        if (Math.abs(d) < (twoPi / count) * 1.6) continue;
        if (!room()) continue;
        const b = plainBullet(eye.x, eye.y, Math.cos(a) * sp, Math.sin(a) * sp, m.k, look(KIND.hex));
        b.accel = 1.5; b.maxSpeed = 210;
        out.push(b);
      }
    }
  }
}
