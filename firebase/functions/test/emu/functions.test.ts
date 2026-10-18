// firebase emulators:exec で Auth / Firestore / Storage / Functions を立てて、実際の関数を呼ぶ
import { initializeApp } from "firebase/app";
import { connectAuthEmulator, createUserWithEmailAndPassword, getAuth, signInAnonymously, signOut } from "firebase/auth";
import { connectFunctionsEmulator, getFunctions, httpsCallable } from "firebase/functions";
import { getFirestore as adminDb } from "firebase-admin/firestore";
import { initializeApp as adminInit } from "firebase-admin/app";
import { beforeAll, describe, expect, it } from "vitest";

process.env.FIRESTORE_EMULATOR_HOST ??= "127.0.0.1:8080";
const app = initializeApp({ apiKey: "demo", projectId: "demo-danmaku" });
const auth = getAuth(app);
connectAuthEmulator(auth, "http://127.0.0.1:9099", { disableWarnings: true });
const fns = getFunctions(app, "asia-northeast1");
connectFunctionsEmulator(fns, "127.0.0.1", 5001);
const admin = adminInit({ projectId: "demo-danmaku" }, "test");
const db = adminDb(admin);

const call = (name: string, data: unknown) => httpsCallable(fns, name)(data).then((r) => r.data as Record<string, unknown>);
const callErr = async (name: string, data: unknown) => { try { await call(name, data); return null; } catch (e) { return (e as { message: string }).message; } };
let n = 0;
const signUp = async () => { await signOut(auth); await createUserWithEmailAndPassword(auth, `u${Date.now()}${n++}@test.dev`, "password123"); };
const emitter = { t: "ring", x: 0.5, y: 0.2, s: 0, e: 20, i: 1, c: 16, v: 2, r: 6, k: 0, ph: 0 };
const stage = { name: "テスト渦", authorName: "Koshin", mode: "survive", durationSec: 20, emitters: [emitter], clearReplay: "AQIDBAUGBwg=", termsAccepted: true, lang: "ja" };
const origin = "http://127.0.0.1:5001/demo-danmaku/asia-northeast1";

async function publish(over: object = {}) {
  await signUp();
  return call("publishStage", { ...stage, ...over });
}

describe("publishStage", () => {
  it("匿名ユーザーは投稿できない", async () => {
    await signOut(auth); await signInAnonymously(auth);
    expect(await callErr("publishStage", stage)).toMatch(/sign-in-required/);
  });
  it("規約に同意していないと投稿できない", async () => {
    await signUp();
    expect(await callErr("publishStage", { ...stage, termsAccepted: false })).toMatch(/terms-not-accepted/);
  });
  it("NGワードは拒否", async () => {
    await signUp();
    expect(await callErr("publishStage", { ...stage, name: "死ね" })).toMatch(/name-ng-word/);
  });
  it("成功すると5文字のIDが返り、ステージとリプレイとOGP画像が保存される", async () => {
    const { id } = (await publish()) as { id: string };
    expect(id).toMatch(/^[2-9A-HJKMNP-Z]{5}$/);
    const s = (await db.doc(`stages/${id}`).get()).data()!;
    expect(s).toMatchObject({ name: "テスト渦", status: "published", plays: 0, clears: 0, likes: 0, reports: 0, ogImagePath: `og/${id}.png` });
    expect(s.clearReplay).toBeUndefined();
    expect((await db.doc(`stageReplays/${id}`).get()).get("clearReplay")).toBe(stage.clearReplay);
  });
  it("連続投稿は拒否される", async () => {
    await signUp();
    await call("publishStage", stage);
    expect(await callErr("publishStage", stage)).toMatch(/too-fast/);
  });
});

describe("submitResults / toggleLike / reportStage", () => {
  it("挑戦・クリア数をまとめて加算し、高難度用の値を更新する", async () => {
    const { id } = (await publish()) as { id: string };
    await signOut(auth); await signInAnonymously(auth);
    await call("submitResults", { results: [{ stageId: id, plays: 10, clears: 3 }] });
    const s = (await db.doc(`stages/${id}`).get()).data()!;
    expect(s).toMatchObject({ plays: 10, clears: 3, hardRate: 0.3 });
    expect(s.trending).toBeGreaterThan(0);
  });
  it("不正な件数は拒否", async () => {
    await signInAnonymously(auth);
    expect(await callErr("submitResults", { results: [{ stageId: "AAAAA", plays: 1, clears: 2 }] })).toMatch(/result-range/);
  });
  it("いいねの付け外し", async () => {
    const { id } = (await publish()) as { id: string };
    await signUp();
    expect(await call("toggleLike", { stageId: id })).toEqual({ liked: true, likes: 1 });
    expect(await call("toggleLike", { stageId: id })).toEqual({ liked: false, likes: 0 });
  });
  it("通報は1人1回で、5件たまると自動で非公開になりアラートが残る", async () => {
    const { id } = (await publish()) as { id: string };
    for (let i = 0; i < 5; i++) { await signUp(); await call("reportStage", { stageId: id, reason: "impossible" }); }
    expect((await db.doc(`stages/${id}`).get()).get("status")).toBe("hidden");
    const alerts = await db.collection("admin_alerts").where("stageId", "==", id).get();
    expect(alerts.size).toBe(1);
    expect(await call("reportStage", { stageId: id, reason: "other" })).toMatchObject({ hidden: true });
  });
  it("同じ人の二重通報は数えない", async () => {
    const { id } = (await publish()) as { id: string };
    await signUp();
    await call("reportStage", { stageId: id, reason: "other" });
    expect(await call("reportStage", { stageId: id, reason: "other" })).toMatchObject({ already: true });
    expect((await db.doc(`stages/${id}`).get()).get("reports")).toBe(1);
  });
});

describe("deleteAccount", () => {
  it("投稿・リプレイ・OGP画像・ユーザー情報・いいねを消し、認証ユーザーも消える", async () => {
    const { id } = (await publish()) as { id: string };
    const myUid = auth.currentUser!.uid;
    const other = (await publish({ name: "他人のステージ" })) as { id: string };
    await signUp();
    const liker = auth.currentUser!.uid;
    await call("toggleLike", { stageId: other.id });
    await call("toggleLike", { stageId: id });
    expect((await db.doc(`stages/${other.id}`).get()).get("likes")).toBe(1);
    // 投稿者に戻って削除…ではなく、いいねした人が自分を削除する
    expect(await call("deleteAccount", {})).toMatchObject({ ok: true, stages: 0 });
    expect((await db.doc(`stages/${other.id}`).get()).get("likes")).toBe(0);
    expect((await db.doc(`stages/${id}`).get()).get("likes")).toBe(0);
    expect((await db.collection(`users/${liker}/likes`).get()).size).toBe(0);
    expect(myUid).not.toBe(liker);
  });
  it("投稿者が削除すると、ステージも関連データも消える", async () => {
    await signUp();
    const uid = auth.currentUser!.uid;
    const { id } = (await call("publishStage", stage)) as { id: string };
    expect((await db.doc(`stages/${id}`).get()).exists).toBe(true);
    expect(await call("deleteAccount", {})).toMatchObject({ ok: true, stages: 1 });
    expect((await db.doc(`stages/${id}`).get()).exists).toBe(false);
    expect((await db.doc(`stageReplays/${id}`).get()).exists).toBe(false);
    expect((await db.doc(`users/${uid}`).get()).exists).toBe(false);
    const res = await fetch(`${origin}/sharePage/s/${id}`);
    expect(res.status).toBe(404);
  });
});

describe("sharePage / ogImage（HTTP）", () => {
  let id = "";
  beforeAll(async () => { id = ((await publish()) as { id: string }).id; });
  it("OGP タグ入りの HTML を返す", async () => {
    const res = await fetch(`${origin}/sharePage/s/${id}`, { headers: { "Accept-Language": "ja" } });
    expect(res.status).toBe(200);
    const html = await res.text();
    expect(html).toContain('property="og:title"');
    expect(html).toContain("テスト渦");
  });
  it("存在しないIDは 404", async () => {
    const res = await fetch(`${origin}/sharePage/s/ZZZZZ`);
    expect(res.status).toBe(404);
  });
  it("OGP 画像は 200 で 1200×630 の PNG", async () => {
    const res = await fetch(`${origin}/ogImage/og/${id}.png`);
    expect(res.status).toBe(200);
    const buf = Buffer.from(await res.arrayBuffer());
    expect(buf.readUInt32BE(16)).toBe(1200);
    expect(buf.readUInt32BE(20)).toBe(630);
  });
});
