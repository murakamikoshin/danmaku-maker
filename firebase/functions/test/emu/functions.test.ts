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
// 1発だけ横へ飛ぶ無害な弾。動かなくてもクリアできるので、サーバーのリプレイ検証を通る
const emitter = { t: "ring", x: 0.5, y: 0.2, s: 0, e: 20, i: 1, c: 1, v: 1, r: 0, k: 0, ph: 0 };
/** 操作記録を作る: [回数, dx, dy] の並びを、先頭1バイト0(そのまま) + 繰り返しで Base64 にする */
const replayOf = (runs: [number, number, number][]) =>
  Buffer.from([0, ...runs.flatMap(([c, dx, dy]) => [c, dx & 0xff, dy & 0xff])]).toString("base64");
const STILL = replayOf([[1, 0, 0]]);
const stage = { name: "テスト渦", authorName: "Koshin", mode: "survive", durationSec: 20, emitters: [emitter], clearReplay: STILL, termsAccepted: true, lang: "ja" };
const bossStage = { ...stage, name: "ボス勝負", mode: "boss", durationSec: 30, bossHp: 100, bossMove: 0 };
const damageStage = { ...stage, name: "ダメージ勝負", mode: "damage", durationSec: 30, bossMove: 0 };
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
  it("クリアできない記録では投稿できない(サーバーが再生して確かめる)", async () => {
    await signUp();
    // 動かない記録でも、強い弾に当たるステージなら失敗する
    const hard = { ...stage, emitters: [{ ...emitter, t: "aim", c: 5, v: 3, i: 0.3, r: 10 }] };
    expect(await callErr("publishStage", hard)).toMatch(/replay-not-cleared/);
  });
  it("壊れた操作記録は拒否される", async () => {
    await signUp();
    expect(await callErr("publishStage", { ...stage, clearReplay: "AQIDBAUGBwg=" })).toMatch(/replay/);
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


describe("submitScore(ランキング)", () => {
  const handle = { a: 3, n: 5 };
  const publishAs = async (st: object) => (await publish(st)) as { id: string };

  it("ボス戦: 再生して確かめた記録(クリアまでのステップ数)が載り、1位になる", async () => {
    const { id } = await publishAs(bossStage);
    await signOut(auth); await signInAnonymously(auth);
    const r = await call("submitScore", { stageId: id, replay: STILL, shot: "standard", handle });
    expect(r).toMatchObject({ accepted: true, improved: true, rank: 1 });
    expect(r.value as number).toBeGreaterThan(300);
    const uid = auth.currentUser!.uid;
    const doc = (await db.doc(`stages/${id}/scores/${uid}`).get()).data()!;
    expect(doc).toMatchObject({ uid, a: 3, n: 5, value: r.value, mode: "boss" });
    expect(doc.num).toBeGreaterThanOrEqual(0);
    expect((await db.doc(`scoreReplays/${id}_${uid}`).get()).get("replay")).toBe(STILL);
  });

  it("ボス戦: 速い記録が上位になり、遅い記録は更新されない", async () => {
    const { id } = await publishAs(bossStage);
    const slow = replayOf([[255, -8, 0], [87, 8, 0]]);
    await signOut(auth); await signInAnonymously(auth);
    const a = await call("submitScore", { stageId: id, replay: slow, shot: "standard", handle });
    expect(a).toMatchObject({ accepted: true, rank: 1 });
    await new Promise((r) => setTimeout(r, 3200));
    const b = await call("submitScore", { stageId: id, replay: STILL, shot: "standard", handle });
    expect(b).toMatchObject({ accepted: true, improved: true, rank: 1 });
    expect(b.value as number).toBeLessThan(a.value as number);
    await new Promise((r) => setTimeout(r, 3200));
    const again = await call("submitScore", { stageId: id, replay: slow, shot: "standard", handle });   // 自己ベストより遅い
    expect(again).toMatchObject({ accepted: true, improved: false, value: b.value, rank: 1 });
    // 別の人が遅い記録を出すと2位
    await signOut(auth); await signInAnonymously(auth);
    expect(await call("submitScore", { stageId: id, replay: slow, shot: "standard", handle })).toMatchObject({ accepted: true, rank: 2 });
  });

  it("ダメージ勝負: 与えたダメージが載る(多いほど上)", async () => {
    const { id } = await publishAs(damageStage);
    await signOut(auth); await signInAnonymously(auth);
    const r = await call("submitScore", { stageId: id, replay: STILL, shot: "standard", handle });
    expect(r).toMatchObject({ accepted: true, improved: true, rank: 1 });
    expect(r.value as number).toBeGreaterThan(300);
    expect((await db.doc(`stages/${id}/scores/${auth.currentUser!.uid}`).get()).get("mode")).toBe("damage");
  });

  it("クリアできていない記録は載らない", async () => {
    const id = "HARD2";
    await db.doc(`stages/${id}`).set({
      name: bossStage.name, authorName: bossStage.authorName, mode: "boss", durationSec: 30, bossHp: 1000, bossMove: 0,
      emitters: bossStage.emitters, formatVersion: 1, status: "published", authorUid: "x",
    });
    await signOut(auth); await signInAnonymously(auth);
    expect(await call("submitScore", { stageId: id, replay: STILL, shot: "standard", handle })).toEqual({ accepted: false, reason: "not-cleared" });
    expect((await db.doc(`stages/${id}/scores/${auth.currentUser!.uid}`).get()).exists).toBe(false);
  });

  it("範囲外の名前、壊れた記録、生き残りステージは拒否される", async () => {
    const boss = await publishAs(bossStage);
    const survive = await publishAs(stage);
    await signOut(auth); await signInAnonymously(auth);
    expect(await callErr("submitScore", { stageId: boss.id, replay: STILL, shot: "standard", handle: { a: 99, n: 0 } })).toMatch(/handle/);
    expect(await callErr("submitScore", { stageId: boss.id, replay: "AQIDBAUGBwg=", shot: "standard", handle })).toMatch(/replay/);
    await new Promise((r) => setTimeout(r, 3200));
    expect(await callErr("submitScore", { stageId: survive.id, replay: STILL, shot: "standard", handle })).toMatch(/no-ranking/);
    expect(await callErr("submitScore", { stageId: "ZZZZZ", replay: STILL, shot: "standard", handle })).toMatch(/stage|too-fast/);
  });

  it("撃ち方はステージで決まる: 投稿した撃ち方が保存され、ランキングの検証もその撃ち方で行われる(アプリから届く値は見ない)", async () => {
    const heavy = await publishAs({ ...bossStage, shot: "heavy" });
    expect((await db.doc(`stages/${heavy.id}`).get()).get("shot")).toBe("heavy");
    const std = await publishAs(bossStage);
    expect((await db.doc(`stages/${std.id}`).get()).get("shot")).toBeUndefined();
    expect(await callErr("publishStage", { ...bossStage, shot: "laser" })).toMatch(/shot/);
    await signOut(auth); await signInAnonymously(auth);
    // 古いアプリは "standard" を送ってくる。ヘビーのステージでも、サーバーはステージの撃ち方で再生する
    const r = (await call("submitScore", { stageId: heavy.id, replay: STILL, shot: "standard", handle })) as { accepted?: boolean };
    expect(r.accepted).toBe(true);
  });

  it("続けて送ると、間隔をあけるよう求められる", async () => {
    const { id } = await publishAs(bossStage);
    await signOut(auth); await signInAnonymously(auth);
    await call("submitScore", { stageId: id, replay: STILL, shot: "standard", handle });
    expect(await callErr("submitScore", { stageId: id, replay: STILL, shot: "standard", handle })).toMatch(/too-fast/);
  });

  it("ログインしていない人は送れない", async () => {
    const { id } = await publishAs(bossStage);
    await signOut(auth);
    expect(await callErr("submitScore", { stageId: id, replay: STILL, shot: "standard", handle })).toMatch(/auth-required/);
  });

  it("アカウントを削除すると、ランキングの記録と操作記録も消える", async () => {
    const { id } = await publishAs(bossStage);
    await signOut(auth); await signUp();
    const uid = auth.currentUser!.uid;
    await call("submitScore", { stageId: id, replay: STILL, shot: "standard", handle });
    expect((await db.doc(`stages/${id}/scores/${uid}`).get()).exists).toBe(true);
    await call("deleteAccount", {});
    expect((await db.doc(`stages/${id}/scores/${uid}`).get()).exists).toBe(false);
    expect((await db.doc(`scoreReplays/${id}_${uid}`).get()).exists).toBe(false);
  });
});


describe("コメント", () => {
  const handle = { a: 2, n: 7 };

  it("Apple でサインインした人はコメントでき、名前・文章・時刻が保存される", async () => {
    const { id } = (await publish()) as { id: string };
    await signUp();
    const r = (await call("postComment", { stageId: id, text: "  むずいけど  楽しい！ ", handle })) as { id: string };
    const doc = (await db.doc(`stages/${id}/comments/${r.id}`).get()).data()!;
    expect(doc).toMatchObject({ uid: auth.currentUser!.uid, a: 2, n: 7, text: "むずいけど 楽しい！", status: "published", reports: 0 });
    expect(doc.createdAt).toBeTruthy();
  });

  it("匿名ユーザーは書けない", async () => {
    const { id } = (await publish()) as { id: string };
    await signOut(auth); await signInAnonymously(auth);
    expect(await callErr("postComment", { stageId: id, text: "こんにちは", handle })).toMatch(/sign-in-required/);
  });

  it("NGワード・URL・長すぎる文・空の文・不正な名前は拒否される", async () => {
    const { id } = (await publish()) as { id: string };
    await signUp();
    expect(await callErr("postComment", { stageId: id, text: "死ね", handle })).toMatch(/comment-ng-word/);
    expect(await callErr("postComment", { stageId: id, text: "ここ見て https://example.com", handle })).toMatch(/comment-link/);
    expect(await callErr("postComment", { stageId: id, text: "あ".repeat(81), handle })).toMatch(/comment-length/);
    expect(await callErr("postComment", { stageId: id, text: "   ", handle })).toMatch(/comment-length/);
    expect(await callErr("postComment", { stageId: id, text: "OK", handle: { a: 40, n: 1 } })).toMatch(/handle/);
    expect(await callErr("postComment", { stageId: "ZZZZZ", text: "OK", handle })).toMatch(/stage/);
  });

  it("連続投稿は拒否される", async () => {
    const { id } = (await publish()) as { id: string };
    await signUp();
    await call("postComment", { stageId: id, text: "1つ目", handle });
    expect(await callErr("postComment", { stageId: id, text: "2つ目", handle })).toMatch(/too-fast/);
  });

  it("コメントは、本人とステージの作者だけが消せる", async () => {
    const { id } = (await publish()) as { id: string };   // 作者 = ここでサインアップした人
    const authorUid = auth.currentUser!.uid;
    await signUp();
    const mine = (await call("postComment", { stageId: id, text: "私のコメント", handle })) as { id: string };
    await signUp();                                        // 他の人
    expect(await callErr("deleteComment", { stageId: id, commentId: mine.id })).toMatch(/not-allowed/);
    await signOut(auth); await signInAnonymously(auth);
    expect(await callErr("deleteComment", { stageId: id, commentId: mine.id })).toMatch(/not-allowed/);
    expect((await db.doc(`stages/${id}/comments/${mine.id}`).get()).exists).toBe(true);
    // 本人
    const u = auth.currentUser;
    expect(u).toBeTruthy();
    await signUp();
    const mine2 = (await call("postComment", { stageId: id, text: "あとで消す", handle })) as { id: string };
    await call("deleteComment", { stageId: id, commentId: mine2.id });
    expect((await db.doc(`stages/${id}/comments/${mine2.id}`).get()).exists).toBe(false);
    expect(authorUid).toBeTruthy();
  });

  it("通報は1人1回で、3人が通報すると自動で非表示になりアラートが残る", async () => {
    const { id } = (await publish()) as { id: string };
    await signUp();
    const c = (await call("postComment", { stageId: id, text: "よくないコメント", handle })) as { id: string };
    await signUp();
    expect(await call("reportComment", { stageId: id, commentId: c.id, reason: "other" })).toMatchObject({ already: false, hidden: false });
    expect(await call("reportComment", { stageId: id, commentId: c.id, reason: "other" })).toMatchObject({ already: true });
    await signUp(); await call("reportComment", { stageId: id, commentId: c.id, reason: "inappropriate_name" });
    await signUp();
    expect(await call("reportComment", { stageId: id, commentId: c.id, reason: "other" })).toMatchObject({ already: false, hidden: true });
    const doc = (await db.doc(`stages/${id}/comments/${c.id}`).get()).data()!;
    expect(doc).toMatchObject({ status: "hidden", reports: 3 });
    const alerts = await db.collection("admin_alerts").where("commentId", "==", c.id).get();
    expect(alerts.size).toBe(1);
    expect(await callErr("reportComment", { stageId: id, commentId: c.id, reason: "bad" })).toMatch(/reason/);
  });

  it("アカウントを削除すると、自分のコメントも消える", async () => {
    const { id } = (await publish()) as { id: string };
    await signUp();
    const c = (await call("postComment", { stageId: id, text: "さようなら", handle })) as { id: string };
    await call("deleteAccount", {});
    expect((await db.doc(`stages/${id}/comments/${c.id}`).get()).exists).toBe(false);
  });
});
