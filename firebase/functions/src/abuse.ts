import { createHash } from "node:crypto";
import { jstDay } from "./quota.js";
import { isValidShortId, normalizeShortId } from "./shortId.js";

/**
 * いたずら・水増しを防ぐための、計算だけの部品(Firestore に触らないので、単体テストで確かめられる)。
 */

// ---- 遊んだ回数の送信(submitResults) ----

/** 1 回の送信で、1 つのステージに数える遊んだ回数の上限 */
export const RESULT_PLAYS_PER_CALL = 3;
/** 1 人が 1 日(日本時間)に、1 つのステージに数えてもらえる遊んだ回数の上限 */
export const RESULT_PLAYS_PER_DAY = 10;
/** 1 人が 1 日に数えてもらえるステージの数の上限(記録の文書が大きくなりすぎないように) */
export const RESULT_STAGES_PER_DAY = 300;
/** 送信の間隔(これより早い送信は断る。アプリは送れなかった分を取っておき、次の機会に送り直す) */
export const RESULT_INTERVAL_MS = 5_000;

export interface ResultAdd { plays: number; clears: number }
export type ParsedResults = { ok: true; merged: Map<string, ResultAdd> } | { ok: false; error: "results" | "result-entry" | "result-range" };

/**
 * アプリから届いた結果の一覧を確かめて、ステージごとにまとめる。形は今までどおり(1通30件・1件100回まで)受け付けるが、
 * 数えるのは 1 ステージにつき RESULT_PLAYS_PER_CALL 回まで(クリアは、数えた回数まで)
 */
export function parseResults(results: unknown): ParsedResults {
  if (!Array.isArray(results) || results.length < 1 || results.length > 30) return { ok: false, error: "results" };
  const merged = new Map<string, ResultAdd>();
  for (const r of results) {
    const id = normalizeShortId(String((r as { stageId?: unknown })?.stageId ?? ""));
    const plays = (r as { plays?: unknown })?.plays, clears = (r as { clears?: unknown })?.clears;
    if (!isValidShortId(id) || !Number.isInteger(plays) || !Number.isInteger(clears)) return { ok: false, error: "result-entry" };
    const p = plays as number, c = clears as number;
    if (p < 0 || p > 100 || c < 0 || c > p) return { ok: false, error: "result-range" };
    const cur = merged.get(id) ?? { plays: 0, clears: 0 };
    merged.set(id, { plays: cur.plays + p, clears: cur.clears + c });
  }
  for (const [id, a] of merged) {
    const plays = Math.min(a.plays, RESULT_PLAYS_PER_CALL);
    merged.set(id, { plays, clears: Math.min(a.clears, plays) });
  }
  return { ok: true, merged };
}

/** その日のステージごとの数えた回数(resultMeta/{uid} に保存する) */
export interface DailyResults { day: number; counts: Record<string, number> }

export function readDaily(raw: { day?: unknown; counts?: unknown } | undefined, now: number): DailyResults {
  const today = jstDay(now);
  if (!raw || raw.day !== today || typeof raw.counts !== "object" || raw.counts === null) return { day: today, counts: {} };
  return { day: today, counts: { ...(raw.counts as Record<string, number>) } };
}

/**
 * 1 日の上限に合わせて、数える回数を削る。返すのは、削ったあとの回数と、更新後のその日の記録。
 * 回数が 0 になったステージは、結果から外す
 */
export function applyDailyCap(merged: Map<string, ResultAdd>, daily: DailyResults): { allowed: Map<string, ResultAdd>; daily: DailyResults } {
  const counts = { ...daily.counts };
  const allowed = new Map<string, ResultAdd>();
  for (const [id, a] of merged) {
    const used = typeof counts[id] === "number" ? counts[id]! : 0;
    if (used === 0 && Object.keys(counts).length >= RESULT_STAGES_PER_DAY) continue;
    const plays = Math.max(0, Math.min(a.plays, RESULT_PLAYS_PER_DAY - used));
    const clears = Math.min(a.clears, plays);
    if (plays === 0 && clears === 0) continue;
    counts[id] = used + plays;
    allowed.set(id, { plays, clears });
  }
  return { allowed, daily: { day: daily.day, counts } };
}

// ---- 世界への公開(publishStage) ----

/** 「URLを知っている人だけ」の投稿を、1 日(日本時間)に出せる数 */
export const UNLISTED_DAILY_POSTS = 20;

export function unlistedUsedToday(user: { get(f: string): unknown }, now: number): number {
  const n = user.get("unlistedToday");
  return user.get("unlistedDay") === jstDay(now) && typeof n === "number" ? n : 0;
}

/** 新しく公開したステージに付ける「急上昇」の初めの点数(2 日で半分になる。遊ばれ方しだいで、上にも下にも動く) */
export const NEW_STAGE_TREND = 8;
/** 初めの点数を付けるのは、1 人 1 日(日本時間)に公開した最初のこの本数まで(たくさん出して急上昇を埋めるのを防ぐ) */
export const NEW_STAGE_TREND_PER_DAY = 3;

/** 新しいステージの急上昇の初めの点数。listedBefore: その日、この投稿の前に公開した本数(「URLを知っている人だけ」は数えない) */
export const initialTrend = (listedBefore: number, unlisted: boolean): number =>
  !unlisted && listedBefore < NEW_STAGE_TREND_PER_DAY ? NEW_STAGE_TREND : 0;

/** 通報で非表示になったステージを作者が消したとき、目印を残しておく数(stageTombs/{uid}.hashes。新しいものから) */
export const MAX_TOMBS = 200;

/** 目印の一覧に足す(同じものは足さない。多すぎたら古いものから捨てる) */
export function addTomb(list: unknown, hash: string): string[] {
  const cur = Array.isArray(list) ? list.filter((h): h is string => typeof h === "string" && h !== hash) : [];
  return [hash, ...cur].slice(0, MAX_TOMBS);
}

/**
 * 同じ作者の、遊ぶ中身の同じステージ(statuses: 見つかったものの status)があるとき、出し直しを断るか。
 * 公開(一覧に載る)なら、「URLを知っている人だけ」のものしか無ければ通す(限定公開で試してから公開に出す流れ)。
 * 公開中・非表示・消した非表示のもの(tombstoned)と同じなら断る。「URLを知っている人だけ」の出し直しは、同じものがあれば断る
 */
export function isDuplicatePost(statuses: unknown[], tombstoned: boolean, unlisted: boolean): boolean {
  if (tombstoned) return true;
  if (unlisted) return statuses.length > 0;
  return statuses.some((s) => s !== "unlisted");
}

/**
 * 遊び方に関わらない項目(名前・説明・見た目・音・演出)。同じステージの出し直しを見分けるとき、比べない。
 * ボスの見た目(bossLook)は比べる: キャラクターのボス(5 以上)は、当たり判定や位置が変わるため(場面ごとの bossLook も同じ)。
 * bossSize・bossX・bossY も比べる(ここに入れない)
 */
const COSMETIC_KEYS = new Set([
  "name", "authorName", "desc", "phaseInfo", "themeBullets", "themeBackground", "themeShip", "bgm", "rewardFx",
  "previewStart", "noPreview", "shipSkin", "mookLook", "bossWarning", "bossDefeat", "hideMarkers", "formatVersion", "needs",
]);

function canonical(v: unknown): unknown {
  if (Array.isArray(v)) return v.map(canonical);
  if (v && typeof v === "object") {
    const o: Record<string, unknown> = {};
    for (const k of Object.keys(v).sort()) if (!COSMETIC_KEYS.has(k) && (v as Record<string, unknown>)[k] !== undefined) o[k] = canonical((v as Record<string, unknown>)[k]);
    return o;
  }
  return v;
}

/** 遊ぶ中身(モード・長さ・ライフ・発射台・場面など)から作る目印。名前や見た目だけを変えた出し直しは、同じ値になる */
export function contentHash(stage: object): string {
  return createHash("sha256").update(JSON.stringify(canonical(stage))).digest("hex").slice(0, 32);
}

// ---- 通報 ----

/** ふつうは 5 人の通報で自動で非表示。始めたばかり(7 日以内)のアカウントのステージは 2 人で非表示 */
export const HIDE_REPORT_THRESHOLD = 5;
export const NEW_AUTHOR_HIDE_THRESHOLD = 2;
export const NEW_AUTHOR_MS = 7 * 24 * 3600_000;

export function reportThreshold(authorSinceMs: number | null, now: number): number {
  return authorSinceMs !== null && now - authorSinceMs < NEW_AUTHOR_MS ? NEW_AUTHOR_HIDE_THRESHOLD : HIDE_REPORT_THRESHOLD;
}

// ---- 弾幕バトル ----

/** 同じ二人の対戦で、1 日(日本時間)にレートが動くのは最初のこの回数まで(2 つのアカウントでの水増しを防ぐ) */
export const PAIR_RATED_PER_DAY = 3;

export const pairKey = (a: string, b: string, now: number): string => `${[a, b].sort().join("_")}_${jstDay(now)}`;
