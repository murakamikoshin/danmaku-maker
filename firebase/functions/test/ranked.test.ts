import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import { createSim, decodeReplay } from "../src/fullsim.js";
import { rankedStage, rankedScore, rankedCompare, ratingDelta, rankOf, RANKED_DURATION } from "../src/ranked.js";
import { encodeReplay, GONE_GRACE_MS, GONE_LAG_MS, MAX_RANKED_REPLAY, opponentGone, queueRowExpired, safeName, SEEDS_PER_WEEK, weekSeeds } from "../src/rankedfns.js";
import { pairKey, PAIR_RATED_PER_DAY } from "../src/abuse.js";

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

describe("弾幕バトルの不正対策", () => {
  it("決まった対戦が始まったら、待ち行列の行は使わない(入り直しで同じ対戦に戻れない)", () => {
    const now = 1_000_000;
    expect(queueRowExpired({ r: 1000, at: now - 1000, m: "x", s: now + 3000 }, now)).toBe(false);
    expect(queueRowExpired({ r: 1000, at: now - 5000, m: "x", s: now - 1 }, now)).toBe(true);
    // 始まる時刻を持たない古い行は、待ち始め + 6.5 秒(START_DELAY_MS)で始まったとみなす
    expect(queueRowExpired({ r: 1000, at: now - 6500, m: "x" }, now)).toBe(true);
    expect(queueRowExpired({ r: 1000, at: now - 6000, m: "x" }, now)).toBe(false);
    expect(queueRowExpired({ r: 1000, at: now - 1000 }, now)).toBe(false);
    expect(queueRowExpired({ r: 1000, at: now - 16_000 }, now)).toBe(true);
    expect(queueRowExpired(null, now)).toBe(true);
  });
  it("相手がいなくなったか(位置の更新が止まった・一度も来ない・大きく遅れた)", () => {
    const start = 1_000_000;
    expect(opponentGone(null, null, start, start + GONE_GRACE_MS - 1)).toBe(false);
    expect(opponentGone(null, null, start, start + GONE_GRACE_MS + 1)).toBe(true);
    // 遅い端末: ゲームの時計が 30 秒以上遅れていても、更新が続いていれば、いなくなったとはしない
    expect(opponentGone({ t: 60 * 120 }, null, start, start + 60_000 + 40_000)).toBe(false);
    expect(opponentGone({ t: 60 * 120 }, { t: 59 * 120, at: start + 70_000 }, start, start + 100_000)).toBe(false);
    // 遅れだけで決めるのは GONE_LAG_MS(75 秒)から
    expect(GONE_LAG_MS).toBeGreaterThanOrEqual(75_000);
    expect(opponentGone({ t: 60 * 120 }, null, start, start + 60_000 + GONE_LAG_MS - 1)).toBe(false);
    expect(opponentGone({ t: 60 * 120 }, null, start, start + 60_000 + GONE_LAG_MS + 1)).toBe(true);
    // 位置の更新が止まった: 前に見た t のまま 30 秒過ぎたら、いない(遅れが小さくても)
    const seen = { t: 60 * 120, at: start + 61_000 };
    expect(opponentGone({ t: 60 * 120 }, seen, start, start + 61_000 + GONE_GRACE_MS - 1)).toBe(false);
    expect(opponentGone({ t: 60 * 120 }, seen, start, start + 61_000 + GONE_GRACE_MS)).toBe(true);
    // まだ遊んでいる(遅れが少ない)
    expect(opponentGone({ t: 100 * 120 }, null, start, start + 102_000)).toBe(false);
  });
  it("相手に見せる名前は NG ワードの検査を通ったものだけ", () => {
    expect(safeName("アリス")).toBe("アリス");
    expect(safeName("し​ね")).toBe("Player");
    expect(safeName("a".repeat(30))).toBe("Player");
    expect(safeName(undefined)).toBe("Player");
    expect(safeName("  ")).toBe("Player");
  });
  it("週の種に合言葉を混ぜる(合言葉が無ければ、これまでと同じ)", () => {
    const plain = weekSeeds(2900, "");
    expect(weekSeeds(2900, "")).toEqual(plain);
    const salted = weekSeeds(2900, "secret-a");
    expect(salted).toHaveLength(SEEDS_PER_WEEK);
    expect(salted).not.toEqual(plain);
    expect(weekSeeds(2900, "secret-a")).toEqual(salted);
    expect(weekSeeds(2900, "secret-b")).not.toEqual(salted);
    expect(salted.every((s) => Number.isInteger(s) && s >= 0 && s < 2 ** 32)).toBe(true);
  });
  it("同じ二人の 1 日の数は、並び順によらず同じ鍵で数える", () => {
    const now = Date.UTC(2026, 10, 15, 3);
    expect(pairKey("b", "a", now)).toBe(pairKey("a", "b", now));
    expect(pairKey("a", "b", now + 86_400_000)).not.toBe(pairKey("a", "b", now));
    expect(PAIR_RATED_PER_DAY).toBe(3);
  });
  it("記録の文字数の上限は、いちばん長い記録(毎ステップ向きを変える)より大きい", () => {
    const steps = (RANKED_DURATION + 3) * 120 + 144;
    const m = new Int8Array(steps * 2);
    for (let i = 0; i < steps; i++) m[i * 2] = i % 2 ? 3 : -3;
    const enc = encodeReplay(m, steps);
    expect(enc.length).toBeLessThanOrEqual(MAX_RANKED_REPLAY);
    expect(decodeReplay(enc, steps)?.steps).toBe(steps);
  });
});
