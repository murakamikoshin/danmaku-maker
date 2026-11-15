// ランク戦: 戦績 → 人同士のマッチ → 二人の記録の提出と判定 → ボット戦 を、エミュレーターで通しで確かめる
import { initializeApp } from "firebase/app";
import { connectAuthEmulator, createUserWithEmailAndPassword, getAuth, signOut } from "firebase/auth";
import { connectFunctionsEmulator, getFunctions, httpsCallable } from "firebase/functions";
import { getFirestore as adminDb } from "firebase-admin/firestore";
import { getDatabaseWithUrl } from "firebase-admin/database";
import { initializeApp as adminInit } from "firebase-admin/app";
import { describe, expect, it } from "vitest";
import { decodeReplay } from "../../src/fullsim.js";
import { rankedCompare, rankedScore } from "../../src/ranked.js";
import { encodeReplay, RTDB_URL } from "../../src/rankedfns.js";

process.env.FIRESTORE_EMULATOR_HOST ??= "127.0.0.1:8080";
process.env.FIREBASE_DATABASE_EMULATOR_HOST ??= "127.0.0.1:9000";
const app = initializeApp({ apiKey: "demo", projectId: "demo-danmaku" }, "ranked");
const auth = getAuth(app);
connectAuthEmulator(auth, "http://127.0.0.1:9099", { disableWarnings: true });
const fns = getFunctions(app, "asia-northeast1");
connectFunctionsEmulator(fns, "127.0.0.1", 5001);
const adminApp = adminInit({ projectId: "demo-danmaku" }, "ranked-admin");
const db = adminDb(adminApp);
const rtdb = getDatabaseWithUrl(RTDB_URL, adminApp);

// eslint-disable-next-line @typescript-eslint/no-explicit-any
const call = (name: string, data: unknown = {}) => httpsCallable(fns, name)(data).then((r) => r.data as any);
const callErr = async (name: string, data: unknown = {}) => { try { await call(name, data); return null; } catch (e) { return (e as { message: string }).message.replace(/ \[\d+\]$/, ""); } };
let n = 0;
const signUp = async (name: string) => {
  await signOut(auth);
  const c = await createUserWithEmailAndPassword(auth, `r${Date.now()}${n++}@test.dev`, "password123");
  await db.doc(`users/${c.user.uid}`).set({ displayName: name }, { merge: true });
  return c.user.uid;
};
const signInAs = async (email: string) => { await signOut(auth); const { signInWithEmailAndPassword } = await import("firebase/auth"); await signInWithEmailAndPassword(auth, email, "password123"); };

/** 動かない記録(steps ステップ) */
const still = (steps: number) => { const m = new Int8Array(steps * 2); return { moves: m, steps, replay: encodeReplay(m, steps) }; };
/** 右へ動き続ける記録 */
const right = (steps: number) => { const m = new Int8Array(steps * 2); for (let i = 0; i < steps; i++) m[i * 2] = 2; return { moves: m, steps, replay: encodeReplay(m, steps) }; };

describe("ランク戦のサーバー", () => {
  it("はじめての人はレート 1000(シルバー)", async () => {
    await signUp("はじめて");
    const s = await call("rankedGetStatus");
    expect([s.rating, s.games, s.rank]).toEqual([1000, 0, "silver"]);
  });

  it("二人が待つとマッチして、二人の記録がそろうと勝ち負けとレートが決まる", async () => {
    await rtdb.ref("rq").remove();
    const emailA = `a${Date.now()}@test.dev`, emailB = `b${Date.now()}@test.dev`;
    await signOut(auth);
    const ua = (await createUserWithEmailAndPassword(auth, emailA, "password123")).user.uid;
    await db.doc(`users/${ua}`).set({ displayName: "アリス" }, { merge: true });
    const first = await call("rankedJoinQueue");
    expect(first.waiting).toBe(true);
    await signOut(auth);
    const ub = (await createUserWithEmailAndPassword(auth, emailB, "password123")).user.uid;
    await db.doc(`users/${ub}`).set({ displayName: "ボブ" }, { merge: true });
    const second = await call("rankedJoinQueue");
    expect(typeof second.matchId).toBe("string");
    const id = second.matchId as string;
    // 先に待っていた人にも、同じ対戦が届く
    expect((await rtdb.ref(`rq/${ua}/m`).get()).val()).toBe(id);
    const meta = (await rtdb.ref(`rm/${id}/meta`).get()).val();
    expect(Object.keys(meta.players).sort()).toEqual([ua, ub].sort());
    expect(meta.players[ua].name).toBe("アリス");
    const match = (await db.doc(`rankedMatches/${id}`).get()).data()!;
    expect([match.kind, match.status, match.players.length]).toEqual(["live", "playing", 2]);

    // B が先に出す → まだ決まらない
    const rb = right(300), ra = still(300);
    const pend = await call("rankedSubmitRun", { matchId: id, replay: rb.replay });
    expect(pend.pending).toBe(true);
    // A が出す → 決まる
    await signInAs(emailA);
    const res = await call("rankedSubmitRun", { matchId: id, replay: ra.replay });
    expect(res.pending).toBe(false);
    const sa = rankedScore(match.seed, ra.moves, ra.steps), sb = rankedScore(match.seed, rb.moves, rb.steps);
    expect(res.me).toEqual(sa);
    expect(res.opp).toEqual(sb);
    const c = rankedCompare(sa, sb);
    expect(res.result).toBe(c > 0 ? "win" : c < 0 ? "lose" : "draw");
    if (c !== 0) expect(res.ratingAfter).toBe(1000 + (c > 0 ? 24 : -24));   // 最初の10戦は ±24
    const pa = (await db.doc(`rankedPlayers/${ua}`).get()).data()!;
    const pb = (await db.doc(`rankedPlayers/${ub}`).get()).data()!;
    expect(pa.rating + pb.rating).toBe(2000);
    expect([pa.games, pb.games]).toEqual([1, 1]);
    // 二回目の提出は、結果を返すだけ(レートは動かない)
    const again = await call("rankedSubmitRun", { matchId: id, replay: ra.replay });
    expect(again.ratingAfter).toBe(res.ratingAfter);
    expect((await db.doc(`rankedPlayers/${ua}`).get()).get("games")).toBe(1);
  }, 60_000);

  it("相手が見つからなければボット。人らしい名前で、記録をそのまま再生でき、結果はボット相手の半分だけ動く", async () => {
    await signUp("ソロ");
    await call("rankedJoinQueue");
    const bot = await call("rankedStartBot", { lang: "ja" });
    expect(typeof bot.matchId).toBe("string");
    expect(bot.opponent.name.length).toBeGreaterThan(0);
    expect(bot.opponent.name).not.toMatch(/bot|cpu/i);
    const d = decodeReplay(bot.replay, 30_000)!;
    const opp = rankedScore(bot.seed, d.moves, d.steps);
    expect(opp.ticks).toBeGreaterThan(0);
    const mine = still(240);
    const res = await call("rankedSubmitRun", { matchId: bot.matchId, replay: mine.replay });
    expect(res.pending).toBe(false);
    expect(res.opp).toEqual(opp);
    expect(Math.abs(res.ratingAfter - 1000)).toBeLessThanOrEqual(13);   // 24 の半分(丸め)
  }, 120_000);

  it("結果は最初の1回だけ。相手がいなくなったら rankedClaimWin でその場で決着する。始まった対戦には入り直せない", async () => {
    await rtdb.ref("rq").remove();
    const emailA = `ca${Date.now()}@test.dev`, emailB = `cb${Date.now()}@test.dev`;
    await signOut(auth);
    const ua = (await createUserWithEmailAndPassword(auth, emailA, "password123")).user.uid;
    await call("rankedJoinQueue");
    await signOut(auth);
    await createUserWithEmailAndPassword(auth, emailB, "password123");
    const id = (await call("rankedJoinQueue")).matchId as string;
    // 始まる時刻を過去にする(相手 A は一度もつながらない)
    await db.doc(`rankedMatches/${id}`).update({ startAt: Date.now() - 60_000 });
    await rtdb.ref(`rq/${ua}/s`).set(Date.now() - 60_000);
    const first = right(300), second = still(600);
    expect((await call("rankedSubmitRun", { matchId: id, replay: first.replay })).pending).toBe(true);
    await new Promise((r) => setTimeout(r, 3100));
    const again = await call("rankedSubmitRun", { matchId: id, replay: second.replay });
    const seed = (await db.doc(`rankedMatches/${id}`).get()).get("seed") as number;
    expect(again.me).toEqual(rankedScore(seed, first.moves, first.steps));   // 上書きされない
    const res = await call("rankedClaimWin", { matchId: id });
    expect(res.pending).toBe(false);
    expect(res.result).toBe("win");
    // A が入り直しても、始まった対戦には戻らない
    await signInAs(emailA);
    const rejoin = await call("rankedJoinQueue");
    expect(rejoin.matchId).not.toBe(id);
  }, 60_000);

  it("ボット戦は引き直せない: 始まる前に次を頼むと、前のボット戦は負け。5 秒より早くは頼めない。入り直しても負け", async () => {
    const uid = await signUp("ひきなおし");
    const first = await call("rankedStartBot", { lang: "ja" });
    expect(await callErr("rankedStartBot", { lang: "ja" })).toBe("too-fast");
    // まだ始まっていなくても、取り消しではなく負け(来なかった扱い)
    await db.doc(`rankedMeta/${uid}`).update({ lastBotAt: Date.now() - 6000 });
    const second = await call("rankedStartBot", { lang: "ja" });
    expect(second.matchId).not.toBe(first.matchId);
    const prev = (await db.doc(`rankedMatches/${first.matchId}`).get()).data()!;
    expect(prev.status).toBe("done");
    expect(prev.changes[uid].result).toBe(0);
    expect((await db.doc(`rankedPlayers/${uid}`).get()).get("losses")).toBe(1);
    // 待ち行列に入り直しても、途中のボット戦は負けで締める
    await rtdb.ref("rq").remove();
    await call("rankedJoinQueue");
    await call("rankedLeaveQueue");
    const sec = (await db.doc(`rankedMatches/${second.matchId}`).get()).data()!;
    expect(sec.status).toBe("done");
    expect((await db.doc(`rankedPlayers/${uid}`).get()).get("losses")).toBe(2);
    // 終わった対戦の結果は、あとから出しても変わらない(ふつうの流れ: 終わってから「もう一戦」は、これまでどおり)
    await db.doc(`rankedMeta/${uid}`).update({ lastBotAt: Date.now() - 6000 });
    const third = await call("rankedStartBot", { lang: "ja" });
    await db.doc(`rankedMatches/${third.matchId}`).update({ startAt: Date.now() - 10_000 });
    const res = await call("rankedSubmitRun", { matchId: third.matchId, replay: still(240).replay });
    expect(res.pending).toBe(false);
    await db.doc(`rankedMeta/${uid}`).update({ lastBotAt: Date.now() - 6000 });
    await call("rankedStartBot", { lang: "ja" });
    expect((await db.doc(`rankedMatches/${third.matchId}`).get()).get(`changes.${uid}.after`)).toBe(res.ratingAfter);
    expect((await db.doc(`rankedPlayers/${uid}`).get()).get("games")).toBe(3);
  }, 180_000);

  it("相手の位置の更新が 30 秒止まったら、rankedClaimWin で決着。遅れていても更新が続いていれば待つ", async () => {
    await rtdb.ref("rq").remove();
    const emailA = `sa${Date.now()}@test.dev`, emailB = `sb${Date.now()}@test.dev`;
    await signOut(auth);
    const ua = (await createUserWithEmailAndPassword(auth, emailA, "password123")).user.uid;
    await call("rankedJoinQueue");
    await signOut(auth);
    await createUserWithEmailAndPassword(auth, emailB, "password123");
    const id = (await call("rankedJoinQueue")).matchId as string;
    await db.doc(`rankedMatches/${id}`).update({ startAt: Date.now() - 50_000 });
    await rtdb.ref(`rq/${ua}/s`).set(Date.now() - 50_000);
    // A は 10 秒ぶんしか進んでいない(遅い端末。遅れは 40 秒)が、位置は届いている
    await rtdb.ref(`rm/${id}/p/${ua}`).set({ x: 180, y: 460, t: 10 * 120 });
    expect((await call("rankedSubmitRun", { matchId: id, replay: right(300).replay })).pending).toBe(true);
    // 提出のときに、相手の位置を見た記録が残る
    expect((await rtdb.ref(`rm/${id}/seen/${ua}`).get()).val()).toMatchObject({ t: 10 * 120 });
    expect((await call("rankedClaimWin", { matchId: id })).pending).toBe(true);
    // 進んでいれば待つ
    await rtdb.ref(`rm/${id}/seen/${ua}`).set({ t: 10 * 120, at: Date.now() - 40_000 });
    await rtdb.ref(`rm/${id}/p/${ua}`).set({ x: 180, y: 460, t: 11 * 120 });
    expect((await call("rankedClaimWin", { matchId: id })).pending).toBe(true);
    // 前に見たときから 30 秒以上止まっていたら決着
    await rtdb.ref(`rm/${id}/seen/${ua}`).set({ t: 11 * 120, at: Date.now() - 31_000 });
    const res = await call("rankedClaimWin", { matchId: id });
    expect(res.pending).toBe(false);
    expect(res.result).toBe("win");
  }, 60_000);

  it("自分の出ていない対戦には出せない・壊れた記録は受け付けない", async () => {
    await signUp("よそもの");
    expect(await callErr("rankedSubmitRun", { matchId: "nonexistent000", replay: still(10).replay })).toMatch(/^match/);
    const bot = await call("rankedStartBot", { lang: "en" });
    expect(await callErr("rankedSubmitRun", { matchId: bot.matchId, replay: "!!!" })).toBe("replay-broken");
    await signUp("べつの人");
    expect(await callErr("rankedSubmitRun", { matchId: bot.matchId, replay: still(10).replay })).toBe("not-player");
  }, 120_000);
});
