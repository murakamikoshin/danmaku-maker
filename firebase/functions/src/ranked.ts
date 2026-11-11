import { createSim, type SimStage } from "./fullsim.js";
import { generateStage, GEN_MAX_HARD } from "./swipegen.js";
import type { Emitter } from "./validate.js";

/**
 * ランク戦(リアルタイム対戦)のステージと、勝ち負けの決め方。アプリの RankedStage の移植。
 * 種から、だんだん激しくなる 180 秒の耐久を作る(15 秒の区切り 12 個に、スワイプ弾幕のランダム生成を難しくしながら並べる)。
 * 計算の順番を変えない(アプリと 1 ビットも違わないこと)。
 */
export const RANKED_SEGMENT_SEC = 15;
export const RANKED_SEGMENTS = 12;
export const RANKED_DURATION = RANKED_SEGMENT_SEC * RANKED_SEGMENTS;

export const rankedHard = (k: number): number => Math.min(GEN_MAX_HARD, 60 + k * 85);
export const rankedSegmentSeed = (seed: number, k: number): number => ((seed >>> 0) + Math.imul(k, 0x9e3779b1)) >>> 0;

export function rankedStage(seed: number): SimStage {
  const emitters: Emitter[] = [];
  for (let k = 0; k < RANKED_SEGMENTS; k++) {
    const part = generateStage(rankedSegmentSeed(seed, k), rankedHard(k));
    const start = k * RANKED_SEGMENT_SEC;
    for (const e of part.emitters) emitters.push({ ...e, s: e.s + start, e: start + RANKED_SEGMENT_SEC });
  }
  return { mode: "survive", durationSec: RANKED_DURATION, emitters, lifeMode: "lives", lifeCount: 1 };
}

export interface RankedScore { ticks: number; grazes: number }

/** 操作の記録([dx, dy, ...])から結果を計算する。記録が尽きたら、その場で落ちたものとする */
export function rankedScore(seed: number, moves: ArrayLike<number>, moveCount: number): RankedScore {
  const sim = createSim(rankedStage(seed), "standard");
  const limit = (RANKED_DURATION + 3) * 120 + 144;
  while (sim.outcome === "playing" && sim.tick < limit) {
    const k = sim.tick;
    if (k >= moveCount) break;
    sim.step(moves[k * 2]!, moves[k * 2 + 1]!);
  }
  return { ticks: sim.tick, grazes: sim.grazeCount };
}

/** 1 = a の勝ち、-1 = b の勝ち、0 = 引き分け */
export function rankedCompare(a: RankedScore, b: RankedScore): number {
  if (a.ticks !== b.ticks) return a.ticks > b.ticks ? 1 : -1;
  if (a.grazes !== b.grazes) return a.grazes > b.grazes ? 1 : -1;
  return 0;
}

// ---- レート(Elo 方式) ----
export const RATING_START = 1000;
/** 最初の 10 戦は大きく動かす */
export const ratingK = (games: number): number => (games < 10 ? 48 : 32);
/** 勝ち = 1、引き分け = 0.5、負け = 0。ボット相手は増減を半分にする。整数に丸める */
export function ratingDelta(mine: number, theirs: number, result: 1 | 0.5 | 0, games: number, vsBot: boolean): number {
  const expected = 1 / (1 + Math.pow(10, (theirs - mine) / 400));
  const d = ratingK(games) * (result - expected) * (vsBot ? 0.5 : 1);
  return Math.round(d);
}

/** レートの帯から、ランクを決める */
export const RANKS = ["bronze", "silver", "gold", "platinum", "diamond", "master"] as const;
export type Rank = (typeof RANKS)[number];
export function rankOf(rating: number): Rank {
  if (rating >= 1600) return "master";
  if (rating >= 1450) return "diamond";
  if (rating >= 1300) return "platinum";
  if (rating >= 1150) return "gold";
  if (rating >= 1000) return "silver";
  return "bronze";
}
