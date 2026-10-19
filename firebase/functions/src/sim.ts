import type { Emitter, Stage } from "./validate.js";

/** OGP 画像用の簡易シミュレーション。自機は動かさず、弾の配置だけを求める（クライアントの Swift 版とは別物） */
export const W = 360;
export const H = 540;

export interface Dot { x: number; y: number; k: number }

function mulberry(seed: number) {
  let a = seed | 0;
  return () => {
    a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

function emit(m: Emitter, k: number, cx: number, cy: number, px: number, py: number, rng: () => number, out: Array<Dot & { vx: number; vy: number }>) {
  const sp = m.v * 60, n = Math.max(1, m.c), deg = Math.PI / 180;
  const add = (x: number, y: number, a: number) => {
    if (out.length < 1600) out.push({ x, y, k: m.k, vx: Math.cos(a) * sp, vy: Math.sin(a) * sp });
  };
  switch (m.t) {
    case "ring": case "spiral":
      for (let j = 0; j < n; j++) add(cx, cy, (j * 2 * Math.PI) / n + k * m.r * deg);
      break;
    case "aim": {
      const b = Math.atan2(py - cy, px - cx);
      for (let j = 0; j < n; j++) add(cx, cy, b + (n > 1 ? (j / (n - 1) - 0.5) * m.r * deg : 0));
      break;
    }
    case "rain":
      for (let j = 0; j < n; j++) { const x = rng() * W; add(x, -8, Math.PI / 2 + (rng() - 0.5) * 0.3); }
      break;
    case "flower": case "star": case "heart": {
      for (let j = 0; j < n; j++) add(cx, cy, (j * 2 * Math.PI) / n);
      break;
    }
    case "beam": case "accel": case "bounce": case "stopgo": case "split": {
      const b = Math.atan2(py - cy, px - cx);
      for (let j = 0; j < n; j++) add(cx, cy, b + (n > 1 && m.t !== "beam" ? (j / (n - 1) - 0.5) * m.r * deg : 0));
      break;
    }
    case "timed": {
      for (let j = 0; j < n; j++) add(cx, cy, (j * 2 * Math.PI) / n + k * m.r * deg);
      break;
    }
    case "cross": {
      for (let arm = 0; arm < 4; arm++) add(cx, cy, (arm * Math.PI) / 2);
      break;
    }
    case "homing": {
      const b = Math.atan2(py - cy, px - cx);
      for (let j = 0; j < n; j++) add(cx, cy, b + (j - (n - 1) / 2) * 0.35);
      break;
    }
    case "sideL": case "sideR": {
      const left = m.t === "sideL";
      for (let j = 0; j < n; j++) {
        const y = rng() * H * 0.78;
        const a = (left ? 0 : Math.PI) + (rng() - 0.5) * 2 * Math.abs(m.r) * deg;
        add(left ? -8 : W + 8, y, a);
      }
      break;
    }
    case "corner": {
      for (const [ox, oy] of [[-8, -8], [W + 8, -8], [-8, H * 0.6], [W + 8, H * 0.6]] as const) {
        const b = Math.atan2(py - oy, px - ox);
        for (let j = 0; j < n; j++) add(ox, oy, b + (n > 1 ? (j / (n - 1) - 0.5) * m.r * deg : 0));
      }
      break;
    }
    case "sweep": {
      const b = Math.PI / 2 + Math.sin(k * 0.25) * m.r * deg;
      for (let j = 0; j < n; j++) add(cx, cy, b + (n > 1 ? (j / (n - 1) - 0.5) * 0.5 : 0));
      break;
    }
  }
}

/** 撃ち始めの数秒後の弾の位置を返す */
export function snapshot(stage0: Stage): { bullets: Dot[]; at: number } {
  // 連戦は、最初の場面で描く
  const first0 = stage0.mode === "sequence" ? stage0.waves?.[0] : undefined;
  const stage = first0 ? { ...stage0, mode: (first0.kind === "boss" ? "boss" : "survive") as Stage["mode"], emitters: first0.emitters, durationSec: first0.durationSec } : stage0;
  const boss = stage.mode !== "survive";
  const starts = stage.emitters.filter((m) => boss || m.t !== "rain").map((m) => (boss ? 0 : m.s));
  const first = starts.length ? Math.min(...starts) : 0;
  const at = Math.min((stage.durationSec === 0 ? 600 : stage.durationSec) - 0.1, first + 3.5);
  const rng = mulberry(12345);
  const px = W / 2, py = H * 0.85, dt = 1 / 60;
  const bullets: Array<Dot & { vx: number; vy: number }> = [];
  const next = stage.emitters.map((m) => (boss ? 0 : m.s));
  const shots = stage.emitters.map(() => 0);
  const bossPos = { x: W / 2, y: H * 0.18 };
  for (let t = 0; t < at; t += dt) {
    stage.emitters.forEach((m, idx) => {
      if (boss && !(m.ph === 0 || m.ph === 1)) return;
      const end = boss ? Infinity : Math.min(m.e, stage.durationSec);
      while (t >= next[idx]! && next[idx]! < end) {
        const cx = boss && m.p !== 1 ? bossPos.x : m.x * W, cy = boss && m.p !== 1 ? bossPos.y : m.y * H;
        emit(m, shots[idx]!, cx, cy, px, py, rng, bullets);
        shots[idx]!++;
        next[idx]! += Math.max(0.05, m.i);
      }
    });
    for (const b of bullets) { b.x += b.vx * dt; b.y += b.vy * dt; }
  }
  return { bullets: bullets.filter((b) => b.x > -10 && b.x < W + 10 && b.y > -10 && b.y < H + 10), at };
}
