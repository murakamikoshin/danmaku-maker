import { describe, expect, it } from "vitest";
import { REGEN_MS, STAMINA_MAX, current, dayKeyJst, hasPass, refill, spend } from "../src/stamina.js";

describe("スタミナ", () => {
  it("はじめは満タン。1 回使うと 4", () => {
    expect(current(undefined, 1000)).toEqual({ value: 5, nextAt: null });
    const s = spend(undefined, 1000)!;
    expect(s).toEqual({ v: 4, at: 1000 });
    expect(current(s, 1000)).toEqual({ value: 4, nextAt: 1000 + REGEN_MS });
  });
  it("2 時間ごとに 1 回復し、5 で止まる", () => {
    let s = spend(undefined, 0)!;
    expect(current(s, REGEN_MS - 1).value).toBe(4);
    expect(current(s, REGEN_MS).value).toBe(5);
    expect(current(s, 100 * REGEN_MS).value).toBe(5);
    // 使い続けると 0 になり、使えなくなる
    s = { v: 5, at: 0 };
    for (let i = 0; i < 5; i++) s = spend(s, 10)!;
    expect(s.v).toBe(0);
    expect(spend(s, 10)).toBeNull();
    // 2 時間たつと 1 回使える。回復の起点は 2 時間ぶんだけ進む(端数は残る)
    const t = REGEN_MS + 5000;
    expect(spend(s, t)).toEqual({ v: 0, at: 10 + REGEN_MS });
    expect(current(spend(s, t)!, t).nextAt).toBe(10 + 2 * REGEN_MS);
  });
  it("満タンから使った時刻が、回復の起点になる", () => {
    const s = spend({ v: 5, at: 0 }, 50_000_000)!;
    expect(s.at).toBe(50_000_000);
  });
  it("全回復と日付とパス", () => {
    expect(refill(5)).toEqual({ v: STAMINA_MAX, at: 5 });
    expect(dayKeyJst(Date.UTC(2026, 10, 3, 14, 59))).toBe("2026-11-03");
    expect(dayKeyJst(Date.UTC(2026, 10, 3, 15, 0))).toBe("2026-11-04");
    expect(hasPass({ until: 100 }, 99)).toBe(true);
    expect(hasPass({ until: 100 }, 100)).toBe(false);
    expect(hasPass(undefined, 1)).toBe(false);
  });
});
