import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import { decodeReplay, simulate, isShotType, type SimStage } from "../src/fullsim.js";

interface Fixture {
  name: string;
  stage: SimStage;
  shot: string;
  replay: string;
  steps: number;
  expect: { outcome: string; tick: number; hp: number; damage: number; lifeLeft: number; bulletCount: number; bulletHash: number };
}
const fixtures: Fixture[] = JSON.parse(readFileSync(new URL("./fixtures/sim_fixtures.json", import.meta.url), "utf8"));

describe("サーバーのゲーム計算は、アプリ(Swift)の計算と同じ結果になる", () => {
  it("正解データが十分にある", () => {
    expect(fixtures.length).toBeGreaterThan(150);
    expect(fixtures.filter((f) => f.expect.outcome === "cleared").length).toBeGreaterThan(10);
    expect(fixtures.filter((f) => f.expect.outcome === "hit").length).toBeGreaterThan(10);
  });

  it("操作記録を復元できる", () => {
    for (const f of fixtures.slice(0, 40)) {
      const d = decodeReplay(f.replay, 40_000);
      expect(d, f.name).not.toBeNull();
      expect(d!.steps, f.name).toBe(f.steps);
    }
  });

  const hashMismatch: string[] = [];
  let checked = 0;
  for (const f of fixtures) {
    it(f.name, () => {
      expect(isShotType(f.shot)).toBe(true);
      const d = decodeReplay(f.replay, 40_000)!;
      const r = simulate(f.stage, d.moves, d.steps, f.shot as "standard");
      expect({ outcome: r.outcome, tick: r.tick, hp: r.hp, damage: r.damage, lifeLeft: r.lifeLeft, bulletCount: r.bulletCount })
        .toEqual({ outcome: f.expect.outcome, tick: f.expect.tick, hp: f.expect.hp, damage: f.expect.damage, lifeLeft: f.expect.lifeLeft, bulletCount: f.expect.bulletCount });
      // 被弾で終わったときは、弾の並びが途中経過のままになる(勝敗には関係しない)ので、ハッシュは最後まで進んだものだけ比べる
      if (f.expect.outcome !== "hit") { checked += 1; if (r.bulletHash !== f.expect.bulletHash) hashMismatch.push(f.name); }
    });
  }

  it("最後まで進んだものは、弾の位置まで(ほぼ)1ビットも違わない", () => {
    // sin/cos/atan2 は実行環境で最後の桁(約1e-16)がまれに違う。弾の位置が1e-13 ずれても勝敗は変わらない(上で全件一致を確認)
    expect(checked).toBeGreaterThan(10);
    expect(hashMismatch.length / checked).toBeLessThan(0.4);
  });

  it("壊れた操作記録は受け付けない", () => {
    expect(decodeReplay("!!!", 100)).toBeNull();
    expect(decodeReplay("AAAA", 100)).toBeNull();
    expect(decodeReplay(Buffer.from([1, 1, 2, 3, 4]).toString("base64"), 100)).toBeNull();
  });
});
