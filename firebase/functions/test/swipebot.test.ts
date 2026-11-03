import { describe, expect, it } from "vitest";
import type { SimStage } from "../src/fullsim.js";
import { botCanClear } from "../src/swipebot.js";
import { candidatesOf, playRun } from "../src/swipe.js";

const em = (t: string, o: object = {}) => ({ t, x: 0.5, y: 0.15, s: 0, e: 30, i: 0.3, c: 12, v: 2, r: 10, k: 1, ph: 0, a: 0, p: 0, ...o });
const ring: SimStage = { mode: "survive", durationSec: 30, emitters: [em("ring"), em("aim", { i: 0.4, c: 5, r: 40 })] as never };
const wall: SimStage = { mode: "survive", durationSec: 20, emitters: [em("rain", { i: 0.05, c: 6, v: 4 })] as never };

describe("スワイプ弾幕のボット", () => {
  it("クリアできる区間は、ボットの動きを再生するとほんとうにクリアになる", () => {
    const cands = candidatesOf(ring);
    expect(cands.length).toBeGreaterThan(0);
    const at = cands[0]!.at;
    const t0 = Date.now();
    const r = botCanClear(ring, at);
    expect(r.ok).toBe(true);
    expect(r.steps).toBe(1200);
    // 同じ動きを 1 プレイとして再計算すると、被弾せずにクリアになる(ボットと本番の計算が同じ)
    const run = playRun(1, [{ id: "R000", d: 850, author: "u" }], new Set(), () => ({ stage: ring, at }),
      [{ go: [], goCount: 0, moves: r.moves, moveCount: r.steps, skipped: false }]);
    expect(run.endedByHit).toBe(false);
    expect(run.clipsCleared).toBe(1);
    console.log("ボットの時間(ms)", Date.now() - t0);
  });

  it("どう動いても逃げられない弾幕は、クリアできないと判定する", () => {
    // 画面いっぱいに、自機の位置めがけて濃く降らせ続ける
    const dense: SimStage = { mode: "survive", durationSec: 20, emitters: [em("rain", { i: 0.05, c: 40, v: 4 }), em("aim", { i: 0.05, c: 30, r: 360, v: 3 })] as never };
    const at = candidatesOf(dense)[0]?.at ?? 2;
    const r = botCanClear(dense, at);
    expect(r.ok).toBe(false);
  }, 120_000);

  it("雨の弾幕でも動ける", () => {
    expect(candidatesOf(wall).length).toBeGreaterThan(0);
  });
});
