/**
 * 称号の定義と、期間(日本時間の毎月 1 日 0:00 区切り)・順位の計算。外に出さない純粋な関数だけ(テストしやすいように)。
 *
 * 称号の種類
 * - スコア達成(score1〜4): 1回のプレイでしきい値以上を出したら、永久にもらえる
 * - 月間(rank1/rank2/rank3/top10/pct1/pct10/pct50): 月の終わりにサーバーが順位から付与する。「<種類>:<年月>」の形で、一度もらったら永久に残る
 *   (王冠・メダル・名前の色だけは、次の月の 1 日 0:00 まで)
 */

export const SCORE_TITLES: { id: string; min: bigint }[] = [
  { id: "score1", min: 10n ** 8n },    // 弾幕初心者: 1億点
  { id: "score2", min: 10n ** 12n },   // 弾幕職人: 1兆点
  { id: "score3", min: 10n ** 18n },   // 弾幕マスター: 100京点
  { id: "score4", min: 10n ** 28n },   // 弾幕の神: 1穣点
];

/** 月間の称号の種類 */
export const MONTHLY_KINDS = ["rank1", "rank2", "rank3", "top10", "pct1", "pct10", "pct50"] as const;
export type MonthlyKind = (typeof MONTHLY_KINDS)[number];

/** 月間の称号の ID(「<種類>:<年月>」。例 rank1:2026-11) */
export const monthlyTitleId = (kind: MonthlyKind, month: string) => `${kind}:${month}`;

/** ID が、いま定義されている称号か(スコア達成、または「種類:週」の形の週間) */
export function isTitleId(id: unknown): id is string {
  if (typeof id !== "string") return false;
  if (SCORE_TITLES.some((t) => t.id === id)) return true;
  const m = /^([a-z0-9]+):(\d{4})-(0[1-9]|1[0-2])$/.exec(id);
  return !!m && (MONTHLY_KINDS as readonly string[]).includes(m[1]!);
}

/** この点数で取れるスコア達成の称号(低い順) */
export function scoreTitlesFor(score: bigint): string[] {
  return SCORE_TITLES.filter((t) => score >= t.min).map((t) => t.id);
}

/** 日本時間の年月を、期間 ID にする。例 "2026-11"(毎月 1 日 0:00 日本時間に切り替わる) */
export function monthIdJst(ms: number): string {
  const d = new Date(ms + 9 * 3600_000);   // 日本時間の暦を、UTC のフィールドで読む
  return `${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, "0")}`;
}

/** 期間 ID から、その月の 1 日 0:00(日本時間)の時刻(ミリ秒) */
export function monthStartMs(month: string): number {
  const m = /^(\d{4})-(\d{2})$/.exec(month);
  if (!m || Number(m[2]) < 1 || Number(m[2]) > 12) throw new Error("bad month");
  return Date.UTC(Number(m[1]), Number(m[2]) - 1, 1) - 9 * 3600_000;
}

/** 前の月の ID */
export const previousMonthId = (month: string): string => monthIdJst(monthStartMs(month) - 3600_000);
/** 次の月が始まる時刻(いまの月の終わり) */
export const monthEndMs = (month: string): number => { const [y, mo] = month.split("-").map(Number) as [number, number]; return Date.UTC(mo === 12 ? y + 1 : y, mo === 12 ? 0 : mo, 1) - 9 * 3600_000; };

export interface MonthlyAward {
  kinds: MonthlyKind[];
  /** 王冠(1=金 2=銀 3=銅。なし=0) */
  crown: 0 | 1 | 2 | 3;
  /** 4〜10 位の小さなメダル */
  medal: boolean;
}

/** 参加者 total 人のうち rank 位(同点は同じ順位)がもらうもの。上位 1%・10%・50% は、一番高い段階を1つ */
export function awardsFor(rank: number, total: number): MonthlyAward {
  const kinds: MonthlyKind[] = [];
  let crown: 0 | 1 | 2 | 3 = 0;
  let medal = false;
  if (rank === 1) { kinds.push("rank1"); crown = 1; }
  else if (rank === 2) { kinds.push("rank2"); crown = 2; }
  else if (rank === 3) { kinds.push("rank3"); crown = 3; }
  else if (rank <= 10) { kinds.push("top10"); medal = true; }
  for (const [p, kind] of [[1, "pct1"], [10, "pct10"], [50, "pct50"]] as const) {
    if (rank <= Math.ceil((total * p) / 100)) { kinds.push(kind); break; }
  }
  return { kinds, crown, medal };
}

/** 並べた並び(点数の高い順)の「キー」から、同点を同じ順位にした順位の配列を作る */
export function competitionRanks(keys: string[]): number[] {
  const ranks: number[] = [];
  keys.forEach((k, i) => ranks.push(i > 0 && keys[i - 1] === k ? ranks[i - 1]! : i + 1));
  return ranks;
}
