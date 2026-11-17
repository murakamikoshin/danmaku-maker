/**
 * 投稿したステージで使ったボス(専用の絵のボス)を、作者が本当に持っているかの確かめと、
 * 利用停止(BAN)した人が、アカウントを消して作り直しても抜けられないようにする目印。
 */
import { createHash } from "node:crypto";

/** ボスの見た目の番号 → 商品名(アプリの BossCharacter.productKey と同じ) */
export const BOSS_BY_LOOK: Readonly<Record<number, string>> = {
  5: "fallen_angel", 6: "kitsune", 7: "ice_queen", 8: "reaper", 9: "witch", 10: "mech", 11: "puni", 12: "hire", 13: "dragon",
};
/** 永久買い切りパックでも手に入らないボス(招待限定。アプリの BossCharacter.purchasable が false のもの) */
export const NOT_IN_LIFETIME: readonly string[] = ["puni"];
export const PRODUCT_PREFIX = "com.koshin.danmakumaker.";

type LookPart = { bossLook?: number };
/** 竜王を持っている人だけが選べる BGM の番号(アプリの Stage.dragonBGMs と同じ) */
export const DRAGON_BGMS: readonly number[] = [5, 6];
/** ステージを公開するのに持っている必要がある、専用の絵のボスの商品名(重複なし)。竜王の曲を選んでいれば竜王も */
export function bossKeysOf(stage: LookPart & { waves?: readonly LookPart[]; bgm?: number }): string[] {
  const looks = [stage.bossLook, ...(stage.waves ?? []).map((w) => w.bossLook)];
  const keys = new Set<string>();
  for (const l of looks) {
    const k = l === undefined ? undefined : BOSS_BY_LOOK[l];
    if (k) keys.add(k);
  }
  if (stage.bgm !== undefined && DRAGON_BGMS.includes(stage.bgm)) keys.add("dragon");
  return [...keys];
}

/** 買った商品の ID の一覧から、そのボスを持っているか(ボス単品か、永久買い切りパック) */
export function ownsBossByPurchase(key: string, purchased: ReadonlySet<string>): boolean {
  if (purchased.has(`${PRODUCT_PREFIX}boss.${key}`)) return true;
  return !NOT_IN_LIFETIME.includes(key) && purchased.has(`${PRODUCT_PREFIX}lifetime`);
}

type FetchLike = (url: string, init: { headers: Record<string, string>; signal?: AbortSignal }) => Promise<{ ok: boolean; status: number; json(): Promise<unknown> }>;

/**
 * RevenueCat に、その人が買った商品(買い切り)の ID を聞く。購入者 ID は Firebase の uid にそろえてある(アプリの PurchaseService.identify)。
 * 聞けなかったとき(鍵がない・通信の失敗・遅い)は null。そのときは投稿を止めない(本当に買った人を、相手の不調で止めないため)
 */
export async function fetchPurchasedIds(uid: string, apiKey: string | undefined, fetchImpl: FetchLike = fetch as unknown as FetchLike): Promise<Set<string> | null> {
  if (!apiKey) return null;
  const ctl = new AbortController();
  const timer = setTimeout(() => ctl.abort(), 5000);
  try {
    const res = await fetchImpl(`https://api.revenuecat.com/v1/subscribers/${encodeURIComponent(uid)}`, {
      headers: { Authorization: `Bearer ${apiKey}`, Accept: "application/json" },
      signal: ctl.signal,
    });
    if (!res.ok) return null;
    const body = await res.json() as { subscriber?: { non_subscriptions?: Record<string, unknown[]>; subscriptions?: Record<string, unknown> } };
    const sub = body?.subscriber;
    if (!sub || typeof sub !== "object") return null;
    const ids = new Set<string>();
    for (const [id, list] of Object.entries(sub.non_subscriptions ?? {})) if (Array.isArray(list) && list.length > 0) ids.add(id);
    for (const id of Object.keys(sub.subscriptions ?? {})) ids.add(id);
    return ids;
  } catch {
    return null;
  } finally {
    clearTimeout(timer);
  }
}

/**
 * サインインに使った外部アカウント(Apple など)の目印。中身(Apple の ID)は残さず、ハッシュだけにする。
 * identities は ID トークンの firebase.identities({ "apple.com": ["…"], … })
 */
/** 目印にする外部アカウント。メールアドレス(identities の email)は使わない(ハッシュでも、辞書で元に戻せてしまうため) */
const MARK_PROVIDERS = new Set(["apple.com", "google.com"]);

export function providerMarks(identities: unknown): string[] {
  if (!identities || typeof identities !== "object") return [];
  const out: string[] = [];
  for (const [provider, ids] of Object.entries(identities as Record<string, unknown>)) {
    if (!MARK_PROVIDERS.has(provider) || !Array.isArray(ids)) continue;
    for (const id of ids) if (typeof id === "string" && id) out.push(createHash("sha256").update(`${provider}:${id}`).digest("hex"));
  }
  return [...new Set(out)];
}
