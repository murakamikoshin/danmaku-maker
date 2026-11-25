/**
 * 投稿したステージで使ったボス(専用の絵のボス)を、作者が本当に持っているかの確かめと、
 * 利用停止(BAN)した人が、アカウントを消して作り直しても抜けられないようにする目印。
 */
import { createHash } from "node:crypto";

/** ボスの見た目の番号 → 商品名(アプリの BossCharacter.productKey と同じ) */
export const BOSS_BY_LOOK: Readonly<Record<number, string>> = {
  5: "fallen_angel", 6: "kitsune", 7: "ice_queen", 8: "reaper", 9: "witch", 10: "mech", 11: "puni", 12: "hire", 13: "dragon", 14: "santa",
};
/** 永久買い切りパックでも手に入らないボス(招待限定。アプリの BossCharacter.purchasable が false のもの) */
export const NOT_IN_LIFETIME: readonly string[] = ["puni"];
/**
 * 期間限定で売るボス(アプリの BossCharacter.season が nil でないもの)。
 * **サーバーは販売期間を見ない**: 持っているかは、買った記録(単品か永久買い切りパック)だけで決める。
 * 期間が終わって売り場から消えても、買った人・永久買い切りパックの人(期間のあとに買った人も)は公開できる。
 * だから NOT_IN_LIFETIME には入れない(入れると、永久買い切りパックの「これから追加される課金コンテンツも全部」の約束を破る)
 */
export const SEASONAL_BOSSES: readonly string[] = ["santa"];
/** ボスの商品名の一覧(アプリの BossCharacter.productKey と同じ) */
export const BOSS_KEYS: readonly string[] = Object.values(BOSS_BY_LOOK);
/** 無料チケットでは手に入らないボス(アプリの BossCharacter.ticketEligible が false のもの)。招待限定のぷにまると、期間限定のサンタ娘 */
export const PAID_ONLY_BOSSES: readonly string[] = ["puni", "santa"];
export const PRODUCT_PREFIX = "com.koshin.danmakumaker.";

/**
 * 買って手に入れる、雑魚の見た目のセット(アプリの MookPack と同じ)。looks は、ステージの mookLook の番号の範囲(両端を含む)。
 * season は、期間限定で売るセットの期間の名前。ボスと同じで、**サーバーは販売期間を見ない**(買った記録だけで決める)
 */
export const MOOK_PACKS: Readonly<Record<string, { from: number; to: number; season?: string }>> = {
  xmas: { from: 5, to: 8, season: "xmas" },
};
/** mookLook に入れられる最大の番号(アプリの DanmakuConfig.mookLooks - 1) */
export const MOOK_LOOK_MAX = Math.max(4, ...Object.values(MOOK_PACKS).map((p) => p.to));
/** 期間限定のボスの、期間の名前(アプリの BossCharacter.season)。その期間の全部入り(pack.<期間>)でも手に入る */
export const BOSS_SEASON: Readonly<Record<string, string>> = { santa: "xmas" };

type LookPart = { bossLook?: number; mooks?: number; mookLook?: number };
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
  const season = BOSS_SEASON[key];
  if (season && purchased.has(`${PRODUCT_PREFIX}pack.${season}`)) return true;
  return !NOT_IN_LIFETIME.includes(key) && purchased.has(`${PRODUCT_PREFIX}lifetime`);
}

/**
 * 公開しようとしているステージで、作者が持っていないボス(空なら公開してよい)。
 * free は、チケット・招待でもらったボス(users.freeBosses)。purchased は RevenueCat に聞いた、買った商品の ID
 */
export function missingBosses(stage: Parameters<typeof bossKeysOf>[0], free: readonly string[], purchased: ReadonlySet<string>): string[] {
  return bossKeysOf(stage).filter((k) => !free.includes(k) && !ownsBossByPurchase(k, purchased));
}

/** ステージを公開するのに持っている必要がある、雑魚の見た目のセットの名前(重複なし)。雑魚を出さない場面の指定は数えない */
export function mookPacksOf(stage: LookPart & { waves?: readonly LookPart[] }): string[] {
  const keys = new Set<string>();
  for (const part of [stage, ...(stage.waves ?? [])]) {
    if (part.mooks === undefined || part.mookLook === undefined) continue;
    for (const [k, p] of Object.entries(MOOK_PACKS)) if (part.mookLook >= p.from && part.mookLook <= p.to) keys.add(k);
  }
  return [...keys];
}

/** 買った商品の ID の一覧から、その雑魚の見た目のセットを持っているか(セット単品・その期間の全部入り・永久買い切りパック) */
export function ownsMookPackByPurchase(key: string, purchased: ReadonlySet<string>): boolean {
  if (purchased.has(`${PRODUCT_PREFIX}mooks.${key}`) || purchased.has(`${PRODUCT_PREFIX}lifetime`)) return true;
  const season = MOOK_PACKS[key]?.season;
  return season !== undefined && purchased.has(`${PRODUCT_PREFIX}pack.${season}`);
}

/** 公開しようとしているステージで、作者が持っていない雑魚の見た目のセット(空なら公開してよい) */
export function missingMookPacks(stage: Parameters<typeof mookPacksOf>[0], purchased: ReadonlySet<string>): string[] {
  return mookPacksOf(stage).filter((k) => !ownsMookPackByPurchase(k, purchased));
}

/**
 * 買って手に入れる、ドット絵の自機(アプリの PaidShip と同じ)。値は、期間限定で売る自機の期間の名前。
 * 招待のごほうびの自機(inviteState の ships)は、ここには入れない
 */
export const PAID_SHIPS: Readonly<Record<string, string | undefined>> = { sleigh_xmas: "xmas", reindeer_xmas: "xmas", snowflake_xmas: "xmas" };

/** その自機が、買って手に入れるものか */
export function isPaidShip(id: string): boolean { return Object.prototype.hasOwnProperty.call(PAID_SHIPS, id); }

/** 買った商品の ID の一覧から、その自機を持っているか(単品・その期間の全部入り・永久買い切りパック)。買う自機でなければ false */
export function ownsShipByPurchase(id: string, purchased: ReadonlySet<string>): boolean {
  if (!isPaidShip(id)) return false;
  if (purchased.has(`${PRODUCT_PREFIX}ship.${id}`) || purchased.has(`${PRODUCT_PREFIX}lifetime`)) return true;
  const season = PAID_SHIPS[id];
  return season !== undefined && purchased.has(`${PRODUCT_PREFIX}pack.${season}`);
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
