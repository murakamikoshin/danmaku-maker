import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import { createSim, decodeReplay } from "../src/fullsim.js";
import { rankedStage, rankedScore, rankedCompare, ratingDelta, rankOf, RANKED_DURATION } from "../src/ranked.js";

interface Fixture {
  seed: number;
  stage: { mode: string; durationSec: number; lifeMode: string; lifeCount: number; emitters: Record<string, unknown>[] };
  style: number;
  replay: string;
  steps: number;
  ticks: number;
  grazes: number;
  fullBullets: number;
  fullHashCoarse: number;
  fullGrazes: number;
  fullTicks: number;
}
const fixtures: Fixture[] = JSON.parse(readFileSync(new URL("./fixtures/ranked_fixtures.json", import.meta.url), "utf8"));

/** 比べる項目だけ取り出す(アプリは標準の値を書き出さないので、無いものは 0 とみなす) */
const norm = (e: Record<string, unknown>) => ({
  t: e.t, x: e.x, y: e.y, s: e.s, e: e.e, i: e.i, c: e.c, v: e.v, r: e.r, k: e.k, a: (e.a as number | undefined) ?? 0,
});

describe("ランク戦: サーバーの計算はアプリ(Swift)と同じ", () => {
  it("照合データがある", () => {
    expect(fixtures.length).toBe(32);
    expect(Math.max(...fixtures.map((f) => f.ticks))).toBeGreaterThan(1500);
  });

  const seeds = [...new Set(fixtures.map((f) => f.seed))];
  for (const seed of seeds) {
    const f = fixtures.find((x) => x.seed === seed)!;
    it(`種 ${seed} から同じステージができる`, () => {
      const st = rankedStage(seed);
      expect(st.durationSec).toBe(f.stage.durationSec);
      expect(st.lifeMode).toBe(f.stage.lifeMode);
      expect(st.lifeCount).toBe(f.stage.lifeCount);
      expect(st.emitters.map((e) => norm(e as unknown as Record<string, unknown>))).toEqual(f.stage.emitters.map(norm));
    });
    it(`種 ${seed} を無敵で最後まで進めた弾の様子が同じ`, () => {
      const sim = createSim(rankedStage(seed), "standard");
      sim.setInvincible(true);
      while (sim.outcome === "playing" && sim.tick < 200 * 120) sim.step(0, 0);
      const r = sim.result();
      expect([sim.outcome, sim.tick, r.bulletCount, r.bulletHashCoarse, sim.grazeCount]).toEqual(["cleared", f.fullTicks, f.fullBullets, f.fullHashCoarse, f.fullGrazes]);
    });
  }

  for (const f of fixtures) {
    it(`種 ${f.seed} 動き${f.style}: 生き残ったステップとかすった数が同じ`, () => {
      const d = decodeReplay(f.replay, 40_000)!;
      expect(d.steps).toBe(f.steps);
      expect(rankedScore(f.seed, d.moves, d.steps)).toEqual({ ticks: f.ticks, grazes: f.grazes });
    });
  }
});

describe("ランク戦: 勝ち負けとレート", () => {
  it("長く生き残った方、同じならかすった数が多い方の勝ち", () => {
    expect(rankedCompare({ ticks: 100, grazes: 0 }, { ticks: 99, grazes: 9 })).toBe(1);
    expect(rankedCompare({ ticks: 100, grazes: 1 }, { ticks: 100, grazes: 2 })).toBe(-1);
    expect(rankedCompare({ ticks: 100, grazes: 2 }, { ticks: 100, grazes: 2 })).toBe(0);
  });
  it("上限は 180 秒", () => expect(RANKED_DURATION).toBe(180));
  it("レート: 同じ強さなら勝ちで +16(10戦目以降)、ボット相手は半分、最初の10戦は大きく動く", () => {
    expect(ratingDelta(1000, 1000, 1, 20, false)).toBe(16);
    expect(ratingDelta(1000, 1000, 0, 20, false)).toBe(-16);
    expect(ratingDelta(1000, 1000, 1, 20, true)).toBe(8);
    expect(ratingDelta(1000, 1000, 1, 0, false)).toBe(24);
    expect(ratingDelta(1000, 1000, 0.5, 20, false)).toBe(0);
    expect(ratingDelta(1000, 1400, 1, 20, false)).toBeGreaterThan(ratingDelta(1000, 1000, 1, 20, false));   // 強い相手に勝つほど多く上がる
  });
  it("ランクの帯", () => {
    expect([rankOf(999), rankOf(1000), rankOf(1150), rankOf(1300), rankOf(1450), rankOf(1600)]).toEqual(["bronze", "silver", "gold", "platinum", "diamond", "master"]);
  });
});
