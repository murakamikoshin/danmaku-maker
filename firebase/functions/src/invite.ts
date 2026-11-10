import { createPrivateKey, randomInt, sign } from "node:crypto";
import { FieldValue, type Firestore } from "firebase-admin/firestore";
import { HttpsError } from "firebase-functions/v2/https";

/**
 * 友達招待のサーバー処理。報酬は、サーバーが付ける(アプリからは「ちょうだい」と言えない)。
 *
 * - inviteState/{uid}: 本人だけ読める。{ code(自分の招待コード), count(遊んでくれた人数), rewarded(報酬を出した人数。上限 MAX_REWARDED), joinedBy(招待してくれた人) }
 * - inviteCodes/{code}: コード → 招待した人の uid(サーバーだけ)
 * - invites/{招待された人の uid}: { inviter, plays(遊んだ回数), rewarded(付与済み), noReward(同じ端末で、もう招待された側になったことがある) }
 *
 * 流れ: 招待された人が初めて開く → registerInvite(1回だけ) → 3回遊ぶ → 両方に付与(称号・回復ドリンク)
 */

export const MAX_REWARDED = 10;
export const PLAYS_NEEDED = 3;
/** 招待された人のアカウントが、この日数より古いと、新しい人とみなさない(登録を受け付けない) */
export const MAX_ACCOUNT_AGE_MS = 3 * 24 * 3600_000;
/** 招待された人がもらう回復ドリンクの本数 */
export const INVITEE_DRINKS = 2;
/** 招待した人が、この人数に届いたときにもらう称号 */
export const INVITER_TITLES: Record<number, string> = { 1: "invited", 3: "inv3", 5: "inv5", 10: "inv10" };

const CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";   // 紛らわしい 0/O/1/I を除く
export const CODE_LENGTH = 8;
const CODE_RE = new RegExp(`^[${CODE_ALPHABET}]{${CODE_LENGTH}}$`);

export const normalizeCode = (raw: unknown): string => (typeof raw === "string" ? raw.trim().toUpperCase().replace(/[\s-]/g, "") : "");
export const isValidCode = (c: string): boolean => CODE_RE.test(c);
const newCode = (): string => Array.from({ length: CODE_LENGTH }, () => CODE_ALPHABET[randomInt(CODE_ALPHABET.length)]!).join("");

/** 端末の判定(DeviceCheck)。テストでは偽物に差し替える */
export interface DeviceGate {
  /** この端末が、もう招待された側として使われたか(判定できなければ false) */
  used(token: string): Promise<boolean>;
  /** この端末を、招待された側として使ったと記録する */
  mark(token: string): Promise<void>;
}

/** 自分の招待コード(なければ作る)と、状況 */
export async function getInviteInfo(db: Firestore, uid: string): Promise<{ code: string; count: number; rewarded: number; joinedBy: boolean }> {
  const ref = db.doc(`inviteState/${uid}`);
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    let code = snap.get("code") as string | undefined;
    if (!code) {
      for (let i = 0; i < 20; i++) {
        const c = newCode();
        const taken = await tx.get(db.doc(`inviteCodes/${c}`));
        if (!taken.exists) { code = c; break; }
      }
      if (!code) throw new HttpsError("internal", "code");
      tx.set(db.doc(`inviteCodes/${code}`), { uid });
      tx.set(ref, { code }, { merge: true });
    }
    return { code, count: (snap.get("count") as number | undefined) ?? 0, rewarded: (snap.get("rewarded") as number | undefined) ?? 0, joinedBy: !!snap.get("joinedBy") };
  });
}

/**
 * 招待コードを登録する。招待された人の uid につき 1 回だけ。
 * - 自分のコードは弾く / 存在しないコードは弾く / 古いアカウントは弾く
 * - 同じ端末で、もう招待された側になっていたら、登録は受け付けるが報酬は出さない
 */
export async function registerInvite(
  db: Firestore, uid: string, data: unknown, now: number,
  opts: { accountCreatedAt: number | null; device: DeviceGate | null },
): Promise<{ status: "registered" | "already"; noReward: boolean }> {
  const d = (data ?? {}) as { code?: unknown; deviceToken?: unknown };
  const code = normalizeCode(d.code);
  if (!isValidCode(code)) throw new HttpsError("invalid-argument", "code");
  const token = typeof d.deviceToken === "string" && d.deviceToken.length > 0 && d.deviceToken.length < 4096 ? d.deviceToken : null;
  if (opts.accountCreatedAt !== null && now - opts.accountCreatedAt > MAX_ACCOUNT_AGE_MS) throw new HttpsError("failed-precondition", "not-new");

  const inviteRef = db.doc(`invites/${uid}`);
  if ((await inviteRef.get()).exists) return { status: "already", noReward: false };
  const owner = await db.doc(`inviteCodes/${code}`).get();
  const inviter = owner.get("uid") as string | undefined;
  if (!inviter) throw new HttpsError("not-found", "code");
  if (inviter === uid) throw new HttpsError("invalid-argument", "self");

  let used = false;
  if (opts.device && token) { try { used = await opts.device.used(token); } catch { used = false; } }

  return db.runTransaction(async (tx) => {
    if ((await tx.get(inviteRef)).exists) return { status: "already" as const, noReward: false };
    tx.create(inviteRef, { inviter, plays: 0, rewarded: false, noReward: used, createdAt: FieldValue.serverTimestamp() });
    tx.set(db.doc(`inviteState/${uid}`), { joinedBy: inviter }, { merge: true });
    return { status: "registered" as const, noReward: used };
  }).then(async (r) => {
    if (r.status === "registered" && opts.device && token) { try { await opts.device.mark(token); } catch { /* 記録できなくても、登録は有効 */ } }
    return r;
  });
}

/**
 * 招待された人が遊んだ回数を数える(世界のステージ・スワイプ弾幕の両方)。3 回に届いたら、両方に報酬を付ける。
 * 招待されていない人・もう付与済みの人は、何もしない。
 */
export async function countInvitePlays(db: Firestore, uid: string, add: number): Promise<{ granted: boolean }> {
  if (add <= 0) return { granted: false };
  const ref = db.doc(`invites/${uid}`);
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists || snap.get("rewarded") === true) return { granted: false };
    const plays = ((snap.get("plays") as number | undefined) ?? 0) + add;
    if (plays < PLAYS_NEEDED) { tx.update(ref, { plays }); return { granted: false }; }
    const inviter = snap.get("inviter") as string;
    const inviterState = db.doc(`inviteState/${inviter}`);
    const inviterTitles = db.doc(`titleState/${inviter}`);
    const inviteeTitles = db.doc(`titleState/${uid}`);
    const inviteeUser = db.doc(`users/${uid}`);
    const [is, it, vt, vu] = await Promise.all([tx.get(inviterState), tx.get(inviterTitles), tx.get(inviteeTitles), tx.get(inviteeUser)]);
    // 同じ端末で、もう招待された側になっていた(再インストールでの自作自演)なら、どちらにも報酬を出さず、人数にも数えない
    if (snap.get("noReward") === true) { tx.update(ref, { plays, rewarded: true, rewardedAt: FieldValue.serverTimestamp() }); return { granted: false }; }
    tx.update(ref, { plays, rewarded: true, rewardedAt: FieldValue.serverTimestamp() });
    const count = ((is.get("count") as number | undefined) ?? 0) + 1;
    const rewarded = (is.get("rewarded") as number | undefined) ?? 0;
    const inviterGets = rewarded < MAX_REWARDED;
    const newRewarded = inviterGets ? rewarded + 1 : rewarded;
    tx.set(inviterState, { count, ...(inviterGets ? { rewarded: newRewarded } : {}) }, { merge: true });
    if (inviterGets) {
      const t = INVITER_TITLES[newRewarded];
      const ownedI = (it.get("titles") as string[] | undefined) ?? [];
      // 1 人目は「おそろい」の称号。以降は 3・5・10 人目で、その人数の称号
      if (t && !ownedI.includes(t)) tx.set(inviterTitles, { titles: [...ownedI, t] }, { merge: true });
    }
    const ownedV = (vt.get("titles") as string[] | undefined) ?? [];
    if (!ownedV.includes("invited")) tx.set(inviteeTitles, { titles: [...ownedV, "invited"] }, { merge: true });
    const base = vu.exists ? {} : { displayName: "", postCount: 0, blockedUids: [], createdAt: FieldValue.serverTimestamp() };
    tx.set(inviteeUser, { ...base, drinks: FieldValue.increment(INVITEE_DRINKS) }, { merge: true });
    return { granted: true };
  });
}

/** 招待機能を出す前から遊んでいる人にだけ配る「初期プレイヤー」称号。cutoffMs(環境変数)より前に作ったアカウントだけ。未設定の間は配らない */
export async function claimFounder(db: Firestore, uid: string, accountCreatedAt: number | null, cutoffMs: number | null): Promise<{ granted: boolean }> {
  if (cutoffMs === null || accountCreatedAt === null) return { granted: false };
  if (accountCreatedAt >= cutoffMs) return { granted: false };
  const ref = db.doc(`titleState/${uid}`);
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const owned = (snap.get("titles") as string[] | undefined) ?? [];
    if (owned.includes("founder")) return { granted: true };
    tx.set(ref, { titles: [...owned, "founder"] }, { merge: true });
    return { granted: true };
  });
}

// ---- DeviceCheck(Apple)----------------------------------------------------------------
const b64url = (b: Buffer | string) => Buffer.from(b).toString("base64url");

/** DeviceCheck の呼び出し用の署名つきトークン(ES256) */
export function deviceCheckJwt(p8Pem: string, keyId: string, teamId: string, nowSec: number): string {
  const head = b64url(JSON.stringify({ alg: "ES256", kid: keyId, typ: "JWT" }));
  const body = b64url(JSON.stringify({ iss: teamId, iat: nowSec }));
  const sig = sign("sha256", Buffer.from(`${head}.${body}`), { key: createPrivateKey(p8Pem), dsaEncoding: "ieee-p1363" });
  return `${head}.${body}.${b64url(sig)}`;
}

/** 環境変数から DeviceCheck の設定を読む。足りなければ null(その場合、端末の判定はしない) */
export function deviceGateFromEnv(env: NodeJS.ProcessEnv, fetcher: typeof fetch = fetch, now: () => number = Date.now): DeviceGate | null {
  const p8b64 = env.DEVICECHECK_P8, keyId = env.DEVICECHECK_KEY_ID, teamId = env.DEVICECHECK_TEAM_ID;
  if (!p8b64 || !keyId || !teamId) return null;
  const pem = Buffer.from(p8b64, "base64").toString("utf8");
  const host = env.DEVICECHECK_ENV === "development" ? "api.development.devicecheck.apple.com" : "api.devicecheck.apple.com";
  const call = async (path: string, token: string, extra: Record<string, unknown>) => {
    const res = await fetcher(`https://${host}/v1/${path}`, {
      method: "POST",
      headers: { Authorization: `Bearer ${deviceCheckJwt(pem, keyId, teamId, Math.floor(now() / 1000))}`, "Content-Type": "application/json" },
      body: JSON.stringify({ device_token: token, transaction_id: `${now()}-${randomInt(1e9)}`, timestamp: now(), ...extra }),
    });
    return { status: res.status, text: await res.text() };
  };
  return {
    used: async (token) => {
      const r = await call("query_two_bits", token, {});
      if (r.status !== 200) throw new Error(`devicecheck ${r.status}`);
      try { return (JSON.parse(r.text) as { bit0?: boolean }).bit0 === true; } catch { return false; }   // 「Bit State Not Found」= まだ記録なし
    },
    mark: async (token) => {
      const r = await call("update_two_bits", token, { bit0: true, bit1: false });
      if (r.status !== 200) throw new Error(`devicecheck ${r.status}`);
    },
  };
}
