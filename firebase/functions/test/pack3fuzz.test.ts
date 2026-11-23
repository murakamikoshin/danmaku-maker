import { describe, expect, it } from "vitest";
import { createSim } from "../src/fullsim.js";
import { PACK3_PATTERNS } from "../src/pack3.js";
import { validatePublish } from "../src/validate.js";

/** 1.4.2: 弾幕パック3・高さ・段階なし/2段階を、でたらめな設定で受け付け→計算しても、落ちない・おかしな数にならない */
function rand(seed: number) { return () => { seed = (seed * 1103515245 + 12345) & 0x7fffffff; return seed / 0x7fffffff; }; }

function run(stage: Parameters<typeof createSim>[0], seconds: number, label: string) {
  const sim = createSim(stage, "standard");
  const r = rand(7);
  let maxCount = 0;
  while (sim.outcome === "playing" && sim.tick < seconds * 120) {
    sim.step(Math.floor(r() * 9) - 4, Math.floor(r() * 9) - 4);
    maxCount = Math.max(maxCount, sim.bullets.length);
    for (const b of sim.bullets) {
      if (!Number.isFinite(b.x) || !Number.isFinite(b.y) || !Number.isFinite(b.vx) || !Number.isFinite(b.vy)) throw new Error(`${label}: 数でない弾(script ${b.script})`);
    }
  }
  expect(maxCount, label).toBeLessThanOrEqual(1600);
}

const base = (o: object) => ({ name: "fuzz", authorName: "t", formatVersion: 1, clearReplay: "AQIDBAUGBwg=", ...o });

describe("弾幕パック3の揺さぶり(受け付け → 計算)", () => {
  it("すべてのパターン × 狙い方 × 左右反転 × 生き残り/ボス戦 × 数で、受け付けられて計算が壊れない", () => {
    const r = rand(42);
    let n = 0;
    for (const t of PACK3_PATTERNS) for (const aim of [undefined, 1, 2]) for (const mir of [undefined, 1]) for (const boss of [false, true]) for (const c of [1, 8, 36]) {
      const rotatable = t !== "lightning" && t !== "pincer";
      const em = { t, x: Math.round(r() * 100) / 100, y: Math.round(r() * 60) / 100, s: 0, e: 20, i: 0.05 + Math.round(r() * 300) / 100, c, v: 1 + Math.round(r() * 16) / 4, r: Math.round(r() * 180) - 90, k: c % 5, ph: 0,
        ...(boss ? { p: 1 } : {}), ...(rotatable ? { a: 45 } : {}), ...(aim ? { aim } : {}), ...(mir ? { mir } : {}), sh: 3 };
      const input = boss ? base({ mode: "boss", durationSec: 60, bossHp: 1000, bossMove: 5, emitters: [em] }) : base({ mode: "survive", durationSec: 20, emitters: [em] });
      const v = validatePublish(input);
      if (!v.ok) {
        // ランダムの狙い方が効かないパターンなどは、アプリが送らない形なので、断られてよい(理由だけ確かめる)
        expect(v.error, `${t} aim=${aim}`).toMatch(/emitter-range/);
        continue;
      }
      expect(v.stage.needs, t).toBe(7);
      run(v.stage as never, 6, `${t} aim=${aim} mir=${mir} boss=${boss} c=${c}`);
      n++;
    }
    expect(n).toBeGreaterThan(300);
  });

  it("左右からの高さ × 反転、段階 1・2 × 撃つ段階、連戦の段階なしも壊れない", () => {
    for (const t of ["sideL", "sideR"]) for (const yr of [1, 2]) for (const mir of [undefined, 1]) {
      const v = validatePublish(base({ mode: "survive", durationSec: 20, emitters: [{ t, x: 0.5, y: 0.2, s: 0, e: 20, i: 0.1, c: 36, v: 5, r: 90, k: 1, ph: 0, yr, ...(mir ? { mir } : {}) }] }));
      expect(v.ok).toBe(true);
      if (v.ok) run(v.stage as never, 6, `${t} yr=${yr}`);
    }
    for (const phases of [1, 2]) for (const mode of ["boss", "damage"]) {
      const ems = [{ t: "needle", x: 0.5, y: 0.2, s: 0, e: 30, i: 0.2, c: 5, v: 3, r: 30, k: 0, ph: phases === 2 ? 2 : 0 }, { t: "ring", x: 0.5, y: 0.2, s: 0, e: 30, i: 0.3, c: 12, v: 2, r: 0, k: 1, ph: 0 }];
      const v = validatePublish(base({ mode, durationSec: 30, ...(mode === "boss" ? { bossHp: 100 } : {}), bossMove: 2, phases, emitters: ems }));
      expect(v.ok, `${mode} phases=${phases}`).toBe(true);
      if (v.ok) run(v.stage as never, 32, `${mode} phases=${phases}`);
    }
    const seq = validatePublish(base({ mode: "sequence", durationSec: 72, emitters: [], waves: [
      { kind: "survive", durationSec: 10, emitters: [{ t: "pincer", x: 0.5, y: 0.2, s: 0, e: 10, i: 0.5, c: 3, v: 2, r: 0, k: 0, ph: 0 }] },
      { kind: "boss", durationSec: 60, bossHp: 100, bossMove: 0, phases: 1, emitters: [{ t: "whirlwind", x: 0.5, y: 0.2, s: 0, e: 30, i: 0.3, c: 6, v: 2, r: 0, k: 0, ph: 0 }] }] }));
    expect(seq.ok).toBe(true);
    if (seq.ok) run(seq.stage as never, 74, "seq");
  });
});
