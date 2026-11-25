import { SANTA_PATTERNS, type Emitter } from "./validate.js";
import { type AngelBullet } from "./fallenangel.js";
import { HOOK_SCRIPT, KIND, WOBBLE_SCRIPT, holdBullet, lookCode, plainBullet, anchorScale } from "./bossscripts.js";

/** ノエル(クリスマスの期間限定のボス、見た目の番号 14)の5つの技の弾の出し方。アプリの SantaPatterns.swift と同じ計算。 */
export const isSantaPattern = (t: string): boolean => (SANTA_PATTERNS as readonly string[]).includes(t);

export function emitSanta(m: Emitter, k: number, cx: number, cy: number, px: number, py: number, rng: () => number, out: AngelBullet[],
  awakened: boolean, _salt: number, maxBullets: number) {
  const sp = m.v * 60;
  const n = Math.max(1, m.c);
  const off = ((m.a ?? 0) * Math.PI) / 180;
  const twoPi = 2 * Math.PI;
  const W = 360, H = 540;
  const room = () => out.length < maxBullets;
  const look = (kind: number) => lookCode(kind, awakened);
  const clamp = (v: number, lo: number, hi: number) => Math.min(hi, Math.max(lo, v));
  // 浮いているプレゼント(絵の中の (80,36))、杖の先 (28,66)、帽子の鈴 (73,25)
  const gift = { x: cx + 48 * anchorScale, y: cy - 40 * anchorScale }, hook = { x: cx - 56 * anchorScale, y: cy + 20 * anchorScale },
    hat = { x: cx + 34 * anchorScale, y: cy - 62 * anchorScale };
  switch (m.t as string) {
    case "santaGift": {
      if (k % 4 >= 3) break;
      const boxes = awakened ? n + 1 : n;
      const pieces = awakened ? 12 : 8;
      const life = 50 / 60;
      for (let j = 0; j < boxes; j++) {
        const a = rng() * twoPi, d = 85 + rng() * 65;
        const a0 = rng() * twoPi;
        const tx = clamp(px + Math.cos(a) * d, 20, W - 20), ty = clamp(py + Math.sin(a) * d, 200, H - 30);
        const delay = (j * 14) / 60;
        const dist = Math.sqrt((tx - gift.x) * (tx - gift.x) + (ty - gift.y) * (ty - gift.y));
        if (!room()) continue;
        out.push(holdBullet(gift.x, gift.y, delay, dist / life, Math.atan2(ty - gift.y, tx - gift.x), false, look(KIND.gift), m.k, life));
        for (let i = 0; i < pieces; i++) {
          if (!room()) continue;
          out.push(holdBullet(tx, ty, delay + life, sp, a0 + (i * twoPi) / pieces, false, look(KIND.candy), m.k));
        }
        if (awakened) {
          for (let i = 0; i < 4; i++) {
            if (!room()) continue;
            out.push(holdBullet(tx, ty, delay + life, sp * 0.54, a0 + ((i + 0.5) * twoPi) / 4, false, look(KIND.star), m.k));
          }
        }
      }
      break;
    }
    case "santaBell": {
      const volleys = awakened ? 5 : 3;
      if (k % (volleys + 1) >= volleys) break;
      const count = awakened ? Math.floor((n * 5 + 2) / 4) : n;
      const a0 = rng() * twoPi + off;
      const dir = k % 2 === 1 ? 1 : -1;
      const v = awakened ? sp * 1.19 : sp;
      for (let i = 0; i < count; i++) {
        if (!room()) continue;
        const a = a0 + (i * twoPi) / count;
        const b = plainBullet(hat.x, hat.y, Math.cos(a) * v, Math.sin(a) * v, m.k, look(KIND.bell));
        b.script = WOBBLE_SCRIPT; b.u0 = 0.72 * dir; b.u1 = 4.2; b.u2 = Math.PI / 2; b.u3 = 0; b.turn = 0;
        out.push(b);
      }
      break;
    }
    case "santaCane": {
      const cycle = Math.floor(k / 11), step = k % 11;
      if (step >= 6) break;
      const a0 = Math.atan2(py - hook.y, px - hook.x) + off;
      const rows = awakened ? n + 1 : n;
      const sides = awakened ? [1, -1] : [cycle % 2 === 1 ? 1 : -1];
      for (const side of sides) {
        for (let i = 0; i < rows; i++) {
          if (!room()) continue;
          const a = a0 + side * (0.25 + i * 0.3);
          const b = plainBullet(hook.x, hook.y, Math.cos(a) * sp, Math.sin(a) * sp, m.k, look(KIND.candy));
          b.script = HOOK_SCRIPT; b.u0 = (-side * Math.PI) / (56 / 60); b.u1 = 40 / 60; b.u2 = 56 / 60;
          out.push(b);
        }
      }
      break;
    }
    case "santaTree": {
      const rows = n;
      const first = clamp(px + (rng() - 0.5) * 60, 90, W - 90);
      const centers: [number, number][] = [[first, 0.5]];
      if (awakened) centers.push([clamp(first + (first < W / 2 ? 120 : -120), 90, W - 90), 1.1]);
      for (const [center, wait] of centers) {
        for (let r = 0; r < rows; r++) {
          for (let i = 0; i <= r; i++) {
            if (!room()) continue;
            out.push(holdBullet(center + (i - r / 2) * 26, -6, wait + r * 0.25, sp, Math.PI / 2, false, look(KIND.star), m.k));
          }
        }
        const trunk = wait + (rows - 1) * 0.25 + 22 / sp;
        for (const dx of [-13, 0, 13]) {
          if (!room()) continue;
          out.push(holdBullet(center + dx, -6, trunk, sp, Math.PI / 2, false, look(KIND.gift), m.k));
        }
      }
      break;
    }
    default: {
      if (k % 5 >= 4) break;
      const boxes = awakened ? n + 2 : n;
      const pieces = awakened ? 7 : 5;
      const wait = 34 / 60;
      const land = H - 40;
      const life = (land + 6) / sp;
      for (let j = 0; j < boxes; j++) {
        const x = j === 0 ? clamp(px, 16, W - 16) : 16 + rng() * (W - 32);
        if (!room()) continue;
        out.push(holdBullet(x, -6, wait, sp, Math.PI / 2, false, look(KIND.gift), m.k, life));
        for (let i = 0; i < pieces; i++) {
          if (!room()) continue;
          out.push(holdBullet(x, land, wait + life, sp * 0.425, -Math.PI / 2 + (i - (pieces - 1) / 2) * 0.34, false, look(KIND.candy), m.k, 0, 0.012 * 3600));
        }
      }
    }
  }
}
