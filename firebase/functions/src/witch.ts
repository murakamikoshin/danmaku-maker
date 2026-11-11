import { WITCH_PATTERNS, type Emitter } from "./validate.js";
import { type AngelBullet } from "./fallenangel.js";
import { CURVE_SCRIPT, DARK_SCRIPT, DRAG_SCRIPT, KIND, LATERAL_SCRIPT, holdBullet, lookCode, plainBullet, anchorScale } from "./bossscripts.js";
import { SWAY_SCRIPT } from "./kitsune.js";

/** 深海の魔女の5つの技の弾の出し方。アプリの WitchPatterns.swift と同じ計算。 */
export const isWitchPattern = (t: string): boolean => (WITCH_PATTERNS as readonly string[]).includes(t);

const TIP_OFFSETS: ReadonlyArray<readonly [number, number]> = [[74, 22], [64, 40], [40, 66], [16, 74], [-12, 74], [-32, 62], [-66, 48], [-58, 16]];
const TENT = TIP_OFFSETS.map(([x, y]) => (Math.atan2(y - 14, x) * 180) / Math.PI);
const DARK_SECONDS = 230 / 60;
const DRAG_DECAY = Math.sqrt(0.995);
const tip = (j: number, cx: number, cy: number) => ({ x: cx + TIP_OFFSETS[j]![0] * anchorScale, y: cy + TIP_OFFSETS[j]![1] * anchorScale });

export function emitWitch(m: Emitter, k: number, cx: number, cy: number, px: number, py: number, rng: () => number, out: AngelBullet[],
  awakened: boolean, _salt: number, maxBullets: number) {
  const sp = m.v * 60;
  const n = Math.max(1, m.c);
  const off = ((m.a ?? 0) * Math.PI) / 180;
  const twoPi = 2 * Math.PI;
  const W = 360;
  const room = () => out.length < maxBullets;
  const look = (kind: number) => lookCode(kind, awakened);
  switch (m.t as string) {
    case "witchAbyss": {
      const lantern = { x: cx + 42 * anchorScale, y: cy - 54 * anchorScale };
      if (k % 17 === 0 && room()) {
        const d = plainBullet(lantern.x, lantern.y, 0, 0, m.k, 0);
        d.script = DARK_SCRIPT; d.fuse = DARK_SECONDS;
        out.push(d);
      }
      const cols = awakened ? n + 2 : n;
      for (let c = 0; c < cols; c++) {
        if (!room()) continue;
        const x0 = ((c + 0.5) * W) / cols;
        const b = plainBullet(x0, -6, 0, awakened ? (sp * 2.2) / 1.8 : sp, m.k, look(KIND.plankton));
        b.script = SWAY_SCRIPT; b.u0 = c; b.u1 = 0.06; b.u2 = 14 * 0.06 * 60; b.u3 = 2;
        out.push(b);
      }
      if (awakened && k % 4 === 0 && room()) {
        const a = Math.atan2(py - lantern.y, px - lantern.x) + off;
        const b = plainBullet(lantern.x, lantern.y, Math.cos(a) * 96, Math.sin(a) * 96, m.k, look(KIND.bubble));
        b.radius = 2;
        out.push(b);
      }
      break;
    }
    case "witchBubbles": {
      const v = k % 4;
      const count = awakened ? 8 : 4;
      const pieces = awakened ? 10 : 6;
      for (let j = 0; j < count; j++) {
        const tp = tip(awakened ? j : (j * 2 + v) % 8, cx, cy);
        const a = Math.PI / 2 + (rng() - 0.5) * 1.2 + off;
        const a0 = rng() * twoPi;
        if (!room()) continue;
        const b = plainBullet(tp.x, tp.y, Math.cos(a) * sp, Math.sin(a) * sp, m.k, look(KIND.bubble));
        b.script = DRAG_SCRIPT; b.fuse = 1.5; b.radius = 0.01; b.grow = 0.09 * 60; b.growMax = 7;
        out.push(b);
        let x = tp.x, y = tp.y, vx = b.vx, vy = b.vy, age = 0;
        const dt = 1 / 120;
        for (;;) {
          age += dt;
          if (age >= 1.5) break;
          vx *= DRAG_DECAY; vy *= DRAG_DECAY;
          x += vx * dt; y += vy * dt;
        }
        for (let i = 0; i < pieces; i++) if (room()) out.push(holdBullet(x, y, 1.5, 108, a0 + (i * twoPi) / pieces, false, look(KIND.plankton), m.k));
      }
      break;
    }
    case "witchTentacles": {
      const cyc = k % 40;
      if (cyc >= 30) break;
      const t = cyc * m.i * 60;
      const amp = awakened ? 18 : 12;
      for (let j = 0; j < 8; j++) {
        if (!room()) continue;
        const tp = tip(j, cx, cy);
        const b = plainBullet(tp.x, tp.y, 0, 0, m.k, look(KIND.plankton));
        b.script = LATERAL_SCRIPT;
        b.u0 = (TENT[j]! * Math.PI) / 180 + (awakened ? Math.sin(t * 0.03) * 0.4 : 0) + off;
        b.u1 = j; b.u2 = amp * 6; b.u3 = sp;
        out.push(b);
      }
      break;
    }
    case "witchMaelstrom": {
      const cyc = k % 50;
      if (!(cyc < 40 && cyc % 4 !== 3)) break;
      const root = { x: cx, y: cy + 14 * anchorScale };
      const arms = awakened ? n + 2 : n;
      const t = cyc * m.i * 60;
      for (let a = 0; a < arms; a++) {
        if (!room()) continue;
        const dir = awakened && a % 2 === 1 ? -1 : 1;
        const ang = (a * twoPi) / arms + t * 0.02 * dir + off;
        const b = plainBullet(root.x, root.y, Math.cos(ang) * sp, Math.sin(ang) * sp, m.k, look(KIND.plankton));
        b.script = CURVE_SCRIPT; b.u0 = 0.012 * 60 * dir;
        out.push(b);
      }
      break;
    }
    default: {
      const v = k % 3;
      const xs = v % 2 === 1 ? [90, 270] : [45, 180, 315];
      const popY = awakened ? 260 : 300;
      const pieces = awakened ? 12 : 8;
      const life = (popY + 10) / sp;
      for (const x of xs) {
        if (!room()) continue;
        out.push(holdBullet(x, -10, 0, sp, Math.PI / 2, false, look(KIND.ink), m.k, life));
        for (let i = 0; i < pieces; i++) if (room()) out.push(holdBullet(x, popY, life, 120, (i * twoPi) / pieces, true, look(KIND.plankton), m.k));
      }
    }
  }
}
