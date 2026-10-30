/**
 * 1日(日本時間)に世界へ公開できるステージの数の上限。
 * ふつうは 1日5本まで。それ以上は、広告を見るごとに1本ぶん(追加券)増える。広告削除・永久買い切りパックの購入者は、上限なし。
 * 広告を見たことや購入者であることは、サーバーでは確かめられない(アプリの自己申告)ので、だれにでも効く「絶対上限」も置く。
 */
export const FREE_DAILY_POSTS = 5;
export const HARD_DAILY_POSTS = 30;
export const MAX_EXTRA_TICKETS = 10;
export const MAX_GRANTS_PER_DAY = 25;
export const MIN_GRANT_INTERVAL_MS = 10_000;

/** 日本時間の日付の番号(1970年1月1日からの日数) */
export const jstDay = (ms: number) => Math.floor((ms + 9 * 3600 * 1000) / 86_400_000);

export interface Quota { day: number; used: number; extra: number; grants: number }

type Getter = { get(field: string): unknown };
const int = (v: unknown) => (typeof v === "number" && Number.isFinite(v) ? Math.max(0, Math.trunc(v)) : 0);

/** ユーザー情報から、今日の記録を取り出す。日付が変わっていたら、今日の分は 0 から(追加券は持ち越す) */
export function readQuota(user: Getter, now: number): Quota {
  const today = jstDay(now);
  const extra = Math.min(MAX_EXTRA_TICKETS, int(user.get("extraPosts")));
  if (int(user.get("postDay")) !== today) return { day: today, used: 0, extra, grants: 0 };
  return { day: today, used: int(user.get("postsToday")), extra, grants: int(user.get("grantsToday")) };
}

/** 投稿できるか。premium: 購入者(アプリの自己申告) */
export function checkPost(q: Quota, premium: boolean): "ok" | "daily-limit" {
  if (q.used >= HARD_DAILY_POSTS) return "daily-limit";
  if (premium) return "ok";
  return q.used < FREE_DAILY_POSTS + q.extra ? "ok" : "daily-limit";
}

/** 投稿したあとの記録。無料の5本を超えたぶんは、追加券を1枚使う */
export function afterPost(q: Quota, premium: boolean): Quota {
  const used = q.used + 1;
  const extra = !premium && used > FREE_DAILY_POSTS ? Math.max(0, q.extra - 1) : q.extra;
  return { ...q, used, extra };
}

/** 広告を見た報告を受けて、追加券を1枚増やす。増やせないとき(持ちすぎ・今日の上限)は null */
export function afterGrant(q: Quota): Quota | null {
  if (q.extra >= MAX_EXTRA_TICKETS || q.grants >= MAX_GRANTS_PER_DAY) return null;
  return { ...q, extra: q.extra + 1, grants: q.grants + 1 };
}

/** 保存する項目 */
export const quotaFields = (q: Quota) => ({ postDay: q.day, postsToday: q.used, extraPosts: q.extra, grantsToday: q.grants });
