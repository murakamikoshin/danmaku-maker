// スワイプ弾幕: スタミナ → プレイ開始 → 記録の提出 → ランキング → 課金の通知 を、エミュレーターで通しで確かめる
import { initializeApp } from "firebase/app";
import { connectAuthEmulator, createUserWithEmailAndPassword, getAuth, signInAnonymously, signOut } from "firebase/auth";
import { connectFunctionsEmulator, getFunctions, httpsCallable } from "firebase/functions";
import { getFirestore as adminDb } from "firebase-admin/firestore";
import { initializeApp as adminInit } from "firebase-admin/app";
import { describe, expect, it } from "vitest";
import { botCanClear } from "../../src/swipebot.js";
import type { SimStage } from "../../src/fullsim.js";

process.env.FIRESTORE_EMULATOR_HOST ??= "127.0.0.1:8080";
const app = initializeApp({ apiKey: "demo", projectId: "demo-danmaku" }, "swipe");
const auth = getAuth(app);
connectAuthEmulator(auth, "http://127.0.0.1:9099", { disableWarnings: true });
const fns = getFunctions(app, "asia-northeast1");
connectFunctionsEmulator(fns, "127.0.0.1", 5001);
const db = adminDb(adminInit({ projectId: "demo-danmaku" }, "swipe-admin"));

// eslint-disable-next-line @typescript-eslint/no-explicit-any
const call = (name: string, data: unknown = {}) => httpsCallable(fns, name)(data).then((r) => r.data as Record<string, never> & Record<string, unknown> & { [k: string]: any });
const callErr = async (name: string, data: unknown = {}) => { try { await call(name, data); return null; } catch (e) { return (e as { message: string }).message; } };
let n = 0;
const signUp = async () => { await signOut(auth); const c = await createUserWithEmailAndPassword(auth, `s${Date.now()}${n++}@test.dev`, "password123"); return c.user.uid; };

/** 操作記録(dx, dy の並び)を、アプリと同じ形(先頭 0 + [回数, dx, dy] の繰り返し)にする */
function encode(moves: Int8Array, steps: number): string {
  const out: number[] = [0];
  for (let i = 0; i < steps;) {
    let j = i + 1;
    while (j < steps && j - i < 255 && moves[j * 2] === moves[i * 2] && moves[j * 2 + 1] === moves[i * 2 + 1]) j++;
    out.push(j - i, moves[i * 2]! & 0xff, moves[i * 2 + 1]! & 0xff);
    i = j;
  }
  return Buffer.from(out).toString("base64");
}

const em = { t: "ring", x: 0.5, y: 0.15, s: 0, e: 30, i: 0.3, c: 12, v: 2, r: 10, k: 1, ph: 0, a: 0, p: 0 };
const stage: SimStage & Record<string, unknown> = { name: "スワイプ用", authorName: "Au", mode: "survive", durationSec: 30, emitters: [em, { ...em, t: "aim", i: 0.4, c: 5, r: 40 }] as never, status: "published", authorUid: "author1" };
const AT = 6;

async function seedPool(ids: string[]) {
  for (const id of ids) await db.doc(`stages/${id}`).set({ ...stage, clip: { ok: true, at: AT, est: 0.85, checkedAt: 1 }, plays: 0, clears: 0 });
  const version = `t${Date.now()}`;
  await db.doc(`swipePools/${version}/chunks/0000`).set({ entries: ids.map((id) => ({ id, d: 850, author: "author1" })) });
  await db.doc(`swipePools/${version}`).set({ count: ids.length });
  await db.doc("swipePools/meta").set({ current: version, count: ids.length });
}

describe("スワイプ弾幕のサーバー", () => {
  it("候補がまだなければ始められない", async () => {
    await db.doc("swipePools/meta").delete();
    await signUp();
    expect(await callErr("swipeUseStamina")).toMatch(/pool-empty/);
  });

  it("始める → 記録を出す → 点数が計算し直されてランキングに載る", async () => {
    await seedPool(["SWPA1", "SWPA2", "SWPA3"]);
    const uid = await signUp();
    const start = await call("swipeUseStamina", {});
    expect(start.value).toBe(4);
    expect(start.unlimited).toBe(false);
    const bot = botCanClear(stage, AT);
    expect(bot.ok).toBe(true);
    const moves = encode(bot.moves, bot.steps);
    const res = await call("swipeSubmitRun", { runId: start.runId, clips: [{ go: "", moves, skipped: false }], handle: { a: 1, n: 2 } });
    expect(res.endedByHit).toBe(false);
    expect(res.ranked).toBe(true);
    expect(BigInt(res.score)).toBeGreaterThanOrEqual(150000n);
    const rank = await call("swipeRanking");
    expect(rank.my.rank).toBeGreaterThanOrEqual(1);
    expect(rank.my.score).toBe(res.score);
    expect((await db.doc(`swipeScores/${uid}`).get()).get("score")).toBe(res.score);
    // 同じプレイは 2 回出せない
    expect(await callErr("swipeSubmitRun", { runId: start.runId, clips: [], handle: { a: 1, n: 2 } })).toMatch(/run-closed/);
  }, 120_000);

  it("他人のプレイや、でたらめな記録は受け付けない", async () => {
    await seedPool(["SWPB1", "SWPB2"]);
    await signUp();
    const start = await call("swipeUseStamina", {});
    await signUp();
    expect(await callErr("swipeSubmitRun", { runId: start.runId, clips: [], handle: { a: 0, n: 0 } })).toMatch(/run|not-found/);
    await signUp();
    const mine = await call("swipeUseStamina", {});
    expect(await callErr("swipeSubmitRun", { runId: mine.runId, clips: [{ go: "AAAA", moves: "!!!", skipped: false }], handle: { a: 0, n: 0 } })).toMatch(/clip|replay/);
  });

  it("スタミナは 5 回で尽き、ドリンクと広告で戻る(広告は 1 日 1 回)", async () => {
    await seedPool(["SWPC1", "SWPC2"]);
    const uid = await signUp();
    for (let i = 0; i < 5; i++) await call("swipeUseStamina", {});
    expect(await callErr("swipeUseStamina", {})).toMatch(/no-stamina/);
    expect(await callErr("swipeUseDrink")).toMatch(/no-drink/);
    const ad = await call("swipeRefillByAd");
    expect(ad.value).toBe(5);
    expect(await callErr("swipeRefillByAd")).toMatch(/ad-refill-used/);
    for (let i = 0; i < 5; i++) await call("swipeUseStamina", {});
    await db.doc(`users/${uid}`).update({ drinks: 2 });
    const d = await call("swipeUseDrink");
    expect(d.value).toBe(5);
    expect(d.drinks).toBe(1);
    const d2 = await call("swipeUseDrink");   // 満タンでも使えて、5 を超えて持てる(+5)
    expect(d2.value).toBe(10);
    expect(d2.drinks).toBe(0);
  }, 60_000);

  it("匿名でも遊べるが、ランキングには載らない", async () => {
    await seedPool(["SWPD1", "SWPD2"]);
    await signOut(auth); await signInAnonymously(auth);
    const start = await call("swipeUseStamina", {});
    const bot = botCanClear(stage, AT);
    const res = await call("swipeSubmitRun", { runId: start.runId, clips: [{ go: "", moves: encode(bot.moves, bot.steps), skipped: false }] });
    expect(res.ranked).toBe(false);
  }, 120_000);

  it("RevenueCat の通知: 合言葉が違えば断り、パスとドリンクが反映され、同じ通知は 2 回効かない", async () => {
    const uid = await signUp();
    const url = "http://127.0.0.1:5001/demo-danmaku/asia-northeast1/revenuecatWebhook";
    const post = (secret: string, event: object) => fetch(url, { method: "POST", headers: { "content-type": "application/json", authorization: `Bearer ${secret}` }, body: JSON.stringify({ event }) });
    expect((await post("wrong", { id: "e0" })).status).toBe(401);
    const until = Date.now() + 30 * 86400_000;
    expect((await post("test-secret", { id: `p-${uid}`, type: "INITIAL_PURCHASE", app_user_id: uid, product_id: "com.koshin.danmakumaker.pass.stamina.monthly", expiration_at_ms: until })).status).toBe(200);
    const drink = { id: `d-${uid}`, type: "NON_RENEWING_PURCHASE", app_user_id: uid, product_id: "com.koshin.danmakumaker.stamina.drink" };
    await post("test-secret", drink); await post("test-secret", drink);
    const u = (await db.doc(`users/${uid}`).get()).data()!;
    expect(u.pass.until).toBe(until);
    expect(u.drinks).toBe(1);
    // パスがあれば、スワイプを何回でも始められ、スタミナは減らない
    await seedPool(["SWPE1", "SWPE2"]);
    for (let i = 0; i < 7; i++) expect((await call("swipeUseStamina", {})).unlimited).toBe(true);
  }, 60_000);
});
