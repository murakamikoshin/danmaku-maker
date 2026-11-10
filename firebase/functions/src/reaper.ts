import { REAPER_PATTERNS, type Emitter } from "./validate.js";
import { mulberry, type AngelBullet } from "./fallenangel.js";
import { KIND, ORBIT_SCRIPT, holdBullet, lookCode, plainBullet } from "./bossscripts.js";
import { SWAY_SCRIPT } from "./kitsune.js";

/** 死神の5つの技の弾の出し方。アプリの ReaperPatterns.swift と同じ計算。 */
export const isReaperPattern = (t: string): boolean => (REAPER_PATTERNS as readonly string[]).includes(t);

export function emitReaper(m: Emitter, k: number, cx: number, cy: number, px: number, py: number, rng: () => number, out: AngelBullet[],
  awakened: boolean, salt: number, maxBullets: number) {
  const sp = m.v * 60;
  const n = Math.max(1, m.c);
  const off = ((m.a ?? 0) * Math.PI) / 180;
  const twoPi = 2 * Math.PI;
  const W = 360, H = 540;
  const skull = { x: cx, y: cy - 32 };
  const room = () => out.length < maxBullets;
  const look = (kind: number) => lookCode(kind, awakened);
  switch (m.t as string) {
    case "reaperScythe": {
      const release = awakened ? 64 / 60 : 44 / 60;
      const a0 = (160 * Math.PI) / 180, a1 = (20 * Math.PI) / 180;
      const ax = cx, ay = cy + 20;
      for (const radius of awakened ? [150, 215] : [150]) {
        const count = Math.floor((radius * (a0 - a1)) / 13);
        let gaps: number[] = [];
        if (awakened) gaps = [Math.floor(count * (0.2 + rng() * 0.25)), Math.floor(count * (0.55 + rng() * 0.25))];
        for (let i = 0; i <= count; i++) {
          if (gaps.some((g) => i >= g && i < g + 4)) continue;
          const a = a0 - ((a0 - a1) * i) / count;
          const vx = (rng() - 0.5) * 36;
          if (!room()) continue;
          out.push(holdBullet(ax + Math.cos(a) * radius, ay + Math.sin(a) * radius, release, Math.sqrt(vx * vx + 900), Math.atan2(30, vx), false, look(KIND.blade), m.k, 0, 160));
        }
      }
      const aim = Math.atan2(py - skull.y, px - skull.x) + off;
      for (const d of [-0.5, 0.5]) {
        if (!room()) continue;
        const b = plainBullet(skull.x, skull.y, Math.cos(aim + d) * 72, Math.sin(aim + d) * 72, m.k, look(KIND.soul));
        b.turn = 1.2; b.homeLeft = 2.5;
        out.push(b);
      }
      break;
    }
    case "reaperSouls": {
      const count = awakened ? Math.floor((n * 8 + 4) / 5) : n;
      for (let i = 0; i < count; i++) {
        if (!room()) continue;
        const b = plainBullet(skull.x, skull.y, 0, 0, m.k, look(KIND.soul));
        b.script = ORBIT_SCRIPT; b.fuse = 40 / 60; b.u0 = skull.x; b.u1 = skull.y; b.u2 = (i * twoPi) / count + off; b.u3 = 3;
        out.push(b);
      }
      break;
    }
    case "reaperChains": {
      const origins: [number, number][] = [[0, 0], [W, 0], [W / 2, -4], [0, 220], [W, 220]];
      for (const o of origins.slice(0, awakened ? 5 : 3)) {
        const a = Math.atan2(py - o[1], px - o[0]);
        let d = 0, j = 0;
        while (d < 760) {
          const x = o[0] + Math.cos(a) * d, y = o[1] + Math.sin(a) * d;
          if (x < -10 || x > W + 10 || y > H + 10) break;
          if (room()) out.push(holdBullet(x, y, (20 + 2 * j) / 60, 0, a, false, look(KIND.chain), m.k, 1.0));
          d += 8; j += 1;
        }
      }
      break;
    }
    case "reaperDeadline": {
      const rows = awakened ? 6 : 4;
      const row = k % rows, cycle = Math.floor(k / rows);
      const r = mulberry((salt ^ 0x00dead11 ^ (Math.imul(cycle, 0x9e3779b1) >>> 0)) >>> 0);
      let gx = 180;
      for (let q = 0; q <= row; q++) {
        const dir = r() < 0.5 ? -1 : 1;
        gx = Math.min(310, Math.max(50, gx + dir * (40 + r() * 40)));
      }
      const gap = (m.r === 0 ? 56 : Math.abs(m.r)) * (awakened ? 48 / 56 : 1);
      for (let x = 10; x < W; x += 14) {
        if (Math.abs(x - gx) < gap / 2 || !room()) continue;
        out.push(plainBullet(x, 150, 0, m.v * 48, m.k, look(KIND.blade)));
      }
      const souls = Math.max(1, Math.ceil((m.i * 60) / 30));
      for (let j = 0; j < souls; j++) if (room()) out.push(holdBullet(skull.x, skull.y, j * 0.5, 120, 0, true, look(KIND.soul), m.k));
      break;
    }
    default: {
      const lanes = [330, 380, 430, 480, 530];
      lanes.forEach((y, i) => {
        if ((k + i * 3) % 7 < 2) return;
        const dir = i % 2 === 1 ? -1 : 1;
        if (!room()) return;
        const speed = awakened ? (sp * 3.0) / 2.4 : sp;
        const b = plainBullet(dir > 0 ? -6 : W + 6, y, dir * speed, 0, m.k, look(KIND.soul));
        if (awakened) { b.script = SWAY_SCRIPT; b.u0 = 0; b.u1 = 0.05; b.u2 = 36; b.u3 = 1; }
        out.push(b);
      });
    }
  }
}
