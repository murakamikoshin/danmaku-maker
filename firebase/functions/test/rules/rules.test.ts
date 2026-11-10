import { assertFails, assertSucceeds, initializeTestEnvironment, type RulesTestEnvironment } from "@firebase/rules-unit-testing";
import { doc, getDoc, setDoc, updateDoc, deleteDoc, serverTimestamp, collection, getDocs, query, where, limit } from "firebase/firestore";
import { readFileSync } from "node:fs";
import { afterAll, beforeAll, beforeEach, describe, it } from "vitest";

let env: RulesTestEnvironment;
const member = (uid: string) => env.authenticatedContext(uid, { firebase: { sign_in_provider: "apple.com" } }).firestore();
const anon = (uid: string) => env.authenticatedContext(uid, { firebase: { sign_in_provider: "anonymous" } }).firestore();

beforeAll(async () => {
  env = await initializeTestEnvironment({
    projectId: "demo-danmaku-rules",
    firestore: { rules: readFileSync(new URL("../../../firestore.rules", import.meta.url), "utf8"), host: "127.0.0.1", port: 8080 },
  });
});
afterAll(async () => { await env.cleanup(); });
beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, "stages/AAAAA"), { status: "published", authorUid: "author", name: "公開", likes: 0 });
    await setDoc(doc(db, "stages/BBBBB"), { status: "hidden", authorUid: "author", name: "非公開" });
    await setDoc(doc(db, "stages/CCCCC"), { status: "unlisted", authorUid: "author", name: "限定" });
    await setDoc(doc(db, "stages/CCCCC/scores/u1"), { uid: "u1", a: 1, n: 2, num: 1234, value: 500, mode: "boss", createdAt: new Date() });
    await setDoc(doc(db, "stages/AAAAA/likes/u1"), { createdAt: new Date() });
    await setDoc(doc(db, "users/u1"), { displayName: "A", blockedUids: [], postCount: 3, createdAt: new Date() });
    await setDoc(doc(db, "reports/x"), { stageId: "AAAAA" });
    await setDoc(doc(db, "stageReplays/AAAAA"), { clearReplay: "AQ==" });
    await setDoc(doc(db, "stages/AAAAA/scores/u1"), { uid: "u1", a: 1, n: 2, num: 1234, value: 500, mode: "boss", createdAt: new Date() });
    await setDoc(doc(db, "stages/BBBBB/scores/u1"), { uid: "u1", a: 1, n: 2, num: 1234, value: 500, mode: "boss", createdAt: new Date() });
    await setDoc(doc(db, "scoreReplays/AAAAA_u1"), { replay: "AQ==" });
    await setDoc(doc(db, "scoreMeta/u1"), { lastAt: 1 });
    await setDoc(doc(db, "stages/AAAAA/comments/c1"), { uid: "u1", a: 0, n: 0, num: 1, text: "いいね", status: "published", reports: 0, createdAt: new Date() });
    await setDoc(doc(db, "stages/AAAAA/comments/c2"), { uid: "u2", a: 0, n: 0, num: 2, text: "隠された", status: "hidden", reports: 3, createdAt: new Date() });
    await setDoc(doc(db, "stages/BBBBB/comments/c3"), { uid: "u1", a: 0, n: 0, num: 1, text: "非公開ステージ", status: "published", reports: 0, createdAt: new Date() });
    await setDoc(doc(db, "commentMeta/u1"), { lastAt: 1 });
    await setDoc(doc(db, "commentReports/x"), { stageId: "AAAAA" });
  });
});

describe("stages", () => {
  it("未ログインでも公開ステージを読める", async () => {
    await assertSucceeds(getDoc(doc(env.unauthenticatedContext().firestore(), "stages/AAAAA")));
  });
  it("公開のみを絞った一覧クエリは通る", async () => {
    const q = query(collection(anon("u9"), "stages"), where("status", "==", "published"), limit(20));
    await assertSucceeds(getDocs(q));
  });
  it("絞らない一覧クエリは拒否される", async () => {
    await assertFails(getDocs(query(collection(anon("u9"), "stages"), limit(20))));
  });
  it("非公開ステージは他人には読めず、作者本人は読める", async () => {
    await assertFails(getDoc(doc(anon("u9"), "stages/BBBBB")));
    await assertSucceeds(getDoc(doc(member("author"), "stages/BBBBB")));
  });
  it("URLを知っている人だけのステージは、IDを指定すれば誰でも読めるが、一覧には出ない", async () => {
    await assertSucceeds(getDoc(doc(anon("u9"), "stages/CCCCC")));
    await assertSucceeds(getDocs(query(collection(anon("u9"), "stages"), where("status", "==", "published"), limit(20))));
    await assertFails(getDocs(query(collection(anon("u9"), "stages"), where("status", "==", "unlisted"), limit(20))));
    await assertSucceeds(getDoc(doc(anon("u9"), "stages/CCCCC/scores/u1")));
  });
  it("クライアントからの書き込み・更新・削除はすべて拒否", async () => {
    const db = member("author");
    await assertFails(setDoc(doc(db, "stages/NEW22"), { status: "published", authorUid: "author" }));
    await assertFails(updateDoc(doc(db, "stages/AAAAA"), { likes: 999 }));
    await assertFails(updateDoc(doc(db, "stages/AAAAA"), { status: "hidden" }));
    await assertFails(deleteDoc(doc(db, "stages/AAAAA")));
  });
});

describe("likes", () => {
  it("自分のいいねだけ読める。書き込みは拒否", async () => {
    await assertSucceeds(getDoc(doc(member("u1"), "stages/AAAAA/likes/u1")));
    await assertFails(getDoc(doc(member("u2"), "stages/AAAAA/likes/u1")));
    await assertFails(setDoc(doc(member("u2"), "stages/AAAAA/likes/u2"), { createdAt: serverTimestamp() }));
    await assertFails(deleteDoc(doc(member("u1"), "stages/AAAAA/likes/u1")));
  });
});

describe("users", () => {
  it("本人だけ読める", async () => {
    await assertSucceeds(getDoc(doc(member("u1"), "users/u1")));
    await assertFails(getDoc(doc(member("u2"), "users/u1")));
  });
  it("blockedUids と displayName は更新できる", async () => {
    await assertSucceeds(updateDoc(doc(member("u1"), "users/u1"), { blockedUids: ["bad"] }));
    await assertSucceeds(updateDoc(doc(member("u1"), "users/u1"), { displayName: "B" }));
  });
  it("postCount など他の項目は更新できない", async () => {
    await assertFails(updateDoc(doc(member("u1"), "users/u1"), { postCount: 0 }));
    await assertFails(updateDoc(doc(member("u1"), "users/u1"), { banned: false }));
  });
  it("他人のドキュメントや匿名ユーザーは更新できない", async () => {
    await assertFails(updateDoc(doc(member("u2"), "users/u1"), { blockedUids: [] }));
    await assertFails(updateDoc(doc(anon("u1"), "users/u1"), { blockedUids: [] }));
  });
  it("作成は postCount 0 で、許可された項目だけ", async () => {
    const ok = { displayName: "N", blockedUids: [], postCount: 0, createdAt: serverTimestamp() };
    await assertSucceeds(setDoc(doc(member("u3"), "users/u3"), ok));
    await assertFails(setDoc(doc(member("u4"), "users/u4"), { ...ok, postCount: 100 }));
    await assertFails(setDoc(doc(member("u5"), "users/u5"), { ...ok, banned: false }));
  });
  it("削除はクライアントからはできない", async () => {
    await assertFails(deleteDoc(doc(member("u1"), "users/u1")));
  });
});

describe("サーバー専用コレクション", () => {
  it("reports / stageReplays / admin_alerts は読み書きとも拒否", async () => {
    const db = member("u1");
    await assertFails(getDoc(doc(db, "reports/x")));
    await assertFails(setDoc(doc(db, "reports/y"), { stageId: "AAAAA" }));
    await assertFails(getDoc(doc(db, "stageReplays/AAAAA")));
    await assertFails(setDoc(doc(db, "admin_alerts/z"), { a: 1 }));
  });
});


describe("scores(ランキング)", () => {
  it("ログイン済み(匿名も可)なら、公開ステージのランキングを読める", async () => {
    await assertSucceeds(getDoc(doc(anon("u9"), "stages/AAAAA/scores/u1")));
    await assertSucceeds(getDocs(query(collection(anon("u9"), "stages/AAAAA/scores"), limit(50))));
    await assertSucceeds(getDoc(doc(member("u9"), "stages/AAAAA/scores/u1")));
  });
  it("未ログインでは読めない", async () => {
    await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(), "stages/AAAAA/scores/u1")));
  });
  it("非公開ステージのランキングは読めない", async () => {
    await assertFails(getDoc(doc(anon("u9"), "stages/BBBBB/scores/u1")));
  });
  it("クライアントからは書き込めない(自分の記録でも)", async () => {
    await assertFails(setDoc(doc(member("u1"), "stages/AAAAA/scores/u1"), { uid: "u1", value: 1 }));
    await assertFails(updateDoc(doc(member("u1"), "stages/AAAAA/scores/u1"), { value: 1 }));
    await assertFails(deleteDoc(doc(member("u1"), "stages/AAAAA/scores/u1")));
    await assertFails(setDoc(doc(anon("u9"), "stages/AAAAA/scores/u9"), { uid: "u9", value: 1 }));
  });
  it("操作記録と送信間隔の記録には一切触れない", async () => {
    await assertFails(getDoc(doc(member("u1"), "scoreReplays/AAAAA_u1")));
    await assertFails(setDoc(doc(member("u1"), "scoreReplays/AAAAA_u1"), { replay: "x" }));
    await assertFails(getDoc(doc(member("u1"), "scoreMeta/u1")));
    await assertFails(setDoc(doc(member("u1"), "scoreMeta/u1"), { lastAt: 0 }));
  });
});


describe("comments(コメント)", () => {
  it("ログイン済み(匿名も可)なら、公開ステージの表示中のコメントを読める", async () => {
    await assertSucceeds(getDoc(doc(anon("u9"), "stages/AAAAA/comments/c1")));
    const q = query(collection(anon("u9"), "stages/AAAAA/comments"), where("status", "==", "published"), limit(30));
    await assertSucceeds(getDocs(q));
  });
  it("未ログインでは読めない", async () => {
    await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(), "stages/AAAAA/comments/c1")));
  });
  it("非表示のコメントと、非公開ステージのコメントは読めない", async () => {
    await assertFails(getDoc(doc(anon("u9"), "stages/AAAAA/comments/c2")));
    await assertFails(getDoc(doc(anon("u9"), "stages/BBBBB/comments/c3")));
  });
  it("絞らない一覧クエリは拒否される(非表示が混ざるため)", async () => {
    await assertFails(getDocs(query(collection(anon("u9"), "stages/AAAAA/comments"), limit(30))));
  });
  it("クライアントからは書き込めない(自分のコメントでも)", async () => {
    await assertFails(setDoc(doc(member("u1"), "stages/AAAAA/comments/new1"), { uid: "u1", text: "x", status: "published" }));
    await assertFails(updateDoc(doc(member("u1"), "stages/AAAAA/comments/c1"), { text: "書き換え" }));
    await assertFails(deleteDoc(doc(member("u1"), "stages/AAAAA/comments/c1")));
  });
  it("投稿間隔と通報の記録には一切触れない", async () => {
    await assertFails(getDoc(doc(member("u1"), "commentMeta/u1")));
    await assertFails(setDoc(doc(member("u1"), "commentMeta/u1"), { lastAt: 0 }));
    await assertFails(getDoc(doc(member("u1"), "commentReports/x")));
  });
});

describe("マイステージのバックアップ", () => {
  const ok = { data: "{}", updatedAt: new Date() };
  it("本人(匿名も可)は読み書き・削除できる", async () => {
    await assertSucceeds(setDoc(doc(anon("a1"), "users/a1/savedStages/s1"), ok));
    await assertSucceeds(getDoc(doc(anon("a1"), "users/a1/savedStages/s1")));
    await assertSucceeds(getDocs(collection(anon("a1"), "users/a1/savedStages")));
    await assertSucceeds(deleteDoc(doc(anon("a1"), "users/a1/savedStages/s1")));
  });
  it("他人は読めず、書けない", async () => {
    await assertSucceeds(setDoc(doc(member("a2"), "users/a2/savedStages/s1"), ok));
    await assertFails(getDoc(doc(member("a3"), "users/a2/savedStages/s1")));
    await assertFails(setDoc(doc(member("a3"), "users/a2/savedStages/s2"), ok));
  });
  it("決まった項目以外は書けない", async () => {
    await assertFails(setDoc(doc(anon("a4"), "users/a4/savedStages/s1"), { ...ok, extra: 1 }));
    await assertFails(setDoc(doc(anon("a4"), "users/a4/savedStages/s1"), { data: 1, updatedAt: new Date() }));
  });
});

describe("通知を受け取る端末", () => {
  const dev = { token: "tok", lang: "ja", enabled: true, likes: true, comments: false, plays: true, updatedAt: serverTimestamp() };
  it("本人は登録・更新・削除できる", async () => {
    await assertSucceeds(setDoc(doc(anon("p1"), "users/p1/pushDevices/d1"), dev));
    await assertSucceeds(setDoc(doc(anon("p1"), "users/p1/pushDevices/d1"), { ...dev, enabled: false }));
    await assertSucceeds(deleteDoc(doc(anon("p1"), "users/p1/pushDevices/d1")));
  });
  it("他人の端末は読めず、登録もできない", async () => {
    await assertSucceeds(setDoc(doc(member("p2"), "users/p2/pushDevices/d1"), dev));
    await assertFails(getDoc(doc(member("p3"), "users/p2/pushDevices/d1")));
    await assertFails(setDoc(doc(member("p3"), "users/p2/pushDevices/d2"), dev));
  });
  it("型や項目が違うものは書けない", async () => {
    await assertFails(setDoc(doc(anon("p4"), "users/p4/pushDevices/d1"), { ...dev, likes: "yes" }));
    await assertFails(setDoc(doc(anon("p4"), "users/p4/pushDevices/d1"), { ...dev, admin: true }));
  });
  it("連打の間引き用の記録は、本人でも触れない", async () => {
    await assertFails(getDoc(doc(anon("p5"), "users/p5/pushThrottle/x_likes")));
  });
});

describe("スワイプ弾幕", () => {
  it("候補の一覧とランキングは、ログイン済みなら読めるが、書けない", async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), "swipePools/meta"), { current: "v1" });
      await setDoc(doc(ctx.firestore(), "swipePools/v1/chunks/0000"), { entries: [] });
      await setDoc(doc(ctx.firestore(), "swipeScores/u1"), { key: "001" + "1", score: "1" });
      await setDoc(doc(ctx.firestore(), "swipeRuns/r1"), { uid: "u1" });
    });
    await assertSucceeds(getDoc(doc(anon("s1"), "swipePools/meta")));
    await assertSucceeds(getDoc(doc(member("s1"), "swipePools/v1/chunks/0000")));
    await assertSucceeds(getDoc(doc(member("s1"), "swipeScores/u1")));
    await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(), "swipeScores/u1")));
    await assertFails(setDoc(doc(member("u1"), "swipeScores/u1"), { key: "999", score: "9" }));
    await assertFails(setDoc(doc(member("u1"), "swipePools/meta"), { current: "x" }));
  });
  it("サーバーから配る商品(catalog): ログイン済みなら読める。誰も書けない", async () => {
    await env.withSecurityRulesDisabled(async (ctx) => { await setDoc(doc(ctx.firestore(), "catalog/shop"), { v: 1, items: [] }); });
    await assertSucceeds(getDoc(doc(member("u1"), "catalog/shop")));
    await assertSucceeds(getDoc(doc(anon("u1"), "catalog/shop")));
    await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(), "catalog/shop")));
    await assertFails(setDoc(doc(member("u1"), "catalog/shop"), { v: 1, items: [{ id: "x_hack" }] }));
  });
  it("称号: 持っている称号は本人だけが読める。名前の横に出す分はログイン済みなら読める。どちらも書けない", async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), "titleState/u1"), { titles: ["score1"], sel: "score1" });
      await setDoc(doc(ctx.firestore(), "publicProfiles/u1"), { title: "score1", crown: 1, cw: "2026-W45" });
    });
    await assertSucceeds(getDoc(doc(member("u1"), "titleState/u1")));
    await assertSucceeds(getDoc(doc(anon("u1"), "titleState/u1")));
    await assertFails(getDoc(doc(member("u2"), "titleState/u1")));
    await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(), "titleState/u1")));
    await assertSucceeds(getDoc(doc(member("u2"), "publicProfiles/u1")));
    await assertSucceeds(getDoc(doc(anon("u2"), "publicProfiles/u1")));
    await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(), "publicProfiles/u1")));
    // 自分でも、称号や王冠は書けない
    await assertFails(setDoc(doc(member("u1"), "titleState/u1"), { titles: ["score4"], sel: "score4" }));
    await assertFails(setDoc(doc(member("u1"), "publicProfiles/u1"), { title: "score4", crown: 1 }));
    await assertFails(setDoc(doc(member("u3"), "publicProfiles/u3"), { crown: 1 }));
  });
  it("実行中のプレイと課金の記録は、本人でも触れない", async () => {
    await assertFails(getDoc(doc(member("u1"), "swipeRuns/r1")));
    await assertFails(setDoc(doc(member("u1"), "swipeRuns/r2"), { uid: "u1", seed: 1 }));
    await assertFails(getDoc(doc(member("u1"), "swipeEvents/e1")));
  });
  it("スタミナ・パス・ドリンクは、自分で書き換えられない(読むのはよい)", async () => {
    await assertSucceeds(getDoc(doc(member("u1"), "users/u1")));
    await assertFails(updateDoc(doc(member("u1"), "users/u1"), { drinks: 99 }));
    await assertFails(updateDoc(doc(member("u1"), "users/u1"), { stamina: { v: 5, at: 0 } }));
    await assertFails(updateDoc(doc(member("u1"), "users/u1"), { pass: { until: 9e15 } }));
  });
});
