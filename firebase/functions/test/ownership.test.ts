import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import { BOSS_BY_LOOK, BOSS_KEYS, NOT_IN_LIFETIME, PAID_ONLY_BOSSES, SEASONAL_BOSSES, bossKeysOf, fetchPurchasedIds, isPaidShip, missingBosses, missingMookPacks, ownsShipByPurchase, PAID_SHIPS, mookPacksOf, MOOK_LOOK_MAX, MOOK_PACKS, ownsBossByPurchase, ownsMookPackByPurchase, providerMarks } from "../src/ownership.js";
import { simulate, type SimStage } from "../src/fullsim.js";
import { validatePublish } from "../src/validate.js";

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

describe("期間限定のボス(サンタ娘)", () => {
  const p = "com.koshin.danmakumaker.";
  const lifetime = new Set([p + "lifetime"]);
  const bought = new Set([p + "boss.santa"]);
  const nothing = new Set([p + "boss.kitsune", p + "patternpack"]);
  const santaStage = { bossLook: 14 };
  const santaInWave = { bossLook: 3, waves: [{ bossLook: 6 }, { bossLook: 14 }] };

  it("番号 14 が santa。永久買い切りパックに含み、無料チケットではもらえない", () => {
    expect(BOSS_BY_LOOK[14]).toBe("santa");
    expect(BOSS_KEYS).toContain("santa");
    expect(SEASONAL_BOSSES).toEqual(["santa"]);
    expect(NOT_IN_LIFETIME).not.toContain("santa");
    expect(PAID_ONLY_BOSSES).toContain("santa");
    expect(PAID_ONLY_BOSSES).toContain("puni");
    // 期間限定のボスは、どれも永久買い切りパックに含む(約束: これから追加される課金コンテンツも全部)
    for (const k of SEASONAL_BOSSES) expect(NOT_IN_LIFETIME).not.toContain(k);
  });

  it("投稿: 永久買い切りパックの人は通る(サーバーは販売期間を見ないので、期間のあとに買った人も同じ)", () => {
    expect(ownsBossByPurchase("santa", lifetime)).toBe(true);
    expect(missingBosses(santaStage, [], lifetime)).toEqual([]);
    expect(missingBosses(santaInWave, [], lifetime)).toEqual([]);
  });

  it("投稿: 期間中に単品で買った人は通る(期間が終わっても、買った記録は残る)", () => {
    expect(ownsBossByPurchase("santa", bought)).toBe(true);
    expect(missingBosses(santaStage, [], bought)).toEqual([]);
    // 連戦で他のボスも使っていれば、そちらは別に要る
    expect(missingBosses(santaInWave, [], bought)).toEqual(["kitsune"]);
    expect(missingBosses(santaInWave, ["kitsune"], bought)).toEqual([]);
  });

  it("投稿: 持っていない人は断られる(他の商品を買っていても)", () => {
    expect(ownsBossByPurchase("santa", nothing)).toBe(false);
    expect(ownsBossByPurchase("santa", new Set())).toBe(false);
    expect(missingBosses(santaStage, [], nothing)).toEqual(["santa"]);
    expect(missingBosses(santaStage, [], new Set())).toEqual(["santa"]);
    expect(missingBosses(santaInWave, ["kitsune"], nothing)).toEqual(["santa"]);
    // 無料チケットのボスを持っていても、サンタ娘の代わりにはならない
    expect(missingBosses(santaStage, ["fallen_angel", "dragon"], new Set())).toEqual(["santa"]);
  });

  it("プレイ・ランキング: 持っているかに関わらず、誰の記録でも同じに計算できる(遊ぶのは誰でも)", () => {
    const input = { name: "xmas", authorName: "Koshin", clearReplay: "AQIDBAUGBwg=", mode: "boss", durationSec: 60, bossHp: 300, bossMove: 0, bossLook: 14,
      emitters: [{ t: "ring", x: 0.5, y: 0.2, s: 0, e: 20, i: 1, c: 16, v: 2, r: 6, k: 0, ph: 0 }] };
    const v = validatePublish(input);
    expect(v.ok).toBe(true);
    if (!v.ok) return;
    expect(v.stage.bossLook).toBe(14);
    expect(v.stage.needs).toBe(8);   // 1.4.2 までのアプリには「アップデートが必要」と案内する
    // 記録の検証(プレイ・ランキング)は、ステージと操作だけで決まる。所持は引数にない
    const a = simulate(v.stage as unknown as SimStage, new Int8Array(0), 0, "standard");
    const b = simulate(v.stage as unknown as SimStage, new Int8Array(0), 0, "standard");
    expect(a.outcome).toBe(b.outcome);
    expect(a).toEqual(b);
  });

  it("Remote Config のひな形: 売り場に出すかの値は、既定がオフで、日時の条件のときだけオン", () => {
    const t = JSON.parse(readFileSync(new URL("../../remoteconfig.template.json", import.meta.url), "utf8")) as {
      conditions: { name: string; expression: string }[];
      parameters: Record<string, { defaultValue: { value: string }; conditionalValues?: Record<string, { value: string }>; valueType: string }>;
    };
    const p = t.parameters["xmas_boss_on_sale"]!;
    expect(p.valueType).toBe("BOOLEAN");
    expect(p.defaultValue.value).toBe("false");   // 取れなかった人・期間外は、売り場に出さない
    const on = Object.entries(p.conditionalValues ?? {}).filter(([, v]) => v.value === "true").map(([k]) => k);
    expect(on).toHaveLength(1);
    const cond = t.conditions.find((c) => c.name === on[0])!;
    // 端末の時計ではなく、サーバーの日時の条件(始まりと終わりの両方、日本時間)
    expect(cond.expression).toMatch(/^dateTime > dateTime\('\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d', 'Asia\/Tokyo'\) && dateTime <= dateTime\('\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d', 'Asia\/Tokyo'\)$/);
  });

  it("範囲外の番号(15)は、まだ受け付けない", () => {
    const r = validatePublish({ name: "x", authorName: "Koshin", clearReplay: "AQIDBAUGBwg=", mode: "boss", durationSec: 60, bossHp: 300, bossMove: 0, bossLook: 15,
      emitters: [{ t: "ring", x: 0.5, y: 0.2, s: 0, e: 20, i: 1, c: 16, v: 2, r: 6, k: 0, ph: 0 }] });
    expect(r).toEqual({ ok: false, error: "look" });
  });
});

describe("雑魚の見た目のセット(クリスマス)と、期間の全部入り", () => {
  const p = "com.koshin.danmakumaker.";
  const lifetime = new Set([p + "lifetime"]);
  const set = new Set([p + "mooks.xmas"]);
  const pack = new Set([p + "pack.xmas"]);
  const other = new Set([p + "boss.santa", p + "patternpack"]);

  it("番号 5〜8 が xmas。最初から使える 0〜4 は、どのセットでもない", () => {
    expect(MOOK_PACKS.xmas).toEqual({ from: 5, to: 8, season: "xmas" });
    expect(MOOK_LOOK_MAX).toBe(8);
    for (let l = 0; l <= 4; l++) expect(mookPacksOf({ mooks: 1, mookLook: l })).toEqual([]);
    for (let l = 5; l <= 8; l++) expect(mookPacksOf({ mooks: 1, mookLook: l })).toEqual(["xmas"]);
  });

  it("雑魚を出さない場面の指定は数えない。連戦は場面ごとに見る", () => {
    expect(mookPacksOf({ mookLook: 6 })).toEqual([]);
    expect(mookPacksOf({ waves: [{ mooks: 0, mookLook: 2 }, { mooks: 2, mookLook: 8 }, { mooks: 1, mookLook: 5 }] })).toEqual(["xmas"]);
    expect(mookPacksOf({ waves: [{ mooks: 0, mookLook: 2 }, { mookLook: 8 }] })).toEqual([]);
  });

  it("セットを買った人・全部入りの人・永久買い切りパックの人は公開できる(販売期間は見ない)", () => {
    for (const own of [set, pack, lifetime]) {
      expect(ownsMookPackByPurchase("xmas", own)).toBe(true);
      expect(missingMookPacks({ mooks: 1, mookLook: 7 }, own)).toEqual([]);
    }
  });

  it("持っていない人は公開できない(ボスだけ買っても、雑魚の見た目は付かない)", () => {
    for (const own of [other, new Set<string>()]) {
      expect(ownsMookPackByPurchase("xmas", own)).toBe(false);
      expect(missingMookPacks({ mooks: 1, mookLook: 7 }, own)).toEqual(["xmas"]);
      expect(missingMookPacks({ mooks: 1, mookLook: 3 }, own)).toEqual([]);
    }
  });

  it("全部入りは、その期間のボスも付く。期間限定でないボスは付かない", () => {
    expect(ownsBossByPurchase("santa", pack)).toBe(true);
    expect(missingBosses({ bossLook: 14, mooks: 1, mookLook: 5 }, [], pack)).toEqual([]);
    expect(ownsBossByPurchase("kitsune", pack)).toBe(false);
    expect(ownsBossByPurchase("puni", pack)).toBe(false);
    expect(ownsBossByPurchase("dragon", pack)).toBe(false);
  });
});

describe("買って手に入れる自機(クリスマス)", () => {
  const p = "com.koshin.danmakumaker.";
  it("アプリの PaidShip と同じ3機", () => {
    expect(Object.keys(PAID_SHIPS)).toEqual(["sleigh_xmas", "reindeer_xmas", "snowflake_xmas"]);
    for (const id of Object.keys(PAID_SHIPS)) expect(isPaidShip(id)).toBe(true);
    for (const id of ["ace_gold", "original_steel", "seraph_special", "x_foo", "toString", "constructor", ""]) expect(isPaidShip(id)).toBe(false);
  });
  it("単品・全部入り・永久買い切りパックで持っている。1機ずつ", () => {
    expect(ownsShipByPurchase("sleigh_xmas", new Set([p + "ship.sleigh_xmas"]))).toBe(true);
    expect(ownsShipByPurchase("reindeer_xmas", new Set([p + "ship.sleigh_xmas"]))).toBe(false);
    for (const id of Object.keys(PAID_SHIPS)) {
      expect(ownsShipByPurchase(id, new Set([p + "pack.xmas"]))).toBe(true);
      expect(ownsShipByPurchase(id, new Set([p + "lifetime"]))).toBe(true);
      expect(ownsShipByPurchase(id, new Set([p + "boss.santa", p + "mooks.xmas"]))).toBe(false);
      expect(ownsShipByPurchase(id, new Set())).toBe(false);
    }
  });
  it("招待のごほうびの自機は、永久買い切りパックでも買ったことにならない", () => {
    expect(ownsShipByPurchase("ace_gold", new Set([p + "lifetime", p + "pack.xmas"]))).toBe(false);
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
