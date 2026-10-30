/**
 * 弾幕作成モードで描いた軌道。発射位置を原点にした (x, y) を、PATH_STEP 秒ごとに並べた [x0, y0, x1, y1, ...]。
 * アプリ(DanmakuCore/CustomPath.swift)と同じ規則。
 */
export const PATH_STEP = 0.1;
export const PATH_MIN_POINTS = 2;
export const PATH_MAX_POINTS = 60;
export const PATH_LIMIT = 600;

/** 0.1 刻みの丸め。0.5 のときは 0 から遠いほうへ(アプリと同じ規則) */
export const round1 = (v: number) => (Math.sign(v) || 1) * (Math.round(Math.abs(v) * 10) / 10);

/** 軌道の検証。形が不正・範囲外なら null(アプリは必ず先に整えてから送る)。0.1 刻みに丸めて返す */
export function validatePath(raw: unknown): number[] | null {
  if (!Array.isArray(raw) || raw.length % 2 !== 0) return null;
  const points = raw.length / 2;
  if (points < PATH_MIN_POINTS || points > PATH_MAX_POINTS) return null;
  const out: number[] = [];
  for (const v of raw) {
    if (typeof v !== "number" || !Number.isFinite(v) || Math.abs(v) > PATH_LIMIT) return null;
    out.push(round1(v) + 0);   // -0 を 0 にする
  }
  return out;
}

/** 時刻 time(秒)の位置。最後の点を過ぎたら、最後の速さのまま進み続ける */
export function pathPosition(p: readonly number[], time: number): { x: number; y: number } {
  const n = p.length / 2;
  if (n < 1) return { x: 0, y: 0 };
  if (n === 1 || time <= 0) return { x: p[0]!, y: p[1]! };
  const f = time / PATH_STEP;
  if (f >= n - 1) {
    const extra = time - (n - 1) * PATH_STEP;
    const vx = (p[2 * n - 2]! - p[2 * n - 4]!) / PATH_STEP, vy = (p[2 * n - 1]! - p[2 * n - 3]!) / PATH_STEP;
    return { x: p[2 * n - 2]! + vx * extra, y: p[2 * n - 1]! + vy * extra };
  }
  const i = Math.trunc(f);
  const u = f - i;
  return { x: p[2 * i]! + (p[2 * i + 2]! - p[2 * i]!) * u, y: p[2 * i + 1]! + (p[2 * i + 3]! - p[2 * i + 1]!) * u };
}
