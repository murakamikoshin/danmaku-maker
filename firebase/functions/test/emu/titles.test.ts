// 称号と月間ランキング: 付与・付け替え・月の集計(王冠・メダル・上位%)・今月のランキング表示を、エミュレーターで通しで確かめる
import { initializeApp } from "firebase/app";
import { connectAuthEmulator, createUserWithEmailAndPassword, getAuth, signOut } from "firebase/auth";
import { connectFunctionsEmulator, getFunctions, httpsCallable } from "firebase/functions";
import { getFirestore as adminDb } from "firebase-admin/firestore";
import { initializeApp as adminInit } from "firebase-admin/app";
import { describe, expect, it } from "vitest";
import { grantScoreTitles, runMonthlyAward } from "../../src/titlesfns.js";
import { monthIdJst } from "../../src/titles.js";
import { rankingKey } from "../../src/swipe.js";

process.env.FIRESTORE_EMULATOR_HOST ??= "127.0.0.1:8080";
const app = initializeApp({ apiKey: "demo", projectId: "demo-danmaku" }, "titles");
const auth = getAuth(app);
connectAuthEmulator(auth, "http://127.0.0.1:9099", { disableWarnings: true });
const fns = getFunctions(app, "asia-northeast1");
connectFunctionsEmulator(fns, "127.0.0.1", 5001);
const db = adminDb(adminInit({ projectId: "demo-danmaku" }, "titles-admin"));

// eslint-disable-next-line @typescript-eslint/no-explicit-any
const call = (name: string, data: unknown = {}) => httpsCallable(fns, name)(data).then((r) => r.data as any);
const callErr = async (name: string, data: unknown = {}) => { try { await call(name, data); return null; } catch (e) { return (e as { message: string }).message; } };
let n = 0;
const signUp = async () => { await signOut(auth); const c = await createUserWithEmailAndPassword(auth, `t${Date.now()}${n++}@test.dev`, "password123"); return c.user.uid; };
const prof = async (uid: string) => (await db.doc(`publicProfiles/${uid}`).get()).data() ?? {};
const jst = (y: number, m: number, d: number, h = 0, mi = 0) => Date.UTC(y, m - 1, d, h - 9, mi);

describe("スコア達成の称号", () => {
  it("検証済みの点数で付き、二重には付かず、最初の1回だけ自動で付ける", async () => {
    const uid = `g${Date.now()}`;
    expect(await grantScoreTitles(db, uid, 99n)).toEqual([]);
    expect((await db.doc(`titleState/${uid}`).get()).exists).toBe(false);
    expect(await grantScoreTitles(db, uid, 10n ** 12n)).toEqual(["score1", "score2"]);
    expect((await db.doc(`titleState/${uid}`).get()).data()).toEqual({ titles: ["score1", "score2"], sel: "score2" });
    expect((await db.doc(`publicProfiles/${uid}`).get()).get("title")).toBe("score2");
    expect(await grantScoreTitles(db, uid, 10n ** 12n)).toEqual([]);
    expect(await grantScoreTitles(db, uid, 10n ** 18n)).toEqual(["score3"]);
    expect((await db.doc(`titleState/${uid}`).get()).get("sel")).toBe("score2");   // もう選んである。勝手に変えない
  });
  it("自分で「付けない」を選んだあとは、新しい称号を自動では付けない", async () => {
    const uid = `h${Date.now()}`;
    await db.doc(`titleState/${uid}`).set({ titles: ["score1"], sel: null });
    expect(await grantScoreTitles(db, uid, 10n ** 12n)).toEqual(["score2"]);
    expect((await db.doc(`titleState/${uid}`).get()).get("sel")).toBeNull();
  });
});

describe("称号を付ける", () => {
  it("持っている称号だけ付けられ、外せて、知らない ID は拒否", async () => {
    const uid = await signUp();
    await db.doc(`titleState/${uid}`).set({ titles: ["score1", "rank1:2026-10"] });
    expect(await callErr("setTitle", { id: "score2" })).toMatch(/not-owned/);
    expect(await callErr("setTitle", { id: "rank2:2026-10" })).toMatch(/not-owned/);
    expect(await callErr("setTitle", { id: "weird" })).toMatch(/title/);
    expect(await call("setTitle", { id: "rank1:2026-10" })).toEqual({ sel: "rank1:2026-10" });   // 取った月の称号は、あとからでも付けられる
    expect((await db.doc(`publicProfiles/${uid}`).get()).get("title")).toBe("rank1:2026-10");
    expect(await call("setTitle", { id: null })).toEqual({ sel: null });
    const p = await db.doc(`publicProfiles/${uid}`).get();
    expect(p.get("title")).toBeUndefined();
    expect((await db.doc(`titleState/${uid}`).get()).get("sel")).toBeNull();
  });
});

describe("月の集計", () => {
  it("順位に応じて称号・王冠・メダルを配り、二重には配らない。王冠・メダルは月ごとに永久に持てる", async () => {
    const tag = `w${Date.now()}`;
    const uids = Array.from({ length: 20 }, (_, i) => `${tag}_${String(i + 1).padStart(2, "0")}`);
    const now = jst(2026, 11, 1, 0, 5);   // 11/1 0:05 → 終わった月は 2026-10
    for (const [i, uid] of uids.entries()) {
      const score = 10n ** BigInt(30 - i);
      await db.doc(`swipeMonthly/2026-10/scores/${uid}`).set({ uid, key: rankingKey(score), score: score.toString(), bestStreak: 1, a: 0, n: 0, num: i });
    }
    // 王冠が前の月から残っている人
    await db.doc("publicProfiles/stale1").set({ cw: "2026-09", crown: 1, title: "score1" });

    const r = await runMonthlyAward(db, now);
    expect(r.month).toBe("2026-10");
    expect(r.participants).toBeGreaterThanOrEqual(20);   // 同じ月の他のテストの記録が混ざってもよい
    const titles = async (uid: string) => ((await db.doc(`titleState/${uid}`).get()).get("titles") as string[] | undefined) ?? [];
    const prof = async (uid: string) => (await db.doc(`publicProfiles/${uid}`).get()).data() ?? {};
    // 点数は 10^30 から順に小さくなるので、並びは uids の並びのまま
    expect(await titles(uids[0]!)).toEqual(expect.arrayContaining(["rank1:2026-10"]));
    expect(await prof(uids[0]!)).toMatchObject({ crown: 1 });
    expect(await prof(uids[1]!)).toMatchObject({ crown: 2 });
    expect(await prof(uids[2]!)).toMatchObject({ crown: 3 });
    expect(await titles(uids[2]!)).toContain("rank3:2026-10");
    expect(await titles(uids[3]!)).toContain("top10:2026-10");
    expect(await prof(uids[3]!)).toMatchObject({ medal: true });
    expect((await prof(uids[3]!)).crown).toBeUndefined();
    expect(await titles(uids[9]!)).toContain("top10:2026-10");
    expect(await titles(uids[5]!)).toEqual(expect.arrayContaining(["top10:2026-10", "pct50:2026-10"]));   // 20人: 6位は上位50%(10位まで)
    expect(await titles(uids[1]!)).toEqual(expect.arrayContaining(["rank2:2026-10", "pct10:2026-10"]));   // 20人: 2位は上位10%(2位まで)
    expect(await titles(uids[10]!)).toEqual([]);   // 11位は、どれにも入らない
    expect(await prof(uids[10]!)).toEqual({});   // 王冠もメダルもない
    // 参加賞: その月に遊んだ全員に、回復ドリンクが1個(11位の人にも)
    const drinks = async (uid: string) => (await db.doc(`users/${uid}`).get()).get("drinks");
    expect(await drinks(uids[0]!)).toBeGreaterThanOrEqual(1);
    expect(await drinks(uids[10]!)).toBeGreaterThanOrEqual(1);
    // 金の自機: 1位は5機、3位は3機、4位は2機。11位は、なし
    const ships = async (uid: string) => (((await db.doc(`inviteState/${uid}`).get()).get("ships") as string[] | undefined) ?? []).sort();
    expect(await ships(uids[0]!)).toEqual(["ace_gold", "bastion_gold", "gemini_gold", "lancer_gold", "phantom_gold"]);
    expect(await ships(uids[2]!)).toEqual(["gemini_gold", "lancer_gold", "phantom_gold"]);
    expect(await ships(uids[3]!)).toEqual(["lancer_gold", "phantom_gold"]);
    expect(await ships(uids[10]!)).toEqual([]);
    // 前から出ている王冠は、消さない(王冠は永久に持てる)
    expect((await prof("stale1")).crown).toBe(1);
    expect((await prof("stale1")).title).toBe("score1");   // 付けている称号はそのまま

    // 二重には配らない
    const again = await runMonthlyAward(db, now + 1000);
    expect(again.skipped).toBe(true);
    expect(await drinks(uids[10]!)).toBe(1);

    // 次の月になっても、王冠・メダル・称号は残る
    await runMonthlyAward(db, jst(2026, 12, 1, 0, 5));
    expect((await prof(uids[0]!)).crown).toBe(1);
    expect((await prof(uids[3]!)).medal).toBe(true);
    expect(await titles(uids[0]!)).toContain("rank1:2026-10");
  });
});

describe("王冠を付ける", () => {
  it("持っている月間の称号の王冠・メダルだけ付けられ、外せて、おまかせで最良に戻せる", async () => {
    const uid = await signUp();
    await db.doc(`titleState/${uid}`).set({ titles: ["score1", "rank3:2026-09", "rank1:2026-10", "top10:2026-11"] });
    expect(await callErr("setCrown", { id: "rank2:2026-10" })).toMatch(/not-owned/);
    expect(await callErr("setCrown", { id: "score1" })).toMatch(/crown/);
    expect(await callErr("setCrown", { id: "pct1:2026-10" })).toMatch(/crown/);
    expect(await call("setCrown", { id: "rank3:2026-09" })).toEqual({ sel: "rank3:2026-09", auto: false });
    expect(await prof(uid)).toMatchObject({ crown: 3 });
    expect(await call("setCrown", { id: "top10:2026-11" })).toEqual({ sel: "top10:2026-11", auto: false });
    const p = await prof(uid);
    expect(p.medal).toBe(true);
    expect(p.crown).toBeUndefined();   // メダルを選ぶと、王冠は外れる
    expect(await call("setCrown", { id: null })).toEqual({ sel: null, auto: false });
    expect((await prof(uid)).medal).toBeUndefined();
    expect((await db.doc(`titleState/${uid}`).get()).get("crownSel")).toBeNull();
    expect(await call("setCrown", { id: "auto" })).toEqual({ sel: "rank1:2026-10", auto: true });   // 王冠 > メダル、1位 > 3位
    expect((await prof(uid)).crown).toBe(1);
    expect((await db.doc(`titleState/${uid}`).get()).get("crownSel")).toBeUndefined();
  });
  it("自分で王冠を選んでいる人の王冠は、次の月の集計で勝手に変えない", async () => {
    const tag = `c${Date.now()}`;
    const keep = `${tag}_keep`, auto = `${tag}_auto`;
    await db.doc(`titleState/${keep}`).set({ titles: ["rank3:2026-01"], crownSel: "rank3:2026-01" });
    await db.doc(`publicProfiles/${keep}`).set({ crown: 3 });
    await db.doc(`titleState/${auto}`).set({ titles: ["rank3:2026-01"] });
    await db.doc(`publicProfiles/${auto}`).set({ crown: 3 });
    for (const [i, u] of [keep, auto].entries()) {
      const score = 10n ** BigInt(40 - i);
      await db.doc(`swipeMonthly/2027-01/scores/${u}`).set({ uid: u, key: rankingKey(score), score: score.toString(), bestStreak: 1, a: 0, n: 0, num: i });
    }
    await runMonthlyAward(db, jst(2027, 2, 1, 0, 5));
    // 1位・2位の王冠(2027-01)は、おまかせの人だけ新しい月のものになる
    expect((await prof(keep)).crown).toBe(3);
    expect((await prof(auto)).crown).toBeLessThan(3);
    expect(((await db.doc(`titleState/${keep}`).get()).get("titles") as string[]).some((t) => t.endsWith(":2027-01"))).toBe(true);
  });
});

describe("今月のランキング", () => {
  it("今月の記録だけを並べ、名前の横の称号・王冠を付けて返す。累計とは別", async () => {
    const month = monthIdJst(Date.now());
    const me = await signUp();
    const top = `top${Date.now()}`;
    await db.doc(`swipeMonthly/${month}/scores/${top}`).set({ uid: top, key: rankingKey(10n ** 20n), score: (10n ** 20n).toString(), bestStreak: 5, a: 1, n: 2, num: 7, name: "王者" });
    await db.doc(`swipeMonthly/${month}/scores/${me}`).set({ uid: me, key: rankingKey(10n ** 9n), score: (10n ** 9n).toString(), bestStreak: 2, a: 3, n: 4, num: 8 });
    await db.doc(`publicProfiles/${top}`).set({ title: `rank1:${month}`, crown: 1, cw: month });
    const w = await call("swipeRanking", { period: "month" });
    expect(w.period).toBe("month");
    expect(w.month).toBe(month);
    expect(w.endsAt).toBeGreaterThan(Date.now());
    expect(w.total).toBeGreaterThanOrEqual(2);
    const topRow = w.rows.find((r: { name: string }) => r.name === "王者");
    expect(topRow).toMatchObject({ crown: 1, title: `rank1:${month}`, medal: false, mine: false });
    expect(topRow.uid ?? null).toBeNull();   // 他人の uid は出さない
    const mine = w.rows.find((r: { mine: boolean }) => r.mine);
    expect(mine).toMatchObject({ crown: 0, title: null });
    expect(w.my.rank).toBeGreaterThan(topRow.rank);
    const all = await call("swipeRanking");
    expect(all.period).toBe("all");
    expect(all.rows.some((r: { name: string }) => r.name === "王者")).toBe(false);   // 累計には、今月の記録は入らない
  });
});
