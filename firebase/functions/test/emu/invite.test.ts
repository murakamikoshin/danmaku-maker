// 友達招待: 登録・自分/古いアカウント/存在しないコードの拒否・3回遊んだときの付与・端末の判定・上限・初期プレイヤーを、エミュレーターで確かめる
import { grantParticipationDrink } from "../../src/swipefns.js";
import { getFirestore as adminDb } from "firebase-admin/firestore";
import { initializeApp as adminInit } from "firebase-admin/app";
import { describe, expect, it } from "vitest";
import { BOSS_TICKET_AT, FOUNDER_SHIP, SHIP_REWARDS, INVITEE_DRINKS, INVITEE_SHIP, INVITER_SHIPS, MAX_ACCOUNT_AGE_MS, MAX_REWARDED, PLAYS_NEEDED, claimFounder, countInvitePlays, getInviteInfo, registerInvite, type DeviceGate } from "../../src/invite.js";

process.env.FIRESTORE_EMULATOR_HOST ??= "127.0.0.1:8080";
const db = adminDb(adminInit({ projectId: "demo-danmaku" }, "invite-admin"));
const errCode = async (p: Promise<unknown>) => { try { await p; return null; } catch (e) { return (e as { message: string }).message; } };
const uid = (t: string) => `i${Date.now()}${Math.floor(Math.random() * 1e6)}${t}`;
const fresh = { accountCreatedAt: Date.now(), device: null as DeviceGate | null };
const titlesOf = async (u: string) => ((await db.doc(`titleState/${u}`).get()).get("titles") as string[] | undefined) ?? [];

describe("招待コード", () => {
  it("自分のコードは1つだけ作られ、何度呼んでも同じ", async () => {
    const a = uid("a");
    const x = await getInviteInfo(db, a), y = await getInviteInfo(db, a);
    expect(x.code).toMatch(/^[A-Z2-9]{8}$/);
    expect(y.code).toBe(x.code);
    expect(x).toMatchObject({ count: 0, rewarded: 0, joinedBy: false });
  });
});

describe("招待の登録", () => {
  it("登録は1回だけ。2回目は何も変えない", async () => {
    const [inviter, friend] = [uid("p"), uid("q")];
    const { code } = await getInviteInfo(db, inviter);
    expect(await registerInvite(db, friend, { code }, Date.now(), fresh)).toEqual({ status: "registered", noReward: false });
    expect(await registerInvite(db, friend, { code }, Date.now(), fresh)).toEqual({ status: "already", noReward: false });
    expect((await getInviteInfo(db, friend)).joinedBy).toBe(true);
  });
  it("自分のコード・存在しないコード・形のおかしいコード・古いアカウントは断る", async () => {
    const [inviter, friend] = [uid("r"), uid("s")];
    const { code } = await getInviteInfo(db, inviter);
    expect(await errCode(registerInvite(db, inviter, { code }, Date.now(), fresh))).toBe("self");
    expect(await errCode(registerInvite(db, friend, { code: "ZZZZZZZZ" }, Date.now(), fresh))).toBe("code");
    expect(await errCode(registerInvite(db, friend, { code: "abc" }, Date.now(), fresh))).toBe("code");
    expect(await errCode(registerInvite(db, friend, { code }, Date.now(), { accountCreatedAt: Date.now() - MAX_ACCOUNT_AGE_MS - 1000, device: null }))).toBe("not-new");
    expect((await db.doc(`invites/${friend}`).get()).exists).toBe(false);
  });
  it("コードは、小文字・空白・ハイフンが混ざっていても読める", async () => {
    const [inviter, friend] = [uid("t"), uid("u")];
    const { code } = await getInviteInfo(db, inviter);
    const typed = ` ${code.slice(0, 4).toLowerCase()}-${code.slice(4)} `;
    expect((await registerInvite(db, friend, { code: typed }, Date.now(), fresh)).status).toBe("registered");
  });
});

describe("3回遊んだときの付与", () => {
  it("3回に届くまでは何も付かず、届いたら両方に付く(1回だけ)", async () => {
    const [inviter, friend] = [uid("v"), uid("w")];
    const { code } = await getInviteInfo(db, inviter);
    await registerInvite(db, friend, { code }, Date.now(), fresh);
    expect(await countInvitePlays(db, friend, PLAYS_NEEDED - 1)).toEqual({ granted: false });
    expect(await titlesOf(inviter)).toEqual([]);
    expect(await countInvitePlays(db, friend, 1)).toMatchObject({ granted: true });
    expect(await titlesOf(inviter)).toEqual(["invited"]);
    expect((await db.doc(`users/${inviter}`).get()).exists).toBe(false);   // 1人目では、ボスのチケットは出ない
    expect(await titlesOf(friend)).toEqual(["invited"]);
    expect((await db.doc(`users/${friend}`).get()).get("drinks")).toBe(INVITEE_DRINKS);
    expect(await getInviteInfo(db, inviter)).toMatchObject({ count: 1, rewarded: 1, ships: ["original_steel"] });
    expect((await getInviteInfo(db, friend)).ships).toEqual([INVITEE_SHIP]);
    expect(await countInvitePlays(db, friend, 5)).toEqual({ granted: false });
    expect((await db.doc(`users/${friend}`).get()).get("drinks")).toBe(INVITEE_DRINKS);
  });
  it("招待されていない人が遊んでも、何も起きない", async () => {
    const a = uid("x");
    expect(await countInvitePlays(db, a, 10)).toEqual({ granted: false });
    expect((await db.doc(`invites/${a}`).get()).exists).toBe(false);
  });
  it("同じ端末で2度目に招待された人には、どちらにも報酬を出さず、人数にも数えない", async () => {
    const [inviter, friend] = [uid("y"), uid("z")];
    const { code } = await getInviteInfo(db, inviter);
    const marked: string[] = [];
    const device: DeviceGate = { used: async (t) => t === "seen", mark: async (t) => { marked.push(t); } };
    expect(await registerInvite(db, friend, { code, deviceToken: "seen" }, Date.now(), { ...fresh, device })).toEqual({ status: "registered", noReward: true });
    await countInvitePlays(db, friend, PLAYS_NEEDED);
    expect(await titlesOf(friend)).toEqual([]);
    expect((await db.doc(`users/${friend}`).get()).exists).toBe(false);
    expect(await titlesOf(inviter)).toEqual([]);
    expect(await getInviteInfo(db, inviter)).toMatchObject({ count: 0, rewarded: 0, ships: [] });
    expect((await getInviteInfo(db, friend)).ships).toEqual([]);
  });
  it("初めての端末は、使ったと記録される。端末の判定が壊れていても登録は通る", async () => {
    const [inviter, a, b] = [uid("k"), uid("l"), uid("m")];
    const { code } = await getInviteInfo(db, inviter);
    const marked: string[] = [];
    await registerInvite(db, a, { code, deviceToken: "new-device" }, Date.now(), { ...fresh, device: { used: async () => false, mark: async (t) => { marked.push(t); } } });
    expect(marked).toEqual(["new-device"]);
    const broken: DeviceGate = { used: async () => { throw new Error("apple down"); }, mark: async () => { throw new Error("apple down"); } };
    expect(await registerInvite(db, b, { code, deviceToken: "x" }, Date.now(), { ...fresh, device: broken })).toEqual({ status: "registered", noReward: false });
  });
  it("人数の称号は1・3・5・10人目で付き、自機は1人ごとに1機。上限を超えたぶんは、数えるが付けない", async () => {
    const inviter = uid("n");
    const { code } = await getInviteInfo(db, inviter);
    for (let i = 1; i <= MAX_REWARDED + 2; i++) {
      const f = uid(`f${i}`);
      await registerInvite(db, f, { code }, Date.now(), fresh);
      await countInvitePlays(db, f, PLAYS_NEEDED);
    }
    expect(await titlesOf(inviter)).toEqual(["invited", "inv3", "inv5", "inv10"]);
    expect(await getInviteInfo(db, inviter)).toMatchObject({ count: MAX_REWARDED + 2, rewarded: MAX_REWARDED });
    // ボスの無料チケットは、10・20人目で1枚ずつ(31人目は限定ボスの枠。チケットは出ない)
    expect((await db.doc(`users/${inviter}`).get()).get("bossTickets")).toBe(BOSS_TICKET_AT.length);
    // 31人目で、招待限定のボス(ぷにまる)が手に入る
    expect((await db.doc(`users/${inviter}`).get()).get("freeBosses")).toEqual(["puni"]);
    // 自機は節目(1・3・5・10・20・31人目)で、色ごとの6機種(1人目だけ1機)。重複なし、上限を超えたぶんは増えない
    expect(Object.keys(SHIP_REWARDS).map(Number)).toEqual([1, 3, 5, 10, 20, 31]);
    expect(new Set(INVITER_SHIPS).size).toBe(31);
    expect([...(await getInviteInfo(db, inviter)).ships].sort()).toEqual([...INVITER_SHIPS].sort());
  });
});

describe("初期プレイヤー", () => {
  it("締め切りより前に作ったアカウントだけ。締め切りが未設定なら配らない", async () => {
    const a = uid("fa"), b = uid("fb");
    const t = Date.now();
    expect(await claimFounder(db, a, t - 1000, null)).toEqual({ granted: false });
    expect(await claimFounder(db, a, t - 1000, t)).toMatchObject({ granted: true });
    expect(await claimFounder(db, a, t - 1000, t)).toMatchObject({ granted: true });
    expect(await titlesOf(a)).toEqual(["founder"]);
    expect((await getInviteInfo(db, a)).ships).toEqual([FOUNDER_SHIP]);
    expect(await claimFounder(db, b, t + 1000, t)).toEqual({ granted: false });
    expect(await titlesOf(b)).toEqual([]);
  });
});

describe("自機を渡す節目", () => {
  it("1人目は1機、3人目で鋼の6機種、その間の人数では増えない", async () => {
    const inviter = uid("s");
    const { code } = await getInviteInfo(db, inviter);
    const shipsAfter = async (n: number) => {
      const f = uid(`sf${n}`);
      await registerInvite(db, f, { code }, Date.now(), fresh);
      await countInvitePlays(db, f, PLAYS_NEEDED);
      return (await getInviteInfo(db, inviter)).ships.length;
    };
    expect(await shipsAfter(1)).toBe(1);
    expect(await shipsAfter(2)).toBe(1);
    expect(await shipsAfter(3)).toBe(7);
    expect(await shipsAfter(4)).toBe(7);
  });
});

describe("参加賞", () => {
  it("初めて遊び終えたとき、回復ドリンクを1個、1度だけ渡す", async () => {
    const u = uid("pd");
    expect(await grantParticipationDrink(db, u)).toBe(true);
    expect((await db.doc(`users/${u}`).get()).get("drinks")).toBe(1);
    expect(await grantParticipationDrink(db, u)).toBe(false);
    expect((await db.doc(`users/${u}`).get()).get("drinks")).toBe(1);
    // すでにドリンクを持っている人にも、1個足す
    const v = uid("pe");
    await db.doc(`users/${v}`).set({ displayName: "x", postCount: 0, blockedUids: [], drinks: 4 });
    expect(await grantParticipationDrink(db, v)).toBe(true);
    expect((await db.doc(`users/${v}`).get()).get("drinks")).toBe(5);
  });
});
