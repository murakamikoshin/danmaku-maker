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
