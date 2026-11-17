import { describe, expect, it } from "vitest";
import { bossKeysOf, fetchPurchasedIds, ownsBossByPurchase, providerMarks } from "../src/ownership.js";

describe("ボスを持っているか", () => {
  it("ステージで使っている専用の絵のボスを集める(図形のボスは数えない)", () => {
    expect(bossKeysOf({ bossLook: 3 })).toEqual([]);
    expect(bossKeysOf({ bossLook: 5 })).toEqual(["fallen_angel"]);
    expect(bossKeysOf({ waves: [{ bossLook: 6 }, { bossLook: 12 }, { bossLook: 6 }, {}] }).sort()).toEqual(["hire", "kitsune"]);
    // 竜王の曲(5・6)を選んだら、竜王を持っている必要がある
    expect(bossKeysOf({ bossLook: 3, bgm: 5 })).toEqual(["dragon"]);
    expect(bossKeysOf({ bossLook: 13, bgm: 6 })).toEqual(["dragon"]);
    expect(bossKeysOf({ bossLook: 5, bgm: 4 })).toEqual(["fallen_angel"]);
  });
  it("単品か永久パックで持っている。招待限定のボスは永久パックに含まれない", () => {
    const p = "com.koshin.danmakumaker.";
    expect(ownsBossByPurchase("kitsune", new Set([p + "boss.kitsune"]))).toBe(true);
    expect(ownsBossByPurchase("kitsune", new Set([p + "boss.witch"]))).toBe(false);
    expect(ownsBossByPurchase("kitsune", new Set([p + "lifetime"]))).toBe(true);
    expect(ownsBossByPurchase("puni", new Set([p + "lifetime"]))).toBe(false);
  });
  it("RevenueCat の答えから、買った商品を読む。聞けないときは null(投稿は止めない)", async () => {
    const ok = async () => ({ ok: true, status: 200, json: async () => ({ subscriber: { non_subscriptions: { "com.koshin.danmakumaker.boss.mech": [{ id: "x" }], "empty": [] }, subscriptions: {} } }) });
    expect([...(await fetchPurchasedIds("u1", "sk_test", ok))!]).toEqual(["com.koshin.danmakumaker.boss.mech"]);
    expect(await fetchPurchasedIds("u1", undefined, ok)).toBeNull();
    expect(await fetchPurchasedIds("u1", "sk_test", async () => ({ ok: false, status: 500, json: async () => ({}) }))).toBeNull();
    expect(await fetchPurchasedIds("u1", "sk_test", async () => { throw new Error("net"); })).toBeNull();
  });
  it("問い合わせ先は uid を URL に入れて送る", async () => {
    let url = "";
    await fetchPurchasedIds("a/b", "sk", async (u) => { url = u; return { ok: true, status: 200, json: async () => ({ subscriber: {} }) }; });
    expect(url).toBe("https://api.revenuecat.com/v1/subscribers/a%2Fb");
  });
});

describe("利用停止の目印", () => {
  it("外部アカウントの ID はハッシュにし、匿名は使わない", () => {
    const m = providerMarks({ "apple.com": ["001.abc"], anonymous: ["x"] });
    expect(m).toHaveLength(1);
    expect(m[0]).toMatch(/^[0-9a-f]{64}$/);
    expect(m[0]).not.toContain("abc");
    expect(providerMarks({ "apple.com": ["001.abc"] })).toEqual(m);
    expect(providerMarks({ "apple.com": ["001.abd"] })).not.toEqual(m);
    expect(providerMarks(undefined)).toEqual([]);
    expect(providerMarks({ email: ["someone@example.com"] })).toEqual([]);
  });
});
