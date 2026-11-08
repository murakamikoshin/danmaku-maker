// 長いプレイ(生成ステージ・ボットで 10 クリップ以上)の入力を書き出す。SWIPE_LONGRUNS_IN があるときだけ動く。
// 書き出した入力を Swift が遊び、結果を fixtures/swipe_longruns.json に置く。比べるのは swipe_longruns.test.ts
import { describe, it } from "vitest";
import { writeFileSync } from "node:fs";
import { GEN_SEEDS } from "../src/swipegen_seeds.js";
import { GEN_AUTHOR, GEN_CLIP_AT, genId, generateStage } from "../src/swipegen.js";
import { pickFeed, type FeedEntry } from "../src/swipe.js";
import { botCanClear } from "../src/swipebot.js";

const out = process.env.SWIPE_LONGRUNS_IN;
describe.skipIf(!out)("長いプレイの入力を作る", () => {
  it("書き出す", () => {
    const pool: FeedEntry[] = GEN_SEEDS.map(([seed, hard, d]) => ({ id: genId(seed, hard), d, author: GEN_AUTHOR }));
    const runs: { seed: number; clips: { go: number[]; moves: number[]; skipped: boolean }[] }[] = [];
    for (let r = 0; r < 12; r++) {
      const seed = (r * 2654435761 + 12345) >>> 0;
      const used = new Set<string>();
      let streak = 0;
      const clips: { go: number[]; moves: number[]; skipped: boolean }[] = [];
      for (let i = 0; i < 16; i++) {
        const e = pickFeed(pool, seed, i, streak, used, new Set());
        if (!e) break;
        used.add(e.id);
        const m = e.id.match(/^G([0-9a-f]{8})([0-9]{3})$/)!;
        const stage = generateStage(parseInt(m[1]!, 16), parseInt(m[2]!, 10));
        const bot = botCanClear(stage, GEN_CLIP_AT);
        const go: number[] = [];
        for (let k = 0; k < 60; k++) { go.push(k < 20 ? ((r + k) % 3) - 1 : 0, k < 20 ? ((r * 2 + k) % 3) - 1 : 0); }
        clips.push({ go, moves: Array.from(bot.moves.subarray(0, bot.steps * 2)), skipped: false });
        if (!bot.ok) break;
        streak += 1;
      }
      runs.push({ seed, clips });
    }
    writeFileSync(out!, JSON.stringify({ pool, runs }));
  });
}, 1_800_000);
