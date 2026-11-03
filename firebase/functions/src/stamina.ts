/** スワイプ弾幕のスタミナ(仕様書 7 章)。最大 5、2 時間で 1 回復、1 プレイで 1 消費。広告で全回復は 1 日 1 回(日本時間)。「回復ドリンク」で全回復 */
export const STAMINA_MAX = 5;
export const REGEN_MS = 2 * 60 * 60 * 1000;

export interface StaminaState { v: number; at: number }

/** いまのスタミナ(回復を反映)と、次の 1 回復までの時刻 */
export function current(s: StaminaState | undefined, now: number): { value: number; nextAt: number | null } {
  if (!s) return { value: STAMINA_MAX, nextAt: null };
  const gained = Math.max(0, Math.floor((now - s.at) / REGEN_MS));
  const value = Math.min(STAMINA_MAX, s.v + gained);
  return { value, nextAt: value >= STAMINA_MAX ? null : s.at + (gained + 1) * REGEN_MS };
}

/** 1 消費した後の保存用の値。足りなければ null */
export function spend(s: StaminaState | undefined, now: number): StaminaState | null {
  const cur = current(s, now);
  if (cur.value < 1) return null;
  const full = cur.value >= STAMINA_MAX;
  const gained = s ? Math.max(0, Math.floor((now - s.at) / REGEN_MS)) : 0;
  return { v: cur.value - 1, at: full || !s ? now : s.at + gained * REGEN_MS };
}

export const refill = (now: number): StaminaState => ({ v: STAMINA_MAX, at: now });

/** 日本時間の日付(広告回復の 1 日 1 回に使う) */
export const dayKeyJst = (now: number): string => new Date(now + 9 * 3600_000).toISOString().slice(0, 10);

export const hasPass = (pass: { until?: number } | undefined, now: number): boolean => (pass?.until ?? 0) > now;
