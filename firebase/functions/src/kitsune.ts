import { KITSUNE_PATTERNS, type Emitter } from "./validate.js";
import { mulberry, type AngelBullet } from "./fallenangel.js";

/**
 * 九尾の巫女の5つの技の弾の出し方。アプリの KitsunePatterns.swift と同じ計算。
 * 弾の動き(折れる御札・揺れる弾)は fullsim.ts の step にある。
 */
export const FOLD_SCRIPT = 14, SWAY_SCRIPT = 15;
export const isKitsunePattern = (t: string): boolean => (KITSUNE_PATTERNS as readonly string[]).includes(t);

/** 専用の弾の番号(アプリの BulletLook.code と同じ。種類 fox=0, ofuda=1) */
const lookCode = (kind: number, awakened: boolean) => 16 + kind * 2 + (awakened ? 1 : 0);
const FOX = 0, OFUDA = 1;
const W = 360;

const root = (cx: number, cy: number) => ({ x: cx, y: cy - 10 });
const TIPS: ReadonlyArray<readonly [number, number]> = [[-64, 30], [-70, -4], [-60, -40], [-32, -64], [32, -70], [56, -48], [70, -28], [76, 2], [66, 34]];
function tip(k: number, cx: number, cy: number) {
  return { x: cx + TIPS[k]![0], y: cy + TIPS[k]![1] };
}

export function emitKitsune(m: Emitter, k: number, cx: number, cy: number, px: number, py: number, rng: () => number, out: AngelBullet[],
  awakened: boolean, salt: number, maxBullets: number) {
  const sp = m.v * 60;
  const n = Math.max(1, m.c);
  const off = ((m.a ?? 0) * Math.PI) / 180;
  const twoPi = 2 * Math.PI;
  const room = () => out.length < maxBullets;
  const add = (x: number, y: number, a: number, speed: number, kind: number): AngelBullet =>
    ({ x, y, vx: Math.cos(a) * speed, vy: Math.sin(a) * speed, color: m.k, turn: 0, homeLeft: 0, accel: 0, maxSpeed: 0, bounces: 0, script: 0, age: 0, look: lookCode(kind, awakened) });
  switch (m.t as string) {
    case "kitsuneLanterns": {
      const cycle = awakened ? 36 : 18;
      const j = k % cycle;
      const within = j % 18;
      if (within < 9) break;
      const idx = within - 9;
      const tipIndex = Math.floor(j / 18) % 2 === 1 ? 8 - idx : idx;
      const o = tip(tipIndex, cx, cy);
      const aim = Math.atan2(py - o.y, px - o.x) + off;
      const speed = awakened ? (sp * 3.8) / 3.2 : sp;
      for (const d of awakened ? [-0.18, 0, 0.18] : [0]) if (room()) out.push(add(o.x, o.y, aim + d, speed, FOX));
      break;
    }
    case "kitsuneBarrier": {
      const r = root(cx, cy);
      const count = awakened ? Math.floor((n * 3 + 1) / 2) : n;
      for (let i = 0; i < count; i++) {
        if (!room()) continue;
        const s = i % 2 === 1 ? 1 : -1;
        const a = k * 0.26 + (i * twoPi) / count + off;
        const b = add(r.x, r.y, a, sp, OFUDA);
        b.script = FOLD_SCRIPT;
        b.u0 = 36 / 60; b.u1 = (s * Math.PI) / 2; b.u2 = awakened ? 72 / 60 : 0; b.u3 = 1.2;
        out.push(b);
      }
      break;
    }
    case "kitsuneSunshower": {
      const r = root(cx, cy);
      const cyc = k % 70;
      const drops = cyc >= 50 ? 0 : awakened ? (cyc % 2 === 0 ? 2 : 1) : cyc % 4 === 3 ? 0 : 1;
      for (let q = 0; q < drops; q++) {
        const x = rng() * W;
        const ph = rng() * 9;
        if (!room()) continue;
        const b = add(x, -8, Math.PI / 2, awakened ? (sp * 2.8) / 2.2 : sp, FOX);
        b.script = SWAY_SCRIPT;
        b.u0 = ph * 20 * 0.04; b.u1 = 0.04; b.u2 = 0.8 * 60;
        out.push(b);
      }
      if (cyc < 50 && cyc % 10 === 0) {
        const aim = Math.atan2(py - r.y, px - r.x) + off;
        for (const d of [-0.2, 0, 0.2]) if (room()) out.push(add(r.x, r.y, aim + d, (sp * 2.6) / 2.2, OFUDA));
      }
      break;
    }
    case "kitsuneTorii": {
      const row = k % 8, cycle = Math.floor(k / 8);
      const rr = mulberry(((salt ^ 0x00070f11 ^ (Math.imul(cycle, 0x9e3779b1) >>> 0)) >>> 0));
      let gx = 180;
      for (let q = 0; q <= row; q++) {
        const dir = rr() < 0.5 ? -1 : 1;
        gx = Math.min(310, Math.max(50, gx + dir * (30 + rr() * 30)));
      }
      const gap = (m.r === 0 ? 60 : Math.abs(m.r)) * (awakened ? 0.8 : 1);
      const r = root(cx, cy);
      for (let x = 8; x < W; x += 16) {
        if (Math.abs(x - gx) < gap / 2 || !room()) continue;
        const b = add(x, r.y, Math.PI / 2, sp, OFUDA);
        if (awakened) { b.script = SWAY_SCRIPT; b.u0 = row; b.u1 = 0.05; b.u2 = 0.6 * 60; }
        out.push(b);
      }
      break;
    }
    default: {
      const cyc = k % 56;
      if (cyc >= 40 || cyc % 4 === 3) break;
      const t = cyc * m.i * 60;
      for (let tp = 0; tp < 9; tp++) {
        const o = tip(tp, cx, cy);
        const base = Math.PI / 2 + (tp - 4) * 0.28 + off;
        const sway = Math.sin(t * 0.05 + tp) * 0.5;
        const speed = awakened ? (sp * 2.6) / 2.2 : sp;
        if (room()) out.push(add(o.x, o.y, base + sway, speed, FOX));
        if (awakened && room()) out.push(add(o.x, o.y, base - sway, speed, FOX));
      }
    }
  }
}
