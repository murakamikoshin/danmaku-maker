import { existsSync, readFileSync } from "node:fs";
import { expect, it } from "vitest";
import { decodeReplay, simulate } from "../src/fullsim.js";
// 速い照合用(tools/parity.sh から使う。Swift の結果ファイルが無いときは何もしない)
it("parity", () => {
  if (!existsSync("/tmp/parity_swift.json")) return;
  const rows = JSON.parse(readFileSync("/tmp/parity_swift.json", "utf8"));
  const bad: string[] = [];
  for (const r of rows) {
    const played = r.replay ? decodeReplay(r.replay, 400_000) : null;
    const x = simulate(r.stage, played ? played.moves : new Int8Array(0), played ? played.steps : 0, "standard", undefined, r.month ?? 0);
    const ok = x.outcome === r.outcome && x.tick === r.steps && x.bulletCount === r.n && (r.outcome === "hit" || x.bulletHashCoarse === r.coarse) && (r.life === undefined || x.lifeLeft === r.life);
    if (!ok) bad.push(`${r.t} aw=${r.aw} mir=${r.mir}: swift ${r.outcome}/${r.steps}/${r.n}/${r.coarse}/${r.life} ts ${x.outcome}/${x.tick}/${x.bulletCount}/${x.bulletHashCoarse}/${x.lifeLeft}`);
  }
  expect(bad, bad.join("\n")).toEqual([]);
  expect(rows.length).toBeGreaterThan(0);
});
