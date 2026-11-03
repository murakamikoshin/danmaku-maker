import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import { genId, generateStage, parseGenId } from "../src/swipegen.js";

interface Gen { seed: number; hard: number; id: string; stage: { emitters: Record<string, number | string>[] } }
const data: { generated: Gen[] } = JSON.parse(readFileSync(new URL("./fixtures/swipe_fixtures.json", import.meta.url), "utf8"));
const norm = (e: Record<string, unknown>) => ({ t: e.t, x: e.x, y: e.y, s: e.s, e: e.e, i: e.i, c: e.c, v: e.v, r: e.r, k: e.k, a: e.a ?? 0 });

describe("ランダム生成ステージは、アプリ(Swift)と同じものができる", () => {
  it("正解データが十分にある", () => { expect(data.generated.length).toBeGreaterThanOrEqual(30); });
  for (const g of data.generated) {
    it(`種 ${g.seed} 難しさ ${g.hard}`, () => {
      const s = generateStage(g.seed, g.hard);
      expect(s.emitters.map((e) => norm(e as unknown as Record<string, unknown>))).toEqual(g.stage.emitters.map((e) => norm(e)));
      expect(genId(g.seed, g.hard)).toBe(g.id);
      expect(parseGenId(g.id)).toEqual({ seed: g.seed, hard: g.hard });
    });
  }
  it("おかしな ID は読まない", () => {
    expect(parseGenId("R000")).toBeNull();
    expect(parseGenId("Gzzzzzzzz000")).toBeNull();
    expect(parseGenId("G00000001000")).not.toBeNull();
  });
});

import { botCanClear } from "../src/swipebot.js";
import { GEN_CLIP_AT } from "../src/swipegen.js";
import { GEN_SEEDS } from "../src/swipegen_seeds.js";

describe("確認済みの生成ステージの一覧", () => {
  it("十分な数があり、ばらけていて、重複しない", () => {
    expect(GEN_SEEDS.length).toBeGreaterThan(300);
    expect(new Set(GEN_SEEDS.map(([s, h]) => genId(s, h))).size).toBe(GEN_SEEDS.length);
    const ds = GEN_SEEDS.map((r) => r[2]);
    expect(Math.min(...ds)).toBeLessThan(150);
    expect(Math.max(...ds)).toBeGreaterThan(800);
  });
  it("いくつか取り出して、もう一度ボットでクリアできる", () => {
    for (const i of [0, 97, 211, 333, GEN_SEEDS.length - 1]) {
      const [seed, hard] = GEN_SEEDS[i]!;
      expect(botCanClear(generateStage(seed, hard), GEN_CLIP_AT).ok, `${seed}/${hard}`).toBe(true);
    }
  }, 120_000);
});
