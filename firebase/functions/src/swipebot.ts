import type { SimStage } from "./fullsim.js";
import { PLAY_STEPS, prepareClip } from "./swipe.js";

/**
 * クリップを「ボットで実際にクリアできるか」確かめる(仕様書 4.1 章)。クリアできない区間は、スワイプ弾幕に出さない。
 * 先読み: 数ステップごとに、いくつかの動きを試して(先の様子を控えから進めて)、当たらず弾から一番離れられる動きを選ぶ。
 * ボットの動きは人が出せる速さ(1 ステップ最大 3.5px)に抑えてある。ボムは使わない(使えるぶん、人のほうが有利)。
 */
export interface BotOptions { every: number; horizon: number }
const SPEEDS = [6, 14];
const DIRS: [number, number][] = [[1, 0], [-1, 0], [0, 1], [0, -1], [1, 1], [1, -1], [-1, 1], [-1, -1]];
const MOVES: [number, number][] = [[0, 0], ...SPEEDS.flatMap((s) => DIRS.map(([x, y]) => [Math.round(x * s * (x && y ? 0.71 : 1)), Math.round(y * s * (x && y ? 0.71 : 1))] as [number, number]))];

export interface BotResult { ok: boolean; moves: Int8Array; steps: number }

export function botClear(stage: SimStage, at: number, opts: BotOptions = { every: 4, horizon: 24 }): BotResult {
  const sim = prepareClip(stage, at);
  const oc = (): string => sim.outcome;
  const moves = new Int8Array(PLAY_STEPS * 2);
  let n = 0;
  while (n < PLAY_STEPS && oc() === "playing") {
    const base = sim.snapshot();
    let best = -Infinity, bm = MOVES[0]!;
    for (const m of MOVES) {
      let survived = 0, minD2 = 1e9;
      for (let k = 0; k < opts.horizon; k++) {
        sim.step(m[0], m[1]);
        if (oc() === "hit") break;
        survived += 1;
        if (k % 4 === 3 || k === opts.horizon - 1) {
          const p = sim.player;
          for (const b of sim.bullets) {
            const dx = b.x - p.x, dy = b.y - p.y;
            const d = dx * dx + dy * dy;
            if (d < minD2) minD2 = d;
          }
        }
        if (oc() === "cleared") { survived = opts.horizon; break; }
      }
      const p = sim.player;
      const score = survived * 1000 + Math.min(Math.sqrt(minD2), 60) * 4 - Math.abs(p.x - 180) * 0.05 - (m[0] === 0 && m[1] === 0 ? 0 : 0.5);
      if (score > best) { best = score; bm = m; }
      sim.restore(base);
    }
    for (let k = 0; k < opts.every && n < PLAY_STEPS && oc() === "playing"; k++) {
      moves[n * 2] = bm[0]; moves[n * 2 + 1] = bm[1];
      sim.step(bm[0], bm[1]);
      n += 1;
    }
  }
  return { ok: oc() !== "hit", moves, steps: n };
}

/** 2 通りの細かさで試して、どちらかでクリアできればよい */
export function botCanClear(stage: SimStage, at: number): BotResult {
  const a = botClear(stage, at);
  if (a.ok) return a;
  return botClear(stage, at, { every: 2, horizon: 36 });
}
