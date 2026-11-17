/**
 * 竜王の、数・速さ・向き・左右反転を自由に決められる5つの技(1.4.0)。アプリの DanmakuCore/DragonFreePatterns.swift と同じ計算。
 * ほかの技と同じく、弾を出すだけ。強さは段階ごとの姿(dragonLv: 0 通常〜3 白金)で上がる。
 */
import { DRAGON_FREE_PATTERNS, type Emitter } from "./validate.js";
import { type AngelBullet } from "./fallenangel.js";
import { anchorScale, plainBullet } from "./bossscripts.js";
import { DRAGON_CURVE, DRAGON_WAIT } from "./dragon.js";

export const isDragonFreePattern = (t: string): boolean => (DRAGON_FREE_PATTERNS as readonly string[]).includes(t);

/** 竜王の姿(0〜3)。竜王の場面で技を撃つ間だけ変える(アプリの Emit.dragonLv) */
export let dragonLv = 0;
export const setDragonLv = (v: number): void => { dragonLv = v; };

/** BulletLook.Kind の番号(アプリと同じ並び) */
const KIND = { flame: 22, slash: 23, gust: 24, spine: 27 } as const;
const dv = <T>(lv: number, a: T, b: T, c: T, d: T): T => (lv === 0 ? a : lv === 1 ? b : lv === 2 ? c : d);

export function emitDragonFree(m: Emitter, k: number, cx: number, cy: number, px: number, py: number, rng: () => number, out: AngelBullet[], maxBullets: number) {
  const L = Math.min(Math.max(dragonLv, 0), 3);
  const sp = m.v * 60;
  const n = Math.max(1, m.c);
  const off = ((m.a ?? 0) * Math.PI) / 180;
  const s = anchorScale;
  const W = 360, H = 540;
  const pi = Math.PI;
  const add = (kind: keyof typeof KIND, x: number, y: number, a: number, speed: number, r: number, script: number, fuse = 0, u0 = 0, u1 = 0, gravity = 0) => {
    if (out.length >= maxBullets) return;
    const b = plainBullet(x, y, Math.cos(a) * speed, Math.sin(a) * speed, m.k, 16 + KIND[kind] * 2 + (L > 0 ? 1 : 0));
    b.script = script;
    b.radius = r;
    b.fuse = fuse; b.u0 = u0; b.u1 = u1;
    b.gravity = gravity;
    out.push(b);
  };
  switch (m.t as string) {
    case "dragonWings": {
      const speed = sp * (1 + 0.08 * L);
      const turn = 1.4 + 0.25 * L;
      for (const side of [-1, 1]) {
        const ox = cx + side * 150 * s, oy = cy + 20 * s;
        for (let j = 0; j < n; j++) {
          const t = n > 1 ? j / (n - 1) : 0.5;
          const a = pi / 2 - side * (0.25 + 0.95 * t + off);
          add("gust", ox, oy, a, speed, 4, DRAGON_CURVE, 0, side * turn, 0.9);
        }
      }
      break;
    }
    case "dragonGeyser": {
      const cols = Math.min(n, 12);
      const gap = Math.min(64, (W - 40) / cols);
      const center = Math.min(W - 20 - (gap * (cols - 1)) / 2, Math.max(20 + (gap * (cols - 1)) / 2, px));
      const per = 4 + L;
      const a = -pi / 2 + off;
      for (let i = 0; i < cols; i++) {
        const x = Math.min(W - 10, Math.max(10, center + (i - (cols - 1) / 2) * gap + (rng() - 0.5) * 8));
        for (let j = 0; j < per; j++) {
          add("flame", x, H + 6, a, sp * 1.5 * (1 - j * 0.06), 4, DRAGON_WAIT, 0.55 + j * 0.06, 0, 0, 120);
        }
      }
      break;
    }
    case "dragonClaw": {
      const lines = L >= 3 ? 4 : 3;
      const theta = k % 2 === 0 ? pi / 4 + off : (3 * pi) / 4 - off;
      const nrm = k % 2 === 0 ? theta - pi / 2 : theta + pi / 2;
      const nx = Math.cos(nrm), ny = Math.sin(nrm);
      const tx = Math.cos(theta), ty = Math.sin(theta);
      const speed = sp * (1 + 0.1 * L);
      for (let i = 0; i < lines; i++) {
        const d = 130 + i * 36;
        const lx = px + nx * d, ly = py + ny * d;
        for (let j = 0; j < n; j++) {
          const q = (j - (n - 1) / 2) * 16;
          add("slash", lx + tx * q, ly + ty * q, nrm + pi, speed, 4, DRAGON_WAIT, 0.5 + i * 0.14);
        }
      }
      break;
    }
    case "dragonTwister": {
      const T = k * Math.max(0.05, m.i);
      const tx = W / 2 + Math.sin(T * 0.9) * (W / 2 - 40);
      const ty = cy + 150 * s + Math.sin(T * 1.7) * 20;
      const speed = sp * (1 + 0.08 * L);
      const spin = 1.6 + 0.3 * L;
      for (let j = 0; j < n; j++) {
        const a = (j * 2 * pi) / n + T * 2.2 + off;
        add("gust", tx + Math.cos(a) * 10, ty + Math.sin(a) * 10, a, speed, 4, DRAGON_CURVE, 0, spin, 1.2);
      }
      if (L >= 2) {
        const half = Math.max(1, Math.trunc(n / 2));
        for (let j = 0; j < half; j++) {
          const a = (j * 2 * pi) / half - T * 2.2 + off;
          add("flame", tx, ty, a, speed * 0.85, 4, DRAGON_CURVE, 0, -spin, 1.2);
        }
      }
      break;
    }
    default: {
      // dragonJaws
      const margin = dv(L, 0.45, 0.38, 0.3, 0.22);
      const ccx = Math.min(W - 30, Math.max(30, px)), ccy = Math.min(py, H - 130);
      const R = 125;
      const speed = sp * (1 + 0.1 * L);
      for (const jaw of [pi, 0]) {
        for (let j = 0; j < n; j++) {
          const t = n > 1 ? j / (n - 1) : 0.5;
          const phi = jaw + margin + (pi - 2 * margin) * t + off;
          add("spine", ccx + Math.cos(phi) * R, ccy + Math.sin(phi) * R, phi + pi, speed, 3, DRAGON_WAIT, 0.55);
        }
      }
    }
  }
}
