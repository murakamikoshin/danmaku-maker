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
