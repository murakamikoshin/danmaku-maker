import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import type { SimStage } from "../src/fullsim.js";
import { SwipeScoring, candidatesOf, playRun, prepareClip, rankingKey, sampleStage, pickCandidates, type ClipInput, type FeedEntry } from "../src/swipe.js";

interface RunCase { seed: number; clips: { go: number[]; moves: number[]; skipped: boolean }[]; clipIDs: string[]; scoreAfterEachClip: string[]; score: string; streak: number; bestStreak: number; clipsPlayed: number; clipsCleared: number; bombs: number; grazes: number; endedByHit: boolean; abandoned: boolean; invalid: string | null }
interface Case { name: string; stage: SimStage; counts: number[]; gaps: boolean[]; candidates: { at: number; total: number }[]; prepared: { at: number; px: number; py: number; bulletCount: number; hashCoarse: number; tick: number }[]; runs: RunCase[] }
const data: { pool: FeedEntry[]; cases: Case[] } = JSON.parse(readFileSync(new URL("./fixtures/swipe_fixtures.json", import.meta.url), "utf8"));
const clipAt = (id: string) => ((parseInt(id.slice(1), 10) || 0) % 4) * 2;

describe("スワイプ弾幕: サーバーの計算は、アプリ(Swift)と同じ結果になる", () => {
  it("正解データが十分にある", () => {
    expect(data.cases.length).toBeGreaterThan(40);
    expect(data.cases.some((c) => c.runs.some((r) => r.grazes > 50))).toBe(true);
    expect(data.cases.some((c) => c.runs.some((r) => r.endedByHit))).toBe(true);
    expect(data.cases.some((c) => c.runs.some((r) => r.bombs > 0))).toBe(true);
    expect(data.cases.filter((c) => c.candidates.length > 0).length).toBeGreaterThan(10);
  });

  for (const c of data.cases) {
    it(`${c.name}: 弾の数の並びと区間の候補`, () => {
      const s = sampleStage(c.stage);
      expect(s.counts).toEqual(c.counts);
      expect(s.gaps).toEqual(c.gaps);
      expect(candidatesOf(c.stage)).toEqual(c.candidates);
      expect(pickCandidates(c.counts, c.gaps)).toEqual(c.candidates);
    });
    it(`${c.name}: クリップの始まりの状態`, () => {
      for (const p of c.prepared) {
        const sim = prepareClip(c.stage, p.at);
        expect({ x: sim.player.x, y: sim.player.y, n: sim.bullets.length, tick: sim.tick }, `${p.at} 秒`).toEqual({ x: p.px, y: p.py, n: p.bulletCount, tick: p.tick });
        expect(sim.result().bulletHashCoarse, `${p.at} 秒`).toBe(p.hashCoarse);
      }
    });
    it(`${c.name}: 1 プレイの点数`, () => {
      for (const r of c.runs) {
        const clips: ClipInput[] = r.clips.map((k) => ({ go: k.go, goCount: k.go.length / 2, moves: k.moves, moveCount: k.moves.length / 2, skipped: k.skipped }));
        const got = playRun(r.seed, data.pool, new Set(["u3"]), (id) => ({ stage: c.stage, at: clipAt(id) }), clips);
        expect({ ids: got.clipIDs, each: got.scoreAfterEachClip, score: got.score.toString(), streak: got.streak, best: got.bestStreak, played: got.clipsPlayed, cleared: got.clipsCleared, bombs: got.bombs, grazes: got.grazes, hit: got.endedByHit, ab: got.abandoned, inv: got.invalid })
          .toEqual({ ids: r.clipIDs, each: r.scoreAfterEachClip, score: r.score, streak: r.streak, best: r.bestStreak, played: r.clipsPlayed, cleared: r.clipsCleared, bombs: r.bombs, grazes: r.grazes, hit: r.endedByHit, ab: r.abandoned, inv: r.invalid ?? null });
      }
    });
  }

  it("点数の式(手で計算できる値)", () => {
    const s = new SwipeScoring();
    s.beginClip();
    s.graze(1);
    expect(s.score).toBe(112n);   // 100 × 9 ÷ 8 = 112(切り捨て)
    s.clear(0);
    expect(s.streak).toBe(1);
    expect(rankingKey(12345n)).toBe("005" + "12345");
  });
});
