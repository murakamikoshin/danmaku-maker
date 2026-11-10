import { PUNI_PATTERNS, type Emitter } from "./validate.js";
import { type AngelBullet } from "./fallenangel.js";
import { CURVE_SCRIPT, KIND, WARP, holdBullet, lookCode, plainBullet, type BossBullet } from "./bossscripts.js";

/** ぷにまるの5つの技の弾の出し方。アプリの PuniPatterns.swift と同じ計算。 */
export const isPuniPattern = (t: string): boolean => (PUNI_PATTERNS as readonly string[]).includes(t);
export const WARP_SCRIPT = WARP;

const BEAM_SCRIPT = 4;
const EYES: ReadonlyArray<readonly [number, number]> = [
  [53.769974, 48.769566], [32.2689, 48.927456], [56.758216, 40.63205], [91.927262, 37.444275], [101.303457, 68.256775], [71.595636, 66.088367],
  [78.477526, 55.65313], [60.787685, 60.679455], [93.244441, 64.921933], [96.380715, 45.321464], [67.414556, 48.286513], [51.060271, 44.701989],
  [77.802896, 79.920395], [96.827309, 65.691207], [73.806344, 61.539982], [61.744536, 34.713954], [89.011201, 38.269815], [83.427582, 37.257611],
  [86.019359, 59.033053], [84.209776, 72.284934], [55.115329, 64.464691], [72.433984, 43.501197]];

export function emitPuni(m: Emitter, k: number, cx: number, cy: number, px: number, py: number, rng: () => number, out: AngelBullet[],
  awakened: boolean, _salt: number, maxBullets: number) {
  const sp = m.v * 60;
  const off = ((m.a ?? 0) * Math.PI) / 180;
  const twoPi = 2 * Math.PI;
  const room = () => out.length < maxBullets;
  const look = (kind: number) => lookCode(kind, awakened);
  const bullet = (x: number, y: number, a: number, speed: number, kind: number): BossBullet => plainBullet(x, y, Math.cos(a) * speed, Math.sin(a) * speed, m.k, look(kind));
  const body = { x: cx - 4, y: cy + 64 }, core = { x: cx, y: cy };
  switch (m.t as string) {
    case "puniPoyon": {
      if (!awakened) {
        const cyc = k % 130;
        if (!(cyc % 20 === 0 && cyc < 120 && room())) break;
        out.push(bullet(body.x, body.y + 8, Math.PI / 2, sp, KIND.jelly));
      } else {
        const cyc = k % 73;
        if (!(cyc < 58 && cyc % 4 !== 3 && room())) break;
        const idx = (cyc - Math.floor((cyc + 1) / 4)) % 22;
        const ex = cx - 136 + EYES[idx]![0] * 2, ey = cy - 112 + EYES[idx]![1] * 2;
        out.push(bullet(ex, ey, Math.atan2(py - ey, px - ex) + off, sp * 3.0, KIND.eye));
      }
      break;
    }
    case "puniShower": {
      if (!awakened) {
        const cyc = k % 80;
        if (!(cyc % 17 === 0 && cyc < 68)) break;
        for (const d of [-0.3, 0, 0.3]) if (room()) out.push(bullet(body.x, body.y + 6, Math.PI / 2 + d, sp, KIND.jelly));
      } else {
        const cyc = k % 70;
        if (!(cyc < 50 && cyc % 4 !== 3)) break;
        const t = cyc * 3;
        for (let a = 0; a < 12; a++) {
          if (!room()) continue;
          const b = bullet(core.x, core.y, (a * Math.PI) / 6 + t * 0.03 + off, (sp * 2.0) / 1.2, KIND.goo);
          b.script = CURVE_SCRIPT; b.u0 = 0.01 * 60;
          out.push(b);
        }
      }
      break;
    }
    case "puniKorokoro": {
      if (!awakened) {
        const cyc = k % 71;
        if (!(cyc % 17 === 0 && cyc < 51)) break;
        for (const s of [-1, 1]) {
          if (!room()) continue;
          const b = bullet(body.x, body.y, -Math.PI / 2 + s * 0.6, sp, KIND.jelly);
          b.gravity = 0.05 * 3600;
          out.push(b);
        }
      } else {
        const cyc = k % 60;
        if (!(cyc % 8 === 0 && cyc < 40)) break;
        const v = Math.floor(cyc / 8);
        for (let i = 0; i < 24; i++) {
          if (!room()) continue;
          const b = bullet(core.x, core.y, (i * twoPi) / 24 + v * 0.13 + off, (sp * 1.6) / 2.0, KIND.tooth);
          b.script = CURVE_SCRIPT; b.u0 = (v % 2 === 1 ? 1 : -1) * 0.008 * 60;
          out.push(b);
        }
      }
      break;
    }
    case "puniPurupuru": {
      if (!awakened) {
        const cyc = k % 60;
        if (!(cyc % 20 === 0 && cyc < 40)) break;
        const v = Math.floor(cyc / 20);
        for (let i = 0; i < 8; i++) if (room()) out.push(bullet(body.x, body.y, (i * Math.PI) / 4 + v * 0.4 + off, sp, KIND.jelly));
      } else {
        const cyc = k % 70;
        if (cyc !== 0) break;
        for (let i = 0; i < 4; i++) {
          if (!room()) continue;
          const b = plainBullet(core.x, core.y, Math.cos(i * Math.PI / 2 + Math.PI / 4 + off), Math.sin(i * Math.PI / 2 + Math.PI / 4 + off), (m.k + (i % 2) * 2) % 5, 0);
          b.script = BEAM_SCRIPT; b.turn = (i % 2 === 1 ? 1 : -1) * 0.008 * 60; b.homeLeft = 150 / 60; b.bounces = 1; b.radius = 4.5;
          out.push(b);
        }
        for (let j = 0; j < 10; j++) if (room()) out.push(holdBullet(core.x, core.y, (j * 20) / 60, sp * 2.2, 0, true, look(KIND.goo), m.k));
      }
      break;
    }
    default: {
      if (!awakened) {
        const cyc = k % 80;
        if (!(cyc % 33 === 0 && cyc < 66 && room())) break;
        const y0 = body.y + 6;
        const life = Math.max(0, (320 - y0) / (sp * 0.9));
        const big = holdBullet(body.x, y0, 0, sp * 0.9, Math.PI / 2, false, look(KIND.jelly), m.k, life);
        big.radius = 4;
        out.push(big);
        for (const d of [-0.5, 0, 0.5]) if (room()) out.push(holdBullet(body.x, Math.max(y0, 320), life, sp * 1.4, Math.PI / 2 + d, false, look(KIND.jelly), m.k));
      } else {
        const cyc = k % 114;
        if (!(cyc % 13 === 0 && cyc < 104)) break;
        const r = Math.floor(cyc / 13);
        const startFrame = r * 39;
        let warpAt = 37;
        for (let n = 0; n <= 20; n++) { const t = 37 + 75 * n; if (t > startFrame + 15) { warpAt = t; break; } }
        for (let i = 0; i < 16; i++) {
          if (!room()) continue;
          const b = bullet(core.x, core.y, (i * twoPi) / 16 + startFrame * 0.01 + off, sp * 1.5, KIND.eye);
          if (rng() < 0.2) {
            const a = rng() * twoPi;
            const d = 50 + rng() * 30;
            b.script = WARP_SCRIPT; b.fuse = (warpAt - startFrame) / 60; b.u0 = a; b.u1 = d;
          }
          out.push(b);
        }
      }
    }
  }
}
