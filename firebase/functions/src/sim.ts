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
    case "sweep": {
      const b = Math.PI / 2 + Math.sin(k * 0.25) * m.r * deg;
      for (let j = 0; j < n; j++) add(cx, cy, b + (n > 1 ? (j / (n - 1) - 0.5) * 0.5 : 0));
      break;
    }
  }
}

/** 撃ち始めの数秒後の弾の位置を返す */
export function snapshot(stage: Stage): { bullets: Dot[]; at: number } {
  const boss = stage.mode === "boss";
  const starts = stage.emitters.filter((m) => boss || m.t !== "rain").map((m) => (boss ? 0 : m.s));
  const first = starts.length ? Math.min(...starts) : 0;
  const at = Math.min(stage.durationSec - 0.1, first + 3.5);
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
        const cx = boss ? bossPos.x : m.x * W, cy = boss ? bossPos.y : m.y * H;
        emit(m, shots[idx]!, cx, cy, px, py, rng, bullets);
        shots[idx]!++;
        next[idx]! += Math.max(0.05, m.i);
      }
    });
    for (const b of bullets) { b.x += b.vx * dt; b.y += b.vy * dt; }
  }
  return { bullets: bullets.filter((b) => b.x > -10 && b.x < W + 10 && b.y > -10 && b.y < H + 10), at };
}
