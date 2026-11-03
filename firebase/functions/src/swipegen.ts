import { mulberry, type SimStage } from "./fullsim.js";
import type { Emitter } from "./validate.js";

/**
 * スワイプ弾幕のランダム生成ステージ(アプリの SwipeGenerator の移植)。同じ(種, 難しさ)から、アプリと同じステージを作る。
 * 値は整数から作るので、小数の誤差が出ない。並びや引く順番を変えない。
 */
export const GEN_DURATION = 12;
export const GEN_CLIP_AT = 1.5;
export const GEN_MAX_HARD = 999;
export const GEN_AUTHOR = "gen";
const PATTERNS = ["ring", "spiral", "aim", "rain", "sideL", "sideR", "corner", "flower", "star", "cross", "sweep"] as const;
const CAN_NOT_ROTATE = new Set(["rain", "sweep", "sideL", "sideR", "corner"]);

export function generateStage(seed: number, hardIn: number): SimStage {
  const h = Math.min(Math.max(Math.trunc(hardIn), 0), GEN_MAX_HARD);
  const rng = mulberry(seed >>> 0);
  const count = 2 + Math.trunc(h / 350);
  const emitters: Emitter[] = [];
  for (let n = 0; n < count; n++) {
    const pattern = PATTERNS[Math.floor(rng() * PATTERNS.length)]!;
    const x = (Math.floor(rng() * 60) + 20) / 100;
    const y = (Math.floor(rng() * 25) + 8) / 100;
    const s = Math.floor(rng() * 10) / 10;
    const intervalBase = Math.floor(rng() * 30) + 60;
    const countBase = Math.floor(rng() * 6) + 6;
    const speedBase = Math.floor(rng() * 10) + 14;
    const spin = Math.floor(rng() * 20) + 3;
    const spread = Math.floor(rng() * 60) + 10;
    const color = Math.floor(rng() * 5);
    const turn = (Math.floor(rng() * 8) - 4) * 45;

    const interval = Math.max(15, Math.trunc((intervalBase * (1000 - Math.trunc((h * 55) / 100))) / 1000));
    const c = countBase + Math.trunc((h * 14) / 1000);
    const v = (speedBase + Math.trunc((h * 8) / 1000)) / 10;
    const r = pattern === "aim" || pattern === "corner" ? spread : spin;
    emitters.push({ t: pattern, x, y, s, e: GEN_DURATION, i: interval / 100, c, v, r, k: color, ph: 0, a: CAN_NOT_ROTATE.has(pattern) ? 0 : turn, p: 0 } as unknown as Emitter);
  }
  return { mode: "survive", durationSec: GEN_DURATION, emitters };
}

export const genId = (seed: number, hard: number): string => "G" + (seed >>> 0).toString(16).padStart(8, "0") + String(Math.min(Math.max(hard, 0), GEN_MAX_HARD)).padStart(3, "0");

export function parseGenId(id: string): { seed: number; hard: number } | null {
  if (id.length !== 12 || id[0] !== "G" || !/^G[0-9a-f]{8}[0-9]{3}$/.test(id)) return null;
  return { seed: parseInt(id.slice(1, 9), 16), hard: parseInt(id.slice(9, 12), 10) };
}
