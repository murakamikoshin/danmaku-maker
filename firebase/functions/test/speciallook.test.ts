import { describe, expect, it } from "vitest";
import { grazeDistanceSquared, hitDistanceSquared, lookHitDistance } from "../src/fullsim.js";

// アプリの SpecialBulletLookTests と同じ値(ボス専用の弾の当たる半径)
const base = { x: 0, y: 0, vx: 0, vy: 0, color: 0, turn: 0, homeLeft: 0, accel: 0, maxSpeed: 0, bounces: 0, script: 0, age: 0 };
const code = (kind: number, aw = false) => 16 + kind * 2 + (aw ? 1 : 0);

describe("ボス専用の弾の当たる半径", () => {
  it("標準・くの字・丸は 5.5px のまま", () => {
    for (const look of [undefined, 0, 1, 2]) expect(hitDistanceSquared({ ...base, look })).toBe(30.25);
  });
  it("種類ごとの半径 + 自機 2.5px", () => {
    expect(hitDistanceSquared({ ...base, look: code(0) })).toBeCloseTo(5.5 ** 2, 9);   // 狐火
    expect(hitDistanceSquared({ ...base, look: code(2) })).toBeCloseTo(25, 9);          // 夜光虫
    expect(hitDistanceSquared({ ...base, look: code(7, true) })).toBeCloseTo(4.5 ** 2, 9); // 砲弾
    expect(hitDistanceSquared({ ...base, look: code(4) })).toBeCloseTo(8.5 ** 2, 9);    // 墨
    expect(grazeDistanceSquared({ ...base, look: code(4) })).toBeCloseTo(21 ** 2, 9);
    expect(grazeDistanceSquared({ ...base, look: code(0) })).toBeCloseTo(18 ** 2, 9);
  });
  it("範囲外の番号は標準扱い", () => {
    expect(lookHitDistance(16 + 44)).toBeUndefined();
    expect(hitDistanceSquared({ ...base, radius: 8, look: code(3) })).toBeCloseTo(13.5 ** 2, 9);
  });
});
