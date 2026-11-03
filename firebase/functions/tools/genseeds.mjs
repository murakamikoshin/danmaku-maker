// ランダム生成ステージの「ボットでクリアできる種」の一覧を作る: node tools/genseeds.mjs <担当番号> <担当数> <候補の数> <出力ファイル>
// 事前に `npm run build`。結果は [[種, 難しさ, 目安の難しさ(千分率)], ...]
import { writeFileSync } from "node:fs";
import { generateStage, GEN_CLIP_AT } from "../lib/swipegen.js";
import { botCanClear } from "../lib/swipebot.js";
import { sampleStage, estimatedClearRate, WINDOW } from "../lib/swipe.js";

const [shard, total, count, out] = [Number(process.argv[2]), Number(process.argv[3]), Number(process.argv[4]), process.argv[5]];
const result = [];
for (let i = shard; i < count; i += total) {
  const seed = (Math.imul(i + 1, 2654435761) + 12345) >>> 0;
  const hard = (i * 37) % 1000;
  const stage = generateStage(seed, hard);
  const ok = botCanClear(stage, GEN_CLIP_AT).ok;
  if (ok) {
    const { counts } = sampleStage(stage);
    const j = Math.round(GEN_CLIP_AT / 0.5);
    const avg = counts.slice(j, j + WINDOW).reduce((a, b) => a + b, 0) / WINDOW;
    result.push([seed, hard, Math.round(estimatedClearRate(avg) * 1000)]);
  }
  if (i % 40 === shard) console.error(`shard ${shard}: ${i}/${count} (ok ${result.length})`);
  writeFileSync(out, JSON.stringify(result));
}
writeFileSync(out, JSON.stringify(result));
